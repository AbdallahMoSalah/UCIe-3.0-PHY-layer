module unit_status_decoder(
    input   [3:0] UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4,
            [3:0] UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7,
            [3:0] UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11,
            
    output  [2:0] pl_lnk_cfg, 
            [2:0] pl_speedmode, 
    output        pl_max_speedmode   
);
    
    assign pl_max_speedmode = (UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4 [2:0] > 4'h5);
    assign pl_lnk_cfg = UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7[2:0];
    assign pl_speedmode = UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11[2:0];

endmodule