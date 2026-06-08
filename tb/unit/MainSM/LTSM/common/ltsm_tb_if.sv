`timescale 1ps/1ps
`ifndef LTSM_TB_IF_SV
`define LTSM_TB_IF_SV

import UCIe_pkg::*;
import ltsm_state_n_pkg::*;

interface ltsm_tb_if #(
        parameter int MAX_VAL_VREF_CODE  = 16,
        parameter int MAX_DATA_VREF_CODE = 16,
        parameter int MAX_VAL_PI_CODE    = 16,
        parameter int MAX_DATA_PI_CODE   = 16,
        parameter int MAX_DESKEW_CODE    = 16
    ) (
        input logic lclk,
        input logic rst_n
    );

    localparam int VAL_VREF_WIDTH  = $clog2(MAX_VAL_VREF_CODE + 1);
    localparam int DATA_VREF_WIDTH = $clog2(MAX_DATA_VREF_CODE + 1);
    localparam int VAL_PI_WIDTH    = $clog2(MAX_VAL_PI_CODE + 1);
    localparam int DATA_PI_WIDTH   = $clog2(MAX_DATA_PI_CODE + 1);
    localparam int DESKEW_WIDTH    = $clog2(MAX_DESKEW_CODE + 1);

    localparam int MAX_VREF_TEMP = (MAX_VAL_VREF_CODE > MAX_DATA_VREF_CODE) ? MAX_VAL_VREF_CODE : MAX_DATA_VREF_CODE;
    localparam int MAX_PI_TEMP   = (MAX_VAL_PI_CODE > MAX_DATA_PI_CODE) ? MAX_VAL_PI_CODE : MAX_DATA_PI_CODE;
    localparam int MAX_CODE_TEMP = (MAX_VREF_TEMP > MAX_PI_TEMP) ? MAX_VREF_TEMP : MAX_PI_TEMP;
    localparam int MAX_CODE      = (MAX_CODE_TEMP > MAX_DESKEW_CODE) ? MAX_CODE_TEMP : MAX_DESKEW_CODE;
    localparam int CW = $clog2(MAX_CODE + 1);


    // State log signal (dynamic state_n)
    state_n_e state_n [4];

    // =========================================================================
    // Sideband Interface (DUT <-> Partner)
    // =========================================================================
    logic        tx_sb_msg_valid;
    logic [7:0]  tx_sb_msg;
    logic [15:0] tx_msginfo;
    logic [63:0] tx_data_field;

    logic        rx_sb_msg_valid;
    logic [7:0]  rx_sb_msg;
    logic [15:0] rx_msginfo;
    logic [63:0] rx_data_field;

    // =========================================================================
    // Mainband Macro Behavior Interface
    // =========================================================================
    // Outputs from DUT to MB
    logic [1:0]  mb_tx_trk_lane_sel;
    logic [1:0]  mb_tx_clk_lane_sel;
    logic [1:0]  mb_tx_val_lane_sel;
    logic [1:0]  mb_tx_data_lane_sel;

    logic        mb_rx_trk_lane_sel;
    logic        mb_rx_clk_lane_sel;
    logic        mb_rx_val_lane_sel;
    logic        mb_rx_data_lane_sel;

    // Controls to MB Macro
    logic        mb_tx_pattern_en;
    logic [2:0]  mb_tx_pattern_setup;
    logic [15:0] mb_tx_iter_count;
    logic [15:0] mb_tx_burst_count;
    logic [15:0] mb_tx_idle_count;

    logic        mb_rx_compare_en;
    logic [2:0]  mb_rx_pattern_setup;
    logic [15:0] mb_rx_iter_count;
    logic [15:0] mb_rx_burst_count;
    logic [15:0] mb_rx_idle_count;

    // Status from MB Macro to DUT
    logic        mb_tx_pattern_count_done;
    logic        mb_rx_compare_done;
    logic [15:0] mb_rx_perlane_pass;
    logic        mb_rx_aggr_pass;
    logic        mb_rx_val_pass;

    // =========================================================================
    // Watchdog and TB Control
    // =========================================================================
    logic        tb_suppress_rx_sb;
    logic [15:0] tb_force_perlane_pass;
    logic        tb_force_aggr_pass;
    logic        tb_force_val_pass;
    logic        tb_verbose;
    logic        tb_wait_timeout;
    logic [15:0] tb_aggr_err;

    // =========================================================================
    // Negotiated Link Parameters and Decoders
    // =========================================================================
    logic [2:0]  mb_rx_data_lane_mask;
    logic [2:0]  mb_tx_data_lane_mask;
    logic [2:0]  phy_negotiated_speed;
    logic        is_high_speed;
    logic [15:0] active_rx_lanes;
    logic [15:0] active_tx_lanes;
    logic [15:0] final_perlane_pass;

    // Configuration Thresholds
    logic [11:0] cfg_max_err_thresh_perlane;
    logic [15:0] cfg_max_err_thresh_aggr;
    wire [11:0] cfg_train4_max_err_thresh_perlane = cfg_max_err_thresh_perlane;
    wire [15:0] cfg_train4_max_err_thresh_aggr = cfg_max_err_thresh_aggr;

    // FSM Control Inputs/Outputs
    logic        partner_sweep_en;

    // D2C Sweep Interface (For Local FSM)
    logic        sweep_en;
    logic [CW-1:0] swept_code;
    logic [CW-1:0] best_code [0:15];
    logic [CW-1:0] min_eye_width;
    logic        sweep_done;

    // Broadcast D2C PT Status
    logic        local_test_d2c_done;
    logic        partner_test_d2c_done;
    logic [15:0] d2c_perlane_pass;
    logic        d2c_aggr_pass;
    logic        d2c_val_pass;

    // Watchdog and Timer Signals
    logic        timeout_timer_en;
    logic        timeout_8ms_occured;
    logic        analog_settle_timer_en;
    logic        analog_settle_time_done;

    // PHY Vref Control (for VALVREF and VALTRAINVREF substates)
    logic [VAL_VREF_WIDTH-1:0]  phy_rx_valvref_ctrl;

    // PHY Vref Control (for DATAVREF substate)
    logic [DATA_VREF_WIDTH-1:0]  phy_rx_datavref_ctrl [0:15];

    // PHY PI Phase Control (for VALTRAINCENTER substate)
    logic [VAL_PI_WIDTH-1:0]  phy_tx_val_pi_phase_ctrl;

    // PHY PI Phase Control (for DATATRAINCENTER1/2 substates)
    logic [DATA_PI_WIDTH-1:0]  phy_tx_data_pi_phase_ctrl [0:15];

    // PHY IQ Calibration Control (for RXCLKCAL)
    logic        phy_rx_clock_lock_en;
    logic        phy_rx_track_lock_en;
    logic        phy_rx_phase_detector_en;

    // PHY TCKN Shift Control (for RXCLKCAL partner)
    logic        phy_tx_tckn_shift_en;
    logic [4:0]  phy_tx_tckn_shift;
    logic        phy_tx_decrement_shift;

    // MB Pattern Controls
    logic [1:0]  mb_tx_clk_pattern_sel;

    // Sideband MUX and Attachments outputs
    logic        wrapper_tx_sb_msg_valid;
    logic [7:0]  wrapper_tx_sb_msg;
    logic [15:0] wrapper_tx_msginfo;
    logic [63:0] wrapper_tx_data_field;

    logic        tb_muxed_tx_sb_msg_valid;
    logic [7:0]  tb_muxed_tx_sb_msg;
    logic [15:0] tb_muxed_tx_msginfo;
    logic [63:0] tb_muxed_tx_data_field;

    // =========================================================================
    // REPAIR and Unit Testbench Additional Signals
    // =========================================================================
    logic [15:0] tb_rx_msginfo;
    logic [63:0] tb_rx_data_field;
    logic [15:0] tb_perlane_err;
    logic        tb_val_err;
    logic        tb_clk_err;
    logic        tb_wrong_sb_msg_en;
    msg_no_e     tb_wrong_sb_msg;
    logic [15:0] tb_wrong_msginfo;
    logic [63:0] tb_wrong_data_field;
    logic        repair_en;
    logic        rx_pt_en;
    logic        tx_pt_en;
    logic        rf_cap_SPMW;
    logic [3:0]  rf_ctrl_target_link_width;
    logic [15:0] linkspeed_success_lanes;
    logic        param_UCIe_S_x8;
    logic [2:0]  degraded_lane_map_code;    // Degraded lane map code output from unit_negotiated_lanes
    logic        degrade_feasible;          // 1: degradation configuration is feasible
    logic        txselfcal_req;
    logic        trainerror_req;
    logic        is_ltsm_out_of_reset;
    logic        repair_done;

    // D2C PT and Testbench Control signals accessed by ltsm_tb_attachments
    logic        local_tx_pt_en;
    logic        partner_tx_pt_en;
    logic        local_rx_pt_en;
    logic        partner_rx_pt_en;
    logic [1:0]  d2c_clk_sampling;
    logic [2:0]  d2c_pattern_setup;
    logic [1:0]  d2c_data_pattern_sel;
    logic        d2c_val_pattern_sel;
    logic        d2c_pattern_mode;
    logic [15:0] d2c_burst_count;
    logic [15:0] d2c_idle_count;
    logic [15:0] d2c_iter_count;
    logic [1:0]  d2c_compare_setup;
    logic [15:0] tb_perlane_pass;
    logic        tb_val_pass;
    logic [15:0] mb_rx_aggr_err;

    // Modports (if needed)
    modport dut (
        input  lclk, rst_n,
        output tx_sb_msg_valid, tx_sb_msg, tx_msginfo, tx_data_field,
        input  rx_sb_msg_valid, rx_sb_msg, rx_msginfo, rx_data_field,

        output mb_tx_trk_lane_sel, mb_tx_clk_lane_sel, mb_tx_val_lane_sel, mb_tx_data_lane_sel,
        output mb_rx_trk_lane_sel, mb_rx_clk_lane_sel, mb_rx_val_lane_sel, mb_rx_data_lane_sel,
        output mb_tx_pattern_en, mb_tx_pattern_setup, mb_tx_iter_count, mb_tx_burst_count, mb_tx_idle_count,
        output mb_rx_compare_en, mb_rx_pattern_setup, mb_rx_iter_count, mb_rx_burst_count, mb_rx_idle_count,

        input  mb_tx_pattern_count_done, mb_rx_compare_done, mb_rx_perlane_pass, mb_rx_aggr_pass, mb_rx_val_pass
    );

endinterface

`endif // LTSM_TB_IF_SV





