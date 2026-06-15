// Testbench for rtl/MainSM/LTSM/L1.sv (UCIe 3.0 LTSM L1 state).
//
// Current L1 contract (black-box):
//   inputs : clk, rst_n, l1_enable, rdi_state_sts (RDI_state)
//   outputs: l1_done, l1_error
//
//   FSM: IDLE --(l1_enable)--> L1_RUN
//        L1_RUN --(rdi_state_sts==Active)--> LINK_SPEED    (l1_done=1)
//        L1_RUN --(rdi_state_sts==LinkError)--> TRAIN_ERROR(l1_error=1)
//        LINK_SPEED / TRAIN_ERROR --(!l1_enable)--> IDLE
//        any state --(!l1_enable)--> IDLE
//   l1_done  = (state == LINK_SPEED)   -- held until l1_enable deasserts
//   l1_error = (state == TRAIN_ERROR)  -- held until l1_enable deasserts
//   Active has priority over LinkError in L1_RUN. LINK_SPEED and TRAIN_ERROR
//   are distinct states, so l1_done and l1_error are mutually exclusive.

`timescale 1ns/1ps

module L1_tb;
    import RDI_SM_pkg::*;

    localparam real CLK_PERIOD = 10.0; // ns

    // ---------------- DUT ports ----------------
    logic     clk;
    logic     rst_n;
    logic     l1_enable;
    RDI_state rdi_state_sts;
    logic     l1_done;
    logic     l1_error;

    L1 dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .l1_enable     (l1_enable),
        .rdi_state_sts (rdi_state_sts),
        .l1_done       (l1_done),
        .l1_error      (l1_error)
    );

    // Clock
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2.0) clk = ~clk;
    end

    // Scoreboard
    int errors = 0;
    task automatic check(input bit cond, input string msg);
        if (!cond) begin
            $error("[%0t] FAIL: %s", $time, msg);
            errors++;
        end else begin
            $display("[%0t] PASS: %s", $time, msg);
        end
    endtask

    // Invariant: done (LINK_SPEED) and error (TRAIN_ERROR) are distinct states,
    // so they must never both be asserted in the same cycle.
    bit done_error_both = 1'b0;
    always @(posedge clk)
        if (l1_done === 1'b1 && l1_error === 1'b1) done_error_both = 1'b1;

    task automatic do_async_reset();
        rst_n         = 1'b0;
        l1_enable     = 1'b0;
        rdi_state_sts = Reset;        // any non-Active, non-LinkError value
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    // Wait for l1_done with a bounded timeout.
    task automatic wait_done(input int max_cycles, input string ctx);
        fork
            begin wait (l1_done === 1'b1); end
            begin repeat (max_cycles) @(posedge clk);
                  $error("[%0t] %s: timed out waiting for l1_done", $time, ctx);
                  errors++; end
        join_any; disable fork;
    endtask

    // Wait for l1_error with a bounded timeout.
    task automatic wait_error(input int max_cycles, input string ctx);
        fork
            begin wait (l1_error === 1'b1); end
            begin repeat (max_cycles) @(posedge clk);
                  $error("[%0t] %s: timed out waiting for l1_error", $time, ctx);
                  errors++; end
        join_any; disable fork;
    endtask

    // ---------------- Tests ----------------
    initial begin
        $display("==== L1_tb start ====");

        do_async_reset();
        check(l1_done  === 1'b0, "after rst_n: l1_done low (IDLE)");
        check(l1_error === 1'b0, "after rst_n: l1_error low");

        // ---- Scenario 1: residency, no trigger ----
        $display("\n-- Scenario 1: residency in L1_RUN, no Active --");
        @(negedge clk) l1_enable = 1'b1;
        rdi_state_sts = Reset;
        repeat (200) @(posedge clk); #1;
        check(l1_done  === 1'b0, "1: no Active -> done stays low");
        check(l1_error === 1'b0, "1: no LinkError -> error stays low");
        @(negedge clk) l1_enable = 1'b0;
        @(posedge clk);

        // ---- Scenario 2: Active asserts done ----
        $display("\n-- Scenario 2: rdi_state_sts==Active -> done --");
        do_async_reset();
        @(negedge clk) l1_enable = 1'b1;
        repeat (3) @(posedge clk); #1;
        check(l1_done === 1'b0, "2: in L1_RUN, done low pre-trigger");
        @(negedge clk) rdi_state_sts = Active;
        wait_done(10, "2");
        check(l1_done  === 1'b1, "2: done asserted on Active (LINK_SPEED)");
        check(l1_error === 1'b0, "2: error low on done path");

        // ---- Scenario 3: done held when trigger deasserts ----
        $display("\n-- Scenario 3: done held when Active deasserts --");
        @(negedge clk) rdi_state_sts = Reset;     // leave Active
        repeat (50) @(posedge clk); #1;
        check(l1_done === 1'b1, "3: done held in LINK_SPEED after Active drops");

        // ---- Scenario 4: exit on enable drop ----
        $display("\n-- Scenario 4: l1_enable drop -> IDLE --");
        @(negedge clk) l1_enable = 1'b0;
        @(posedge clk); #1;
        check(l1_done === 1'b0, "4: done drops after enable=0");

        // ---- Scenario 5: enable=0 overrides Active ----
        $display("\n-- Scenario 5: Active while disabled is ignored --");
        do_async_reset();
        @(negedge clk) rdi_state_sts = Active;    // but enable stays 0
        repeat (50) @(posedge clk); #1;
        check(l1_done === 1'b0, "5: Active with enable=0 -> done stays low");

        // ---- Scenario 6: drop enable from L1_RUN (pre-trigger) ----
        $display("\n-- Scenario 6: drop enable from L1_RUN --");
        do_async_reset();
        @(negedge clk) l1_enable = 1'b1;
        rdi_state_sts = Reset;
        repeat (3) @(posedge clk);
        @(negedge clk) l1_enable = 1'b0;
        @(posedge clk); #1;
        check(l1_done === 1'b0, "6: enable drop from L1_RUN -> done stays low");

        // ---- Scenario 7: single-cycle Active pulse is captured ----
        $display("\n-- Scenario 7: 1-cycle Active pulse is captured --");
        do_async_reset();
        @(negedge clk) l1_enable = 1'b1;
        rdi_state_sts = Reset;
        repeat (3) @(posedge clk);
        @(negedge clk) rdi_state_sts = Active;    // held across exactly one posedge
        @(negedge clk) rdi_state_sts = Reset;
        wait_done(10, "7");
        check(l1_done === 1'b1, "7: 1-cycle Active pulse -> LINK_SPEED, done held");
        @(negedge clk) l1_enable = 1'b0;
        @(posedge clk);

        // ---- Scenario 8: re-entry ----
        $display("\n-- Scenario 8: re-entry after disable --");
        do_async_reset();
        @(negedge clk) l1_enable = 1'b1;
        @(negedge clk) rdi_state_sts = Active;
        wait_done(10, "8a");
        @(negedge clk) l1_enable = 1'b0;
        @(posedge clk); #1;
        check(l1_done === 1'b0, "8: done cleared after enable drop");
        @(negedge clk) begin l1_enable = 1'b1; rdi_state_sts = Reset; end
        repeat (30) @(posedge clk); #1;
        check(l1_done === 1'b0, "8: re-entry with no Active -> done stays low");
        @(negedge clk) rdi_state_sts = Active;
        wait_done(10, "8b");
        check(l1_done === 1'b1, "8: fresh Active after re-entry -> done");
        @(negedge clk) l1_enable = 1'b0;
        @(posedge clk);

        // ---- Scenario 9: async rst_n mid-LINK_SPEED ----
        $display("\n-- Scenario 9: async rst_n -> IDLE --");
        do_async_reset();
        @(negedge clk) l1_enable = 1'b1;
        @(negedge clk) rdi_state_sts = Active;
        wait_done(10, "9");
        rst_n = 1'b0;
        #(CLK_PERIOD * 1.5);
        check(l1_done === 1'b0, "9: async rst_n -> done deasserts immediately");
        rst_n = 1'b1;
        @(posedge clk);

        // ---- Scenario 10: LinkError -> TRAIN_ERROR (error asserts) ----
        $display("\n-- Scenario 10: rdi_state_sts==LinkError -> error --");
        do_async_reset();
        @(negedge clk) l1_enable = 1'b1;
        rdi_state_sts = Reset;
        repeat (3) @(posedge clk); #1;
        check(l1_error === 1'b0, "10: in L1_RUN, error low pre-trigger");
        @(negedge clk) rdi_state_sts = LinkError;
        wait_error(10, "10");
        check(l1_error === 1'b1, "10: error asserted on LinkError (TRAIN_ERROR)");
        check(l1_done  === 1'b0, "10: done stays low on error path");

        // ---- Scenario 11: error held when LinkError deasserts, exits on enable drop ----
        $display("\n-- Scenario 11: error held, exits on enable drop --");
        @(negedge clk) rdi_state_sts = Reset;     // leave LinkError; state is sticky
        repeat (50) @(posedge clk); #1;
        check(l1_error === 1'b1, "11: error held in TRAIN_ERROR after LinkError drops");
        check(l1_done  === 1'b0, "11: done still low while in TRAIN_ERROR");
        @(negedge clk) l1_enable = 1'b0;
        @(posedge clk); #1;
        check(l1_error === 1'b0, "11: error drops after enable=0 (back to IDLE)");

        // ---- Scenario 12: single-cycle LinkError pulse is captured ----
        $display("\n-- Scenario 12: 1-cycle LinkError pulse is captured --");
        do_async_reset();
        @(negedge clk) l1_enable = 1'b1;
        rdi_state_sts = Reset;
        repeat (3) @(posedge clk);
        @(negedge clk) rdi_state_sts = LinkError; // held across exactly one posedge
        @(negedge clk) rdi_state_sts = Reset;
        wait_error(10, "12");
        check(l1_error === 1'b1, "12: 1-cycle LinkError pulse -> TRAIN_ERROR, error held");
        @(negedge clk) l1_enable = 1'b0;
        @(posedge clk);

        // ---- Final: done/error mutual-exclusion invariant ----
        check(done_error_both === 1'b0,
              "INV: l1_done and l1_error never both high");

        $display("\n==== L1_tb summary: %0d error(s) ====", errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 100000);
        $error("Global TB watchdog expired");
        $finish;
    end

endmodule
