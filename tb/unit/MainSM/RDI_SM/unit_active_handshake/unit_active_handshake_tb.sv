`timescale 1ns / 1ps

import UCIe_pkg::*;

module unit_active_handshake_tb;

    // ===============
    // Signals
    // ===============
    logic    lclk;
    logic    rst_n;
    logic    pm_exit;
    logic    inband_pres;
    logic    active_handshake_strt;

    // DUT enum ports
    msg_no_e message_receive;
    msg_no_e active_message_send;

    // DUT output
    logic active_handshake_done;

    // ===============
    // DUT Instantiation
    // ===============
    unit_active_handshake uut (
        .rst_n                (rst_n),
        .inband_pres          (inband_pres),
        .lclk                 (lclk),
        .pm_exit              (pm_exit),
        .message_receive      (message_receive),
        .active_handshake_strt(active_handshake_strt),
        .active_message_send  (active_message_send),
        .active_handshake_done(active_handshake_done)
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
        active_handshake_strt = 1;
    endtask

    task end_handshake();
        @(negedge lclk);
        active_handshake_strt = 0;
    endtask

    task rcv_msg(input logic msg); // 0 for req, 1 for rsp
        @(negedge lclk);
        message_receive = msg ? RDI_ACTIVE_RSP : RDI_ACTIVE_REQ;
        @(negedge lclk);
        message_receive = NOP;  
    endtask

    // ===============
    // Test Sequence
    // ===============
    initial begin
        // Initialize inputs
        rst_n = 0;
        message_receive = NOP;
        pm_exit = 0;
        active_handshake_strt = 0;
        inband_pres = 0;
        
        // Wait for global reset / initialization
        #100;
        rst_n = 1;
        #10;

        // ---------------------------------------------------
        // Scenario 1: FLOW_2
        // ---------------------------------------------------
        $display("[%0t] Starting Scenario 1: FLOW_2", $time);
        start_handshake();
        fork 
            begin 
                inband_pres = 1;
                wait(active_message_send == RDI_ACTIVE_REQ);
                $display("[%0t] REQ sent", $time);
                rcv_msg(0);
            end 

            begin
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No req sent within 50 time units", $time);
            end 
        join_any
        disable fork;

        fork  begin
            wait(active_message_send == RDI_ACTIVE_RSP);
            $display("[%0t] RSP sent", $time);
            end

            begin
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No Rsp sent within 50 time units", $time);
            end 
        join_any; 
        disable fork;
                
        fork
            begin
                rcv_msg(1);
                wait(active_handshake_done == 1'b1);
                $display("[%0t] %s handshake done", $time, uut.flow.name());
                inband_pres = 0;
            end
            
            begin
                repeat (50) @(negedge lclk);
                $error("Error @ %0t : handshake didn't complete within 50 time units", $time);
            end 
        join_any; 
        disable fork; 
        
        @(negedge lclk);
        
        end_handshake();

        //---------------------------------------------------
        // Scenario 2: FLOW_0
        //---------------------------------------------------
        $display("[%0t] Starting Scenario 2: FLOW_0", $time);
        start_handshake();
        fork 
            begin 
                inband_pres = 1;
                wait(active_message_send == RDI_ACTIVE_REQ);
                $display("[%0t] REQ sent", $time);
                rcv_msg(1);
            end 
            begin 
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No req sent within 50 time units", $time);
            end
        join_any;
        disable fork;

        fork  begin
            rcv_msg(0);
            wait(active_message_send == RDI_ACTIVE_RSP);
            $display("[%0t] RSP sent", $time);
            end

            begin
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No Rsp sent within 50 time units", $time);
            end 
        join_any; 
        disable fork;
                
        fork
            begin
                wait(active_handshake_done == 1'b1);
                $display("[%0t] %s handshake done", $time, uut.flow.name());
                inband_pres = 0;
            end
            
            begin
                repeat (50) @(negedge lclk);
                $error("Error @ %0t : handshake didn't complete within 50 time units", $time);
            end 
        join_any; 
        disable fork; 
        
        @(negedge lclk);
        
        end_handshake();

        //---------------------------------------------------
        // Scenario 3: FLOW_1
        //---------------------------------------------------
        $display("[%0t] Starting Scenario 3: FLOW_1", $time);
        rcv_msg(0);
        start_handshake();
        fork 
            begin 
                inband_pres = 1;
                wait(active_message_send == RDI_ACTIVE_RSP);
                $display("[%0t] RSP sent", $time);
            end 
            begin 
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No rsp sent within 50 time units", $time);
            end
        join_any;
        disable fork;

        fork  begin
            wait(active_message_send == RDI_ACTIVE_REQ);
            $display("[%0t] REQ sent", $time);
            end

            begin
                repeat (50) @(negedge lclk);
                $error("Error @ %0t :No REQ sent within 50 time units", $time);
            end 
        join_any; 
        disable fork;
                
        fork
            begin
                rcv_msg(1);
                wait(active_handshake_done == 1'b1);
                $display("[%0t] %s handshake done", $time, uut.flow.name());
                inband_pres = 0;
            end
            
            begin
                repeat (50) @(negedge lclk);
                $error("Error @ %0t : handshake didn't complete within 50 time units", $time);
            end 
        join_any; 
        disable fork; 
        
        @(negedge lclk);
        
        end_handshake();
        $display("\n========================================");
        $display("TEST COMPLETED!");
        $display("========================================");

        $finish;
    end

endmodule
