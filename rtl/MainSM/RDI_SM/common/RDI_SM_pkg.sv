package RDI_SM_pkg;
    typedef enum logic [3:0] {  Reset,
                                Active,
                                Active_PMNAK,
                                L1, 
                                L2,
                                LinkReset,
                                LinkError,
                                Retrain, 
                                Disabled, 
                                Nop
                                } RDI_state;
endpackage