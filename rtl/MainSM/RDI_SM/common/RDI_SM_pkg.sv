package RDI_SM_pkg;
    typedef enum logic [3:0] {  Reset,
                                Active,
                                Active_PMNAK,
                                L_1, 
                                L_2,
                                LinkReset,
                                LinkError,
                                Retrain, 
                                Disabled, 
                                Nop
                                } RDI_state;
endpackage
