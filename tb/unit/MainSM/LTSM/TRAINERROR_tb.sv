// Testbench for rtl/MainSM/LTSM/TRAINERROR.sv against UCIe 3.0 §4.5.3.8.
//
// Scaled clock: CLK_FRQ_HZ=10_000 -> 8 ms watchdog = 80 cycles, so timeout
// scenarios complete in microseconds.  TX-content observation uses the same
// always-on sticky pattern proved on PHYRETRAIN.

`timescale 1ns/1ps

module TRAINERROR_tb;
    import UCIe_pkg::*;

    localparam int  CLK_FRQ_HZ      = 10_000;
    localparam int  TIME_OUT_MS     = 8;
    localparam int  TIMEOUT_CYCLES  = (CLK_FRQ_HZ/1000) * TIME_OUT_MS; // 80
    localparam real CLK_PERIOD      = 10.0;

    // ---------------- DUT ports ----------------
    logic        clk;
    logic        rst_n;
    logic        trainerror_enable;
    logic        is_initiator;
    logic        skip_handshake;
    logic        rdi_link_error;
    logic        trainerror_done;

    logic        tx_sb_msg_valid;
    msg_no_e     tx_sb_msg;
    logic [15:0] tx_msginfo;
    logic        ltsm_rdy;

    logic        rx_sb_msg_valid;
    msg_no_e     rx_sb_msg;
    logic [15:0] rx_msginfo;

    TRAINERROR #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .trainerror_enable  (trainerror_enable),
        .is_initiator       (is_initiator),
        .skip_handshake     (skip_handshake),
        .rdi_link_error     (rdi_link_error),
        .trainerror_done    (trainerror_done),
        .tx_sb_msg_valid    (tx_sb_msg_valid),
        .tx_sb_msg          (tx_sb_msg),
        .tx_msginfo         (tx_msginfo),
        .ltsm_rdy           (ltsm_rdy),
        .rx_sb_msg_valid    (rx_sb_msg_valid),
        .rx_sb_msg          (rx_sb_msg),
        .rx_msginfo         (rx_msginfo)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2.0) clk = ~clk;
    end

    // ---------------- Scoreboard ----------------
    int errors = 0;
    task automatic check(input bit cond, input string msg);
        if (!cond) begin $error("[%0t] FAIL: %s", $time, msg); errors++; end
        else        $display("[%0t] PASS: %s", $time, msg);
    endtask

    // ---------------- Always-on TX observers ----------------
    // Cleared by rst_n=0 (do_async_reset() asserts rst_n=0).
    logic saw_tx_req;
    logic saw_tx_rsp;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_tx_req <= 1'b0;
            saw_tx_rsp <= 1'b0;
        end else if (tx_sb_msg_valid && ltsm_rdy) begin
            if (tx_sb_msg == TRAINERROR_Entry_req ) saw_tx_req <= 1'b1;
            if (tx_sb_msg == TRAINERROR_Entry_resp) saw_tx_rsp <= 1'b1;
        end
    end

    // ---------------- Partner driver ----------------
    task automatic init_rx();
        rx_sb_msg_valid = 1'b0;
        rx_sb_msg       = msg_no_e'(NOTHING);
        rx_msginfo      = 16'h0000;
    endtask

    task automatic send_partner_req();
        @(negedge clk);
        rx_sb_msg       = TRAINERROR_Entry_req;
        rx_sb_msg_valid = 1'b1;
        @(negedge clk);
        rx_sb_msg_valid = 1'b0;
        rx_sb_msg       = msg_no_e'(NOTHING);
    endtask

    task automatic send_partner_rsp();
        @(negedge clk);
        rx_sb_msg       = TRAINERROR_Entry_resp;
        rx_sb_msg_valid = 1'b1;
        @(negedge clk);
        rx_sb_msg_valid = 1'b0;
        rx_sb_msg       = msg_no_e'(NOTHING);
    endtask

    task automatic do_async_reset();
        rst_n             = 1'b0;
        trainerror_enable = 1'b0;
        is_initiator      = 1'b0;
        skip_handshake    = 1'b0;
        rdi_link_error    = 1'b0;
        ltsm_rdy          = 1'b1;
        init_rx();
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    task automatic wait_done(input int max_cycles, input string label);
        fork
            begin wait (trainerror_done === 1'b1); end
            begin
                repeat (max_cycles) @(posedge clk);
                $error("[%s] timeout waiting for done", label);
                errors++;
            end
        join_any
        disable fork;
    endtask

    // ---------------- Tests ----------------
    initial begin
        $display("==== TRAINERROR_tb start ====");
        $display("  TIMEOUT_CYCLES = %0d", TIMEOUT_CYCLES);

        do_async_reset();
        check(trainerror_done === 1'b0, "after rst_n: done low (IDLE)");

        // ---- Scenario 1: initiator path, partner responds ----
        $display("\n-- Scenario 1: initiator path --");
        do_async_reset();
        is_initiator = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (3) @(posedge clk);
        send_partner_rsp();                                // partner answers our req
        wait_done(TIMEOUT_CYCLES + 20, "1");
        check(trainerror_done === 1'b1, "1: done asserted");
        check(saw_tx_req      === 1'b1, "1: DUT sent Entry_req");
        check(saw_tx_rsp      === 1'b0, "1: DUT did NOT send Entry_resp (no partner req)");
        @(negedge clk) trainerror_enable = 1'b0; @(posedge clk);

        // ---- Scenario 2: receiver path, partner sends req, DUT must respond ----
        $display("\n-- Scenario 2: receiver path --");
        do_async_reset();
        is_initiator = 1'b0;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (3) @(posedge clk);
        send_partner_req();                                // partner initiates
        wait_done(TIMEOUT_CYCLES + 20, "2");
        check(trainerror_done === 1'b1, "2: done asserted");
        check(saw_tx_req      === 1'b0, "2: DUT did NOT send Entry_req (not initiator)");
        check(saw_tx_rsp      === 1'b1, "2: DUT sent Entry_resp in response to partner req");
        @(negedge clk) trainerror_enable = 1'b0; @(posedge clk);

        // ---- Scenario 3: skip_handshake + no linkerror -> straight to done ----
        $display("\n-- Scenario 3: skip_handshake, no linkerror --");
        do_async_reset();
        skip_handshake = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        wait_done(10, "3");
        check(trainerror_done === 1'b1, "3: done asserted quickly with skip_handshake");
        check(saw_tx_req      === 1'b0, "3: no TX traffic");
        check(saw_tx_rsp      === 1'b0, "3: no TX traffic");
        @(negedge clk) trainerror_enable = 1'b0; @(posedge clk);

        // ---- Scenario 4: skip_handshake + rdi_link_error held -> wait, then clear ----
        $display("\n-- Scenario 4: skip_handshake + RDI LinkError gate --");
        do_async_reset();
        skip_handshake = 1'b1;
        rdi_link_error = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (50) @(posedge clk); #1;
        check(trainerror_done === 1'b0, "4: done held low while RDI in LinkError");
        @(negedge clk) rdi_link_error = 1'b0;
        wait_done(10, "4");
        check(trainerror_done === 1'b1, "4: done asserts after RDI clears LinkError");
        @(negedge clk) trainerror_enable = 1'b0; @(posedge clk);

        // ---- Scenario 5: initiator + no partner response -> 8 ms timeout fallback ----
        $display("\n-- Scenario 5: initiator, no response, 8 ms timeout --");
        do_async_reset();
        is_initiator = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        // Wait close to timeout; ensure not yet done
        repeat (TIMEOUT_CYCLES - 10) @(posedge clk); #1;
        check(trainerror_done === 1'b0, "5: done still low before 8 ms timeout");
        // Now wait for timeout-driven done
        wait_done(40, "5");
        check(trainerror_done === 1'b1, "5: done asserts on 8 ms timeout despite no partner response");
        check(saw_tx_req      === 1'b1, "5: DUT did send Entry_req");
        check(saw_tx_rsp      === 1'b0, "5: DUT did NOT send Entry_resp");
        @(negedge clk) trainerror_enable = 1'b0; @(posedge clk);

        // ---- Scenario 6: simultaneous role -> initiator AND receives partner req ----
        $display("\n-- Scenario 6: simultaneous initiator + receiver --");
        do_async_reset();
        is_initiator = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (3) @(posedge clk);
        send_partner_req();             // partner also initiated; DUT must respond too
        repeat (3) @(posedge clk);
        send_partner_rsp();             // partner's response to our req
        wait_done(TIMEOUT_CYCLES + 20, "6");
        check(trainerror_done === 1'b1, "6: done asserted");
        check(saw_tx_req      === 1'b1, "6: DUT sent Entry_req (initiator)");
        check(saw_tx_rsp      === 1'b1, "6: DUT also sent Entry_resp (to partner's req)");
        @(negedge clk) trainerror_enable = 1'b0; @(posedge clk);

        // ---- Scenario 7: handshake completes but RDI in LinkError -> stays in TRAINERROR ----
        $display("\n-- Scenario 7: handshake done + RDI LinkError gate --");
        do_async_reset();
        is_initiator   = 1'b1;
        rdi_link_error = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (3) @(posedge clk);
        send_partner_rsp();
        // handshake should now be complete, but linkerror holds us in LINKERROR_GATE
        repeat (50) @(posedge clk); #1;
        check(trainerror_done === 1'b0, "7: handshake done but rdi_link_error holds us");
        @(negedge clk) rdi_link_error = 1'b0;
        wait_done(10, "7");
        check(trainerror_done === 1'b1, "7: done after RDI clears LinkError");
        @(negedge clk) trainerror_enable = 1'b0; @(posedge clk);

        // ---- Scenario 8: done held until trainerror_enable drops ----
        $display("\n-- Scenario 8: done held until enable drops --");
        do_async_reset();
        skip_handshake = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        wait_done(10, "8");
        repeat (50) @(posedge clk);
        check(trainerror_done === 1'b1, "8: done remains high in DONE_HOLD");
        @(negedge clk) trainerror_enable = 1'b0;
        @(posedge clk); #1;
        check(trainerror_done === 1'b0, "8: done drops after enable=0");

        // ---- Scenario 9: re-entry restarts handshake ----
        $display("\n-- Scenario 9: re-entry restarts handshake --");
        do_async_reset();
        is_initiator = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (3) @(posedge clk); send_partner_rsp();
        wait_done(TIMEOUT_CYCLES + 20, "9.first");
        check(trainerror_done === 1'b1, "9.first: done asserted");
        @(negedge clk) trainerror_enable = 1'b0;
        @(posedge clk); #1;
        check(trainerror_done === 1'b0, "9: done cleared on enable drop");
        // re-enter as receiver
        do_async_reset();
        is_initiator = 1'b0;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (3) @(posedge clk); send_partner_req();
        wait_done(TIMEOUT_CYCLES + 20, "9.second");
        check(trainerror_done === 1'b1, "9.second: done asserted on re-entry");
        check(saw_tx_rsp      === 1'b1, "9.second: receiver path TX observed");
        @(negedge clk) trainerror_enable = 1'b0; @(posedge clk);

        // ---- Scenario 10: async rst_n returns FSM to IDLE ----
        $display("\n-- Scenario 10: async rst_n -> IDLE --");
        do_async_reset();
        skip_handshake = 1'b1;
        @(negedge clk) trainerror_enable = 1'b1;
        wait_done(10, "10.setup");
        check(trainerror_done === 1'b1, "10: setup done high");
        rst_n = 1'b0;
        #(CLK_PERIOD * 1.5);
        check(trainerror_done === 1'b0, "10: async rst_n -> done deasserts immediately");
        rst_n = 1'b1;
        @(posedge clk);

        $display("\n==== TRAINERROR_tb summary: %0d error(s) ====", errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 200000);
        $error("Global TB watchdog expired");
        $finish;
    end

endmodule
