interface rdi_de_aggregator_if(input bit clk);

    logic rst_n;
    
    logic [127:0] pl_msg;      
    logic         pl_msg_vld;  
    logic         pl_msg_ready;

    logic [31:0]  pl_cfg; 
    logic         pl_cfg_vld; 
    logic         traffic_req;
    logic         traffic_ready;

endinterface
