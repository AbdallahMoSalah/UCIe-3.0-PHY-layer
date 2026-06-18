import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// LTSM  —  Step 1 integration top (MBTRAIN is a controller pass-through)
// =============================================================================
//     RESET -> SBINIT -> MBINIT -> (MBTRAIN) -> LINKINIT -> ACTIVE
//
// Contents:
//   * unit_ltsm_controller : minimal Step-1 FSM (enables + status + 8 ms timer ctrl)
//   * timeout_counter      : shared 8 ms watchdog (internal)
//   * RESET / SBINIT / MBINIT / LINKINIT / ACTIVE : real state blocks
//   * wrapper_D2C_PT_top   : real D2C point-test block (MBINIT.REPAIRMB)
//   * SB / MB output muxes  : route the active state's outputs out
//
// MBTRAIN is NOT instantiated here. The real MBTRAIN block (wrapper_MBTRAIN /
// wrapper_MBTRAIN_old) is interface-based (internal_ltsm_if modports) and is
// deliberately left out of this Step-1 integration so we don't have to bridge
// its interface yet. The controller still walks through the MBTRAIN state, but
// it is a pass-through: mbtrain_done is tied to mbtrain_en so the FSM enters and
// immediately advances to LINKINIT. The MB datapath is exercised by MBINIT.
// MBTRAIN will be re-integrated (with its internal_ltsm_if bridge) in a later step.
//
// D2C point test (wrapper_D2C_PT_top) is now used by MBINIT.REPAIRMB only; its
// enables/config come straight from MBINIT. The mainband control mux has two
// sources: the D2C point test (when active) and MBINIT-direct.
//
// Assumptions flagged for review:
//   * param_UCIe_S_x8 <= reg_phy_x8_mode_ctrl
//
// Deferred to later steps: MBTRAIN (interface bridge), PHYRETRAIN / L1 / L2 /
// TRAINERROR, capability-status latching, state/error logs.
// =============================================================================

module LTSM_wrapper #(
    parameter int CLK_FRQ_HZ         = 800000000,
    parameter int MAX_VAL_VREF_CODE  = 127,
    parameter int MAX_DATA_VREF_CODE = 127,
    parameter int MAX_PI_PHASE_CODE  = 127,
    parameter int MAX_DESKEW_CODE    = 127
)(
    input  logic        clk,
    input  logic        rst_n,

    // =========================================================================
    // Status / observability
    // =========================================================================
    output LTSM_state_e current_ltsm_state,
    output state_n_e    current_ltsm_state_n,
    output logic [7:0]  log0_state_n,
    output logic        log0_lane_reversal,
    output logic        log0_width_degrade,
    output logic [7:0]  log0_state_n_minus_1,
    output logic [7:0]  log0_state_n_minus_2,
    output logic [7:0]  log1_state_n_minus_3,

    // =========================================================================
    // RESET-state triggers
    // =========================================================================
    input  logic        phy_start_ucie_link_training_ctrl_out,
    input  logic        Adapter_training_req,
    input  logic        sb_det_pattern_rcvd,

    // SPMW strap
    input  logic        SPMW,

    // =========================================================================
    // Capability configuration (to MBINIT) — matches current MBINIT ports
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

    // Capability status (from MBINIT, passed through)
    output logic        reg_Clock_Phase_enable_status,
    output logic        reg_Clock_mode_enable_status,
    output logic        reg_TARR_enable_status,
    output logic [3:0]  reg_Link_Width_enable_status,
    output logic [3:0]  reg_Link_Speed_enable_status,
    output logic        reg_PMO_enable_status,
    output logic        reg_L2SPD_enable_status,
    output logic        reg_PSPT_enable_status,

    // D2C / comparison thresholds (from Register File)
    input  logic [11:0] cfg_max_err_thresh_perlane,
    input  logic [15:0] cfg_max_err_thresh_aggr,

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

    // SBINIT sideband pattern handshake (to SideBand_Top Link Controller)
    input  logic        sb_iter_done,
    output logic        sb_pattern_mode,
    output logic        sb_det_pattern_req,
    output logic [2:0]  sbinit_req_iter_count,

    // =========================================================================
    // Unified mainband control outputs (to mainband_ltsm_interface)
    // =========================================================================
    output logic        mb_tx_pattern_en,
    output logic [2:0]  mb_tx_pattern_setup,
    output logic [1:0]  mb_tx_data_pattern_sel,
    output logic        mb_tx_val_pattern_sel,
    output logic [1:0]  mb_tx_clk_pattern_sel,
    output logic        mb_rx_compare_en,
    output logic [1:0]  mb_rx_compare_setup,
    output logic        clear_error_req,
    output logic [2:0]  mb_rx_data_lane_mask,
    output logic [2:0]  mb_tx_data_lane_mask,
    output logic        mb_lane_reversal_req,

    // Lane selects + extended controls (D2C point test / MBTRAIN substates)
    output logic [1:0]  mb_tx_trk_lane_sel,
    output logic [1:0]  mb_tx_clk_lane_sel,
    output logic [1:0]  mb_tx_val_lane_sel,
    output logic [1:0]  mb_tx_data_lane_sel,
    output logic        mb_rx_trk_lane_sel,
    output logic        mb_rx_clk_lane_sel,
    output logic        mb_rx_val_lane_sel,
    output logic        mb_rx_data_lane_sel,
    output logic        mb_tx_lfsr_en,
    output logic        mb_tx_lfsr_rst,
    output logic        mb_rx_lfsr_en,
    output logic        mb_rx_lfsr_rst,
    output logic [2:0]  mb_rx_pattern_setup,
    output logic [1:0]  mb_rx_data_pattern_sel,
    output logic        mb_rx_val_pattern_sel,
    output logic        mb_rx_pattern_mode,
    output logic [15:0] mb_rx_burst_count,
    output logic [15:0] mb_rx_idle_count,
    output logic [15:0] mb_rx_iter_count,
    output logic        mb_tx_pattern_mode,
    output logic [15:0] mb_tx_burst_count,
    output logic [15:0] mb_tx_idle_count,
    output logic [15:0] mb_tx_iter_count,
    output logic        mb_tx_clk_sampling_en,
    output logic [1:0]  mb_tx_clk_sampling,
    output logic [11:0] mb_rx_max_err_thresh_perlane,
    output logic [15:0] mb_rx_max_err_thresh_aggr,

    // =========================================================================
    // Unified mainband status inputs (from mainband_ltsm_interface)
    // =========================================================================
    input  logic [15:0] mb_rx_perlane_pass,
    input  logic        mb_tx_pattern_count_done,
    input  logic        mb_rx_compare_done,
    input  logic        mb_rx_aggr_pass,
    input  logic        mb_rx_val_pass,
    input  logic        repairclk_rtrk_pass,
    input  logic        repairclk_rckn_pass,
    input  logic        repairclk_rckp_pass,
    input  logic        repairval_RVLD_L_pass,

    // =========================================================================
    // RDI status (LINKINIT / ACTIVE)
    // =========================================================================
    input  RDI_state    rdi_state
);

    // =========================================================================
    // CONTROLLER <-> SUBMODULE HANDSHAKES
    // =========================================================================
    logic reset_en,    reset_done;
    logic sbinit_en,   sbinit_done,  sbinit_error;
    logic mbinit_en,   mbinit_done,  mbinit_error;
    logic mbtrain_en,  mbtrain_done;
    logic linkinit_en, linkinit_done, linkinit_error;
    logic active_en,   active_error;
    logic phyretrain_en, phyretrain_done;
    logic l1_en,         l1_done;
    logic l2_en,         l2_done;
    logic trainerror_en, trainerror_done;

    logic timeout_timer_en, timer_rst_n;

    // =========================================================================
    // SBINIT sideband TX wires
    // =========================================================================
    logic     sbinit_tx_valid;
    msg_no_e  sbinit_tx_msg_id;

    // =========================================================================
    // MBINIT output wires
    // =========================================================================
    logic        mbinit_tx_valid;
    msg_no_e     mbinit_tx_msg_id;
    logic [15:0] mbinit_tx_MsgInfo;
    logic [63:0] mbinit_tx_data_Field;

    logic        mbinit_mb_tx_pattern_en;
    logic [2:0]  mbinit_mb_tx_pattern_setup;
    logic [1:0]  mbinit_mb_tx_data_pattern_sel;
    logic        mbinit_mb_tx_val_pattern_sel;
    logic        mbinit_mb_rx_compare_en;
    logic [1:0]  mbinit_mb_rx_compare_setup;
    logic        mbinit_clear_error_req;
    logic [2:0]  mbinit_rx_data_lane_mask;
    logic [2:0]  mbinit_tx_data_lane_mask;
    logic        mbinit_mb_lane_reversal_req;

    logic        mbinit_local_tx_pt_en;
    logic        mbinit_partner_tx_pt_en;
    logic [2:0]  mbinit_d2c_pattern_setup;
    logic [1:0]  mbinit_d2c_data_pattern_sel;
    logic        mbinit_d2c_pattern_mode;
    logic [1:0]  mbinit_d2c_compare_setup;
    logic [1:0]  mbinit_d2c_clk_sampling;
    logic [15:0] mbinit_d2c_burst_count;
    logic [15:0] mbinit_d2c_idle_count;
    logic [15:0] mbinit_d2c_iter_count;

    state_n_e    mbinit_state_n;

    logic        mbinit_reg_Clock_Phase_enable_status;
    logic        mbinit_reg_Clock_mode_enable_status;
    logic        mbinit_reg_TARR_enable_status;
    logic [3:0]  mbinit_reg_Link_Width_enable_status;
    logic [3:0]  mbinit_reg_Link_Speed_enable_status;
    logic        mbinit_reg_PMO_enable_status;
    logic        mbinit_reg_L2SPD_enable_status;
    logic        mbinit_reg_PSPT_enable_status;

    // =========================================================================
    // D2C wrapper output wires
    // =========================================================================
    logic [15:0] d2c_perlane_pass;
    logic        d2c_aggr_pass;
    logic        d2c_val_pass;
    logic        local_test_d2c_done;
    logic        partner_test_d2c_done;

    logic        d2c_tx_sb_msg_valid;
    logic [7:0]  d2c_tx_sb_msg;
    logic [15:0] d2c_tx_msginfo;
    logic [63:0] d2c_tx_data_field;

    logic [1:0]  d2c_mb_tx_trk_lane_sel, d2c_mb_tx_clk_lane_sel;
    logic [1:0]  d2c_mb_tx_val_lane_sel, d2c_mb_tx_data_lane_sel;
    logic        d2c_mb_rx_trk_lane_sel, d2c_mb_rx_clk_lane_sel;
    logic        d2c_mb_rx_val_lane_sel, d2c_mb_rx_data_lane_sel;
    logic        d2c_mb_tx_pattern_en;
    logic [2:0]  d2c_mb_tx_pattern_setup;
    logic [2:0]  d2c_mb_rx_pattern_setup;
    logic        d2c_mb_tx_lfsr_en, d2c_mb_tx_lfsr_rst;
    logic        d2c_mb_rx_lfsr_en, d2c_mb_rx_lfsr_rst;
    logic [15:0] d2c_mb_rx_iter_count, d2c_mb_rx_idle_count, d2c_mb_rx_burst_count;
    logic        d2c_mb_rx_pattern_mode;
    logic        d2c_mb_rx_val_pattern_sel;
    logic [1:0]  d2c_mb_rx_data_pattern_sel;
    logic        d2c_mb_rx_compare_en;
    logic [1:0]  d2c_mb_rx_compare_setup;
    logic [11:0] d2c_mb_rx_max_err_thresh_perlane;
    logic [15:0] d2c_mb_rx_max_err_thresh_aggr;
    logic        d2c_mb_tx_clk_sampling_en;
    logic [1:0]  d2c_mb_tx_clk_sampling;
    logic        d2c_mb_tx_pattern_mode;
    logic [15:0] d2c_mb_tx_burst_count, d2c_mb_tx_idle_count, d2c_mb_tx_iter_count;
    logic [1:0]  d2c_mb_tx_data_pattern_sel;
    logic        d2c_mb_tx_val_pattern_sel;

    // ACTIVE next-state (unused until L1/L2/PHYRETRAIN exits are added)
    ltsm_ctrl_state_e active_next_ltsm_state;

    // Sideband RX, 8-bit form for the D2C point test
    logic [7:0] sb_rx_msg_8;
    assign sb_rx_msg_8 = sb_rx_msg_id;

    // =========================================================================
    // STATE LOG REGISTERS (SHIFT & LATCH HISTORY)
    // =========================================================================
    state_n_e mbtrain_state_n;
    assign mbtrain_state_n = LOG_NOP;

    state_n_e current_log_state;
    always_comb begin
        case (current_ltsm_state)
            RESET:      current_log_state = LOG_RESET;
            SBINIT:     current_log_state = LOG_SBINIT;
            MBINIT:     current_log_state = mbinit_state_n;
            MBTRAIN:    current_log_state = mbtrain_state_n;
            LINKINIT:   current_log_state = LOG_LINKINIT;
            ACTIVE:     current_log_state = LOG_ACTIVE;
            PHYRETRAIN: current_log_state = LOG_PHYRETRAIN;
            L1, L2:     current_log_state = LOG_L1_L2;
            TRAINERROR: current_log_state = LOG_TRAINERROR;
            default:    current_log_state = LOG_RESET;
        endcase
    end

    logic [7:0] log0_state_n_reg;
    logic [7:0] log0_state_n_minus_1_reg;
    logic [7:0] log0_state_n_minus_2_reg;
    logic [7:0] log1_state_n_minus_3_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            log0_state_n_reg         <= 8'h00;
            log0_state_n_minus_1_reg <= 8'h00;
            log0_state_n_minus_2_reg <= 8'h00;
            log1_state_n_minus_3_reg <= 8'h00;
        end else begin
            if (current_log_state != log0_state_n_reg[4:0]) begin
                log0_state_n_reg         <= {3'b0, current_log_state};
                log0_state_n_minus_1_reg <= log0_state_n_reg;
                log0_state_n_minus_2_reg <= log0_state_n_minus_1_reg;
                log1_state_n_minus_3_reg <= log0_state_n_minus_2_reg;
            end
        end
    end

    assign log0_state_n         = log0_state_n_reg;
    assign log0_state_n_minus_1 = log0_state_n_minus_1_reg;
    assign log0_state_n_minus_2 = log0_state_n_minus_2_reg;
    assign log1_state_n_minus_3 = log1_state_n_minus_3_reg;

    assign log0_width_degrade   = (mb_tx_data_lane_mask != 3'b011);
    assign log0_lane_reversal   = mb_lane_reversal_req;

    assign current_ltsm_state_n = current_log_state;

    // =========================================================================
    // D2C POINT-TEST INPUTS (MBINIT.REPAIRMB only)
    // =========================================================================
    logic        d2cpt_local_tx_pt_en, d2cpt_partner_tx_pt_en;
    logic        d2cpt_local_rx_pt_en, d2cpt_partner_rx_pt_en;
    logic [1:0]  d2cpt_clk_sampling;
    logic [2:0]  d2cpt_pattern_setup;
    logic [1:0]  d2cpt_data_pattern_sel;
    logic        d2cpt_val_pattern_sel;
    logic        d2cpt_pattern_mode;
    logic [15:0] d2cpt_burst_count, d2cpt_idle_count, d2cpt_iter_count;
    logic [1:0]  d2cpt_compare_setup;
    logic [2:0]  d2cpt_rx_data_lane_mask;

    // Driven entirely by MBINIT now that MBTRAIN (and its sweep) is not integrated.
    assign d2cpt_local_tx_pt_en    = mbinit_local_tx_pt_en;
    assign d2cpt_partner_tx_pt_en  = mbinit_partner_tx_pt_en;
    assign d2cpt_local_rx_pt_en    = 1'b0;
    assign d2cpt_partner_rx_pt_en  = 1'b0;
    assign d2cpt_clk_sampling      = mbinit_d2c_clk_sampling;
    assign d2cpt_pattern_setup     = mbinit_d2c_pattern_setup;
    assign d2cpt_data_pattern_sel  = mbinit_d2c_data_pattern_sel;
    assign d2cpt_val_pattern_sel   = 1'b0;
    assign d2cpt_pattern_mode      = mbinit_d2c_pattern_mode;
    assign d2cpt_burst_count       = mbinit_d2c_burst_count;
    assign d2cpt_idle_count        = mbinit_d2c_idle_count;
    assign d2cpt_iter_count        = mbinit_d2c_iter_count;
    assign d2cpt_compare_setup     = mbinit_d2c_compare_setup;
    assign d2cpt_rx_data_lane_mask = mbinit_rx_data_lane_mask;

    // True while the D2C point test owns the mainband (MBINIT.REPAIRMB)
    logic d2c_active;
    assign d2c_active = d2cpt_local_tx_pt_en | d2cpt_partner_tx_pt_en;

    // =========================================================================
    // MBTRAIN / PHYRETRAIN / L1 / L2 / TRAINERROR PASS-THROUGH
    // =========================================================================
    // These states are not instantiated. They are implemented as pass-throughs
    // by tying the done output directly to the enable input.
    assign mbtrain_done             = mbtrain_en;
    assign current_mbtrain_substate = LOG_NOP;
    assign phyretrain_done          = phyretrain_en;
    assign l1_done                  = l1_en;
    assign l2_done                  = l2_en;
    assign trainerror_done          = trainerror_en;

    // =========================================================================
    // CONTROLLER
    // =========================================================================
    unit_ltsm_controller u_controller (
        .clk                 (clk),
        .rst_n               (rst_n),
        .reset_en            (reset_en),
        .reset_done          (reset_done),
        .sbinit_en           (sbinit_en),
        .sbinit_done         (sbinit_done),
        .mbinit_en           (mbinit_en),
        .mbinit_done         (mbinit_done),
        .mbtrain_en          (mbtrain_en),
        .mbtrain_done        (mbtrain_done),
        .linkinit_en         (linkinit_en),
        .linkinit_done       (linkinit_done),
        .active_en           (active_en),
        .phyretrain_en       (phyretrain_en),
        .phyretrain_done     (phyretrain_done),
        .l1_en               (l1_en),
        .l1_done             (l1_done),
        .l2_en               (l2_en),
        .l2_done             (l2_done),
        .trainerror_en       (trainerror_en),
        .trainerror_done     (trainerror_done),
        // Per-state errors (reserved — TRAINERROR handshake wired in a later step)
        .sbinit_error        (sbinit_error),
        .mbinit_error        (mbinit_error),
        .mbtrain_error       (1'b0),                  // MBTRAIN not integrated in Step 1
        .linkinit_error      (linkinit_error),
        .active_error        (active_error),
        // ACTIVE-resolved next state (reserved — drives ACTIVE exit in a later step)
        .active_next_ltsm_state (active_next_ltsm_state),

        .current_ltsm_state  (current_ltsm_state)
    );

    // =========================================================================
    // 8 ms WATCHDOG TIMER CONTROL LOGIC
    // =========================================================================
    // Enabled while in states where handshakes can stall
    assign timeout_timer_en = (current_ltsm_state == SBINIT)  ||
                              (current_ltsm_state == MBINIT)   ||
                              (current_ltsm_state == MBTRAIN)  ||
                              (current_ltsm_state == LINKINIT) ||
                              (current_ltsm_state == PHYRETRAIN);

    // Reset the counter for one cycle whenever the substate (current_log_state) changes,
    // so every substate starts with a fresh 8 ms budget.
    state_n_e prev_log_state;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_log_state <= LOG_RESET;
        end else begin
            prev_log_state <= current_log_state;
        end
    end

    logic substate_changing;
    assign substate_changing = (current_log_state != prev_log_state);

    logic timer_rst_n_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) timer_rst_n_q <= 1'b0;
        else        timer_rst_n_q <= ~substate_changing;
    end
    assign timer_rst_n = timer_rst_n_q;

    // =========================================================================
    // 8 ms WATCHDOG TIMER (internal)
    // =========================================================================
    timeout_counter #(
        .CLK_FRQ_HZ (CLK_FRQ_HZ),
        .TIME_OUT   (8)
    ) u_timer_8ms (
        .clk             (clk),
        .timeout_rst_n   (timer_rst_n),
        .enable_timeout  (timeout_timer_en),
        .timeout_expired (timeout_8ms_occured)
    );

    // =========================================================================
    // 1. RESET
    // =========================================================================
    RESET #(
        .CLK_FRQ_HZ (CLK_FRQ_HZ)
    ) u_reset (
        .clk                                   (clk),
        .rst_n                                 (rst_n),
        .phy_start_ucie_link_training_ctrl_out (phy_start_ucie_link_training_ctrl_out),
        .Adapter_training_req                  (Adapter_training_req),//
        .sb_det_pattern_rcvd                   (sb_det_pattern_rcvd),
        .RESET_enable                          (reset_en),
        .RESET_state_done                      (reset_done)
    );

    // =========================================================================
    // 2. SBINIT
    // =========================================================================
    SBINIT #(
        .CLK_FRQ_HZ (CLK_FRQ_HZ)
    ) u_sbinit (
        .clk                 (clk),
        .rst_n               (rst_n),
        .sbinit_enable       (sbinit_en),
        .sbinit_done         (sbinit_done),
        .sbinit_error        (sbinit_error),
        .sb_rx_valid         (sb_rx_valid),
        .sb_rx_msg_id        (sb_rx_msg_id),
        .iter_done           (sb_iter_done),
        .sb_det_pattern_rcvd (sb_det_pattern_rcvd),
        .sb_tx_valid         (sbinit_tx_valid),
        .sb_tx_msg_id        (sbinit_tx_msg_id),
        .sbinit_pattern_mode (sbinit_pattern_mode),
        .sb_det_pattern_req  (sb_det_pattern_req),
        .req_iter_count      (sbinit_req_iter_count),
        .ltsm_rdy            (sb_ltsm_rdy),
        .global_error        (timeout_8ms_occured)
    );

    // =========================================================================
    // 3. MBINIT
    // =========================================================================
    MBINIT u_mbinit (
        .clk   (clk),
        .rst_n (rst_n),

        .mbinit_enable (mbinit_en),
        .mbinit_done   (mbinit_done),
        .mbinit_error  (mbinit_error),
        .mbinit_state_n(mbinit_state_n),
        .SPMW          (SPMW),

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

        .reg_Clock_Phase_enable_status (mbinit_reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status  (mbinit_reg_Clock_mode_enable_status),
        .reg_TARR_enable_status        (mbinit_reg_TARR_enable_status),
        .reg_Link_Width_enable_status  (mbinit_reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status  (mbinit_reg_Link_Speed_enable_status),
        .reg_PMO_enable_status         (mbinit_reg_PMO_enable_status),
        .reg_L2SPD_enable_status       (mbinit_reg_L2SPD_enable_status),
        .reg_PSPT_enable_status        (mbinit_reg_PSPT_enable_status),

        .local_tx_pt_en       (mbinit_local_tx_pt_en),
        .partner_tx_pt_en     (mbinit_partner_tx_pt_en),
        .d2c_pattern_setup    (mbinit_d2c_pattern_setup),
        .d2c_data_pattern_sel (mbinit_d2c_data_pattern_sel),
        .d2c_pattern_mode     (mbinit_d2c_pattern_mode),
        .d2c_compare_setup    (mbinit_d2c_compare_setup),
        .d2c_clk_sampling     (mbinit_d2c_clk_sampling),
        .d2c_burst_count      (mbinit_d2c_burst_count),
        .d2c_idle_count       (mbinit_d2c_idle_count),
        .d2c_iter_count       (mbinit_d2c_iter_count),
        .d2c_perlane_pass     (d2c_perlane_pass),
        .local_test_d2c_done  (local_test_d2c_done),
        .partner_test_d2c_done(partner_test_d2c_done),

        .sb_rx_valid     (sb_rx_valid),
        .sb_rx_msg_id    (sb_rx_msg_id),
        .sb_rx_MsgInfo   (sb_rx_MsgInfo[2:0]),
        .sb_rx_data_Field(sb_rx_data_Field[15:0]),
        .sb_tx_valid     (mbinit_tx_valid),
        .sb_ltsm_rdy     (sb_ltsm_rdy),
        .sb_tx_msg_id    (mbinit_tx_msg_id),
        .sb_tx_MsgInfo   (mbinit_tx_MsgInfo),
        .sb_tx_data_Field(mbinit_tx_data_Field),

        .mb_tx_pattern_en        (mbinit_mb_tx_pattern_en),
        .mb_tx_pattern_setup     (mbinit_mb_tx_pattern_setup),
        .mb_tx_data_pattern_sel  (mbinit_mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel   (mbinit_mb_tx_val_pattern_sel),
        .mb_rx_compare_en        (mbinit_mb_rx_compare_en),
        .mb_rx_compare_setup     (mbinit_mb_rx_compare_setup),
        .clear_error_req         (mbinit_clear_error_req),
        .mbinit_rx_data_lane_mask(mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask(mbinit_tx_data_lane_mask),

        .mb_rx_perlane_pass      (mb_rx_perlane_pass),
        .mb_tx_pattern_count_done(mb_tx_pattern_count_done),

        .mb_lane_reversal_req (mbinit_mb_lane_reversal_req),
        .repairclk_rtrk_pass  (repairclk_rtrk_pass),
        .repairclk_rckn_pass  (repairclk_rckn_pass),
        .repairclk_rckp_pass  (repairclk_rckp_pass),
        .repairval_RVLD_L_pass(repairval_RVLD_L_pass),

        .global_error(timeout_8ms_occured)
    );

    // =========================================================================
    // 4. MBTRAIN — not integrated in Step 1 (see MBTRAIN PASS-THROUGH above)
    // =========================================================================

    // =========================================================================
    // 5. LINKINIT
    // =========================================================================
    linkinit u_linkinit (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .rdi_state_sts            (rdi_state),
        .Linkinit_enable          (linkinit_en),
        .start_ucie_link_training (phy_start_ucie_link_training_ctrl_out),
        .linkinit_done            (linkinit_done),
        .linkinit_error           (linkinit_error)
    );

    // =========================================================================
    // 6. ACTIVE
    // =========================================================================
    ACTIVE u_active (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .active_enable            (active_en),
        .rdi_state                (rdi_state),
        .Start_UCIe_Link_Training (phy_start_ucie_link_training_ctrl_out),
        .active_error             (active_error),
        .next_ltsm_state          (active_next_ltsm_state)
    );

    // =========================================================================
    // 7. D2C POINT-TEST WRAPPER (real, shared MBINIT/MBTRAIN)
    // =========================================================================
    wrapper_D2C_PT_top u_d2c (
        .lclk  (clk),
        .rst_n (rst_n),

        .mb_rx_data_lane_mask (d2cpt_rx_data_lane_mask),

        .local_test_d2c_done   (local_test_d2c_done),
        .partner_test_d2c_done (partner_test_d2c_done),
        .d2c_perlane_pass      (d2c_perlane_pass),
        .d2c_aggr_pass         (d2c_aggr_pass),
        .d2c_val_pass          (d2c_val_pass),

        .local_tx_pt_en   (d2cpt_local_tx_pt_en),
        .partner_tx_pt_en (d2cpt_partner_tx_pt_en),
        .local_rx_pt_en   (d2cpt_local_rx_pt_en),
        .partner_rx_pt_en (d2cpt_partner_rx_pt_en),

        .d2c_clk_sampling     (d2cpt_clk_sampling),
        .d2c_pattern_setup    (d2cpt_pattern_setup),
        .d2c_data_pattern_sel (d2cpt_data_pattern_sel),
        .d2c_val_pattern_sel  (d2cpt_val_pattern_sel),
        .d2c_pattern_mode     (d2cpt_pattern_mode),
        .d2c_burst_count      (d2cpt_burst_count),
        .d2c_idle_count       (d2cpt_idle_count),
        .d2c_iter_count       (d2cpt_iter_count),
        .d2c_compare_setup    (d2cpt_compare_setup),
        .cfg_max_err_thresh_perlane (cfg_max_err_thresh_perlane),
        .cfg_max_err_thresh_aggr    (cfg_max_err_thresh_aggr),

        .mb_tx_trk_lane_sel  (d2c_mb_tx_trk_lane_sel),
        .mb_tx_clk_lane_sel  (d2c_mb_tx_clk_lane_sel),
        .mb_tx_val_lane_sel  (d2c_mb_tx_val_lane_sel),
        .mb_tx_data_lane_sel (d2c_mb_tx_data_lane_sel),
        .mb_rx_trk_lane_sel  (d2c_mb_rx_trk_lane_sel),
        .mb_rx_clk_lane_sel  (d2c_mb_rx_clk_lane_sel),
        .mb_rx_val_lane_sel  (d2c_mb_rx_val_lane_sel),
        .mb_rx_data_lane_sel (d2c_mb_rx_data_lane_sel),
        .mb_tx_pattern_en    (d2c_mb_tx_pattern_en),
        .mb_tx_pattern_setup (d2c_mb_tx_pattern_setup),
        .mb_rx_pattern_setup (d2c_mb_rx_pattern_setup),
        .mb_tx_lfsr_en       (d2c_mb_tx_lfsr_en),
        .mb_tx_lfsr_rst      (d2c_mb_tx_lfsr_rst),
        .mb_rx_lfsr_en       (d2c_mb_rx_lfsr_en),
        .mb_rx_lfsr_rst      (d2c_mb_rx_lfsr_rst),
        .mb_rx_iter_count    (d2c_mb_rx_iter_count),
        .mb_rx_idle_count    (d2c_mb_rx_idle_count),
        .mb_rx_burst_count   (d2c_mb_rx_burst_count),
        .mb_rx_pattern_mode  (d2c_mb_rx_pattern_mode),
        .mb_rx_val_pattern_sel  (d2c_mb_rx_val_pattern_sel),
        .mb_rx_data_pattern_sel (d2c_mb_rx_data_pattern_sel),
        .mb_rx_compare_en    (d2c_mb_rx_compare_en),
        .mb_rx_compare_setup (d2c_mb_rx_compare_setup),
        .mb_rx_max_err_thresh_perlane (d2c_mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr    (d2c_mb_rx_max_err_thresh_aggr),
        .mb_tx_clk_sampling_en (d2c_mb_tx_clk_sampling_en),
        .mb_tx_clk_sampling    (d2c_mb_tx_clk_sampling),
        .mb_tx_pattern_mode    (d2c_mb_tx_pattern_mode),
        .mb_tx_burst_count     (d2c_mb_tx_burst_count),
        .mb_tx_idle_count      (d2c_mb_tx_idle_count),
        .mb_tx_iter_count      (d2c_mb_tx_iter_count),
        .mb_tx_data_pattern_sel(d2c_mb_tx_data_pattern_sel),
        .mb_tx_val_pattern_sel (d2c_mb_tx_val_pattern_sel),

        // PHY-layer feedback signals (inputs to LTSM_wrapper, forwarded to D2C PT wrapper)
        .mb_tx_pattern_count_done (mb_tx_pattern_count_done),
        .mb_rx_aggr_pass          (mb_rx_aggr_pass),
        .mb_rx_perlane_pass       (mb_rx_perlane_pass),
        .mb_rx_val_pass           (mb_rx_val_pass),

        .tx_sb_msg_valid (d2c_tx_sb_msg_valid),
        .tx_sb_msg       (d2c_tx_sb_msg),
        .tx_msginfo      (d2c_tx_msginfo),
        .tx_data_field   (d2c_tx_data_field),
        .rx_sb_msg_valid (sb_rx_valid),
        .rx_sb_msg       (sb_rx_msg_8),
        .rx_msginfo      (sb_rx_MsgInfo),
        .rx_data_field   (sb_rx_data_Field)
    );

    // =========================================================================
    // SIDEBAND TX MUX
    // =========================================================================
    always_comb begin
        sb_tx_valid      = 1'b0;
        sb_tx_msg_id     = msg_no_e'(8'h0);
        sb_tx_MsgInfo    = 16'h0;
        sb_tx_data_Field = 64'h0;
        case (current_ltsm_state)
            SBINIT: begin
                sb_tx_valid  = sbinit_tx_valid;
                sb_tx_msg_id = sbinit_tx_msg_id;
            end
            MBINIT: begin
                if (d2c_tx_sb_msg_valid) begin
                    sb_tx_valid      = 1'b1;
                    sb_tx_msg_id     = msg_no_e'(d2c_tx_sb_msg);
                    sb_tx_MsgInfo    = d2c_tx_msginfo;
                    sb_tx_data_Field = d2c_tx_data_field;
                end else begin
                    sb_tx_valid      = mbinit_tx_valid;
                    sb_tx_msg_id     = mbinit_tx_msg_id;
                    sb_tx_MsgInfo    = mbinit_tx_MsgInfo;
                    sb_tx_data_Field = mbinit_tx_data_Field;
                end
            end
            default: ; // RESET / MBTRAIN / LINKINIT / ACTIVE: no SB TX in Step 1
        endcase
    end

    // =========================================================================
    // MAINBAND CONTROL MUX
    // =========================================================================
    // MBINIT : D2C point test (d2c_active) else MBINIT-direct
    always_comb begin
        mb_tx_pattern_en             = 1'b0;
        mb_tx_pattern_setup          = 3'b000;
        mb_tx_data_pattern_sel       = 2'b00;
        mb_tx_val_pattern_sel        = 1'b0;
        mb_tx_clk_pattern_sel        = 2'b00;
        mb_rx_compare_en             = 1'b0;
        mb_rx_compare_setup          = 2'b00;
        clear_error_req              = 1'b0;

        mb_tx_trk_lane_sel           = 2'b00;
        mb_tx_clk_lane_sel           = 2'b00;
        mb_tx_val_lane_sel           = 2'b00;
        mb_tx_data_lane_sel          = 2'b00;
        mb_rx_trk_lane_sel           = 1'b0;
        mb_rx_clk_lane_sel           = 1'b0;
        mb_rx_val_lane_sel           = 1'b0;
        mb_rx_data_lane_sel          = 1'b0;
        mb_tx_lfsr_en                = 1'b0;
        mb_tx_lfsr_rst               = 1'b0;
        mb_rx_lfsr_en                = 1'b0;
        mb_rx_lfsr_rst               = 1'b0;
        mb_rx_pattern_setup          = 3'b000;
        mb_rx_data_pattern_sel       = 2'b00;
        mb_rx_val_pattern_sel        = 1'b0;
        mb_rx_pattern_mode           = 1'b0;
        mb_rx_burst_count            = 16'h0;
        mb_rx_idle_count             = 16'h0;
        mb_rx_iter_count             = 16'h0;
        mb_tx_pattern_mode           = 1'b0;
        mb_tx_burst_count            = 16'h0;
        mb_tx_idle_count             = 16'h0;
        mb_tx_iter_count             = 16'h0;
        mb_tx_clk_sampling_en        = 1'b0;
        mb_tx_clk_sampling           = 2'b00;
        mb_rx_max_err_thresh_perlane = cfg_max_err_thresh_perlane;
        mb_rx_max_err_thresh_aggr    = cfg_max_err_thresh_aggr;

        if (d2c_active) begin
            // Shared D2C point test owns the mainband (MBINIT REPAIRMB or MBTRAIN sweep)
            mb_tx_pattern_en             = d2c_mb_tx_pattern_en;
            mb_tx_pattern_setup          = d2c_mb_tx_pattern_setup;
            mb_tx_data_pattern_sel       = d2c_mb_tx_data_pattern_sel;
            mb_tx_val_pattern_sel        = d2c_mb_tx_val_pattern_sel;
            mb_rx_compare_en             = d2c_mb_rx_compare_en;
            mb_rx_compare_setup          = d2c_mb_rx_compare_setup;
            mb_tx_trk_lane_sel           = d2c_mb_tx_trk_lane_sel;
            mb_tx_clk_lane_sel           = d2c_mb_tx_clk_lane_sel;
            mb_tx_val_lane_sel           = d2c_mb_tx_val_lane_sel;
            mb_tx_data_lane_sel          = d2c_mb_tx_data_lane_sel;
            mb_rx_trk_lane_sel           = d2c_mb_rx_trk_lane_sel;
            mb_rx_clk_lane_sel           = d2c_mb_rx_clk_lane_sel;
            mb_rx_val_lane_sel           = d2c_mb_rx_val_lane_sel;
            mb_rx_data_lane_sel          = d2c_mb_rx_data_lane_sel;
            mb_tx_lfsr_en                = d2c_mb_tx_lfsr_en;
            mb_tx_lfsr_rst               = d2c_mb_tx_lfsr_rst;
            mb_rx_lfsr_en                = d2c_mb_rx_lfsr_en;
            mb_rx_lfsr_rst               = d2c_mb_rx_lfsr_rst;
            mb_rx_pattern_setup          = d2c_mb_rx_pattern_setup;
            mb_rx_data_pattern_sel       = d2c_mb_rx_data_pattern_sel;
            mb_rx_val_pattern_sel        = d2c_mb_rx_val_pattern_sel;
            mb_rx_pattern_mode           = d2c_mb_rx_pattern_mode;
            mb_rx_burst_count            = d2c_mb_rx_burst_count;
            mb_rx_idle_count             = d2c_mb_rx_idle_count;
            mb_rx_iter_count             = d2c_mb_rx_iter_count;
            mb_tx_pattern_mode           = d2c_mb_tx_pattern_mode;
            mb_tx_burst_count            = d2c_mb_tx_burst_count;
            mb_tx_idle_count             = d2c_mb_tx_idle_count;
            mb_tx_iter_count             = d2c_mb_tx_iter_count;
            mb_tx_data_pattern_sel       = d2c_mb_tx_data_pattern_sel;
            mb_tx_val_pattern_sel        = d2c_mb_tx_val_pattern_sel;
            mb_tx_clk_sampling_en        = d2c_mb_tx_clk_sampling_en;
            mb_tx_clk_sampling           = d2c_mb_tx_clk_sampling;
            mb_rx_max_err_thresh_perlane = d2c_mb_rx_max_err_thresh_perlane;
            mb_rx_max_err_thresh_aggr    = d2c_mb_rx_max_err_thresh_aggr;
        end else if (current_ltsm_state == MBINIT) begin
            mb_tx_pattern_en       = mbinit_mb_tx_pattern_en;
            mb_tx_pattern_setup    = mbinit_mb_tx_pattern_setup;
            mb_tx_data_pattern_sel = mbinit_mb_tx_data_pattern_sel;
            mb_tx_val_pattern_sel  = mbinit_mb_tx_val_pattern_sel;
            mb_rx_compare_en       = mbinit_mb_rx_compare_en;
            mb_rx_compare_setup    = mbinit_mb_rx_compare_setup;
            clear_error_req        = mbinit_clear_error_req;

            mb_rx_val_lane_sel     = (current_ltsm_state_n >= LOG_MBINIT_REPAIRVAL);
            
            mb_rx_data_lane_sel    = (current_ltsm_state_n >= LOG_MBINIT_REVERSALMB);
            
            

        end
        else if (current_ltsm_state == ACTIVE) begin
            mb_rx_val_lane_sel     = 1'b1;
            mb_rx_data_lane_sel    = 1'b1;
        end
    end

    // =========================================================================
    // SEQUENTIAL LATCHING & LOOKAHEAD FOR MBINIT OUTPUTS
    // =========================================================================
    logic [2:0] mb_rx_data_lane_mask_reg;
    logic [2:0] mb_tx_data_lane_mask_reg;
    logic       mb_lane_reversal_req_reg;

    logic        reg_Clock_Phase_enable_status_reg;
    logic        reg_Clock_mode_enable_status_reg;
    logic        reg_TARR_enable_status_reg;
    logic [3:0]  reg_Link_Width_enable_status_reg;
    logic [3:0]  reg_Link_Speed_enable_status_reg;
    logic        reg_PMO_enable_status_reg;
    logic        reg_L2SPD_enable_status_reg;
    logic        reg_PSPT_enable_status_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mb_rx_data_lane_mask_reg          <= 3'b011;
            mb_tx_data_lane_mask_reg          <= 3'b011;
            mb_lane_reversal_req_reg          <= 1'b0;
            reg_Clock_Phase_enable_status_reg <= 1'b0;
            reg_Clock_mode_enable_status_reg  <= 1'b0;
            reg_TARR_enable_status_reg        <= 1'b0;
            reg_Link_Width_enable_status_reg  <= 4'h0;
            reg_Link_Speed_enable_status_reg  <= 4'h0;
            reg_PMO_enable_status_reg         <= 1'b0;
            reg_L2SPD_enable_status_reg       <= 1'b0;
            reg_PSPT_enable_status_reg        <= 1'b0;
        end else if (current_ltsm_state == RESET || current_ltsm_state == SBINIT) begin
            mb_rx_data_lane_mask_reg          <= 3'b011;
            mb_tx_data_lane_mask_reg          <= 3'b011;
            mb_lane_reversal_req_reg          <= 1'b0;
            reg_Clock_Phase_enable_status_reg <= 1'b0;
            reg_Clock_mode_enable_status_reg  <= 1'b0;
            reg_TARR_enable_status_reg        <= 1'b0;
            reg_Link_Width_enable_status_reg  <= 4'h0;
            reg_Link_Speed_enable_status_reg  <= 4'h0;
            reg_PMO_enable_status_reg         <= 1'b0;
            reg_L2SPD_enable_status_reg       <= 1'b0;
            reg_PSPT_enable_status_reg        <= 1'b0;
        end else if (current_ltsm_state == MBINIT) begin
            mb_rx_data_lane_mask_reg          <= mbinit_rx_data_lane_mask;
            mb_tx_data_lane_mask_reg          <= mbinit_tx_data_lane_mask;
            mb_lane_reversal_req_reg          <= mbinit_mb_lane_reversal_req;
            reg_Clock_Phase_enable_status_reg <= mbinit_reg_Clock_Phase_enable_status;
            reg_Clock_mode_enable_status_reg  <= mbinit_reg_Clock_mode_enable_status;
            reg_TARR_enable_status_reg        <= mbinit_reg_TARR_enable_status;
            reg_Link_Width_enable_status_reg  <= mbinit_reg_Link_Width_enable_status;
            reg_Link_Speed_enable_status_reg  <= mbinit_reg_Link_Speed_enable_status;
            reg_PMO_enable_status_reg         <= mbinit_reg_PMO_enable_status;
            reg_L2SPD_enable_status_reg       <= mbinit_reg_L2SPD_enable_status;
            reg_PSPT_enable_status_reg        <= mbinit_reg_PSPT_enable_status;
        end
    end

    always_comb begin
        mb_rx_data_lane_mask          = mb_rx_data_lane_mask_reg;
        mb_tx_data_lane_mask          = mb_tx_data_lane_mask_reg;
        mb_lane_reversal_req          = mb_lane_reversal_req_reg;
        reg_Clock_Phase_enable_status = reg_Clock_Phase_enable_status_reg;
        reg_Clock_mode_enable_status  = reg_Clock_mode_enable_status_reg;
        reg_TARR_enable_status        = reg_TARR_enable_status_reg;
        reg_Link_Width_enable_status  = reg_Link_Width_enable_status_reg;
        reg_Link_Speed_enable_status  = reg_Link_Speed_enable_status_reg;
        reg_PMO_enable_status         = reg_PMO_enable_status_reg;
        reg_L2SPD_enable_status       = reg_L2SPD_enable_status_reg;
        reg_PSPT_enable_status        = reg_PSPT_enable_status_reg;

        if (current_ltsm_state == RESET || current_ltsm_state == SBINIT) begin
            mb_rx_data_lane_mask          = 3'b011;
            mb_tx_data_lane_mask          = 3'b011;
            mb_lane_reversal_req          = 1'b0;
            reg_Clock_Phase_enable_status = 1'b0;
            reg_Clock_mode_enable_status  = 1'b0;
            reg_TARR_enable_status        = 1'b0;
            reg_Link_Width_enable_status  = 4'h0;
            reg_Link_Speed_enable_status  = 4'h0;
            reg_PMO_enable_status         = 1'b0;
            reg_L2SPD_enable_status       = 1'b0;
            reg_PSPT_enable_status        = 1'b0;
        end else if (current_ltsm_state == MBINIT) begin
            mb_rx_data_lane_mask          = mbinit_rx_data_lane_mask;
            mb_tx_data_lane_mask          = mbinit_tx_data_lane_mask;
            mb_lane_reversal_req          = mbinit_mb_lane_reversal_req;
            reg_Clock_Phase_enable_status = mbinit_reg_Clock_Phase_enable_status;
            reg_Clock_mode_enable_status  = mbinit_reg_Clock_mode_enable_status;
            reg_TARR_enable_status        = mbinit_reg_TARR_enable_status;
            reg_Link_Width_enable_status  = mbinit_reg_Link_Width_enable_status;
            reg_Link_Speed_enable_status  = mbinit_reg_Link_Speed_enable_status;
            reg_PMO_enable_status         = mbinit_reg_PMO_enable_status;
            reg_L2SPD_enable_status       = mbinit_reg_L2SPD_enable_status;
            reg_PSPT_enable_status        = mbinit_reg_PSPT_enable_status;
        end
    end

    assign sb_pattern_mode      = (current_ltsm_state == RESET) || (sbinit_pattern_mode && current_ltsm_state == SBINIT);

endmodule
