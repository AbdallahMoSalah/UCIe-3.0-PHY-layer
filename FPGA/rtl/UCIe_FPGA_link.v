`timescale 1ns/1ps
// =============================================================================
// Module  : UCIe_FPGA_link
// Project : UCIe 3.0 PHY - FPGA bring-up (NO ANALOG, NOT LOOPED BACK)
//
// Purpose : Non-loopback sibling of UCIe_FPGA_loopback.  Same core wrapper
//           duties - re-create the MainBand word-clock gate that the stripped
//           analog hard macro used to provide - but the MainBand/SideBand
//           parallel boundary is EXPOSED on ports (digital_ucie_link) instead
//           of folded (digital_ucie_loopback).
//
//           Cross-wire two instances to form a die-to-die link:
//             dieA.o_mb_tx_*  <-> dieB.i_mb_rx_*
//             dieB.o_mb_tx_*  <-> dieA.i_mb_rx_*
//             dieA.o_sb_tx_*  <-> dieB.i_sb_rx_*
//             dieB.o_sb_tx_*  <-> dieA.i_sb_rx_*
//             i_sb_tx_rdy = 1'b1 on both (lossless parallel channel).
//
//  Clocks  : runs synchronously with lclk (no PLL); pll_clk = lclk.
// =============================================================================
module UCIe_FPGA_link #(
    parameter      DATA_WIDTH_MB  = 32,
    parameter      DATA_WIDTH_SB  = 64,
    parameter      NUM_LANES      = 16,
    parameter      N_BYTES        = 64,
    parameter      GAP_WIDTH      = 32,
    parameter      [DATA_WIDTH_MB-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS  = 0.5,
    parameter      RX_ALIGN_DELAY = 2,
    parameter      CLK_FRQ_HZ     = 800_000_000,
    parameter [2:0] MAX_LINK_WIDTH_CAP  = 3'd0,
    parameter [3:0] MAX_LINK_SPEED_CAP  = 4'h5,
    parameter       SPMW_CAP            = 1'b0,
    parameter       PMO_CAP             = 1'b1,
    parameter       PSPT_CAP            = 1'b0,
    parameter       L2SPD_CAP           = 1'b0,
    parameter [4:0] SUPPORTEDVSWING_CAP = 5'h01,
    parameter [1:0] CLK_MODE_CAP        = 2'b10,
    parameter [1:0] CLK_PHASE_CAP       = 2'b00,
    parameter       TARR_CAP            = 1'b0,
    parameter       ADVANCED_PKG_CAP    = 1'b0,
    parameter [1:0] MODULE_ID           = 2'b0
)(
    input  wire                             rst_n,

    // ---- Clocks (no PLL; from MMCM/clock-enables on FPGA) ----
    input  wire                             lclk,
    input  wire                             gated_lclk,
    input  wire                             clk_sb,

    // ---- MainBand flit data (adapter face) ----
    input  wire [8*N_BYTES-1:0]             lp_data,
    input  wire                             lp_irdy,
    input  wire                             lp_valid,
    output wire                             pl_trdy,
    output wire                             pl_error,
    output wire [8*N_BYTES-1:0]             pl_data,
    output wire                             pl_valid,

    // ---- Register access / config over sideband ----
    input  wire [31:0]                      lp_cfg,
    input  wire                             lp_cfg_vld,
    output wire                             pl_cfg_crd,
    input  wire                             lp_cfg_crd,
    output wire [31:0]                      pl_cfg,
    output wire                             pl_cfg_vld,

    // ---- RDI adapter-facing interface ----
    input  wire [3:0]                       lp_state_req,
    input  wire                             lp_clk_ack,
    input  wire                             lp_wake_req,
    input  wire                             lp_stallack,
    input  wire                             lp_linkerror,

    output wire                             pl_clk_req,
    output wire                             pl_stallreq,
    output wire                             pl_wake_ack,
    output wire                             pl_trainerror,
    output wire                             pl_inband_pres,
    output wire                             pl_phyinrecenter,
    output wire [3:0]                       pl_state_sts,
    output wire                             pl_max_speedmode,
    output wire [2:0]                       pl_speedmode,
    output wire [2:0]                       pl_lnk_cfg,

    // ---- Exposed MainBand parallel boundary (die-to-die) ----
    output wire                             o_mb_tx_ser_en,
    output wire [NUM_LANES*DATA_WIDTH_MB-1:0] o_mb_tx_lane,
    output wire                             o_mb_tx_valid_ser_en,
    output wire [DATA_WIDTH_MB-1:0]         o_mb_tx_valid_word,
    output wire                             o_mb_tx_ckp,
    output wire                             o_mb_tx_ckn,
    output wire                             o_mb_tx_trk,
    input  wire                             i_mb_rx_data_valid,
    input  wire [NUM_LANES*DATA_WIDTH_MB-1:0] i_mb_rx_lane,
    input  wire                             i_mb_rx_valid_frame_vld,
    input  wire [DATA_WIDTH_MB-1:0]         i_mb_rx_valid_frame_data,
    input  wire                             i_mb_rx_ckp,
    input  wire                             i_mb_rx_ckn,
    input  wire                             i_mb_rx_trk,

    // ---- Exposed SideBand parallel boundary (die-to-die) ----
    output wire [63:0]                      o_sb_tx_data,
    output wire                             o_sb_tx_vld,
    input  wire                             i_sb_tx_rdy,
    input  wire [63:0]                      i_sb_rx_data,
    input  wire                             i_sb_rx_vld
);

    // =========================================================================
    // MainBand word-clock gating  (lives here, at the FPGA core wrapper)
    //   The stripped analog hard macro produced gated_lclk by gating lclk with
    //   the core's enable o_mb_lclk_g (== rdi_lclk_g from the MainSM, on the
    //   ungated lclk domain). We re-create that gate here:
    //
    //     `ifdef FPGA : unit_clk_gate -> BUFGCE (global, glitch-free). gated_lclk
    //                   is produced on-chip; the gated_lclk INPUT port is ignored.
    //     else        : pass the external gated_lclk through (simulation / ASIC).
    // =========================================================================
    wire mb_lclk_g;          // clock-gate enable out of the digital core
    wire gated_lclk_use;     // word clock actually fed to the core

`ifdef FPGA
    unit_clk_gate u_mb_clk_gate (
        .CLK_EN   (mb_lclk_g),
        .CLK      (lclk),
        .GATED_CLK(gated_lclk_use)
    );
`else
    assign gated_lclk_use = gated_lclk;
`endif

    digital_ucie_link #(
        .DATA_WIDTH_MB  (DATA_WIDTH_MB),
        .DATA_WIDTH_SB  (DATA_WIDTH_SB),
        .NUM_LANES      (NUM_LANES),
        .N_BYTES        (N_BYTES),
        .GAP_WIDTH      (GAP_WIDTH),
        .VALID_PATTERN  (VALID_PATTERN),
        .PLL_PERIOD_NS  (PLL_PERIOD_NS),
        .RX_ALIGN_DELAY (RX_ALIGN_DELAY),
        .CLK_FRQ_HZ     (CLK_FRQ_HZ),
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
    ) digital_ucie_link_inst (
        .rst_n                                (rst_n),

        // ---- Clocks (no PLL) ----
        .lclk                                 (lclk),
        .gated_lclk                           (gated_lclk_use),
        .pll_clk                              (lclk),
        .clk_sb                               (clk_sb),

        // ---- MainBand flit data (adapter face) ----
        .lp_data                              (lp_data),
        .lp_irdy                              (lp_irdy),
        .lp_valid                             (lp_valid),
        .pl_trdy                              (pl_trdy),
        .pl_error                             (pl_error),
        .pl_data                              (pl_data),
        .pl_valid                             (pl_valid),

        // ---- Register access / config over sideband ----
        .lp_cfg                               (lp_cfg),
        .lp_cfg_vld                           (lp_cfg_vld),
        .pl_cfg_crd                           (pl_cfg_crd),
        .lp_cfg_crd                           (lp_cfg_crd),
        .pl_cfg                               (pl_cfg),
        .pl_cfg_vld                           (pl_cfg_vld),

        // ---- RDI adapter-facing interface ----
        .lp_state_req                         (lp_state_req),
        .lp_clk_ack                           (lp_clk_ack),
        .lp_wake_req                          (lp_wake_req),
        .lp_stallack                          (lp_stallack),
        .lp_linkerror                         (lp_linkerror),

        .pl_clk_req                           (pl_clk_req),
        .pl_stallreq                          (pl_stallreq),
        .pl_wake_ack                          (pl_wake_ack),
        .pl_trainerror                        (pl_trainerror),
        .pl_inband_pres                       (pl_inband_pres),
        .pl_phyinrecenter                     (pl_phyinrecenter),
        .pl_state_sts                         (pl_state_sts),
        .pl_max_speedmode                     (pl_max_speedmode),
        .pl_speedmode                         (pl_speedmode),
        .pl_lnk_cfg                           (pl_lnk_cfg),

        // ---- Exposed MainBand parallel boundary ----
        .o_mb_tx_ser_en                       (o_mb_tx_ser_en),
        .o_mb_tx_lane                         (o_mb_tx_lane),
        .o_mb_tx_valid_ser_en                 (o_mb_tx_valid_ser_en),
        .o_mb_tx_valid_word                   (o_mb_tx_valid_word),
        .o_mb_tx_ckp                          (o_mb_tx_ckp),
        .o_mb_tx_ckn                          (o_mb_tx_ckn),
        .o_mb_tx_trk                          (o_mb_tx_trk),
        .i_mb_rx_data_valid                   (i_mb_rx_data_valid),
        .i_mb_rx_lane                         (i_mb_rx_lane),
        .i_mb_rx_valid_frame_vld              (i_mb_rx_valid_frame_vld),
        .i_mb_rx_valid_frame_data             (i_mb_rx_valid_frame_data),
        .i_mb_rx_ckp                          (i_mb_rx_ckp),
        .i_mb_rx_ckn                          (i_mb_rx_ckn),
        .i_mb_rx_trk                          (i_mb_rx_trk),

        // ---- Exposed SideBand parallel boundary ----
        .o_sb_tx_data                         (o_sb_tx_data),
        .o_sb_tx_vld                          (o_sb_tx_vld),
        .i_sb_tx_rdy                          (i_sb_tx_rdy),
        .i_sb_rx_data                         (i_sb_rx_data),
        .i_sb_rx_vld                          (i_sb_rx_vld),

        // ---- MainBand clock-gate enable (drives the top-level clock gate) ----
        .o_mb_lclk_g                          (mb_lclk_g)
    );
endmodule
