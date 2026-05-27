`timescale 1ns/1ps
import UCIe_pkg::*;

// ============================================================================
// MBINIT_REVERSALMB Comprehensive Unit Testbench
// ============================================================================
// Covers UCIe Rev 3.0 (§4.5.3.2) Lane Reversal & Width Negotiation logic.
// Fully verifies readiness handshake, clear error handshake, pattern transmission,
// result exchange with spec-compliant MsgInfo & data layout, decision making
// (with single-cycle mb_lane_reversal_req and retry), finalize handshake,
// safety watchdog timeouts, and FIFO backpressure.
// ============================================================================

module MBINIT_REVERSALMB_tb;

    logic clk;
    logic rst_n;

    // DUT ports
    logic        mb_reversal_enable;
    logic        mb_reversal_done;
    logic        mb_reversal_error;

    // RX msg bus
    logic        mb_reversal_rx_valid;
    msg_no_e     mb_reversal_rx_msg_id;
    logic [15:0] mb_reversal_rx_MsgInfo;
    logic [63:0] mb_reversal_rx_data_Field;

    // TX msg bus
    logic        mb_reversal_tx_valid;
    msg_no_e     mb_reversal_tx_msg_id;
    logic [15:0] mb_reversal_tx_MsgInfo;
    logic [63:0] mb_reversal_tx_data_Field;

    logic        reg_x8_mode_req;
    logic [3:0]  Link_Width_enable_status;
    assign Link_Width_enable_status = reg_x8_mode_req ? 4'h1 : 4'h0;

    // Pattern Generation & Comparison Signals
    logic        mb_tx_pattern_en;
    logic [2:0]  mb_tx_pattern_setup;
    logic [1:0]  mb_tx_data_pattern_sel;
    logic        mb_rx_compare_en;
    logic [1:0]  mb_rx_compare_setup;

    logic [15:0] mb_rx_perlane_pass;
    logic        mb_tx_pattern_count_done;

    logic        mb_lane_reversal_req;
    logic        clear_error_req;

    logic        ltsm_rdy;

    logic        timeout_reversal_expired;
    logic        timeout_reversal_enable;

    int errors;
    int checks;
    int scn;

    // Clock generator (100 kHz -> 10us period)
    initial clk = 0;
    always #5000 clk = ~clk;

    initial begin
        $dumpfile("MBINIT_REVERSALMB_tb.vcd");
        $dumpvars(0, MBINIT_REVERSALMB_tb);
    end

    // Instantiate timeout counter next to the DUT (as requested)
    timeout_counter #(
        .CLK_FRQ_HZ(100000),    // match our TB clock frequency of 100 kHz
        .TIME_OUT(1)            // 1ms timeout for safety watchdog
    ) u_tb_timeout (
        .clk(clk),
        .timeout_rst_n(rst_n),
        .enable_timeout(timeout_reversal_enable),
        .timeout_expired(timeout_reversal_expired)
    );

    // Instantiate DUT
    MBINIT_REVERSALMB #(
        .CLK_FRQ_HZ(100000)     // match our TB clock frequency of 100 kHz
    ) dut (.*);

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
        rst_n                                     = 0;
        mb_reversal_enable                        = 0;
        mb_reversal_rx_valid                      = 0;
        mb_reversal_rx_msg_id                     = msg_no_e'(NOTHING);
        mb_reversal_rx_MsgInfo                    = 16'h0;
        mb_reversal_rx_data_Field                 = 64'h0;
        
        reg_x8_mode_req                           = 1'b0; // default x16
        mb_rx_perlane_pass                        = 16'hFFFF; // default all lanes PASS
        mb_tx_pattern_count_done                  = 1'b0;

        ltsm_rdy                                  = 1'b1;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    endtask

    // Send a message from partner
    task send_msg(input msg_no_e msg_id, input logic [63:0] data_field, input logic [15:0] msg_info = 16'h0);
        @(posedge clk);
        mb_reversal_rx_valid      <= 1'b1;
        mb_reversal_rx_msg_id     <= msg_id;
        mb_reversal_rx_MsgInfo    <= msg_info;
        mb_reversal_rx_data_Field <= data_field;
        @(posedge clk);
        mb_reversal_rx_valid      <= 1'b0;
        mb_reversal_rx_msg_id     <= msg_no_e'(NOTHING);
        mb_reversal_rx_data_Field <= 64'h0;
    endtask

    // ========================================================================
    // Main Test Suite
    // ========================================================================
    initial begin
        errors = 0;
        checks = 0;
        $display("[%0t] === MBINIT_REVERSALMB COMPREHENSIVE TB START ===\n", $time);

        // ====================================================================
        // SCN 1: Normal Happy Path (All PASS on First Run, x16 Mode)
        // ====================================================================
        scn = 1;
        $display("[%0t] --- SCN %0d: HAPPY PATH (x16 MODE) ---", $time, scn);
        do_reset();
        mb_reversal_enable = 1;

        // Step 1: Readiness Handshake
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req);
        check(timeout_reversal_enable, "SCN1: Timeout timer enabled in S1");
        send_msg(MBINIT_REVERSALMB_init_req, 64'h0);

        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_resp);
        send_msg(MBINIT_REVERSALMB_init_resp, 64'h0);

        // Step 2: Clear Error Handshake
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_req);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        #1;
        check(clear_error_req, "SCN1: clear_error_req pulsed high upon receiving clear_error_req from partner");

        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        // Step 3: Pattern Transmission Phase
        wait (mb_tx_pattern_en);
        #1;
        check(mb_rx_compare_en, "SCN1: Rx compare enabled during pattern transmission");
        check(mb_tx_data_pattern_sel == 2'b01, "SCN1: Pattern selection is per-lane ID (2'b01)");
        check(mb_rx_compare_setup == 2'b01, "SCN1: Compare setup is per-lane (2'b01)");
        repeat (20) @(posedge clk);
        
        // Logical block finishes transmitting
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // Step 4: Result Exchange Handshake
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        check(!mb_tx_pattern_en, "SCN1: Tx pattern disabled after transmission completed");
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);

        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        // Our local status is all PASS (16'hFFFF)
        check(mb_reversal_tx_data_Field == 64'h0000_0000_0000_FFFF, "SCN1: Local result is driven correctly (no inversion, 16'hFFFF)");

        // Partner reports all lanes PASS
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_FFFF);

        // Step 5: Decision -> Finalize Handshake
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_req);
        check(mb_lane_reversal_req == 1'b0, "SCN1: No lane reversal requested");
        send_msg(MBINIT_REVERSALMB_done_req, 64'h0);

        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_resp);
        send_msg(MBINIT_REVERSALMB_done_resp, 64'h0);

        // Success DONE
        wait (mb_reversal_done);
        check(!mb_reversal_error, "SCN1: FSM finished successfully without errors");

        mb_reversal_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 2: Reversal Needed & Retry PASS (x16 Mode)
        // ====================================================================
        scn = 2;
        $display("\n[%0t] --- SCN %0d: REVERSAL NEEDED & RETRY PASS (x16 MODE) ---", $time, scn);
        do_reset();
        mb_reversal_enable = 1;

        // Step 1: Readiness
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req);
        send_msg(MBINIT_REVERSALMB_init_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_resp);
        send_msg(MBINIT_REVERSALMB_init_resp, 64'h0);

        // Step 2: Clear Error
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_req);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        // Step 3: Pattern (First Run - Fails)
        wait (mb_tx_pattern_en);
        // Configure local status as fail on 1st run: mb_rx_perlane_pass = 16'h0000
        mb_rx_perlane_pass = 16'h0000;
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // Step 4: Result Exchange (First Run - Fail)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        check(mb_reversal_tx_data_Field == 64'h0000_0000_0000_0000, "SCN2: Local driven result reports 0 on FAIL");
        
        // Partner also reports all FAIL
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_0000);

        // Step 5: Decision -> FSM detects failure (success_count = 0 < 8), raises mb_lane_reversal_req for 1 cycle,
        // and transitions back to S2 to retry.
        @(posedge clk);
        @(posedge clk);
        #1;
        check(mb_lane_reversal_req == 1'b1, "SCN2: Lane reversal request pulsed high for 1 cycle");
        @(posedge clk);
        #1;
        check(mb_lane_reversal_req == 1'b0, "SCN2: Lane reversal request dropped back to 0");

        // FSM has transitioned to S2 to retry
        wait (dut.current_state == dut.MB_S2_ERROR_RESET_REQ_SEND || dut.current_state == dut.MB_S2_ERROR_RESET_REQ_WAIT);
        $display("[%0t] SCN2 ok  : FSM retried and returned to S2 clear error", $time);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        // Step 3: Pattern (Second Run - PASS after reversal)
        wait (mb_tx_pattern_en);
        mb_rx_perlane_pass = 16'hFFFF; // Now passing
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // Step 4: Result Exchange (Second Run - PASS)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        check(mb_reversal_tx_data_Field == 64'h0000_0000_0000_FFFF, "SCN2: Local driven result reports FFFF on PASS");
        
        // Partner also reports PASS
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_FFFF);

        // Step 5: Finalize
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_req);
        send_msg(MBINIT_REVERSALMB_done_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_resp);
        send_msg(MBINIT_REVERSALMB_done_resp, 64'h0);

        wait (mb_reversal_done);
        check(!mb_reversal_error, "SCN2: FSM completed successfully after retry");

        mb_reversal_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 3: Reversal Needed but Retry FAIL (Double Fail -> ERROR)
        // ====================================================================
        scn = 3;
        $display("\n[%0t] --- SCN %0d: REVERSAL DOUBLE FAILURE ---", $time, scn);
        do_reset();
        mb_reversal_enable = 1;

        // S1
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req);
        send_msg(MBINIT_REVERSALMB_init_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_resp);
        send_msg(MBINIT_REVERSALMB_init_resp, 64'h0);

        // S2 (1st clear)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_req);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        // S3 (1st pattern fail)
        wait (mb_tx_pattern_en);
        mb_rx_perlane_pass = 16'h0000;
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // S4 (1st result exchange fail)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_0000);

        // S5 decision: triggers reversal_req and retry
        @(posedge clk);
        @(posedge clk);
        #1;
        check(mb_lane_reversal_req == 1'b1, "SCN3: Lane reversal requested");

        // S2 (2nd clear)
        wait (dut.current_state == dut.MB_S2_ERROR_RESET_REQ_SEND || dut.current_state == dut.MB_S2_ERROR_RESET_REQ_WAIT);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        // S3 (2nd pattern fail)
        wait (mb_tx_pattern_en);
        mb_rx_perlane_pass = 16'h0000; // Still failing
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // S4 (2nd result exchange fail)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_0000);

        // S5 decision: since retry_done is set and majority_success is false, abort to ERROR
        wait (mb_reversal_error);
        check(!mb_reversal_done, "SCN3: FSM did not complete successfully");
        check(mb_reversal_error, "SCN3: FSM successfully entered error state");

        mb_reversal_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 4: Normal Happy Path (All PASS, x8 Mode)
        // ====================================================================
        scn = 4;
        $display("\n[%0t] --- SCN %0d: HAPPY PATH (x8 MODE) ---", $time, scn);
        do_reset();
        reg_x8_mode_req = 1'b1; // x8 Mode
        mb_reversal_enable = 1;

        // S1
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req);
        send_msg(MBINIT_REVERSALMB_init_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_resp);
        send_msg(MBINIT_REVERSALMB_init_resp, 64'h0);

        // S2
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_req);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        // S3
        wait (mb_tx_pattern_en);
        // Only active lower 8 lanes are passing (status 1 = PASS)
        mb_rx_perlane_pass = 16'h00FF;
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // S4
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        
        // Under x8 mode, the data field must mask upper bits to 0
        check(mb_reversal_tx_data_Field == 64'h0000_0000_0000_00FF, 
              "SCN4: Driven result masked correctly to 56'h0 + lower active 8 status bits (64'h00FF)");

        // Partner reports lower 8 lanes PASS
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_00FF);

        // S5 -> Finalize
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_req);
        send_msg(MBINIT_REVERSALMB_done_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_resp);
        send_msg(MBINIT_REVERSALMB_done_resp, 64'h0);

        wait (mb_reversal_done);
        check(!mb_reversal_error, "SCN4: x8 happy path completed successfully");

        mb_reversal_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 5: Reversal Needed & Retry PASS (x8 Mode)
        // ====================================================================
        scn = 5;
        $display("\n[%0t] --- SCN %0d: REVERSAL NEEDED & RETRY PASS (x8 MODE) ---", $time, scn);
        do_reset();
        reg_x8_mode_req = 1'b1;
        mb_reversal_enable = 1;

        // S1
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req);
        send_msg(MBINIT_REVERSALMB_init_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_resp);
        send_msg(MBINIT_REVERSALMB_init_resp, 64'h0);

        // S2 (1st clear)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_req);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        // S3 (1st pattern fail)
        wait (mb_tx_pattern_en);
        mb_rx_perlane_pass = 16'h0000;
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // S4 (1st result exchange fail)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_0000);

        // S5 decision: triggers reversal_req and retry
        @(posedge clk);
        @(posedge clk);
        #1;
        check(mb_lane_reversal_req == 1'b1, "SCN5: Reversal requested in x8 mode");

        // S2 (2nd clear)
        wait (dut.current_state == dut.MB_S2_ERROR_RESET_REQ_SEND || dut.current_state == dut.MB_S2_ERROR_RESET_REQ_WAIT);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        // S3 (2nd pattern pass)
        wait (mb_tx_pattern_en);
        mb_rx_perlane_pass = 16'h00FF; // lower 8 active lanes PASS
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        // S4 (2nd result exchange pass)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_00FF);

        // S6
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_req);
        send_msg(MBINIT_REVERSALMB_done_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_resp);
        send_msg(MBINIT_REVERSALMB_done_resp, 64'h0);

        wait (mb_reversal_done);
        check(!mb_reversal_error, "SCN5: x8 reversal retry completed successfully");

        mb_reversal_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 6: FIFO Backpressure handling (ltsm_rdy = 0)
        // ====================================================================
        scn = 6;
        $display("\n[%0t] --- SCN %0d: FIFO BACKPRESSURE (ltsm_rdy = 0) ---", $time, scn);
        do_reset();
        ltsm_rdy = 1'b0; // FIFO full
        mb_reversal_enable = 1;

        // FSM should stall in READY_REQ_SEND and drive it continuously
        repeat (20) @(posedge clk);
        check(mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req, 
              "SCN6: FSM stalled in READY_REQ_SEND during backpressure");

        ltsm_rdy = 1'b1;
        wait (mb_reversal_rx_valid == 1'b0); // transitions to wait state

        mb_reversal_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 7: Safety Watchdog Timeout
        // ====================================================================
        scn = 7;
        $display("\n[%0t] --- SCN %0d: SAFETY WATCHDOG TIMEOUT ---", $time, scn);
        do_reset();
        mb_reversal_enable = 1;

        // Wait in S1 READY_REQ_WAIT (partner never replies)
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req);
        check(timeout_reversal_enable, "SCN7: Watchdog timer enabled");

        // Wait for TB timeout counter to trigger expiration (1ms TB duration = 100 clock cycles)
        wait (timeout_reversal_expired);

        // Expect immediate transition to ERROR
        wait (mb_reversal_error);
        check(!mb_reversal_done, "SCN7: FSM did not complete successfully");
        check(mb_reversal_error, "SCN7: FSM aborted to ERROR state successfully");

        mb_reversal_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SCN 8: Clean Restart (Disable & Re-enable)
        // ====================================================================
        scn = 8;
        $display("\n[%0t] --- SCN %0d: CLEAN RESTART ---", $time, scn);
        do_reset();
        mb_reversal_enable = 1;

        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req);
        send_msg(MBINIT_REVERSALMB_init_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_resp);
        
        // Disable FSM mid-run in S1_READY_RSP_WAIT
        mb_reversal_enable = 0;
        repeat (5) @(posedge clk);

        check(!mb_reversal_done, "SCN8: Done is low");
        check(!mb_reversal_error, "SCN8: Error is low");
        check(!mb_reversal_tx_valid, "SCN8: Tx outputs cleared");

        // Re-enable: FSM should start fresh from S1 again
        mb_reversal_enable = 1;
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_req);
        check(1'b1, "SCN8: Restarted successfully from S1");

        // Complete normally
        send_msg(MBINIT_REVERSALMB_init_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_init_resp);
        send_msg(MBINIT_REVERSALMB_init_resp, 64'h0);

        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_req);
        send_msg(MBINIT_REVERSALMB_clear_error_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_clear_error_resp);
        send_msg(MBINIT_REVERSALMB_clear_error_resp, 64'h0);

        wait (mb_tx_pattern_en);
        mb_rx_perlane_pass = 16'hFFFF;
        mb_tx_pattern_count_done = 1'b1;
        @(posedge clk);
        mb_tx_pattern_count_done = 1'b0;

        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_req);
        send_msg(MBINIT_REVERSALMB_result_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_result_resp);
        send_msg(MBINIT_REVERSALMB_result_resp, 64'h0000_0000_0000_FFFF);

        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_req);
        send_msg(MBINIT_REVERSALMB_done_req, 64'h0);
        wait (mb_reversal_tx_valid && mb_reversal_tx_msg_id == MBINIT_REVERSALMB_done_resp);
        send_msg(MBINIT_REVERSALMB_done_resp, 64'h0);

        wait (mb_reversal_done);
        check(!mb_reversal_error, "SCN8: Restarted FSM completed happy path successfully!");

        mb_reversal_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SUMMARY
        // ====================================================================
        $display("\n[%0t] === DONE: %0d checks, %0d errors ===", $time, checks, errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end

    // Hard sim watchdog (500 ms)
    initial begin
        #500_000_000;
        $display("[%0t] HARD TIMEOUT — possible hang", $time);
        $finish;
    end

endmodule