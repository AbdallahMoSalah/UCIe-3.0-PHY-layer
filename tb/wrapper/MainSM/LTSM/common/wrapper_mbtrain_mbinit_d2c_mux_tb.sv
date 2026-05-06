// here we target to rought these modules together:
// 1. MBTRAIN wrapper  : wrapper_MBINIT.sv
// 2. MBTRAIN unit     : wrapper_MBTRAIN.sv
// 3. D2C tests wrapper: wrapper_D2C_PT.sv

module  wrapper_mbtrain_mbinit_d2c_mux_tb #() (
        input  lclk,
        input  rst_n,

        // -- Timers --
        output timeout_timer_en,
        input  timeout_8ms_occured,
        output analog_settle_timer_en,
        input  analog_settle_time_done,

        // -- General signals --
        input  mbtrain_repair_req,
        input  mbtrain_speedidle_req,
        input  mbtrain_txselfcal_req,
        input  mbtrain_en,
        output mbtrain_done,
        output current_mbtrain_substate,
        input  current_ltsm_state,
        input  mbinit_rx_data_lane_mask,
        input  mbinit_tx_data_lane_mask,
        output mb_rx_data_lane_mask,
        output mb_tx_data_lane_mask,
        input  state_n,

        // PHY_IN_RETRAIN interface (spec 4.5.3.4.12)
        input  phyretrain_PHY_IN_RETRAIN,
        output linkspeed_PHY_IN_RETRAIN,
        input  params_changed,

        // 1. VALVREF & 7. VALTRAINVREF analog signals:
        output phy_rx_valvref_ctrl           ,

        // 2. DATAVREF & 9. DATATRAINVREF analog signals:
        output phy_rx_datavref_ctrl          ,

        // 3. SPEEDIDLE analog signals:
        input  param_negotiated_max_speed    , // from MBINIT.
        output phy_negotiated_speed          ,

        // 4. TXSELFCAL analog signals:
        output phy_tx_selfcal_en             ,

        // 5. RXCLKCAL analog signals:
        output phy_rx_clock_lock_en          ,
        output phy_rx_track_lock_en          ,
        output phy_rx_phase_detector_en      ,
        output phy_tx_tckn_shift_en          ,
        input  phy_rx_tckn_shift             ,
        input  phy_rx_decrement_shift        ,
        output phy_tx_tckn_shift             ,
        output phy_tx_decrement_shift        ,
        input  phy_tx_tckn_shift_out_of_range,

        // 6. VALTRAINCENTER analog signals:
        output phy_tx_val_pi_phase_ctrl      ,

        // 8. DATATRAINCENTER1 & 12. DATATRAINCENTER2 analog signals:
        output phy_tx_data_pi_phase_ctrl     ,

        // 10. RXDESKEW analog signals:
        output phy_rx_deskew_ctrl            ,
        output phy_tx_eq_preset_ctrl         ,


        // -- RF inputs / params --
        input rf_cap_SPMW               , // from RF.
        input rf_ctrl_target_link_width , // from RF.
        input param_UCIe_S_x8           , // from MBINIT.

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

        output mb_tx_pattern_en     , // Needed for RXCLKCAL. 0b: don't send the pattern; 1b: send the pattern immediately.
        output mb_tx_pattern_setup  , // Needed for RXCLKCAL. 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        output mb_tx_clk_pattern_sel, // Needed for RXCLKCAL. 2'b00: operational clock, 2'b01: Held Low, 2'b10: Clock Mode 1, 2'b11: Clock Mode 2.

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


        // ============================== //
        // MB D2C point tests signals.    //
        // ============================== //


    );



    // //=======================================================================================//
    // // For the `wrapper_MBTRAIN` module Signals. (LTSM State prespective)                    //
    // //=======================================================================================//
    // mbtrain_mp #() (
    //     .lclk(lclk), .rst_n(rst_n),

    //     // -- Timers --
    //     .timeout_timer_en(timeout_timer_en)            , .timeout_8ms_occured(timeout_8ms_occured),
    //     .analog_settle_timer_en(analog_settle_timer_en), .analog_settle_time_done(analog_settle_time_done),

    //     // -- General signals --
    //     .mbtrain_repair_req(mbtrain_repair_req) , .mbtrain_speedidle_req(mbtrain_speedidle_req) , .mbtrain_txselfcal_req(mbtrain_txselfcal_req),
    //     .mbtrain_en(mbtrain_en)                 , .mbtrain_done(mbtrain_done)                   ,
    //     .current_mbtrain_substate(current_mbtrain_substate)                                     ,
    //     .current_ltsm_state(current_ltsm_state) , // Needed by RXDESKEW for RESET detection.,

    //     .mbinit_rx_data_lane_mask(mbinit_rx_data_lane_mask) , .mbinit_tx_data_lane_mask(mbinit_tx_data_lane_mask),
    //     .mb_rx_data_lane_mask(mb_rx_data_lane_mask)         , .mb_tx_data_lane_mask(mb_tx_data_lane_mask)        ,

    //     .state_n(state_n),

    //     // ======================================================================== //
    //     // PHY_IN_RETRAIN interface (spec 4.5.3.4.12)                               //
    //     // Sampled once at LINKSPEED_START_REQ; used in EVAL_RESULT to decide       //
    //     // whether to exit via phy_retrain path (if params changed during retrain). //
    //     // ======================================================================== //
    //     .phyretrain_PHY_IN_RETRAIN.(phyretrain_PHY_IN_RETRAIN) , // From PHYRETRAIN state: was PHY_IN_RETRAIN asserted?
    //     .linkspeed_PHY_IN_RETRAIN .(linkspeed_PHY_IN_RETRAIN)  , // Sampled copy held stable through the sub-state.
    //     .params_changed           .(params_changed)            , // Were link parameters changed during PHYRETRAIN?
    //     // ======================================================================== //


    //     // ======================================================================== //
    //     // PHY Analog / RXCLKCAL / PI                                               //
    //     // ======================================================================== //
    //     // 1. VALVREF & 7. VALTRAINVREF analog signals:
    //     .phy_rx_valvref_ctrl(phy_rx_valvref_ctrl)                      ,

    //     // 2. DATAVREF & 9. DATATRAINVREF analog signals:
    //     .phy_rx_datavref_ctrl(phy_rx_datavref_ctrl)                    ,

    //     // 3. SPEEDIDLE analog signals:
    //     .param_negotiated_max_speed(param_negotiated_max_speed)        , // from MBINIT.
    //     .phy_negotiated_speed(phy_negotiated_speed)                    ,

    //     // 4. TXSELFCAL analog signals:
    //     .phy_tx_selfcal_en(phy_tx_selfcal_en)                          ,

    //     // 5. RXCLKCAL analog signals:
    //     .phy_rx_clock_lock_en(phy_rx_clock_lock_en)                    ,
    //     .phy_rx_track_lock_en(phy_rx_track_lock_en)                    ,
    //     .phy_rx_phase_detector_en(phy_rx_phase_detector_en)            ,
    //     .phy_tx_tckn_shift_en(phy_tx_tckn_shift_en)                    ,
    //     .phy_rx_tckn_shift(phy_rx_tckn_shift)                          ,
    //     .phy_rx_decrement_shift(phy_rx_decrement_shift)                ,
    //     .phy_tx_tckn_shift(phy_tx_tckn_shift)                          ,
    //     .phy_tx_decrement_shift(phy_tx_decrement_shift)                ,
    //     .phy_tx_tckn_shift_out_of_range(phy_tx_tckn_shift_out_of_range),

    //     // 6. VALTRAINCENTER analog signals:
    //     .phy_tx_val_pi_phase_ctrl(phy_tx_val_pi_phase_ctrl)            ,

    //     // 8. DATATRAINCENTER1 & 12. DATATRAINCENTER2 analog signals:
    //     .phy_tx_data_pi_phase_ctrl(phy_tx_data_pi_phase_ctrl)          ,

    //     // 10. RXDESKEW analog signals:
    //     .phy_rx_deskew_ctrl(phy_rx_deskew_ctrl)                        ,
    //     .phy_tx_eq_preset_ctrl(phy_tx_eq_preset_ctrl)                  ,

    //     // -- RF inputs / params --
    //     .rf_cap_SPMW(rf_cap_SPMW)                                      , // from RF.
    //     .rf_ctrl_target_link_width(rf_ctrl_target_link_width)          , // from RF.
    //     .param_UCIe_S_x8(param_UCIe_S_x8)                              , // from MBINIT.

    //     // ======================= //
    //     // MB signals.             //
    //     // ======================= //
    //     // Lane Behavior Control
    //     .mb_tx_clk_lane_sel(.mb_tx_clk_lane_sel)  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
    //     .mb_tx_data_lane_sel(.mb_tx_data_lane_sel), // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
    //     .mb_tx_val_lane_sel(.mb_tx_val_lane_sel)  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
    //     .mb_tx_trk_lane_sel(.mb_tx_trk_lane_sel)  , // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
    //     .mb_rx_clk_lane_sel(.mb_rx_clk_lane_sel)  , // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
    //     .mb_rx_data_lane_sel(.mb_rx_data_lane_sel), // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
    //     .mb_rx_val_lane_sel(mb_rx_val_lane_sel)   , // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
    //     .mb_rx_trk_lane_sel(mb_rx_trk_lane_sel)   , // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

    //     .mb_tx_pattern_en(mb_tx_pattern_en)          , // Needed for RXCLKCAL. 0b: don't send the pattern; 1b: send the pattern immediately.
    //     .mb_tx_pattern_setup(mb_tx_pattern_setup)    , // Needed for RXCLKCAL. 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    //     .mb_tx_clk_pattern_sel(mb_tx_clk_pattern_sel), // Needed for RXCLKCAL. 2'b00: operational clock, 2'b01: Held Low, 2'b10: Clock Mode 1, 2'b11: Clock Mode 2.

    //     // ======================= //
    //     // SB signals.             //
    //     // ======================= //
    //     .tx_sb_msg_valid(tx_sb_msg_valid),
    //     .tx_sb_msg(tx_sb_msg)            ,
    //     .tx_msginfo(tx_msginfo)          ,
    //     .tx_data_field(tx_data_field)    ,

    //     .rx_sb_msg_valid(rx_sb_msg_valid),
    //     .rx_sb_msg(rx_sb_msg)            ,
    //     .rx_msginfo(rx_msginfo)          ,
    //     .rx_data_field(rx_data_field)

    // );

    internal_ltsm_if #()  d2c_if                (.lclk(lclk), .rst_n(rst_n));
    internal_ltsm_if #()  mbinit_if             (.lclk(lclk), .rst_n(rst_n));
    internal_ltsm_if #()  mbtrain_if            (.lclk(lclk), .rst_n(rst_n));
    internal_ltsm_if #()  current_ltsm_state_if (.lclk(lclk), .rst_n(rst_n));

    wrapper_D2C_PT u_wrapper_D2C_PT (
        .mbtrain_if(mbtrain_if.d2c2substate_mp),
        .mbinit_if (mbinit_if.d2c2substate_mp ),
        .current_ltsm_state_if(current_ltsm_state_if.current_ltsm_state_mp),
        .mux_if(d2c_if.d2c2mux_mp)
    );
    modport d2c2substate_mp(
        input  rx_pt_en,
        input  tx_pt_en,
        output test_d2c_done,

        // Clock sampling.
        input  d2c_clk_sampling    , // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

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
        output  partner_valtraincenter_fail_flag   // From our UCIe die Rx. It represents the fail flags of the partner Tx Valid lane.
    );
endmodule
