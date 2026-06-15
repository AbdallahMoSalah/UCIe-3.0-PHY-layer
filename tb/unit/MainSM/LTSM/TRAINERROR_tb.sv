// Testbench for rtl/MainSM/LTSM/TRAINERROR.sv (UCIe 3.0 LTSM TRAINERROR state).
//
// Current TRAINERROR contract (black-box):
//   inputs : clk, rst_n, trainerror_enable, rdi_state_sts (RDI_state)
//   outputs: trainerror_done
//
//   FSM: IDLE --(trainerror_enable)--> HOLD
//        HOLD --(rdi_state_sts != LinkError)--> DONE
//        DONE: terminal (only async rst_n leaves it)
//   trainerror_done = (state == DONE)
//
//   Notable contract points (differ from L1/L2):
//     - DONE is TERMINAL: once asserted, trainerror_done is held regardless of
//       trainerror_enable.  Only async rst_n returns the FSM to IDLE.
//     - There is no exit-on-enable-drop: dropping trainerror_enable in HOLD/DONE
//       does NOT return to IDLE.
//     - HOLD is gated by rdi_state_sts: while RDI is in LinkError the FSM waits
//       in HOLD; it advances to DONE the first cycle RDI is any other state.

`timescale 1ns/1ps

module TRAINERROR_tb;
    import RDI_SM_pkg::*;

    localparam real CLK_PERIOD = 10.0; // ns

    // ---------------- DUT ports ----------------
    logic     clk;
    logic     rst_n;
    logic     trainerror_enable;
    RDI_state rdi_state_sts;
    logic     trainerror_done;

    TRAINERROR dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .trainerror_enable (trainerror_enable),
        .rdi_state_sts     (rdi_state_sts),
        .trainerror_done   (trainerror_done)
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

    // Invariant: trainerror_done must never go high while the FSM has not been
    // enabled out of reset.  Tracked as a sticky violation flag.
    bit done_without_enable = 1'b0;
    bit ever_enabled        = 1'b0;
    always @(posedge clk) begin
        if (trainerror_enable === 1'b1) ever_enabled = 1'b1;
        if (trainerror_done === 1'b1 && ever_enabled === 1'b0)
            done_without_enable = 1'b1;
    end

    task automatic do_async_reset();
        rst_n             = 1'b0;
        trainerror_enable = 1'b0;
        rdi_state_sts     = Reset;     // any non-LinkError value
        ever_enabled      = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    // Wait for trainerror_done with a bounded timeout.
    task automatic wait_done(input int max_cycles, input string ctx);
        fork
            begin wait (trainerror_done === 1'b1); end
            begin repeat (max_cycles) @(posedge clk);
                  $error("[%0t] %s: timed out waiting for trainerror_done", $time, ctx);
                  errors++; end
        join_any; disable fork;
    endtask

    // ---------------- Tests ----------------
    initial begin
        $display("==== TRAINERROR_tb start ====");

        do_async_reset();
        check(trainerror_done === 1'b0, "after rst_n: done low (IDLE)");

        // ---- Scenario 1: enable + no LinkError -> advance to DONE ----
        $display("\n-- Scenario 1: enable, RDI not LinkError -> done --");
        do_async_reset();
        rdi_state_sts = Active;        // not LinkError
        @(negedge clk) trainerror_enable = 1'b1;
        check(trainerror_done === 1'b0, "1: done low immediately after enable");
        wait_done(10, "1");
        check(trainerror_done === 1'b1, "1: done asserted (reached DONE)");

        // ---- Scenario 2: DONE is terminal, held when enable drops ----
        $display("\n-- Scenario 2: DONE held after enable drops --");
        @(negedge clk) trainerror_enable = 1'b0;   // drop enable while in DONE
        repeat (50) @(posedge clk); #1;
        check(trainerror_done === 1'b1, "2: done held in DONE after enable=0 (terminal)");
        // RDI changes must not disturb a terminal DONE either.
        @(negedge clk) rdi_state_sts = LinkError;
        repeat (10) @(posedge clk); #1;
        check(trainerror_done === 1'b1, "2: done held in DONE despite RDI->LinkError");

        // ---- Scenario 3: enable=0 -> stays in IDLE ----
        $display("\n-- Scenario 3: no enable -> stays IDLE --");
        do_async_reset();
        rdi_state_sts = Active;        // not LinkError, but no enable
        repeat (50) @(posedge clk); #1;
        check(trainerror_done === 1'b0, "3: no enable -> done stays low (IDLE)");

        // ---- Scenario 4: LinkError gate holds in HOLD ----
        $display("\n-- Scenario 4: RDI LinkError gate holds in HOLD --");
        do_async_reset();
        rdi_state_sts = LinkError;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (50) @(posedge clk); #1;
        check(trainerror_done === 1'b0, "4: done held low while RDI in LinkError (HOLD)");
        @(negedge clk) rdi_state_sts = Active;   // clear LinkError
        wait_done(10, "4");
        check(trainerror_done === 1'b1, "4: done asserts after RDI leaves LinkError");

        // ---- Scenario 5: single-cycle enable pulse captured in IDLE ----
        $display("\n-- Scenario 5: 1-cycle enable pulse captured --");
        do_async_reset();
        rdi_state_sts = Active;
        @(negedge clk) trainerror_enable = 1'b1;  // sampled at next posedge: IDLE->HOLD
        @(negedge clk) trainerror_enable = 1'b0;  // already in HOLD; enable no longer needed
        wait_done(10, "5");
        check(trainerror_done === 1'b1, "5: 1-cycle enable pulse -> DONE (no exit on drop)");

        // ---- Scenario 6: single-cycle LinkError clear advances HOLD ----
        $display("\n-- Scenario 6: 1-cycle non-LinkError clears the gate --");
        do_async_reset();
        rdi_state_sts = LinkError;
        @(negedge clk) trainerror_enable = 1'b1;
        repeat (5) @(posedge clk);                 // park in HOLD
        check(trainerror_done === 1'b0, "6: parked in HOLD, done low");
        @(negedge clk) rdi_state_sts = Active;     // one cycle of non-LinkError
        @(negedge clk) rdi_state_sts = LinkError;  // back to LinkError
        wait_done(10, "6");
        check(trainerror_done === 1'b1, "6: 1-cycle non-LinkError advances HOLD->DONE");

        // ---- Scenario 7: async rst_n returns FSM to IDLE ----
        $display("\n-- Scenario 7: async rst_n -> IDLE --");
        do_async_reset();
        rdi_state_sts = Active;
        @(negedge clk) trainerror_enable = 1'b1;
        wait_done(10, "7");
        check(trainerror_done === 1'b1, "7: done high pre-reset");
        rst_n = 1'b0;
        #(CLK_PERIOD * 1.5);
        check(trainerror_done === 1'b0, "7: async rst_n -> done deasserts immediately");
        rst_n = 1'b1;
        @(posedge clk);

        // ---- Scenario 8: clean re-entry after reset ----
        $display("\n-- Scenario 8: re-entry after reset --");
        do_async_reset();
        rdi_state_sts = Active;
        @(negedge clk) trainerror_enable = 1'b1;
        wait_done(10, "8");
        check(trainerror_done === 1'b1, "8: fresh run after reset reaches DONE");
        @(negedge clk) trainerror_enable = 1'b0;
        @(posedge clk);

        // ---- Final: never asserted done before being enabled ----
        check(done_without_enable === 1'b0,
              "INV: trainerror_done never high before enable");

        $display("\n==== TRAINERROR_tb summary: %0d error(s) ====", errors);
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
