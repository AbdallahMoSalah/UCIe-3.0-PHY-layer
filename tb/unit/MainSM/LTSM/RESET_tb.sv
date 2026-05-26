// Testbench for rtl/MainSM/LTSM/RESET.sv against UCIe 3.0 §4.5.3.1.
//
// Scaled clock: CLK_FRQ_HZ = 10_000 gives TIME_OUT_CYCLES = (10_000/1000) * 4
// = 40 cycles for the "4 ms" minimum dwell.  Clock period is 10 ns so each
// scenario completes in microseconds of wall time.

`timescale 1ns/1ps

module RESET_tb;

    // ---------------- Parameters ----------------
    localparam int CLK_FRQ_HZ      = 10_000;                 // scaled for fast sim
    localparam int TIME_OUT_MS     = 4;                      // matches RESET TIME_OUT
    localparam int DWELL_CYCLES    = (CLK_FRQ_HZ/1000) * TIME_OUT_MS; // = 40
    localparam real CLK_PERIOD     = 10.0;                   // ns

    // ---------------- DUT ports ----------------
    logic clk;
    logic rst_n;
    logic phy_start_ucie_link_training_ctrl_out;
    logic Adapter_training_req;
    logic sb_det_pattern_rcvd;
    logic RESET_enable;
    logic RESET_state_done;

    RESET #(.CLK_FRQ_HZ(CLK_FRQ_HZ)) dut (
        .clk                                  (clk),
        .rst_n                                (rst_n),
        .phy_start_ucie_link_training_ctrl_out(phy_start_ucie_link_training_ctrl_out),
        .Adapter_training_req                 (Adapter_training_req),
        .sb_det_pattern_rcvd                  (sb_det_pattern_rcvd),
        .RESET_enable                         (RESET_enable),
        .RESET_state_done                     (RESET_state_done)
    );

    // ---------------- Clock ----------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2.0) clk = ~clk;
    end

    // ---------------- Scoreboard ----------------
    int errors = 0;
    task automatic check(input bit cond, input string msg);
        if (!cond) begin
            $error("[%0t] FAIL: %s", $time, msg);
            errors++;
        end else begin
            $display("[%0t] PASS: %s", $time, msg);
        end
    endtask

    // ---------------- Helpers ----------------
    task automatic clear_triggers();
        phy_start_ucie_link_training_ctrl_out = 1'b0;
        Adapter_training_req                  = 1'b0;
        sb_det_pattern_rcvd                   = 1'b0;
    endtask

    task automatic do_async_reset();
        rst_n        = 1'b0;
        RESET_enable = 1'b0;
        clear_triggers();
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    // ---------------- Tests ----------------
    initial begin
        $display("==== RESET_tb start ====");
        $display("  DWELL_CYCLES = %0d", DWELL_CYCLES);

        do_async_reset();
        check(RESET_state_done === 1'b0, "after rst_n: RESET_state_done low (IDLE)");

        // ---- Scenario 1: spec §4.5.3.1 minimum 4 ms dwell honored even if trigger asserted early ----
        $display("\n-- Scenario 1: trigger early, must wait full 4 ms dwell --");
        RESET_enable                          = 1'b1;
        phy_start_ucie_link_training_ctrl_out = 1'b1; // trigger asserted from the very first cycle
        // Sample after IDLE->DWELL_4MS transition + ~80% of dwell: done must still be 0.
        repeat (DWELL_CYCLES - 5) @(posedge clk);
        #1;
        check(RESET_state_done === 1'b0,
              "done is low while still inside 4 ms dwell");

        // Now wait for done. The FSM goes DWELL_4MS -> WAIT_TRIGGER -> DONE_HOLD; since
        // the trigger is asserted, it should advance through WAIT_TRIGGER in 1 cycle.
        fork
            begin : wait_done_1
                wait (RESET_state_done === 1'b1);
            end
            begin : timeout_1
                repeat (DWELL_CYCLES + 20) @(posedge clk);
                $error("[%0t] Scenario 1: timed out waiting for RESET_state_done", $time);
                errors++;
            end
        join_any
        disable fork;
        check(RESET_state_done === 1'b1, "done asserted after 4 ms dwell + trigger");

        // ---- Scenario 2: done is held until RESET_enable deasserts ----
        $display("\n-- Scenario 2: done held until RESET_enable drops --");
        clear_triggers();
        repeat (20) @(posedge clk);
        check(RESET_state_done === 1'b1, "done still high while enable=1 and no triggers");

        @(negedge clk) RESET_enable = 1'b0;
        @(posedge clk); #1;
        check(RESET_state_done === 1'b0, "done deasserts after RESET_enable drops");

        // ---- Scenario 3: re-entry restarts the 4 ms dwell ----
        $display("\n-- Scenario 3: re-entry restarts 4 ms dwell --");
        @(negedge clk) RESET_enable = 1'b1;
        phy_start_ucie_link_training_ctrl_out = 1'b1;
        repeat (DWELL_CYCLES - 5) @(posedge clk); #1;
        check(RESET_state_done === 1'b0, "re-entry: done low during dwell");
        fork
            begin wait (RESET_state_done === 1'b1); end
            begin repeat (DWELL_CYCLES + 20) @(posedge clk); $error("re-entry timeout"); errors++; end
        join_any; disable fork;
        check(RESET_state_done === 1'b1, "re-entry: done asserted after second 4 ms dwell");

        // tear down
        @(negedge clk) RESET_enable = 1'b0; clear_triggers();
        @(posedge clk);

        // ---- Scenario 4: dwell completes but no trigger -> stay in WAIT_TRIGGER, done stays low ----
        $display("\n-- Scenario 4: dwell complete, no trigger, done stays low --");
        @(negedge clk) RESET_enable = 1'b1;
        clear_triggers();
        repeat (DWELL_CYCLES + 50) @(posedge clk); #1;
        check(RESET_state_done === 1'b0,
              "no trigger -> done stays low even after dwell complete");

        // Now drive Adapter_training_req — exit should happen via WAIT_TRIGGER->DONE_HOLD.
        @(negedge clk) Adapter_training_req = 1'b1;
        fork
            begin wait (RESET_state_done === 1'b1); end
            begin repeat (20) @(posedge clk); $error("trigger from WAIT_TRIGGER timed out"); errors++; end
        join_any; disable fork;
        check(RESET_state_done === 1'b1, "Adapter_training_req from WAIT_TRIGGER -> done");

        @(negedge clk) RESET_enable = 1'b0; clear_triggers();
        @(posedge clk);

        // ---- Scenario 5: each trigger source independently exits to DONE_HOLD ----
        begin : per_trigger
            static string names[3] = '{"phy_start_ucie_link_training_ctrl_out",
                                       "Adapter_training_req",
                                       "sb_det_pattern_rcvd"};
            for (int i = 0; i < 3; i++) begin
                $display("\n-- Scenario 5.%0d: exit via %s --", i, names[i]);
                @(negedge clk) RESET_enable = 1'b1;
                clear_triggers();
                // wait past dwell
                repeat (DWELL_CYCLES + 5) @(posedge clk);
                check(RESET_state_done === 1'b0, $sformatf("5.%0d: still no done (no trigger yet)", i));
                @(negedge clk);
                case (i)
                    0: phy_start_ucie_link_training_ctrl_out = 1'b1;
                    1: Adapter_training_req                  = 1'b1;
                    2: sb_det_pattern_rcvd                   = 1'b1;
                endcase
                fork
                    begin wait (RESET_state_done === 1'b1); end
                    begin repeat (20) @(posedge clk); $error("5.%0d trigger timeout", i); errors++; end
                join_any; disable fork;
                check(RESET_state_done === 1'b1, $sformatf("5.%0d: done after %s", i, names[i]));
                @(negedge clk) RESET_enable = 1'b0; clear_triggers();
                @(posedge clk);
            end
        end

        // ---- Scenario 6: dropping RESET_enable mid-dwell aborts, next entry needs full dwell again ----
        $display("\n-- Scenario 6: enable drop mid-dwell aborts; next entry restarts dwell --");
        @(negedge clk) RESET_enable = 1'b1;
        phy_start_ucie_link_training_ctrl_out = 1'b1;
        repeat (DWELL_CYCLES/2) @(posedge clk);
        check(RESET_state_done === 1'b0, "6: done low mid-dwell");
        @(negedge clk) RESET_enable = 1'b0;       // abort
        repeat (3) @(posedge clk); #1;
        check(RESET_state_done === 1'b0, "6: aborted -> still low");
        // re-enter; trigger still asserted; must wait the full new dwell
        @(negedge clk) RESET_enable = 1'b1;
        repeat (DWELL_CYCLES - 5) @(posedge clk); #1;
        check(RESET_state_done === 1'b0, "6: after re-entry, done still low during new dwell");
        fork
            begin wait (RESET_state_done === 1'b1); end
            begin repeat (DWELL_CYCLES + 20) @(posedge clk); $error("6: re-entry done timeout"); errors++; end
        join_any; disable fork;
        check(RESET_state_done === 1'b1, "6: done asserted after full re-entry dwell");
        @(negedge clk) RESET_enable = 1'b0; clear_triggers();
        @(posedge clk);

        // ---- Scenario 7: single-cycle trigger pulse during dwell must be latched ----
        // sb_det_pattern_rcvd (and the other triggers) can be a one-cycle pulse from
        // the SB block; the FSM must remember it through the 4 ms dwell and honor it
        // upon entering WAIT_TRIGGER.
        $display("\n-- Scenario 7: 1-cycle trigger pulse during dwell is latched --");
        @(negedge clk) RESET_enable = 1'b1;
        // wait a few cycles into the dwell, then issue a single-cycle pulse
        repeat (5) @(posedge clk);
        @(negedge clk) sb_det_pattern_rcvd = 1'b1;
        @(negedge clk) sb_det_pattern_rcvd = 1'b0;     // pulse cleared well before dwell ends
        // done must NOT assert before dwell completes
        repeat (DWELL_CYCLES - 10) @(posedge clk); #1;
        check(RESET_state_done === 1'b0,
              "7: latched pulse: done still low during dwell");
        // but it MUST assert shortly after dwell completes (WAIT_TRIGGER sees sticky)
        fork
            begin wait (RESET_state_done === 1'b1); end
            begin repeat (DWELL_CYCLES + 20) @(posedge clk); $error("7: latched pulse timeout"); errors++; end
        join_any; disable fork;
        check(RESET_state_done === 1'b1,
              "7: latched pulse exits via WAIT_TRIGGER once dwell ends");
        @(negedge clk) RESET_enable = 1'b0; clear_triggers();
        @(posedge clk);

        // ---- Scenario 7b: pulse on each trigger source survives the dwell ----
        $display("\n-- Scenario 7b: each trigger pulses 1 cycle during dwell, all latched --");
        begin : per_trigger_pulse
            static string pulse_names[3] = '{"phy_start_ucie_link_training_ctrl_out",
                                             "Adapter_training_req",
                                             "sb_det_pattern_rcvd"};
            for (int i = 0; i < 3; i++) begin
                @(negedge clk) RESET_enable = 1'b1;
                clear_triggers();
                repeat (3) @(posedge clk);                 // enter DWELL_4MS
                @(negedge clk);
                case (i)
                    0: phy_start_ucie_link_training_ctrl_out = 1'b1;
                    1: Adapter_training_req                  = 1'b1;
                    2: sb_det_pattern_rcvd                   = 1'b1;
                endcase
                @(negedge clk);
                clear_triggers();                          // 1-cycle pulse done
                fork
                    begin wait (RESET_state_done === 1'b1); end
                    begin repeat (DWELL_CYCLES + 20) @(posedge clk); $error("7b.%0d timeout", i); errors++; end
                join_any; disable fork;
                check(RESET_state_done === 1'b1,
                      $sformatf("7b.%0d: 1-cycle pulse on %s latched through dwell", i, pulse_names[i]));
                @(negedge clk) RESET_enable = 1'b0;
                @(posedge clk);
            end
        end

        // ---- Scenario 8: async rst_n returns FSM to IDLE ----
        $display("\n-- Scenario 8: async rst_n -> IDLE --");
        @(negedge clk) RESET_enable = 1'b1;
        phy_start_ucie_link_training_ctrl_out = 1'b1;
        fork
            begin wait (RESET_state_done === 1'b1); end
            begin repeat (DWELL_CYCLES + 20) @(posedge clk); $error("8: setup timeout"); errors++; end
        join_any; disable fork;
        check(RESET_state_done === 1'b1, "8: setup -> done high");
        // pulse rst_n low (async)
        rst_n = 1'b0;
        #(CLK_PERIOD * 1.5);
        check(RESET_state_done === 1'b0, "8: async rst_n -> done deasserts immediately");
        rst_n = 1'b1;
        @(posedge clk);

        // ---- Done ----
        $display("\n==== RESET_tb summary: %0d error(s) ====", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_PERIOD * DWELL_CYCLES * 200);
        $error("Global TB watchdog expired");
        $finish;
    end

endmodule
