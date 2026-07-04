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
// Deferred to later steps: L1 / L2 re-entry MBTRAIN paths,
// capability-status latching, state/error logs.
// =============================================================================

module LTSM_wrapper #(
        parameter int CLK_FRQ_HZ         = 125_000_000,
        parameter int MAX_VAL_VREF_CODE  = 32'd3,
        parameter int MAX_DATA_VREF_CODE = 32'd3,
        parameter int MAX_PI_PHASE_CODE  = 32'd3,
        parameter int MAX_DESKEW_CODE    = 32'd3
    )(
        input  logic        clk,
        input  logic        rst_n,

        // =========================================================================
        // Status / observability
        // =========================================================================
        output LTSM_state_e current_ltsm_state,





        // Rigster File Interface
        output logic        link_training_retraining,
        output logic        link_status,
        output logic        timeout_8ms_occured,
        output logic        busy_flag,

        // RESET-state completion (high once the 4 ms dwell + a training trigger are
        // both satisfied, held until the LTSM leaves RESET). Forwarded to the RDI
        // gating logic to clear its sideband-pattern ungate latch at RESET exit.
        output logic        RESET_state_done,

        // State log registers (shift & latch history)
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
        input  logic        sb_det_pattern_rcvd,
        input  logic        sb_det_pattern_rcvd_sticky,

        // SPMW strap
        input  logic        SPMW,

        // =========================================================================
        // Capability configuration (to MBINIT) — matches current MBINIT ports
        // =========================================================================
        input  logic        start_bit,
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
        input  logic        rt_apply_module_0_lane_repair_ctrl_out,
        input  logic [6:0]  module_0_lane_repair_id_ctrl_out,

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
        output logic [2:0]  mb_pll_speed_sel,
        output logic        clk_embedded_en,
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
        input  RDI_state    rdi_state,

        // Adapter-requested RDI state (L1 wake trigger)
        input  RDI_state    lp_state_req
    );

    // MAX_CODE: derived automatically — do not override.
    parameter int unsigned MAX_CODE =
        (MAX_VAL_VREF_CODE  >= MAX_DATA_VREF_CODE && MAX_VAL_VREF_CODE  >= MAX_PI_PHASE_CODE && MAX_VAL_VREF_CODE  >= MAX_DESKEW_CODE)  ? MAX_VAL_VREF_CODE  :
        (MAX_DATA_VREF_CODE >= MAX_PI_PHASE_CODE  && MAX_DATA_VREF_CODE >= MAX_DESKEW_CODE) ? MAX_DATA_VREF_CODE :
        (MAX_PI_PHASE_CODE  >= MAX_DESKEW_CODE) ? MAX_PI_PHASE_CODE : MAX_DESKEW_CODE;
    parameter int MAX_CODE_WIDTH = $clog2(MAX_CODE+1);
    parameter int MAX_DESKEW_CODE_WIDTH = $clog2(MAX_DESKEW_CODE+1);

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
    logic l1_en,         l1_done, l1_error;
    logic l2_en,         l2_done, l2_error;
    logic trainerror_en, trainerror_done;
    logic sbinit_pattern_mode;
    // L1-exit MBTRAIN re-entry at SPEEDIDLE (controller -> wrapper_MBTRAIN)
    logic mbtrain_speedidle_req;

    state_n_e    current_ltsm_state_n;
    logic timeout_timer_en, timer_rst_n;
    assign clk_embedded_en = (current_ltsm_state_n > LOG_MBINIT_REPAIRCLK);
    // =========================================================================
    // MBTRAIN block <-> wrapper signals (declared early to satisfy ordering)
    // =========================================================================
    state_n_e    mbtrain_current_substate;
    logic        mbtrain_ltsm_trainerror_req;
    logic        mbtrain_ltsm_linkinit_req;   // observe only (LINKINIT exit = mbtrain_done)
    logic        mbtrain_ltsm_phyretrain_req;

    logic        mbtrain_local_sweep_en;
    logic        mbtrain_partner_sweep_en;
    logic [15:0] mbtrain_sweep_active_lanes;

    logic        mbtrain_sub_rx_clk_lane_sel, mbtrain_sub_rx_data_lane_sel;
    logic        mbtrain_sub_rx_val_lane_sel, mbtrain_sub_rx_trk_lane_sel;

    logic        mbtrain_rxclkcal_tx_pattern_en;
    logic [2:0]  mbtrain_rxclkcal_tx_pattern_setup;
    logic [1:0]  mbtrain_rxclkcal_tx_clk_pattern_sel;

    logic        mbtrain_tx_sb_msg_valid;
    logic [7:0]  mbtrain_tx_sb_msg;
    logic [15:0] mbtrain_tx_msginfo;
    logic [63:0] mbtrain_tx_data_field;

    logic [2:0]  mbtrain_mb_rx_data_lane_mask;   // observe only in this step
    logic [2:0]  mbtrain_mb_tx_data_lane_mask;

    // MBTRAIN PHY analog control outputs — kept INTERNAL (mainband model ignores
    // analog codes; exposed here only for waveform observability).
    logic [2:0]  mbtrain_phy_negotiated_speed;
    logic        mbtrain_phy_tx_selfcal_en;
    logic        mbtrain_phy_rx_clock_lock_en, mbtrain_phy_rx_track_lock_en;
    logic        mbtrain_phy_rx_phase_detector_en;
    logic        mbtrain_phy_tx_tckn_shift_en, mbtrain_phy_tx_decrement_shift;
    logic [4:0]  mbtrain_phy_tx_tckn_shift;
    logic        mbtrain_PHY_IN_RETRAIN_rst;

    // =========================================================================
    // PHYRETRAIN block <-> wrapper signals
    // =========================================================================
    logic        phyretrain_tx_sb_msg_valid;
    msg_no_e     phyretrain_tx_sb_msg;
    logic [15:0] phyretrain_tx_msginfo;
    logic [2:0]  phyretrain_resolved_enc;
    logic        phyretrain_error;
    logic        PHY_IN_RETRAIN;
    logic        PHY_IN_RETRAIN_rst;
    logic        busy_bit_PHY_RETRAIN;

    // Latched resolved encoding — held after PHYRETRAIN completes so MBTRAIN
    // can read the re-entry selector even after phyretrain_enable deasserts.
    logic [2:0]  phyretrain_resolved_enc_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phyretrain_resolved_enc_reg <= 3'b000;
        else if (phyretrain_done)
            phyretrain_resolved_enc_reg <= phyretrain_resolved_enc;
    end

    // MBTRAIN re-entry selectors driven by the PHYRETRAIN resolved encoding.
    // Active while PHY_IN_RETRAIN is set (from PHYRETRAIN entry until MBTRAIN
    // LINKSPEED clears it).
    logic phyretrain_mbtrain_txselfcal_req;
    logic phyretrain_mbtrain_repair_req;
    logic phyretrain_mbtrain_speedidle_req;
    assign phyretrain_mbtrain_txselfcal_req = PHY_IN_RETRAIN && (phyretrain_resolved_enc_reg == 3'b001);
    assign phyretrain_mbtrain_repair_req    = PHY_IN_RETRAIN && (phyretrain_resolved_enc_reg == 3'b100);
    assign phyretrain_mbtrain_speedidle_req = PHY_IN_RETRAIN && (phyretrain_resolved_enc_reg == 3'b010);

    // Shared sweep-engine results (wrapper_D2C_sweep -> consumers).
    // Width = $clog2(MAX_CODE+1); MAX_CODE=2 (shrunk ranges) -> 2 bits.
    logic        d2c_sweep_done;
    logic [MAX_CODE_WIDTH-1:0]  d2c_swept_code;
    wire  [MAX_CODE_WIDTH-1:0]  d2c_best_code [0:15];
    wire  [MAX_DESKEW_CODE_WIDTH-1:0]  d2c_min_eye_width;

    // Shared D2C sweep-engine muxed inputs (MBINIT vs MBTRAIN)
    logic        sweep_local_en, sweep_partner_en;
    logic [15:0] sweep_active_lanes_mux;

    // wrapper_MBTRAIN state_n_0 entry-context. Per the verified MBTRAIN contract,
    // state_n_0 must read LOG_RESET / LOG_SBINIT during init (drives the internal
    // soft_rst_n) and LOG_MBTRAIN_VALVREF throughout MBTRAIN (REPAIR.partner gates
    // its mbinit-lane-mask update on this). It is NOT a live substate tracker.

    // MBTRAIN analog-settle timer
    localparam int unsigned MBTRAIN_SETTLE_DELAY = 16;
    logic        mbtrain_analog_settle_timer_en;
    logic        mbtrain_analog_settle_time_done;
    logic [$clog2(MBTRAIN_SETTLE_DELAY+1)-1:0] mbtrain_settle_cnt;

    // Latched lane masks (driven by MBINIT; declared early for MBTRAIN use)
    logic [2:0]  mb_rx_data_lane_mask_reg;
    logic [2:0]  mb_tx_data_lane_mask_reg;
    logic [15:0] active_lanes;

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
    logic       mb_lane_reversal_req_reg;
    logic        reg_Clock_Phase_enable_status_reg;
    logic        reg_Clock_mode_enable_status_reg;
    logic        reg_TARR_enable_status_reg;
    logic [3:0]  reg_Link_Width_enable_status_reg;
    logic [3:0]  reg_Link_Speed_enable_status_reg;
    logic        reg_PMO_enable_status_reg;
    logic        reg_L2SPD_enable_status_reg;
    logic        reg_PSPT_enable_status_reg;
    logic UCIe_x8_reg;
    logic [3:0] param_negotiated_speed;

    logic busy_bit_rst;

    logic  busy_flag_rst;
    assign busy_flag_rst = busy_bit_rst;


    logic [7:0] log0_state_n_reg;
    logic [7:0] log0_state_n_minus_1_reg;
    logic [7:0] log0_state_n_minus_2_reg;
    logic [7:0] log1_state_n_minus_3_reg;

    // ACTIVE next-state (unused until L1/L2/PHYRETRAIN exits are added)
    ltsm_ctrl_state_e active_next_ltsm_state;

    // Sideband RX, 8-bit form for the D2C point test
    msg_no_e sb_rx_msg_8;
    assign sb_rx_msg_8 = sb_rx_msg_id;

    RDI_state p_lp_state_req;
    logic Adapter_training_req;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_lp_state_req <= Nop;
        end else begin
            p_lp_state_req <= lp_state_req;
        end
    end
    assign Adapter_training_req = (p_lp_state_req == Nop && lp_state_req == Active && current_ltsm_state == RESET);

    logic [15:0] PHYRETRAIN_success_lanes;
    always_comb begin
        case (module_0_lane_repair_id_ctrl_out[4:0])
            5'd0:PHYRETRAIN_success_lanes = 16'b1111_1111_1111_1110;
            5'd1:PHYRETRAIN_success_lanes = 16'b1111_1111_1111_1101;
            5'd2:PHYRETRAIN_success_lanes = 16'b1111_1111_1111_1011;
            5'd3:PHYRETRAIN_success_lanes = 16'b1111_1111_1111_0111;
            5'd4:PHYRETRAIN_success_lanes = 16'b1111_1111_1110_1111;
            5'd5:PHYRETRAIN_success_lanes = 16'b1111_1111_1101_1111;
            5'd6:PHYRETRAIN_success_lanes = 16'b1111_1111_1011_1111;
            5'd7:PHYRETRAIN_success_lanes = 16'b1111_1111_0111_1111;
            5'd8:PHYRETRAIN_success_lanes = 16'b1111_1110_1111_1111;
            5'd9:PHYRETRAIN_success_lanes = 16'b1111_1101_1111_1111;
            5'd10:PHYRETRAIN_success_lanes = 16'b1111_1011_1111_1111;
            5'd11:PHYRETRAIN_success_lanes = 16'b1111_0111_1111_1111;
            5'd12:PHYRETRAIN_success_lanes = 16'b1110_1111_1111_1111;
            5'd13:PHYRETRAIN_success_lanes = 16'b1101_1111_1111_1111;
            5'd14:PHYRETRAIN_success_lanes = 16'b1011_1111_1111_1111;
            5'd15:PHYRETRAIN_success_lanes = 16'b0111_1111_1111_1111;
            default:PHYRETRAIN_success_lanes = 16'b1111_1111_1111_1111;
        endcase
    end
    //==========================================================================
    // runtime test ctrl change sense logic 
    //==========================================================================
    logic rt_link_test_changed;
    logic start_bit_reg,rt_apply_module_0_lane_repair_ctrl_out_reg;
    logic [6:0] module_0_lane_repair_id_ctrl_out_reg;
    state_n_e prev_ltsm_state_n;
    logic entry_PHYRETRAIN;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            prev_ltsm_state_n <= LOG_PHYRETRAIN;
        end else begin
            prev_ltsm_state_n <= current_ltsm_state_n;
        end
    end
    assign entry_PHYRETRAIN = (prev_ltsm_state_n != LOG_PHYRETRAIN && current_ltsm_state_n == LOG_PHYRETRAIN);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rt_apply_module_0_lane_repair_ctrl_out_reg <= 1'b0;
            module_0_lane_repair_id_ctrl_out_reg <= 7'b0;
            start_bit_reg <= 1'b0;
        end else if (entry_PHYRETRAIN) begin
            rt_apply_module_0_lane_repair_ctrl_out_reg <= rt_apply_module_0_lane_repair_ctrl_out;
            module_0_lane_repair_id_ctrl_out_reg <= module_0_lane_repair_id_ctrl_out;
            start_bit_reg <= start_bit;
        end
    end
    assign rt_link_test_changed = (rt_apply_module_0_lane_repair_ctrl_out != rt_apply_module_0_lane_repair_ctrl_out_reg) ||
                                  (module_0_lane_repair_id_ctrl_out != module_0_lane_repair_id_ctrl_out_reg) ||
                                  (start_bit != start_bit_reg);
    //==========================================================================
    logic [2:0] mb_pll_speed_sel_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mb_pll_speed_sel_reg <= 3'b000;
        end else if(current_ltsm_state_n == LOG_RESET) begin
            mb_pll_speed_sel_reg <= 3'b000;
        end else if (current_ltsm_state_n == LOG_MBTRAIN_SPEEDIDLE) begin
            mb_pll_speed_sel_reg <= reg_Link_Speed_enable_status[2:0];
        end
    end
    always_comb begin
        mb_pll_speed_sel = mb_pll_speed_sel_reg;

        if(current_ltsm_state_n == LOG_RESET) begin
            mb_pll_speed_sel = 3'b000;
        end else if (current_ltsm_state_n == LOG_MBTRAIN_SPEEDIDLE) begin
            mb_pll_speed_sel = reg_Link_Speed_enable_status[2:0];
        end
    end


// =============================================================================
    // LINK TRAINING / RETRAINING STATUS (to Register File)
    // =============================================================================
    assign link_training_retraining = (current_ltsm_state == SBINIT) ||
        (current_ltsm_state == MBINIT) ||
        (current_ltsm_state == MBTRAIN) ||
        (current_ltsm_state == LINKINIT) ||
        (current_ltsm_state == PHYRETRAIN);

    // =============================================================================
    // LINK STATUS (to Register File)
    // =============================================================================
    assign link_status = (current_ltsm_state == ACTIVE) ||
        (current_ltsm_state == PHYRETRAIN);
    // =========================================================================
    // STATE LOG REGISTERS (SHIFT & LATCH HISTORY)
    // =========================================================================
    state_n_e mbtrain_state_n;
    assign mbtrain_state_n = mbtrain_current_substate;

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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            log0_state_n_reg         <= 8'h00;
            log0_state_n_minus_1_reg <= 8'h00;
            log0_state_n_minus_2_reg <= 8'h00;
            log1_state_n_minus_3_reg <= 8'h00;
        end else begin
            if (current_log_state[4:0] != log0_state_n_reg[4:0]) begin
                log0_state_n_reg         <= {3'b0, current_log_state[4:0]};
                log0_state_n_minus_1_reg <= log0_state_n_reg;
                log0_state_n_minus_2_reg <= log0_state_n_minus_1_reg;
                log1_state_n_minus_3_reg <= log0_state_n_minus_2_reg;
            end
        end
    end

    logic [4:0] log0_state_n_comb;
    logic [4:0] log0_state_n_minus_1_comb;
    logic [4:0] log0_state_n_minus_2_comb;
    logic [4:0] log1_state_n_minus_3_comb;

    always_comb begin
        log0_state_n_comb         = log0_state_n_reg[4:0];
        log0_state_n_minus_1_comb = log0_state_n_minus_1_reg[4:0];
        log0_state_n_minus_2_comb = log0_state_n_minus_2_reg[4:0];
        log1_state_n_minus_3_comb = log1_state_n_minus_3_reg[4:0];

        if (current_log_state[4:0] != log0_state_n_reg[4:0]) begin
            log0_state_n_comb         = current_log_state[4:0];
            log0_state_n_minus_1_comb = log0_state_n_reg[4:0];
            log0_state_n_minus_2_comb = log0_state_n_minus_1_reg[4:0];
            log1_state_n_minus_3_comb = log0_state_n_minus_2_reg[4:0];
        end

    end

    assign log0_state_n         = {3'b0, log0_state_n_comb};
    assign log0_state_n_minus_1 = {3'b0, log0_state_n_minus_1_comb};
    assign log0_state_n_minus_2 = {3'b0, log0_state_n_minus_2_comb};
    assign log1_state_n_minus_3 = {3'b0, log1_state_n_minus_3_comb};

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

    // True while the shared D2C sweep engine owns the mainband — either the
    // MBINIT.REPAIRMB point test or a MBTRAIN sweep substate (muxed enables).
    logic d2c_active;
    assign d2c_active = sweep_local_en | sweep_partner_en;

    // =========================================================================
    // PHYRETRAIN (real block — sideband handshake + encoding resolution)
    // =========================================================================
    PHYRETRAIN u_phyretrain (
        .clk                                     (clk),
        .rst_n                                   (rst_n),
        .phyretrain_enable                       (phyretrain_en),
        .phyretrain_done                         (phyretrain_done),
        .phyretrain_error                        (phyretrain_error),
        .rt_apply_module_0_lane_repair_ctrl_out  (rt_apply_module_0_lane_repair_ctrl_out),
        .module_0_lane_repair_id_ctrl_out        (module_0_lane_repair_id_ctrl_out),
        .busy_bit_PHY_RETRAIN                    (busy_bit_PHY_RETRAIN),
        .mbinit_tx_data_lane_mask                (mb_tx_data_lane_mask_reg),
        .is_x8                                   (UCIe_x8_reg),
        .global_error                            (timeout_8ms_occured),
        .resolved_retrain_enc                    (phyretrain_resolved_enc),
        .tx_sb_msg_valid                         (phyretrain_tx_sb_msg_valid),
        .tx_sb_msg                               (phyretrain_tx_sb_msg),
        .tx_msginfo                              (phyretrain_tx_msginfo),
        .ltsm_rdy                                (sb_ltsm_rdy),
        .rx_sb_msg_valid                         (sb_rx_valid),
        .rx_sb_msg                               (sb_rx_msg_8),
        .rx_msginfo                              (sb_rx_MsgInfo)
    );

    // =========================================================================
    // MBTRAIN block / shared-sweep wiring  (declarations are up top)
    // =========================================================================
    // wrapper_D2C_sweep already drives local_test_d2c_done off its sweep_done port.
    assign local_test_d2c_done = d2c_sweep_done;

    // MBTRAIN analog-settle timer (mirrors unit_analog_settle_timer)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) mbtrain_settle_cnt <= '0;
        else if (mbtrain_analog_settle_timer_en) begin
            if (32'(mbtrain_settle_cnt) < MBTRAIN_SETTLE_DELAY)
                mbtrain_settle_cnt <= mbtrain_settle_cnt + 1'b1;
        end else mbtrain_settle_cnt <= '0;
    end
    assign mbtrain_analog_settle_time_done =
        (32'(mbtrain_settle_cnt) == MBTRAIN_SETTLE_DELAY) && mbtrain_analog_settle_timer_en;

    // Shared D2C sweep-engine input mux (MBINIT.REPAIRMB vs MBTRAIN). MBINIT and
    // MBTRAIN are never active simultaneously, so the single wrapper_D2C_sweep is
    // shared: enables/active-lanes come from MBTRAIN while in MBTRAIN, else MBINIT.
    assign sweep_local_en   = (current_ltsm_state == MBTRAIN) ? mbtrain_local_sweep_en
        : d2cpt_local_tx_pt_en;
    assign sweep_partner_en = (current_ltsm_state == MBTRAIN) ? mbtrain_partner_sweep_en
        : d2cpt_partner_tx_pt_en;
    assign sweep_active_lanes_mux = (current_ltsm_state == MBTRAIN) ? mbtrain_sweep_active_lanes
        : active_lanes;
    // =========================================================================
    // TRAINERROR HANDSHAKE INTEGRATION
    // =========================================================================
    logic        te_handshake_en;
    logic        te_local_error_trigger;
    logic        te_handshake_done;
    logic        te_tx_sb_msg_valid;
    msg_no_e     te_tx_sb_msg;
    logic [15:0] te_tx_msginfo;

    assign te_handshake_en = (current_ltsm_state == PHYRETRAIN || current_ltsm_state == MBINIT || current_ltsm_state == MBTRAIN || current_ltsm_state == LINKINIT);

    logic second_timeout_occured;
    assign second_timeout_occured = te_handshake_en && te_local_error_trigger && timeout_8ms_occured;

    // Watchdog reset on handshake start
    logic reset_timer_on_handshake_start;
    assign reset_timer_on_handshake_start = te_handshake_en && !te_local_error_trigger &&
        ((mbinit_error && (current_ltsm_state == MBINIT)) ||
            (mbtrain_ltsm_trainerror_req && (current_ltsm_state == MBTRAIN)) ||
            (linkinit_error && (current_ltsm_state == LINKINIT)) ||
            (phyretrain_error && (current_ltsm_state == PHYRETRAIN)));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            te_local_error_trigger <= 1'b0;
        end else if (te_handshake_en) begin
            // Trigger handshake on mbinit_error (in MBINIT), mbtrain_error (in MBTRAIN), linkinit_error (in LINKINIT), or timeout_8ms_occured
            if ((mbinit_error && (current_ltsm_state == MBINIT)) ||
                    (mbtrain_ltsm_trainerror_req && (current_ltsm_state == MBTRAIN)) ||
                    (linkinit_error && (current_ltsm_state == LINKINIT)) ||
                    (phyretrain_error && (current_ltsm_state == PHYRETRAIN)) ||
                    timeout_8ms_occured) begin
                // $display("T=%0t | [TRAINERROR DEBUG %m] TRIGGERED! mbinit_error=%b, mbtrain_ltsm_trainerror_req=%b, linkinit_error=%b, timeout_8ms_occured=%b, current_ltsm_state=%s, current_log_state=%s",
                //          $time, mbinit_error, mbtrain_ltsm_trainerror_req, linkinit_error, timeout_8ms_occured, current_ltsm_state.name(), current_log_state.name());
                if (te_local_error_trigger) begin
                    // If already running, a second timeout clears it
                    if (timeout_8ms_occured) begin
                        te_local_error_trigger <= 1'b0;
                    end
                end else begin
                    te_local_error_trigger <= 1'b1;
                end
            end
            // Clear on handshake done
            if (te_handshake_done) begin
                te_local_error_trigger <= 1'b0;
            end
        end else begin
            te_local_error_trigger <= 1'b0;
        end
    end

    trainerror_handshake u_trainerror_handshake (
        .clk                 (clk),
        .rst_n               (rst_n),
        .en                  (te_handshake_en),
        .local_error_trigger (te_local_error_trigger),
        .done                (te_handshake_done),
        .tx_sb_msg_valid     (te_tx_sb_msg_valid),
        .tx_sb_msg           (te_tx_sb_msg),
        .tx_msginfo          (te_tx_msginfo),
        .ltsm_rdy            (sb_ltsm_rdy),
        .rx_sb_msg_valid     (sb_rx_valid),
        .rx_sb_msg           (sb_rx_msg_8),
        .rx_msginfo          (sb_rx_MsgInfo)
    );

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
        .mbtrain_phyretrain_req (mbtrain_ltsm_phyretrain_req),
        .linkinit_en         (linkinit_en),
        .linkinit_done       (linkinit_done),
        .active_en           (active_en),
        .mbtrain_speedidle_req (mbtrain_speedidle_req),
        .phyretrain_en       (phyretrain_en),
        .phyretrain_done     (phyretrain_done),
        .l1_en               (l1_en),
        .l1_done             (l1_done),
        .l1_error            (l1_error),
        .l2_en               (l2_en),
        .l2_done             (l2_done),
        .l2_error            (l2_error),
        .trainerror_en       (trainerror_en),
        .trainerror_done     (trainerror_done),
        .te_handshake_done   (te_handshake_done),
        // Per-state errors. sbinit_error -> CTRL_TRAINERROR directly; the rest are
        // combined above into the §4.5.3.8 handshake trigger (te_handshake_done).
        .sbinit_error        (sbinit_error),
        .mbinit_error        (mbinit_error),
        .mbtrain_error       (mbtrain_ltsm_trainerror_req),
        .linkinit_error      (linkinit_error),
        .active_error        (active_error),
        .timeout_8ms_occured (timeout_8ms_occured),
        .second_timeout_occured(second_timeout_occured),
        // ACTIVE-resolved next state — drives the ACTIVE exit (PHYRETRAIN/L1/L2/TRAINERROR)
        .active_next_ltsm_state (active_next_ltsm_state),
        .rdi_state           (rdi_state),

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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PHY_IN_RETRAIN <= 1'b0;
        end else if (current_ltsm_state == PHYRETRAIN) begin
            PHY_IN_RETRAIN <= 1'b1;
        end else if (PHY_IN_RETRAIN_rst) begin
            PHY_IN_RETRAIN <= 1'b0;
        end
    end


    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_flag <= 1'b0;
        end else if (start_bit && (current_ltsm_state_n == LOG_PHYRETRAIN)) begin
            busy_flag <= 1'b1;
        end else if (busy_flag_rst) begin
            busy_flag <= 1'b0;
        end
    end
    
always_comb  begin
        busy_bit_PHY_RETRAIN = busy_flag ;
        if(start_bit && (current_ltsm_state_n == LOG_PHYRETRAIN))begin
            busy_bit_PHY_RETRAIN = 1'b1;
        end else if(busy_flag_rst) begin
            busy_bit_PHY_RETRAIN = 1'b0;
        end
    end

    logic timer_rst_n_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) timer_rst_n_q <= 1'b0;
        else        timer_rst_n_q <= ~(substate_changing || reset_timer_on_handshake_start);
    end
    assign timer_rst_n = timer_rst_n_q;

    // // === DEBUG: Watchdog timer monitoring ===
    // // synopsys translate_off
    // always_ff @(posedge clk) begin
    //     if (substate_changing)
    //         $display("T=%0t | [WATCHDOG DEBUG %m] substate_changing=1: prev=%s -> cur=%s, timer_rst_n_q will go LOW next cycle",
    //                  $time, prev_log_state.name(), current_log_state.name());
    //     if (timeout_8ms_occured && timeout_timer_en)
    //         $display("T=%0t | [WATCHDOG DEBUG %m] >>> TIMEOUT FIRED! current_ltsm_state=%s, current_log_state=%s, prev_log_state=%s, timer_rst_n=%b, te_local_error_trigger=%b",
    //                  $time, current_ltsm_state.name(), current_log_state.name(), prev_log_state.name(), timer_rst_n, te_local_error_trigger);
    // end
    // // synopsys translate_on

    // =========================================================================
    // 8 ms WATCHDOG TIMER (internal)
    // -------------------------------------------------------------------------
    // SPEED_AWARE: derive the 8 ms cycle count from the live mb_pll_speed_sel
    // (gated_lclk = mb_PLL/16) so it is a true 8 ms at whatever speed the link
    // is running — not a fraction/multiple of it as a fixed CLK_FRQ_HZ would
    // give once speed negotiation changes the clock.
    // =========================================================================
    timeout_counter #(
        .CLK_FRQ_HZ  (CLK_FRQ_HZ),
        .TIME_OUT    (8),
        .SPEED_AWARE (1'b1)
    ) u_timer_8ms (
        .clk             (clk),
        .timeout_rst_n   (timer_rst_n),
        .enable_timeout  (timeout_timer_en),
        .speed_sel       (mb_pll_speed_sel),
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
        .sb_det_pattern_rcvd                   (sb_det_pattern_rcvd_sticky),
        .RESET_enable                          (reset_en),
        .RESET_state_done                      (reset_done)
    );

    // Forward RESET completion out of the wrapper (RDI gating clears its
    // sideband-pattern ungate latch on this).
    assign RESET_state_done = reset_done;

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
        .partner_test_d2c_done(local_test_d2c_done),

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
    // 4. MBTRAIN (real block) — shares the single wrapper_D2C_sweep above
    // =========================================================================
    // Sweep code ranges left at wrapper defaults so the swept/best code widths
    // match the (default-parameterised) wrapper_D2C_sweep instance above.
    //
    // Config sourcing (flagged for review):
    //   * param_negotiated_max_speed <= reg_Target_Link_Speed_ctrl[2:0]
    //   * is_continuous_clk_mode     <= 1'b0  (strobed clock, matches verified MBTRAIN TB)
    //   * rf_cap_SPMW                <= SPMW
    //   * rf_ctrl_target_link_width  <= reg_Target_Link_Width_ctrl
    //   * param_UCIe_S_x8            <= reg_phy_x8_mode_ctrl
    //   * PHY_IN_RETRAIN             <= set when LTSM enters PHYRETRAIN state
    //   * mbtrain_*_req re-entry     <= driven by PHYRETRAIN resolved encoding + L1 exit
    wrapper_MBTRAIN #(
        // Must match the wrapper_D2C_sweep ranges above so swept/best code widths agree.
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE   (MAX_PI_PHASE_CODE),
        .MIN_DATA_PI_CODE   (1),
        .MAX_VAL_PI_CODE    (MAX_PI_PHASE_CODE),
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE    (1)
    ) u_mbtrain (
        .lclk                       (clk),
        .rst_n                      (rst_n),

        .mbtrain_en                 (mbtrain_en),
        .mbtrain_done               (mbtrain_done),
        .current_mbtrain_substate   (mbtrain_current_substate),

        .ltsm_trainerror_req        (mbtrain_ltsm_trainerror_req),
        .ltsm_linkinit_req          (mbtrain_ltsm_linkinit_req),
        .ltsm_phyretrain_req        (mbtrain_ltsm_phyretrain_req),

        // Re-entry selectors. PHYRETRAIN drives txselfcal/speedidle/repair via
        // resolved encoding; L1 exit drives speedidle via controller.
        .mbtrain_txselfcal_req      (phyretrain_mbtrain_txselfcal_req),
        .mbtrain_speedidle_req      (mbtrain_speedidle_req || phyretrain_mbtrain_speedidle_req),
        .mbtrain_repair_req         (phyretrain_mbtrain_repair_req),

        .analog_settle_time_done    (mbtrain_analog_settle_time_done),
        .analog_settle_timer_en     (mbtrain_analog_settle_timer_en),

        // Entry-context (static), per verified MBTRAIN contract — see above.
        // state_n_1 = DATAVREF selects the normal first-pass SPEEDIDLE entry
        // (re-entry from PHYRETRAIN/L1/L2 is not wired yet, so always normal).
        .state_n_0                  (state_n_e'(log0_state_n)),
        .state_n_1                  (state_n_e'(log0_state_n_minus_1)),

        .param_negotiated_max_speed (param_negotiated_speed[2:0]),
        .is_continuous_clk_mode     (reg_Clock_mode_enable_status_reg),
        .rf_cap_SPMW                (SPMW),
        .rf_ctrl_target_link_width  (reg_Target_Link_Width_ctrl),
        .param_UCIe_S_x8            (UCIe_x8_reg),

        .PHY_IN_RETRAIN             (PHY_IN_RETRAIN),
        .params_changed             (rt_link_test_changed),
        .PHY_IN_RETRAIN_rst         (PHY_IN_RETRAIN_rst),
        .busy_bit_rst               (busy_bit_rst),

        .mbinit_rx_data_lane_mask   (mb_rx_data_lane_mask_reg),
        .mbinit_tx_data_lane_mask   (mb_tx_data_lane_mask_reg),
        .mb_rx_data_lane_mask       (mbtrain_mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask       (mbtrain_mb_tx_data_lane_mask),

        // Shared D2C sweep engine (wrapper_D2C_sweep above)
        .local_sweep_en             (mbtrain_local_sweep_en),
        .partner_sweep_en           (mbtrain_partner_sweep_en),
        .sweep_active_lanes         (mbtrain_sweep_active_lanes),
        .sweep_done                 (d2c_sweep_done),
        .sweep_swept_code           (d2c_swept_code),
        .sweep_best_code            (d2c_best_code),
        .sweep_min_eye_width        (d2c_min_eye_width),

        .d2c_perlane_pass           (d2c_perlane_pass),

        .PHYRETRAIN_success_lanes   (PHYRETRAIN_success_lanes),

        // PHY analog controls — kept internal (mainband model ignores them)
        .phy_negotiated_speed       (mbtrain_phy_negotiated_speed),
        .phy_tx_selfcal_en          (mbtrain_phy_tx_selfcal_en),
        .phy_rx_clock_lock_en       (mbtrain_phy_rx_clock_lock_en),
        .phy_rx_track_lock_en       (mbtrain_phy_rx_track_lock_en),
        .phy_rx_phase_detector_en   (mbtrain_phy_rx_phase_detector_en),

        .phy_rx_tckn_shift          (5'd0),
        .phy_rx_decrement_shift     (1'b0),
        .phy_tx_tckn_shift_en       (mbtrain_phy_tx_tckn_shift_en),
        .phy_tx_tckn_shift          (mbtrain_phy_tx_tckn_shift),
        .phy_tx_decrement_shift     (mbtrain_phy_tx_decrement_shift),
        .phy_tx_tckn_shift_out_of_range (1'b0),

        .phy_rx_val_vref_ctrl       (),
        .phy_rx_data_vref_ctrl      (),
        .phy_tx_val_pi_phase_ctrl   (),
        .phy_tx_data_pi_phase_ctrl  (),
        .phy_rx_deskew_ctrl         (),
        .phy_tx_eq_preset_ctrl      (),
        .phy_tx_eq_preset_en        (),

        // Mainband lane selectors (routed by the mainband mux during MBTRAIN)
        .substate_mb_rx_clk_lane_sel  (mbtrain_sub_rx_clk_lane_sel),
        .substate_mb_rx_data_lane_sel (mbtrain_sub_rx_data_lane_sel),
        .substate_mb_rx_val_lane_sel  (mbtrain_sub_rx_val_lane_sel),
        .substate_mb_rx_trk_lane_sel  (mbtrain_sub_rx_trk_lane_sel),

        .rxclkcal_mb_tx_pattern_en      (mbtrain_rxclkcal_tx_pattern_en),
        .rxclkcal_mb_tx_pattern_setup   (mbtrain_rxclkcal_tx_pattern_setup),
        .rxclkcal_mb_tx_clk_pattern_sel (mbtrain_rxclkcal_tx_clk_pattern_sel),

        .substate_tx_sb_msg_valid   (mbtrain_tx_sb_msg_valid),
        .substate_tx_sb_msg         (mbtrain_tx_sb_msg),
        .substate_tx_msginfo        (mbtrain_tx_msginfo),
        .substate_tx_data_field     (mbtrain_tx_data_field),

        .rx_sb_msg_valid            (sb_rx_valid),
        .rx_sb_msg                  (sb_rx_msg_8),
        .rx_msginfo                 (sb_rx_MsgInfo)
    );

    // =========================================================================
    // 5. LINKINIT
    // =========================================================================
    linkinit u_linkinit (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .rdi_state_sts            (rdi_state),
        .Linkinit_enable          (linkinit_en),
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
    // 6a. L1 / L2 (real blocks, RDI-state driven)
    // =========================================================================
    // L1 exit (l1_done on rdi==Active) -> controller returns to ACTIVE.
    // L2 exit (l2_done on rdi==Reset)  -> controller returns to RESET.
    // l1_error / l2_error (rdi==LinkError) -> controller goes to TRAINERROR.
    L1 u_l1 (
        .clk           (clk),
        .rst_n         (rst_n),
        .l1_enable     (l1_en),
        .rdi_state_sts (rdi_state),
        .lp_state_req  (lp_state_req),
        .l1_done       (l1_done),
        .l1_error      (l1_error)
    );

    L2 u_l2 (
        .clk           (clk),
        .rst_n         (rst_n),
        .l2_enable     (l2_en),
        .rdi_state_sts (rdi_state),
        .l2_done       (l2_done),
        .l2_error      (l2_error)
    );

    // TRAINERROR (real block): latches on entry, HOLDs while rdi==LinkError, and
    // signals trainerror_done once the adapter clears the error -> controller -> RESET.
    TRAINERROR u_trainerror (
        .clk               (clk),
        .rst_n             (rst_n),
        .trainerror_enable (trainerror_en),
        .rdi_state_sts     (rdi_state),
        .trainerror_done   (trainerror_done)
    );

    // =========================================================================
    // 7. D2C POINT-TEST WRAPPER (real, shared MBINIT/MBTRAIN)
    // =========================================================================
    always_comb begin
        case (mb_rx_data_lane_mask_reg)
            3'b011:  active_lanes = 16'hFFFF;
            3'b001:  active_lanes = 16'h00FF;
            3'b010:  active_lanes = 16'hFF00;
            3'b100:  active_lanes = 16'h000F;
            3'b101:  active_lanes = 16'h00F0;
            default: active_lanes = 16'hFFFF;
        endcase
    end

    wrapper_D2C_sweep #(
        // Sweep ranges shrunk to the minimum so the full 13-substate MBTRAIN run
        // fits the integration TB's per-scenario lclk budget. Codes are inert in
        // this TB (the mainband model ignores analog codes), so range size only
        // affects sim time, not functional coverage of the training sequence.
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE  (1),
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE (1),
        .MAX_DATA_PI_CODE   (MAX_PI_PHASE_CODE),
        .MIN_DATA_PI_CODE   (1),
        .MAX_VAL_PI_CODE    (MAX_PI_PHASE_CODE),
        .MIN_VAL_PI_CODE    (1),
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE    (1)
    ) u_d2c (
        .lclk  (clk),
        .rst_n (rst_n),

        .active_lanes         (sweep_active_lanes_mux),
        .state_n              (current_log_state),
        .mb_rx_data_lane_mask (mb_rx_data_lane_mask_reg),

        .sweep_done            (d2c_sweep_done),
        .d2c_perlane_pass      (d2c_perlane_pass),
        .d2c_val_pass          (d2c_val_pass),
        .swept_code            (d2c_swept_code),
        .best_code             (d2c_best_code),
        .min_eye_width         (d2c_min_eye_width),

        .local_sweep_en       (sweep_local_en),
        .partner_sweep_en     (sweep_partner_en),

        .cfg_max_err_thresh_perlane (cfg_max_err_thresh_perlane),
        .cfg_max_err_thresh_aggr    (cfg_max_err_thresh_aggr),

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
        if (te_tx_sb_msg_valid) begin
            sb_tx_valid      = 1'b1;
            sb_tx_msg_id     = te_tx_sb_msg;
            sb_tx_MsgInfo    = te_tx_msginfo;
            sb_tx_data_Field = 64'h0;
        end else begin
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
                    // Substate handshake messages take priority; otherwise the shared
                    // D2C sweep engine's point-test messages own the SB bus.
                    if (mbtrain_tx_sb_msg_valid) begin
                        sb_tx_valid      = 1'b1;
                        sb_tx_msg_id     = msg_no_e'(mbtrain_tx_sb_msg);
                        sb_tx_MsgInfo    = mbtrain_tx_msginfo;
                        sb_tx_data_Field = mbtrain_tx_data_field;
                    end else if (d2c_tx_sb_msg_valid) begin
                        sb_tx_valid      = 1'b1;
                        sb_tx_msg_id     = msg_no_e'(d2c_tx_sb_msg);
                        sb_tx_MsgInfo    = d2c_tx_msginfo;
                        sb_tx_data_Field = d2c_tx_data_field;
                    end
                end
                PHYRETRAIN: begin
                    if (phyretrain_tx_sb_msg_valid) begin
                        sb_tx_valid      = 1'b1;
                        sb_tx_msg_id     = phyretrain_tx_sb_msg;
                        sb_tx_MsgInfo    = phyretrain_tx_msginfo;
                        sb_tx_data_Field = 64'h0;
                    end
                end
                default: ; // RESET / LINKINIT / ACTIVE: no SB TX
            endcase
        end
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
        else if (current_ltsm_state == MBTRAIN) begin
            // No sweep running (d2c_active handled above): the active MBTRAIN
            // substate owns the MB lane selectors; RXCLKCAL owns the clk pattern.
            mb_rx_clk_lane_sel    = mbtrain_sub_rx_clk_lane_sel;
            mb_rx_data_lane_sel   = mbtrain_sub_rx_data_lane_sel;
            mb_rx_val_lane_sel    = mbtrain_sub_rx_val_lane_sel;
            mb_rx_trk_lane_sel    = mbtrain_sub_rx_trk_lane_sel;
            mb_tx_pattern_en      = mbtrain_rxclkcal_tx_pattern_en;
            mb_tx_pattern_setup   = mbtrain_rxclkcal_tx_pattern_setup;
            mb_tx_clk_pattern_sel = mbtrain_rxclkcal_tx_clk_pattern_sel;
        end
        else if (current_ltsm_state == ACTIVE) begin
            mb_rx_val_lane_sel     = 1'b1;
            mb_rx_data_lane_sel    = 1'b1;
        end

        if (!d2c_active) begin
            mb_rx_pattern_setup    = mb_tx_pattern_setup;
            mb_rx_data_pattern_sel = mb_tx_data_pattern_sel;
        end
    end

    // mb_tx_trk_lane_sel, mb_tx_clk_lane_sel, mb_tx_val_lane_sel, mb_tx_data_lane_sel from MainSM (direct)
    always_comb begin
        mb_tx_trk_lane_sel=2'b01;
        mb_tx_clk_lane_sel=2'b01;
        mb_tx_val_lane_sel=2'b01;
        mb_tx_data_lane_sel=2'b01;
        case (current_ltsm_state_n)
            LOG_RESET,
            LOG_SBINIT,
            LOG_MBINIT_PARAM,
            LOG_MBINIT_CAL,
            LOG_MBTRAIN_TXSELFCAL,
            LOG_TRAINERROR,
            LOG_L1_L2:
            begin
                mb_tx_trk_lane_sel=2'b10;
                mb_tx_clk_lane_sel=2'b10;
                mb_tx_val_lane_sel =2'b10;
                mb_tx_data_lane_sel=2'b10;
            end
            LOG_MBINIT_REPAIRCLK: begin
                mb_tx_val_lane_sel  = 2'b10; // Hi-Z (not trained yet)
                mb_tx_data_lane_sel = 2'b10; // Hi-Z (not trained yet)
            end
            LOG_MBINIT_REPAIRVAL: begin
                mb_tx_data_lane_sel=2'b00;
            end
            LOG_MBTRAIN_RXCLKCAL:
            begin
                mb_tx_val_lane_sel = 2'b00;
                mb_tx_data_lane_sel = 2'b00;
            end
            LOG_MBTRAIN_VALVREF,
            LOG_MBTRAIN_VALTRAINCENTER,
            LOG_MBTRAIN_VALTRAINVREF:
            begin
                mb_tx_trk_lane_sel = 2'b00;
                mb_tx_data_lane_sel = 2'b00;
            end
            LOG_MBTRAIN_DATAVREF,
            LOG_MBTRAIN_DATATRAINCENTER1,
            LOG_MBTRAIN_DATATRAINVREF,
            LOG_MBTRAIN_RXDESKEW,
            LOG_MBTRAIN_DATATRAINCENTER2,
            LOG_MBTRAIN_LINKSPEED:
            begin
                mb_tx_trk_lane_sel = 2'b00;
            end
            LOG_MBTRAIN_SPEEDIDLE,
            LOG_LINKINIT,
            LOG_PHYRETRAIN,
            LOG_MBTRAIN_REPAIR:
            begin
                mb_tx_trk_lane_sel = 2'b00;
                mb_tx_clk_lane_sel = 2'b00;
                mb_tx_val_lane_sel = 2'b00;
                mb_tx_data_lane_sel = 2'b00;
            end
            default: begin
                mb_tx_trk_lane_sel = 2'b01;
                mb_tx_clk_lane_sel = 2'b01;
                mb_tx_val_lane_sel = 2'b01;
                mb_tx_data_lane_sel = 2'b01;
            end

        endcase
    end

    // =========================================================================
    // SEQUENTIAL LATCHING & LOOKAHEAD FOR MBINIT OUTPUTS
    // =========================================================================
    function automatic logic [3:0] get_width_code(logic [2:0] map);
        case (map)
            3'b011:  return 4'h2; // x16
            3'b001:  return 4'h1; // x8 lower
            3'b010:  return 4'h1; // x8 upper
            3'b100:  return 4'h0; // x4 lower
            3'b101:  return 4'h0; // x4 upper
            default: return 4'h0;
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            UCIe_x8_reg <= 1'b0;
            param_negotiated_speed <= 4'h0;
        end
        else if(current_ltsm_state_n == LOG_RESET) begin
            UCIe_x8_reg <= 1'b0;
            param_negotiated_speed <= 4'h0;
        end
        else if(current_ltsm_state_n == LOG_MBINIT_CAL)begin
            UCIe_x8_reg <= mbinit_reg_Link_Width_enable_status == 4'h1 ? 1'b1: 1'b0;
            param_negotiated_speed <= reg_Link_Speed_enable_status_reg;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mb_rx_data_lane_mask_reg          <= 3'b011;
            mb_tx_data_lane_mask_reg          <= 3'b011;
            mb_lane_reversal_req_reg          <= 1'b0;
            reg_Clock_Phase_enable_status_reg <= 1'b0;
            reg_Clock_mode_enable_status_reg  <= 1'b0;
            reg_TARR_enable_status_reg        <= 1'b0;
            reg_Link_Width_enable_status_reg  <= 4'h2;
            reg_Link_Speed_enable_status_reg  <= 4'h0;
            reg_PMO_enable_status_reg         <= 1'b0;
            reg_L2SPD_enable_status_reg       <= 1'b0;
            reg_PSPT_enable_status_reg        <= 1'b0;
        end else if (current_ltsm_state == RESET) begin
            mb_rx_data_lane_mask_reg          <= 3'b011;
            mb_tx_data_lane_mask_reg          <= 3'b011;
            mb_lane_reversal_req_reg          <= 1'b0;
            reg_Clock_Phase_enable_status_reg <= 1'b0;
            reg_Clock_mode_enable_status_reg  <= 1'b0;
            reg_TARR_enable_status_reg        <= 1'b0;
            reg_Link_Width_enable_status_reg  <= 4'h2;
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
        end else if (current_ltsm_state == MBTRAIN) begin
            // Only latch the MBTRAIN-final lane masks when MBTRAIN is done
            // (mbtrain_ltsm_linkinit_req = 1).  Capturing every cycle would
            // overwrite the MBINIT-negotiated mask with the REPAIR_partner's
            // soft-reset default (3'b011) during the early substates of MBTRAIN.
            if (current_ltsm_state_n != LOG_MBTRAIN_VALVREF) begin
                if (mbtrain_mb_rx_data_lane_mask != 3'b000)
                    mb_rx_data_lane_mask_reg      <= mbtrain_mb_rx_data_lane_mask;
                if (mbtrain_mb_tx_data_lane_mask != 3'b000)
                    mb_tx_data_lane_mask_reg      <= mbtrain_mb_tx_data_lane_mask;
            end
            reg_Link_Speed_enable_status_reg  <= {1'b0,mbtrain_phy_negotiated_speed};
        end
        else if(current_ltsm_state_n == LOG_LINKINIT)begin
            reg_Link_Width_enable_status_reg <= get_width_code(mb_tx_data_lane_mask_reg);
        end
    end

    always_comb begin
        mb_rx_data_lane_mask          = mb_rx_data_lane_mask_reg;
        mb_tx_data_lane_mask          = mb_tx_data_lane_mask_reg;
        mb_lane_reversal_req          = mb_lane_reversal_regit q_reg;
        reg_Clock_Phase_enable_status = reg_Clock_Phase_enable_status_reg;
        reg_Clock_mode_enable_status  = reg_Clock_mode_enable_status_reg;
        reg_TARR_enable_status        = reg_TARR_enable_status_reg;
        reg_Link_Width_enable_status  = reg_Link_Width_enable_status_reg;
        reg_Link_Speed_enable_status  = reg_Link_Speed_enable_status_reg;
        reg_PMO_enable_status         = reg_PMO_enable_status_reg;
        reg_L2SPD_enable_status       = reg_L2SPD_enable_status_reg;
        reg_PSPT_enable_status        = reg_PSPT_enable_status_reg;

    end

    assign sb_pattern_mode      = (current_ltsm_state == RESET) || (sbinit_pattern_mode && current_ltsm_state == SBINIT);

endmodule
