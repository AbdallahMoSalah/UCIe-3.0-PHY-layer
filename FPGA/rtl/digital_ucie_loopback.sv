`timescale 1ns/1ps
// =============================================================================
// Module  : digital_ucie_loopback
// Project : UCIe 3.0 PHY - FPGA bring-up (NO ANALOG)
//
// Purpose : Self-loopback of digital_ucie ALONE - the analog hard macro
//           (PLL, SerDes, tri-state, #delay sample clock) is removed.
//           The MainBand parallel boundary is folded back on itself:
//
//             TX (tx_reversal out)          -> RX (lfsr_rx in)
//               o_mb_lfsr_lane[]            -> i_mb_par_data[]
//               o_mb_lfsr_ser_en           -> i_mb_data_valid
//               o_mb_valid_word            -> i_mb_valid_frame_data
//               o_mb_valid_ser_en          -> i_mb_valid_frame_vld
//               o_mb_tckp/tckn/ttrk_p_pre  -> i_RCKP_P / i_RCKN_P / i_RTRK_P
//
//           Sideband parallel boundary folded back:
//               o_sb_ser_data_send         -> i_sb_des_data_rcvd
//               o_sb_ser_vld_send          -> i_sb_des_vld_rcvd
//               i_sb_ser_rdy               = 1 (channel always ready)
//
//  Clocks  : supplied as inputs (no PLL).  On FPGA these come from one MMCM /
//            clock-enable tree; in simulation the testbench drives them.
//              gated_lclk / lclk : MainBand word clock (= analog pll/16)
//              pll_clk           : fast clock for clk-pattern gen/detector
//              clk_sb            : Sideband parallel clock (= analog sb_pll/8)
//
//  NOTE   : This is the parallel-boundary loopback with NO SerDes.  Because the
//           TX/RX run in the SAME word-clock domain there is no serialize/
//           deserialize latency, so the descrambler in lfsr_rx stays lock-step
//           with lfsr_tx word-for-word.
// =============================================================================

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

module digital_ucie_loopback #(
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

    // ---- Clocks (no PLL; from MMCM/clock-enables on FPGA) ----
    input  logic                             lclk,
    input  logic                             gated_lclk,
    input  logic                             pll_clk,
    input  logic                             clk_sb,

    // ---- MainBand flit data (adapter face) ----
    input  logic [8*N_BYTES-1:0]             lp_data,
    input  logic                             lp_irdy,
    input  logic                             lp_valid,
    output logic                             pl_trdy,
    output logic                             pl_error,
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
    input  logic [3:0]                       lp_state_req,
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
    output logic [3:0]                       pl_state_sts,
    output logic                             pl_max_speedmode,
    output logic [2:0]                       pl_speedmode,
    output logic [2:0]                       pl_lnk_cfg
);

    // =========================================================================
    // Loopback nets (digital_ucie TX boundary -> own RX boundary)
    // =========================================================================
    logic [DATA_WIDTH_MB-1:0] mb_lane   [0:NUM_LANES-1];  // tx_reversal out -> lfsr_rx in
    logic                     mb_ser_en;                  // data ser_en  -> data_valid
    logic [DATA_WIDTH_MB-1:0] mb_vword;                   // valid word   -> valid_frame_data
    logic                     mb_vser_en;                 // valid ser_en -> valid_frame_vld
    logic                     mb_tckp, mb_tckn, mb_ttrk;  // clk-pattern -> forwarded RX clk

    logic [63:0]              sb_data;                    // SB ser data -> SB des data
    logic                     sb_vld;                     // SB ser vld  -> SB des vld
    RDI_state                 lp_state_req_int, pl_state_sts_int;
    assign lp_state_req_int = RDI_state'(lp_state_req);  // input  : 4-bit -> enum (into DUT)
    assign pl_state_sts     = pl_state_sts_int;          // output : enum (from DUT) -> 4-bit
    // =========================================================================
    // The digital PHY under self-loopback
    // =========================================================================
    digital_ucie #(
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
    ) u_digital_ucie (
        .rst_n                  (rst_n),

        // Clocks
        .lclk                   (lclk),
        .gated_lclk             (gated_lclk),
        .pll_clk                (pll_clk),
        .clk_sb                 (clk_sb),

        // MainBand control & data
        .lp_data                (lp_data),
        .lp_irdy                (lp_irdy),
        .lp_valid               (lp_valid),
        .pl_trdy                (pl_trdy),
        .pl_error               (pl_error),
        .pl_data                (pl_data),
        .pl_valid               (pl_valid),

        // ---- MainBand TX boundary -> looped into RX boundary ----
        .o_mb_lfsr_ser_en       (mb_ser_en),
        .o_mb_lfsr_lane         (mb_lane),
        .o_mb_valid_ser_en      (mb_vser_en),
        .o_mb_valid_word        (mb_vword),
        .o_mb_tckp_p_pre        (mb_tckp),
        .o_mb_tckn_p_pre        (mb_tckn),
        .o_mb_ttrk_p_pre        (mb_ttrk),
        // analog-only controls left open (no hard macro)
        .o_mb_pll_speed_sel     (),
        .o_mb_lclk_g            (),
        .o_mb_tx_data_lane_sel  (),
        .o_mb_tx_val_lane_sel   (),
        .o_mb_tx_clk_lane_sel   (),
        .o_mb_tx_trk_lane_sel   (),
        .o_mb_rx_data_deser_en  (),
        .o_mb_rx_valid_deser_en (),
        .o_mb_vcmp_enable       (),
        .o_mb_vcmp_done         (),

        // ---- RX recovered parallel words : driven by the loopback ----
        .i_mb_par_data          (mb_lane),       // tx_reversal out -> lfsr_rx in
        .i_mb_data_valid        (mb_ser_en),     // data ser_en      -> word valid
        .i_mb_valid_frame_data  (mb_vword),      // valid word       -> frame data
        .i_mb_valid_frame_vld   (mb_vser_en),    // valid ser_en     -> frame strobe

        // ---- Raw forwarded RX clock/track : looped from clk-pattern gen ----
        .i_RCKP_P               (mb_tckp),
        .i_RCKN_P               (mb_tckn),
        .i_RTRK_P               (mb_ttrk),

        // ---- Sideband parallel boundary : looped back ----
        .o_sb_pattern_mode      (),
        .o_sb_pmo_en            (),
        .o_sb_ser_data_send     (sb_data),
        .o_sb_ser_vld_send      (sb_vld),
        .i_sb_ser_rdy           (1'b1),          // channel always ready
        .i_sb_des_data_rcvd     (sb_data),
        .i_sb_des_vld_rcvd      (sb_vld),

        // ---- Adapter interface ----
        .lp_cfg                 (lp_cfg),
        .lp_cfg_vld             (lp_cfg_vld),
        .pl_cfg_crd             (pl_cfg_crd),
        .lp_cfg_crd             (lp_cfg_crd),
        .pl_cfg                 (pl_cfg),
        .pl_cfg_vld             (pl_cfg_vld),

        // ---- RDI adapter face ----
        .lp_state_req           (lp_state_req_int),
        .lp_clk_ack             (lp_clk_ack),
        .lp_wake_req            (lp_wake_req),
        .lp_stallack            (lp_stallack),
        .lp_linkerror           (lp_linkerror),
        .pl_clk_req             (pl_clk_req),
        .pl_stallreq            (pl_stallreq),
        .pl_wake_ack            (pl_wake_ack),
        .pl_trainerror          (pl_trainerror),
        .pl_inband_pres         (pl_inband_pres),
        .pl_phyinrecenter       (pl_phyinrecenter),
        .pl_state_sts           (pl_state_sts_int),
        .pl_max_speedmode       (pl_max_speedmode),
        .pl_speedmode           (pl_speedmode),
        .pl_lnk_cfg             (pl_lnk_cfg)
    );

endmodule
