`timescale 1ns/1ps

import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_active_state_tb();

    // ------------------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------------------
    logic lclk;
    logic rst_n;
    logic lp_linkerror;
    msg_no_e massage_recieve;
    logic stall_done;
    logic EN;
    RDI_state lp_state_req;
    logic timeout_1us;
    
    RDI_state next_state;
    logic stall_req;
    logic start_1us_timer;
    msg_no_e massage_send;

    // ------------------------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------------------------
    initial begin
        lclk = 0;
        forever #5 lclk = ~lclk; // 100MHz clock (10ns period)
    end

    // ------------------------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------------------------
    unit_active_state dut (
        .lclk(lclk),
        .rst_n(rst_n),
        .lp_linkerror(lp_linkerror),
        .massage_recieve(massage_recieve),
        .stall_done(stall_done),
        .EN(EN),
        .lp_state_req(lp_state_req),
        .timeout_1us(timeout_1us),
        
        .next_state(next_state),
        .stall_req(stall_req),
        .start_1us_timer(start_1us_timer),
        .massage_send(massage_send)
    );

    // ------------------------------------------------------------------------
    // Helper Task for Soft Reset
    // ------------------------------------------------------------------------
    task soft_reset();
        begin
            @(posedge lclk);
            EN = 0;
            @(posedge lclk);
            lp_state_req = Active;
            massage_recieve = NOP;
            lp_linkerror = 0;
            stall_done = 0;
            timeout_1us = 0;
            #10;
            EN = 1;
            @(posedge lclk);
        end
    endtask

    // ------------------------------------------------------------------------
    // Test Sequences
    // ------------------------------------------------------------------------
    initial begin
        // Initialize signals
        rst_n = 0;
        lp_linkerror = 0;
        massage_recieve = NOP;
        stall_done = 0;
        EN = 0;
        lp_state_req = Active;
        timeout_1us = 0;
        
        // Apply Reset
        #25 rst_n = 1;
        
        $display("\n========================================");
        $display("Starting unit_active_state Testbench");
        $display("========================================\n");
        
        // Enable State Machine
        @(posedge lclk);
        EN = 1;
        #10;

        // ====================================================================
        // SCENARIO GROUP: LINK ERROR
        // ====================================================================
        $display("--> Scenario 1: Link Error from Local Adapter (lp_linkerror)");
        @(posedge lclk);
        lp_linkerror = 1;
        @(negedge lclk);
        if (massage_send !== RDI_LINK_ERROR_REQ) $error("Expected RDI_LINK_ERROR_REQ");
        lp_linkerror = 0;
        
        // Respond as Peer
        @(posedge lclk);
        massage_recieve = RDI_LINK_ERROR_RSP;
        @(negedge lclk);
        if (next_state !== LinkError) $error("Expected next_state = LinkError");
        massage_recieve = NOP;
        
        soft_reset();

        $display("--> Scenario 2: Link Error from Peer");
        @(posedge lclk);
        massage_recieve = RDI_LINK_ERROR_REQ;
        @(negedge lclk);
        if (massage_send !== RDI_LINK_ERROR_RSP) $error("Expected RDI_LINK_ERROR_RSP");
        @(negedge lclk); // Verify the state transitions immediately
        if (next_state !== LinkError) $error("Expected next_state = LinkError");
        massage_recieve = NOP;
        
        soft_reset();


        // ====================================================================
        // SCENARIO GROUP: RETRAIN
        // ====================================================================
        $display("--> Scenario 3: Retrain from Local Adapter");
        @(posedge lclk);
        lp_state_req = Retrain;
        @(negedge lclk);
        if (stall_req !== 1'b1) $error("Expected stall_req = 1");
        
        @(posedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        if (massage_send !== RDI_RETRAIN_REQ) $error("Expected RDI_RETRAIN_REQ");
        
        @(posedge lclk);
        massage_recieve = RDI_RETRAIN_RSP;
        @(negedge lclk);
        if (next_state !== Retrain) $error("Expected next_state = Retrain");
        massage_recieve = NOP;

        soft_reset();


        $display("--> Scenario 4: Retrain from Peer");
        @(posedge lclk);
        massage_recieve = RDI_RETRAIN_REQ;
        @(negedge lclk);
        if (stall_req !== 1'b1) $error("Expected stall_req = 1");
        
        @(posedge lclk);
        stall_done = 1;
        massage_recieve = NOP;
        @(negedge lclk);
        stall_done = 0; 
        if (massage_send !== RDI_RETRAIN_RSP) $error("Expected RDI_RETRAIN_RSP");
        
        @(negedge lclk);
        if (next_state !== Retrain) $error("Expected next_state = Retrain");

        soft_reset();


        // ====================================================================
        // SCENARIO GROUP: LINK RESET
        // ====================================================================
        $display("--> Scenario 5: Link Reset from Local Adapter");
        @(posedge lclk);
        lp_state_req = LinkReset;
        
        @(posedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        if (massage_send !== RDI_LINK_RESET_REQ) $error("Expected RDI_LINK_RESET_REQ");
        
        @(posedge lclk);
        massage_recieve = RDI_LINK_RESET_RSP;
        @(negedge lclk);
        if (next_state !== LinkReset) $error("Expected next_state = LinkReset");
        massage_recieve = NOP;

        soft_reset();


        $display("--> Scenario 6: Link Reset from Peer");
        @(posedge lclk);
        massage_recieve = RDI_LINK_RESET_REQ;
        
        @(posedge lclk);
        stall_done = 1;
        massage_recieve = NOP;
        @(negedge lclk);
        stall_done = 0; 
        if (massage_send !== RDI_LINK_RESET_RSP) $error("Expected RDI_LINK_RESET_RSP");
        
        @(negedge lclk);
        if (next_state !== LinkReset) $error("Expected next_state = LinkReset");

        soft_reset();


        // ====================================================================
        // SCENARIO GROUP: DISABLE
        // ====================================================================
        $display("--> Scenario 7: Disable from Local Adapter");
        @(posedge lclk);
        lp_state_req = Disabled;
        
        @(posedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        if (massage_send !== RDI_DISABLE_REQ) $error("Expected RDI_DISABLE_REQ");
        
        @(posedge lclk);
        massage_recieve = RDI_DISABLE_RSP;
        @(negedge lclk);
        if (next_state !== Disabled) $error("Expected next_state = Disabled");
        massage_recieve = NOP;

        soft_reset();

        $display("--> Scenario 8: Disable from Peer");
        @(posedge lclk);
        massage_recieve = RDI_DISABLE_REQ;
        
        @(posedge lclk);
        stall_done = 1;
        massage_recieve = NOP;
        @(negedge lclk);
        stall_done = 0; 
        if (massage_send !== RDI_DISABLE_RSP) $error("Expected RDI_DISABLE_RSP");
        
        @(negedge lclk);
        if (next_state !== Disabled) $error("Expected next_state = Disabled");

        soft_reset();


        // ====================================================================
        // SCENARIO GROUP: L1 / L2 LOW POWER STATES
        // ====================================================================
        $display("--> Scenario 9: L1 Entry initiated by Peer (Success)");
        @(posedge lclk);
        massage_recieve = RDI_L1_REQ;
        
        @(negedge lclk);
        if (start_1us_timer !== 1'b1) $error("Expected start_1us_timer = 1 for Peer L1 req");
        massage_recieve = NOP;
        
        // Emulate Adapter confirming the L1 request before timeout
        @(posedge lclk);
        lp_state_req = L1;
        
        @(negedge lclk);
        if (stall_req !== 1'b1) $error("Expected stall_req = 1");
        
        @(posedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        if (massage_send !== RDI_L1_RSP) $error("Expected RDI_L1_RSP");
        
        @(posedge lclk);
        massage_recieve = RDI_L1_RSP;  // Peer sends final confirmation based on the flow design
        @(negedge lclk);
        if (next_state !== L1) $error("Expected next_state = L1");
        massage_recieve = NOP;

        soft_reset();

        $display("--> Scenario 10: L2 Entry initiated by Local Adapter (Success)");
        @(posedge lclk);
        lp_state_req = L2;
        
        @(posedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        if (massage_send !== RDI_L2_REQ) $error("Expected RDI_L2_REQ");
        
        @(posedge lclk);
        massage_recieve = RDI_L2_RSP; // Peer responses
        @(negedge lclk);
        // Design sends final Response and transitions
        if (massage_send !== RDI_L2_RSP) $error("Expected RDI_L2_RSP back (confirmation)");
        @(negedge lclk);
        if (next_state !== L2) $error("Expected next_state = L2");
        massage_recieve = NOP;

        soft_reset();

        $display("--> Scenario 11: L1 Entry initiated by Peer but TIMEOUT occurs (PM NAK)");
        @(posedge lclk);
        massage_recieve = RDI_L1_REQ;
        
        @(posedge lclk);
        massage_recieve = NOP;
        
        // Wait state de-asserts timer and waits for timeout_1us
        @(posedge lclk);
        timeout_1us = 1;

        // Verify PMNAK logic triggers
        @(negedge lclk);
        timeout_1us = 0;
        if (massage_send !== RDI_PMNAK_RSP) $error("Expected PM NAK Response upon timeout");

        // ====================================================================
        $display("\n========================================");
        $display("Testbench Finished Successfully!");
        $display("========================================\n");
        $stop;
    end

endmodule
