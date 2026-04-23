`timescale 1ns/1ps

import UCIe_pkg::*;

module wrapper_handshake_logic_tb();

    // ===============
    // Signals
    // ===============
    logic lclk;
    
    // Inputs
    logic lp_clk_ack;
    logic clk_handshake_strt;
    
    logic lp_awak_req;
    logic ungating_done;
    
    logic lp_stallack;
    logic stall_req;

    logic Active_handshake_strt;
    msg_no_e message_receive;
    logic pm_exit;
    logic inband_pres;

    // Outputs
    logic pl_clk_req;
    logic clk_handshake_done;
    
    logic pl_awak_ack;
    logic ungating_req;
    
    logic pl_stallreq;
    logic stall_done;

    logic Active_handshake_done;
    msg_no_e Active_message_send;

    // ===============
    // DUT Instantiation
    // ===============
    wrapper_handshake_logic dut (
        .lclk(lclk),
        .pm_exit(pm_exit),
        
        .lp_clk_ack(lp_clk_ack),
        .clk_handshake_strt(clk_handshake_strt),
        
        .lp_awak_req(lp_awak_req),
        .ungating_done(ungating_done),
        
        .lp_stallack(lp_stallack),
        .stall_req(stall_req),
        
        .inband_pres(inband_pres),
        .Active_handshake_strt(Active_handshake_strt),
        .message_receive(message_receive),
        
        .pl_clk_req(pl_clk_req),
        .clk_handshake_done(clk_handshake_done),
        .pl_awak_ack(pl_awak_ack),
        .ungating_req(ungating_req),
        .pl_stallreq(pl_stallreq),
        .stall_done(stall_done),
        .Active_handshake_done(Active_handshake_done),
        .Active_message_send(Active_message_send)
    );

    // ===============
    // Clock Generation
    // ===============
    initial begin
        lclk = 0;
        forever #5 lclk = ~lclk;
    end

    task start_handshake();
        @(negedge lclk);
        Active_handshake_strt = 1;
    endtask

    task end_handshake();
        @(negedge lclk);
        Active_handshake_strt = 0;
    endtask

    task rcv_msg(input logic msg); //0 for req, 1 for rsp
        @(negedge lclk);
        message_receive = msg ? RDI_ACTIVE_RSP : RDI_ACTIVE_REQ;
        @(negedge lclk);
        message_receive = NOP;  
    endtask

    // ===============
    // Test Sequence
    // ===============
    initial begin
        $display("========================================");
        $display("Starting wrapper_handshake_logic Testbench");
        $display("========================================");

        // Initialize inputs
        lp_clk_ack = 0;
        clk_handshake_strt = 0;
        lp_awak_req = 0;
        ungating_done = 0;
        lp_stallack = 0;
        stall_req = 0;
        Active_handshake_strt = 0;
        message_receive = NOP;
        pm_exit = 0;
        inband_pres=0;
        // Let system settle
        repeat(2) @(posedge lclk);
        
        $display("\n--- Test 1: CLK Handshake ---");
        @(negedge lclk);
        clk_handshake_strt = 1;
        wait(pl_clk_req);
        @(negedge lclk);
        lp_clk_ack = 1;
        wait(clk_handshake_done);
        @(negedge lclk);
        clk_handshake_strt = 0;
        lp_clk_ack = 0;
        $display("CLK Handshake Done");

        $display("\n--- Test 2: AWAKE Handshake ---");
        @(negedge lclk);
        lp_awak_req = 1;
        wait(ungating_req);
        @(negedge lclk);
        ungating_done = 1;
        wait(pl_awak_ack);
        @(negedge lclk);
        lp_awak_req = 0;
        ungating_done = 0;
        $display("AWAKE Handshake Done");

        $display("\n--- Test 3: STALL Handshake ---");
        @(negedge lclk);
        stall_req = 1;
        wait(pl_stallreq);
        @(negedge lclk);
        lp_stallack = 1;
        wait(stall_done);
        @(negedge lclk);
        stall_req = 0;
        wait(!stall_done);
        @(negedge lclk);
        lp_stallack = 0;
        $display("STALL Handshake Done");

        $display("\n--- Test 4: Active Handshake ---");
        // ---------------------------------------------------
        // Scenario 1: flow2
        // ---------------------------------------------------
        $display("[%0t] Starting Scenario 1: flow2", $time);
        start_handshake();
        fork 
            begin 
                inband_pres = 1;
                wait(Active_message_send == RDI_ACTIVE_REQ);
                $display("[%0t] REQ sent", $time);
                rcv_msg(0);
            end 

            begin
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No req sent within 50 time units",$time);
            end 
        join_any
        disable fork;

        fork  begin
            wait(Active_message_send == RDI_ACTIVE_RSP);
            $display("[%0t] RSP sent", $time);
            end

            begin
                repeat(50) @(negedge lclk);
                $error("Error @ %0t :No Rsp sent within 50 time units",$time);
            end 
        join_any; 
        disable fork;
                
        fork
            begin
                rcv_msg(1);
                wait(Active_handshake_done == 1'b1);
                $display("[%0t] %s handshake done", $time, dut.u4.flow.name());
                inband_pres=0;
            end
            
            begin
                repeat(50) @(negedge lclk);
                $error("Error @ %0t : handshake didn't complete within 50 time units", $time);
            end 
        join_any; 
        disable fork; 
        
        @(negedge lclk);
        
        end_handshake();

       //---------------------------------------------------
       //scenario 2: flow 0
       //---------------------------------------------------
        $display("[%0t] Starting Scenario 2: flow0", $time);
        start_handshake();
        fork 
            begin 
                inband_pres = 1;
                wait(Active_message_send == RDI_ACTIVE_REQ);
                $display("[%0t] REQ sent", $time);
                rcv_msg(1);
            end 
            begin 
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No req sent within 50 time units",$time);
            end
        join_any;
        disable fork;

        fork  begin
            rcv_msg(0);
            wait(Active_message_send == RDI_ACTIVE_RSP);
            $display("[%0t] RSP sent", $time);
            end

            begin
                repeat(50) @(negedge lclk);
                $error("Error @ %0t :No Rsp sent within 50 time units",$time);
            end 
        join_any; 
        disable fork;
                
        fork
            begin
                wait(Active_handshake_done == 1'b1);
                $display("[%0t] %s handshake done", $time, dut.u4.flow.name());
                inband_pres=0;
            end
            
            begin
                repeat(50) @(negedge lclk);
                $error("Error @ %0t : handshake didn't complete within 50 time units", $time);
            end 
        join_any; 
        disable fork; 
        
        @(negedge lclk);
        
        end_handshake();
       //---------------------------------------------------
       //scenario 3: flow 1
       //---------------------------------------------------
        $display("[%0t] Starting Scenario 3: flow1", $time);
        rcv_msg(0);
        start_handshake();
        fork 
            begin 
                inband_pres = 1;
                wait(Active_message_send == RDI_ACTIVE_RSP);
                $display("[%0t] RSP sent", $time);
            end 
            begin 
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No rsp sent within 50 time units",$time);
            end
        join_any;
        disable fork;

        fork  begin
            wait(Active_message_send == RDI_ACTIVE_REQ);
            $display("[%0t] REQ sent", $time);
            end

            begin
                repeat(50) @(negedge lclk);
                $error("Error @ %0t :No REQ sent within 50 time units",$time);
            end 
        join_any; 
        disable fork;
                
        fork
            begin
                rcv_msg(1);
                wait(Active_handshake_done == 1'b1);
                $display("[%0t] %s handshake done", $time, dut.u4.flow.name());
                inband_pres=0;
            end
            
            begin
                repeat(50) @(negedge lclk);
                $error("Error @ %0t : handshake didn't complete within 50 time units", $time);
            end 
        join_any; 
        disable fork; 
        
        @(negedge lclk);
        
        end_handshake();
 
    $display("\n========================================");
    $display("TEST COMPLETED!");
    $display("========================================");

        $stop;
    end

endmodule
