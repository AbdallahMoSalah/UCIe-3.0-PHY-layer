import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// LTSM  —  Step 1 integration top (now with real MBTRAIN)
// =============================================================================
//     RESET -> SBINIT -> MBINIT -> MBTRAIN -> LINKINIT -> ACTIVE
//
// Contents:
//   * unit_ltsm_controller : minimal Step-1 FSM (enables + status + 8 ms timer ctrl)
//   * timeout_counter      : shared 8 ms watchdog (internal)
//   * RESET / SBINIT / MBINIT / LINKINIT / ACTIVE : real state blocks
//   * wrapper_MBTRAIN      : real MBTRAIN (substate machine)               <== NEW
//   * unit_D2C_sweep       : drives the D2C point test during MBTRAIN      <== NEW
//   * inline analog-settle timer (unit_analog_settle_timer is interface-   <== NEW
//                            based, so its trivial counter is inlined here)
//   * wrapper_D2C_PT_top   : real D2C point-test block (shared MBINIT/MBTRAIN)
//   * SB / MB output muxes  : route the active state's outputs out
//
// D2C point test is shared: its enables/config are muxed from the SWEEP block
// while in MBTRAIN, and from MBINIT otherwise. The mainband control mux has
// three sources: MBINIT-direct, the D2C point test, and MBTRAIN substate
// (RXCLKCAL clock pattern + lane selects).
//
// MBTRAIN's analog PHY controls (phy_rx_datavref / PI / deskew / eq / tckn
// shift, etc.) have no consumer in the behavioral MainBand_RD datapath, so
// those outputs are left unconnected and the few phy_* inputs are tied off.
//
// Assumptions flagged for review:
//   * param_negotiated_max_speed <= reg_Link_Speed_enable_status[2:0]
//   * is_continuous_clk_mode     <= reg_Clock_mode_enable_status
//   * param_UCIe_S_x8            <= reg_phy_x8_mode_ctrl
//   * state_n_0/1 derived from current_ltsm_state (substate from MBINIT/MBTRAIN);
//     state_n_1 is the previous distinct state.
//   * MBTRAIN external sub-requests (txselfcal/speedidle/repair) tied 0;
//     PHY_IN_RETRAIN / params_changed tied 0 (PHYRETRAIN is a later step).
//
// Deferred to later steps: PHYRETRAIN / L1 / L2 / TRAINERROR, capability-status
// latching, state/error logs.
// =============================================================================

module LTSM #(
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
    output state_n_e    current_mbtrain_substate,
    output logic        mbinit_error,
    output logic        active_error,
    output logic        timeout_8ms_occured,

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
    output logic        sbinit_pattern_mode,
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
    logic mbinit_en,   mbinit_done;
    logic mbtrain_en,  mbtrain_done;
    logic linkinit_en, linkinit_done, linkinit_error;
    logic active_en;

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

    // =========================================================================
    // MBTRAIN output wires
    // =========================================================================
    logic        ltsm_trainerror_req;
    logic        ltsm_linkinit_req;     // observed; transition uses mbtrain_done
    logic        ltsm_phyretrain_req;   // reserved for PHYRETRAIN step

    logic [2:0]  mbtrain_rx_data_lane_mask;
    logic [2:0]  mbtrain_tx_data_lane_mask;

    logic        mbtrain_local_sweep_en;
    logic        mbtrain_partner_sweep_en;
    logic [15:0] sweep_active_lanes;

    // MBTRAIN substate mainband controls
    logic [1:0]  substate_mb_tx_clk_lane_sel, substate_mb_tx_data_lane_sel;
    logic [1:0]  substate_mb_tx_val_lane_sel, substate_mb_tx_trk_lane_sel;
    logic        substate_mb_rx_clk_lane_sel, substate_mb_rx_data_lane_sel;
    logic        substate_mb_rx_val_lane_sel, substate_mb_rx_trk_lane_sel;
    logic        rxclkcal_mb_tx_pattern_en;
    logic [2:0]  rxclkcal_mb_tx_pattern_setup;
    logic [1:0]  rxclkcal_mb_tx_clk_pattern_sel;

    // MBTRAIN substate sideband TX (8-bit msg form)
    logic        mbtrain_tx_sb_msg_valid;
    logic [7:0]  mbtrain_tx_sb_msg;
    logic [15:0] mbtrain_tx_msginfo;
    logic [63:0] mbtrain_tx_data_field;

    // =========================================================================
    // D2C sweep <-> D2C point-test wires
    // =========================================================================
    localparam int unsigned SWEEP_MAX_CODE = 16; // matches unit_D2C_sweep / wrapper_MBTRAIN defaults
    localparam int unsigned SWEEP_CODE_W   = $clog2(SWEEP_MAX_CODE + 1);

    logic        sweep_done;
    logic [SWEEP_CODE_W-1:0] sweep_swept_code;
    logic [SWEEP_CODE_W-1:0] sweep_best_code [0:15];
    logic [SWEEP_CODE_W-1:0] sweep_min_eye_width;

    logic        sweep_local_tx_pt_en, sweep_local_rx_pt_en;
    logic        sweep_partner_tx_pt_en, sweep_partner_rx_pt_en;
    logic [1:0]  sweep_d2c_clk_sampling;
    logic [2:0]  sweep_d2c_pattern_setup;
    logic [1:0]  sweep_d2c_data_pattern_sel;
    logic        sweep_d2c_val_pattern_sel;
    logic        sweep_d2c_pattern_mode;
    logic [15:0] sweep_d2c_burst_count, sweep_d2c_idle_count, sweep_d2c_iter_count;
    logic [1:0]  sweep_d2c_compare_setup;

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

    // Sideband RX, 8-bit form for D2C / MBTRAIN
    logic [7:0] sb_rx_msg_8;
    assign sb_rx_msg_8 = sb_rx_msg_id;

    // Config sources for MBTRAIN (negotiated by MBINIT) — see header assumptions
    logic [2:0] param_negotiated_max_speed_src;
    logic       is_continuous_clk_mode_src;
    assign param_negotiated_max_speed_src = reg_Link_Speed_enable_status[2:0];
    assign is_continuous_clk_mode_src      = reg_Clock_mode_enable_status;

    // =========================================================================
    // D2C POINT-TEST SHARED-INPUT MUX (sweep drives during MBTRAIN, else MBINIT)
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

    always_comb begin
        if (current_ltsm_state == MBTRAIN) begin
            d2cpt_local_tx_pt_en    = sweep_local_tx_pt_en;
            d2cpt_partner_tx_pt_en  = sweep_partner_tx_pt_en;
            d2cpt_local_rx_pt_en    = sweep_local_rx_pt_en;
            d2cpt_partner_rx_pt_en  = sweep_partner_rx_pt_en;
            d2cpt_clk_sampling      = sweep_d2c_clk_sampling;
            d2cpt_pattern_setup     = sweep_d2c_pattern_setup;
            d2cpt_data_pattern_sel  = sweep_d2c_data_pattern_sel;
            d2cpt_val_pattern_sel   = sweep_d2c_val_pattern_sel;
            d2cpt_pattern_mode      = sweep_d2c_pattern_mode;
            d2cpt_burst_count       = sweep_d2c_burst_count;
            d2cpt_idle_count        = sweep_d2c_idle_count;
            d2cpt_iter_count        = sweep_d2c_iter_count;
            d2cpt_compare_setup     = sweep_d2c_compare_setup;
            d2cpt_rx_data_lane_mask = mbtrain_rx_data_lane_mask;
        end else begin
            d2cpt_local_tx_pt_en    = mbinit_local_tx_pt_en;
            d2cpt_partner_tx_pt_en  = mbinit_partner_tx_pt_en;
            d2cpt_local_rx_pt_en    = 1'b0;
            d2cpt_partner_rx_pt_en  = 1'b0;
            d2cpt_clk_sampling      = mbinit_d2c_clk_sampling;
            d2cpt_pattern_setup     = mbinit_d2c_pattern_setup;
            d2cpt_data_pattern_sel  = mbinit_d2c_data_pattern_sel;
            d2cpt_val_pattern_sel   = 1'b0;
            d2cpt_pattern_mode      = mbinit_d2c_pattern_mode;
            d2cpt_burst_count       = mbinit_d2c_burst_count;
            d2cpt_idle_count        = mbinit_d2c_idle_count;
            d2cpt_iter_count        = mbinit_d2c_iter_count;
            d2cpt_compare_setup     = mbinit_d2c_compare_setup;
            d2cpt_rx_data_lane_mask = mbinit_rx_data_lane_mask;
        end
    end

    // True while a D2C point test owns the mainband (MBINIT REPAIRMB or MBTRAIN sweep)
    logic d2c_active;
    assign d2c_active = d2cpt_local_tx_pt_en | d2cpt_partner_tx_pt_en |
                        d2cpt_local_rx_pt_en | d2cpt_partner_rx_pt_en;

    // =========================================================================
    // STATE-N HISTORY (for MBTRAIN soft-reset / entry detection)
    // =========================================================================
    state_n_e state_n_0_c;
    always_comb begin
        case (current_ltsm_state)
            RESET:    state_n_0_c = LOG_RESET;
            SBINIT:   state_n_0_c = LOG_SBINIT;
            MBINIT:   state_n_0_c = mbinit_state_n;
            MBTRAIN:  state_n_0_c = current_mbtrain_substate;
            LINKINIT: state_n_0_c = LOG_LINKINIT;
            ACTIVE:   state_n_0_c = LOG_ACTIVE;
            default:  state_n_0_c = LOG_NOP;
        endcase
    end

    state_n_e state_n_0_q, state_n_1_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_n_0_q <= LOG_NOP;
            state_n_1_q <= LOG_NOP;
        end else if (state_n_0_c != state_n_0_q) begin
            state_n_1_q <= state_n_0_q; // previous distinct state
            state_n_0_q <= state_n_0_c;
        end
    end

    // =========================================================================
    // INLINE ANALOG-SETTLE TIMER (mirrors unit_analog_settle_timer behavior)
    // =========================================================================
    localparam int ANALOG_SETTLE_DELAY = 16;
    logic                                       analog_settle_timer_en;
    logic                                       analog_settle_time_done;
    logic [$clog2(ANALOG_SETTLE_DELAY+1)-1:0]   analog_settle_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            analog_settle_cnt <= '0;
        else if (analog_settle_timer_en) begin
            if (analog_settle_cnt < ANALOG_SETTLE_DELAY)
                analog_settle_cnt <= analog_settle_cnt + 1'b1;
        end else
            analog_settle_cnt <= '0;
    end
    assign analog_settle_time_done = (analog_settle_cnt == ANALOG_SETTLE_DELAY) && analog_settle_timer_en;

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
        // Per-state errors (reserved — TRAINERROR handshake wired in a later step)
        .sbinit_error        (sbinit_error),
        .mbinit_error        (mbinit_error),
        .mbtrain_error       (ltsm_trainerror_req),
        .linkinit_error      (linkinit_error),
        .active_error        (active_error),
        .current_ltsm_state  (current_ltsm_state),
        .timeout_timer_en    (timeout_timer_en),
        .timer_rst_n         (timer_rst_n),
        .timeout_8ms_occured (timeout_8ms_occured)
    );

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
        .Adapter_training_req                  (Adapter_training_req),
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

        .reg_Clock_Phase_enable_status (reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status  (reg_Clock_mode_enable_status),
        .reg_TARR_enable_status        (reg_TARR_enable_status),
        .reg_Link_Width_enable_status  (reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status  (reg_Link_Speed_enable_status),
        .reg_PMO_enable_status         (reg_PMO_enable_status),
        .reg_L2SPD_enable_status       (reg_L2SPD_enable_status),
        .reg_PSPT_enable_status        (reg_PSPT_enable_status),

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
    // 4. MBTRAIN (real)
    // =========================================================================
    wrapper_MBTRAIN u_mbtrain (
        .lclk  (clk),
        .rst_n (rst_n),

        .mbtrain_en               (mbtrain_en),
        .mbtrain_done             (mbtrain_done),
        .current_mbtrain_substate (current_mbtrain_substate),

        .ltsm_trainerror_req (ltsm_trainerror_req),
        .ltsm_linkinit_req   (ltsm_linkinit_req),
        .ltsm_phyretrain_req (ltsm_phyretrain_req),

        // External sub-requests (none in Step 1)
        .mbtrain_txselfcal_req (1'b0),
        .mbtrain_speedidle_req (1'b0),
        .mbtrain_repair_req    (1'b0),

        // Analog settle timer (inlined above)
        .analog_settle_time_done (analog_settle_time_done),
        .analog_settle_timer_en  (analog_settle_timer_en),

        // State history
        .state_n_0 (state_n_0_c),
        .state_n_1 (state_n_1_q),

        // Config / straps
        .param_negotiated_max_speed (param_negotiated_max_speed_src),
        .is_continuous_clk_mode     (is_continuous_clk_mode_src),
        .rf_cap_SPMW                (SPMW),
        .rf_ctrl_target_link_width  (reg_Target_Link_Width_ctrl),
        .param_UCIe_S_x8            (reg_phy_x8_mode_ctrl),

        // PHYRETRAIN handshake (later step)
        .PHY_IN_RETRAIN     (1'b0),
        .params_changed     (1'b0),
        .PHY_IN_RETRAIN_rst (),
        .busy_bit_rst       (),

        // Lane masks
        .mbinit_rx_data_lane_mask (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask (mbinit_tx_data_lane_mask),
        .mb_rx_data_lane_mask     (mbtrain_rx_data_lane_mask),
        .mb_tx_data_lane_mask     (mbtrain_tx_data_lane_mask),

        // D2C sweep interface
        .local_sweep_en     (mbtrain_local_sweep_en),
        .partner_sweep_en   (mbtrain_partner_sweep_en),
        .sweep_active_lanes (sweep_active_lanes),
        .sweep_done         (sweep_done),
        .sweep_swept_code   (sweep_swept_code),
        .sweep_best_code    (sweep_best_code),
        .sweep_min_eye_width(sweep_min_eye_width),

        .d2c_perlane_pass   (d2c_perlane_pass),

        // PHY analog controls — no consumer in the behavioral MB datapath
        .phy_negotiated_speed         (),
        .phy_tx_selfcal_en            (),
        .phy_rx_clock_lock_en         (),
        .phy_rx_track_lock_en         (),
        .phy_rx_phase_detector_en     (),
        .phy_rx_tckn_shift            (5'd0),
        .phy_rx_decrement_shift       (1'b0),
        .phy_tx_tckn_shift_en         (),
        .phy_tx_tckn_shift            (),
        .phy_tx_decrement_shift       (),
        .phy_tx_tckn_shift_out_of_range(1'b0),
        .phy_rx_valvref_ctrl          (),
        .phy_rx_datavref_ctrl         (),
        .phy_tx_val_pi_phase_ctrl     (),
        .phy_tx_data_pi_phase_ctrl    (),
        .phy_rx_deskew_ctrl           (),
        .phy_tx_eq_preset_ctrl        (),
        .phy_tx_eq_preset_en          (),

        // Substate lane selects
        .substate_mb_tx_clk_lane_sel  (substate_mb_tx_clk_lane_sel),
        .substate_mb_tx_data_lane_sel (substate_mb_tx_data_lane_sel),
        .substate_mb_tx_val_lane_sel  (substate_mb_tx_val_lane_sel),
        .substate_mb_tx_trk_lane_sel  (substate_mb_tx_trk_lane_sel),
        .substate_mb_rx_clk_lane_sel  (substate_mb_rx_clk_lane_sel),
        .substate_mb_rx_data_lane_sel (substate_mb_rx_data_lane_sel),
        .substate_mb_rx_val_lane_sel  (substate_mb_rx_val_lane_sel),
        .substate_mb_rx_trk_lane_sel  (substate_mb_rx_trk_lane_sel),

        // RXCLKCAL pattern controls
        .rxclkcal_mb_tx_pattern_en     (rxclkcal_mb_tx_pattern_en),
        .rxclkcal_mb_tx_pattern_setup  (rxclkcal_mb_tx_pattern_setup),
        .rxclkcal_mb_tx_clk_pattern_sel(rxclkcal_mb_tx_clk_pattern_sel),

        // Substate sideband TX
        .substate_tx_sb_msg_valid (mbtrain_tx_sb_msg_valid),
        .substate_tx_sb_msg       (mbtrain_tx_sb_msg),
        .substate_tx_msginfo      (mbtrain_tx_msginfo),
        .substate_tx_data_field   (mbtrain_tx_data_field),

        // Broadcast sideband RX
        .rx_sb_msg_valid (sb_rx_valid),
        .rx_sb_msg       (sb_rx_msg_8),
        .rx_msginfo      (sb_rx_MsgInfo),
        .rx_data_field   (sb_rx_data_Field)
    );

    // =========================================================================
    // 4b. D2C SWEEP (drives the point test during MBTRAIN)
    // =========================================================================
    unit_D2C_sweep u_d2c_sweep (
        .lclk  (clk),
        .rst_n (rst_n),
        .active_lanes          (sweep_active_lanes),
        .local_sweep_en        (mbtrain_local_sweep_en),
        .partner_sweep_en      (mbtrain_partner_sweep_en),
        .sweep_done            (sweep_done),
        .state_n               (state_n_0_c),
        .local_test_d2c_done   (local_test_d2c_done),
        .partner_test_d2c_done (partner_test_d2c_done),
        .d2c_perlane_pass      (d2c_perlane_pass),
        .d2c_val_pass          (d2c_val_pass),
        .local_tx_pt_en        (sweep_local_tx_pt_en),
        .local_rx_pt_en        (sweep_local_rx_pt_en),
        .partner_tx_pt_en      (sweep_partner_tx_pt_en),
        .partner_rx_pt_en      (sweep_partner_rx_pt_en),
        .d2c_clk_sampling      (sweep_d2c_clk_sampling),
        .d2c_pattern_setup     (sweep_d2c_pattern_setup),
        .d2c_data_pattern_sel  (sweep_d2c_data_pattern_sel),
        .d2c_val_pattern_sel   (sweep_d2c_val_pattern_sel),
        .d2c_pattern_mode      (sweep_d2c_pattern_mode),
        .d2c_burst_count       (sweep_d2c_burst_count),
        .d2c_idle_count        (sweep_d2c_idle_count),
        .d2c_iter_count        (sweep_d2c_iter_count),
        .d2c_compare_setup     (sweep_d2c_compare_setup),
        .swept_code            (sweep_swept_code),
        .best_code             (sweep_best_code),
        .min_eye_width         (sweep_min_eye_width),
        .local_pt_en_dbg       ()
    );

    // =========================================================================
    // 5. LINKINIT
    // =========================================================================
    linkinit u_linkinit (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .rdi_state_sts            (rdi_state),
        .timeout_expired          (timeout_8ms_occured),
        .Linkinit_enable          (linkinit_en),
        .start_ucie_link_training (phy_start_ucie_link_training_ctrl_out),
        .linkinit_done            (linkinit_done),
        .timeout_rst_n            (),
        .enable_timeout           (),
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

        .mb_tx_pattern_count_done(mb_tx_pattern_count_done),
        .mb_rx_compare_done      (mb_rx_compare_done),
        .mb_rx_aggr_pass         (mb_rx_aggr_pass),
        .mb_rx_perlane_pass      (mb_rx_perlane_pass),
        .mb_rx_val_pass          (mb_rx_val_pass),

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
            MBTRAIN: begin
                if (d2c_tx_sb_msg_valid) begin
                    sb_tx_valid      = 1'b1;
                    sb_tx_msg_id     = msg_no_e'(d2c_tx_sb_msg);
                    sb_tx_MsgInfo    = d2c_tx_msginfo;
                    sb_tx_data_Field = d2c_tx_data_field;
                end else begin
                    sb_tx_valid      = mbtrain_tx_sb_msg_valid;
                    sb_tx_msg_id     = msg_no_e'(mbtrain_tx_sb_msg);
                    sb_tx_MsgInfo    = mbtrain_tx_msginfo;
                    sb_tx_data_Field = mbtrain_tx_data_field;
                end
            end
            default: ; // RESET / LINKINIT / ACTIVE: no SB TX in Step 1
        endcase
    end

    // =========================================================================
    // MAINBAND CONTROL MUX
    // =========================================================================
    // MBINIT  : D2C point test (d2c_active) else MBINIT-direct
    // MBTRAIN : D2C point test (sweep) else MBTRAIN substate (RXCLKCAL + lane sels)
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
        mb_rx_max_err_thresh_perlane = 12'h0;
        mb_rx_max_err_thresh_aggr    = 16'h0;

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
        end else if (current_ltsm_state == MBTRAIN) begin
            // MBTRAIN substate direct (RXCLKCAL clock pattern + lane selects)
            mb_tx_pattern_en      = rxclkcal_mb_tx_pattern_en;
            mb_tx_pattern_setup   = rxclkcal_mb_tx_pattern_setup;
            mb_tx_clk_pattern_sel = rxclkcal_mb_tx_clk_pattern_sel;
            mb_tx_clk_lane_sel    = substate_mb_tx_clk_lane_sel;
            mb_tx_data_lane_sel   = substate_mb_tx_data_lane_sel;
            mb_tx_val_lane_sel    = substate_mb_tx_val_lane_sel;
            mb_tx_trk_lane_sel    = substate_mb_tx_trk_lane_sel;
            mb_rx_clk_lane_sel    = substate_mb_rx_clk_lane_sel;
            mb_rx_data_lane_sel   = substate_mb_rx_data_lane_sel;
            mb_rx_val_lane_sel    = substate_mb_rx_val_lane_sel;
            mb_rx_trk_lane_sel    = substate_mb_rx_trk_lane_sel;
        end
    end

    // =========================================================================
    // LANE MASK / REVERSAL  (MBINIT owns in MBINIT, MBTRAIN owns in MBTRAIN)
    // =========================================================================
    assign mb_tx_data_lane_mask = (current_ltsm_state == MBTRAIN) ? mbtrain_tx_data_lane_mask
                                                                  : mbinit_tx_data_lane_mask;
    assign mb_rx_data_lane_mask = (current_ltsm_state == MBTRAIN) ? mbtrain_rx_data_lane_mask
                                                                  : mbinit_rx_data_lane_mask;
    assign mb_lane_reversal_req = mbinit_mb_lane_reversal_req;

endmodule
