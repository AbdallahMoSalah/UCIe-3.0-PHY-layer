package ltsm_state_n_pkg;

    // from Page 500 in the UCIe_specification pdf file. (Table 9-59.)  (9.5.3.34 Error Log 0 (Offset 1080h))
    typedef enum logic [4:0] {
        RESET                    = 5'h00,
        SBINIT                   = 5'h01,
        MBINIT_PARAM             = 5'h02,
        MBINIT_CAL               = 5'h03,
        MBINIT_REPAIRCLK         = 5'h04,
        MBINIT_REPAIRVAL         = 5'h05,
        MBINIT_REVERSALMB        = 5'h06,
        MBINIT_REPAIRMB          = 5'h07,
        MBTRAIN_VALVREF          = 5'h08,
        MBTRAIN_DATAVREF         = 5'h09,
        MBTRAIN_SPEEDIDLE        = 5'h0A,
        MBTRAIN_TXSELFCAL        = 5'h0B,
        MBTRAIN_RXSELFCAL        = 5'h0C,
        MBTRAIN_VALTRAINCENTER   = 5'h0D,
        MBTRAIN_VALTRAINVREF     = 5'h0E,
        MBTRAIN_DATATRAINCENTER1 = 5'h0F,
        MBTRAIN_DATATRAINVREF    = 5'h10,
        MBTRAIN_RXDESKEW         = 5'h11,
        MBTRAIN_DATATRAINCENTER2 = 5'h12,
        MBTRAIN_LINKSPEED        = 5'h13,
        MBTRAIN_REPAIR           = 5'h14,
        PHYRETRAIN               = 5'h15,
        LINKINIT                 = 5'h16,
        ACTIVE                   = 5'h17,
        TRAINERROR               = 5'h18,
        L1_L2                    = 5'h19
    } state_n_e;

    // for current `ltsm_ctrl` state
    typedef enum logic [3:0] {
        CTRL_RESET      = 4'd0,
        CTRL_SBINIT     = 4'd1,
        CTRL_MBINIT     = 4'd2,
        CTRL_MBTRAIN    = 4'd3,
        CTRL_LINKINIT   = 4'd4,
        CTRL_ACTIVE     = 4'd5,
        CTRL_PHYRETRAIN = 4'd6,
        CTRL_L1_L2      = 4'd7,
        CTRL_TRAINERROR = 4'd8
    } ltsm_ctrl_state_e;

    // for current `mbinit` sub-state
    typedef enum logic [2:0] {
        MBINIT_IDLE       = 3'd0,
        PARAM             = 3'd1,
        CAL               = 3'd2,
        REPAIRCLK         = 3'd3,
        REPAIRVAL         = 3'd4,
        REVERSALMB        = 3'd5,
        REPAIRMB          = 3'd6,
        MBINIT_DONE       = 3'd7
    } mbinit_substate_e;

    // for current `mbtrain` sub-state
    typedef enum logic [3:0] {
        MBTRAIN_IDLE       = 4'd0,
        VALVREF            = 4'd1,
        DATAVREF           = 4'd2,
        SPEEDIDLE          = 4'd3,
        TXSELFCAL          = 4'd4,
        RXSELFCAL          = 4'd5,
        VALTRAINCENTER     = 4'd6,
        VALTRAINVREF       = 4'd7,
        DATATRAINCENTER1   = 4'd8,
        DATATRAINVREF      = 4'd9,
        RXDESKEW           = 4'd10,
        DATATRAINCENTER2   = 4'd11,
        LINKSPEED          = 4'd12,
        REPAIR             = 4'd13,
        MBTRAIN_DONE       = 4'd14
    } mbtrain_substate_e;
endpackage