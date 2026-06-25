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
module UCIe_FPGA_loopback #(
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
    output wire [2:0]                       pl_lnk_cfg
);

// =============================================================================
// MainBand word-clock gating  (lives here, at the FPGA top wrapper)
//   The stripped analog hard macro produced gated_lclk by gating lclk with the
//   core's enable o_mb_lclk_g (== rdi_lclk_g from the MainSM, on the ungated
//   lclk domain). We re-create that gate here:
//
//     `ifdef FPGA : unit_clk_gate -> BUFGCE (global, glitch-free). gated_lclk
//                   is produced on-chip; the gated_lclk INPUT port is ignored.
//     else        : pass the external gated_lclk through (simulation / ASIC).
// =============================================================================
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

digital_ucie_loopback #(
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
) digital_ucie_loopback_inst (
    .rst_n                                (rst_n),

    // ---- Clocks (no PLL; from MMCM/clock-enables on FPGA) ----
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

    // ---- MainBand clock-gate enable (drives the top-level clock gate) ----
    .o_mb_lclk_g                          (mb_lclk_g)
);
endmodule
