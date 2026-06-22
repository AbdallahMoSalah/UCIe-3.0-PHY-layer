`timescale 1ps/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// UCIe_PHY
// -----------------------------------------------------------------------------
// Top-level system integration of the UCIe PHY logical layer. Following the
// hierarchy refactor, UCIe_PHY now instantiates the four blocks directly
// (the former Logical_PHY wrapper has been dissolved into this module):
//
//   * Reg_File       (u_reg_file)       - chapter-9 config/status register block
//   * SideBand_Top   (u_sideband_top)   - Sideband (messaging + reg access + RDI)
//   * unit_mb_die    (u_mb_die)         - MainBand TX/RX die
//   * MainSM         (u_main_sm)        - Main State Machine = LTSM_TOP + RDI_SM
//
// Clock generation (sb_pll + ClkDiv ÷8 → clk_sb) lives inside SideBand_Top;
// clk_sb is forwarded from SideBand_Top to Reg_File as an output net.
//
// This is a pure structural refactor: every net is wired identically to the
// previous UCIe_PHY -> Logical_PHY -> {mb_die, SideBand, LTSM, RDI} hierarchy.
// No functional behaviour was changed.
//
// Register-access bus (clk_sb domain) between SideBand Reg_Access and Reg_File:
//   SideBand_Top.{rf_addr, rf_be, rf_is_64b_access, rf_wdata, rd_en, wr_en}
//       -> Reg_File   (write / read request)
//   Reg_File.{rf_rdata, rdata_vld, addr_err_o}
//       -> SideBand_Top (read completion back to Reg_Access)
//
// INTENTIONALLY LEFT AS PASS-THROUGH (kept simple, "just wiring"):
//   * The PHY control/strap inputs (reg_*_ctrl / reg_*_cap / phy_start / D2C
//     thresholds / lane mask) are driven from the Reg_File *_ctrl_out outputs
//     (sideband-written) and capability straps, exactly as before. The Reg_File
//     *_ctrl_out / *_r_out outputs that are unused are left open (a couple of
//     register read-backs are exposed for observability).
// =============================================================================

module UCIe_PHY #(
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

    // clk_sb is generated inside SideBand_Top and forwarded here for Reg_File
    logic clk_sb;

    // =========================================================================
    // Internal nets: register-access bus (clk_sb domain) between
    // SideBand_Top's Reg_Access and the Reg_File.
    // =========================================================================
    logic [24:0] rf_addr;
    logic [7:0]  rf_be;
    logic        rf_is_64b_access;
    logic [63:0] rf_wdata;
    logic        rd_en;
    logic        wr_en;
    logic [63:0] rf_rdata;
    logic        rdata_vld;
    logic        addr_err_o;
    logic [31:0] phy_status_r_out;
    logic [31:0] ucie_link_status_r_out;
    logic [63:0] lane_mask_ctrl_out;

    // -------------------------------------------------------------------------
    // Reg_File -> MainSM control (driven by sideband register writes)
    // -------------------------------------------------------------------------
    logic        phy_start_ucie_link_training_ctrl_out;
    logic        reg_phy_x8_mode_ctrl;
    logic        reg_TARR_support_local_ctrl;
    logic        reg_PMO_support_local_ctrl;
    logic        reg_Clock_Phase_ctrl;
    logic        reg_Clock_mode_ctrl;
    logic        reg_L2SPD_support_local_ctrl;
    logic        reg_PSPT_support_local_ctrl;
    logic [3:0]  reg_Target_Link_Width_ctrl;
    logic [3:0]  reg_Target_Link_Speed_ctrl;
    logic [11:0] cfg_max_err_thresh_perlane;
    logic [15:0] cfg_max_err_thresh_aggr;
    logic        start_bit;

    // -------------------------------------------------------------------------
    // MainSM -> Reg_File status / observability
    // -------------------------------------------------------------------------
    logic        reg_Clock_Phase_enable_status;
    logic        reg_Clock_mode_enable_status;
    logic        reg_TARR_enable_status;
    logic [3:0]  reg_Link_Width_enable_status;
    logic [3:0]  reg_Link_Speed_enable_status;
    logic        reg_PMO_enable_status;
    logic        reg_L2SPD_enable_status;
    logic        reg_PSPT_enable_status;
    logic        state_timeout_8ms_occured;
    logic        sb_msg_timeout_8ms;
    logic        busy_flag;
    logic        link_training_retraining;
    logic        link_status;
    logic [7:0]  log0_state_n;
    logic        log0_lane_reversal;
    logic        log0_width_degrade;
    logic [7:0]  log0_state_n_minus_1;
    logic [7:0]  log0_state_n_minus_2;
    logic [7:0]  log1_state_n_minus_3;
    logic        phy_rm_link_err_i;

    // =========================================================================
    // MainBand die <-> MainSM / SideBand glue nets (formerly inside Logical_PHY)
    // =========================================================================

    // ---- LTSM <-> SideBand message bus ----
    logic        sb_rx_valid;
    logic [7:0]  ltsm_msg_no_rcvd;
    logic [15:0] sb_rx_MsgInfo;
    logic [63:0] sb_rx_data_Field;
    logic        sb_tx_valid;
    logic        sb_lsm_rdy;
    logic [7:0]  ltsm_msg_n_send;
    logic [15:0] sb_tx_MsgInfo;
    logic [63:0] sb_tx_data_Field;
    logic        sb_iter_done;
    logic        sbinit_pattern_mode;
    logic        sb_det_pattern_req;
    logic [2:0]  sbinit_req_iter_count;
    logic        sb_det_pattern_rcvd;

    // ---- RDI_SM <-> SideBand RDI message bus ----
    logic        rdi_vld_send;
    logic        rdi_vld_rcvd;
    logic [7:0]  rdi_msg_no_send_bus;
    logic [7:0]  rdi_msg_no_rcvd_bus;

    // ---- RDI_SM <-> MainBand / clock handshake ----
    logic        traffic_req_w;       // SideBand_Top.traffic_req -> MainSM
    logic        clk_handshake_done;  // MainSM -> SideBand_Top.traffic_rdy
    logic        rdi_lclk_g;          // MainSM -> mb_die.lclk_g

    // ---- LTSM macro-state + gated clock ----
    LTSM_state_e          current_ltsm_state;  // MainSM macro state
    logic                 gated_lclk;          // mb_die.gated_lclk -> SideBand/MainSM clock

    // ---- LTSM/RDI <-> MainBand die control/result wires ----
    logic                 mb_mapper_en;        // gated mapper enable -> mb_die.i_mapper_en
    logic [2:0]           mb_pll_speed_sel;
    logic [2:0]           mb_width_deg_tx;
    logic [2:0]           mb_width_deg_rx;
    logic [2:0]           mb_lfsr_state;
    logic                 mb_reversal_en;
    logic                 mb_valid_pattern_en;
    logic                 mb_clk_pattern_en;
    logic [2:0]           mb_state;
    logic                 mb_demapper_en;
    logic                 mb_pcmp_enable;
    logic                 mb_pcmp_mode;
    logic [NUM_LANES-1:0] mb_pcmp_lane_mask;
    logic [15:0]          mb_pcmp_iter_count;
    logic                 mb_pcmp_pattern_mode;
    logic                 mb_pcmp_clear;
    logic                 mb_vcmp_enable;
    logic                 mb_vcmp_mode;
    logic                 mb_vcmp_clear;
    logic                 mb_clk_detector_en;
    logic [NUM_LANES-1:0] mb_rx_data_deser_en;
    logic                 mb_rx_valid_deser_en;
    logic                 mb_clk_embedded_en;
    logic [11:0]          mb_rx_max_err_thresh_perlane;
    logic [15:0]          mb_rx_max_err_thresh_aggr;

    // MB TX per-stream tri-state lane selects (2-bit each: {[1]=Hi-Z, [0]=drive}).
    logic [1:0]           mb_tx_trk_lane_sel;
    logic [1:0]           mb_tx_clk_lane_sel;
    logic [1:0]           mb_tx_val_lane_sel;
    logic [1:0]           mb_tx_data_lane_sel;

    logic                 mb_lfsr_tx_done;
    logic                 mb_valid_done;
    logic                 mb_clk_done;
    logic                 mb_pcmp_done;
    logic [NUM_LANES-1:0] mb_pcmp_per_lane_pass;
    logic                 mb_pcmp_agg_error;
    logic                 mb_vcmp_done;
    logic                 mb_vcmp_pass;
    logic                 mb_clk_p_pass;
    logic                 mb_clk_n_pass;
    logic                 mb_track_pass;

    // =========================================================================
    // 1. MainBand die (TX/RX)
    // =========================================================================
    unit_mb_die #(
        .DATA_WIDTH     (DATA_WIDTH_MB),
        .NUM_LANES      (NUM_LANES),
        .N_BYTES        (N_BYTES),
        .VALID_PATTERN  (VALID_PATTERN),
        .PLL_PERIOD_NS  (PLL_PERIOD_NS),
        .RX_ALIGN_DELAY (RX_ALIGN_DELAY)
    ) u_mb_die (
        .i_rst_n              (rst_n),

        // TX control
        .lp_data              (lp_data),
        .lp_irdy              (lp_irdy),
        .lp_valid             (lp_valid),
        .pl_trdy              (pl_trdy),
        .i_mapper_en          (mb_mapper_en),
        .i_width_deg_tx       (mb_width_deg_tx),
        .i_width_deg_rx       (mb_width_deg_rx),
        .i_lfsr_state         (mb_lfsr_state),
        .i_reversal_en        (mb_reversal_en),
        .i_valid_pattern_en   (mb_valid_pattern_en),
        .i_pll_en             (1'b1),
        .i_pll_speed_sel      (mb_pll_speed_sel),
        .lclk_g               (rdi_lclk_g),
        .i_clk_pattern_en     (mb_clk_pattern_en),
        .i_clk_embedded_en    (mb_clk_embedded_en),
        .i_mb_tx_trk_lane_sel                  (mb_tx_trk_lane_sel),
        .i_mb_tx_clk_lane_sel                  (mb_tx_clk_lane_sel),
        .i_mb_tx_val_lane_sel                  (mb_tx_val_lane_sel),
        .i_mb_tx_data_lane_sel                 (mb_tx_data_lane_sel),

        // RX control
        .i_state              (mb_state),
        .demapper_en          (mb_demapper_en),
        .i_pcmp_enable        (mb_pcmp_enable),
        .i_pcmp_mode          (mb_pcmp_mode),
        .i_pcmp_lane_mask     (mb_pcmp_lane_mask),
        .i_pcmp_thr_per_lane  (mb_rx_max_err_thresh_perlane),
        .i_pcmp_thr_aggregate (mb_rx_max_err_thresh_aggr),
        .i_pcmp_iter_count    (mb_pcmp_iter_count),
        .i_pcmp_pattern_mode  (mb_pcmp_pattern_mode),
        .i_pcmp_clear         (mb_pcmp_clear),
        .i_vcmp_enable        (mb_vcmp_enable),
        .i_vcmp_mode          (mb_vcmp_mode),
        .i_vcmp_thr           (mb_rx_max_err_thresh_perlane),
        .i_vcmp_clear         (mb_vcmp_clear),
        .i_clk_detector_en    (mb_clk_detector_en),
        .i_rx_data_deser_en   (mb_rx_data_deser_en),
        .i_rx_valid_deser_en  (mb_rx_valid_deser_en),

        // RX serial in (partner TX)
        .i_RD_P               (i_RD_P),
        .i_RVLD_P             (i_RVLD_P),
        .i_RCKP_P             (i_RCKP_P),
        .i_RCKN_P             (i_RCKN_P),
        .i_RTRK_P             (i_RTRK_P),

        // TX serial out (partner RX)
        .o_TD_P               (o_TD_P),
        .o_TVLD_P             (o_TVLD_P),
        .o_TCKP_P             (o_TCKP_P),
        .o_TCKN_P             (o_TCKN_P),
        .o_TTRK_P             (o_TTRK_P),

        // clocks / status
        .lclk                 (lclk),
        .gated_lclk           (gated_lclk),
        .o_lfsr_tx_done       (mb_lfsr_tx_done),
        .o_valid_done         (mb_valid_done),
        .o_clk_done           (mb_clk_done),

        // RX results + observability
        .o_out_data           (pl_data),
        .o_pl_valid           (pl_valid),
        .o_pcmp_done          (mb_pcmp_done),
        .o_pcmp_per_lane_pass (mb_pcmp_per_lane_pass),
        .o_pcmp_agg_error     (mb_pcmp_agg_error),
        .o_vcmp_done          (mb_vcmp_done),
        .o_vcmp_pass          (mb_vcmp_pass),
        .o_valid_frame_error  (pl_error),
        .o_clk_p_pass         (mb_clk_p_pass),
        .o_clk_n_pass         (mb_clk_n_pass),
        .o_track_pass         (mb_track_pass)
    );

    // =========================================================================
    // 2. SideBand
    // =========================================================================
    SideBand_Top #(
        .DATA_WIDTH (DATA_WIDTH_SB),
        .GAP_WIDTH  (GAP_WIDTH)
    ) u_sideband_top (
        .clk_main         (lclk),
        .clk_ltsm         (gated_lclk),
        .rst_main_n       (rst_n),
        .clk_sb           (clk_sb),
        .rst_sb_n         (rst_n),
        .phy_in_reset     ((current_ltsm_state == RESET)),
        .pmo_en           (reg_PMO_enable_status),

        .RXCKSB           (RXCKSB),
        .TXCKSB           (TXCKSB),
        .TXDATASB         (TXDATASB),
        .RXDATASB         (RXDATASB),

        .pattern_mode     (sbinit_pattern_mode),
        .start_pat_req    (sb_det_pattern_req),
        .req_iter_count   (sbinit_req_iter_count),
        .iter_done        (sb_iter_done),
        .det_pat_rcvd     (sb_det_pattern_rcvd),

        .traffic_req      (traffic_req_w),
        .traffic_rdy      (clk_handshake_done),

        // RDI message path (driven by MainSM / RDI_SM)
        .RDI_msg_no_send  (rdi_msg_no_send_bus),
        .stall_send       (1'b0),                 // tied per integration spec
        .RDI_vld_send     (rdi_vld_send),
        .RDI_rdy          (),                      // unconnected per integration spec
        .RDI_vld_rcvd     (rdi_vld_rcvd),
        .RDI_msg_no_rcvd  (rdi_msg_no_rcvd_bus),
        .stall_rcvd       (),                      // unconnected per integration spec

        // LTSM message path
        .ltsm_msg_n_send  (ltsm_msg_n_send),
        .msg_data_send    (sb_tx_data_Field),
        .msg_info_send    (sb_tx_MsgInfo),
        .ltsm_vld_send    (sb_tx_valid),
        .ltsm_rdy         (sb_lsm_rdy),

        .ltsm_vld_rcvd    (sb_rx_valid),
        .ltsm_msg_no_rcvd (ltsm_msg_no_rcvd),
        .msg_data_rcvd    (sb_rx_data_Field),
        .msg_info_rcvd    (sb_rx_MsgInfo),

        .lp_cfg           (lp_cfg),
        .lp_cfg_vld       (lp_cfg_vld),
        .pl_cfg_crd       (pl_cfg_crd),
        .lp_cfg_crd       (lp_cfg_crd),
        .pl_cfg           (pl_cfg),
        .pl_cfg_vld       (pl_cfg_vld),

        .rf_addr          (rf_addr),
        .rf_be            (rf_be),
        .rf_is_64b_access (rf_is_64b_access),
        .rf_wdata         (rf_wdata),
        .rd_en            (rd_en),
        .wr_en            (wr_en),
        .rf_rdata         (rf_rdata),
        .rdata_vld        (rdata_vld),
        .addr_err_o       (addr_err_o)
    );

    // =========================================================================
    // 3. MainSM (LTSM_TOP + RDI_SM)
    // =========================================================================
    MainSM #(
        .NUM_LANES  (NUM_LANES),
        .CLK_FRQ_HZ (CLK_FRQ_HZ)
    ) u_main_sm (
        .lclk                                  (lclk),
        .gated_lclk                            (gated_lclk),
        .rst_n                                 (rst_n),

        // LTSM observability / error log
        .log0_state_n                          (log0_state_n),
        .log0_lane_reversal                    (log0_lane_reversal),
        .log0_width_degrade                    (log0_width_degrade),
        .log0_state_n_minus_1                  (log0_state_n_minus_1),
        .log0_state_n_minus_2                  (log0_state_n_minus_2),
        .log1_state_n_minus_3                  (log1_state_n_minus_3),
        .phy_rm_link_err_i                     (phy_rm_link_err_i),
        .current_ltsm_state                    (current_ltsm_state),

        // RESET-state triggers / strap
        .phy_start_ucie_link_training_ctrl_out (phy_start_ucie_link_training_ctrl_out),
        .SPMW                                  (SPMW_CAP),

        // Capability configuration
        .reg_phy_x8_mode_ctrl                  (reg_phy_x8_mode_ctrl),
        .reg_TARR_support_local_cap            (TARR_CAP),
        .reg_L2SPD_support_local_cap           (L2SPD_CAP),
        .reg_PSPT_support_local_cap            (PSPT_CAP),
        .reg_PMO_support_local_cap             (PMO_CAP),
        .reg_Max_Link_Speed_cap                (MAX_LINK_SPEED_CAP),
        .reg_Supported_TX_Vswing               (SUPPORTEDVSWING_CAP),
        .reg_so                                (1'b0),
        .reg_mtp                               (1'b0),
        .reg_Module_ID                         (MODULE_ID),
        .reg_Clock_Phase_cap                   (CLK_PHASE_CAP),
        .reg_Clock_mode_cap                    (CLK_MODE_CAP),
        .reg_TARR_support_local_ctrl           (reg_TARR_support_local_ctrl),
        .reg_PMO_support_local_ctrl            (reg_PMO_support_local_ctrl),
        .reg_Clock_Phase_ctrl                  (reg_Clock_Phase_ctrl),
        .reg_Clock_mode_ctrl                   (reg_Clock_mode_ctrl),
        .reg_L2SPD_support_local_ctrl          (reg_L2SPD_support_local_ctrl),
        .reg_PSPT_support_local_ctrl           (reg_PSPT_support_local_ctrl),
        .reg_Target_Link_Width_ctrl            (reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl            (reg_Target_Link_Speed_ctrl),

        // Capability status
        .reg_Clock_Phase_enable_status         (reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status          (reg_Clock_mode_enable_status),
        .reg_TARR_enable_status                (reg_TARR_enable_status),
        .reg_Link_Width_enable_status          (reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status          (reg_Link_Speed_enable_status),
        .reg_PMO_enable_status                 (reg_PMO_enable_status),
        .reg_L2SPD_enable_status               (reg_L2SPD_enable_status),
        .reg_PSPT_enable_status                (reg_PSPT_enable_status),
        .state_timeout_8ms_occured             (state_timeout_8ms_occured),
        .sb_msg_timeout_8ms                    (sb_msg_timeout_8ms),
        .start_bit                             (start_bit),
        .busy_flag                             (busy_flag),
        .link_training_retraining              (link_training_retraining),
        .link_status                           (link_status),

        // D2C thresholds + lane mask
        .cfg_max_err_thresh_perlane            (cfg_max_err_thresh_perlane),
        .cfg_max_err_thresh_aggr               (cfg_max_err_thresh_aggr),
        .reg_lane_mask                         (lane_mask_ctrl_out [NUM_LANES-1:0]),

        // SideBand : LTSM message bus
        .sb_rx_valid                           (sb_rx_valid),
        .ltsm_msg_no_rcvd                      (ltsm_msg_no_rcvd),
        .sb_rx_MsgInfo                         (sb_rx_MsgInfo),
        .sb_rx_data_Field                      (sb_rx_data_Field),
        .sb_tx_valid                           (sb_tx_valid),
        .sb_ltsm_rdy                           (sb_lsm_rdy),
        .ltsm_msg_n_send                       (ltsm_msg_n_send),
        .sb_tx_MsgInfo                         (sb_tx_MsgInfo),
        .sb_tx_data_Field                      (sb_tx_data_Field),
        .sb_iter_done                          (sb_iter_done),
        .sbinit_pattern_mode                   (sbinit_pattern_mode),
        .sb_det_pattern_req                    (sb_det_pattern_req),
        .sbinit_req_iter_count                 (sbinit_req_iter_count),
        .sb_det_pattern_rcvd                   (sb_det_pattern_rcvd),

        // SideBand : RDI message bus + clock handshake
        .rdi_msg_no_send_bus                   (rdi_msg_no_send_bus),
        .rdi_vld_send                          (rdi_vld_send),
        .rdi_vld_rcvd                          (rdi_vld_rcvd),
        .rdi_msg_no_rcvd_bus                   (rdi_msg_no_rcvd_bus),
        .traffic_req                           (traffic_req_w),
        .clk_handshake_done                    (clk_handshake_done),

        // MainBand die : CONTROL outputs
        .mb_mapper_en                          (mb_mapper_en),
        .rdi_lclk_g                            (rdi_lclk_g),
        .mb_pll_speed_sel                      (mb_pll_speed_sel),
        .mb_width_deg_tx                       (mb_width_deg_tx),
        .mb_width_deg_rx                       (mb_width_deg_rx),
        .mb_lfsr_state                         (mb_lfsr_state),
        .mb_reversal_en                        (mb_reversal_en),
        .mb_valid_pattern_en                   (mb_valid_pattern_en),
        .mb_clk_pattern_en                     (mb_clk_pattern_en),
        .mb_state                              (mb_state),
        .mb_demapper_en                        (mb_demapper_en),
        .mb_pcmp_enable                        (mb_pcmp_enable),
        .mb_pcmp_mode                          (mb_pcmp_mode),
        .mb_pcmp_lane_mask                     (mb_pcmp_lane_mask),
        .mb_pcmp_iter_count                    (mb_pcmp_iter_count),
        .mb_pcmp_pattern_mode                  (mb_pcmp_pattern_mode),
        .mb_pcmp_clear                         (mb_pcmp_clear),
        .mb_vcmp_enable                        (mb_vcmp_enable),
        .mb_vcmp_mode                          (mb_vcmp_mode),
        .mb_vcmp_clear                         (mb_vcmp_clear),
        .mb_clk_detector_en                    (mb_clk_detector_en),
        .mb_rx_data_deser_en                   (mb_rx_data_deser_en),
        .mb_rx_valid_deser_en                  (mb_rx_valid_deser_en),
        .mb_clk_embedded_en                    (mb_clk_embedded_en),
        .mb_tx_trk_lane_sel                    (mb_tx_trk_lane_sel),
        .mb_tx_clk_lane_sel                    (mb_tx_clk_lane_sel),
        .mb_tx_val_lane_sel                    (mb_tx_val_lane_sel),
        .mb_tx_data_lane_sel                   (mb_tx_data_lane_sel),
        .mb_rx_max_err_thresh_perlane          (mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr             (mb_rx_max_err_thresh_aggr),

        // MainBand die : RESULT inputs
        .mb_lfsr_tx_done                       (mb_lfsr_tx_done),
        .mb_valid_done                         (mb_valid_done),
        .mb_clk_done                           (mb_clk_done),
        .mb_pcmp_done                          (mb_pcmp_done),
        .mb_pcmp_per_lane_pass                 (mb_pcmp_per_lane_pass),
        .mb_pcmp_agg_error                     (mb_pcmp_agg_error),
        .mb_vcmp_done                          (mb_vcmp_done),
        .mb_vcmp_pass                          (mb_vcmp_pass),
        .mb_valid_frame_error                  (pl_error),
        .mb_clk_p_pass                         (mb_clk_p_pass),
        .mb_clk_n_pass                         (mb_clk_n_pass),
        .mb_track_pass                         (mb_track_pass),

        // RDI adapter face
        .lp_state_req                          (lp_state_req),
        .lp_clk_ack                            (lp_clk_ack),
        .lp_wake_req                           (lp_wake_req),
        .lp_stallack                           (lp_stallack),
        .lp_linkerror                          (lp_linkerror),
        .pl_clk_req                            (pl_clk_req),
        .pl_stallreq                           (pl_stallreq),
        .pl_wake_ack                           (pl_wake_ack),
        .pl_trainerror                         (pl_trainerror),
        .pl_inband_pres                        (pl_inband_pres),
        .pl_phyinrecenter                      (pl_phyinrecenter),
        .pl_state_sts                          (pl_state_sts),
        .pl_max_speedmode                      (pl_max_speedmode),
        .pl_speedmode                          (pl_speedmode),
        .pl_lnk_cfg                            (pl_lnk_cfg)
    );

    // =========================================================================
    // 4. Register File (chapter-9 config/status block, sideband-accessible)
    // -------------------------------------------------------------------------
    // Clocked in the clk_sb domain (same as Reg_Access inside SideBand_Top).
    // HW capability inputs are driven from the top-level strap ports; HW status
    // inputs are driven from the live MainSM status outputs. SW-control outputs
    // (*_ctrl_out) feed MainSM; unused outputs are left open.
    // =========================================================================
    Reg_File u_reg_file (
        .clk                  (clk_sb),
        .rst_n                (rst_n),

        // Register-access bus (from SideBand Reg_Access)
        .rf_addr              (rf_addr),
        .rf_be                (rf_be),
        .rf_is_64b_access     (rf_is_64b_access),
        .rf_wdata             (rf_wdata),
        .rd_en                (rd_en),
        .wr_en                (wr_en),
        .rf_rdata             (rf_rdata),
        .rdata_vld            (rdata_vld),
        .addr_err_o           (addr_err_o),

        // --- UCIe Link Capability (00Ch) cap inputs ---
        .adapter_raw_format_support_cap_i                                                  (1'b0),
        .hw_max_link_width_cap_i                                                           (MAX_LINK_WIDTH_CAP),
        .hw_max_link_speed_cap_i                                                           (MAX_LINK_SPEED_CAP),
        .adapter_multi_protocol_cap_i                                                      (1'b0),
        .phy_advanced_pkg_cap_i                                                            (ADVANCED_PKG_CAP),
        .adapter_68B_flit_formate_streaming_cap_i                                          (1'b0),
        .adapter_256B_end_header_flit_format_streaming_cap_i                               (1'b0),
        .adapter_256B_start_header_flit_format_streaming_cap_i                             (1'b0),
        .adapter_256B_latency_optimized_flit_format_without_optional_bytes_streaming_cap_i (1'b0),
        .adapter_256B_latency_optimized_flit_format_with_optional_bytes_streaming_cap_i    (1'b0),
        .adapter_enhanced_multi_protocol_capable_cap_i                                     (1'b0),
        .adapter_standard_start_header_flit_for_pcie_protocol_cap_i                        (1'b0),
        .adapter_latency_optimized_flit_with_optional_bytes_for_pcie_protocol_cap_i        (1'b0),
        .adapter_runtime_link_testing_parity_feature_error_signaling_cap_i                 (1'b0),
        .hw_apmw_cap_i                                                                     (1'b0),
        .hw_spmw_cap_i                                                                     (SPMW_CAP),
        .phy_sideband_performant_mode_operation_cap_i                                      (PMO_CAP),
        .phy_priority_sideband_packet_transfer_cap_i                                       (PSPT_CAP),
        .phy_l2_sideband_power_down_cap_i                                                  (L2SPD_CAP),

        // --- UCIe Link Status (014h) live HW inputs ---
        .adapter_raw_format_enabled_status_i               (1'b0),
        .adapter_multi_protocol_enabled_status_i           (1'b0),
        .adapter_enhanced_multi_protocol_enabled_status_i  (1'b0),
        .phy_x32_advanced_package_module_enabled_status_i  (1'b0),
        .phy_link_width_enabled_status_i                   (reg_Link_Width_enable_status),
        .phy_link_speed_enabled_status_i                   (reg_Link_Speed_enable_status),
        .phy_link_status_status_i                          (link_status),
        .phy_link_training_retraining_status_i             (link_training_retraining),
        .phy_bw_changed_status_i                           (log0_width_degrade || 1'b0),
        .phy_uci_e_link_correctable_error_i                (1'b0),
        .phy_uci_e_link_uncorrectable_non_fatal_error_i    (1'b0),
        .phy_uci_e_link_uncorrectable_fatal_error_i        (1'b0),
        .adapter_flit_format_status_i                      (4'd0),
        .phy_sideband_performant_mode_operation_status_i   (reg_PMO_enable_status),
        .phy_priority_sideband_packet_transfer_status_i    (reg_PSPT_enable_status),
        .phy_l2_sideband_power_down_status_i               (reg_L2SPD_enable_status),

        // --- Link Event Notification Control ---
        .link_event_notification_interrupt_number_i        (5'd0),

        // --- PHY Capability (1000h) cap inputs ---
        .phy_term_link_cap_i                       (1'b0),
        .phy_tx_eq_status_iualization_support_cap_i(1'b0),
        .phy_tx_vswing_encodings_cap_i             (SUPPORTEDVSWING_CAP),
        .phy_rx_clk_mode_support_cap_i             (CLK_MODE_CAP),
        .phy_rx_clk_phase_support_cap_i            (CLK_PHASE_CAP),
        .phy_package_type_cap_i                    (!ADVANCED_PKG_CAP),
        .phy_tcm_support_cap_i                     (1'b0),
        .phy_tarr_support_cap_i                    (TARR_CAP),

        // --- PHY Status (1008h) live HW inputs ---
        .phy_rx_term_status_i                      (1'b0),
        .phy_tx_eq_status_i                        (1'b0),
        .phy_clk_mode_status_i                     (reg_Clock_mode_enable_status),
        .phy_clk_phase_status_i                    (reg_Clock_Phase_enable_status),
        .phy_lane_rev_status_i                     (log0_lane_reversal),
        .phy_iq_correction_param_status_i          (6'd0),
        .phy_eq_preset_setting_status_i            (4'd0),
        .phy_tarr_status_i                         (reg_TARR_enable_status),

        // --- Error Log 0 (1080h) ---
        .err_state_capture                         (log0_state_n),
        .phy_lane_rev_err_log_i                    (log0_lane_reversal),
        .phy_width_degrade_err_log_i               (log0_width_degrade),
        .err_capture_en                            (pl_trainerror),

        // --- Error Log 1 (1090h) ---
        .phy_state_timeout_i                       (state_timeout_8ms_occured),
        .phy_sb_timeout_i                          (sb_msg_timeout_8ms),
        .phy_rm_link_err_i                         (phy_rm_link_err_i),
        .phy_internal_err_i                        (1'b0),

        // --- Runtime Link Test Status (1108h) ---
        .rt_link_busy_status_i                     (busy_flag),

        // =====================================================================
        // SW control / register read-back OUTPUTS
        // =====================================================================
        .phy_max_link_speed_cap_out                (),
        .phy_link_width_enabled_status_out         (),
        .phy_link_speed_enabled_status_out         (),
        .phy_target_link_width_ctrl_out            (reg_Target_Link_Width_ctrl),
        .phy_target_link_speed_ctrl_out            (reg_Target_Link_Speed_ctrl),
        .phy_start_ucie_link_training_ctrl_out     (phy_start_ucie_link_training_ctrl_out),
        .phy_retrain_ucie_link_ctrl_out            (),
        .phy_pmo_ctrl_out                          (reg_PMO_support_local_ctrl),
        .phy_pspt_ctrl_out                         (reg_PSPT_support_local_ctrl),
        .phy_l2spd_ctrl_out                        (reg_L2SPD_support_local_ctrl),
        .phy_rx_term_status_i_ctrl_out             (),
        .phy_tx_eq_status_i_en_ctrl_out            (),
        .phy_rx_clk_mode_ctrl_out                  (reg_Clock_mode_ctrl),
        .phy_rx_clk_phase_ctrl_out                 (reg_Clock_Phase_ctrl),
        .phy_x8_width_mode_ctrl_out                (reg_phy_x8_mode_ctrl),
        .phy_iq_correction_en_ctrl_out             (),
        .phy_iq_correction_param_ctrl_out          (),
        .phy_tx_eq_status_i_preset_ctrl_out        (),
        .phy_tx_eq_status_i_preset_setting_ctrl_out(),
        .phy_tarr_en_ctrl_out                      (reg_TARR_support_local_ctrl),
        .phy_init_ctrl_out                         (),
        .phy_resume_training_ctrl_out              (),
        .lane_mask_ctrl_out                        (lane_mask_ctrl_out),
        .max_error_threshold_in_per_lane_comparison_out  (cfg_max_err_thresh_perlane),
        .max_error_threshold_in_aggregate_comparison_out (cfg_max_err_thresh_aggr),
        .idle_count_out                            (),
        .iterations_out                            (),
        .current_lane_map_module_0_enable_out      (),
        .rt_link_test_start_ctrl_out               (start_bit),
        .rt_apply_module_0_lane_repair_ctrl_out    (),
        .inject_stuck_at_fault_ctrl_out            (),
        .module_0_lane_repair_id_ctrl_out          (),

        .ucie_link_cap_r_out                       (),
        .ucie_link_ctrl_r_out                      (),
        .ucie_link_status_r_out                    (ucie_link_status_r_out),
        .link_event_notif_ctrl_r_out               (),
        .error_notif_ctrl_r_out                    (),
        .phy_cap_r_out                             (),
        .phy_control_r_out                         (),
        .phy_status_r_out                          (phy_status_r_out),
        .phy_init_debug_r_out                      (),
        .training_setup1_r_out                     (),
        .training_setup2_r_out                     (),
        .training_setup3_r_out                     (),
        .training_setup4_r_out                     (),
        .lane_map_mod0_r_out                       (),
        .error_log0_r_out                          (),
        .error_log1_r_out                          (),
        .rt_test_ctrl_r_out                        (),
        .rt_test_status_r_out                      ()
    );

endmodule
