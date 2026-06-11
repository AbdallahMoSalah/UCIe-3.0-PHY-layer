package ltsm_state_n_pkg;

    // from Page 500 in the UCIe_specification pdf file. (Table 9-59.)  (9.5.3.34 Error Log 0 (Offset 1080h))
    typedef enum logic [7:0] {
        LOG_RESET                    = 8'h00,
        LOG_SBINIT                   = 8'h01,
        LOG_MBINIT_PARAM             = 8'h02,
        LOG_MBINIT_CAL               = 8'h03,
        LOG_MBINIT_REPAIRCLK         = 8'h04,
        LOG_MBINIT_REPAIRVAL         = 8'h05,
        LOG_MBINIT_REVERSALMB        = 8'h06,
        LOG_MBINIT_REPAIRMB          = 8'h07,
        LOG_MBTRAIN_VALVREF          = 8'h08,
        LOG_MBTRAIN_DATAVREF         = 8'h09,
        LOG_MBTRAIN_SPEEDIDLE        = 8'h0A,
        LOG_MBTRAIN_TXSELFCAL        = 8'h0B,
        LOG_MBTRAIN_RXCLKCAL         = 8'h0C,
        LOG_MBTRAIN_VALTRAINCENTER   = 8'h0D,
        LOG_MBTRAIN_VALTRAINVREF     = 8'h0E,
        LOG_MBTRAIN_DATATRAINCENTER1 = 8'h0F,
        LOG_MBTRAIN_DATATRAINVREF    = 8'h10,
        LOG_MBTRAIN_RXDESKEW         = 8'h11,
        LOG_MBTRAIN_DATATRAINCENTER2 = 8'h12,
        LOG_MBTRAIN_LINKSPEED        = 8'h13,
        LOG_MBTRAIN_REPAIR           = 8'h14,
        LOG_PHYRETRAIN               = 8'h15,
        LOG_LINKINIT                 = 8'h16,
        LOG_ACTIVE                   = 8'h17,
        LOG_TRAINERROR               = 8'h18,
        LOG_L1_L2                    = 8'h19,
        LOG_L1                       = 8'h1A,
        LOG_L2                       = 8'h1B,
        LOG_NOP                      = 8'h1C
    } state_n_e;

    // // for current `ltsm_ctrl` state
    // typedef enum logic [3:0] {
    //     CTRL_RESET      = 4'd0,
    //     CTRL_SBINIT     = 4'd1,
    //     CTRL_MBINIT     = 4'd2,
    //     CTRL_MBTRAIN    = 4'd3,
    //     CTRL_LINKINIT   = 4'd4,
    //     CTRL_ACTIVE     = 4'd5,
    //     CTRL_PHYRETRAIN = 4'd6,
    //     CTRL_L1         = 4'd7,
    //     CTRL_L2         = 4'd8,
    //     CTRL_TRAINERROR = 4'd9,
    //     CTRL_NOP        = 4'd10
    // } ltsm_ctrl_state_e;

    // // for current `mbinit` sub-state
    // typedef enum logic [2:0] {
    //     MBINIT_IDLE       = 3'd0,
    //     PARAM             = 3'd1,
    //     CAL               = 3'd2,
    //     REPAIRCLK         = 3'd3,
    //     REPAIRVAL         = 3'd4,
    //     REVERSALMB        = 3'd5,
    //     REPAIRMB          = 3'd6,
    //     MBINIT_DONE       = 3'd7
    // } mbinit_substate_e;
endpackage
