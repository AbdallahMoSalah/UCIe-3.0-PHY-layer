`timescale 1ns/1ps
import UCIe_pkg::*;

// SBINIT unit testbench — covers UCIe Rev 3.0 §4.5.3.2 Steps 1-8.
// 10 scenarios. Procedural checks (no SVA).

module SBINIT_tb;

    parameter int CLK_FRQ_HZ = 100_000;        // 100 kHz -> 1 cycle = 10 us
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
    logic       sbinit_timer_enable;
    logic       sbinit_timeout_expired;

    int errors;
    int checks;
    int t_high;
    int t_low;

    initial clk = 0;
    always #5000 clk = ~clk;   // 10 us period

    initial begin
        $dumpfile("SBINIT_tb.vcd");
        $dumpvars(0, SBINIT_tb);
    end

    SBINIT #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) dut (.*);

    // ---------------- Helpers ----------------
    task check(input bit cond, input string msg);
        checks++;
        if (!cond) begin
            errors++;
            $display("[%0t] FAIL: %s", $time, msg);
        end else begin
            $display("[%0t] ok  : %s", $time, msg);
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
        sbinit_timeout_expired = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
    endtask

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

    // Drive DUT from IDLE all the way into S4 (done-handshake).
    task run_to_S4();
        wait (sb_det_pattern_req);
        repeat (MS_CYCLES + 5) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        repeat (5) @(posedge clk);
        iter_done <= 1'b1; @(posedge clk);
        iter_done <= 1'b0;
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        send_msg(SBINIT_Out_of_Reset);
    endtask

    // ---------------- Main ----------------
    initial begin
        errors = 0;
        checks = 0;
        $display("[%0t] === SBINIT TB START ===", $time);

        // -------- Scenario 1: happy path --------
        $display("\n[%0t] --- SCN 1: HAPPY PATH ---", $time);
        do_reset();
        sbinit_enable = 1;

        wait (sb_det_pattern_req);
        check(sbinit_pattern_mode, "S1: sbinit_pattern_mode high");
        check(sbinit_timer_enable, "S1: timer enabled while running");
        repeat (MS_CYCLES + 5) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk);
        sb_det_pattern_rcvd <= 1'b0;
        @(posedge clk);
        check(!sb_det_pattern_req, "S1: pattern_req drops after detect");

        wait (req_iter_count == 3'd4);
        check(sbinit_pattern_mode, "S2: pattern_mode still 1 in S2");
        repeat (5) @(posedge clk);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;

        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        check(!sbinit_pattern_mode, "S3: pattern_mode drops in S3");
        send_msg(SBINIT_Out_of_Reset);

        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);

        wait (sbinit_done);
        check(!sbinit_error,        "DONE: error must be low");
        check(!sbinit_timer_enable, "DONE: timer must drop");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // -------- Scenario 2: Step-5 duty cycle --------
        $display("\n[%0t] --- SCN 2: DUTY CYCLE ---", $time);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        t_high = 0;
        while (sb_det_pattern_req) begin
            @(posedge clk);
            t_high++;
        end
        t_low = 0;
        while (!sb_det_pattern_req) begin
            @(posedge clk);
            t_low++;
        end
        check(t_high >= MS_CYCLES-2 && t_high <= MS_CYCLES+2,
              $sformatf("DUTY: high=%0d ~= %0d cycles", t_high, MS_CYCLES));
        check(t_low  >= MS_CYCLES-2 && t_low  <= MS_CYCLES+2,
              $sformatf("DUTY: low =%0d ~= %0d cycles", t_low,  MS_CYCLES));
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // -------- Scenario 3: iter handshake --------
        $display("\n[%0t] --- SCN 3: ITER HANDSHAKE ---", $time);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        repeat (10) @(posedge clk);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk); sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        check(req_iter_count == 3'd4, "S2: req_iter_count == 4");
        repeat (20) @(posedge clk);
        check(req_iter_count == 3'd4, "S2: req_iter_count holds 4 until iter_done");
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        check(req_iter_count == 3'd0, "S3: req_iter_count back to 0");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // -------- Scenario 4: continuous Out_of_Reset until peer echoes --------
        $display("\n[%0t] --- SCN 4: OUT_OF_RESET PERSIST ---", $time);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk); sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        repeat (30) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset,
              "S3: keeps driving Out_of_Reset until peer responds");
        send_msg(SBINIT_Out_of_Reset);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // -------- Scenario 5: ltsm_rdy backpressure in S4 --------
        $display("\n[%0t] --- SCN 5: LTSM_RDY BACKPRESSURE ---", $time);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_req);
        repeat (20) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_req,
              "S4: keeps driving done_req while ltsm_rdy=0");
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        repeat (20) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp,
              "S4: keeps driving done_resp while ltsm_rdy=0");
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // -------- Scenario 6: partner done_req arrives before ours is accepted --------
        $display("\n[%0t] --- SCN 6: PARTNER DONE_REQ EARLY ---", $time);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        send_msg(SBINIT_done_req);
        repeat (5) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_done_req,
              "S4: ours not sent yet -> still drives done_req");
        accept_tx(SBINIT_done_req);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        accept_tx(SBINIT_done_resp);
        send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // -------- Scenario 7: partner done_resp arrives early --------
        $display("\n[%0t] --- SCN 7: PARTNER DONE_RESP EARLY ---", $time);
        do_reset();
        sbinit_enable = 1;
        run_to_S4();
        send_msg(SBINIT_done_resp);
        accept_tx(SBINIT_done_req);
        send_msg(SBINIT_done_req);
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_done_resp);
        accept_tx(SBINIT_done_resp);
        wait (sbinit_done);
        check(!sbinit_error, "S7: no error");
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // -------- Scenario 8: watchdog timeout -> TRAINERROR --------
        $display("\n[%0t] --- SCN 8: TIMEOUT ---", $time);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        repeat (10) @(posedge clk);
        check(sbinit_timer_enable, "TO: timer enabled during run");
        sbinit_timeout_expired <= 1'b1;
        wait (sbinit_error);
        check(!sbinit_done, "TO: done must be 0 in error");
        @(posedge clk);
        check(!sbinit_timer_enable, "TO: timer drops on error");
        sbinit_timeout_expired <= 1'b0;
        sbinit_enable = 0;
        repeat (10) @(posedge clk);

        // -------- Scenario 9: enable deassert -> IDLE --------
        $display("\n[%0t] --- SCN 9: DISABLE MIDWAY ---", $time);
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
        check(!sbinit_timer_enable, "IDLE: timer disabled");
        repeat (10) @(posedge clk);

        // -------- Scenario 10: unknown msg in S3 ignored --------
        $display("\n[%0t] --- SCN 10: UNKNOWN MSG IGNORED ---", $time);
        do_reset();
        sbinit_enable = 1;
        wait (sb_det_pattern_req);
        sb_det_pattern_rcvd <= 1'b1; @(posedge clk); sb_det_pattern_rcvd <= 1'b0;
        wait (req_iter_count == 3'd4);
        iter_done <= 1'b1; @(posedge clk); iter_done <= 1'b0;
        wait (sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset);
        send_msg(msg_no_e'(NOTHING));
        repeat (10) @(posedge clk);
        check(sb_tx_valid && sb_tx_msg_id == SBINIT_Out_of_Reset,
              "S3: stays driving Out_of_Reset on unknown msg");
        send_msg(SBINIT_Out_of_Reset);
        accept_tx(SBINIT_done_req);  send_msg(SBINIT_done_req);
        accept_tx(SBINIT_done_resp); send_msg(SBINIT_done_resp);
        wait (sbinit_done);
        sbinit_enable = 0;

        // -------- Summary --------
        $display("\n[%0t] === DONE: %0d checks, %0d errors ===", $time, checks, errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $finish;
    end

    // Hard sim timeout
    initial begin
        #500_000_000;
        $display("[%0t] HARD TIMEOUT — possible hang", $time);
        $finish;
    end

endmodule