module Link_Controller_tb();

import Link_Controller_tb_pkg::*;

// Clock Generation
bit clk;
initial begin
    clk = 0;
    forever #5 clk = ~clk;  
end

// Interface Instantiation
Link_controller_if vif(clk);

//=====================================//
///////////////////DUT///////////////////
//=====================================//

Link_Controller dut(
    .clk               ( vif.clk               ),
    .rst_n             ( vif.rst_n             ),
    .Link_msg_send     ( vif.Link_msg_send     ),
    .Link_vld_send     ( vif.Link_vld_send     ),
    .Adapter_msg_send  ( vif.Adapter_msg_send  ),
    .Adapter_vld_send  ( vif.Adapter_vld_send  ),
    .ser_ready         ( vif.ser_ready         ),
    
    .pattern_mode      ( vif.pattern_mode      ),
    .start_pat_req     ( vif.start_pat_req     ),
    .send_4_iter       ( vif.send_4_iter       ),
    
    .four_iter_done    ( vif.four_iter_done    ),
    
    .ser_data_send     ( vif.ser_data_send     ),
    .ser_vld_send      ( vif.ser_vld_send      ),
    
    .Adapter_ready     ( vif.Adapter_ready     ),
    .Link_ready        ( vif.Link_ready        ),

    .det_pat_rcvd      ( vif.det_pat_rcvd      ),

    .des_data_rcvd     ( vif.des_data_rcvd     ),
    .des_vld_rcvd      ( vif.des_vld_rcvd      ),

    .Adapter_msg_rcvd  ( vif.Adapter_msg_rcvd  ),
    .Adapter_vld_rcvd  ( vif.Adapter_vld_rcvd  ),
    .LINK_msg_rcvd     ( vif.LINK_msg_rcvd     ),
    .Link_valid_rcvd   ( vif.Link_valid_rcvd   )
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

    fork
        tx_drv.run();
        rx_drv.run();
        mon.run();
        sb.run();
    join_none
    
    // ----------------------------------------------------
    // Reset Phase
    // ----------------------------------------------------
    $display("[%0t] Applying Reset...", $time);
    vif.rst_n = 0;
    vif.pattern_mode = 0;
    vif.start_pat_req = 0;
    vif.send_4_iter = 0;
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
    
    vif.send_4_iter = 1;
    #10;
    vif.send_4_iter = 0;
    
    #500;
    vif.pattern_mode = 0; // Ensure it goes back to 0

    // ----------------------------------------------------
    // Random Tests Simulation
    // ----------------------------------------------------
    $display("[%0t] Running Random Transactions...", $time);
    #1000;
    
    $display("==================================================");
    $display("====== Link_Controller Testbench Finished ========");
    $display("======    Matches (TX: %0d / RX: %0d)     ========", sb.tx_pass, sb.rx_pass);
    $display("====== Mismatches (TX: %0d / RX: %0d)     ========", sb.tx_fail, sb.rx_fail);
    $display("==================================================");
    
    $finish;
end  

endmodule