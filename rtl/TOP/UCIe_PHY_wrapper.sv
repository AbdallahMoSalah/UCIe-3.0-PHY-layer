`timescale 1ps/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// UCIe_PHY_wrapper
// -----------------------------------------------------------------------------
// Re-assembles the analog/digital split back into a single block that is
// functionally and pin-for-pin identical to UCIe_PHY:
//
//   UCIe_PHY_wrapper
//     |
//     +-- digital_ucie       (all digital: digital_mb + digital_sideband +
//     |                        MainSM + Reg_File)
//     +-- analog_hard_macro   (all analog : MB PLL/clocking/SerDes/tri-state +
//                              SB PLL/ClkDiv/ser-des)
//
// The two halves are wired together through the parallel/control boundary that
// each one exposes, and the external ports below are exactly the UCIe_PHY ports.
// So instantiating UCIe_PHY_wrapper is interchangeable with instantiating
// UCIe_PHY - the only difference is the internal hierarchy (digital and analog
// are now separated into two child blocks instead of being intermixed).
//
//  Boundary wiring (digital_ucie  <->  analog_hard_macro)
//  ------------------------------------------------------
//   Clocks   : the hard macro GENERATES lclk / gated_lclk / pll_clk /
//              pll_period (MainBand) and clk_sb (Sideband); these feed back
//              into digital_ucie as inputs.
//   MB TX    : digital_ucie.o_mb_*  -> hard macro serializer/tri-state inputs.
//   MB RX    : hard macro recovered parallel words -> digital_ucie.i_mb_*.
//   SB       : digital_ucie.o_sb_ser_* -> hard macro; hard macro des_* ->
//              digital_ucie.i_sb_des_*.
//   The raw forwarded MB RX clock/track pins (i_RCKP_P / i_RCKN_P / i_RTRK_P)
//   fan out to BOTH the hard macro (i_RCKP_P, for RX sampling) and digital_ucie
//   (all three, for the clock-pattern detector).
//  Simulation only.
// =============================================================================

module UCIe_PHY_wrapper #(
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
    // =========================================================================
    // System Reset
    // =========================================================================
    input  logic                             rst_n,

    // =========================================================================
    // MainBand Control & Data
    // =========================================================================
    input  logic [8*N_BYTES-1:0]             lp_data,
    input  logic                             lp_irdy,
    input  logic                             lp_valid,
    output logic                             pl_trdy,
    output logic                             pl_error,

    // Observability outputs
    output logic                             lclk,
    output logic [8*N_BYTES-1:0]             pl_data,
    output logic                             pl_valid,

    // =========================================================================
    // MainBand Serial Interface
    // =========================================================================
    input  logic [NUM_LANES-1:0]             i_RD_P,
    input  logic                             i_RVLD_P,
    input  logic                             i_RCKP_P,
    input  logic                             i_RCKN_P,
    input  logic                             i_RTRK_P,

    output logic [NUM_LANES-1:0]             o_TD_P,
    output logic                             o_TVLD_P,
    output logic                             o_TCKP_P,
    output logic                             o_TCKN_P,
    output logic                             o_TTRK_P,

    // =========================================================================
    // Sideband Serial Interface
    // =========================================================================
    input  logic                             RXCKSB,
    output logic                             TXCKSB,
    output logic                             TXDATASB,
    input  logic                             RXDATASB,

    // Adapter Interface (RDI Control / config over sideband)
    input  logic [31:0]                      lp_cfg,
    input  logic                             lp_cfg_vld,
    output logic                             pl_cfg_crd,
    input  logic                             lp_cfg_crd,
    output logic [31:0]                      pl_cfg,
    output logic                             pl_cfg_vld,

    // =========================================================================
    // RDI_SM Adapter-facing Interface
    // =========================================================================
    input  RDI_state                         lp_state_req,   // shared: RDI_SM + LTSM
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
    // Boundary nets between digital_ucie and analog_hard_macro
    // =========================================================================
    // ---- Clocks generated by the hard macro ----
    logic                    gated_lclk;
    logic                    pll_clk;
    real                     pll_period;
    logic                    clk_sb;

    // ---- MainBand TX : digital_ucie -> hard macro ----
    logic                    mb_lfsr_ser_en;
    logic [DATA_WIDTH_MB-1:0] mb_lfsr_lane [0:NUM_LANES-1];
    logic                    mb_valid_ser_en;
    logic [DATA_WIDTH_MB-1:0] mb_valid_word;
    logic                    mb_tckp_p_pre;
    logic                    mb_tckn_p_pre;
    logic                    mb_ttrk_p_pre;
    logic [2:0]              mb_pll_speed_sel;
    logic                    mb_lclk_g;
    logic [1:0]              mb_tx_data_lane_sel;
    logic [1:0]              mb_tx_val_lane_sel;
    logic [1:0]              mb_tx_clk_lane_sel;
    logic [1:0]              mb_tx_trk_lane_sel;
    logic [NUM_LANES-1:0]    mb_rx_data_deser_en;
    logic                    mb_rx_valid_deser_en;
    logic                    mb_vcmp_enable;
    logic                    mb_vcmp_done;

    // ---- MainBand RX : hard macro -> digital_ucie ----
    logic [DATA_WIDTH_MB-1:0] mb_par_data [0:NUM_LANES-1];
    logic                    mb_data_valid;
    logic [DATA_WIDTH_MB-1:0] mb_valid_frame_data;
    logic                    mb_valid_frame_vld;

    // ---- Sideband : SerDes parallel bus + serializer controls ----
    logic                    sb_pattern_mode;
    logic                    sb_pmo_en;
    logic [63:0]             sb_ser_data_send;
    logic                    sb_ser_vld_send;
    logic                    sb_ser_rdy;
    logic [63:0]             sb_des_data_rcvd;
    logic                    sb_des_vld_rcvd;

    // =========================================================================
    // 1. Digital half (all digital blocks)
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

        // Clocks from the hard macro
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

        // MainBand TX -> hard macro
        .o_mb_lfsr_ser_en       (mb_lfsr_ser_en),
        .o_mb_lfsr_lane         (mb_lfsr_lane),
        .o_mb_valid_ser_en      (mb_valid_ser_en),
        .o_mb_valid_word        (mb_valid_word),
        .o_mb_tckp_p_pre        (mb_tckp_p_pre),
        .o_mb_tckn_p_pre        (mb_tckn_p_pre),
        .o_mb_ttrk_p_pre        (mb_ttrk_p_pre),
        .o_mb_pll_speed_sel     (mb_pll_speed_sel),
        .o_mb_lclk_g            (mb_lclk_g),
        .o_mb_tx_data_lane_sel  (mb_tx_data_lane_sel),
        .o_mb_tx_val_lane_sel   (mb_tx_val_lane_sel),
        .o_mb_tx_clk_lane_sel   (mb_tx_clk_lane_sel),
        .o_mb_tx_trk_lane_sel   (mb_tx_trk_lane_sel),
        .o_mb_rx_data_deser_en  (mb_rx_data_deser_en),
        .o_mb_rx_valid_deser_en (mb_rx_valid_deser_en),
        .o_mb_vcmp_enable       (mb_vcmp_enable),
        .o_mb_vcmp_done         (mb_vcmp_done),

        // MainBand RX <- hard macro
        .i_mb_par_data          (mb_par_data),
        .i_mb_data_valid        (mb_data_valid),
        .i_mb_valid_frame_data  (mb_valid_frame_data),
        .i_mb_valid_frame_vld   (mb_valid_frame_vld),

        // MainBand raw forwarded RX clock/track (clk detector)
        .i_RCKP_P               (i_RCKP_P),
        .i_RCKN_P               (i_RCKN_P),
        .i_RTRK_P               (i_RTRK_P),

        // Sideband <-> hard macro
        .o_sb_pattern_mode      (sb_pattern_mode),
        .o_sb_pmo_en            (sb_pmo_en),
        .o_sb_ser_data_send     (sb_ser_data_send),
        .o_sb_ser_vld_send      (sb_ser_vld_send),
        .i_sb_ser_rdy           (sb_ser_rdy),
        .i_sb_des_data_rcvd     (sb_des_data_rcvd),
        .i_sb_des_vld_rcvd      (sb_des_vld_rcvd),

        // Adapter interface
        .lp_cfg                 (lp_cfg),
        .lp_cfg_vld             (lp_cfg_vld),
        .pl_cfg_crd             (pl_cfg_crd),
        .lp_cfg_crd             (lp_cfg_crd),
        .pl_cfg                 (pl_cfg),
        .pl_cfg_vld             (pl_cfg_vld),

        // RDI_SM adapter face
        .lp_state_req           (lp_state_req),
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
        .pl_state_sts           (pl_state_sts),
        .pl_max_speedmode       (pl_max_speedmode),
        .pl_speedmode           (pl_speedmode),
        .pl_lnk_cfg             (pl_lnk_cfg)
    );

    // =========================================================================
    // 2. Analog half (PLL/clocking/SerDes/tri-state for both bands)
    // =========================================================================
    analog_hard_macro #(
        .DATA_WIDTH    (DATA_WIDTH_MB),
        .NUM_LANES     (NUM_LANES),
        .VALID_PATTERN (VALID_PATTERN)
    ) u_analog_hard_macro (
        // ---- Sideband ----
        .rst_sb_n      (rst_n),
        .clk_sb        (clk_sb),
        .pattern_mode  (sb_pattern_mode),
        .pmo_en        (sb_pmo_en),
        .des_data_rcvd (sb_des_data_rcvd),
        .des_vld_rcvd  (sb_des_vld_rcvd),
        .ser_data_send (sb_ser_data_send),
        .ser_vld_send  (sb_ser_vld_send),
        .ser_rdy       (sb_ser_rdy),
        .RXDATASB      (RXDATASB),
        .TXDATASB      (TXDATASB),
        .RXCKSB        (RXCKSB),
        .TXCKSB        (TXCKSB),

        // ---- Mainband : clocks / reset ----
        .i_rst_n               (rst_n),
        .i_pll_speed_sel       (mb_pll_speed_sel),
        .lclk_g                (mb_lclk_g),
        .lclk                  (lclk),
        .gated_lclk            (gated_lclk),
        .pll_clk               (pll_clk),
        .pll_period            (pll_period),

        // ---- Mainband TX parallel in ----
        .lfsr_ser_en           (mb_lfsr_ser_en),
        .lfsr_lane             (mb_lfsr_lane),
        .valid_ser_en          (mb_valid_ser_en),
        .valid_word            (mb_valid_word),
        .i_tckp_p_pre          (mb_tckp_p_pre),
        .i_tckn_p_pre          (mb_tckn_p_pre),
        .i_ttrk_p_pre          (mb_ttrk_p_pre),
        .i_mb_tx_data_lane_sel (mb_tx_data_lane_sel),
        .i_mb_tx_val_lane_sel  (mb_tx_val_lane_sel),
        .i_mb_tx_clk_lane_sel  (mb_tx_clk_lane_sel),
        .i_mb_tx_trk_lane_sel  (mb_tx_trk_lane_sel),

        // ---- Mainband TX serial out ----
        .o_TD_P                (o_TD_P),
        .o_TVLD_P              (o_TVLD_P),
        .o_TCKP_P              (o_TCKP_P),
        .o_TCKN_P              (o_TCKN_P),
        .o_TTRK_P              (o_TTRK_P),

        // ---- Mainband RX clocks / control ----
        .i_rx_data_deser_en    (mb_rx_data_deser_en),
        .i_rx_valid_deser_en   (mb_rx_valid_deser_en),
        .i_vcmp_enable         (mb_vcmp_enable),
        .i_vcmp_done           (mb_vcmp_done),

        // ---- Mainband RX serial in ----
        .i_RD_P                (i_RD_P),
        .i_RVLD_P              (i_RVLD_P),
        .i_RCKP_P              (i_RCKP_P),

        // ---- Mainband RX parallel out ----
        .o_par_data            (mb_par_data),
        .o_data_valid          (mb_data_valid),
        .valid_frame_data      (mb_valid_frame_data),
        .valid_frame_vld       (mb_valid_frame_vld)
    );

endmodule
