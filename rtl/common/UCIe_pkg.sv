package UCIe_pkg;

  typedef enum logic [7:0] {



    // ==================================================
    // SBINIT
    // ==================================================
    SBINIT_Out_of_Reset,  // d00
    SBINIT_done_req,      // d01
    SBINIT_done_resp,     // d02  

    // ==================================================
    // RDI
    // ==================================================

    RDI_ACTIVE_REQ, 
    RDI_ACTIVE_RSP,
    RDI_L1_REQ,
    RDI_L1_RSP,
    RDI_L2_REQ,
    RDI_L2_RSP,
    RDI_LINK_RESET_REQ,
    RDI_LINK_RESET_RSP,
    RDI_LINK_ERROR_REQ,
    RDI_LINK_ERROR_RSP,
    RDI_RETRAIN_REQ,
    RDI_RETRAIN_RSP,
    RDI_DISABLE_REQ,
    RDI_DISABLE_RSP,
    NOP,
    RDI_PMNAK_RSP,
    

    // ==================================================
    // MBINIT
    // ==================================================

    // =========================
    // MBINIT.PARAM
    // =========================
    MBINIT_PARAM_configuration_req,   // d03
    MBINIT_PARAM_configuration_resp,  // d04
    MBINIT_PARAM_SBFE_req,            // d05
    MBINIT_PARAM_SBFE_resp,           // d06
    MBINIT_CAL_Done_req,              // d07 
    MBINIT_CAL_Done_resp,             // d08

    // =========================
    // MBINIT.REPAIRCLK
    // =========================
    MBINIT_REPAIRCLK_init_req,     // d09
    MBINIT_REPAIRCLK_init_resp,    // d10  
    MBINIT_REPAIRCLK_result_req,   // d11
    MBINIT_REPAIRCLK_result_resp,  // d12
    MBINIT_REPAIRCLK_done_req,     // d13
    MBINIT_REPAIRCLK_done_resp,    // d14

    // =========================
    // MBINIT.REPAIRVAL
    // =========================
    MBINIT_REPAIRVAL_init_req,     // d15
    MBINIT_REPAIRVAL_init_resp,    // d16
    MBINIT_REPAIRVAL_result_req,   // d17
    MBINIT_REPAIRVAL_result_resp,  // d18
    MBINIT_REPAIRVAL_done_req,     // d19
    MBINIT_REPAIRVAL_done_resp,    // d20

    // =========================
    // MBINIT.REVERSALMB
    // =========================
    MBINIT_REVERSALMB_init_req,          // d21
    MBINIT_REVERSALMB_init_resp,         // d22
    MBINIT_REVERSALMB_clear_error_req,   // d23
    MBINIT_REVERSALMB_clear_error_resp,  // d24
    MBINIT_REVERSALMB_result_req,        // d25
    MBINIT_REVERSALMB_result_resp,       // d26
    MBINIT_REVERSALMB_done_req,          // d27
    MBINIT_REVERSALMB_done_resp,         // d28

    // =========================
    // MBINIT.REPAIRMB
    // =========================
    MBINIT_REPAIRMB_start_req,           // d29
    MBINIT_REPAIRMB_start_resp,          // d30
    MBINIT_REPAIRMB_apply_repair_req,    // d31
    MBINIT_REPAIRMB_apply_repair_resp,   // d32
    MBINIT_REPAIRMB_apply_degrade_req,   // d31
    MBINIT_REPAIRMB_apply_degrade_resp,  // d32
    MBINIT_REPAIRMB_end_req,             // d33
    MBINIT_REPAIRMB_end_resp,            // d34

    // ==================================================
    // MBTRAIN
    // ==================================================

    // =========================
    // MBTRAIN.VALVREF
    // =========================
    MBTRAIN_VALVREF_start_req,   // d35
    MBTRAIN_VALVREF_start_resp,  // d36
    MBTRAIN_VALVREF_end_req,     // d37
    MBTRAIN_VALVREF_end_resp,    // d38

    // =========================
    // MBTRAIN.DATAVREF
    // =========================
    MBTRAIN_DATAVREF_start_req,   // d39  
    MBTRAIN_DATAVREF_start_resp,  // d40
    MBTRAIN_DATAVREF_end_req,     // d41
    MBTRAIN_DATAVREF_end_resp,    // d42

    // =========================
    // MBTRAIN.SPEEDIDLE
    // =========================
    MBTRAIN_SPEEDIDLE_done_req,  // d43
    MBTRAIN_SPEEDIDLE_done_resp, // d44

    // =========================
    // MBTRAIN.TXSELFCAL
    // =========================
    MBTRAIN_TXSELFCAL_Done_req,  // d45
    MBTRAIN_TXSELFCAL_Done_resp, // d46

    // =========================
    // MBTRAIN.RXCLKCAL
    // =========================
    MBTRAIN_RXCLKCAL_start_req,          // d47
    MBTRAIN_RXCLKCAL_start_resp,         // d48
    MBTRAIN_RXCLKCAL_TCKN_L_shift_req,   // d49
    MBTRAIN_RXCLKCAL_TCKN_L_shift_resp,  // d50
    MBTRAIN_RXCLKCAL_done_req,           // d51
    MBTRAIN_RXCLKCAL_done_resp,          // d52

    // =========================
    // MBTRAIN.VALTRAINCENTER
    // =========================
    MBTRAIN_VALTRAINCENTER_start_req,   // d53
    MBTRAIN_VALTRAINCENTER_start_resp,  // d54
    MBTRAIN_VALTRAINCENTER_done_req,    // d55
    MBTRAIN_VALTRAINCENTER_done_resp,   // d56

    // =========================
    // MBTRAIN.VALTRAINVREF
    // =========================
    MBTRAIN_VALTRAINVREF_start_req,   // d57
    MBTRAIN_VALTRAINVREF_start_resp,  // d58
    MBTRAIN_VALTRAINVREF_end_req,     // d59
    MBTRAIN_VALTRAINVREF_end_resp,    // d60


    // =========================
    // MBTRAIN.DATATRAINCENTER1
    // =========================
    MBTRAIN_DATATRAINCENTER1_start_req,  // d61
    MBTRAIN_DATATRAINCENTER1_start_resp,  // d62
    MBTRAIN_DATATRAINCENTER1_end_req,  // d63
    MBTRAIN_DATATRAINCENTER1_end_resp,  // d64

    // =========================
    // MBTRAIN.DATATRAINVREF
    // =========================
    MBTRAIN_DATATRAINVREF_start_req,   // d65
    MBTRAIN_DATATRAINVREF_start_resp,  // d66
    MBTRAIN_DATATRAINVREF_end_req,     // d67
    MBTRAIN_DATATRAINVREF_end_resp,    // d68

    // =========================
    // MBTRAIN.RXDESKEW
    // =========================
    MBTRAIN_RXDESKEW_start_req,                      // d69
    MBTRAIN_RXDESKEW_start_resp,                     // d70
    MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req,   // d73
    MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp,  // d74
    MBTRAIN_RXDESKEW_end_req,                        // d75
    MBTRAIN_RXDESKEW_end_resp,                       // d76

    // =========================
    // MBTRAIN.DATATRAINCENTER2
    // =========================
    MBTRAIN_DATATRAINCENTER2_start_req,  // d77
    MBTRAIN_DATATRAINCENTER2_start_resp,  // d78
    MBTRAIN_DATATRAINCENTER2_end_req,  // d79
    MBTRAIN_DATATRAINCENTER2_end_resp,  // d80

    // =========================
    // MBTRAIN.LINKSPEED
    // =========================
    MBTRAIN_LINKSPEED_start_req,                   // d81
    MBTRAIN_LINKSPEED_start_resp,                  // d82
    MBTRAIN_LINKSPEED_error_req,                   // d83
    MBTRAIN_LINKSPEED_error_resp,                  // d84
    MBTRAIN_LINKSPEED_exit_to_repair_req,          // d85
    MBTRAIN_LINKSPEED_exit_to_repair_resp,         // d86
    MBTRAIN_LINKSPEED_exit_to_speed_degrade_req,   // d87
    MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp,  // d88
    MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req,     // d89 
    MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp,    // d90
    MBTRAIN_LINKSPEED_done_req,                    // d91
    MBTRAIN_LINKSPEED_done_resp,                   // d92

    // =========================
    // MBTRAIN.REPAIR
    // =========================
    MBTRAIN_REPAIR_init_req,            // d93
    MBTRAIN_REPAIR_init_resp,           // d94
    MBTRAIN_REPAIR_apply_repair_req,   // d95
    MBTRAIN_REPAIR_apply_repair_resp,  // d96
    MBTRAIN_REPAIR_apply_degrade_req,   // d95
    MBTRAIN_REPAIR_apply_degrade_resp,  // d96
    MBTRAIN_REPAIR_end_req,             // d97
    MBTRAIN_REPAIR_end_resp,            // d98

    // ==================================================
    // RECAL
    // ==================================================
    RECAL_track_pattern_init_req,  // d99
    RECAL_track_pattern_init_resp,  // d100     
    RECAL_track_tx_adjust_req,          // d101     // This message is under MBTRAIN domain but named after RECAL messages
    RECAL_track_tx_adjust_resp,         // d102     // This message is under MBTRAIN domain but named after RECAL messages
    RECAL_track_pattern_done_req,  // d103
    RECAL_track_pattern_done_resp,  // d104

    // ==================================================
    // PHYRETRAIN
    // ==================================================
    PHYRETRAIN_retrain_start_req,  // d105
    PHYRETRAIN_retrain_start_resp, // d106

    // ==================================================
    // TRAINERROR
    // ==================================================
    TRAINERROR_Entry_req,  // d107
    TRAINERROR_Entry_resp, // d108

    // ==================================================
    // D2C TEST
    // ==================================================

    // =========================
    // Tx Init D2C
    // =========================
    Start_Tx_Init_D_to_C_point_test_req,   // d109
    Start_Tx_Init_D_to_C_point_test_resp,  // d110
    LFSR_clear_error_req,    // d111
    LFSR_clear_error_resp,   // d112
    Tx_Init_D_to_C_results_req,     // d113
    Tx_Init_D_to_C_results_resp,    // d114
    End_Tx_Init_D_to_C_point_test_req,            // d115
    End_Tx_Init_D_to_C_point_test_resp,           // d116
    Start_Tx_Init_D_to_C_eye_sweep_req,     // d117
    Start_Tx_Init_D_to_C_eye_sweep_resp,    // d118
    End_Tx_Init_D_to_C_eye_sweep_req,      // d119
    End_Tx_Init_D_to_C_eye_sweep_resp,     // d120

    // =========================
    // Rx Init D2C
    // =========================
    Start_Rx_Init_D_to_C_point_test_req,   // d121
    Start_Rx_Init_D_to_C_point_test_resp,  // d122
    Rx_Init_D_to_C_Tx_Count_Done_req,    // d123
    Rx_Init_D_to_C_Tx_Count_Done_resp,   // d124
    End_Rx_Init_D_to_C_point_test_req,      // d125
    End_Rx_Init_D_to_C_point_test_resp,     // d126
    Start_Rx_Init_D_to_C_eye_sweep_req,            // d127
    Start_Rx_Init_D_to_C_eye_sweep_resp,           // d128
    Rx_Init_D_to_C_results_req,     // d129
    Rx_Init_D_to_C_results_resp,    // d130
    End_Rx_Init_D_to_C_eye_sweep_req,      // d131
    End_Rx_Init_D_to_C_eye_sweep_resp,     // d132

    Rx_Init_D_to_C_sweep_done_with_results,

    NOTHING = 8'hff

  } msg_no_e;
endpackage
