`timescale 1ps/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

module MB_SB_LTSM #(
    parameter int  DATA_WIDTH_MB  = 32,
    parameter int  DATA_WIDTH_SB  = 64,
    parameter int  NUM_LANES      = 16,
    parameter int  N_BYTES        = 64,
    parameter int  GAP_WIDTH      = 32,
    parameter      [DATA_WIDTH_MB-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS  = 0.5,
    parameter int  RX_ALIGN_DELAY = 2,
    parameter int  CLK_FRQ_HZ     = 800_000_000
)(
    // =========================================================================
    // System Reset & PLL Controls
    // =========================================================================
    input  logic                             rst_n,

    // =========================================================================
    // MainBand Control & Data
    // =========================================================================
    input  logic [8*N_BYTES-1:0]             lp_data,
    input  logic                             lp_irdy,
    input  logic                             lp_valid,
    output logic                             pl_trdy,
    input  logic                             lclk_g,
    input  logic [15:0]                      i_pcmp_thr_per_lane,
    input  logic [15:0]                      i_pcmp_thr_aggregate,
    input  logic [15:0]                      i_vcmp_thr,

    // Observability outputs
    output logic                             lclk,
    output logic                             o_pll_clk,
    output logic [8*N_BYTES-1:0]             o_out_data,
    output logic                             o_pl_valid,
    output logic [15:0]                      o_pcmp_agg_err_cnt,

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
    // Sideband Controls & Serial Interface
    // =========================================================================
    input  logic                             RXCKSB,
    output logic                             TXCKSB,
    output logic                             TXDATASB,
    input  logic                             RXDATASB,

    // RDI SM Traffic Control
    output logic                             traffic_req,
    input  logic                             traffic_rdy,

    // RDI SM TX Interface (From Main Controller)
    input  logic [7:0]                       RDI_msg_no_send,
    input  logic                             stall_send,
    input  logic                             RDI_vld_send,
    output logic                             RDI_rdy,

    // RDI SM RX Interface (To Main Controller)
    output logic                             RDI_vld_rcvd,
    output logic [7:0]                       RDI_msg_no_rcvd,
    output logic                             stall_rcvd,

    // Adapter Interface (RDI Control)
    input  logic [31:0]                      lp_cfg,
    input  logic                             lp_cfg_vld,
    output logic                             pl_cfg_crd,
    input  logic                             lp_cfg_crd,
    output logic [31:0]                      pl_cfg,
    output logic                             pl_cfg_vld,

    // Register File Interface (Reg_Access)
    output logic [24:0]                      rf_addr,
    output logic [7:0]                       rf_be,
    output logic                             rf_is_64b_access,
    output logic [63:0]                      rf_wdata,
    output logic                             rd_en,
    output logic                             wr_en,
    input  logic [63:0]                      rf_rdata,
    input  logic                             rdata_vld,
    input  logic                             addr_err_o,

    // =========================================================================
    // LTSM Controls & Observability
    // =========================================================================
    output LTSM_state_e                      current_ltsm_state,
    output state_n_e                         current_ltsm_state_n,
    output logic                             timeout_8ms_occured,
    output logic [7:0]                       log0_state_n,
    output logic                             log0_lane_reversal,
    output logic                             log0_width_degrade,
    output logic [7:0]                       log0_state_n_minus_1,
    output logic [7:0]                       log0_state_n_minus_2,
    output logic [7:0]                       log1_state_n_minus_3,
    input  logic                             start_bit,            // -> LTSM params_changed
    output logic                             busy_bit_rst,

    // RESET-state triggers / strap
    input  logic                             phy_start_ucie_link_training_ctrl_out,
    input  logic                             Adapter_training_req,
    input  logic                             SPMW,

    // Capability configuration (to MBINIT)
    input  logic                             reg_phy_x8_mode_ctrl,
    input  logic                             reg_TARR_support_local_cap,
    input  logic                             reg_L2SPD_support_local_cap,
    input  logic                             reg_PSPT_support_local_cap,
    input  logic                             reg_PMO_support_local_cap,
    input  logic [3:0]                       reg_Max_Link_Speed_cap,
    input  logic [4:0]                       reg_Supported_TX_Vswing,
    input  logic                             reg_so,
    input  logic                             reg_mtp,
    input  logic [1:0]                       reg_Module_ID,
    input  logic [1:0]                       reg_Clock_Phase_cap,
    input  logic [1:0]                       reg_Clock_mode_cap,
    input  logic                             reg_TARR_support_local_ctrl,
    input  logic                             reg_PMO_support_local_ctrl,
    input  logic                             reg_Clock_Phase_ctrl,
    input  logic                             reg_Clock_mode_ctrl,
    input  logic                             reg_L2SPD_support_local_ctrl,
    input  logic                             reg_PSPT_support_local_ctrl,
    input  logic [3:0]                       reg_Target_Link_Width_ctrl,
    input  logic [3:0]                       reg_Target_Link_Speed_ctrl,

    // Capability status (from MBINIT)
    output logic                             reg_Clock_Phase_enable_status,
    output logic                             reg_Clock_mode_enable_status,
    output logic                             reg_TARR_enable_status,
    output logic [3:0]                       reg_Link_Width_enable_status,
    output logic [3:0]                       reg_Link_Speed_enable_status,
    output logic                             reg_PMO_enable_status,
    output logic                             reg_L2SPD_enable_status,
    output logic                             reg_PSPT_enable_status,

    // D2C / comparison thresholds + per-lane compare mask
    input  logic [11:0]                      cfg_max_err_thresh_perlane,
    input  logic [15:0]                      cfg_max_err_thresh_aggr,
    input  logic [NUM_LANES-1:0]             reg_lane_mask,

    // RDI status
    input  RDI_state                         rdi_state,
    input  RDI_state                         lp_state_req   // Adapter-requested RDI state (L1 wake)
);
    // clk_sb is driven as output by u_sideband_top
    logic clk_sb;

    // 2-bit lane selects for tri-state buffers (LTSM -> mb_die)
    logic [1:0]           mb_tx_trk_lane_sel;
    logic [1:0]           mb_tx_clk_lane_sel;
    logic [1:0]           mb_tx_val_lane_sel;
    logic [1:0]           mb_tx_data_lane_sel;

    // =========================================================================
    // 2. Internal Signals
    // =========================================================================

    // Sideband message bus connections between u_ltsm_top and u_sideband_top
    logic        sb_rx_valid;
    msg_no_e     sb_rx_msg_id;
    logic [15:0] sb_rx_MsgInfo;
    logic [63:0] sb_rx_data_Field;
    logic        sb_tx_valid;
    logic        sb_lsm_rdy; // Connected to sb_ltsm_rdy of u_ltsm_top
    msg_no_e     sb_tx_msg_id;
    logic [15:0] sb_tx_MsgInfo;
    logic [63:0] sb_tx_data_Field;
    logic        sb_iter_done;
    logic        sbinit_pattern_mode;
    logic        sb_det_pattern_req;
    logic [2:0]  sbinit_req_iter_count;
    logic        sb_det_pattern_rcvd;

    // Casting wires for SideBand_Top ltsm message IDs
    logic [7:0]  ltsm_msg_n_send;
    logic [7:0]  ltsm_msg_no_rcvd;

    assign ltsm_msg_n_send = sb_tx_msg_id;
    assign sb_rx_msg_id    = msg_no_e'(ltsm_msg_no_rcvd);

    // phy in reset logic 

    logic phy_in_reset = (current_ltsm_state == RESET ||
                          current_ltsm_state == SBINIT);
                          
    logic [11:0] mb_rx_max_err_thresh_perlane;
    logic [15:0] mb_rx_max_err_thresh_aggr;
    logic        gated_lclk;

    logic sticky_sb_pattern_detected;
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin 
            sticky_sb_pattern_detected <= 1'b0;
        end else if (current_ltsm_state == SBINIT) begin
            sticky_sb_pattern_detected <= 1'b0;
        end else if (sb_det_pattern_rcvd) begin
            sticky_sb_pattern_detected <= 1'b1;
        end
    end
                          
    // MainBand Control/Status intermediate connections between u_ltsm_top and u_mb_die
    logic [2:0]           mb_pll_speed_sel;   // LTSM-driven PLL speed select -> u_mb_die
    logic                 mb_mapper_en;
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

    logic                 mb_lfsr_tx_done;
    logic                 mb_valid_done;
    logic                 mb_clk_done;
    logic                 mb_pcmp_done;
    logic [NUM_LANES-1:0] mb_pcmp_per_lane_pass;
    logic                 mb_pcmp_agg_error;
    logic                 mb_vcmp_done;
    logic                 mb_vcmp_pass;
    logic                 mb_valid_frame_error;
    logic                 mb_clk_p_pass;
    logic                 mb_clk_n_pass;
    logic                 mb_track_pass;

    // =========================================================================
    // 3. Module Instantiations
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
        .lclk_g               (lclk_g),
        .i_clk_pattern_en     (mb_clk_pattern_en),
        .i_clk_embedded_en    (mb_clk_embedded_en),

        // RX control
        .i_state              (mb_state),
        .demapper_en          (mb_demapper_en),
        .i_pcmp_enable        (mb_pcmp_enable),
        .i_pcmp_mode          (mb_pcmp_mode),
        .i_pcmp_lane_mask     (mb_pcmp_lane_mask),
        .i_pcmp_thr_per_lane  (i_pcmp_thr_per_lane),
        .i_pcmp_thr_aggregate (i_pcmp_thr_aggregate),
        .i_pcmp_iter_count    (mb_pcmp_iter_count),
        .i_pcmp_pattern_mode  (mb_pcmp_pattern_mode),
        .i_pcmp_clear         (mb_pcmp_clear),
        .i_vcmp_enable        (mb_vcmp_enable),
        .i_vcmp_mode          (mb_vcmp_mode),
        .i_vcmp_thr           (i_vcmp_thr),
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

        .i_mb_tx_trk_lane_sel                  (mb_tx_trk_lane_sel),
        .i_mb_tx_clk_lane_sel                  (mb_tx_clk_lane_sel),
        .i_mb_tx_val_lane_sel                  (mb_tx_val_lane_sel),
        .i_mb_tx_data_lane_sel                 (mb_tx_data_lane_sel),

        // clocks / status
        .lclk                 (lclk),
        .gated_lclk           (gated_lclk),
        .o_lfsr_tx_done       (mb_lfsr_tx_done),
        .o_valid_done         (mb_valid_done),
        .o_clk_done           (mb_clk_done),

        // RX results + observability
        .o_out_data           (o_out_data),
        .o_pl_valid           (o_pl_valid),
        .o_pcmp_done          (mb_pcmp_done),
        .o_pcmp_per_lane_pass (mb_pcmp_per_lane_pass),
        .o_pcmp_agg_error     (mb_pcmp_agg_error),
        .o_vcmp_done          (mb_vcmp_done),
        .o_vcmp_pass          (mb_vcmp_pass),
        .o_valid_frame_error  (mb_valid_frame_error),
        .o_clk_p_pass         (mb_clk_p_pass),
        .o_clk_n_pass         (mb_clk_n_pass),
        .o_track_pass         (mb_track_pass)
    );

    SideBand_Top #(
        .DATA_WIDTH (DATA_WIDTH_SB),
        .GAP_WIDTH  (GAP_WIDTH)
    ) u_sideband_top (
        .clk_main         (lclk), // Driven by lclk coming out of u_mb_die
        .rst_main_n       (rst_n),
        .clk_sb           (clk_sb),
        .rst_sb_n         (rst_n),
        .phy_in_reset     (1'b0),
        .pmo_en           (reg_PMO_enable_status),
        .clk_ltsm         (lclk),
        .RXCKSB           (RXCKSB),
        .TXCKSB           (TXCKSB),
        .TXDATASB         (TXDATASB),
        .RXDATASB         (RXDATASB),

        .pattern_mode     (sbinit_pattern_mode),
        .start_pat_req    (sb_det_pattern_req),
        .req_iter_count   (sbinit_req_iter_count),
        .iter_done        (sb_iter_done),
        .det_pat_rcvd     (sb_det_pattern_rcvd),

        .traffic_req      (traffic_req),
        .traffic_rdy      (traffic_rdy),

        .RDI_msg_no_send  (RDI_msg_no_send),
        .stall_send       (stall_send),
        .RDI_vld_send     (RDI_vld_send),
        .RDI_rdy          (RDI_rdy),

        .ltsm_msg_n_send  (ltsm_msg_n_send),
        .msg_data_send    (sb_tx_data_Field),
        .msg_info_send    (sb_tx_MsgInfo),
        .ltsm_vld_send    (sb_tx_valid),
        .ltsm_rdy         (sb_lsm_rdy),

        .RDI_vld_rcvd     (RDI_vld_rcvd),
        .RDI_msg_no_rcvd  (RDI_msg_no_rcvd),
        .stall_rcvd       (stall_rcvd),

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

    LTSM_TOP #(
        .CLK_FRQ_HZ (CLK_FRQ_HZ),
        .NUM_LANES  (NUM_LANES)
    ) u_ltsm_top (
        .clk                                   (lclk),
        .rst_n                                 (rst_n),

        // Status / observability
        .current_ltsm_state                    (current_ltsm_state),
        .link_training_retraining              (link_training_retraining),
        .link_status                           (link_status),
        .timeout_8ms_occured                   (timeout_8ms_occured),
        
        .log0_state_n                          (log0_state_n),
        .log0_lane_reversal                    (log0_lane_reversal),
        .log0_width_degrade                    (log0_width_degrade),
        .log0_state_n_minus_1                  (log0_state_n_minus_1),
        .log0_state_n_minus_2                  (log0_state_n_minus_2),
        .log1_state_n_minus_3                  (log1_state_n_minus_3),

        // RESET-state triggers / strap
        .phy_start_ucie_link_training_ctrl_out (phy_start_ucie_link_training_ctrl_out),
        .sb_det_pattern_rcvd                   (sb_det_pattern_rcvd),
        .sb_det_pattern_rcvd_sticky            (sticky_sb_pattern_detected),
        .SPMW                                  (SPMW),

        // Capability configuration (to MBINIT)
        .reg_phy_x8_mode_ctrl                  (reg_phy_x8_mode_ctrl),
        .reg_TARR_support_local_cap            (reg_TARR_support_local_cap),
        .reg_L2SPD_support_local_cap           (reg_L2SPD_support_local_cap),
        .reg_PSPT_support_local_cap            (reg_PSPT_support_local_cap),
        .reg_PMO_support_local_cap             (reg_PMO_support_local_cap),
        .reg_Max_Link_Speed_cap                (reg_Max_Link_Speed_cap),
        .reg_Supported_TX_Vswing               (reg_Supported_TX_Vswing),
        .reg_so                                (reg_so),
        .reg_mtp                               (reg_mtp),
        .reg_Module_ID                         (reg_Module_ID),
        .reg_Clock_Phase_cap                   (reg_Clock_Phase_cap),
        .reg_Clock_mode_cap                    (reg_Clock_mode_cap),
        .reg_TARR_support_local_ctrl           (reg_TARR_support_local_ctrl),
        .reg_PMO_support_local_ctrl            (reg_PMO_support_local_ctrl),
        .reg_Clock_Phase_ctrl                  (reg_Clock_Phase_ctrl),
        .reg_Clock_mode_ctrl                   (reg_Clock_mode_ctrl),
        .reg_L2SPD_support_local_ctrl          (reg_L2SPD_support_local_ctrl),
        .reg_PSPT_support_local_ctrl           (reg_PSPT_support_local_ctrl),
        .reg_Target_Link_Width_ctrl            (reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl            (reg_Target_Link_Speed_ctrl),

        // Capability status (from MBINIT)
        .reg_Clock_Phase_enable_status         (reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status          (reg_Clock_mode_enable_status),
        .reg_TARR_enable_status                (reg_TARR_enable_status),
        .reg_Link_Width_enable_status          (reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status          (reg_Link_Speed_enable_status),
        .reg_PMO_enable_status                 (reg_PMO_enable_status),
        .reg_L2SPD_enable_status               (reg_L2SPD_enable_status),
        .reg_PSPT_enable_status                (reg_PSPT_enable_status),

        // D2C / comparison thresholds + per-lane compare mask
        .cfg_max_err_thresh_perlane            (cfg_max_err_thresh_perlane),
        .cfg_max_err_thresh_aggr               (cfg_max_err_thresh_aggr),
        .reg_lane_mask                         (reg_lane_mask),

        // Sideband message bus
        .sb_rx_valid                           (sb_rx_valid),
        .sb_rx_msg_id                          (sb_rx_msg_id),
        .sb_rx_MsgInfo                         (sb_rx_MsgInfo),
        .sb_rx_data_Field                      (sb_rx_data_Field),
        .sb_tx_valid                           (sb_tx_valid),
        .sb_ltsm_rdy                           (sb_lsm_rdy),
        .sb_tx_msg_id                          (sb_tx_msg_id),
        .sb_tx_MsgInfo                         (sb_tx_MsgInfo),
        .sb_tx_data_Field                      (sb_tx_data_Field),
        .sb_iter_done                          (sb_iter_done),
        .sbinit_pattern_mode                   (sbinit_pattern_mode),
        .sb_det_pattern_req                    (sb_det_pattern_req),
        .sbinit_req_iter_count                 (sbinit_req_iter_count),

        // RDI status
        .rdi_state                             (rdi_state),
        .lp_state_req                          (lp_state_req),

        // unit_mb_die-facing CONTROL outputs
        .i_mapper_en                           (mb_mapper_en),
        .i_width_deg_tx                        (mb_width_deg_tx),
        .i_width_deg_rx                        (mb_width_deg_rx),
        .i_lfsr_state                          (mb_lfsr_state),
        .i_reversal_en                         (mb_reversal_en),
        .i_valid_pattern_en                    (mb_valid_pattern_en),
        .i_clk_pattern_en                      (mb_clk_pattern_en),
        .i_state                               (mb_state),
        .demapper_en                           (mb_demapper_en),
        .i_pcmp_enable                         (mb_pcmp_enable),
        .i_pcmp_mode                           (mb_pcmp_mode),
        .i_pcmp_lane_mask                      (mb_pcmp_lane_mask),
        .i_pcmp_iter_count                     (mb_pcmp_iter_count),
        .i_pcmp_pattern_mode                   (mb_pcmp_pattern_mode),
        .i_pcmp_clear                          (mb_pcmp_clear),
        .i_vcmp_enable                         (mb_vcmp_enable),
        .i_vcmp_mode                           (mb_vcmp_mode),
        .i_vcmp_clear                          (mb_vcmp_clear),
        .i_clk_detector_en                     (mb_clk_detector_en),
        .i_rx_data_deser_en                    (mb_rx_data_deser_en),
        .i_rx_valid_deser_en                   (mb_rx_valid_deser_en),
        .i_clk_embedded_en                     (mb_clk_embedded_en),

        // unit_mb_die-facing RESULT inputs
        .o_lfsr_tx_done                        (mb_lfsr_tx_done),
        .o_valid_done                          (mb_valid_done),
        .o_clk_done                            (mb_clk_done),
        .o_pcmp_done                           (mb_pcmp_done),
        .o_pcmp_per_lane_pass                  (mb_pcmp_per_lane_pass),
        .o_vcmp_done                           (mb_vcmp_done),
        .o_vcmp_pass                           (mb_vcmp_pass),
        .o_valid_frame_error                   (mb_valid_frame_error),
        .o_clk_p_pass                          (mb_clk_p_pass),
        .o_clk_n_pass                          (mb_clk_n_pass),
        .i_aggr_err                            (mb_pcmp_agg_error),
        .o_track_pass                          (mb_track_pass),
        .mb_tx_data_lane_sel                   (mb_tx_data_lane_sel),
        .mb_tx_val_lane_sel                    (mb_tx_val_lane_sel),
        .mb_tx_clk_lane_sel                    (mb_tx_clk_lane_sel),
        .mb_tx_trk_lane_sel                    (mb_tx_trk_lane_sel),

        // PLL-speed / params-changed / busy-bit
        .mb_pll_speed_sel                      (mb_pll_speed_sel),
        .busy_flag                             (busy_flag),
        .start_bit                             (start_bit),
        .mb_rx_max_err_thresh_perlane          (mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr             (mb_rx_max_err_thresh_aggr)
    );

    // Expose outputs
    assign o_pll_clk = 1'b0;
    assign o_pcmp_agg_err_cnt = {15'b0, mb_pcmp_agg_error};
    assign current_ltsm_state_n = state_n_e'(log0_state_n);

endmodule
