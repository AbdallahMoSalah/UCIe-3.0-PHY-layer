import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// LTSM_WRAPPER
// =============================================================================
// Top-level wrapper for Link Training State Machine (LTSM).
// Integrates completed submodules: RESET, SBINIT, MBINIT, MBTRAIN (wrapper_MBTRAIN),
// ACTIVE, and ltsm_controller.
// =============================================================================

module ltsm_wrapper
#(
    parameter int CLK_FRQ_HZ         = 800000000,
    parameter int MAX_VAL_VREF_CODE  = 127,
    parameter int MAX_DATA_VREF_CODE = 127,
    parameter int MAX_PI_PHASE_CODE  = 127,
    parameter int MAX_DESKEW_CODE    = 127
)
(
    input  logic        clk,
    input  logic        rst_n,

    // =========================================================================
    // Control / Status Configuration & RDI
    // =========================================================================
    input  logic [3:0]  state_req,
    input  logic        reset_req,
    input  logic        phyretrain_req,
    input  logic        trainerror_req,
    input  logic        mbtrain_speedidle_req,

    output LTSM_state_e current_ltsm_state,
    output state_n_e    current_ltsm_state_n,

    // Triggers
    input  logic        phy_start_ucie_link_training_ctrl_out,
    input  logic        Adapter_training_req,
    input  logic        sb_det_pattern_rcvd,

    // SPMW Strap
    input  logic        SPMW,

    // =========================================================================
    // Capability interface (Discrete Normal Ports)
    // =========================================================================
    // Local Inputs (from registers)
    input  logic        reg_phy_x8_mode_ctrl,
    input  logic [3:0]  local_max_speed,
    input  logic        local_sbfe,
    input  logic        reg_TARR_support_local_cap,
    input  logic        reg_L2SPD_support_local_cap,
    input  logic        reg_PSPT_support_local_cap,
    input  logic        local_so,
    input  logic        reg_PMO_support_local_cap,
    input  logic [2:0]  reg_Max_Link_Width_cap,
    input  logic [3:0]  reg_Max_Link_Speed_cap,
    input  logic        local_mtp,

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

    // From Link
    input  logic        reg_L2SPD_support_local_ctrl,
    input  logic        reg_PSPT_support_local_ctrl,
    input  logic [3:0]  reg_Target_Link_Width_ctrl,
    input  logic [3:0]  reg_Target_Link_Speed_ctrl,

    // -------------------------------
    // --------- STATUS REG ----------
    // -------------------------------
    // To RF
    output logic        reg_Clock_Phase_enable_status,
    output logic        reg_Clock_mode_enable_status,
    output logic        reg_TARR_enable_status,
    output logic [3:0]  reg_Link_Width_enable_status,
    output logic [3:0]  reg_Link_Speed_enable_status,
    output logic        reg_PMO_enable_status,
    output logic        reg_L2SPD_enable_status,
    output logic        reg_PSPT_enable_status,
    output logic        link_training_retraining,
    output logic        link_status,

    // =========================================================================
    // D2C point-test interface
    // =========================================================================
    output logic        local_tx_pt_en,
    output logic        partner_tx_pt_en,
    output logic [2:0]  d2c_pattern_setup,
    output logic [1:0]  d2c_data_pattern_sel,
    output logic        d2c_pattern_mode,
    output logic [1:0]  d2c_compare_setup,

    input  logic [15:0] d2c_perlane_pass,
    input  logic        local_test_d2c_done,
    input  logic        partner_test_d2c_done,

    // =========================================================================
    // RX / TX sideband message bus
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

    // =========================================================================
    // Unified Mainband Outputs (Muxed / Latched)
    // =========================================================================
    output logic        mb_tx_pattern_en,
    output logic [2:0]  mb_tx_pattern_setup,
    output logic [1:0]  mb_tx_data_pattern_sel,
    output logic        mb_tx_val_pattern_sel,
    output logic        mb_rx_compare_en,
    output logic [1:0]  mb_rx_compare_setup,
    output logic        clear_error_req,
    output logic [2:0]  mbinit_rx_data_lane_mask,
    output logic [2:0]  mbinit_tx_data_lane_mask,

    // =========================================================================
    // Unified Mainband Inputs
    // =========================================================================
    input  logic [15:0] mb_rx_perlane_pass,
    input  logic        mb_tx_pattern_count_done,

    // =========================================================================
    // Substate Discrete Outputs/Inputs
    // =========================================================================
    output logic        mb_lane_reversal_req,
    input  logic        repairclk_rtrk_pass,
    input  logic        repairclk_rckn_pass,
    input  logic        repairclk_rckp_pass,
    input  logic        repairval_RVLD_L_pass,

    // =========================================================================
    // Sideband Block controls (SBINIT)
    // =========================================================================
    input  logic        sb_iter_done,
    output logic        sbinit_pattern_mode,
    output logic        sb_det_pattern_req,
    output logic [2:0]  sbinit_req_iter_count,

    // =========================================================================
    // ACTIVE state interface
    // =========================================================================
    input  RDI_state    rdi_state,

    // =========================================================================
    // Exposed Handshakes for Unimplemented States (PHYRETRAIN, L1, L2, TRAINERROR)
    // =========================================================================
    output logic        phyretrain_en,
    input  logic        phyretrain_done,

    output logic        l1_en,
    input  logic        l1_done,

    output logic        l2_en,
    input  logic        l2_done,

    output logic        trainerror_en,
    input  logic        trainerror_done,

    // =========================================================================
    // Exposed Handshakes & Interface for MBTRAIN (Unimplemented State)
    // =========================================================================
    output logic        mbtrain_en,
    input  logic        mbtrain_done,
    input  logic        mbtrain_error,
    input  state_n_e    mbtrain_state_n,

    // MBTRAIN Sideband interface
    input  logic        mbtrain_tx_valid,
    input  msg_no_e     mbtrain_tx_msg_id,
    input  logic [15:0] mbtrain_tx_MsgInfo,
    input  logic [63:0] mbtrain_tx_data_Field,

    // MBTRAIN Mainband interface
    input  logic        mbtrain_mb_tx_pattern_en,
    input  logic [2:0]  mbtrain_mb_tx_pattern_setup,
    input  logic [1:0]  mbtrain_mb_tx_data_pattern_sel,
    input  logic        mbtrain_mb_tx_val_pattern_sel,
    input  logic        mbtrain_mb_rx_compare_en,
    input  logic [1:0]  mbtrain_mb_rx_compare_setup,
    input  logic        mbtrain_clear_error_req,
    input  logic        mbtrain_mb_lane_reversal_req,

    // MBTRAIN D2C interface
    input  logic        mbtrain_local_tx_pt_en,
    input  logic        mbtrain_partner_tx_pt_en,
    input  logic [2:0]  mbtrain_d2c_pattern_setup,
    input  logic [1:0]  mbtrain_d2c_data_pattern_sel,
    input  logic        mbtrain_d2c_pattern_mode,
    input  logic [1:0]  mbtrain_d2c_compare_setup,

    // =========================================================================
    // Watchdog and Settle Timers
    // =========================================================================
    output logic        timer_enable,
    output logic        timer_rst_n,
    input  logic        timer_timeout_expired,

    output logic        analog_settle_timer_en,
    input  logic        analog_settle_time_done,

    // =========================================================================
    // Status Log Registers (to RF)
    // =========================================================================
    output logic [7:0]  log0_state_n,
    output logic        log0_lane_reversal,
    output logic        log0_width_degrade,
    output logic [7:0]  log0_state_n_minus_1,
    output logic [7:0]  log0_state_n_minus_2,
    output logic [7:0]  log1_state_n_minus_3,

    output logic        log0_state_n_valid,
    output logic        log0_lane_reversal_valid,
    output logic        log0_width_degrade_valid,
    output logic        log0_state_n_minus_1_valid,
    output logic        log0_state_n_minus_2_valid,
    output logic        log1_state_n_minus_3_valid,

    output logic        log1_state_timeout_occ,
    output logic        log1_sideband_timeout_occ,
    output logic        log1_remote_link_error,
    output logic        log1_internal_error,

    output logic        log1_state_timeout_occ_valid,
    output logic        log1_sideband_timeout_occ_valid,
    output logic        log1_remote_link_error_valid,
    output logic        log1_internal_error_valid
);

    // =========================================================================
    // INTERNAL WIRES
    // =========================================================================
    // State Enables & Dones
    logic reset_en, reset_done;
    logic sbinit_en, sbinit_done;
    logic mbinit_en, mbinit_done, mbinit_error;
    logic linkinit_en, linkinit_done;
    logic active_en;

    // ACTIVE module next state outputs
    ltsm_ctrl_state_e active_next_ltsm_state;
    logic active_error;

    // Submodule Sideband TX wires
    logic        sbinit_tx_valid;
    msg_no_e     sbinit_tx_msg_id;
    logic [15:0] sbinit_tx_MsgInfo;
    logic [63:0] sbinit_tx_data_Field;

    logic        mbinit_tx_valid;
    msg_no_e     mbinit_tx_msg_id;
    logic [15:0] mbinit_tx_MsgInfo;
    logic [63:0] mbinit_tx_data_Field;

    // Submodule Mainband wires
    logic        mbinit_mb_tx_pattern_en;
    logic [2:0]  mbinit_mb_tx_pattern_setup;
    logic [1:0]  mbinit_mb_tx_data_pattern_sel;
    logic        mbinit_mb_tx_val_pattern_sel;
    logic        mbinit_mb_rx_compare_en;
    logic [1:0]  mbinit_mb_rx_compare_setup;
    logic        mbinit_clear_error_req;
    logic        mbinit_mb_lane_reversal_req;

    // Submodule D2C wires
    logic        mbinit_local_tx_pt_en;
    logic        mbinit_partner_tx_pt_en;
    logic [2:0]  mbinit_d2c_pattern_setup;
    logic [1:0]  mbinit_d2c_data_pattern_sel;
    logic        mbinit_d2c_pattern_mode;
    logic [1:0]  mbinit_d2c_compare_setup;

    // Submodule Status Capability wires
    logic        mbinit_Clock_Phase_enable_status;
    logic        mbinit_Clock_mode_enable_status;
    logic        mbinit_TARR_enable_status;
    logic [3:0]  mbinit_Link_Width_enable_status;
    logic [3:0]  mbinit_Link_Speed_enable_status;
    logic        mbinit_PMO_enable_status;
    logic        mbinit_L2SPD_enable_status;
    logic        mbinit_PSPT_enable_status;

    // Submodule Error Log state_n values
    state_n_e    mbinit_state_n;

    // Watchdog/Settle timer feedback routing

    // =========================================================================
    // LTSM CONTROLLER INSTANTIATION
    // =========================================================================
    ltsm_controller u_controller (
        .clk(clk),
        .rst_n(rst_n),

        // FSM Ports
        .state_req(state_req),
        .reset_req(reset_req),
        .phyretrain_req(phyretrain_req),
        .trainerror_req(trainerror_req),
        .mbtrain_speedidle_req(mbtrain_speedidle_req),
        .active_next_ltsm_state(active_next_ltsm_state),
        .active_error(active_error),
        .current_ltsm_state(current_ltsm_state),
        .current_ltsm_state_n(current_ltsm_state_n),
        .link_training_retraining(link_training_retraining),
        .link_status(link_status),

        // Submodule enables / handshakes
        .reset_en(reset_en),
        .reset_done(reset_done),

        .sbinit_en(sbinit_en),
        .sbinit_done(sbinit_done),

        .mbinit_en(mbinit_en),
        .mbinit_done(mbinit_done),
        .mbinit_error(mbinit_error),

        .mbtrain_en(mbtrain_en),
        .mbtrain_done(mbtrain_done),
        .mbtrain_error(mbtrain_error),

        .linkinit_en(linkinit_en),
        .linkinit_done(linkinit_done),

        .active_en(active_en),

        .phyretrain_en(phyretrain_en),
        .phyretrain_done(phyretrain_done),

        .l1_en(l1_en),
        .l1_done(l1_done),

        .l2_en(l2_en),
        .l2_done(l2_done),

        .trainerror_en(trainerror_en),
        .trainerror_done(trainerror_done),

        // Watchdog Timer
        .timeout_timer_en(timer_enable),
        .timer_rst_n(timer_rst_n),
        .timeout_8ms_occured(timer_timeout_expired),

        // Sideband TX
        .sb_tx_valid(sb_tx_valid),
        .sb_tx_msg_id(sb_tx_msg_id),
        .sb_tx_MsgInfo(sb_tx_MsgInfo),
        .sb_tx_data_Field(sb_tx_data_Field),

        .sbinit_tx_valid(sbinit_tx_valid),
        .sbinit_tx_msg_id(sbinit_tx_msg_id),
        .sbinit_tx_MsgInfo(sbinit_tx_MsgInfo),
        .sbinit_tx_data_Field(sbinit_tx_data_Field),

        .mbinit_tx_valid(mbinit_tx_valid),
        .mbinit_tx_msg_id(mbinit_tx_msg_id),
        .mbinit_tx_MsgInfo(mbinit_tx_MsgInfo),
        .mbinit_tx_data_Field(mbinit_tx_data_Field),

        .mbtrain_tx_valid(mbtrain_tx_valid),
        .mbtrain_tx_msg_id(mbtrain_tx_msg_id),
        .mbtrain_tx_MsgInfo(mbtrain_tx_MsgInfo),
        .mbtrain_tx_data_Field(mbtrain_tx_data_Field),

        // Mainband
        .mb_tx_pattern_en(mb_tx_pattern_en),
        .mb_tx_pattern_setup(mb_tx_pattern_setup),
        .mb_tx_data_pattern_sel(mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel(mb_tx_val_pattern_sel),
        .mb_rx_compare_en(mb_rx_compare_en),
        .mb_rx_compare_setup(mb_rx_compare_setup),
        .clear_error_req(clear_error_req),
        .mb_lane_reversal_req(mb_lane_reversal_req),

        .mbinit_mb_tx_pattern_en(mbinit_mb_tx_pattern_en),
        .mbinit_mb_tx_pattern_setup(mbinit_mb_tx_pattern_setup),
        .mbinit_mb_tx_data_pattern_sel(mbinit_mb_tx_data_pattern_sel),
        .mbinit_mb_tx_val_pattern_sel(mbinit_mb_tx_val_pattern_sel),
        .mbinit_mb_rx_compare_en(mbinit_mb_rx_compare_en),
        .mbinit_mb_rx_compare_setup(mbinit_mb_rx_compare_setup),
        .mbinit_clear_error_req(mbinit_clear_error_req),
        .mbinit_mb_lane_reversal_req(mbinit_mb_lane_reversal_req),

        .mbtrain_mb_tx_pattern_en(mbtrain_mb_tx_pattern_en),
        .mbtrain_mb_tx_pattern_setup(mbtrain_mb_tx_pattern_setup),
        .mbtrain_mb_tx_data_pattern_sel(mbtrain_mb_tx_data_pattern_sel),
        .mbtrain_mb_tx_val_pattern_sel(mbtrain_mb_tx_val_pattern_sel),
        .mbtrain_mb_rx_compare_en(mbtrain_mb_rx_compare_en),
        .mbtrain_mb_rx_compare_setup(mbtrain_mb_rx_compare_setup),
        .mbtrain_clear_error_req(mbtrain_clear_error_req),
        .mbtrain_mb_lane_reversal_req(mbtrain_mb_lane_reversal_req),

        // D2C PT Mux
        .local_tx_pt_en(local_tx_pt_en),
        .partner_tx_pt_en(partner_tx_pt_en),
        .d2c_pattern_setup(d2c_pattern_setup),
        .d2c_data_pattern_sel(d2c_data_pattern_sel),
        .d2c_pattern_mode(d2c_pattern_mode),
        .d2c_compare_setup(d2c_compare_setup),

        .mbinit_local_tx_pt_en(mbinit_local_tx_pt_en),
        .mbinit_partner_tx_pt_en(mbinit_partner_tx_pt_en),
        .mbinit_d2c_pattern_setup(mbinit_d2c_pattern_setup),
        .mbinit_d2c_data_pattern_sel(mbinit_d2c_data_pattern_sel),
        .mbinit_d2c_pattern_mode(mbinit_d2c_pattern_mode),
        .mbinit_d2c_compare_setup(mbinit_d2c_compare_setup),

        .mbtrain_local_tx_pt_en(mbtrain_local_tx_pt_en),
        .mbtrain_partner_tx_pt_en(mbtrain_partner_tx_pt_en),
        .mbtrain_d2c_pattern_setup(mbtrain_d2c_pattern_setup),
        .mbtrain_d2c_data_pattern_sel(mbtrain_d2c_data_pattern_sel),
        .mbtrain_d2c_pattern_mode(mbtrain_d2c_pattern_mode),
        .mbtrain_d2c_compare_setup(mbtrain_d2c_compare_setup),

        // Configurations
        .reg_Max_Link_Width_cap(reg_Max_Link_Width_cap),

        // Capability Status registers
        .reg_Clock_Phase_enable_status(reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status(reg_Clock_mode_enable_status),
        .reg_TARR_enable_status(reg_TARR_enable_status),
        .reg_Link_Width_enable_status(reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status(reg_Link_Speed_enable_status),
        .reg_PMO_enable_status(reg_PMO_enable_status),
        .reg_L2SPD_enable_status(reg_L2SPD_enable_status),
        .reg_PSPT_enable_status(reg_PSPT_enable_status),

        .mbinit_Clock_Phase_enable_status(mbinit_Clock_Phase_enable_status),
        .mbinit_Clock_mode_enable_status(mbinit_Clock_mode_enable_status),
        .mbinit_TARR_enable_status(mbinit_TARR_enable_status),
        .mbinit_Link_Width_enable_status(mbinit_Link_Width_enable_status),
        .mbinit_Link_Speed_enable_status(mbinit_Link_Speed_enable_status),
        .mbinit_PMO_enable_status(mbinit_PMO_enable_status),
        .mbinit_L2SPD_enable_status(mbinit_L2SPD_enable_status),
        .mbinit_PSPT_enable_status(mbinit_PSPT_enable_status),

        // Log registers
        .mbinit_state_n(mbinit_state_n),
        .mbtrain_state_n(mbtrain_state_n),

        .log0_state_n(log0_state_n),
        .log0_lane_reversal(log0_lane_reversal),
        .log0_width_degrade(log0_width_degrade),
        .log0_state_n_minus_1(log0_state_n_minus_1),
        .log0_state_n_minus_2(log0_state_n_minus_2),
        .log1_state_n_minus_3(log1_state_n_minus_3),

        .log0_state_n_valid(log0_state_n_valid),
        .log0_lane_reversal_valid(log0_lane_reversal_valid),
        .log0_width_degrade_valid(log0_width_degrade_valid),
        .log0_state_n_minus_1_valid(log0_state_n_minus_1_valid),
        .log0_state_n_minus_2_valid(log0_state_n_minus_2_valid),
        .log1_state_n_minus_3_valid(log1_state_n_minus_3_valid),

        .log1_state_timeout_occ(log1_state_timeout_occ),
        .log1_sideband_timeout_occ(log1_sideband_timeout_occ),
        .log1_remote_link_error(log1_remote_link_error),
        .log1_internal_error(log1_internal_error),

        .log1_state_timeout_occ_valid(log1_state_timeout_occ_valid),
        .log1_sideband_timeout_occ_valid(log1_sideband_timeout_occ_valid),
        .log1_remote_link_error_valid(log1_remote_link_error_valid),
        .log1_internal_error_valid(log1_internal_error_valid)
    );

    // =========================================================================
    // SUBMODULE INSTANTIATIONS
    // =========================================================================

    // 1. RESET state module
    RESET #(
        .CLK_FRQ_HZ(CLK_FRQ_HZ)
    ) u_reset (
        .clk(clk),
        .rst_n(rst_n),
        .phy_start_ucie_link_training_ctrl_out(phy_start_ucie_link_training_ctrl_out),
        .Adapter_training_req(Adapter_training_req),
        .sb_det_pattern_rcvd(sb_det_pattern_rcvd),
        .RESET_enable(reset_en),
        .RESET_state_done(reset_done)
    );

    // 2. SBINIT state module
    SBINIT #(
        .CLK_FRQ_HZ(CLK_FRQ_HZ)
    ) u_sbinit (
        .clk(clk),
        .rst_n(rst_n),
        .sbinit_enable(sbinit_en),
        .sbinit_done(sbinit_done),
        .sbinit_error(mbtrain_error), // Route or wire to controller error
        .sb_rx_valid(sb_rx_valid),
        .sb_rx_msg_id(sb_rx_msg_id),
        .iter_done(sb_iter_done),
        .sb_det_pattern_rcvd(sb_det_pattern_rcvd),
        .sb_tx_valid(sbinit_tx_valid),
        .sb_tx_msg_id(sbinit_tx_msg_id),
        .sbinit_pattern_mode(sbinit_pattern_mode),
        .sb_det_pattern_req(sb_det_pattern_req),
        .req_iter_count(sbinit_req_iter_count),
        .ltsm_rdy(sb_ltsm_rdy),
        .global_error(timer_timeout_expired)
    );

    // 3. MBINIT Top module
    MBINIT #(
        .CLK_FRQ_HZ(CLK_FRQ_HZ)
    ) u_mbinit (
        .clk(clk),
        .rst_n(rst_n),
        .mbinit_enable(mbinit_en),
        .mbinit_done(mbinit_done),
        .mbinit_error(mbinit_error),
        .mbinit_state_n(mbinit_state_n),
        .SPMW(SPMW),

        // Configs
        .reg_phy_x8_mode_ctrl(reg_phy_x8_mode_ctrl),
        .local_sbfe(local_sbfe),
        .reg_TARR_support_local_cap(reg_TARR_support_local_cap),
        .reg_L2SPD_support_local_cap(reg_L2SPD_support_local_cap),
        .reg_PSPT_support_local_cap(reg_PSPT_support_local_cap),
        .local_so(local_so),
        .reg_PMO_support_local_cap(reg_PMO_support_local_cap),
        .reg_Max_Link_Width_cap(reg_Max_Link_Width_cap),
        .reg_Max_Link_Speed_cap(reg_Max_Link_Speed_cap),
        .local_mtp(local_mtp),
        .reg_Supported_TX_Vswing(reg_Supported_TX_Vswing),
        .reg_so(reg_so),
        .reg_mtp(reg_mtp),
        .reg_Module_ID(reg_Module_ID),
        .reg_Clock_Phase_cap(reg_Clock_Phase_cap),
        .reg_Clock_mode_cap(reg_Clock_mode_cap),
        .reg_TARR_support_local_ctrl(reg_TARR_support_local_ctrl),
        .reg_PMO_support_local_ctrl(reg_PMO_support_local_ctrl),
        .reg_Clock_Phase_ctrl(reg_Clock_Phase_ctrl),
        .reg_Clock_mode_ctrl(reg_Clock_mode_ctrl),
        .reg_L2SPD_support_local_ctrl(reg_L2SPD_support_local_ctrl),
        .reg_PSPT_support_local_ctrl(reg_PSPT_support_local_ctrl),
        .reg_Target_Link_Width_ctrl(reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl(reg_Target_Link_Speed_ctrl),

        // Status capabilities outputs
        .reg_Clock_Phase_enable_status(mbinit_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status(mbinit_Clock_mode_enable_status),
        .reg_TARR_enable_status(mbinit_TARR_enable_status),
        .reg_Link_Width_enable_status(mbinit_Link_Width_enable_status),
        .reg_Link_Speed_enable_status(mbinit_Link_Speed_enable_status),
        .reg_PMO_enable_status(mbinit_PMO_enable_status),
        .reg_L2SPD_enable_status(mbinit_L2SPD_enable_status),
        .reg_PSPT_enable_status(mbinit_PSPT_enable_status),

        // D2C point test interface (directly broadcasted)
        .local_tx_pt_en(mbinit_local_tx_pt_en),
        .partner_tx_pt_en(mbinit_partner_tx_pt_en),
        .d2c_pattern_setup(mbinit_d2c_pattern_setup),
        .d2c_data_pattern_sel(mbinit_d2c_data_pattern_sel),
        .d2c_pattern_mode(mbinit_d2c_pattern_mode),
        .d2c_compare_setup(mbinit_d2c_compare_setup),
        .d2c_perlane_pass(d2c_perlane_pass),
        .local_test_d2c_done(local_test_d2c_done),
        .partner_test_d2c_done(partner_test_d2c_done),

        // RX/TX sideband message bus
        .sb_rx_valid(sb_rx_valid),
        .sb_rx_msg_id(sb_rx_msg_id),
        .sb_rx_MsgInfo(sb_rx_MsgInfo),
        .sb_rx_data_Field(sb_rx_data_Field),
        .sb_tx_valid(mbinit_tx_valid),
        .sb_ltsm_rdy(sb_ltsm_rdy),
        .sb_tx_msg_id(mbinit_tx_msg_id),
        .sb_tx_MsgInfo(mbinit_tx_MsgInfo),
        .sb_tx_data_Field(mbinit_tx_data_Field),

        // Unified Mainband Outputs
        .mb_tx_pattern_en(mbinit_mb_tx_pattern_en),
        .mb_tx_pattern_setup(mbinit_mb_tx_pattern_setup),
        .mb_tx_data_pattern_sel(mbinit_mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel(mbinit_mb_tx_val_pattern_sel),
        .mb_rx_compare_en(mbinit_mb_rx_compare_en),
        .mb_rx_compare_setup(mbinit_mb_rx_compare_setup),
        .clear_error_req(mbinit_clear_error_req),
        .mbinit_rx_data_lane_mask(mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(mbinit_tx_data_lane_mask),

        // Unified Mainband Inputs
        .mb_rx_perlane_pass(mb_rx_perlane_pass),
        .mb_tx_pattern_count_done(mb_tx_pattern_count_done),

        // Substate Discrete Outputs/Inputs
        .mb_lane_reversal_req(mbinit_mb_lane_reversal_req),
        .repairclk_rtrk_pass(repairclk_rtrk_pass),
        .repairclk_rckn_pass(repairclk_rckn_pass),
        .repairclk_rckp_pass(repairclk_rckp_pass),
        .repairval_RVLD_L_pass(repairval_RVLD_L_pass),

        // Watchdog Timer / Global Error
        .global_error(timer_timeout_expired)
    );

    // 4. LINKINIT state module
    linkinit u_linkinit (
        .clk(clk),
        .rst_n(rst_n),
        .rdi_state_sts(rdi_state),
        .timeout_expired(timer_timeout_expired),
        .Linkinit_enable(linkinit_en),
        .start_ucie_link_training(phy_start_ucie_link_training_ctrl_out),
        .linkinit_done(linkinit_done),
        .timeout_rst_n(),
        .enable_timeout(),
        .linkinit_error()
    );

    // MBTRAIN is now unimplemented at this level, and its signals are routed as top-level ports.
    // We default analog_settle_timer_en to 1'b0 here since it was driven by mbtrain previously.
    assign analog_settle_timer_en = 1'b0;

    // 5. ACTIVE state module
    ACTIVE u_active (
        .clk(clk),
        .rst_n(rst_n),
        .active_enable(active_en),
        .rdi_state(rdi_state),
        .Start_UCIe_Link_Training(phy_start_ucie_link_training_ctrl_out),
        .active_error(active_error),
        .next_ltsm_state(active_next_ltsm_state)
    );

endmodule
