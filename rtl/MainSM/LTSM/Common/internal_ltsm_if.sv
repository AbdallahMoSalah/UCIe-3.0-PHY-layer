// This interface file needs these packages before we compile it:
//      rtl/common/UCIe_pkg.sv
//      rtl/MainSM/LTSM/common/ltsm_state_n_pkg.sv
//      rtl/MainSM/common/LTSM_state_pkg.sv

interface internal_ltsm_if #(
        parameter MAX_VAL_VREF_CODE  = 'D127, // for Reference Rx Valid Lane Vref control. For the MB Rx Valid Lane.
        parameter MAX_DATA_VREF_CODE = 'D127, // for Reference Rx Data Lanes Vref control. For the MB Rx Data Lanes.
        parameter MAX_PI_PHASE_CODE  = 'D172, // for Phase Interpolator (PI) control.      For the MB Tx Data Lanes.
        parameter MAX_DESKEW_CODE    = 'D127  // for Deskew control.                       For the MB Rx Data Lanes.
    ) (
        input logic lclk,
        input logic rst_n
    );

    // For analog Voltage control.
    localparam VAL_VREF_CODE_WIDTH  = $clog2(MAX_VAL_VREF_CODE );
    localparam DATA_VREF_CODE_WIDTH = $clog2(MAX_DATA_VREF_CODE);
    localparam PI_PHASE_WIDTH       = $clog2(MAX_PI_PHASE_CODE);
    localparam DESKEW_WIDTH         = $clog2(MAX_DESKEW_CODE);

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
    logic mbtrain_repair_req , mbtrain_speedidle_req, mbtrain_txselfcal_req     ; // we use the signals that starts with "mbtrain_..." for the requests that come from State outside the MBTRAIN substates.
    logic valvref_en         , valvref_done                                     ;
    logic datavref_en        , datavref_done                                    ;
    logic speedidle_en       , speedidle_done       , speedidle_req             ;
    logic txselfcal_en       , txselfcal_done       , txselfcal_req             ;
    logic rxclkcal_en        , rxclkcal_done                                    ;
    logic valtraincenter_en  , valtraincenter_done  , valtraincenter_fail_flag  ;
    logic valtrainvref_en    , valtrainvref_done                                ;
    logic datatraincenter1_en, datatraincenter1_done, datatraincenter1_req;
    logic datatrainvref_en   , datatrainvref_done                               ;
    logic rxdeskew_en        , rxdeskew_done                                    ;
    logic datatraincenter2_en, datatraincenter2_done                            ;
    logic linkspeed_en       , linkspeed_done                                   ;
    logic [15:0] linkspeed_success_lanes                                        ; // From LINKSPEED to REPAIR: indicates the lanes that passed the test.
    logic repair_en          , repair_done          , repair_req                ;

    // PHY_IN_RETRAIN handshake between PHYRETRAIN state and MBTRAIN.LINKSPEED sub-state.
    // Spec 4.5.3.4.12: if PHY-retrain set PHY_IN_RETRAIN=1 AND params_changed=1,
    // LINKSPEED must exit via phy_retrain path instead of the normal done path.
    logic phyretrain_PHY_IN_RETRAIN; // Input to LINKSPEED: did PHYRETRAIN assert PHY_IN_RETRAIN?
    logic linkspeed_PHY_IN_RETRAIN ; // Output from LINKSPEED: sampled copy used in EVAL_RESULT decision.
    logic params_changed           ; // Input to LINKSPEED: did link parameters change during PHYRETRAIN?


