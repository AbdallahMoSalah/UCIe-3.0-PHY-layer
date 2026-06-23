`timescale 1ns/1ps
// =============================================================================
// Module  : ucie_phy_loopback
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : Single-instance SELF-LOOPBACK of one UCIe_PHY_wrapper.
//
//           Instead of two dies wired back-to-back (which costs ~2x FPGA
//           resources), this wraps ONE PHY and folds its own TX lanes back
//           into its own RX lanes:
//
//                 o_TD_P  -> i_RD_P      (MainBand data)
//                 o_TVLD_P-> i_RVLD_P    (MainBand valid)
//                 o_TCKP_P-> i_RCKP_P    (forwarded clock +)
//                 o_TCKN_P-> i_RCKN_P    (forwarded clock -)
//                 o_TTRK_P-> i_RTRK_P    (clock track)
//                 TXCKSB  -> RXCKSB      (Sideband clock)
//                 TXDATASB-> RXDATASB    (Sideband data)
//
//           The whole adapter face (RDI + register-config-over-sideband +
//           MainBand flit data) is brought straight out so a processor/DMA
//           (via the AXI-Stream shell added on top of this) can drive it.
//
//  NOTE (FPGA target):
//    This step still contains the analog hard-macro (SerDes + behavioural PLL)
//    so the loopback is validated against the *proven* datapath/framing first.
//    The analog half is removed in the next step (FPGA clocking + parallel
//    boundary loopback, no SerDes).  Keeping it here isolates the question
//    "does a self-looped LTSM train?" from any new framing logic.
// =============================================================================

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

module ucie_phy_loopback #(
    parameter int  DATA_WIDTH_MB  = 32,
    parameter int  DATA_WIDTH_SB  = 64,
    parameter int  NUM_LANES      = 16,
    parameter int  N_BYTES        = 64,
    parameter int  GAP_WIDTH      = 32,
    parameter      [DATA_WIDTH_MB-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS  = 0.5,
    parameter int  RX_ALIGN_DELAY = 2,
    parameter int  CLK_FRQ_HZ     = 800_000_000,
    parameter logic [2:0] MAX_LINK_WIDTH_CAP  = 3'd0,
    parameter logic [3:0] MAX_LINK_SPEED_CAP  = 4'h5,
    parameter logic       SPMW_CAP            = 1'b0,
    parameter logic       PMO_CAP             = 1'b1,
    parameter logic       PSPT_CAP            = 1'b0,
    parameter logic       L2SPD_CAP           = 1'b0,
    parameter logic [4:0] SUPPORTEDVSWING_CAP = 5'h01,
    parameter logic [1:0] CLK_MODE_CAP        = 2'b10,
    parameter logic [1:0] CLK_PHASE_CAP       = 2'b00,
    parameter logic       TARR_CAP            = 1'b0,
    parameter logic       ADVANCED_PKG_CAP    = 1'b0,
    parameter logic [1:0] MODULE_ID           = 2'b0
)(
    input  logic                             rst_n,

    // ---- MainBand flit data (adapter face) ----
    input  logic [8*N_BYTES-1:0]             lp_data,
    input  logic                             lp_irdy,
    input  logic                             lp_valid,
    output logic                             pl_trdy,
    output logic                             pl_error,

    output logic                             lclk,
    output logic [8*N_BYTES-1:0]             pl_data,
    output logic                             pl_valid,

    // ---- Register access / config over sideband ----
    input  logic [31:0]                      lp_cfg,
    input  logic                             lp_cfg_vld,
    output logic                             pl_cfg_crd,
    input  logic                             lp_cfg_crd,
    output logic [31:0]                      pl_cfg,
    output logic                             pl_cfg_vld,

    // ---- RDI adapter-facing interface ----
    input  RDI_state                         lp_state_req,
    input  logic                             lp_clk_ack,
    input  logic                             lp_wake_req,
    input  logic                             lp_stallack,
    input  logic                             lp_linkerror,

    output logic                             pl_clk_req,
    output logic                             pl_stallreq,
    output logic                             pl_wake_ack,
    output logic                             pl_trainerror,
    output logic                             pl_inband_pres,
    output logic                             pl_phyinrecenter,
    output RDI_state                         pl_state_sts,
    output logic                             pl_max_speedmode,
    output logic [2:0]                       pl_speedmode,
    output logic [2:0]                       pl_lnk_cfg
);

    // =========================================================================
    // Internal loopback nets (TX -> own RX)
    // =========================================================================
    logic [NUM_LANES-1:0] mb_td;
    logic                 mb_tvld;
    logic                 mb_tckp;
    logic                 mb_tckn;
    logic                 mb_ttrk;
    logic                 sb_txck;
    logic                 sb_txdata;

    // =========================================================================
    // The PHY under loopback
    // =========================================================================
    UCIe_PHY_wrapper #(
        .DATA_WIDTH_MB       (DATA_WIDTH_MB),
        .DATA_WIDTH_SB       (DATA_WIDTH_SB),
        .NUM_LANES           (NUM_LANES),
        .N_BYTES             (N_BYTES),
        .GAP_WIDTH           (GAP_WIDTH),
        .VALID_PATTERN       (VALID_PATTERN),
        .PLL_PERIOD_NS       (PLL_PERIOD_NS),
        .RX_ALIGN_DELAY      (RX_ALIGN_DELAY),
        .CLK_FRQ_HZ          (CLK_FRQ_HZ),
        .MAX_LINK_WIDTH_CAP  (MAX_LINK_WIDTH_CAP),
        .MAX_LINK_SPEED_CAP  (MAX_LINK_SPEED_CAP),
        .SPMW_CAP            (SPMW_CAP),
        .PMO_CAP             (PMO_CAP),
        .PSPT_CAP            (PSPT_CAP),
        .L2SPD_CAP           (L2SPD_CAP),
        .SUPPORTEDVSWING_CAP (SUPPORTEDVSWING_CAP),
        .CLK_MODE_CAP        (CLK_MODE_CAP),
        .CLK_PHASE_CAP       (CLK_PHASE_CAP),
        .TARR_CAP            (TARR_CAP),
        .ADVANCED_PKG_CAP    (ADVANCED_PKG_CAP),
        .MODULE_ID           (MODULE_ID)
    ) u_phy (
        .rst_n        (rst_n),

        .lp_data      (lp_data),
        .lp_irdy      (lp_irdy),
        .lp_valid     (lp_valid),
        .pl_trdy      (pl_trdy),
        .pl_error     (pl_error),

        .lclk         (lclk),
        .pl_data      (pl_data),
        .pl_valid     (pl_valid),

        // ---- MainBand serial : looped TX -> own RX ----
        .o_TD_P       (mb_td),   .i_RD_P   (mb_td),
        .o_TVLD_P     (mb_tvld), .i_RVLD_P (mb_tvld),
        .o_TCKP_P     (mb_tckp), .i_RCKP_P (mb_tckp),
        .o_TCKN_P     (mb_tckn), .i_RCKN_P (mb_tckn),
        .o_TTRK_P     (mb_ttrk), .i_RTRK_P (mb_ttrk),

        // ---- Sideband serial : looped TX -> own RX ----
        .TXCKSB       (sb_txck),   .RXCKSB   (sb_txck),
        .TXDATASB     (sb_txdata), .RXDATASB (sb_txdata),

        // ---- Register config over sideband ----
        .lp_cfg       (lp_cfg),
        .lp_cfg_vld   (lp_cfg_vld),
        .pl_cfg_crd   (pl_cfg_crd),
        .lp_cfg_crd   (lp_cfg_crd),
        .pl_cfg       (pl_cfg),
        .pl_cfg_vld   (pl_cfg_vld),

        // ---- RDI adapter face ----
        .lp_state_req     (lp_state_req),
        .lp_clk_ack       (lp_clk_ack),
        .lp_wake_req      (lp_wake_req),
        .lp_stallack      (lp_stallack),
        .lp_linkerror     (lp_linkerror),
        .pl_clk_req       (pl_clk_req),
        .pl_stallreq      (pl_stallreq),
        .pl_wake_ack      (pl_wake_ack),
        .pl_trainerror    (pl_trainerror),
        .pl_inband_pres   (pl_inband_pres),
        .pl_phyinrecenter (pl_phyinrecenter),
        .pl_state_sts     (pl_state_sts),
        .pl_max_speedmode (pl_max_speedmode),
        .pl_speedmode     (pl_speedmode),
        .pl_lnk_cfg       (pl_lnk_cfg)
    );

endmodule
