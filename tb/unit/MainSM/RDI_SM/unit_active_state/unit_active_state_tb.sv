`timescale 1ns/1ps

import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module unit_active_state_tb();

    // ------------------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------------------
    logic           lclk;
    logic           rst_n;
    logic           en;
    logic           stall_done;
    logic           timeout_1us;
    logic           lp_linkerror;
    logic           pl_error;
    RDI_state       lp_state_req;
    LTSM_state_e    state_sts;
    msg_no_e        message_receive;
    
    RDI_state       next_state;
    logic           stall_req;
    logic           start_1us_timer;
    msg_no_e        message_send;

    int errors = 0;
    int successes = 0;

    `define CHECK(cond, msg) \
        if (cond) begin \
            $error(msg); \
            errors++; \
        end else begin \
            successes++; \
        end

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
        .en(en),
        .stall_done(stall_done),
        .timeout_1us(timeout_1us),
        .lp_linkerror(lp_linkerror),
        .pl_error(pl_error),
        .lp_state_req(lp_state_req),
        .state_sts(state_sts),
        .message_receive(message_receive),
        
        .next_state(next_state),
        .stall_req(stall_req),
        .start_1us_timer(start_1us_timer),
        .message_send(message_send)
    );

    // ------------------------------------------------------------------------
    // Helper Task for Soft Reset
    // ------------------------------------------------------------------------
    task soft_reset();
        begin
            @(negedge lclk);
            en = 0;
            @(negedge lclk);
            lp_state_req = Active;
            message_receive = NOP;
            lp_linkerror = 0;
            pl_error = 0;
            state_sts = NO_OP;
            stall_done = 0;
            timeout_1us = 0;
            #10;
            en = 1;
            @(negedge lclk);
        end
    endtask

    // ------------------------------------------------------------------------
    // Test Sequences
    // ------------------------------------------------------------------------
    initial begin
        // Initialize signals
        rst_n = 0;
        lp_linkerror = 0;
        pl_error = 0;
        message_receive = NOP;
        stall_done = 0;
        en = 0;
        lp_state_req = Active;
        state_sts = NO_OP;
        timeout_1us = 0;
        
        // Apply Reset
        #25 rst_n = 1;
        
        $display("\n========================================");
        $display("Starting unit_active_state Testbench");
        $display("========================================\n");
        
        // Enable State Machine
        @(negedge lclk);
        en = 1;
        #10;

        // ====================================================================
        // SCENARIO GROUP: LINK ERROR
        // ====================================================================
        $display("--> Scenario 1: Link Error from Local Adapter (lp_linkerror)");
        @(negedge lclk);
        lp_linkerror = 1;
        @(negedge lclk);
        `CHECK(message_send !== RDI_LINK_ERROR_REQ, "Expected RDI_LINK_ERROR_REQ")
        lp_linkerror = 0;
        
        // Respond as Peer
        @(negedge lclk);
        message_receive = RDI_LINK_ERROR_RSP;
        @(negedge lclk);
        `CHECK(next_state !== LinkError, "Expected next_state = LinkError")
        message_receive = NOP;
        
        soft_reset();

        $display("--> Scenario 2: Link Error from Peer");
        @(negedge lclk);
        message_receive = RDI_LINK_ERROR_REQ;
        @(negedge lclk);
        `CHECK(message_send !== RDI_LINK_ERROR_RSP, "Expected RDI_LINK_ERROR_RSP")
        @(negedge lclk); // Verify the state transitions immediately
        `CHECK(next_state !== LinkError, "Expected next_state = LinkError")
        message_receive = NOP;
        
        soft_reset();


        // ====================================================================
        // SCENARIO GROUP: RETRAIN
        // ====================================================================
        $display("--> Scenario 3: Retrain from Local Adapter");
        @(negedge lclk);
        lp_state_req = Retrain;
        @(negedge lclk);
        `CHECK(stall_req !== 1'b1, "Expected stall_req = 1")
        
        @(negedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        `CHECK(message_send !== RDI_RETRAIN_REQ, "Expected RDI_RETRAIN_REQ")
        
        @(negedge lclk);
        message_receive = RDI_RETRAIN_RSP;
        @(negedge lclk);
        `CHECK(next_state !== Retrain, "Expected next_state = Retrain")
        message_receive = NOP;

        soft_reset();


        $display("--> Scenario 4: Retrain from Peer");
        @(negedge lclk);
        message_receive = RDI_RETRAIN_REQ;
        @(negedge lclk);
        `CHECK(stall_req !== 1'b1, "Expected stall_req = 1")
        
        @(negedge lclk);
        stall_done = 1;
        message_receive = NOP;
        @(negedge lclk);
        stall_done = 0; 
        `CHECK(message_send !== RDI_RETRAIN_RSP, "Expected RDI_RETRAIN_RSP")
        
        @(negedge lclk);
        `CHECK(next_state !== Retrain, "Expected next_state = Retrain")

        soft_reset();


        // ====================================================================
        // SCENARIO GROUP: LINK RESET
        // ====================================================================
        $display("--> Scenario 5: Link Reset from Local Adapter");
        @(negedge lclk);
        lp_state_req = LinkReset;
        
        @(negedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        `CHECK(message_send !== RDI_LINK_RESET_REQ, "Expected RDI_LINK_RESET_REQ")
        
        @(negedge lclk);
        message_receive = RDI_LINK_RESET_RSP;
        @(negedge lclk);
        `CHECK(next_state !== LinkReset, "Expected next_state = LinkReset")
        message_receive = NOP;

        soft_reset();


        $display("--> Scenario 6: Link Reset from Peer");
        @(negedge lclk);
        message_receive = RDI_LINK_RESET_REQ;
        
        @(negedge lclk);
        stall_done = 1;
        message_receive = NOP;
        @(negedge lclk);
        stall_done = 0; 
        `CHECK(message_send !== RDI_LINK_RESET_RSP, "Expected RDI_LINK_RESET_RSP")
        
        @(negedge lclk);
        `CHECK(next_state !== LinkReset, "Expected next_state = LinkReset")

        soft_reset();


        // ====================================================================
        // SCENARIO GROUP: DISABLE
        // ====================================================================
        $display("--> Scenario 7: Disable from Local Adapter");
        @(negedge lclk);
        lp_state_req = Disabled;
        
        @(negedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        `CHECK(message_send !== RDI_DISABLE_REQ, "Expected RDI_DISABLE_REQ")
        
        @(negedge lclk);
        message_receive = RDI_DISABLE_RSP;
        @(negedge lclk);
        `CHECK(next_state !== Disabled, "Expected next_state = Disabled")
        message_receive = NOP;

        soft_reset();

        $display("--> Scenario 8: Disable from Peer");
        @(negedge lclk);
        message_receive = RDI_DISABLE_REQ;
        
        @(negedge lclk);
        stall_done = 1;
        message_receive = NOP;
        @(negedge lclk);
        stall_done = 0; 
        `CHECK(message_send !== RDI_DISABLE_RSP, "Expected RDI_DISABLE_RSP")
        
        @(negedge lclk);
        `CHECK(next_state !== Disabled, "Expected next_state = Disabled")

        soft_reset();


        // ====================================================================
        // SCENARIO GROUP: L1 / L2 LOW POWER STATES
        // ====================================================================
        $display("--> Scenario 9: L1 Entry initiated by Peer (Success)");
        @(negedge lclk);
        message_receive = RDI_L1_REQ;
        
        @(negedge lclk);
        `CHECK(start_1us_timer !== 1'b1, "Expected start_1us_timer = 1 for Peer L1 req")
        message_receive = NOP;
        
        // Emulate Adapter confirming the L1 request before timeout
        @(negedge lclk);
        lp_state_req = L_1;
        
        @(negedge lclk);
        `CHECK(stall_req !== 1'b1, "Expected stall_req = 1")
        
        @(negedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 
        @(negedge lclk);
        `CHECK(message_send !== RDI_L1_RSP, "Expected RDI_L1_RSP")
        
        @(negedge lclk);
        message_receive = RDI_L1_RSP;  // Peer sends final confirmation based on the flow design
        @(negedge lclk);
        `CHECK(next_state !== L_1, "Expected next_state = L_1")
        message_receive = NOP;

        soft_reset();

        $display("--> Scenario 10: L2 Entry initiated by Local Adapter (Success)");
        @(negedge lclk);
        lp_state_req = L_2;
        
        @(negedge lclk);
        stall_done = 1;
        lp_state_req = Active;
        @(negedge lclk);
        stall_done = 0; 

        // 1. send req
        `CHECK(message_send !== RDI_L2_REQ, "Expected RDI_L2_REQ")
        
        // 2. receive req
        @(negedge lclk);
        message_receive = RDI_L2_REQ; 
        
        // 3. receive resp
        @(negedge lclk);
        message_receive = RDI_L2_RSP;
        
        // 4. send resp
        @(negedge lclk);
        `CHECK(message_send !== RDI_L2_RSP, "Expected RDI_L2_RSP back (confirmation)")
        
        @(negedge lclk);
        `CHECK(next_state !== L_2, "Expected next_state = L_2")
        message_receive = NOP;

        soft_reset();

        $display("--> Scenario 11: L1 Entry initiated by Peer but TIMEOUT occurs (PM NAK)");
        @(negedge lclk);
        message_receive = RDI_L1_REQ;
        
        @(negedge lclk);
        message_receive = NOP;
        
        // Wait state de-asserts timer and waits for timeout_1us
        @(negedge lclk);
        timeout_1us = 1;

        // Verify PMNAK logic triggers
        @(negedge lclk);
        timeout_1us = 0;
        `CHECK(message_send !== RDI_PMNAK_RSP, "Expected PM NAK Response upon timeout")

        // ====================================================================
        $display("\n========================================");
        $display("Testbench Finished!");
        $display("Total Errors : %0d", errors);
        $display("Total Success: %0d", successes);
        $display("========================================\n");
        $stop;
    end

endmodule
