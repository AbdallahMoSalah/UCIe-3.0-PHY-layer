`timescale 1ps/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// MainSM
// -----------------------------------------------------------------------------
// Main State Machine wrapper: groups the two link state machines together with
// the small amount of glue that lives strictly between them:
//
//   * LTSM_TOP  (u_ltsm_top)  - Link Training State Machine
//   * RDI_SM    (u_rdi_sm)    - RDI (Raw D2D Interface) state machine
//
// This block was carved out of the former Logical_PHY with NO behavioural
// change: every net that used to be internal to Logical_PHY between LTSM_TOP /
// RDI_SM and the glue is preserved verbatim here.  Signals that previously
// crossed between these SMs and the MainBand die / SideBand / Reg_File / adapter
// are now exposed as MainSM ports and wired identically by UCIe_PHY.
//
// Glue kept inside MainSM (was inside Logical_PHY):
//   * stall_done latch + mapper-enable gating  -> mb_mapper_en
//   * sticky SBINIT pattern-detected flop
//   * phy_rm_link_err_i decode from the RDI receive message
//
// Internal-only nets (never leave MainSM):
//   * current_ltsm_state (also exported for SideBand phy_in_reset / observ.)
//   * rdi_state_w        (RDI_SM.rdi_state -> LTSM.rdi_state)
//   * ltsm_mapper_en, stall_done_w, stall_done_latched
//   * the msg_no_e <-> [7:0] casts for both the LTSM and RDI message buses
// =============================================================================

module MainSM #(
    parameter int  NUM_LANES  = 16,
    parameter int  CLK_FRQ_HZ = 800_000_000
)(
    // =========================================================================
    // Clocks & Reset
    // =========================================================================
    input  logic                             lclk,        // RDI_SM + glue flops
    input  logic                             gated_lclk,  // LTSM_TOP clock
    input  logic                             rst_n,

    // =========================================================================
    // LTSM observability / error log
    // =========================================================================
    output logic [7:0]                       log0_state_n,
    output logic                             log0_lane_reversal,
    output logic                             log0_width_degrade,
    output logic [7:0]                       log0_state_n_minus_1,
    output logic [7:0]                       log0_state_n_minus_2,
    output logic [7:0]                       log1_state_n_minus_3,
    output logic                             phy_rm_link_err_i,

    // Macro state (to SideBand phy_in_reset and top-level observability)
    output LTSM_state_e                       current_ltsm_state,

    // =========================================================================
    // RESET-state triggers / strap
    // =========================================================================
    input  logic                             phy_start_ucie_link_training_ctrl_out,
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
    output logic                             timeout_8ms_occured,
    input  logic                             start_bit,
    output logic                             busy_flag,
    output logic                             link_training_retraining,
    output logic                             link_status,

    // D2C / comparison thresholds + per-lane compare mask
    input  logic [11:0]                      cfg_max_err_thresh_perlane,
    input  logic [15:0]                      cfg_max_err_thresh_aggr,
    input  logic [NUM_LANES-1:0]             reg_lane_mask,

    // =========================================================================
    // SideBand : LTSM message bus
    // =========================================================================
    input  logic                             sb_rx_valid,
    input  logic [7:0]                       ltsm_msg_no_rcvd,
    input  logic [15:0]                      sb_rx_MsgInfo,
    input  logic [63:0]                      sb_rx_data_Field,
    output logic                             sb_tx_valid,
    input  logic                             sb_ltsm_rdy,
    output logic [7:0]                       ltsm_msg_n_send,
    output logic [15:0]                      sb_tx_MsgInfo,
    output logic [63:0]                      sb_tx_data_Field,
    input  logic                             sb_iter_done,
    output logic                             sbinit_pattern_mode,
    output logic                             sb_det_pattern_req,
    output logic [2:0]                       sbinit_req_iter_count,
    input  logic                             sb_det_pattern_rcvd,

    // =========================================================================
    // SideBand : RDI message bus + clock handshake
    // =========================================================================
    output logic [7:0]                       rdi_msg_no_send_bus,
    output logic                             rdi_vld_send,
    input  logic                             rdi_vld_rcvd,
    input  logic [7:0]                       rdi_msg_no_rcvd_bus,
    input  logic                             traffic_req,        // SideBand -> RDI
    output logic                             clk_handshake_done, // RDI -> SideBand traffic_rdy

    // =========================================================================
    // MainBand die : CONTROL outputs
    // =========================================================================
    output logic                             mb_mapper_en,       // gated mapper enable
    output logic                             rdi_lclk_g,          // RDI-owned TX clock gate
    output logic [2:0]                       mb_pll_speed_sel,
    output logic [2:0]                       mb_width_deg_tx,
    output logic [2:0]                       mb_width_deg_rx,
    output logic [2:0]                       mb_lfsr_state,
    output logic                             mb_reversal_en,
    output logic                             mb_valid_pattern_en,
    output logic                             mb_clk_pattern_en,
    output logic [2:0]                       mb_state,
    output logic                             mb_demapper_en,
    output logic                             mb_pcmp_enable,
    output logic                             mb_pcmp_mode,
    output logic [NUM_LANES-1:0]             mb_pcmp_lane_mask,
    output logic [15:0]                      mb_pcmp_iter_count,
    output logic                             mb_pcmp_pattern_mode,
    output logic                             mb_pcmp_clear,
    output logic                             mb_vcmp_enable,
    output logic                             mb_vcmp_mode,
    output logic                             mb_vcmp_clear,
    output logic                             mb_clk_detector_en,
    output logic [NUM_LANES-1:0]             mb_rx_data_deser_en,
    output logic                             mb_rx_valid_deser_en,
    output logic                             mb_clk_embedded_en,
    output logic [1:0]                       mb_tx_trk_lane_sel,
    output logic [1:0]                       mb_tx_clk_lane_sel,
    output logic [1:0]                       mb_tx_val_lane_sel,
    output logic [1:0]                       mb_tx_data_lane_sel,
    output logic [11:0]                      mb_rx_max_err_thresh_perlane,
    output logic [15:0]                      mb_rx_max_err_thresh_aggr,

    // =========================================================================
    // MainBand die : RESULT inputs
    // =========================================================================
    input  logic                             mb_lfsr_tx_done,
    input  logic                             mb_valid_done,
    input  logic                             mb_clk_done,
    input  logic                             mb_pcmp_done,
    input  logic [NUM_LANES-1:0]             mb_pcmp_per_lane_pass,
    input  logic                             mb_pcmp_agg_error,
    input  logic                             mb_vcmp_done,
    input  logic                             mb_vcmp_pass,
    input  logic                             mb_valid_frame_error,
    input  logic                             mb_clk_p_pass,
    input  logic                             mb_clk_n_pass,
    input  logic                             mb_track_pass,

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
    // Internal nets (kept internal to MainSM)
    // =========================================================================

    // LTSM message-id casting wires
    msg_no_e       sb_rx_msg_id;
    msg_no_e       sb_tx_msg_id;
    assign ltsm_msg_n_send = sb_tx_msg_id;
    assign sb_rx_msg_id    = msg_no_e'(ltsm_msg_no_rcvd);

    // RDI message-id casting wires
    msg_no_e       rdi_msg_send;          // RDI_SM.Link_Mgmt_Msg_Send
    msg_no_e       rdi_msg_rcvd;          // RDI_SM.Link_Mgmt_Msg_Receive
    assign rdi_msg_no_send_bus = rdi_msg_send;                   // msg_no_e -> [7:0]
    assign rdi_msg_rcvd        = msg_no_e'(rdi_msg_no_rcvd_bus); // [7:0] -> msg_no_e

    // RDI_SM <-> LTSM
    RDI_state    rdi_state_w;      // RDI_SM.rdi_state -> LTSM.rdi_state
    logic        ltsm_mapper_en;   // LTSM mapper enable (pre-gate)
    logic        stall_done_w;     // RDI_SM.stall_done (latched into mapper enable)

    // =========================================================================
    // stall_done latch + mapper-enable gating
    // -------------------------------------------------------------------------
    // The RDI stall_done pulse is captured into a level (SR flop on lclk) that
    // represents "data path stalled":
    //   * set   by stall_done   (RDI stall handshake complete -> stall the path)
    //   * clear when the LTSM mapper enable falls (acts as the latch reset)
    // The mapper is enabled in ACTIVE (ltsm_mapper_en) while NOT stalled, so data
    // flows in steady ACTIVE and is held off only during an RDI stall.
    // =========================================================================
    logic stall_done_latched;
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n)
            stall_done_latched <= 1'b0;
        else if (!ltsm_mapper_en)      // enable low -> clear the latch
            stall_done_latched <= 1'b0;
        else if (stall_done_w)         // set on stall_done (stalled)
            stall_done_latched <= 1'b1;
    end

    assign mb_mapper_en = ltsm_mapper_en & ~stall_done_latched;

    always_comb begin
        phy_rm_link_err_i = (rdi_msg_rcvd == RDI_LINK_ERROR_REQ)
                            && rdi_vld_rcvd;
    end

    // =========================================================================
    // sticky SBINIT pattern-detected flop
    // =========================================================================
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

    // =========================================================================
    // LTSM_TOP
    // =========================================================================
    LTSM_TOP #(
        .CLK_FRQ_HZ (CLK_FRQ_HZ),
        .NUM_LANES  (NUM_LANES)
    ) u_ltsm_top (
        .clk                                   (gated_lclk),
        .rst_n                                 (rst_n),

        // Status
        .current_ltsm_state                    (current_ltsm_state),
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
        .sb_ltsm_rdy                           (sb_ltsm_rdy),
        .sb_tx_msg_id                          (sb_tx_msg_id),
        .sb_tx_MsgInfo                         (sb_tx_MsgInfo),
        .sb_tx_data_Field                      (sb_tx_data_Field),
        .sb_iter_done                          (sb_iter_done),
        .sbinit_pattern_mode                   (sbinit_pattern_mode),
        .sb_det_pattern_req                    (sb_det_pattern_req),
        .sbinit_req_iter_count                 (sbinit_req_iter_count),

        // RDI status
        .rdi_state                             (rdi_state_w),
        .lp_state_req                          (lp_state_req),

        // unit_mb_die-facing CONTROL outputs
        .i_mapper_en                           (ltsm_mapper_en),
        .mb_pll_speed_sel                      (mb_pll_speed_sel),
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
        .mb_tx_trk_lane_sel                    (mb_tx_trk_lane_sel),
        .mb_tx_clk_lane_sel                    (mb_tx_clk_lane_sel),
        .mb_tx_val_lane_sel                    (mb_tx_val_lane_sel),
        .mb_tx_data_lane_sel                   (mb_tx_data_lane_sel),
        .busy_flag                             (busy_flag),
        .link_status                           (link_status),
        .link_training_retraining              (link_training_retraining),
        .start_bit                             (start_bit),
        .timeout_8ms_occured                   (timeout_8ms_occured),
        .mb_rx_max_err_thresh_perlane          (mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr             (mb_rx_max_err_thresh_aggr),

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
        .o_track_pass                          (mb_track_pass)
    );

    // =========================================================================
    // RDI_SM
    // =========================================================================
    RDI_SM u_rdi_sm (
        .lclk                                       (lclk),
        .rst_n                                      (rst_n),

        // Adapter interface
        .lp_clk_ack                                 (lp_clk_ack),
        .lp_wake_req                                (lp_wake_req),
        .lp_stallack                                (lp_stallack),
        .lp_state_req                               (lp_state_req),
        .lp_linkerror                               (lp_linkerror),

        .pl_clk_req                                 (pl_clk_req),
        .pl_stallreq                                (pl_stallreq),
        .pl_wake_ack                                (pl_wake_ack),
        .pl_trainerror                              (pl_trainerror),
        .pl_inband_pres                             (pl_inband_pres),
        .pl_phyinrecenter                           (pl_phyinrecenter),
        .pl_state_sts                               (pl_state_sts),
        .pl_max_speedmode                           (pl_max_speedmode),
        .pl_speedmode                               (pl_speedmode),
        .pl_lnk_cfg                                 (pl_lnk_cfg),

        // Sideband DVSEC status
        .UCIe_Link_DVSEC_UCIe_Link_Capability_7to4  (reg_Max_Link_Speed_cap),
        .UCIe_Link_DVSEC_UCIe_Link_Status_17to11    (reg_Link_Speed_enable_status),
        .UCIe_Link_DVSEC_UCIe_Link_Status_10to7     (reg_Link_Width_enable_status),

        // Sideband RDI message path
        .Link_Mgmt_Msg_Receive                      (rdi_msg_rcvd),
        .valid_r                                    (rdi_vld_rcvd),
        .Link_Mgmt_Msg_Send                         (rdi_msg_send),
        .valid_s                                    (rdi_vld_send),

        // Clock handshake
        .traffic_req                                (traffic_req),
        .clk_handshake_done                         (clk_handshake_done),
        .sticky_sb_pattern_detected                 (sticky_sb_pattern_detected),

        // MainBand interface
        .lclk_g                                     (rdi_lclk_g),
        .stall_done                                 (stall_done_w),
        .pl_error                                   (mb_valid_frame_error),

        // LTSM interface
        .state_sts                                  (current_ltsm_state),
        .phy_start_ucie_link_training_ctrl_out      (phy_start_ucie_link_training_ctrl_out),
        .rdi_state                                  (rdi_state_w)
    );

endmodule
