package LTSM_state_pkg;
    
    typedef enum logic [3:0] {  RESET      = 4'd0,
                                SBINIT     = 4'd1,
                                MBINIT     = 4'd2,
                                MBTRAIN    = 4'd3,
                                LINKINIT   = 4'd4,
                                ACTIVE     = 4'd5,
                                PHYRETRAIN = 4'd6,
                                TRAINERROR = 4'd7,
                                L1         = 4'd8,
                                L2         = 4'd9,
                                NO_OP      = 4'd10 } LTSM_state_e;
endpackage