module Link_Controller_tb();

import Link_Controller_tb_pkg::*;

// Clock Generation
bit clk;
initial begin
    clk = 0;
    forever #5 clk = ~clk;  
end
assign vif.mapper_rdy = dut.u_sb_mapper.mapper_rdy;
// Interface Instantiation
Link_controller_if vif(clk);

//=====================================//
///////////////////DUT///////////////////
//=====================================//

Link_Controller dut(
    .clk               ( vif.clk               ),
    .rst_n             ( vif.rst_n             ),
    .trn_msg_send     ( vif.trn_msg_send     ),
    .trn_vld_send     ( vif.trn_vld_send     ),
    .adapter_msg_send  ( vif.adapter_msg_send  ),
    .adapter_vld_send  ( vif.adapter_vld_send  ),
    .ser_rdy         ( vif.ser_rdy         ),
    
    .pattern_mode      ( vif.pattern_mode      ),
    .start_pat_req     ( vif.start_pat_req     ),
    .req_iter_count    ( vif.req_iter_count    ),
    
    .iter_done         ( vif.iter_done         ),
    
    .ser_data_send     ( vif.ser_data_send     ),
    .ser_vld_send      ( vif.ser_vld_send      ),
    
    .adapter_rdy     ( vif.adapter_rdy     ),
    .trn_rdy        ( vif.trn_rdy        ),

    .det_pat_rcvd      ( vif.det_pat_rcvd      ),

    .des_data_rcvd     ( vif.des_data_rcvd     ),
    .des_vld_rcvd      ( vif.des_vld_rcvd      ),

    .adapter_msg_rcvd  ( vif.adapter_msg_rcvd  ),
    .adapter_vld_rcvd  ( vif.adapter_vld_rcvd  ),
    .trn_msg_rcvd     ( vif.trn_msg_rcvd     ),
    .trn_vld_rcvd   ( vif.trn_vld_rcvd   )
);


//=====================================//
/////////////Test Execution//////////////
//=====================================//

link_controller_tx_driver tx_drv;
link_controller_rx_driver rx_drv;
link_controller_monitor mon;
link_controller_scoreboard sb;

initial begin
    
    $display("==================================================");
    $display("====== Starting Link_Controller Testbench ========");
    $display("==================================================");

    tx_drv = new(vif);
    rx_drv = new(vif);
    mon = new(vif);
    sb = new(mon);

    
    
    // ----------------------------------------------------
    // Reset Phase
    // ----------------------------------------------------
    $display("[%0t] Applying Reset...", $time);
    vif.rst_n = 0;
    vif.pattern_mode = 0;
    vif.start_pat_req = 0;
    vif.req_iter_count = 3'd0;
    vif.ser_rdy = 1;
    vif.trn_msg_send = 0;
    vif.trn_vld_send = 0;
    vif.adapter_msg_send = 0;
    vif.adapter_vld_send = 0;
    vif.des_data_rcvd = 0;
    vif.des_vld_rcvd = 0;
    
    
    #20;
    vif.rst_n = 1;

    // ----------------------------------------------------
    // Directed Pattern Tests
    // ----------------------------------------------------
    $display("[%0t] Running Directed Pattern Test...", $time);
    vif.pattern_mode = 1;
    vif.start_pat_req = 1;
    #10;
    vif.start_pat_req = 0;
    
    vif.req_iter_count = 3'd4;
    #10;
    vif.req_iter_count = 3'd0;
    
    #500;
    vif.pattern_mode = 0; // Ensure it goes back to 0
    fork
        tx_drv.run();
        rx_drv.run();
        mon.run();
        sb.run();
    join_none
    // ----------------------------------------------------
    // Random Tests Simulation
    // ----------------------------------------------------
    $display("[%0t] Running Random Transactions...", $time);
    repeat(1000) @(posedge clk);
    
    $display("==================================================");
    $display("====== Link_Controller Testbench Finished ========");
    $display("======    Matches (TX: %0d / RX: %0d)     ========", sb.tx_pass, sb.rx_pass);
    $display("====== Mismatches (TX: %0d / RX: %0d)     ========", sb.tx_fail, sb.rx_fail);
    $display("==================================================");
    
    $stop;
end  

endmodule