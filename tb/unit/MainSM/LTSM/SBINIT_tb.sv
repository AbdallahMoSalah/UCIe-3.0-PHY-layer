`timescale 1ns/1ps
import UCIe_pkg::*;

// ============================================================================
// SBINIT Comprehensive Unit Testbench
// ============================================================================
// Covers UCIe Rev 3.0 §4.5.3.2 Steps 1-8 (Standard Package flow).
// All scenarios are spec-compliant. Partner timing variations respect:
//
//   1. Partner sends Out_of_Reset independently (Step 6) — no dependency on us.
//   2. Partner sends done_req (Step 8a) only AFTER receiving OUR Out_of_Reset.
//      → Earliest arrival: during our S3 (we start sending Out_of_Reset there).
//   3. Partner sends done_resp (Step 8c) only AFTER receiving OUR done_req.
//      → Earliest arrival: during our RSP_SEND (we sent done_req in REQ_SEND).
//   4. SB channel preserves FIFO ordering:
//      Out_of_Reset arrives before done_req, done_req before done_resp.
//
// 29 scenarios across 8 categories.
// ============================================================================

module SBINIT_tb;

    parameter int CLK_FRQ_HZ = 100_000;            // 100 kHz -> 1 cycle = 10 us
    localparam int MS_CYCLES = CLK_FRQ_HZ / 1000;  // 100 cycles per 1 ms

    logic clk;
    logic rst_n;

    // DUT IO
    logic       sbinit_enable, sbinit_done, sbinit_error;
    logic       sb_rx_valid;
    msg_no_e    sb_rx_msg_id;
    logic       iter_done;
    logic       sb_det_pattern_rcvd;
    logic       sb_tx_valid;
    msg_no_e    sb_tx_msg_id;
    logic       sbinit_pattern_mode;
    logic       sb_det_pattern_req;
    logic [2:0] req_iter_count;
    logic       ltsm_rdy;
    logic       global_error;

    int errors;
    int checks;
    int scn;
    int t_high, t_low;

    initial clk = 0;
    always #5000 clk = ~clk;   // 10 us period

    initial begin
        $dumpfile("SBINIT_tb.vcd");
        $dumpvars(0, SBINIT_tb);
    end

    SBINIT #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) dut (.*);

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
        rst_n                  = 0;
        sbinit_enable          = 0;
        sb_rx_valid            = 0;
        sb_rx_msg_id           = msg_no_e'(NOTHING);
        iter_done              = 0;
        sb_det_pattern_rcvd    = 0;
        ltsm_rdy               = 0;
        global_error           = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    endtask

    // Send a single SB message (1-cycle pulse).
    task send_msg(input msg_no_e m);
        @(posedge clk);
        sb_rx_valid  <= 1'b1;
        sb_rx_msg_id <= m;
        @(posedge clk);
        sb_rx_valid  <= 1'b0;
        sb_rx_msg_id <= msg_no_e'(NOTHING);
    endtask

    // Pulse ltsm_rdy=1 for one clock once the DUT is driving the expected msg.
    task accept_tx(input msg_no_e expected);
        wait (sb_tx_valid && sb_tx_msg_id == expected);
        @(posedge clk);
        ltsm_rdy <= 1'b1;
        @(posedge clk);
        ltsm_rdy <= 1'b0;
    endtask

    // Drive DUT from IDLE through S1->S2 (LINK_SYNCH entry).
    task run_to_S2();
        wait (sb_det_pattern_req);
        repeat (MS_CYCLES + 5) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
    endtask

    // Drive DUT from IDLE through S1->S2->S3 (OUT_OF_RESET entry).
    task run_to_S3();
        run_to_S2();
        repeat (5) @(posedge clk);
        iter_done <= 1'b1; @(posedge clk);
        iter_done <= 1'b0;
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
    endtask

    // Drive DUT from IDLE all the way into S4 (REQ_SEND entry).
    task run_to_S4();
        run_to_S3();
        send_msg(SBINIT_Out_of_Reset);
    endtask

    // Complete Step 8 with default ordering (normal handshake).
    task complete_step8_normal();
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
    endtask

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        errors = 0;
        checks = 0;
        $display("[%0t] === SBINIT COMPREHENSIVE TB START ===\n", $time);

        // ====================================================================
        // CATEGORY 1: HAPPY PATH
        // ====================================================================

        // ---- SCN 1: Normal happy path (all steps in order) ----
        // Spec: §4.5.3.2 Steps 1→8, both sides same speed.
        scn = 1;
        $display("[%0t] --- SCN %0d: HAPPY PATH ---", $time, scn);
        do_reset();
        sbinit_enable = 1;

        // S1: Pattern detection with 1ms/1ms duty cycle
        wait (sb_det_pattern_req);
        check(sbinit_pattern_mode, "S1: pattern_mode high");
        repeat (MS_CYCLES + 5) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        @(posedge clk);
        check(!sb_det_pattern_req, "S1->S2: pattern_req drops after detect");

        // S2: 4 iterations
        wait (req_iter_count == 3'd4);
        check(sbinit_pattern_mode, "S2: pattern_mode still high");
        repeat (5) @(posedge clk);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;

        // S3: Out of Reset
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        check(!sbinit_pattern_mode, "S3: pattern_mode drops");
        send_msg(SBINIT_Out_of_Reset);

        // S4: Done handshake (normal order)
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);

        wait (sbinit_done);
        check(!sbinit_error,        "DONE: no error");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // CATEGORY 2: PATTERN DETECTION (Steps 1-5)
        // ====================================================================

        // ---- SCN 2: Duty cycle timing (1ms high / 1ms low) ----
        // Spec: §4.5.3.2 Step 5 — 1ms send pattern / 1ms hold low.
        scn = 2;
        $display("\n[%0t] --- SCN %0d: DUTY CYCLE TIMING ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        t_high = 0;
        while (sb_det_pattern_req) begin @(posedge clk); t_high++; end
        t_low = 0;
        while (!sb_det_pattern_req) begin @(posedge clk); t_low++; end
        check(t_high >= MS_CYCLES-2 && t_high <= MS_CYCLES+2,
              $sformatf("DUTY: high=%0d ~= %0d cycles", t_high, MS_CYCLES));
        check(t_low >= MS_CYCLES-2 && t_low <= MS_CYCLES+2,
              $sformatf("DUTY: low=%0d ~= %0d cycles", t_low, MS_CYCLES));
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 3: Pattern detected during hold-low phase ----
        // Spec: Pattern detect can happen at any time during Step 5.
        scn = 3;
        $display("\n[%0t] --- SCN %0d: PATTERN DETECTED DURING LOW PHASE ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        while (sb_det_pattern_req) @(posedge clk); // wait for low phase
        repeat (MS_CYCLES / 2) @(posedge clk);     // middle of low phase
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        check(1'b1, "Pattern detected during low phase -> S2 reached");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 4: Multiple pattern_rcvd pulses (second ignored) ----
        // Spec: Once pattern is detected, subsequent detections are irrelevant.
        scn = 4;
        $display("\n[%0t] --- SCN %0d: DUPLICATE PATTERN DETECT ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        repeat (10) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        // Send another detection pulse in S2 (should be harmless)
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        repeat (5) @(posedge clk);
        check(req_iter_count == 3'd4, "Duplicate pattern_rcvd ignored, still in S2");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 5: iter_done hold and release ----
        // Spec: Step 4 — 4 iterations must complete before enabling msg tx/rx.
        scn = 5;
        $display("\n[%0t] --- SCN %0d: ITER_DONE HOLD AND RELEASE ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S2();
        check(req_iter_count == 3'd4, "S2: req_iter_count == 4");
        repeat (20) @(posedge clk);
        check(req_iter_count == 3'd4, "S2: count holds until iter_done");
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        check(req_iter_count == 3'd0, "S3: count back to 0");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 6: Spurious iter_done during S1 (ignored) ----
        // Spec: iter_done only relevant in Step 4 (S2). Ignored elsewhere.
        scn = 6;
        $display("\n[%0t] --- SCN %0d: SPURIOUS ITER_DONE IN S1 ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        repeat (5) @(posedge clk);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        repeat (5) @(posedge clk);
        check(sbinit_pattern_mode, "Still in S1 (spurious iter_done ignored)");
        // Complete normally
        repeat (MS_CYCLES) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        check(1'b1, "Normal flow resumed after spurious iter_done");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // CATEGORY 3: OUT OF RESET (Steps 6-7)
        // ====================================================================

        // ---- SCN 7: Continuous Out_of_Reset until partner echoes ----
        // Spec: §4.5.3.2 Step 6-7 — keep sending Out_of_Reset until received.
        scn = 7;
        $display("\n[%0t] --- SCN %0d: OUT_OF_RESET PERSISTENCE ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S3();
        repeat (50) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset,
              "S3: still driving Out_of_Reset after 50 cycles");
        send_msg(SBINIT_Out_of_Reset);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        check(1'b1, "Transitioned to REQ_SEND after partner echo");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 8: Unknown message in S3 (ignored) ----
        // Spec: Only Out_of_Reset is relevant in Step 7.
        scn = 8;
        $display("\n[%0t] --- SCN %0d: UNKNOWN MSG IN S3 ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S3();
        send_msg(msg_no_e'(NOTHING));
        repeat (10) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset,
              "S3: stays after unknown msg");
        send_msg(SBINIT_Out_of_Reset);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        check(1'b1, "S3 exited after real Out_of_Reset");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 9: Partner Out_of_Reset arrives during S2 ----
        // Spec-valid: Partner completed Steps 1-5 faster, sent Out_of_Reset
        // before us. No dependency — Out_of_Reset is sent independently.
        scn = 9;
        $display("\n[%0t] --- SCN %0d: PARTNER OUT_OF_RESET EARLY (S2) ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S2();
        // Partner is faster at pattern detection, already in Step 6
        send_msg(SBINIT_Out_of_Reset);
        repeat (5) @(posedge clk);
        // Complete S2
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        // Sticky set -> should skip S3, jump to REQ_SEND
        repeat (3) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_req,
              "Skipped S3 (Out_of_Reset arrived during S2)");
        complete_step8_normal();
        check(!sbinit_error, "Completed without error");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 10: Partner Out_of_Reset arrives during S1 ----
        // Spec-valid: Partner was much faster at pattern detection.
        scn = 10;
        $display("\n[%0t] --- SCN %0d: PARTNER OUT_OF_RESET EARLY (S1) ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        repeat (5) @(posedge clk);
        // Partner already in Step 6 while we're still in Step 5
        send_msg(SBINIT_Out_of_Reset);
        // Continue our pattern detection
        repeat (MS_CYCLES) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        repeat (5) @(posedge clk);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        // Should skip S3 -> REQ_SEND
        repeat (3) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_req,
              "Skipped S3 (Out_of_Reset arrived during S1)");
        complete_step8_normal();
        check(!sbinit_error, "Completed without error");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // CATEGORY 4: STEP 8 — BACKPRESSURE (FIFO busy)
        // ====================================================================

        // ---- SCN 11: ltsm_rdy backpressure in REQ_SEND ----
        // Spec: DUT keeps driving done_req until FIFO accepts.
        scn = 11;
        $display("\n[%0t] --- SCN %0d: BACKPRESSURE IN REQ_SEND ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        repeat (30) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_req,
              "REQ_SEND: holds done_req for 30 cycles");
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "Completed after REQ backpressure");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 12: ltsm_rdy backpressure in RSP_SEND ----
        // Spec: DUT keeps driving done_resp until FIFO accepts.
        scn = 12;
        $display("\n[%0t] --- SCN %0d: BACKPRESSURE IN RSP_SEND ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        repeat (30) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp,
              "RSP_SEND: holds done_resp for 30 cycles");
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "Completed after RSP backpressure");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 13: ltsm_rdy already high when entering REQ_SEND ----
        // Edge case: FIFO ready before we start driving.
        scn = 13;
        $display("\n[%0t] --- SCN %0d: LTSM_RDY PRE-ASSERTED ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S3();
        ltsm_rdy <= 1'b1;  // pre-assert
        send_msg(SBINIT_Out_of_Reset);
        // ltsm_rdy=1 when entering REQ_SEND -> immediate accept
        repeat (3) @(posedge clk);
        ltsm_rdy <= 1'b0;
        // Now in REQ_WAIT, need partner done_req
        send_msg(SBINIT_done_req);
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "Completed with pre-asserted ltsm_rdy");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // CATEGORY 5: STEP 8 — SPEC-VALID PARTNER TIMING VARIATIONS
        // ====================================================================

        // ---- SCN 14: Partner done_req during REQ_SEND ----
        // Spec-valid: Partner was faster — already sent done_req before our
        // FIFO accepted ours. Both sides send done_req independently.
        scn = 14;
        $display("\n[%0t] --- SCN %0d: PARTNER done_req DURING REQ_SEND ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        // Partner's done_req arrives while our FIFO hasn't accepted ours
        send_msg(SBINIT_done_req);
        repeat (5) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_req,
              "Still in REQ_SEND (ours not accepted yet)");
        // Accept ours -> REQ_WAIT. done_req_rcvd sticky already set -> skip REQ_WAIT
        accept_tx(SBINIT_done_req);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        check(1'b1, "Skipped REQ_WAIT -> RSP_SEND (done_req sticky set)");
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "Completed with early partner done_req");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 15: Partner done_req during S3 (fast partner) ----
        // Spec-valid: Partner received our Out_of_Reset quickly (low-latency
        // SB channel), completed Step 7, and sent done_req (Step 8a).
        // Partner's Out_of_Reset arrives first (FIFO ordering), followed by
        // done_req in rapid succession — both during our S3.
        scn = 15;
        $display("\n[%0t] --- SCN %0d: PARTNER done_req DURING S3 (FAST PARTNER) ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S3();
        // Partner's Out_of_Reset arrives first (FIFO ordering)
        send_msg(SBINIT_Out_of_Reset);
        // Partner received our Out_of_Reset quickly, sent done_req immediately
        send_msg(SBINIT_done_req);
        // We transition S3->REQ_SEND. done_req_rcvd sticky is set.
        // Accept our done_req
        accept_tx(SBINIT_done_req);
        // REQ_WAIT: done_req_rcvd already set -> skip to RSP_SEND
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        check(1'b1, "Skipped REQ_WAIT (done_req arrived during S3)");
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "Completed with fast partner (done_req in S3)");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 16: Partner done_resp during RSP_SEND ----
        // Spec-valid: Partner received our done_req (we sent it in REQ_SEND),
        // quickly completed Step 8b, and sent done_resp (Step 8c).
        // Their done_resp arrives while we're still in RSP_SEND.
        scn = 16;
        $display("\n[%0t] --- SCN %0d: PARTNER done_resp DURING RSP_SEND ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        // Now in RSP_SEND. Partner already received our done_req and replied fast.
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        // Partner's done_resp arrives while we're driving our done_resp
        send_msg(SBINIT_done_resp);
        repeat (5) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp,
              "Still in RSP_SEND (FIFO hasn't accepted ours)");
        // Accept our done_resp -> RSP_WAIT. done_resp_rcvd sticky set -> skip RSP_WAIT
        accept_tx(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "Completed (partner done_resp arrived during RSP_SEND)");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 17: Fast partner — Out_of_Reset in S2, done_req in S3, done_resp in RSP_SEND ----
        // Spec-valid: Partner is a faster UCIe implementation at every step.
        scn = 17;
        $display("\n[%0t] --- SCN %0d: FAST PARTNER (ALL MSGS ARRIVE EARLY) ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S2();
        // Partner's Out_of_Reset arrives during our S2 (partner faster at Steps 1-5)
        send_msg(SBINIT_Out_of_Reset);
        // Complete S2
        repeat (5) @(posedge clk);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        // Skip S3 (sticky set), enter REQ_SEND
        // Partner received our Out_of_Reset (sent when we briefly touched S3's
        // output) and replied with done_req quickly
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        send_msg(SBINIT_done_req);  // arrives during REQ_SEND
        accept_tx(SBINIT_done_req);
        // Skip REQ_WAIT, enter RSP_SEND
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        // Partner received our done_req quickly, replies with done_resp
        send_msg(SBINIT_done_resp);  // arrives during RSP_SEND
        accept_tx(SBINIT_done_resp);
        // Skip RSP_WAIT
        wait (sbinit_done);
        check(!sbinit_error, "Fast partner: all wait states skipped");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // CATEGORY 6: TIMEOUT (8ms watchdog)
        // ====================================================================

        // ---- SCN 18: Timeout during S1 (pattern never detected) ----
        // Spec: 8ms timeout → TRAINERROR.
        scn = 18;
        $display("\n[%0t] --- SCN %0d: TIMEOUT IN S1 ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        repeat (10) @(posedge clk);
        global_error <= 1'b1;
        wait (sbinit_error);
        check(!sbinit_done,         "Timeout: done=0");
        global_error <= 1'b0;
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 19: Timeout during S3 (partner never sends Out_of_Reset) ----
        // Spec: Partner stuck or disconnected.
        scn = 19;
        $display("\n[%0t] --- SCN %0d: TIMEOUT IN S3 ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S3();
        repeat (10) @(posedge clk);
        global_error <= 1'b1;
        wait (sbinit_error);
        check(!sbinit_done, "Timeout in S3: done=0");
        global_error <= 1'b0;
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 20: Timeout during REQ_WAIT (partner never sends done_req) ----
        // Spec: Partner stuck after we sent done_req.
        scn = 20;
        $display("\n[%0t] --- SCN %0d: TIMEOUT IN REQ_WAIT ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        accept_tx(SBINIT_done_req);
        repeat (10) @(posedge clk);
        global_error <= 1'b1;
        wait (sbinit_error);
        check(!sbinit_done, "Timeout in REQ_WAIT: done=0");
        global_error <= 1'b0;
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 21: Timeout during RSP_WAIT (partner never sends done_resp) ----
        // Spec: Partner sent done_req but never followed with done_resp.
        scn = 21;
        $display("\n[%0t] --- SCN %0d: TIMEOUT IN RSP_WAIT ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        accept_tx(SBINIT_done_resp);
        repeat (10) @(posedge clk);
        global_error <= 1'b1;
        wait (sbinit_error);
        check(!sbinit_done, "Timeout in RSP_WAIT: done=0");
        global_error <= 1'b0;
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // CATEGORY 7: ENABLE CONTROL
        // ====================================================================

        // ---- SCN 22: Disable during S1 ----
        // Spec: sbinit_enable deassert returns to IDLE.
        scn = 22;
        $display("\n[%0t] --- SCN %0d: DISABLE DURING S1 ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        repeat (30) @(posedge clk);
        sbinit_enable = 0;
        repeat (5) @(posedge clk);
        check(!sb_det_pattern_req,  "IDLE: pattern_req low");
        check(!sbinit_pattern_mode, "IDLE: pattern_mode low");
        check(!sbinit_done,         "IDLE: done low");
        check(!sbinit_error,        "IDLE: error low");
        repeat (10) @(posedge clk);

        // ---- SCN 23: Disable during REQ_SEND ----
        scn = 23;
        $display("\n[%0t] --- SCN %0d: DISABLE DURING REQ_SEND ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        repeat (5) @(posedge clk);
        sbinit_enable = 0;
        repeat (5) @(posedge clk);
        check(!sb_tx_valid,  "IDLE: tx_valid low");
        check(!sbinit_done,  "IDLE: done low");
        check(!sbinit_error, "IDLE: error low");
        repeat (10) @(posedge clk);

        // ---- SCN 24: Disable during RSP_WAIT ----
        scn = 24;
        $display("\n[%0t] --- SCN %0d: DISABLE DURING RSP_WAIT ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        accept_tx(SBINIT_done_resp);
        repeat (5) @(posedge clk);
        sbinit_enable = 0;
        repeat (5) @(posedge clk);
        check(!sbinit_done,  "IDLE: done low after disable in RSP_WAIT");
        check(!sbinit_error, "IDLE: error low");
        repeat (10) @(posedge clk);

        // ---- SCN 25: Disable + re-enable (clean restart, stickies cleared) ----
        // Spec: Re-entering SBINIT must start fresh.
        scn = 25;
        $display("\n[%0t] --- SCN %0d: DISABLE + RE-ENABLE ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S3();
        repeat (10) @(posedge clk);
        sbinit_enable = 0;
        repeat (10) @(posedge clk);
        check(!sbinit_done, "After disable: done low");
        // Re-enable -> must restart from S1
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        check(sbinit_pattern_mode, "Re-enabled: back in S1");
        // Full flow to prove stickies cleared
        repeat (MS_CYCLES + 5) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        repeat (5) @(posedge clk);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        send_msg(SBINIT_Out_of_Reset);
        complete_step8_normal();
        check(!sbinit_error, "Clean restart completed");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // CATEGORY 8: EDGE CASES
        // ====================================================================

        // ---- SCN 26: Duplicate done_req from partner ----
        // Spec: Sticky flag already set, second message harmless.
        scn = 26;
        $display("\n[%0t] --- SCN %0d: DUPLICATE PARTNER done_req ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        send_msg(SBINIT_done_req);  // duplicate
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "Duplicate done_req handled");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 27: Unknown messages during Step 8 ----
        // Spec: Messages not matching done_req/done_resp are ignored.
        scn = 27;
        $display("\n[%0t] --- SCN %0d: UNKNOWN MSGS DURING STEP 8 ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        send_msg(msg_no_e'(NOTHING));        // unknown
        send_msg(SBINIT_Out_of_Reset);       // irrelevant in Step 8
        repeat (5) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_req,
              "Still in REQ_SEND after irrelevant msgs");
        complete_step8_normal();
        check(!sbinit_error, "Completed after ignoring unknown msgs");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 28: Back-to-back full runs (stickies properly cleared) ----
        // Spec: Each SBINIT entry must be independent.
        scn = 28;
        $display("\n[%0t] --- SCN %0d: BACK-TO-BACK RUNS ---", $time, scn);
        do_reset();
        // Run 1
        sbinit_enable = 1;
        run_to_S4();
        complete_step8_normal();
        check(!sbinit_error, "Run 1 completed");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);
        // Run 2
        sbinit_enable = 1;
        run_to_S4();
        complete_step8_normal();
        check(!sbinit_error, "Run 2 completed (stickies cleared)");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ---- SCN 29: ltsm_rdy multi-cycle burst ----
        // Edge case: FIFO keeps rdy high for several cycles.
        scn = 29;
        $display("\n[%0t] --- SCN %0d: LTSM_RDY MULTI-CYCLE ---", $time, scn);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        @(posedge clk);
        ltsm_rdy <= 1'b1;
        repeat (5) @(posedge clk);
        ltsm_rdy <= 1'b0;
        // Should have moved past REQ_SEND on first ltsm_rdy cycle
        send_msg(SBINIT_done_req);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "Completed with multi-cycle ltsm_rdy");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // ====================================================================
        // SUMMARY
        // ====================================================================
        $display("\n[%0t] === DONE: %0d checks, %0d errors ===", $time, checks, errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end

    // Hard sim timeout
    initial begin
        #2_000_000_000;
        $display("[%0t] HARD TIMEOUT — possible hang", $time);
        $finish;
    end

endmodule