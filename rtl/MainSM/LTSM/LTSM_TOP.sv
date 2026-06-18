import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// LTSM_TOP — LTSM + mainband_ltsm_interface (signal decode/translate)
// =============================================================================
// Bundles the link-training state machine (LTSM) with the project's
// mainband_ltsm_interface (rtl/MainBand_RD/mainband_ltsm_interface.sv), which
// translates the LTSM mainband CONTROL/STATUS signals into the unit_mb_die
// low-level control/result signals.
//
// The MainBand_RD die is NOT instantiated here — it is connected in the
// testbench. LTSM_TOP therefore exposes the die-facing control (i_*) outputs and
// result (o_*) inputs of the interface, plus the sideband bus, so the TB can wire
// one unit_mb_die (and a SideBand_Top) per LTSM_TOP and cross-connect two dies.
//
// LTSM<->interface signal sourcing (a few interface inputs are derived here):
//   * active           <= (current_ltsm_state == ACTIVE)
//   * mb_rx_data_en    <= LTSM mb_rx_data_lane_sel
//   * mb_rx_valid_en   <= LTSM mb_rx_val_lane_sel
//   * mb_rx_vcomp_mode <= LTSM mb_rx_pattern_mode            [ASSUMPTION]
//   * reg_lane_mask    <= top-level RF input (extra per-lane compare mask)
// And two LTSM inputs the interface does not produce:
//   * mb_rx_val_pass   <= interface repairval_RVLD_L_pass
//   * mb_rx_aggr_pass  <= 1'b1 (interface models per-lane/valid/clk, not aggregate) [ASSUMPTION]
// =============================================================================

module LTSM_TOP #(
    parameter int CLK_FRQ_HZ = 800000000,
    parameter int NUM_LANES  = 16
)(
    input  logic        clk,
    input  logic        rst_n,

    // =========================================================================
    // Status / observability
    // =========================================================================
    output LTSM_state_e current_ltsm_state,
    output state_n_e    current_mbtrain_substate,
    output logic        mbinit_error,
    output logic        active_error,
    output logic        timeout_8ms_occured,
    output logic [7:0]  log0_state_n,
    output logic        log0_lane_reversal,
    output logic        log0_width_degrade,
    output logic [7:0]  log0_state_n_minus_1,
    output logic [7:0]  log0_state_n_minus_2,
    output logic [7:0]  log1_state_n_minus_3,

    // =========================================================================
    // RESET-state triggers / strap
    // =========================================================================
    input  logic        phy_start_ucie_link_training_ctrl_out,
    input  logic        Adapter_training_req,
    input  logic        sb_det_pattern_rcvd,
    input  logic        SPMW,

    // =========================================================================
    // Capability configuration (to MBINIT)
    // =========================================================================
    input  logic        reg_phy_x8_mode_ctrl,
    input  logic        reg_TARR_support_local_cap,
    input  logic        reg_L2SPD_support_local_cap,
    input  logic        reg_PSPT_support_local_cap,
    input  logic        reg_PMO_support_local_cap,
    input  logic [3:0]  reg_Max_Link_Speed_cap,
    input  logic [4:0]  reg_Supported_TX_Vswing,
    input  logic        reg_so,
    input  logic        reg_mtp,
    input  logic [1:0]  reg_Module_ID,
    input  logic [1:0]  reg_Clock_Phase_cap,
    input  logic [1:0]  reg_Clock_mode_cap,
    input  logic        reg_TARR_support_local_ctrl,
    input  logic        reg_PMO_support_local_ctrl,
    input  logic        reg_Clock_Phase_ctrl,
    input  logic        reg_Clock_mode_ctrl,
    input  logic        reg_L2SPD_support_local_ctrl,
    input  logic        reg_PSPT_support_local_ctrl,
    input  logic [3:0]  reg_Target_Link_Width_ctrl,
    input  logic [3:0]  reg_Target_Link_Speed_ctrl,

    // Capability status (from MBINIT)
    output logic        reg_Clock_Phase_enable_status,
    output logic        reg_Clock_mode_enable_status,
    output logic        reg_TARR_enable_status,
    output logic [3:0]  reg_Link_Width_enable_status,
    output logic [3:0]  reg_Link_Speed_enable_status,
    output logic        reg_PMO_enable_status,
    output logic        reg_L2SPD_enable_status,
    output logic        reg_PSPT_enable_status,

    // D2C / comparison thresholds + per-lane compare mask
    input  logic [11:0] cfg_max_err_thresh_perlane,
    input  logic [15:0] cfg_max_err_thresh_aggr,
    input  logic [NUM_LANES-1:0] reg_lane_mask,

    // =========================================================================
    // Sideband message bus (to/from SideBand_Top)
    // =========================================================================
    input  logic        sb_rx_valid,
    input  msg_no_e     sb_rx_msg_id,
    input  logic [15:0] sb_rx_MsgInfo,
    input  logic [63:0] sb_rx_data_Field,
    output logic        sb_tx_valid,
    input  logic        sb_ltsm_rdy,
    output msg_no_e     sb_tx_msg_id,
    output logic [15:0] sb_tx_MsgInfo,
    output logic [63:0] sb_tx_data_Field,
    input  logic        sb_iter_done,
    output logic        sbinit_pattern_mode,
    output logic        sb_det_pattern_req,
    output logic [2:0]  sbinit_req_iter_count,

    // =========================================================================
    // RDI status
    // =========================================================================
    input  RDI_state    rdi_state,

    // =========================================================================
    // unit_mb_die-facing CONTROL outputs (from the interface)
    // =========================================================================
    output logic                 i_mapper_en,
    output logic [2:0]           i_width_deg_tx,
    output logic [2:0]           i_width_deg_rx,
    output logic [2:0]           i_lfsr_state,
    output logic                 i_reversal_en,
    output logic                 i_valid_pattern_en,
    output logic                 i_clk_pattern_en,
    output logic [2:0]           i_state,
    output logic                 demapper_en,
    output logic                 i_pcmp_enable,
    output logic                 i_pcmp_mode,
    output logic [NUM_LANES-1:0] i_pcmp_lane_mask,
    output logic [15:0]          i_pcmp_iter_count,
    output logic                 i_pcmp_pattern_mode,
    output logic                 i_pcmp_clear,
    output logic                 i_vcmp_enable,
    output logic                 i_vcmp_mode,
    output logic                 i_vcmp_clear,
    output logic                 i_clk_detector_en,
    output logic [NUM_LANES-1:0] i_rx_data_deser_en,
    output logic                 i_rx_valid_deser_en,

    // =========================================================================
    // unit_mb_die-facing RESULT inputs (to the interface)
    // =========================================================================
    input  logic                 o_lfsr_tx_done,
    input  logic                 o_valid_done,
    input  logic                 o_clk_done,
    input  logic                 o_pcmp_done,
    input  logic [NUM_LANES-1:0] o_pcmp_per_lane_pass,
    input  logic                 o_vcmp_done,
    input  logic                 o_vcmp_pass,
    input  logic                 o_valid_frame_error,
    input  logic                 o_clk_p_pass,
    input  logic                 o_clk_n_pass,
    input  logic                 o_track_pass
);

    // =========================================================================
    // LTSM mainband CONTROL outputs -> interface (translated subset)
    // =========================================================================
    logic        w_mb_tx_pattern_en;
    logic [2:0]  w_mb_tx_pattern_setup;
    logic [1:0]  w_mb_tx_data_pattern_sel;
    logic        w_mb_tx_val_pattern_sel;
    logic        w_mb_rx_compare_en;
    logic [1:0]  w_mb_rx_compare_setup;
    logic        w_clear_error_req;
    logic [2:0]  w_mb_rx_data_lane_mask;
    logic [2:0]  w_mb_tx_data_lane_mask;
    logic        w_mb_lane_reversal_req;
    logic        w_mb_tx_lfsr_rst;
    logic        w_mb_rx_lfsr_rst;
    logic        w_mb_rx_data_lane_sel;
    logic        w_mb_rx_val_lane_sel;
    logic        w_mb_rx_pattern_mode;

    // interface -> LTSM mainband STATUS inputs
    logic [NUM_LANES-1:0] w_mb_rx_perlane_pass;
    logic        w_mb_tx_pattern_count_done;
    logic        w_mb_rx_compare_done;
    logic        w_repairclk_rtrk_pass;
    logic        w_repairclk_rckn_pass;
    logic        w_repairclk_rckp_pass;
    logic        w_repairval_RVLD_L_pass;

    // derived interface inputs
    wire         w_active = (current_ltsm_state == ACTIVE);

    // =========================================================================
    // LTSM
    // =========================================================================
    LTSM_wrapper #(
        .CLK_FRQ_HZ (CLK_FRQ_HZ)
    ) u_ltsm (
        .clk   (clk),
        .rst_n (rst_n),

        .current_ltsm_state       (current_ltsm_state),
        .current_mbtrain_substate (current_mbtrain_substate),
        .mbinit_error             (mbinit_error),
        .active_error             (active_error),
        .timeout_8ms_occured      (timeout_8ms_occured),
        .log0_state_n             (log0_state_n),
        .log0_lane_reversal       (log0_lane_reversal),
        .log0_width_degrade       (log0_width_degrade),
        .log0_state_n_minus_1     (log0_state_n_minus_1),
        .log0_state_n_minus_2     (log0_state_n_minus_2),
        .log1_state_n_minus_3     (log1_state_n_minus_3),

        .phy_start_ucie_link_training_ctrl_out (phy_start_ucie_link_training_ctrl_out),
        .Adapter_training_req                  (Adapter_training_req),
        .sb_det_pattern_rcvd                   (sb_det_pattern_rcvd),
        .SPMW                                  (SPMW),

        .reg_phy_x8_mode_ctrl        (reg_phy_x8_mode_ctrl),
        .reg_TARR_support_local_cap  (reg_TARR_support_local_cap),
        .reg_L2SPD_support_local_cap (reg_L2SPD_support_local_cap),
        .reg_PSPT_support_local_cap  (reg_PSPT_support_local_cap),
        .reg_PMO_support_local_cap   (reg_PMO_support_local_cap),
        .reg_Max_Link_Speed_cap      (reg_Max_Link_Speed_cap),
        .reg_Supported_TX_Vswing     (reg_Supported_TX_Vswing),
        .reg_so                      (reg_so),
        .reg_mtp                     (reg_mtp),
        .reg_Module_ID               (reg_Module_ID),
        .reg_Clock_Phase_cap         (reg_Clock_Phase_cap),
        .reg_Clock_mode_cap          (reg_Clock_mode_cap),
        .reg_TARR_support_local_ctrl (reg_TARR_support_local_ctrl),
        .reg_PMO_support_local_ctrl  (reg_PMO_support_local_ctrl),
        .reg_Clock_Phase_ctrl        (reg_Clock_Phase_ctrl),
        .reg_Clock_mode_ctrl         (reg_Clock_mode_ctrl),
        .reg_L2SPD_support_local_ctrl(reg_L2SPD_support_local_ctrl),
        .reg_PSPT_support_local_ctrl (reg_PSPT_support_local_ctrl),
        .reg_Target_Link_Width_ctrl  (reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl  (reg_Target_Link_Speed_ctrl),

        .reg_Clock_Phase_enable_status (reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status  (reg_Clock_mode_enable_status),
        .reg_TARR_enable_status        (reg_TARR_enable_status),
        .reg_Link_Width_enable_status  (reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status  (reg_Link_Speed_enable_status),
        .reg_PMO_enable_status         (reg_PMO_enable_status),
        .reg_L2SPD_enable_status       (reg_L2SPD_enable_status),
        .reg_PSPT_enable_status        (reg_PSPT_enable_status),

        .cfg_max_err_thresh_perlane (cfg_max_err_thresh_perlane),
        .cfg_max_err_thresh_aggr    (cfg_max_err_thresh_aggr),

        .sb_rx_valid     (sb_rx_valid),
        .sb_rx_msg_id    (sb_rx_msg_id),
        .sb_rx_MsgInfo   (sb_rx_MsgInfo),
        .sb_rx_data_Field(sb_rx_data_Field),
        .sb_tx_valid     (sb_tx_valid),
        .sb_ltsm_rdy     (sb_ltsm_rdy),
        .sb_tx_msg_id    (sb_tx_msg_id),
        .sb_tx_MsgInfo   (sb_tx_MsgInfo),
        .sb_tx_data_Field(sb_tx_data_Field),
        .sb_iter_done          (sb_iter_done),
        .sbinit_pattern_mode   (sbinit_pattern_mode),
        .sb_det_pattern_req    (sb_det_pattern_req),
        .sbinit_req_iter_count (sbinit_req_iter_count),

        .rdi_state (rdi_state),

        // Mainband control -> interface (subset the interface consumes)
        .mb_tx_pattern_en       (w_mb_tx_pattern_en),
        .mb_tx_pattern_setup    (w_mb_tx_pattern_setup),
        .mb_tx_data_pattern_sel (w_mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel  (w_mb_tx_val_pattern_sel),
        .mb_rx_compare_en       (w_mb_rx_compare_en),
        .mb_rx_compare_setup    (w_mb_rx_compare_setup),
        .clear_error_req        (w_clear_error_req),
        .mb_rx_data_lane_mask   (w_mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask   (w_mb_tx_data_lane_mask),
        .mb_lane_reversal_req   (w_mb_lane_reversal_req),
        .mb_tx_lfsr_rst         (w_mb_tx_lfsr_rst),
        .mb_rx_lfsr_rst         (w_mb_rx_lfsr_rst),
        .mb_rx_data_lane_sel    (w_mb_rx_data_lane_sel),
        .mb_rx_val_lane_sel     (w_mb_rx_val_lane_sel),
        .mb_rx_pattern_mode     (w_mb_rx_pattern_mode),
        // (remaining LTSM mainband outputs are intentionally left unconnected —
        //  the project interface does not consume them)

        // Mainband status <- interface
        .mb_rx_perlane_pass      (w_mb_rx_perlane_pass),
        .mb_tx_pattern_count_done(w_mb_tx_pattern_count_done),
        .mb_rx_compare_done      (w_mb_rx_compare_done),
        .mb_rx_aggr_pass         (1'b1),                       // [ASSUMPTION] interface has no aggregate
        .mb_rx_val_pass          (w_repairval_RVLD_L_pass),    // = vcmp pass
        .repairclk_rtrk_pass     (w_repairclk_rtrk_pass),
        .repairclk_rckn_pass     (w_repairclk_rckn_pass),
        .repairclk_rckp_pass     (w_repairclk_rckp_pass),
        .repairval_RVLD_L_pass   (w_repairval_RVLD_L_pass)
    );

    // =========================================================================
    // mainband_ltsm_interface  (project signal decode/translate)
    // =========================================================================
    mainband_ltsm_interface #(
        .NUM_LANES (NUM_LANES)
    ) u_mb_if (
        // die-facing control out
        .i_mapper_en        (i_mapper_en),
        .i_width_deg_tx     (i_width_deg_tx),
        .i_width_deg_rx     (i_width_deg_rx),
        .i_lfsr_state       (i_lfsr_state),
        .i_reversal_en      (i_reversal_en),
        .i_valid_pattern_en (i_valid_pattern_en),
        .i_clk_pattern_en   (i_clk_pattern_en),
        .i_state            (i_state),
        .demapper_en        (demapper_en),
        .i_pcmp_enable      (i_pcmp_enable),
        .i_pcmp_mode        (i_pcmp_mode),
        .i_pcmp_lane_mask   (i_pcmp_lane_mask),
        .i_pcmp_iter_count  (i_pcmp_iter_count),
        .i_pcmp_pattern_mode(i_pcmp_pattern_mode),
        .i_pcmp_clear       (i_pcmp_clear),
        .i_vcmp_enable      (i_vcmp_enable),
        .i_vcmp_mode        (i_vcmp_mode),
        .i_vcmp_clear       (i_vcmp_clear),
        .i_clk_detector_en  (i_clk_detector_en),
        .i_rx_data_deser_en (i_rx_data_deser_en),
        .i_rx_valid_deser_en(i_rx_valid_deser_en),

        // die-facing results in
        .o_lfsr_tx_done      (o_lfsr_tx_done),
        .o_valid_done        (o_valid_done),
        .o_clk_done          (o_clk_done),
        .o_pcmp_done         (o_pcmp_done),
        .o_pcmp_per_lane_pass(o_pcmp_per_lane_pass),
        .o_vcmp_done         (o_vcmp_done),
        .o_vcmp_pass         (o_vcmp_pass),
        .o_valid_frame_error (o_valid_frame_error),
        .o_clk_p_pass        (o_clk_p_pass),
        .o_clk_n_pass        (o_clk_n_pass),
        .o_track_pass        (o_track_pass),

        .reg_lane_mask (reg_lane_mask),

        // LTSM control in
        .mb_tx_pattern_en      (w_mb_tx_pattern_en),
        .mb_tx_pattern_setup   (w_mb_tx_pattern_setup),
        .mb_tx_data_pattern_sel(w_mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel (w_mb_tx_val_pattern_sel),
        .mb_rx_compare_en      (w_mb_rx_compare_en),
        .mb_rx_compare_setup   (w_mb_rx_compare_setup),
        .clear_error_req       (w_clear_error_req),
        .mb_rx_data_lane_map   (w_mb_rx_data_lane_mask),
        .mb_tx_data_lane_map   (w_mb_tx_data_lane_mask),

        // LTSM status out
        .mb_rx_perlane_pass      (w_mb_rx_perlane_pass),
        .mb_tx_pattern_count_done(w_mb_tx_pattern_count_done),

        // discrete substate I/O
        .mb_lane_reversal_req (w_mb_lane_reversal_req),
        .active               (w_active),
        .mb_tx_lfsr_rst       (w_mb_tx_lfsr_rst),
        .mb_rx_lfsr_rst       (w_mb_rx_lfsr_rst),
        .mb_rx_vcomp_mode     (w_mb_rx_pattern_mode),         // [ASSUMPTION]
        .mb_rx_data_en        (w_mb_rx_data_lane_sel),
        .mb_rx_valid_en       (w_mb_rx_val_lane_sel),
        .repairclk_rtrk_pass  (w_repairclk_rtrk_pass),
        .repairclk_rckn_pass  (w_repairclk_rckn_pass),
        .repairclk_rckp_pass  (w_repairclk_rckp_pass),
        .repairval_RVLD_L_pass(w_repairval_RVLD_L_pass),
        .mb_rx_compare_done   (w_mb_rx_compare_done)
    );

endmodule
