// here we target to rought these modules together:
// 1. MBTRAIN wrapper  : wrapper_MBINIT.sv
// 2. MBTRAIN unit     : wrapper_MBTRAIN.sv
// 3. D2C tests wrapper: wrapper_D2C_PT.sv

import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import UCIe_pkg::*;

module  wrapper_mbtrain_mbinit_d2c_mux_tb #(
        parameter integer MAX_VAL_VREF_CODE  = 127 , // unit_VALVREF / unit_VALTRAINVREF upper bound
        parameter integer MIN_VAL_VREF_CODE  = 0   , // unit_VALVREF / unit_VALTRAINVREF lower bound
        parameter integer MAX_DATA_VREF_CODE = 127 , // unit_DATAVREF / unit_DATATRAINVREF upper bound
        parameter integer MIN_DATA_VREF_CODE = 0   , // unit_DATAVREF / unit_DATATRAINVREF lower bound
        parameter integer MAX_PI_PHASE_CODE  = 127 , // PI phase upper bound (VALTRAINCENTER, DTC1/2)
        parameter integer MIN_PI_PHASE_CODE  = 0   , // PI phase lower bound
        parameter integer MAX_DESKEW_CODE    = 127 , // for Deskew control. For the MB Rx Data Lanes.
        parameter integer MIN_DESKEW_CODE    = 0   , // for Deskew control. For the MB Rx Data Lanes.
        parameter integer D2C_ITER_COUNT     = 2   ,
        parameter integer D2C_BURST_COUNT    = 16

    ) (
        input  logic lclk,
        input  logic rst_n,

        // -- Timers --
        output logic timeout_timer_en,
        input  logic timeout_8ms_occured,
        output logic analog_settle_timer_en,
        input  logic analog_settle_time_done,

        // -- General signals --
        output logic trainerror_req,
        input  logic mbtrain_repair_req,
        input  logic mbtrain_speedidle_req,
        input  logic mbtrain_txselfcal_req,
        input  logic mbtrain_en,
        output logic mbtrain_done,
        output mbtrain_substate_e current_mbtrain_substate,
        input  LTSM_state_e       current_ltsm_state,
        input  logic [2:0] mbinit_rx_data_lane_mask,
        input  logic [2:0] mbinit_tx_data_lane_mask,
        output logic [2:0] mb_rx_data_lane_mask,
        output logic [2:0] mb_tx_data_lane_mask,
        input  state_n_e   state_n[3:0],

        // PHY_IN_RETRAIN interface (spec 4.5.3.4.12)
        input  logic phyretrain_PHY_IN_RETRAIN,
        output logic linkspeed_PHY_IN_RETRAIN,
        input  logic params_changed,

        // 1. VALVREF & 7. VALTRAINVREF analog signals:
        output logic [$clog2(MAX_VAL_VREF_CODE)-1:0] phy_rx_valvref_ctrl,

        // 2. DATAVREF & 9. DATATRAINVREF analog signals:
        output logic [$clog2(MAX_DATA_VREF_CODE)-1:0] phy_rx_datavref_ctrl[15:0],

        // 3. SPEEDIDLE analog signals:
        input  logic [2:0] param_negotiated_max_speed,
        output logic [2:0] phy_negotiated_speed,

        // 4. TXSELFCAL analog signals:
        output logic phy_tx_selfcal_en,

        // 5. RXCLKCAL analog signals:
        output logic phy_rx_clock_lock_en,
        output logic phy_rx_track_lock_en,
        output logic phy_rx_phase_detector_en,
        output logic phy_tx_tckn_shift_en,
        input  logic [4:0] phy_rx_tckn_shift,
        input  logic phy_rx_decrement_shift,
        output logic [4:0] phy_tx_tckn_shift,
        output logic phy_tx_decrement_shift,
        input  logic phy_tx_tckn_shift_out_of_range,

        // 6. VALTRAINCENTER analog signals:
        output logic [$clog2(MAX_PI_PHASE_CODE + 1)-1:0] phy_tx_val_pi_phase_ctrl,

        // 8. DATATRAINCENTER1 & 12. DATATRAINCENTER2 analog signals:
        output logic [$clog2(MAX_PI_PHASE_CODE + 1)-1:0] phy_tx_data_pi_phase_ctrl[15:0],

        // 10. RXDESKEW analog signals:
        output logic [$clog2(MAX_DESKEW_CODE + 1)-1:0] phy_rx_deskew_ctrl[15:0],
        output logic [2:0] phy_tx_eq_preset_ctrl,

        // -- RF inputs / params --
        input  logic rf_cap_SPMW,
        input  logic [3:0] rf_ctrl_target_link_width,
        input  logic param_UCIe_S_x8,

        // ======================= //
        // MB signals.             //
        // ======================= //
        output logic [1:0] mb_tx_clk_lane_sel,
        output logic [1:0] mb_tx_data_lane_sel,
        output logic [1:0] mb_tx_val_lane_sel,
        output logic [1:0] mb_tx_trk_lane_sel,
        output logic mb_rx_clk_lane_sel,
        output logic mb_rx_data_lane_sel,
        output logic mb_rx_val_lane_sel,
        output logic mb_rx_trk_lane_sel,

        output logic mb_tx_pattern_en,
        output logic [2:0] mb_tx_pattern_setup,
        output logic [1:0] mb_tx_clk_pattern_sel,

        // ======================= //
        // SB signals.             //
        // ======================= //
        output logic tx_sb_msg_valid,
        output msg_no_e tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic rx_sb_msg_valid,
        input  msg_no_e rx_sb_msg,
        input  logic [15:0] rx_msginfo,
        input  logic [63:0] rx_data_field,

        // ====================================== //
        // MB D2C point tests additinal singals.  //
        // ====================================== //
        output logic mb_tx_clk_sampling_en,
        output logic [1:0] mb_tx_clk_sampling,
        output logic [1:0] mb_tx_data_pattern_sel,
        output logic mb_tx_val_pattern_sel,
        output logic mb_tx_lfsr_en,
        output logic mb_tx_lfsr_rst,
        output logic mb_rx_lfsr_en,
        output logic mb_rx_lfsr_rst,
        output logic mb_tx_pattern_mode,
        output logic [15:0] mb_tx_burst_count,
        output logic [15:0] mb_tx_idle_count,
        output logic [15:0] mb_tx_iter_count,
        output logic mb_rx_compare_en,
        output logic [15:0] mb_rx_max_err_thresh_aggr,
        output logic [11:0] mb_rx_max_err_thresh_perlane,
        output logic [1:0] mb_rx_compare_setup,

        input  logic mb_tx_pattern_count_done,
        input  logic [15:0] mb_rx_aggr_err,
        input  logic [15:0] mb_rx_perlane_err,
        input  logic mb_rx_val_err,
        input  logic mb_rx_clk_err,
        input  logic mb_rx_compare_done,
        input  logic [11:0] cfg_train4_max_err_thresh_perlane,
        input  logic [15:0] cfg_train4_max_err_thresh_aggr
    );

    // =========================================================== //
    // Interfaceses                                                //
    // =========================================================== //
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE ), // for Reference Rx Valid Lane Vref control. For the MB Rx Valid Lane.
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE), // for Reference Rx Data Lanes Vref control. For the MB Rx Data Lanes.
        .MAX_PI_PHASE_CODE  (MAX_PI_PHASE_CODE ), // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE   )  // for Deskew control.
    ) mbtrain_if (.lclk(lclk), .rst_n(rst_n));

    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE ), // for Reference Rx Valid Lane Vref control. For the MB Rx Valid Lane.
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE), // for Reference Rx Data Lanes Vref control. For the MB Rx Data Lanes.
        .MAX_PI_PHASE_CODE  (MAX_PI_PHASE_CODE ), // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE   )  // for Deskew control.
    ) mbinit_if             (.lclk(lclk), .rst_n(rst_n));

    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE ), // for Reference Rx Valid Lane Vref control. For the MB Rx Valid Lane.
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE), // for Reference Rx Data Lanes Vref control. For the MB Rx Data Lanes.
        .MAX_PI_PHASE_CODE  (MAX_PI_PHASE_CODE ), // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE   )  // for Deskew control.
    ) d2c2mux_if (.lclk(lclk), .rst_n(rst_n));

    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE ), // for Reference Rx Valid Lane Vref control. For the MB Rx Valid Lane.
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE), // for Reference Rx Data Lanes Vref control. For the MB Rx Data Lanes.
        .MAX_PI_PHASE_CODE  (MAX_PI_PHASE_CODE ), // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE   )  // for Deskew control.
    ) current_ltsm_state_if (.lclk(lclk), .rst_n(rst_n));


    // =========================================================== //
    // Modules instantiation                                       //
    // =========================================================== //
    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE ), // unit_VALVREF / unit_VALTRAINVREF upper bound
        .MIN_VAL_VREF_CODE (MIN_VAL_VREF_CODE ), // unit_VALVREF / unit_VALTRAINVREF lower bound
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE), // unit_DATAVREF / unit_DATATRAINVREF upper bound
        .MIN_DATA_VREF_CODE(MIN_DATA_VREF_CODE), // unit_DATAVREF / unit_DATATRAINVREF lower bound
        .MAX_PI_PHASE_CODE (MAX_PI_PHASE_CODE ), // PI phase upper bound (VALTRAINCENTER, DTC1/2)
        .MIN_PI_PHASE_CODE (MIN_PI_PHASE_CODE ), // PI phase lower bound
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE   ), // for Deskew control. For the MB Rx Data Lanes.
        .MIN_DESKEW_CODE   (MIN_DESKEW_CODE   )  // for Deskew control. For the MB Rx Data Lanes.
    ) u_wrapper_MBTRAIN (
        .mbtrain_if (mbtrain_if.mbtrain_mp     ),
        .d2c_if     (mbtrain_if.substate2d2c_mp)
    );


    wrapper_D2C_PT #( ) u_wrapper_D2C_PT (
        .mbtrain_if           (mbtrain_if.d2c2substate_mp),
        .mbinit_if            (mbinit_if.d2c2substate_mp ),
        .current_ltsm_state_if(current_ltsm_state_if.current_ltsm_state_mp), // used to know when the LTSM enter the RESET State.
        .mux_if               (d2c2mux_if.d2c2mux_mp) // These interface is the most important interface, as it is the one that connects the MB & SB. It has signals need to be muxed with MBTRAIN & MBINIT signals that target to be connected to the MB & SB & RF.
    );

    // MBINIT Module not build yet so, here is its place .....



    // ========================================================================================================================== //
    // ========================================================================================================================== //
    // ===========================================                                    =========================================== //
    // =======================================                                            ======================================= //
    // ===================================                                                    =================================== //
    // ===============================           Connect the Input ports of each modport          =============================== //
    // ===================================                                                    =================================== //
    // =======================================                                            ======================================= //
    // ===========================================                                    =========================================== //
    // ========================================================================================================================== //
    // ========================================================================================================================== //

    // =========================================================== //
    // Assign `mbtrain_mp` inputs.                                 //
    // =========================================================== //
    // -- Timers --
    assign mbtrain_if.timeout_8ms_occured            = timeout_8ms_occured           ;
    assign mbtrain_if.analog_settle_time_done        = analog_settle_time_done       ;

    // -- General signals --
    assign mbtrain_if.mbtrain_repair_req             = mbtrain_repair_req            ;
    assign mbtrain_if.mbtrain_speedidle_req          = mbtrain_speedidle_req         ;
    assign mbtrain_if.mbtrain_txselfcal_req          = mbtrain_txselfcal_req         ;
    assign mbtrain_if.mbtrain_en                     = mbtrain_en                    ;
    assign mbtrain_if.current_ltsm_state             = current_ltsm_state            ;  // Needed by RXDESKEW for RESET detection.
    assign mbtrain_if.mbinit_rx_data_lane_mask       = mbinit_rx_data_lane_mask      ;
    assign mbtrain_if.mbinit_tx_data_lane_mask       = mbinit_tx_data_lane_mask      ;
    genvar prior_state_num;
    generate
        for (prior_state_num = 0; prior_state_num < 4; prior_state_num++) begin : prior_state_loop
            assign mbtrain_if.state_n[prior_state_num] = state_n[prior_state_num];
        end
    endgenerate

    // 12. LINKSPEED Sub-state and PHYRETRAIN State
    assign mbtrain_if.phyretrain_PHY_IN_RETRAIN      = phyretrain_PHY_IN_RETRAIN     ; // From PHYRETRAIN state: was PHY_IN_RETRAIN asserted?
    assign mbtrain_if.params_changed                 = params_changed                ; // Were link parameters changed during PHYRETRAIN?

    // 3. SPEEDIDLE analog signals:
    assign mbtrain_if.param_negotiated_max_speed     = param_negotiated_max_speed    ; // from MBINIT.

    // 5. RXCLKCAL analog signals:
    assign mbtrain_if.phy_rx_tckn_shift              = phy_rx_tckn_shift             ;
    assign mbtrain_if.phy_rx_decrement_shift         = phy_rx_decrement_shift        ;
    assign mbtrain_if.phy_tx_tckn_shift_out_of_range = phy_tx_tckn_shift_out_of_range;

    // -- RF inputs / params --
    assign mbtrain_if.rf_cap_SPMW                    = rf_cap_SPMW                   ; // from RF.
    assign mbtrain_if.rf_ctrl_target_link_width      = rf_ctrl_target_link_width     ; // from RF.
    assign mbtrain_if.param_UCIe_S_x8                = param_UCIe_S_x8               ; // from MBINIT.

    // SB signals.
    assign mbtrain_if.rx_sb_msg_valid                = rx_sb_msg_valid               ;
    assign mbtrain_if.rx_sb_msg                      = rx_sb_msg                     ;
    assign mbtrain_if.rx_msginfo                     = rx_msginfo                    ;
    assign mbtrain_if.rx_data_field                  = rx_data_field                 ;



    // =========================================================== //
    // Assign `mbinit_mp` inputs.                                  //
    // =========================================================== //
    // TODO: This is a placeholder for future implementation.
    //       Now I don't need to fill this part...
    //
    //
    //
    //
    //
    //
    //
    //
    // =========================================================== //



    // =========================================================== //
    // Assign `d2c2substate_mp` inputs.                            //
    // Assign `substate2d2c_mp` inputs.                            //
    // =========================================================== //
    // Note: Since all input  signals in `d2c2substate_mp` are received from `substate2d2c_mp`,
    //             all output signals in `d2c2substate_mp` are sent to       `substate2d2c_mp`,
    //             we have connected  `mbtrain_if.d2c2substate_mp` with `mbtrain_if.substate2d2c_mp`, and
    //             we have connected  `mbinit_if.d2c2substate_mp` with `mbinit_if.substate2d2c_mp`.
    //             we don't need to re-assign any signals here, because they already assigned above.


    // =========================================================== //
    // Assign `current_ltsm_state_mp` inputs.                      //
    // =========================================================== //
    assign current_ltsm_state_if.current_ltsm_state = current_ltsm_state;


    // =========================================================== //
    // Assign `d2c2mux_mp` inputs.                                 //
    // =========================================================== //
    assign d2c2mux_if.mb_tx_pattern_count_done          = mb_tx_pattern_count_done         ; // Asserted (=1) once MB completes the iter_count.
    assign d2c2mux_if.mb_rx_aggr_err                    = mb_rx_aggr_err                   ; // The total calculated Aggregate Errors on Rx.
    assign d2c2mux_if.mb_rx_perlane_err                 = mb_rx_perlane_err                ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
    assign d2c2mux_if.mb_rx_val_err                     = mb_rx_val_err                    ; // The error coming from Valid Lane receiver in MB.
    assign d2c2mux_if.mb_rx_clk_err                     = mb_rx_clk_err                    ; // The error coming from Clock Lane receiver in MB.
    assign d2c2mux_if.mb_rx_compare_done                = mb_rx_compare_done               ; // From MB to LTSM to tell that comparison of burst_count is done.

    // For SB RX:
    assign d2c2mux_if.rx_sb_msg_valid                   = rx_sb_msg_valid                  ; // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
    assign d2c2mux_if.rx_sb_msg                         = rx_sb_msg                        ; // Get the Received SB msg.
    assign d2c2mux_if.rx_msginfo                        = rx_msginfo                       ; // MsgInfo field of the SB message received.
    assign d2c2mux_if.rx_data_field                     = rx_data_field                    ; // Data field of the SB message.

    // Register File (RF) Control Signals:
    // Training Setup 4 (Offset 1050h)
    assign d2c2mux_if.cfg_train4_max_err_thresh_perlane = cfg_train4_max_err_thresh_perlane; // Max error Threshold in per-Lane comparison for error counting.
    assign d2c2mux_if.cfg_train4_max_err_thresh_aggr    = cfg_train4_max_err_thresh_aggr   ; // Max error Threshold in aggregate comparison for error counting.




    // ========================================================================================================================== //
    // ========================================================================================================================== //
    // ===========================================                                    =========================================== //
    // =======================================                                            ======================================= //
    // ===================================                                                    =================================== //
    // ===============================          Connect the output ports of each modport          =============================== //
    // ===================================                                                    =================================== //
    // =======================================                                            ======================================= //
    // ===========================================                                    =========================================== //
    // ========================================================================================================================== //
    // ========================================================================================================================== //

    // =========================================================== //
    // Assign signals to `mbtrain_mp` outputs.                     //
    // =========================================================== //
    // -- Timers --
    assign timeout_timer_en          = mbtrain_if.timeout_timer_en         ;
    assign analog_settle_timer_en    = mbtrain_if.analog_settle_timer_en   ;

    // -- General signals --
    assign trainerror_req            = mbtrain_if.trainerror_req           ;
    assign mbtrain_done              = mbtrain_if.mbtrain_done             ;
    assign current_mbtrain_substate  = mbtrain_if.current_mbtrain_substate ;
    assign mb_rx_data_lane_mask      = mbtrain_if.mb_rx_data_lane_mask     ;
    assign mb_tx_data_lane_mask      = mbtrain_if.mb_tx_data_lane_mask     ;

    // PHY_IN_RETRAIN interface (spec 4.5.3.4.12)
    assign linkspeed_PHY_IN_RETRAIN  = mbtrain_if.linkspeed_PHY_IN_RETRAIN ;

    // 1. VALVREF & 7. VALTRAINVREF analog signals:
    assign phy_rx_valvref_ctrl       = mbtrain_if.phy_rx_valvref_ctrl      ;

    // 3. SPEEDIDLE analog signals:
    assign phy_negotiated_speed      = mbtrain_if.phy_negotiated_speed     ;

    // 4. TXSELFCAL analog signals:
    assign phy_tx_selfcal_en         = mbtrain_if.phy_tx_selfcal_en        ;

    // 5. RXCLKCAL analog signals:
    assign phy_rx_clock_lock_en      = mbtrain_if.phy_rx_clock_lock_en     ;
    assign phy_rx_track_lock_en      = mbtrain_if.phy_rx_track_lock_en     ;
    assign phy_rx_phase_detector_en  = mbtrain_if.phy_rx_phase_detector_en ;
    assign phy_tx_tckn_shift_en      = mbtrain_if.phy_tx_tckn_shift_en     ;
    assign phy_tx_tckn_shift         = mbtrain_if.phy_tx_tckn_shift        ;
    assign phy_tx_decrement_shift    = mbtrain_if.phy_tx_decrement_shift   ;

    // -- Monitoring Signals (for TB models) --
    assign rx_pt_en                  = mbtrain_if.rx_pt_en                 ;
    assign tx_pt_en                  = mbtrain_if.tx_pt_en                 ;

    // 6. VALTRAINCENTER analog signals:
    assign phy_tx_val_pi_phase_ctrl  = mbtrain_if.phy_tx_val_pi_phase_ctrl ;

    // 10. RXDESKEW analog signals:
    assign phy_tx_eq_preset_ctrl     = mbtrain_if.phy_tx_eq_preset_ctrl    ;

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane++) begin : data_vref_loop
            // 2. DATAVREF & 9. DATATRAINVREF analog signals:
            assign phy_rx_datavref_ctrl[lane]      = mbtrain_if.phy_rx_datavref_ctrl[lane]     ;

            // 8. DATATRAINCENTER1 & 12. DATATRAINCENTER2 analog signals:
            assign phy_tx_data_pi_phase_ctrl[lane] = mbtrain_if.phy_tx_data_pi_phase_ctrl[lane];

            // 10. RXDESKEW analog signals:
            assign phy_rx_deskew_ctrl[lane]        = mbtrain_if.phy_rx_deskew_ctrl[lane]       ;
        end
    endgenerate



    always_comb begin
        if (current_ltsm_state == MBTRAIN && (!mbtrain_if.tx_pt_en & !mbtrain_if.rx_pt_en)) begin

            // =========================    MBTRAIN signals    ========================= //
            // MB signals.
            mb_tx_clk_lane_sel    = mbtrain_if.mb_tx_clk_lane_sel       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
            mb_tx_data_lane_sel   = mbtrain_if.mb_tx_data_lane_sel      ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
            mb_tx_val_lane_sel    = mbtrain_if.mb_tx_val_lane_sel       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
            mb_tx_trk_lane_sel    = mbtrain_if.mb_tx_trk_lane_sel       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
            mb_rx_clk_lane_sel    = mbtrain_if.mb_rx_clk_lane_sel       ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
            mb_rx_data_lane_sel   = mbtrain_if.mb_rx_data_lane_sel      ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
            mb_rx_val_lane_sel    = mbtrain_if.mb_rx_val_lane_sel       ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
            mb_rx_trk_lane_sel    = mbtrain_if.mb_rx_trk_lane_sel       ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

            mb_tx_pattern_en      = mbtrain_if.mb_tx_pattern_en         ; // Needed for RXCLKCAL. 0b: don't send the pattern; 1b: send the pattern immediately.
            mb_tx_pattern_setup   = mbtrain_if.mb_tx_pattern_setup      ; // Needed for RXCLKCAL. 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            mb_tx_clk_pattern_sel = mbtrain_if.mb_tx_clk_pattern_sel    ; // Needed for RXCLKCAL. 2'b00: operational clock, 2'b01: Held Low, 2'b10: Clock Mode 1, 2'b11: Clock Mode 2.

            // SB signals.
            tx_sb_msg_valid       = mbtrain_if.tx_sb_msg_valid          ;
            tx_sb_msg             = mbtrain_if.tx_sb_msg                ;
            tx_msginfo            = mbtrain_if.tx_msginfo               ;
            tx_data_field         = mbtrain_if.tx_data_field            ;

        end
        else if (current_ltsm_state == MBINIT && (!mbtrain_if.tx_pt_en & !mbtrain_if.rx_pt_en)) begin


            // =========================    MBINIT signals    ========================= //
            // MB signals.
            mb_tx_clk_lane_sel    = mbinit_if.mb_tx_clk_lane_sel       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
            mb_tx_data_lane_sel   = mbinit_if.mb_tx_data_lane_sel      ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
            mb_tx_val_lane_sel    = mbinit_if.mb_tx_val_lane_sel       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
            mb_tx_trk_lane_sel    = mbinit_if.mb_tx_trk_lane_sel       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
            mb_rx_clk_lane_sel    = mbinit_if.mb_rx_clk_lane_sel       ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
            mb_rx_data_lane_sel   = mbinit_if.mb_rx_data_lane_sel      ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
            mb_rx_val_lane_sel    = mbinit_if.mb_rx_val_lane_sel       ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
            mb_rx_trk_lane_sel    = mbinit_if.mb_rx_trk_lane_sel       ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

            mb_tx_pattern_en      = mbinit_if.mb_tx_pattern_en         ; // Needed for RXCLKCAL. 0b: don't send the pattern; 1b: send the pattern immediately.
            mb_tx_pattern_setup   = mbinit_if.mb_tx_pattern_setup      ; // Needed for RXCLKCAL. 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            mb_tx_clk_pattern_sel = mbinit_if.mb_tx_clk_pattern_sel    ; // Needed for RXCLKCAL. 2'b00: operational clock, 2'b01: Held Low, 2'b10: Clock Mode 1, 2'b11: Clock Mode 2.

            // SB signals.
            tx_sb_msg_valid       = mbinit_if.tx_sb_msg_valid          ;
            tx_sb_msg             = mbinit_if.tx_sb_msg                ;
            tx_msginfo            = mbinit_if.tx_msginfo               ;
            tx_data_field         = mbinit_if.tx_data_field            ;

        end
        else begin
            // =========================    D2C Test signals    ========================= //
            //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
            // Tx Pattern Generator Setup Group:
            mb_tx_pattern_en      = d2c2mux_if.mb_tx_pattern_en            ; // 1: Send pattern immediately, 0: Don't send pattern.
            mb_tx_pattern_setup   = d2c2mux_if.mb_tx_pattern_setup         ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            mb_tx_clk_pattern_sel = 2'b00                                  ; // Needed for RXCLKCAL. 2'b00: operational clock, 2'b01: Held Low, 2'b10: Clock Mode 1, 2'b11: Clock Mode 2.

            //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
            // Lane Behavior Control
            mb_tx_clk_lane_sel    = d2c2mux_if.mb_tx_clk_lane_sel          ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
            mb_tx_data_lane_sel   = d2c2mux_if.mb_tx_data_lane_sel         ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
            mb_tx_val_lane_sel    = d2c2mux_if.mb_tx_val_lane_sel          ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
            mb_tx_trk_lane_sel    = d2c2mux_if.mb_tx_trk_lane_sel          ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
            mb_rx_clk_lane_sel    = d2c2mux_if.mb_rx_clk_lane_sel          ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
            mb_rx_data_lane_sel   = d2c2mux_if.mb_rx_data_lane_sel         ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
            mb_rx_val_lane_sel    = d2c2mux_if.mb_rx_val_lane_sel          ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
            mb_rx_trk_lane_sel    = d2c2mux_if.mb_rx_trk_lane_sel          ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

            // For SB TX:
            tx_sb_msg_valid       = d2c2mux_if.tx_sb_msg_valid             ; // Tell the SB that the selected message is valid.
            tx_sb_msg             = d2c2mux_if.tx_sb_msg                   ; // Tell the Sideband the message that it should to send.
            tx_msginfo            = d2c2mux_if.tx_msginfo                  ; // MsgInfo field of the SB message.
            tx_data_field         = d2c2mux_if.tx_data_field               ; // Data field of the SB message.
        end

        // =========================    D2C Test signals    ========================= //
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling and Shapes Details Group:
        mb_tx_clk_sampling_en        = d2c2mux_if.mb_tx_clk_sampling_en       ; // Enable changing Clock sampling/PI phase control state.
        mb_tx_clk_sampling           = d2c2mux_if.mb_tx_clk_sampling          ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

        // Tx Pattern Generator Setup Group:
        mb_tx_data_pattern_sel       = d2c2mux_if.mb_tx_data_pattern_sel      ; // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
        mb_tx_val_pattern_sel        = d2c2mux_if.mb_tx_val_pattern_sel       ; // 0: VALTRAIN pattern, 1: Held Low.
        mb_tx_lfsr_en                = d2c2mux_if.mb_tx_lfsr_en               ; // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
        mb_tx_lfsr_rst               = d2c2mux_if.mb_tx_lfsr_rst              ; // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
        mb_rx_lfsr_en                = d2c2mux_if.mb_rx_lfsr_en               ; // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
        mb_rx_lfsr_rst               = d2c2mux_if.mb_rx_lfsr_rst              ; // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.

        // Tx Pattern Mode Setup Group:
        mb_tx_pattern_mode           = d2c2mux_if.mb_tx_pattern_mode          ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        mb_tx_burst_count            = d2c2mux_if.mb_tx_burst_count           ; // Burst Count: Indicates the duration of selected pattern (UI count).
        mb_tx_idle_count             = d2c2mux_if.mb_tx_idle_count            ; // IDLE Count: Indicates the duration of low following the burst (UI count).
        mb_tx_iter_count             = d2c2mux_if.mb_tx_iter_count            ; // Iterations: Indicates the iteration count of bursts followed by idle.

        // Receiver Comparison Setup & Errors
        mb_rx_compare_en             = d2c2mux_if.mb_rx_compare_en            ; // 1: Enable the Rx comparison circuit, 0: Disable.
        mb_rx_max_err_thresh_aggr    = d2c2mux_if.mb_rx_max_err_thresh_aggr   ; // Max error Threshold in aggregate comparison.
        mb_rx_max_err_thresh_perlane = d2c2mux_if.mb_rx_max_err_thresh_perlane; // Max error Threshold in per Lane comparison.
        mb_rx_compare_setup          = d2c2mux_if.mb_rx_compare_setup         ; // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
    end



endmodule
