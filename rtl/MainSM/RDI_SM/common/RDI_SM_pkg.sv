package RDI_SM_pkg;
    typedef enum logic [3:0] { Reset, 
                                Active, 
                                L1, 
                                L2, 
                                Retrain, 
                                LinkReset, 
                                Disabled, 
                                LinkError,
                                Nop
                                } RDI_state;
endpackage