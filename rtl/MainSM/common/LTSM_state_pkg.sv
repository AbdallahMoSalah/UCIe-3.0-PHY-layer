package LTSM_state_pkg;
    
    typedef enum logic [3:0] { RESET,
                                SBINIT,
                                MBINIT,
                                MBTRAIN,
                                LINKINIT,
                                ACTIVE,
                                PHYRETRAIN,
                                TRAINERROR,
                                L1,
                                L2 } LTSM_state_e;
endpackage