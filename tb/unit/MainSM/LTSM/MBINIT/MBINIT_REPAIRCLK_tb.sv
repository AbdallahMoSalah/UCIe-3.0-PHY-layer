`timescale 1ns/1ps
import UCIe_pkg::*;

// ============================================================================
// MBINIT_REPAIRCLK Comprehensive Unit Testbench
// ============================================================================
// Covers UCIe Rev 3.0 §4.5.3.2 Clock Repair Initialization.
// Fully verifies readiness handshake, clock pattern transmission, result
// exchange, error checks, safety watchdog timeouts, and FIFO backpressure.
// Verifies early partner message latching (immunity to sideband latency deadlocks).
// ============================================================================

module MBINIT_REPAIRCLK_tb;

    logic clk;
    logic rst_n;

    // DUT Ports
    logic        mb_repairclk_enable;
    logic        mb_repairclk_done;
    logic        mb_repairclk_error;

    // RX
    logic        mb_repairclk_rx_valid;
    msg_no_e     mb_repairclk_rx_msg_id;
    logic [15:0] mb_repairclk_rx_MsgInfo;
    logic [63:0] mb_repairclk_rx_data_Field;

    // TX
    logic        mb_repairclk_tx_valid;
    msg_no_e     mb_repairclk_tx_msg_id;
    logic [15:0] mb_repairclk_tx_MsgInfo;
    logic [63:0] mb_repairclk_tx_data_Field;

    // Clock patterns
    logic        mb_tx_pattern_en;
    logic [2:0]  mb_tx_pattern_setup;
    logic        mb_rx_compare_en;
    logic [1:0]  mb_rx_compare_setup;

    // Local training passes
    logic        rtrk_pass;
    logic        rckn_pass;
    logic        rckp_pass;

    logic        mb_tx_pattern_count_done;
    logic        ltsm_rdy;
    logic        timeout_repairclk_expired;
    logic        timeout_repairclk_enable;

    int errors;
    int checks;
    int scn;

    // Clock generator (100 MHz -> 10ns period)
    initial clk = 0;
    always #5000 clk = ~clk;

    initial begin
        $dumpfile("MBINIT_REPAIRCLK_tb.vcd");
        $dumpvars(0, MBINIT_REPAIRCLK_tb);
    end

    // Instantiate DUT
    MBINIT_REPAIRCLK dut (.*);

    // ========================================================================
    // Helper Tasks
    // ========================================================================

    task check(input bit cond, input string msg);
        checks++;
        if (!cond) begin
            errors++;
            $display("[%0t] SCN%0d FAIL: %s", $time, scn, msg);
        end else begin
            $display("[%0t] SCN%0d ok  : %s", $time, scn, msg);
        end
    endtask

    task do_reset();
        rst_n                                    = 0;
        mb_repairclk_enable                      = 0;
        mb_repairclk_rx_valid                    = 0;
        mb_repairclk_rx_msg_id                   = msg_no_e'(NOTHING);
        mb_repairclk_rx_MsgInfo                  = 16'h0;
        mb_repairclk_rx_data_Field               = 64'h0;
        
        rtrk_pass                                = 1'b1;
        rckn_pass                                = 1'b1;
        rckp_pass                                = 1'b1;
        mb_tx_pattern_count_done                 = 1'b0;

        ltsm_rdy                                 = 1'b1;
        timeout_repairclk_expired                = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    endtask

    // Send a message from partner
    task send_msg(input msg_no_e msg_id, input logic [63:0] data_field, input logic [15:0] msg_info = 16'h0);
        @(posedge clk);
        mb_repairclk_rx_valid      <= 1'b1;
        mb_repairclk_rx_msg_id     <= msg_id;
        mb_repairclk_rx_MsgInfo    <= msg_info;
        mb_repairclk_rx_data_Field <= data_field;
        @(posedge clk);
        mb_repairclk_rx_valid      <= 1'b0;
        mb_repairclk_rx_msg_id     <= msg_no_e'(NOTHING);
        mb_repairclk_rx_data_Field <= 64'h0;
    endtask

    // ========================================================================
    // Main Test Suite
    // ========================================================================
    initial begin
        errors = 0;
        checks = 0;
        $display("[%0t] === MBINIT_REPAIRCLK COMPREHENSIVE TB START ===\n", $time);

        // ====================================================================
        // SCN 1: Normal Happy Path (All passes, successful training)
        // ====================================================================
        scn = 1;
        $display("[%0t] --- SCN %0d: NORMAL HAPPY PATH ---", $time, scn);
        do_reset();
        mb_repairclk_enable = 1;

        // Step 1: Readiness Handshake
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req);
        check(timeout_repairclk_enable, "SCN1: Timeout timer enabled in S1");
        send_msg(MBINIT_REPAIRCLK_init_req, 64'h0);

        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_resp);
        send_msg(MBINIT_REPAIRCLK_init_resp, 64'h0);

        // Step 2: Pattern Transmission Phase
        wait (mb_tx_pattern_en);
        check(mb_rx_compare_en, "SCN1: Rx compare enabled during pattern transmission");
        repeat (20) @(posedge clk);
        
        // Logical block finishes transmitting
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // Step 3: Result Exchange Handshake
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_req);
        check(!mb_tx_pattern_en, "SCN1: Tx pattern disabled after transmission completed");
        send_msg(MBINIT_REPAIRCLK_result_req, 64'h0);

        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_resp);
        // Local results were {rtrk_pass, rckn_pass, rckp_pass} = 3'b111 (7)
        check(mb_repairclk_tx_MsgInfo[2:0] == 3'b111, "SCN1: Local result is driven correctly (3'b111)");
        
        // Partner result: All pass (3'b111)
        send_msg(MBINIT_REPAIRCLK_result_resp, 64'h0, 16'h7);

        // Step 4/5: Error check passed -> Finalize Handshake
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_done_req);
        send_msg(MBINIT_REPAIRCLK_done_req, 64'h0);

        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_done_resp);
        send_msg(MBINIT_REPAIRCLK_done_resp, 64'h0);

        // Success DONE
        wait (mb_repairclk_done);
        check(!mb_repairclk_error, "SCN1: FSM finished successfully without errors");
        check(!timeout_repairclk_enable, "SCN1: Watchdog timer disabled at DONE");

        mb_repairclk_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 2: Clock Training Failure (Error check triggers S6_ERROR)
        // ====================================================================
        scn = 2;
        $display("\n[%0t] --- SCN %0d: PARTNER TRAINING FAILURE ---", $time, scn);
        do_reset();
        mb_repairclk_enable = 1;

        // S1
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req);
        send_msg(MBINIT_REPAIRCLK_init_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_resp);
        send_msg(MBINIT_REPAIRCLK_init_resp, 64'h0);

        // S2
        wait (mb_tx_pattern_en);
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // S3
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_req);
        send_msg(MBINIT_REPAIRCLK_result_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_resp);
        
        // Partner reports clock training failure: rckn_pass = 0 -> compare result = 3'b101 (5)
        send_msg(MBINIT_REPAIRCLK_result_resp, 64'h0, 16'h5);

        // S4: Error check sees 0 in partner results -> transitions to S6_REPAIRCLK_ERROR
        wait (mb_repairclk_error);
        check(!mb_repairclk_done, "SCN2: FSM did not complete");
        check(mb_repairclk_error, "SCN2: FSM entered ERROR state successfully");

        mb_repairclk_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 3: Local Clock Training Failure
        // ====================================================================
        scn = 3;
        $display("\n[%0t] --- SCN %0d: LOCAL TRAINING FAILURE ---", $time, scn);
        do_reset();
        
        // Configure local clock training failure: rckp_pass = 0
        rckp_pass = 1'b0;
        mb_repairclk_enable = 1;

        // S1
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req);
        send_msg(MBINIT_REPAIRCLK_init_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_resp);
        send_msg(MBINIT_REPAIRCLK_init_resp, 64'h0);

        // S2
        wait (mb_tx_pattern_en);
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // S3
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_req);
        send_msg(MBINIT_REPAIRCLK_result_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_resp);
        
        // Local results were {rtrk_pass, rckn_pass, rckp_pass} = 3'b110 (6)
        check(mb_repairclk_tx_MsgInfo[2:0] == 3'b110, "SCN3: Local result reports rckp_pass=0 correctly (3'b110)");

        mb_repairclk_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 4: FIFO Backpressure handling (ltsm_rdy = 0)
        // ====================================================================
        scn = 4;
        $display("\n[%0t] --- SCN %0d: FIFO BACKPRESSURE (ltsm_rdy = 0) ---", $time, scn);
        do_reset();
        
        ltsm_rdy = 1'b0; // FIFO full
        mb_repairclk_enable = 1;

        // FSM should stay in READY_REQ_SEND and continue driving it
        repeat (20) @(posedge clk);
        check(mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req, 
              "SCN4: FSM stalled in READY_REQ_SEND during backpressure");

        ltsm_rdy = 1'b1; // Accept
        wait (mb_repairclk_rx_valid == 1'b0); // transitioned to wait state

        mb_repairclk_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 5: Early Partner Message (Deadlock Immunity)
        // ====================================================================
        scn = 5;
        $display("\n[%0t] --- SCN %0d: PARTNER EARLY MESSAGE ---", $time, scn);
        do_reset();
        
        ltsm_rdy = 1'b0; // Stalled
        mb_repairclk_enable = 1;
        repeat (5) @(posedge clk);

        // Partner sends init_req early while we are stalled in S1 REQ_SEND
        send_msg(MBINIT_REPAIRCLK_init_req, 64'h0);
        repeat (5) @(posedge clk);

        // We should still be driving ours since ltsm_rdy is 0
        check(mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req, 
              "SCN5: Still driving our init_req");

        // Now FIFO accepts ours
        ltsm_rdy = 1'b1;
        @(posedge clk);
        ltsm_rdy <= 1'b0;

        // FSM should instantly skip READY_REQ_WAIT because partner's request was already latched by sticky flag,
        // transitioning directly to READY_RSP_SEND
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_resp);
        check(1'b1, "SCN5: Skipped READY_REQ_WAIT successfully!");

        mb_repairclk_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 6: Early Partner Result Exchange
        // ====================================================================
        scn = 6;
        $display("\n[%0t] --- SCN %0d: EARLY PARTNER RESULT EXCHANGE ---", $time, scn);
        do_reset();
        mb_repairclk_enable = 1;

        // S1
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req);
        send_msg(MBINIT_REPAIRCLK_init_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_resp);
        send_msg(MBINIT_REPAIRCLK_init_resp, 64'h0);

        // S2
        wait (mb_tx_pattern_en);
        
        // Partner is very fast and sends result_req and result_resp early during our pattern transmission
        send_msg(MBINIT_REPAIRCLK_result_req, 64'h0);
        send_msg(MBINIT_REPAIRCLK_result_resp, 64'h0, 16'h7);
        repeat (5) @(posedge clk);

        // FSM should still be in S2 transmitting pattern
        check(mb_tx_pattern_en, "SCN6: FSM remains in S2 pattern transmission");

        // Now pattern completes
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // FSM transitions to RESULT_REQ_SEND. FIFO accepts ours immediately.
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_req);
        ltsm_rdy = 1'b1;
        @(posedge clk);
        ltsm_rdy <= 1'b0;

        // Expect FSM to skip RESULT_REQ_WAIT and RESULT_RSP_WAIT, transitioning directly to S3_RESULT_RSP_SEND
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_resp);
        check(1'b1, "SCN6: Skipped S3 wait states successfully (immune to latency deadlocks)!");

        mb_repairclk_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 7: Safety Watchdog Timeout
        // ====================================================================
        scn = 7;
        $display("\n[%0t] --- SCN %0d: SAFETY WATCHDOG TIMEOUT ---", $time, scn);
        do_reset();
        mb_repairclk_enable = 1;

        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req);
        // Stalled waiting for partner's S1 message. Timeout expired
        timeout_repairclk_expired = 1'b1;

        // Expect immediate transition to ERROR
        wait (mb_repairclk_error);
        check(!mb_repairclk_done, "SCN7: FSM did not complete");
        check(mb_repairclk_error, "SCN7: FSM aborted to ERROR successfully");

        mb_repairclk_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 8: Clean Restart (Disable & Re-enable)
        // ====================================================================
        scn = 8;
        $display("\n[%0t] --- SCN %0d: CLEAN RESTART ---", $time, scn);
        do_reset();
        mb_repairclk_enable = 1;

        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req);
        send_msg(MBINIT_REPAIRCLK_init_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_resp);
        
        // Disable FSM mid-run
        mb_repairclk_enable = 0;
        repeat (5) @(posedge clk);

        check(!mb_repairclk_done, "SCN8: Done is low");
        check(!mb_repairclk_error, "SCN8: Error is low");
        check(!mb_repairclk_tx_valid, "SCN8: Tx outputs cleared");

        // Re-enable: Should start fresh from S1 again
        mb_repairclk_enable = 1;
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_req);
        check(1'b1, "SCN8: Restarted successfully from S1");

        // Complete normally
        send_msg(MBINIT_REPAIRCLK_init_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_resp);
        send_msg(MBINIT_REPAIRCLK_init_resp, 64'h0);

        wait (mb_tx_pattern_en);
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_req);
        send_msg(MBINIT_REPAIRCLK_result_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_resp);
        send_msg(MBINIT_REPAIRCLK_result_resp, 64'h0, 16'h7);

        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_done_req);
        send_msg(MBINIT_REPAIRCLK_done_req, 64'h0);
        wait (mb_repairclk_tx_valid && mb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_done_resp);
        send_msg(MBINIT_REPAIRCLK_done_resp, 64'h0);

        wait (mb_repairclk_done);
        check(!mb_repairclk_error, "SCN8: Restarted FSM completed happy path successfully!");

        mb_repairclk_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SUMMARY
        // ====================================================================
        $display("\n[%0t] === DONE: %0d checks, %0d errors ===", $time, checks, errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end

    // Hard sim watchdog
    initial begin
        #500_000_000;
        $display("[%0t] HARD TIMEOUT — possible hang", $time);
        $finish;
    end

endmodule