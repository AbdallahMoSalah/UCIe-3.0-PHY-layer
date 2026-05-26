// Testbench for rtl/MainSM/LTSM/ACTIVE.sv against UCIe 3.0 §4.5.3.6.
//
// ACTIVE is a residency + exit-trigger detector.  Each exit trigger is latched
// in a sticky while in ACTIVE_RUN so single-cycle pulses survive until the
// state transitions to DONE_HOLD.  active_done is held until active_enable
// deasserts.

`timescale 1ns/1ps

module ACTIVE_tb;

    localparam real CLK_PERIOD = 10.0; // ns

    // ---------------- DUT ports ----------------
    logic clk;
    logic rst_n;
    logic active_enable;
    logic phyretrain_req;
    logic l1_req;
    logic l2_req;
    logic linkreset_req;
    logic linkerror_req;
    logic trainerror_req;
    logic active_done;

    ACTIVE dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .active_enable  (active_enable),
        .phyretrain_req (phyretrain_req),
        .l1_req         (l1_req),
        .l2_req         (l2_req),
        .linkreset_req  (linkreset_req),
        .linkerror_req  (linkerror_req),
        .trainerror_req (trainerror_req),
        .active_done    (active_done)
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

    task automatic clear_triggers();
        phyretrain_req = 1'b0;
        l1_req         = 1'b0;
        l2_req         = 1'b0;
        linkreset_req  = 1'b0;
        linkerror_req  = 1'b0;
        trainerror_req = 1'b0;
    endtask

    task automatic do_async_reset();
        rst_n         = 1'b0;
        active_enable = 1'b0;
        clear_triggers();
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    // ---------------- Tests ----------------
    initial begin
        $display("==== ACTIVE_tb start ====");

        do_async_reset();
        check(active_done === 1'b0, "after rst_n: active_done low (IDLE)");

        // ---- Scenario 1: residency — no trigger -> stay forever, done stays low ----
        $display("\n-- Scenario 1: residency, no trigger --");
        @(negedge clk) active_enable = 1'b1;
        clear_triggers();
        repeat (200) @(posedge clk); #1;
        check(active_done === 1'b0, "1: no trigger -> done stays low over long residency");

        // ---- Scenario 2: each trigger independently asserts done (level-driven) ----
        $display("\n-- Scenario 2: each trigger independently asserts done --");
        begin : per_trigger_level
            static string names[6] = '{"phyretrain_req", "l1_req", "l2_req",
                                       "linkreset_req", "linkerror_req", "trainerror_req"};
            for (int i = 0; i < 6; i++) begin
                do_async_reset();
                @(negedge clk) active_enable = 1'b1;
                repeat (3) @(posedge clk);
                check(active_done === 1'b0, $sformatf("2.%0d: in ACTIVE_RUN, done low pre-trigger", i));
                @(negedge clk);
                case (i)
                    0: phyretrain_req = 1'b1;
                    1: l1_req         = 1'b1;
                    2: l2_req         = 1'b1;
                    3: linkreset_req  = 1'b1;
                    4: linkerror_req  = 1'b1;
                    5: trainerror_req = 1'b1;
                endcase
                fork
                    begin wait (active_done === 1'b1); end
                    begin repeat (10) @(posedge clk); $error("2.%0d trigger timeout", i); errors++; end
                join_any; disable fork;
                check(active_done === 1'b1, $sformatf("2.%0d: done asserted on %s", i, names[i]));
                @(negedge clk) active_enable = 1'b0; clear_triggers();
                @(posedge clk); #1;
                check(active_done === 1'b0, $sformatf("2.%0d: done deasserts after enable drop", i));
            end
        end

        // ---- Scenario 3: 1-cycle pulse on each trigger is latched ----
        $display("\n-- Scenario 3: 1-cycle pulse on each trigger is latched --");
        begin : per_trigger_pulse
            static string names[6] = '{"phyretrain_req", "l1_req", "l2_req",
                                       "linkreset_req", "linkerror_req", "trainerror_req"};
            for (int i = 0; i < 6; i++) begin
                do_async_reset();
                @(negedge clk) active_enable = 1'b1;
                repeat (5) @(posedge clk);                // residency
                @(negedge clk);
                case (i)
                    0: phyretrain_req = 1'b1;
                    1: l1_req         = 1'b1;
                    2: l2_req         = 1'b1;
                    3: linkreset_req  = 1'b1;
                    4: linkerror_req  = 1'b1;
                    5: trainerror_req = 1'b1;
                endcase
                @(negedge clk) clear_triggers();           // 1-cycle pulse only
                fork
                    begin wait (active_done === 1'b1); end
                    begin repeat (10) @(posedge clk); $error("3.%0d pulse timeout", i); errors++; end
                join_any; disable fork;
                check(active_done === 1'b1, $sformatf("3.%0d: pulse on %s latched -> done", i, names[i]));
                @(negedge clk) active_enable = 1'b0;
                @(posedge clk);
            end
        end

        // ---- Scenario 4: done held until active_enable deasserts ----
        $display("\n-- Scenario 4: done held until active_enable drops --");
        do_async_reset();
        @(negedge clk) active_enable = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk) phyretrain_req = 1'b1;
        @(negedge clk) phyretrain_req = 1'b0;
        wait (active_done === 1'b1);
        repeat (50) @(posedge clk);                       // sit in DONE_HOLD a long time
        check(active_done === 1'b1, "4: done remains high in DONE_HOLD");
        @(negedge clk) active_enable = 1'b0;
        @(posedge clk); #1;
        check(active_done === 1'b0, "4: done drops after enable=0");

        // ---- Scenario 5: stickies cleared on IDLE re-entry; new dwell honored ----
        $display("\n-- Scenario 5: re-entry clears stickies --");
        do_async_reset();
        @(negedge clk) active_enable = 1'b1;
        @(negedge clk) l2_req = 1'b1;
        @(negedge clk) l2_req = 1'b0;
        wait (active_done === 1'b1);
        @(negedge clk) active_enable = 1'b0;              // back to IDLE -> clear stickies
        @(posedge clk); #1;
        check(active_done === 1'b0, "5: done cleared after enable drop");
        // re-enter with no trigger; done must stay low
        @(negedge clk) active_enable = 1'b1;
        repeat (50) @(posedge clk); #1;
        check(active_done === 1'b0, "5: re-entry with no trigger -> done stays low");
        // fresh trigger fires
        @(negedge clk) l1_req = 1'b1;
        wait (active_done === 1'b1);
        check(active_done === 1'b1, "5: fresh trigger after re-entry -> done");
        @(negedge clk) active_enable = 1'b0; clear_triggers();
        @(posedge clk);

        // ---- Scenario 6: trigger arriving while active_enable=0 must NOT linger ----
        $display("\n-- Scenario 6: trigger while disabled is not retained --");
        do_async_reset();
        // enable low; pulse a trigger
        @(negedge clk) phyretrain_req = 1'b1;
        @(negedge clk) phyretrain_req = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk) active_enable = 1'b1;              // now enable
        repeat (50) @(posedge clk); #1;
        check(active_done === 1'b0,
              "6: pulse while disabled is NOT carried into enabled run");
        @(negedge clk) active_enable = 1'b0;
        @(posedge clk);

        // ---- Scenario 7: multiple concurrent triggers — single done assertion ----
        $display("\n-- Scenario 7: concurrent triggers (any/all) -> done --");
        do_async_reset();
        @(negedge clk) active_enable = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk) begin
            phyretrain_req = 1'b1;
            linkerror_req  = 1'b1;
            l1_req         = 1'b1;
        end
        wait (active_done === 1'b1);
        check(active_done === 1'b1, "7: any of several concurrent triggers asserts done");
        @(negedge clk) active_enable = 1'b0; clear_triggers();
        @(posedge clk);

        // ---- Scenario 8: async rst_n returns FSM to IDLE ----
        $display("\n-- Scenario 8: async rst_n -> IDLE --");
        @(negedge clk) active_enable = 1'b1;
        @(negedge clk) trainerror_req = 1'b1;
        wait (active_done === 1'b1);
        rst_n = 1'b0;
        #(CLK_PERIOD * 1.5);
        check(active_done === 1'b0, "8: async rst_n -> done deasserts immediately");
        rst_n = 1'b1;
        @(posedge clk);

        // ---- Done ----
        $display("\n==== ACTIVE_tb summary: %0d error(s) ====", errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED");
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_PERIOD * 100000);
        $error("Global TB watchdog expired");
        $finish;
    end

endmodule
