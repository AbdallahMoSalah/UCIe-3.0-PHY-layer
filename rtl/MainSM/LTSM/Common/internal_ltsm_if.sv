// This interface file needs these packages before we compile it:
//      rtl/common/UCIe_pkg.sv
//      rtl/MainSM/LTSM/common/ltsm_state_n_pkg.sv
//      rtl/MainSM/common/LTSM_state_pkg.sv

interface internal_ltsm_if #(
        parameter MAX_VAL_VREF_CODE  = 'D127, // for Reference Rx Valid Lane Vref control.
        parameter MAX_DATA_VREF_CODE = 'D127  // for Reference Rx Data Lanes Vref control.
    ) (
        input logic lclk,
        input logic rst_n
    );

    // For analog Voltage control.
    localparam VAL_VREF_CODE_WIDTH  = $clog2(MAX_VAL_VREF_CODE );
    localparam DATA_VREF_CODE_WIDTH = $clog2(MAX_DATA_VREF_CODE);

    // current and previous states.
    import ltsm_state_n_pkg::state_n_e         ; state_n_e          state_n[3:0]            ; // for RF (to log the last 4 states names). state_n[0]: current state, state_n[1]: previous state, state_n[2]: previous previous state, state_n[3]: previous previous previous state.
    import LTSM_state_pkg  ::LTSM_state_e      ; LTSM_state_e       current_ltsm_state      ; // for RF (to know the current unit_LTSM_ctrl state)
    import ltsm_state_n_pkg::mbinit_substate_e ; mbinit_substate_e  current_mbinit_substate ; // for RF (to know the current unit_MBINIT_ctrl substate)
    import ltsm_state_n_pkg::mbtrain_substate_e; mbtrain_substate_e current_mbtrain_substate; // for RF (to know the current unit_MBTRAIN_ctrl substate)




    // enable, done, and req signals for the `ltsm_ctrl` states
    logic reset_en           , reset_done           , reset_req                 ;  // the reset_req signal is used for telling the `ltsm_ctrl` to enter the RESET state.
    logic sbinit_en          , sbinit_done                                      ;
    logic mbinit_en          , mbinit_done                                      ;
    logic mbtrain_en         , mbtrain_done                                     ;
    logic linkinit_en        , linkinit_done        , linkinit_req              ;
    logic active_en                                                             ;
    logic phyretrain_en      , phyretrain_done      , phyretrain_req            ; // the phyretrain_req signal is used for telling the `ltsm_ctrl` to enter the PHYRETRAIN state.
    logic trainerror_en      , trainerror_done      , trainerror_req            ; // the trainerror_req signal is used for telling the `ltsm_ctrl` to enter the TREAINERROR state.

    // enable, done, and fail_flag signals for the MBINIT sub-states:
    logic param_en           , param_done                                       ;
    logic cal_en             , cal_done                                         ;
    logic repairclk_en       , repairclk_done                                   ;
    logic repairval_en       , repairval_done                                   ;
    logic reversalmb_en      , reversalmb_done                                  ;
    logic repairmb_en        , repairmb_done        , repairmb_fail_flag        ; // repairmb_fail_flag: For MBINIT.RepairMB FSM state: To report if the RepairMB FSM failed to repair the MB.

    // enable, done and fail_flag signals for the MBTRAIN sub-states:
    logic mbtrain_repair_req , mbtrain_speedidle_req, mbtrain_txselfcal_req;
    logic valvref_en         , valvref_done                                     ;
    logic datavref_en        , datavref_done        , datavref_fail_flag        ; // datavref_fail_flag: For MBTRAIN.DATAVREF FSM state: To report if the Data  Vref calibration failed.
    logic speedidle_en       , speedidle_done       , speedidle_req             ;
    logic txselfcal_en       , txselfcal_done                                   ;
    logic rxclkcal_en        , rxclkcal_done                                    ;
    logic valtraincenter_en  , valtraincenter_done  , valtraincenter_fail_flag  ; // valtraincenter_fail_flag: For MBTRAIN.VALTRAINCENTER FSM state: To report if there was a fail in calibration.
    logic valtrainvref_en    , valtrainvref_done    , valtrainvref_fail_flag    ; // valtrainvref_fail_flag: For MBTRAIN.VALTRAINVREF FSM state: To report if the Valid Vref calibration failed.
    logic datatraincenter1_en, datatraincenter1_done, datatraincenter1_fail_flag, datatraincenter1_req;
    logic datatrainvref_en   , datatrainvref_done   , datatrainvref_fail_flag   ;
    logic rxdeskew_en        , rxdeskew_done        , rxdeskew_fail_flag        ; // rxdeskew_fail_flag: For MBTRAIN.RXDESKEW FSM state: To report if the per-lane deskew failed.
    logic datatraincenter2_en, datatraincenter2_done, datatraincenter2_fail_flag;
    logic linkspeed_en       , linkspeed_done       , linkspeed_fail_flag       ; // linkspeed_fail_flag: For MBTRAIN.LINKSPEED FSM state: To report if there was a problem.
    logic repair_en          , repair_done          , repair_req                ;


    //=====================================//
    // Control Signals For Timers:         //
    //=====================================//
    logic timeout_timer_en      , timeout_8ms_occured    ;
    logic analog_settle_timer_en, analog_settle_time_done;




    //=====================================//
    // Control Signals From RDI:           //
    //=====================================//
    logic [3:0] state_req   ; // To know if the next state is TRAINERROR or not.
    logic [3:0] state_status; // To tell RDI the current state.

    //=====================================//
    // Control Signals For MB:              //
    //=====================================//

    //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
    // Clock Sampling and Shapes Details Group:
    logic        mb_tx_clk_shape               ; // 0: Differential clocking, 1: Quadrature clocking.
    logic        mb_tx_continuous_or_strobe_clk; // 0: continuous mode clock, 1: strobe mode clock.
    logic        mb_tx_clk_sampling_en         ; // Enable changing Clock sampling/PI phase control state.
    logic [1:0]  mb_tx_clk_sampling            ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

    // Tx Pattern Generator Setup Group:
    logic        mb_tx_pattern_en      ; // 1: Send pattern immediately, 0: Don't send pattern.
    logic [2:0]  mb_tx_pattern_setup   ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    logic [1:0]  mb_tx_data_pattern_sel; // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
    logic        mb_tx_val_pattern_sel ; // 0: VALTRAIN pattern, 1: Held Low.
    logic        mb_tx_lfsr_en         ; // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
    logic        mb_tx_lfsr_rst        ; // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
    logic        mb_rx_lfsr_en         ; // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
    logic        mb_rx_lfsr_rst        ; // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.
    logic [1:0]  mb_tx_clk_pattern_sel ; // 2'b00: operational clock, 2'b01: Held Low, 2'b10: Clock Mode 1, 2'b11: Clock Mode 2.

    // Tx Pattern Mode Setup Group:
    logic        mb_tx_pattern_mode      ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
    logic [15:0] mb_tx_burst_count       ; // Burst Count: Indicates the duration of selected pattern (UI count).
    logic [15:0] mb_tx_idle_count        ; // IDLE Count: Indicates the duration of low following the burst (UI count).
    logic [15:0] mb_tx_iter_count        ; // Iterations: Indicates the iteration count of bursts followed by idle.
    logic        mb_tx_pattern_count_done; // Asserted (=1) once MB completes the iter_count.

    // Receiver Comparison Setup & Errors
    logic        mb_rx_compare_en            ; // 1: Enable the Rx comparison circuit, 0: Disable.
    logic [15:0] mb_rx_max_err_thresh_aggr   ; // Max error Threshold in aggregate comparison.
    logic [11:0] mb_rx_max_err_thresh_perlane; // Max error Threshold in per Lane comparison.
    logic [1:0]  mb_rx_compare_setup         ; // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
    logic [15:0] mb_rx_aggr_err              ; // The total calculated Aggregate Errors on Rx.
    logic [15:0] mb_rx_perlane_err           ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
    logic        mb_rx_val_err               ; // The error coming from Valid Lane receiver in MB.
    logic        mb_rx_clk_err               ; // The error coming from Clock Lane receiver in MB.
    logic        mb_rx_compare_done          ; // From MB to LTSM to tell that comparison of burst_count, track, clock, valid signals receiveing is done.

    //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//

    // MB Lane Control
    // For mb_rx_data_lane_mask or mb_tx_data_lane_mask
    // 000b:  None (Degrade not possible)
    // 001b: Logical Lanes 0 to 7
    // 010b: Logical Lanes 8 to 15
    // 011b: Logical Lanes 0 to 15
    // 100b: Logical Lanes 0 to 3
    // 101b: Logical Lanes 4 to 7
    logic [2:0]  mb_rx_data_lane_mask; // Describes the Functional Rx Lanes (Active Lanes).
    logic [2:0]  mb_tx_data_lane_mask; // Describes the Functional Tx Lanes (Active Lanes).
    logic        mb_mapper_en        ; // 0: Disable the mapper, 1: Enable the mapper.

    // Lane Behavior Control
    logic [1:0]  mb_tx_clk_lane_sel ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
    logic [1:0]  mb_tx_data_lane_sel; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
    logic [1:0]  mb_tx_val_lane_sel ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
    logic [1:0]  mb_tx_trk_lane_sel ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
    logic        mb_rx_clk_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
    logic        mb_rx_data_lane_sel; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
    logic        mb_rx_val_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
    logic        mb_rx_trk_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

    // PHY Level Control & Analog Interface
    logic        phy_tx_selfcal_en         ; // Enable Tx Self Calibration. It's Used in TXSELFCAL FSM.
    logic [2:0]  phy_negotiated_speed      ; // Target Link Speed (0h: 4 GT/s; 1h: 8 GT/s; 2h: 12 GT/s; ... ; or 7h: 64 GT/s)
    logic        phy_rx_clock_lock_en      ; // Allow analog Rx circuit to Lock the coming clock.
    logic        phy_rx_track_lock_en      ; // Allow analog Rx circuit to Lock the coming Track.
    logic        phy_rx_phase_detector_en  ; // Activate Phase Detector Circuit for IQ clock phase shift test.
    logic        phy_tx_tckn_shift_en      ; // Activate circuits to calculate shift on partner TCKN_L.
    logic [4:0]  phy_tx_tckn_shift         ; // The shift applied on our die's TCKN_L.
    logic        phy_tx_decrement_shift    ; // Direction of shift on our die.
    logic        phy_tx_tckn_shift_out_of_range; // Extent of shift limit hit on our die.
    logic [4:0]  phy_rx_tckn_shift         ; // The required shift of the partner TCKN_L (range 0 to 12).
    logic        phy_rx_decrement_shift    ; // Direction of shift: 1b (earlier), 0b (later).
    logic [VAL_VREF_CODE_WIDTH-1 :0] phy_rx_valvref_ctrl       ; // Tell ADC the Rx Valid Lane Vref level to operate in.
    logic [DATA_VREF_CODE_WIDTH-1:0] phy_rx_datavref_ctrl[15:0]; // Tell ADC the Rx Data Lane Vref level to operate in.
    logic [5:0]  phy_tx_pi_phase_ctrl      ; // Tell ADC the Tx Clock Lane PI phase level.
    logic [6:0]  phy_rx_deskew_ctrl[15:0]  ; // Tell ADC the Rx deskew level for each data lane (16 lanes x 6 bits).
    logic [2:0]  phy_tx_eq_preset_ctrl     ; // Choose the EQ Tx Preset to use (for speed > 32 GT/s).
    logic        phy_rx_clk_drift_cal_state; // 1b: Calibration done successfully (drift is small), 0b: Needs TARR.
    logic        phy_rx_clk_drift_cal_valid; // Tells LTSM if phy_rx_clk_drift_cal_state is ready.

    logic [2:0]  param_negotiated_max_speed;


    //=================================================//
    // Control Signals For (Rx init D to C point test) //
    // Control Signals For (Tx init D to C point test) //
    //=================================================//
    logic substate_timeout_8ms_occured;
    logic        rx_pt_en;
    logic        tx_pt_en;
    logic        test_d2c_done;
    logic [1:0]  d2c_clk_sampling    ;  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
    logic        d2c_timeout_or_error; // Tell the external Sub-state if timeout or error occurs during the test to move to TRAINERROR state.

    //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
    // Received Tx Pattern Generator Setup Group:
    logic        d2c_lfsr_en         ; // 1: Enable the Tx & Rx LFSR when use the Rx or Tx FSM Test, 0: Disable the Tx & Rx LFSR.
    logic [2:0]  d2c_pattern_setup   ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    logic [1:0]  d2c_data_pattern_sel; // Data pattern used during training: LFSR, ID, or all 0.
    logic        d2c_val_pattern_sel ; // 0: VALTRAIN pattern, 1: Held Low.

    // Received Tx Pattern Mode Setup Group:
    logic        d2c_pattern_mode; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
    logic [15:0] d2c_burst_count ; // Burst Count: Indicates the duration of selected pattern (UI count).
    logic [15:0] d2c_idle_count  ; // IDLE Count: Indicates the duration of low following the burst (UI count).
    logic [15:0] d2c_iter_count  ; // Iteration Count: Indicates the iteration count of bursts followed by idle.

    // Received Receiver Comparison Setup & Errors
    logic [1:0]  d2c_compare_setup; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
    logic [15:0] d2c_aggr_err     ; // The total calculated Aggregate Errors on Rx.
    logic [15:0] d2c_perlane_err  ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
    logic        d2c_val_err      ; // The error coming from Valid Lane receiver in MB.
    logic        d2c_clk_err      ; // The error coming from Clock Lane receiver in MB.
    logic        partner_valtraincenter_fail_flag ; // From our UCIe die Rx. It represents the fail flags of the partner Tx Valid lane.
    logic        partner_datatraincenter_fail_flag; // From our UCIe die Rx. It represents the fail flags of the partner Tx Data lanes.

    //=====================================//
    // Sideband Control Signals:           //
    //=====================================//
    import UCIe_pkg::msg_no_e;

    // For SB TX:
    logic        tx_sb_msg_valid; // Tell the SB that the selected message is valid.
    msg_no_e     tx_sb_msg      ; // Tell the Sideband the message that it should to send.
    logic [15:0] tx_msginfo     ; // MsgInfo field of the SB message.
    logic [63:0] tx_data_field  ; // Data field of the SB message.

    // For SB RX:
    logic        rx_sb_msg_valid; // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
    msg_no_e     rx_sb_msg      ; // Get the Received SB msg.
    logic [15:0] rx_msginfo     ; // MsgInfo field of the SB message received.
    logic [63:0] rx_data_field  ; // Data field of the SB message.


    //=====================================//
    // Register File (RF) Control Signals: //
    //=====================================//
    //  UCIe Link DVSEC - UCIe Link Capability (Offset Ch)
    logic  [2:0] cfg_max_link_width; // Max Link Width 0h: x16; 7h: x8
    logic  [7:4] cfg_max_link_speed; // Max Link Speeds = (0h: 4 GT/s; 1h: 8 GT/s; 12h: 4 GT/s; ... ; or 7h: 64 GT/s)
    logic        cfg_SPMW          ; // SPMW (Standard Package Module Width): If 1, indicates the Standard Package Module size is a x8 module, or a x16 module operating in x8 mode (decided at integration time). If 0, indicates x16 Standard Package Module.
    // Note cfg_SPMW = ((there was a width degrade & cfg_max_link_width is x16) | (cfg_max_link_width is x8) | (cfg_force_x8_width & cfg_lane_reversal))? 1 : 0;

    // // PHY Control (Offset 1004h)
    // input wire         cfg_force_x8_width, // Force x8 Width Mode in a UCIe-S x16 Module (used only for test and debug). This feature can be used only when there is no lane reversal on the UCIe-S x16 link (cfg_lane_reversal = 0).
    // ...

    // // PHY Status (Offset 1008h)
    // input wire         cfg_lane_reversal, //Lane Reversal within Module: Indicates if Lanes within a module are reversed. (0: not reversed; 1: reversed)
    // ...

    // // Training Setup 3 (Offset 1030h)
    // logic [15:0]  cfg_train3_lane_mask ; // Masks specific Rx lanes during comparison (16-bits for x16 Standard Package).
    // logic cfg_current_rx_lane_map_valid; // To tell the RF to apply the change on cfg_current_rx_lane_map field.


    // Training Setup 4 (Offset 1050h)
    // Note: 'Repair Lane mask' (Bits 3:0) is omitted as it only applies to Advanced Package.
    logic [11:0]  cfg_train4_max_err_thresh_perlane; // Max error Threshold in per-Lane comparison for error counting.
    logic [15:0]  cfg_train4_max_err_thresh_aggr   ; // Max error Threshold in aggregate comparison for error counting.

    // // Current Lane Map Module 0 (Offset 1060h)
    // // Note: Marked as RW in spec, but typically driven by PHY to indicate functional lanes after training.
    // logic [15:0]  cfg_current_rx_lane_map; // 1b indicates the corresponding Rx physical Lane is operational.

    // Error Log 0 (Offset 1080h) - (ROS: Read-Only Status driven by PHY)
    logic  [7:0]   log0_state_n        ; // Captures the current Link training state machine (LTSM) status.
    logic          log0_lane_reversal  ; // 1b indicates Lane Reversal was applied within the module.
    logic          log0_width_degrade  ; // 1b indicates Module width Degrade occurred (Standard package only).
    logic  [7:0]   log0_state_n_minus_1; // Captures the LTSM state before State N was entered.
    logic  [7:0]   log0_state_n_minus_2; // Captures the LTSM state before State (N-1) was entered.
    logic log0_state_n_valid           ; // To tell the RF to apply the change on log0_state_n         field.
    logic log0_lane_reversal_valid     ; // To tell the RF to apply the change on log0_lane_reversal   field.
    logic log0_width_degrade_valid     ; // To tell the RF to apply the change on log0_width_degrade   field.
    logic log0_state_n_minus_1_valid   ; // To tell the RF to apply the change on log0_state_n_minus_1 field.
    logic log0_state_n_minus_2_valid   ; // To tell the RF to apply the change on log0_state_n_minus_2 field.

    // Error Log 1 (Offset 1090h) - (ROS / RW1CS driven by PHY)
    logic  [7:0]   log1_state_n_minus_3     ; // Captures the LTSM state before State (N-2) was entered.
    logic          log1_state_timeout_occ   ; // 1b if a Link Training state or sub-state timed out (Fatal error).
    logic          log1_sideband_timeout_occ; // 1b if a sideband handshake timed out (e.g., > 8ms).
    logic          log1_remote_link_error   ; // 1b if remote Link partner requested LinkError transition via Sideband.
    logic          log1_internal_error      ; // 1b if any implementation-specific internal error occurred in the PHY.
    logic log1_state_n_minus_3_valid        ; // To tell the RF to apply the change on log1_state_n_minus_3      field.
    logic log1_state_timeout_occ_valid      ; // To tell the RF to apply the change on log1_state_timeout_occ    field.
    logic log1_sideband_timeout_occ_valid   ; // To tell the RF to apply the change on log1_sideband_timeout_occ field.
    logic log1_remote_link_error_valid      ; // To tell the RF to apply the change on log1_remote_link_error    field.
    logic log1_internal_error_valid         ; // To tell the RF to apply the change on log1_internal_error       field.



    ////////////////////////////////////////////////////////
    // For Testbench only                                 //
    ////////////////////////////////////////////////////////
    logic [15:0] tb_aggr_err     ; // Aggregate error for current comparison.
    logic [15:0] tb_perlane_err  ; // Per-lane  error for current comparison.
    logic        tb_val_err      ; // valid error for current comparison.
    logic        tb_clk_err      ; // clock error for current comparison.
    logic        tb_wait_timeout ; // Used to test the timeout condition by waiting for some time before setting mb_tx_pattern_count_done to 1.
    logic        tb_wrong_sb_msg_en; // To test the case when the SB Rx receives wrong message.
    msg_no_e     tb_wrong_sb_msg ; // To choose the SB Rx wrong Message (if "tb_wrong_sb_msg_en" = 1).
    logic [15:0] tb_rx_msginfo   ; // To control in case the SB Rx receives wrong value.
    logic [63:0] tb_rx_data_field;

    //=============================================//
    // for any module has a sequential logic.      //
    //=============================================//
    modport clk_rst_mp(
        input  lclk ,
        input  rst_n
    );

    //  ><  \\\\\\\\\\\\\\\\\\\\\\\\\                                                      ///////////////////////  ><  //
    //  >===<  \\\\\\\\\\\\\\\\\\\\\\\\\                                                ///////////////////////  >===<  //
    //  >======<  \\\\\\\\\\\\\\\\\\\\\\\\\==========================================///////////////////////  >======<  //
    //  >=========<  >>                                 Timers interface                               <<  >=========<  //
    //  >======<  /////////////////////////==========================================\\\\\\\\\\\\\\\\\\\\\\\  >======<  //
    //  >===<  /////////////////////////                                                \\\\\\\\\\\\\\\\\\\\\\\  >===<  //
    //  ><  /////////////////////////                                                      \\\\\\\\\\\\\\\\\\\\\\\  ><  //

    //========================================================================//
    // Timers signals from LTSM states Prespective:                           //
    //========================================================================//
    modport state2timerout_8ms_mp (
        // Timers signals.
        input  timeout_8ms_occured,
        output timeout_timer_en
    );

    modport state2analog_settle_timer_mp (
        // Timers signals.
        input  analog_settle_time_done,
        output analog_settle_timer_en
    );

    //========================================================================//
    // Timers signals from Timers blocks Prespective:                         //
    //========================================================================//
    modport timer_timerout_8ms2state_mp (
        // Timers signals.
        input  lclk,
        input  rst_n,
        output timeout_8ms_occured,
        input  timeout_timer_en
    );

    modport timer_analog_settle2state_mp (
        // Timers signals.
        input  lclk,
        input  rst_n,
        output analog_settle_time_done,
        input  analog_settle_timer_en
    );





    //  ><  \\\\\\\\\\\\\\\\\\\\\\\\\                                                      ///////////////////////  ><  //
    //  >===<  \\\\\\\\\\\\\\\\\\\\\\\\\                                                ///////////////////////  >===<  //
    //  >======<  \\\\\\\\\\\\\\\\\\\\\\\\\==========================================///////////////////////  >======<  //
    //  >=========<  >>                           MB signals from LTSM States                          <<  >=========<  //
    //  >======<  /////////////////////////==========================================\\\\\\\\\\\\\\\\\\\\\\\  >======<  //
    //  >===<  /////////////////////////                                                \\\\\\\\\\\\\\\\\\\\\\\  >===<  //
    //  ><  /////////////////////////                                                      \\\\\\\\\\\\\\\\\\\\\\\  ><  //

    //=======================================================================================//
    // Control Signals from the LTSM to the MB direction: (LTSM prespective)                 //
    // LTSM -> MB                                                                            //
    //=======================================================================================//
    modport ltsm2mb_mp (
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling and Shapes Details Group:
        output mb_tx_clk_shape               , // 0: Differential clocking, 1: Quadrature clocking.
        output mb_tx_continuous_or_strobe_clk, // 0: continuous mode clock, 1: strobe mode clock.
        output mb_tx_clk_sampling_en         , // Enable changing Clock sampling/PI phase control state.
        output mb_tx_clk_sampling            , // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

        // Tx Pattern Generator Setup Group:
        output mb_tx_pattern_en      , // 1: Send pattern immediately, 0: Don't send pattern.
        output mb_tx_pattern_setup   , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        output mb_tx_data_pattern_sel, // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
        output mb_tx_val_pattern_sel , // 0: VALTRAIN pattern, 1: Held Low.
        output mb_tx_lfsr_en         , // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
        output mb_tx_lfsr_rst        , // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
        output mb_rx_lfsr_en         , // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
        output mb_rx_lfsr_rst        , // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.

        // Tx Pattern Mode Setup Group:
        output mb_tx_pattern_mode      , // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        output mb_tx_burst_count       , // Burst Count: Indicates the duration of selected pattern (UI count).
        output mb_tx_idle_count        , // IDLE Count: Indicates the duration of low following the burst (UI count).
        output mb_tx_iter_count        , // Iterations: Indicates the iteration count of bursts followed by idle.
        input  mb_tx_pattern_count_done, // Asserted (=1) once MB completes the iter_count.

        // Receiver Comparison Setup & Errors
        output mb_rx_compare_en            , // 1: Enable the Rx comparison circuit, 0: Disable.
        output mb_rx_max_err_thresh_aggr   , // Max error Threshold in aggregate comparison.
        output mb_rx_max_err_thresh_perlane, // Max error Threshold in per Lane comparison.
        output mb_rx_compare_setup         , // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
        input  mb_rx_aggr_err              , // The total calculated Aggregate Errors on Rx.
        input  mb_rx_perlane_err           , // The Per-Lane Errors (Each bit represents one fail Data Lane).
        input  mb_rx_val_err               , // The error coming from Valid Lane receiver in MB.
        input  mb_rx_clk_err               , // The error coming from Clock Lane receiver in MB.
        input  mb_rx_compare_done          , // From MB to LTSM to tell that comparison of burst_count is done.

        //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
        // MB Lane Control
        output mb_rx_data_lane_mask, // Describes the Functional Rx Lanes (Active Lanes).
        output mb_tx_data_lane_mask, // Describes the Functional Tx Lanes (Active Lanes).
        output mb_mapper_en        , // 0: Disable the mapper, 1: Enable the mapper.

        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        // PHY Level Control & Analog Interface
        output phy_negotiated_speed      , // Target Link Speed (0h: 4 GT/s; 1h: 8 GT/s; 2h: 12 GT/s; ... ; or 7h: 64 GT/s)
        output phy_rx_clock_lock_en      , // Allow analog Rx circuit to Lock the coming clock.
        output phy_rx_track_lock_en      , // Allow analog Rx circuit to Lock the coming Track.
        output phy_rx_phase_detector_en  , // Activate Phase Detector Circuit for IQ clock phase shift test.
        output phy_tx_tckn_shift_en      , // Activate circuits to calculate shift on partner TCKN_L.
        input  phy_rx_tckn_shift         , // The required shift of the partner TCKN_L (range 0 to 12).
        input  phy_rx_decrement_shift    , // Direction of shift: 1b (earlier), 0b (later).
        output phy_rx_valvref_ctrl       , // Tell ADC the Rx Valid Lane Vref level to operate in.
        output phy_rx_datavref_ctrl      , // Tell ADC the Rx Data Lane Vref level to operate in.
        output phy_tx_pi_phase_ctrl      , // Tell ADC the Tx Clock Lane PI phase level.
        output phy_rx_deskew_ctrl        , // Tell ADC the Rx deskew level for each data lane (16 lanes x 6 bits).
        output phy_tx_eq_preset_ctrl     , // Choose the EQ Tx Preset to use (for speed > 32 GT/s).
        input  phy_rx_clk_drift_cal_state, // 1b: Calibration done successfully (drift is small), 0b: Needs TARR.
        input  phy_rx_clk_drift_cal_valid  // Tells LTSM if phy_rx_clk_drift_cal_state is ready.
    );

    //=======================================================================================//
    // Control Signals from the MB to the LTSM direction: (MB prespective)                   //
    // MB -> LTSM                                                                            //
    //=======================================================================================//
    modport mb2ltsm_mp (
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling and Shapes Details Group:
        input mb_tx_clk_shape               , // 0: Differential clocking, 1: Quadrature clocking.
        input mb_tx_continuous_or_strobe_clk, // 0: continuous mode clock, 1: strobe mode clock.
        input mb_tx_clk_sampling_en         , // Enable changing Clock sampling/PI phase control state.
        input mb_tx_clk_sampling            , // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

        // Tx Pattern Generator Setup Group:
        input mb_tx_pattern_en      , // 1: Send pattern immediately, 0: Don't send pattern.
        input mb_tx_pattern_setup   , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        input mb_tx_data_pattern_sel, // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
        input mb_tx_val_pattern_sel , // 0: VALTRAIN pattern, 1: Held Low.
        input mb_tx_lfsr_en         , // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
        input mb_tx_lfsr_rst        , // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
        input mb_rx_lfsr_en         , // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
        input mb_rx_lfsr_rst        , // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.

        // Tx Pattern Mode Setup Group:
        input  mb_tx_pattern_mode      , // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        input  mb_tx_burst_count       , // Burst Count: Indicates the duration of selected pattern (UI count).
        input  mb_tx_idle_count        , // IDLE Count: Indicates the duration of low following the burst (UI count).
        input  mb_tx_iter_count        , // Iterations: Indicates the iteration count of bursts followed by idle.
        output mb_tx_pattern_count_done, // Asserted (=1) once MB completes the iter_count.

        // Receiver Comparison Setup & Errors
        input  mb_rx_compare_en            , // 1: Enable the Rx comparison circuit, 0: Disable.
        input  mb_rx_max_err_thresh_aggr   , // Max error Threshold in aggregate comparison.
        input  mb_rx_max_err_thresh_perlane, // Max error Threshold in per Lane comparison.
        input  mb_rx_compare_setup         , // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
        output mb_rx_aggr_err              , // The total calculated Aggregate Errors on Rx.
        output mb_rx_perlane_err           , // The Per-Lane Errors (Each bit represents one fail Data Lane).
        output mb_rx_val_err               , // The error coming from Valid Lane receiver in MB.
        output mb_rx_clk_err               , // The error coming from Clock Lane receiver in MB.
        output mb_rx_compare_done          , // From MB to LTSM to tell that comparison of burst_count is done.

        //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
        // MB Lane Control
        input mb_rx_data_lane_mask, // Describes the Functional Rx Lanes (Active Lanes).
        input mb_tx_data_lane_mask, // Describes the Functional Tx Lanes (Active Lanes).
        input mb_mapper_en        , // 0: Disable the mapper, 1: Enable the mapper.

        // Lane Behavior Control
        input mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        input mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        input mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        input mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        input mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        input mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        input mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        input mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        // PHY Level Control & Analog Interface
        input  phy_negotiated_speed      , // Target Link Speed (0h: 4 GT/s; 1h: 8 GT/s; 2h: 12 GT/s; ... ; or 7h: 64 GT/s)
        input  phy_rx_clock_lock_en      , // Allow analog Rx circuit to Lock the coming clock.
        input  phy_rx_track_lock_en      , // Allow analog Rx circuit to Lock the coming Track.
        input  phy_rx_phase_detector_en  , // Activate Phase Detector Circuit for IQ clock phase shift test.
        input  phy_tx_tckn_shift_en      , // Activate circuits to calculate shift on partner TCKN_L.
        output phy_rx_tckn_shift         , // The required shift of the partner TCKN_L (range 0 to 12).
        output phy_rx_decrement_shift    , // Direction of shift: 1b (earlier), 0b (later).
        input  phy_rx_valvref_ctrl       , // Tell ADC the Rx Valid Lane Vref level to operate in.
        input  phy_rx_datavref_ctrl      , // Tell ADC the Rx Data Lane Vref level to operate in.
        input  phy_tx_pi_phase_ctrl      , // Tell ADC the Tx Clock Lane PI phase level.
        input  phy_rx_deskew_ctrl        , // Tell ADC the Rx deskew level for each data lane (16 lanes x 6 bits).
        input  phy_tx_eq_preset_ctrl     , // Choose the EQ Tx Preset to use (for speed > 32 GT/s).
        output phy_rx_clk_drift_cal_state, // 1b: Calibration done successfully (drift is small), 0b: Needs TARR.
        output phy_rx_clk_drift_cal_valid  // Tells LTSM if phy_rx_clk_drift_cal_state is ready.
    );



    //  ><  \\\\\\\\\\\\\\\\\\\\\\\\\                                                      ///////////////////////  ><  //
    //  >===<  \\\\\\\\\\\\\\\\\\\\\\\\\                                                ///////////////////////  >===<  //
    //  >======<  \\\\\\\\\\\\\\\\\\\\\\\\\==========================================///////////////////////  >======<  //
    //  >=========<  >>                      SB signals from LTSM States Prespective                   <<  >=========<  //
    //  >======<  /////////////////////////==========================================\\\\\\\\\\\\\\\\\\\\\\\  >======<  //
    //  >===<  /////////////////////////                                                \\\\\\\\\\\\\\\\\\\\\\\  >===<  //
    //  ><  /////////////////////////                                                      \\\\\\\\\\\\\\\\\\\\\\\  ><  //

    //=======================================================================================//
    // Control Signals from the LTSM states to the SB direction: (LTSM prespective)          //
    // LTSM -> SB                                                                            //
    //=======================================================================================//
    modport ltsm2sb_mp(
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );


    //=======================================================================================//
    // Control Signals from the SB to the LTSM direction: (SB prespective)                   //
    // SB -> LTSM                                                                            //
    //=======================================================================================//
    modport sb2ltsm_mp(
        // For SB TX:
        input tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        input tx_sb_msg      , // Tell the Sideband the message that it should to send.
        input tx_msginfo     , // MsgInfo field of the SB message.
        input tx_data_field  , // Data field of the SB message.

        // For SB RX:
        output rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
        output rx_sb_msg      , // Get the Received SB msg.
        output rx_msginfo     , // MsgInfo field of the SB message received.
        output rx_data_field    // Data field of the SB message.
    );

    //  ><  \\\\\\\\\\\\\\\\\\\\\\\\\                                                      ///////////////////////  ><  //
    //  >===<  \\\\\\\\\\\\\\\\\\\\\\\\\                                                ///////////////////////  >===<  //
    //  >======<  \\\\\\\\\\\\\\\\\\\\\\\\\==========================================///////////////////////  >======<  //
    //  >=========<  >>                Regester File signals from LTSM States Prespective              <<  >=========<  //
    //  >======<  /////////////////////////==========================================\\\\\\\\\\\\\\\\\\\\\\\  >======<  //
    //  >===<  /////////////////////////                                                \\\\\\\\\\\\\\\\\\\\\\\  >===<  //
    //  ><  /////////////////////////                                                      \\\\\\\\\\\\\\\\\\\\\\\  ><  //


    //======================================================================================//
    // Register File (RF) signals from LTSM States Prespective:                             //
    // These modport is used in                                                             //
    //          - each sub-state needs to use it.                                           //
    //          - interface with the RF.                                                    //
    //          - MUX signals exporting side.                                               //
    //======================================================================================//

    //  UCIe Link DVSEC - UCIe Link Capability (Offset Ch)
    modport state_rf_offset_c_mp (
        input  cfg_max_link_width, // Max Link Width 0h: x16; 7h: x8
        input  cfg_max_link_speed, // Max Link Speeds = (0h: 4 GT/s; 1h: 8 GT/s; 12h: 4 GT/s; ... ; or 7h: 64 GT/s)
        input  cfg_SPMW            // SPMW (Standard Package Module Width): If 1, indicates the Standard Package Module size is a x8 module, or a x16 module operating in x8 mode (decided at integration time). If 0, indicates x16 Standard Package Module.
        // Note cfg_SPMW = ((there was a width degrade & cfg_max_link_width is x16) | (cfg_max_link_width is x8) | (cfg_force_x8_width & cfg_lane_reversal))? 1 : 0;
    );

    // // Training Setup 3 (Offset 1030h)
    // modport state_rf_offset_1030_mp (
    //     input  cfg_train3_lane_mask // Masks specific Rx lanes during comparison (16-bits for x16 Standard Package).
    // );

    // Training Setup 4 (Offset 1050h)
    // Note: 'Repair Lane mask' (Bits 3:0) is omitted as it only applies to Advanced Package.
    modport state_rf_offset_1050_mp (
        input  cfg_train4_max_err_thresh_perlane, // Max error Threshold in per-Lane comparison for error counting.
        input  cfg_train4_max_err_thresh_aggr     // Max error Threshold in aggregate comparison for error counting.
    );

    // // Current Lane Map Module 0 (Offset 1060h)
    // // Note: Marked as RW in spec, but typically driven by PHY to indicate functional lanes after training.
    // modport state_rf_offset_1060_mp (
    //     output cfg_current_rx_lane_map      , // 1b indicates the corresponding Rx physical Lane is operational.
    //     output cfg_current_rx_lane_map_valid  // To tell the RF to apply the change
    // );

    // Error Log 0 (Offset 1080h) - (ROS: Read-Only Status driven by PHY)
    modport state_rf_offset_1080_mp (
        output log0_state_n              , // Captures the current Link training state machine (LTSM) status.
        output log0_lane_reversal        , // 1b indicates Lane Reversal was applied within the module.
        output log0_width_degrade        , // 1b indicates Module width Degrade occurred (Standard package only).
        output log0_state_n_minus_1      , // Captures the LTSM state before State N was entered.
        output log0_state_n_minus_2      , // Captures the LTSM state before State (N-1) was entered.
        output log0_state_n_valid        , // To tell the RF to apply the change on log0_state_n         field.
        output log0_lane_reversal_valid  , // To tell the RF to apply the change on log0_lane_reversal   field.
        output log0_width_degrade_valid  , // To tell the RF to apply the change on log0_width_degrade   field.
        output log0_state_n_minus_1_valid, // To tell the RF to apply the change on log0_state_n_minus_1 field.
        output log0_state_n_minus_2_valid  // To tell the RF to apply the change on log0_state_n_minus_2 field.
    );

    // Error Log 1 (Offset 1090h) - (ROS / RW1CS driven by PHY)
    modport state_rf_offset_1090_mp (
        output log1_state_n_minus_3           , // Captures the LTSM state before State (N-2) was entered.
        output log1_state_timeout_occ         , // 1b if a Link Training state or sub-state timed out (Fatal error).
        output log1_sideband_timeout_occ      , // 1b if a sideband handshake timed out (e.g., > 8ms).
        output log1_remote_link_error         , // 1b if remote Link partner requested LinkError transition via Sideband.
        output log1_internal_error            , // 1b if any implementation-specific internal error occurred in the PHY.
        output log1_state_n_minus_3_valid     , // To tell the RF to apply the change on log1_state_n_minus_3      field.
        output log1_state_timeout_occ_valid   , // To tell the RF to apply the change on log1_state_timeout_occ    field.
        output log1_sideband_timeout_occ_valid, // To tell the RF to apply the change on log1_sideband_timeout_occ field.
        output log1_remote_link_error_valid   , // To tell the RF to apply the change on log1_remote_link_error    field.
        output log1_internal_error_valid        // To tell the RF to apply the change on log1_internal_error       field.
    );



    //  ><  \\\\\\\\\\\\\\\\\\\\\\\\\                                                      ///////////////////////  ><  //
    //  >===<  \\\\\\\\\\\\\\\\\\\\\\\\\                                                ///////////////////////  >===<  //
    //  >======<  \\\\\\\\\\\\\\\\\\\\\\\\\==========================================///////////////////////  >======<  //
    //  >=========<  >>               Regester File signals from the MUX side Prespective              <<  >=========<  //
    //  >=========<  >>                     (that's connected with the LTSM states)                    <<  >=========<  //
    //  >======<  /////////////////////////==========================================\\\\\\\\\\\\\\\\\\\\\\\  >======<  //
    //  >===<  /////////////////////////                                                \\\\\\\\\\\\\\\\\\\\\\\  >===<  //
    //  ><  /////////////////////////                                                      \\\\\\\\\\\\\\\\\\\\\\\  ><  //

    //======================================================================================//
    // Register File (RF) signals LTSM states side prespective in the MUXs:                 //
    // This modport is used in                                                              //
    //          - MUX side from the LTSM states side.                                       //
    // Note: for the "another side of the MUX" we will use the modport "state_rf_offset_*". //
    //======================================================================================//
    // Quick summary to remember:
    //          What I can theoretically do = Capability (Offset Ch). (Before Link Training (Read Only for me))
    //          What the software asks me to do = Control (Offset 10h). (Before Link Training (depending on the software selection))
    //          The actual result we agreed upon after training = Status (Offset 14h). (After Link Training)

    // UCIe Link DVSEC - UCIe Link Capability (Offset Ch)
    modport mux_rf_offset_c_mp (
        output  cfg_max_link_width, // Max Link Width 0h: x16; 7h: x8
        output  cfg_max_link_speed, // Max Link Speeds = (0h: 4 GT/s; 1h: 8 GT/s; 12h: 4 GT/s; ... ; or 7h: 64 GT/s)
        output  cfg_SPMW            // SPMW (Standard Package Module Width): If 1, indicates the Standard Package Module size is a x8 module, or a x16 module operating in x8 mode (decided at integration time). If 0, indicates x16 Standard Package Module.
    );

    // // Training Setup 3 (Offset 1030h)
    // modport mux_rf_offset_1030_mp (
    //     output  cfg_train3_lane_mask // Masks specific Rx lanes during comparison (16-bits for x16 Standard Package).
    // );

    // Training Setup 4 (Offset 1050h)
    // Note: 'Repair Lane mask' (Bits 3:0) is omitted as it only applies to Advanced Package.
    modport mux_rf_offset_1050_mp (
        output  cfg_train4_max_err_thresh_perlane, // Max error Threshold in per-Lane comparison for error counting.
        output  cfg_train4_max_err_thresh_aggr     // Max error Threshold in aggregate comparison for error counting.
    );

    // // Current Lane Map Module 0 (Offset 1060h)
    // // Note: Marked as RW in spec, but typically driven by PHY to indicate functional lanes after training.
    // modport mux_rf_offset_1060_mp (
    //     input cfg_current_rx_lane_map      , // 1b indicates the corresponding Rx physical Lane is operational.
    //     input cfg_current_rx_lane_map_valid  // To tell the RF to apply the change
    // );

    // Error Log 0 (Offset 1080h) - (ROS: Read-Only Status driven by PHY)
    modport mux_rf_offset_1080_mp (
        input log0_state_n              , // Captures the current Link training state machine (LTSM) status.
        input log0_lane_reversal        , // 1b indicates Lane Reversal was applied within the module.
        input log0_width_degrade        , // 1b indicates Module width Degrade occurred (Standard package only).
        input log0_state_n_minus_1      , // Captures the LTSM state before State N was entered.
        input log0_state_n_minus_2      , // Captures the LTSM state before State (N-1) was entered.
        input log0_state_n_valid        , // To tell the RF to apply the change on log0_state_n         field.
        input log0_lane_reversal_valid  , // To tell the RF to apply the change on log0_lane_reversal   field.
        input log0_width_degrade_valid  , // To tell the RF to apply the change on log0_width_degrade   field.
        input log0_state_n_minus_1_valid, // To tell the RF to apply the change on log0_state_n_minus_1 field.
        input log0_state_n_minus_2_valid  // To tell the RF to apply the change on log0_state_n_minus_2 field.
    );

    // Error Log 1 (Offset 1090h) - (ROS / RW1CS driven by PHY)
    modport mux_rf_offset_1090_mp (
        input log1_state_n_minus_3           , // Captures the LTSM state before State (N-2) was entered.
        input log1_state_timeout_occ         , // 1b if a Link Training state or sub-state timed out (Fatal error).
        input log1_sideband_timeout_occ      , // 1b if a sideband handshake timed out (e.g., > 8ms).
        input log1_remote_link_error         , // 1b if remote Link partner requested LinkError transition via Sideband.
        input log1_internal_error            , // 1b if any implementation-specific internal error occurred in the PHY.
        input log1_state_n_minus_3_valid     , // To tell the RF to apply the change on log1_state_n_minus_3      field.
        input log1_state_timeout_occ_valid   , // To tell the RF to apply the change on log1_state_timeout_occ    field.
        input log1_sideband_timeout_occ_valid, // To tell the RF to apply the change on log1_sideband_timeout_occ field.
        input log1_remote_link_error_valid   , // To tell the RF to apply the change on log1_remote_link_error    field.
        input log1_internal_error_valid        // To tell the RF to apply the change on log1_internal_error       field.
    );



// ============================================================================================================================================================================================================================================== //
//                                                                                                                                                                                                                                                //
//         ===========                                   ======                                                                                                                                                                                   //
//      =================                                ======                                                                                                                                                                                   //
//    ========     ========                              ======                                                                   ======                                        ======                                                            //
//   ======           ======                             ======                                                                   ======                                        ======                                                            //
//   ======           ======   ======           ======   ======   =======                              ===========         =================            ===========      =================            ===========             ===========         //
//    ========                 ======           ======   ====================                       =================     =================          =================  =================          =================       =================      //
//      ============           ======           ======   =======================                   ========     ========        ======             =======      ======        ======             =======       =======    ========     ========   //
//         =============       ======           ======   =========        ========   ===========   ======                       ======                          ======        ======            ======           ======   ======                  //
//              ==========     ======           ======   =======            ======   ===========    =========                   ======               =================        ======            =======================    =========              //
//   ======           ======   ======           ======   =======            ======   ===========      ==============            ======             ========     ======        ======            ======                       ==============       //
//   ======           ======    ======          ======   =========        =======                             =========         ======            ======        ======        ======             ======                              =========    //
//    ========     ========      =======      ========   =======================                   ========     ========        ======            ======      ========        ======              =======        ======   ========     ========   //
//      =================          ===================   ====== =============                        =================            =============    ===================          =============       =================       =================     //
//         ===========                =========  =====   ======   =======                               ===========                  ========        ==========   ====             ========            ===========             ===========        //
//                                                                                                                                                                                                                                                //
// ============================================================================================================================================================================================================================================== //
    // Adel ...
    // ...


    //  ><  \\\\\\\\\\\\\\\\\\\\\\\\\                                                      ///////////////////////  ><  //
    //  >===<  \\\\\\\\\\\\\\\\\\\\\\\\\                                                ///////////////////////  >===<  //
    //  >======<  \\\\\\\\\\\\\\\\\\\\\\\\\==========================================///////////////////////  >======<  //
    //  >=========<  >>                                                                                <<  >=========<  //
    //  >=========<  >>              //=================================================\\             <<  >=========<  //
    //  >=========<  >>             |   Control Signals For (Rx init D to C point test)   |            <<  >=========<  //
    //  >=========<  >>             |   Control Signals For (Tx init D to C point test)   |            <<  >=========<  //
    //  >=========<  >>              \\=================================================//             <<  >=========<  //
    //  >=========<  >>                                                                                <<  >=========<  //
    //  >======<  /////////////////////////==========================================\\\\\\\\\\\\\\\\\\\\\\\  >======<  //
    //  >===<  /////////////////////////                                                \\\\\\\\\\\\\\\\\\\\\\\  >===<  //
    //  ><  /////////////////////////                                                      \\\\\\\\\\\\\\\\\\\\\\\  ><  //

    //  >======<  /////////////////////////////////////////////////////  >======<  //
    //  >======<  //=================================================//  >======<  //
    //  >======<  // Control Signals For (Rx init D to C point test) //  >======<  //
    //  >======<  // Control Signals For (Tx init D to C point test) //  >======<  //
    //  >======<  //=================================================//  >======<  //
    //  >======<  /////////////////////////////////////////////////////  >======<  //
    // It's LTSM sub-states prespective (Not the test FSM prespective).
    modport substate2d2c_mp(
        // timeout handling.
        output substate_timeout_8ms_occured,

        output rx_pt_en           , // To enable Rx init Data to Clock Point Test
        output tx_pt_en           , // To enable Tx init Data to Clock Point Test
        input  test_d2c_done      , // To identecate the enabled test (Rx/Tx init Data)

        // Clock sampling.
        output d2c_clk_sampling    ,  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
        input  d2c_timeout_or_error, // Tell the external Sub-state if timeout or error occurs during the test to move to TRAINERROR state.

        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Received Tx Pattern Generator Setup Group:
        output d2c_lfsr_en         , // 1: Enable the Tx & Rx LFSR when use the Rx or Tx FSM Test, 0: Disable the Tx & Rx LFSR.
        output d2c_pattern_setup   , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        output d2c_data_pattern_sel, // Data pattern used during training: LFSR, ID, or all 0.
        output d2c_val_pattern_sel , // 0: VALTRAIN pattern, 1: Held Low.

        // Received Tx Pattern Mode Setup Group:
        output d2c_pattern_mode    , // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        output d2c_burst_count     , // Burst Count: Indicates the duration of selected pattern (UI count).
        output d2c_idle_count      , // IDLE Count: Indicates the duration of low following the burst (UI count).
        output d2c_iter_count      , // Iteration Count: Indicates the iteration count of bursts followed by idle.

        // Received Receiver Comparison Setup & Errors
        output d2c_compare_setup   , // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
        input  d2c_aggr_err        , // The total calculated Aggregate Errors on Rx.
        input  d2c_perlane_err     , // The Per-Lane Errors (Each bit represents one fail Data Lane).
        input  d2c_val_err         , // The error coming from Valid Lane receiver in MB.
        input  d2c_clk_err         , // The error coming from Clock Lane receiver in MB.
        input  partner_valtraincenter_fail_flag , // Pass/fail of the partner Tx Valid lane (from RX D2C test FSM).
        input  partner_datatraincenter_fail_flag  // Pass/fail of the partner Tx Data lanes (from TX D2C test FSM).
    );

    // It's the test (Rx/Tx D-to-C point test FSM) prespective (Not the main LTSM states prespective)
    modport d2c2substate_mp(
        // timeout handling.
        input  substate_timeout_8ms_occured,

        input  rx_pt_en,
        input  tx_pt_en,
        output test_d2c_done,

        // Clock sampling.
        input  d2c_clk_sampling    , // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
        output d2c_timeout_or_error, // Tell the external Sub-state if timeout or error occurs during the test to move to TRAINERROR state.

        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Received Tx Pattern Generator Setup Group:
        input  d2c_lfsr_en         , // 1: Enable the Tx & Rx LFSR when use the Rx or Tx FSM Test, 0: Disable the Tx & Rx LFSR.
        input  d2c_pattern_setup   , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        input  d2c_data_pattern_sel, // Data pattern used during training: LFSR, ID, or all 0.
        input  d2c_val_pattern_sel , // 0: VALTRAIN pattern, 1: Held Low.

        // Received Tx Pattern Mode Setup Group:
        input  d2c_pattern_mode, // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        input  d2c_burst_count , // Burst Count: Indicates the duration of selected pattern (UI count).
        input  d2c_idle_count  , // IDLE Count: Indicates the duration of low following the burst (UI count).
        input  d2c_iter_count  , // Iteration Count: Indicates the iteration count of bursts followed by idle.

        // Received Receiver Comparison Setup & Errors
        input   d2c_compare_setup, // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
        output  d2c_aggr_err     , // The total calculated Aggregate Errors on Rx.
        output  d2c_perlane_err  , // The Per-Lane Errors (Each bit represents one fail Data Lane).
        output  d2c_val_err      , // The error coming from Valid Lane receiver in MB.
        output  d2c_clk_err      , // The error coming from Clock Lane receiver in MB.
        output  partner_valtraincenter_fail_flag , // From our UCIe die Rx. It represents the fail flags of the partner Tx Valid lane.
        output  partner_datatraincenter_fail_flag  // From our UCIe die Rx. It represents the fail flags of the partner Tx Data lanes.
        // output  d2c_partner_tx_fail_flag           // Driven by TX D2C PT FSM: overall pass/fail of the partner Tx side based on active compare mode.
    );

    //=======================================================================================//
    // Control Signals from the D2C to the MUX direction: (D2C prespective)                  //
    // D2C -> MUX                                                                            //
    //=======================================================================================//
    modport d2c2mux_mp (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  lclk , input  rst_n,

        //=====================================//
        // Control Signals for MB:             //
        //=====================================//
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling and Shapes Details Group:
        output mb_tx_clk_sampling_en   , // Enable changing Clock sampling/PI phase control state.
        output mb_tx_clk_sampling      , // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

        // Tx Pattern Generator Setup Group:
        output mb_tx_pattern_en        , // 1: Send pattern immediately, 0: Don't send pattern.
        output mb_tx_pattern_setup     , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        output mb_tx_data_pattern_sel  , // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
        output mb_tx_val_pattern_sel   , // 0: VALTRAIN pattern, 1: Held Low.
        output mb_tx_lfsr_en           , // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
        output mb_tx_lfsr_rst          , // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
        output mb_rx_lfsr_en           , // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
        output mb_rx_lfsr_rst          , // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.

        // Tx Pattern Mode Setup Group:
        output mb_tx_pattern_mode      , // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        output mb_tx_burst_count       , // Burst Count: Indicates the duration of selected pattern (UI count).
        output mb_tx_idle_count        , // IDLE Count: Indicates the duration of low following the burst (UI count).
        output mb_tx_iter_count        , // Iterations: Indicates the iteration count of bursts followed by idle.
        input  mb_tx_pattern_count_done, // Asserted (=1) once MB completes the iter_count.

        // Receiver Comparison Setup & Errors
        output mb_rx_compare_en            , // 1: Enable the Rx comparison circuit, 0: Disable.
        output mb_rx_max_err_thresh_aggr   , // Max error Threshold in aggregate comparison.
        output mb_rx_max_err_thresh_perlane, // Max error Threshold in per Lane comparison.
        output mb_rx_compare_setup         , // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
        input  mb_rx_aggr_err              , // The total calculated Aggregate Errors on Rx.
        input  mb_rx_perlane_err           , // The Per-Lane Errors (Each bit represents one fail Data Lane).
        input  mb_rx_val_err               , // The error coming from Valid Lane receiver in MB.
        input  mb_rx_clk_err               , // The error coming from Clock Lane receiver in MB.
        input  mb_rx_compare_done          , // From MB to LTSM to tell that comparison of burst_count is done.

        //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
        // MB Lane Control
        // output mb_rx_data_lane_mask, // Describes the Functional Rx Lanes (Active Lanes).
        // output mb_tx_data_lane_mask, // Describes the Functional Tx Lanes (Active Lanes).
        // output mb_mapper_en        , // 0: Disable the mapper, 1: Enable the mapper.

        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).



        //=====================================//
        // Control Signals for SB:             //
        //=====================================//
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field  , // Data field of the SB message.


        //=====================================//
        // Register File (RF) Control Signals: //
        //=====================================//
        // Training Setup 4 (Offset 1050h)
        // Note: 'Repair Lane mask' (Bits 3:0) is omitted as it only applies to Advanced Package.
        input  cfg_train4_max_err_thresh_perlane, // Max error Threshold in per-Lane comparison for error counting.
        input  cfg_train4_max_err_thresh_aggr     // Max error Threshold in aggregate comparison for error counting.
    );



    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//
    //=========================.
    // MBTRAIN.VALVREF:        |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state prespective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport valvref_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  valvref_en    , output  valvref_done,
        output trainerror_req,

        // ======================= //
        // MB signals.             //
        // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        output phy_rx_valvref_ctrl, // Tell ADC the Rx Valid Lane Vref level to operate in.

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );

    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//
    //=========================.
    // MBTRAIN.DATAVREF:       |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state prespective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//

    modport  datavref_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  datavref_en            , output datavref_done          ,
        output datavref_fail_flag     , // To report if the Data Vref calibration failed.
        output trainerror_req         , // To request TRAINERROR implementation (because of (Timeout) OR (receiving TRAINERROR req)).
        input  mb_rx_data_lane_mask   , // Describes the Functional Rx Lanes (Active Lanes) in 3-bit. as in table 4-9 in UCIe_reference

        // ======================= //
        // MB signals.             //
        // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        output phy_rx_datavref_ctrl, // Tell ADC the Rx Data Lane Vref level to operate in.

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );


    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//
    //=========================.
    // MBTRAIN.SPEEDIDLE:      |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state prespective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//

    modport  speedidle_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  speedidle_en           , output speedidle_done        ,
        output trainerror_req         , // To request TRAINERROR implementation (because of (Timeout) OR (receiving TRAINERROR req)).
        input  state_n                , // for RF (to get the last states name). state_n[0]: current state, state_n[1]: previous state, state_n[2]: previous previous state, state_n[3]: previous previous previous state.

        // ======================= //
        // MB signals.             //
        // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        output param_negotiated_max_speed,
        output phy_negotiated_speed      ,
        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//

    //=========================.
    // MBTRAIN.TXSELFCAL:      |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state prespective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport  txselfcal_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  txselfcal_en          , output txselfcal_done        ,
        output trainerror_req        , // To request TRAINERROR implementation (because of (Timeout) OR (receiving TRAINERROR req)).

        // ======================= //
        // MB signals.             //
        // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel  , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        output phy_tx_selfcal_en   , // Enable Tx Self Calibration (To adjust the MB Tx analog circuits).

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//

    //=========================.
    // MBTRAIN.RXCLKCAL:       |
    //=======================================================================================//
    // Control Signals from the LTSM substate prespective:                                   //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport  rxclkcal_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  rxclkcal_en           , output rxclkcal_done         ,
        output trainerror_req        , // To request TRAINERROR implementation.

        // ======================= //
        // MB signals.             //
        // ======================= //
        output mb_tx_clk_lane_sel   ,
        output mb_tx_trk_lane_sel   ,
        output mb_tx_data_lane_sel  ,
        output mb_tx_val_lane_sel   ,
        output mb_rx_clk_lane_sel   ,
        output mb_rx_trk_lane_sel   ,
        output mb_rx_data_lane_sel  ,
        output mb_rx_val_lane_sel   ,

        output mb_tx_pattern_en     ,
        output mb_tx_pattern_setup  ,
        output mb_tx_clk_pattern_sel,

        // ======================= //
        // PHY Rx/Tx control       //
        // ======================= //
        output phy_rx_clock_lock_en          ,
        output phy_rx_track_lock_en          ,
        output phy_rx_phase_detector_en      ,
        output phy_tx_tckn_shift_en          ,
        input  phy_rx_tckn_shift             ,
        input  phy_rx_decrement_shift        ,
        output phy_tx_tckn_shift             ,
        output phy_tx_decrement_shift        ,
        input  phy_tx_tckn_shift_out_of_range,

        // ======================= //
        // RF Signals              //
        // ======================= //
        input  phy_negotiated_speed      , // this signal to know the max link speed.

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid,
        output tx_sb_msg      ,
        output tx_msginfo     ,
        output tx_data_field  ,

        // For SB RX:
        input rx_sb_msg_valid,
        input rx_sb_msg      ,
        input rx_msginfo     ,
        input rx_data_field
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//

    //=========================.
    // MBTRAIN.VALTRAINCENTER: |
    //=======================================================================================//
    // Control Signals from the LTSM substate prespective:                                   //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport valtraincenter_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  valtraincenter_en, output valtraincenter_done, output valtraincenter_fail_flag,
        output trainerror_req,

        // ======================= //
        // MB signals.             //
        // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        // ======================= //
        // PHY Rx/Tx control       //
        // ======================= //
        output phy_tx_pi_phase_ctrl, // Tell ADC the Tx Clock Lane PI phase level.

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//
    //=========================.
    // MBTRAIN.VALTRAINVREF:   |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state prespective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport valtrainvref_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  valtrainvref_en, output valtrainvref_done, output valtrainvref_fail_flag,
        input  valtraincenter_fail_flag, // Read by VALTRAINVREF S2 to skip sweep when VALTRAINCENTER failed.
        output trainerror_req,

        // ======================= //
        // MB signals.             //
        // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        output phy_rx_valvref_ctrl, // Tell ADC the Rx Valid Lane Vref level to operate in.

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//



    //==========================.
    // MBTRAIN.DATATRAINCENTER1:|
    //=======================================================================================//
    // Control Signals from the LTSM sub-state perspective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport datatraincenter1_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
         // ======================= //
         input  datatraincenter1_en, output datatraincenter1_done, output datatraincenter1_fail_flag,
         output trainerror_req,
         input  mb_rx_data_lane_mask, // Describes the Functional Rx Lanes (Active Lanes) in 3-bit encoding.

         // ======================= //
         // MB signals.             //
         // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        // ======================= //
        // PHY Rx/Tx control       //
        // ======================= //
        output phy_tx_pi_phase_ctrl, // Tell PHY the Tx Clock Lane PI phase (per-lane phase sweep).

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//

    //=========================.
    // MBTRAIN.DATATRAINVREF:  |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state perspective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport datatrainvref_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  datatrainvref_en, output datatrainvref_done, output datatrainvref_fail_flag,
        // S2 shortcut inputs: if dtc1_fail_flag==1 OR valtraincenter_fail_flag==1 → skip sweep → S7.
        input  datatraincenter1_fail_flag, // Read by DATATRAINVREF S2 to skip sweep.
        input  valtraincenter_fail_flag  , // Read by DATATRAINVREF S2 to skip sweep.
        output trainerror_req,
        input  mb_rx_data_lane_mask, // Describes the Functional Rx Lanes (Active Lanes) in 3-bit encoding.

        // ======================= //
        // MB signals.             //
        // ======================= //
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        output phy_rx_datavref_ctrl, // Tell PHY the Rx Data Lane Vref level (per-lane, after CALC_APPLY).

        // ======================= //
        // SB signals.             //
        // ======================= //
        output tx_sb_msg_valid,
        output tx_sb_msg      ,
        output tx_msginfo     ,
        output tx_data_field  ,

        input rx_sb_msg_valid,
        input rx_sb_msg      ,
        input rx_msginfo     ,
        input rx_data_field
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//

    //=========================.
    // MBTRAIN.RXDESKEW:       |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state perspective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport rxdeskew_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  rxdeskew_en, output rxdeskew_done, output rxdeskew_fail_flag,
        // Fail flags from prior sub-states (used in RXDESKEW_START_RESP and CHOOSE_PRESET).
        input  datatraincenter1_fail_flag, // Used in accumulative_error for EQ preset selection.
        input  valtraincenter_fail_flag  , // Used in accumulative_error and speed-degrade exit.
        input  partner_valtraincenter_fail_flag , // Used to determine to know if partner needs to exit as fast as possible.
        input  partner_datatraincenter_fail_flag, // Used to determine to know if partner needs a new Tx EQ Preset.
        output trainerror_req,
        // Re-entry signal: when TO_DTC1 fires, this tells controller to re-enable RXDESKEW
        // after DTC1 completes (loop counter is not reset on IDLE2 entry).
        output datatraincenter1_req, // Request DATATRAINCENTER1 re-entry from RXDESKEW.
        input  current_ltsm_state,   // To know if the current unit_LTSM_ctrl state = RESET or not.
        input  mb_rx_data_lane_mask, // To know the Functional Rx Lanes (Active Lanes) in 3-bit encoding.

        // ======================= //
        // MB signals.             //
        // ======================= //
        output mb_tx_clk_lane_sel ,
        output mb_tx_data_lane_sel,
        output mb_tx_val_lane_sel ,
        output mb_tx_trk_lane_sel ,
        output mb_rx_clk_lane_sel ,
        output mb_rx_data_lane_sel,
        output mb_rx_val_lane_sel ,
        output mb_rx_trk_lane_sel ,

        output phy_rx_deskew_ctrl, // Per-lane deskew code (unpacked [15:0] array in interface).
        input  phy_negotiated_speed, // to know the max link speed.

        // ======================= //
        // EQ Preset signals       //
        // ======================= //
        output phy_tx_eq_preset_ctrl, // TX EQ preset code (3-bit) sent to partner.

        // ======================= //
        // SB signals.             //
        // ======================= //
        output tx_sb_msg_valid,
        output tx_sb_msg      ,
        output tx_msginfo     ,
        output tx_data_field  ,

        input rx_sb_msg_valid,
        input rx_sb_msg      ,
        input rx_msginfo     ,
        input rx_data_field
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//

    //==========================.
    // MBTRAIN.DATATRAINCENTER2:|
    //=======================================================================================//
    // Control Signals from the LTSM sub-state perspective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport datatraincenter2_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
         // ======================= //
         input  datatraincenter2_en, output datatraincenter2_done, output datatraincenter2_fail_flag,
         output trainerror_req,
         input  mb_rx_data_lane_mask, // Describes the Functional Rx Lanes (Active Lanes) in 3-bit encoding.

         // ======================= //
         // MB signals.             //
         // ======================= //
         // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        // ======================= //
        // PHY Rx/Tx control       //
        // ======================= //
        output phy_tx_pi_phase_ctrl, // Tell PHY the Tx Clock Lane PI phase (per-lane phase sweep).

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//

    //========================.
    // MBTRAIN.LINKSPEED:     |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state perspective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport linkspeed_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  linkspeed_en, output linkspeed_done, output linkspeed_fail_flag,
        output trainerror_req,

        // Previous substates fail flags (read-only inputs to decide exit path)
        input  datatraincenter2_fail_flag,
        input  datatrainvref_fail_flag   ,
        input  valtrainvref_fail_flag    ,
        input  valtraincenter_fail_flag  ,

        // Negotiated speed from MBINIT.PARAM
        input  param_negotiated_max_speed,

        // ======================= //
        // MB signals.             //
        // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        // ======================= //
        // PHY Rx/Tx control       //
        // ======================= //
        output phy_negotiated_speed, // Drive the agreed link speed to the PHY analog circuits.

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//

    //========================.
    // MBTRAIN.REPAIR:        |
    //=======================================================================================//
    // Control Signals from the LTSM sub-state perspective:                                  //
    // LTSM -> LTSM                                                                          //
    //=======================================================================================//
    modport repair_mp (
        // ======================= //
        // Clock and Reset.        //
        // ======================= //
        input  lclk, input  rst_n,

        // ======================= //
        // Timers signals.         //
        // ======================= //
        output timeout_timer_en      , input  timeout_8ms_occured    ,
        output analog_settle_timer_en, input  analog_settle_time_done,

        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        input  repair_en  , output repair_done, output repair_req,
        output trainerror_req,

        // Result from LINKSPEED: if set we just degrade, not repair
        input  linkspeed_fail_flag,

        // ======================= //
        // MB signals.             //
        // ======================= //
        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        // ======================= //
        // SB signals.             //
        // ======================= //
        // For SB TX:
        output tx_sb_msg_valid, // Tell the SB that the selected message is valid.
        output tx_sb_msg      , // Tell the Sideband the message that it should to send.
        output tx_msginfo     , // MsgInfo field of the SB message.
        output tx_data_field  , // Data field of the SB message.

        // For SB RX:
        input rx_sb_msg_valid, // Indicates that the sideband message is valid.
        input rx_sb_msg      , // Get the Received SB msg.
        input rx_msginfo     , // MsgInfo field of the SB message received.
        input rx_data_field    // Data field of the SB message.
    );
    //____________________________________________________________________________________________________________________________________________________________________________________________________________________________________________//























    modport datavref2ltsm_mp (
        input  datavref_en            , // Enable the DATAVREF FSM.
        output datavref_done          , // To Know if the DATAVREF FSM is done.
        output datavref_fail_flag     , // To report if the Data Vref calibration failed.
        // output successful_clk_sampling, // To know if the clock needs to take a shift (to right or to left).
        output trainerror_req         , // To request TRAINERROR implementation (because of (Timeout) OR (receiving TRAINERROR req)).
        input  mb_rx_data_lane_mask     // Describes the Functional Rx Lanes (Active Lanes) in 3-bit. as in table 4-9 in UCIe_reference
    );

    //=======================================================================================//
    // Control Signals from the LTSM to the MB direction: (LTSM prespective)                 //
    // LTSM -> MB                                                                            //
    //=======================================================================================//
    modport datavref2mb_mp (
        // Lane Behavior Control
        output mb_tx_clk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        output mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        output mb_tx_val_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        output mb_tx_trk_lane_sel , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
        output mb_rx_clk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        output mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        output mb_rx_val_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        output mb_rx_trk_lane_sel , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        output phy_rx_datavref_ctrl  // Tell ADC the Rx Data Lane Vref level to operate in.
    );


    modport ltsm_ctrl2states_mp (
        input  lclk               , input rst_n,
        input  state_req          , input mbtrain_speedidle_req, input timeout_8ms_occured,
        output current_ltsm_state ,

        // MBTRAIN handshake
        output reset_en           , input reset_done           ,input reset_req     ,
        output sbinit_en          , input sbinit_done                               ,
        output mbinit_en          , input mbinit_done                               ,
        output mbtrain_en         , input mbtrain_done                              ,
        output linkinit_en        , input linkinit_done                             ,
        output active_en                                                            ,
        output phyretrain_en      , input phyretrain_done      ,input phyretrain_req,
        output trainerror_en      , input trainerror_done      ,input trainerror_req
    );

    modport mbtrain_mp (
        input  lclk      , input  rst_n       ,
        input  mbtrain_en, output mbtrain_done,
        output current_mbtrain_substate       ,
        input  trainerror_req, input phyretrain_req, input linkinit_req,

        // Sub-state handshakes:
        input  mbtrain_repair_req, mbtrain_speedidle_req, mbtrain_txselfcal_req,
        output valvref_en         , input valvref_done                                           ,
        output datavref_en        , input datavref_done        , input datavref_fail_flag        , // datavref_fail_flag: For MBTRAIN.DATAVREF FSM state: To report if the Data  Vref calibration failed.
        output speedidle_en       , input speedidle_done       , input speedidle_req             ,
        output txselfcal_en       , input txselfcal_done                                         ,
        output rxclkcal_en        , input rxclkcal_done                                          ,
        output valtraincenter_en  , input valtraincenter_done  , input valtraincenter_fail_flag  , // valtraincenter_fail_flag: For MBTRAIN.VALTRAINCENTER FSM state: To report if there was a fail in calibration.
        output valtrainvref_en    , input valtrainvref_done                                      ,
        output datatraincenter1_en, input datatraincenter1_done, input  datatraincenter1_req     ,
        output datatrainvref_en   , input datatrainvref_done                                     ,
        output rxdeskew_en        , input rxdeskew_done                                          ,
        output datatraincenter2_en, input datatraincenter2_done                                  ,
        output linkspeed_en       , input linkspeed_done                                         ,
        output repair_en          , input repair_done          , input repair_req
    );



endinterface
