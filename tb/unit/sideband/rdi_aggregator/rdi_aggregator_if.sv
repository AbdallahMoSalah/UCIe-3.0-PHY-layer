interface rdi_aggregator_if(input bit clk);

    logic rst_n;
    
    logic [31:0]  lp_cfg;      
    logic         lp_cfg_vld;  

    logic [127:0] lp_msg; 
    logic         lp_msg_vld; 

endinterface