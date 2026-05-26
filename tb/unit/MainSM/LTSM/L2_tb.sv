// Testbench for rtl/MainSM/LTSM/L2.sv against UCIe 3.0 §4.5.3.9.
//
// L2 is a residency + exit-trigger detector.  L2SPD is a project-skipped
// feature; only the basic non-L2SPD flow is exercised.  Exit destination
// (RESET) is the top controller's concern.

`timescale 1ns/1ps

module L2_tb;

    localparam real CLK_PERIOD = 10.0; // ns

    // ---------------- DUT ports ----------------
    logic clk;
    logic rst_n;
    logic l2_enable;
    logic local_active_req;
    logic remote_l2_exit_req;
    logic l2_done;

    L2 dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .l2_enable          (l2_enable),
        .local_active_req   (local_active_req),
        .remote_l2_exit_req (remote_l2_exit_req),
        .l2_done            (l2_done)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2.0) clk = ~clk;
    end

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
        local_active_req   = 1'b0;
        remote_l2_exit_req = 1'b0;
    endtask

    task automatic do_async_reset();
        rst_n     = 1'b0;
        l2_enable = 1'b0;
        clear_triggers();
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    initial begin
        $display("==== L2_tb start ====");

        do_async_reset();
        check(l2_done === 1'b0, "after rst_n: l2_done low (IDLE)");

        // ---- Scenario 1: residency, no trigger ----
        $display("\n-- Scenario 1: residency, no trigger --");
        @(negedge clk) l2_enable = 1'b1;
        clear_triggers();
        repeat (200) @(posedge clk); #1;
        check(l2_done === 1'b0, "1: no trigger -> done stays low");

        // ---- Scenario 2: each trigger (level) asserts done ----
        $display("\n-- Scenario 2: each trigger (level) asserts done --");
        begin : per_trigger_level
            static string names[2] = '{"local_active_req", "remote_l2_exit_req"};
            for (int i = 0; i < 2; i++) begin
                do_async_reset();
                @(negedge clk) l2_enable = 1'b1;
                repeat (3) @(posedge clk);
                check(l2_done === 1'b0, $sformatf("2.%0d: in L2_RUN, done low pre-trigger", i));
                @(negedge clk);
                case (i)
                    0: local_active_req   = 1'b1;
                    1: remote_l2_exit_req = 1'b1;
                endcase
                fork
                    begin wait (l2_done === 1'b1); end
                    begin repeat (10) @(posedge clk); $error("2.%0d trigger timeout", i); errors++; end
                join_any; disable fork;
                check(l2_done === 1'b1, $sformatf("2.%0d: done asserted on %s", i, names[i]));
                @(negedge clk) l2_enable = 1'b0; clear_triggers();
                @(posedge clk); #1;
                check(l2_done === 1'b0, $sformatf("2.%0d: done deasserts after enable drop", i));
            end
        end

        // ---- Scenario 3: 1-cycle pulse on each trigger is latched ----
        $display("\n-- Scenario 3: 1-cycle pulse on each trigger is latched --");
        begin : per_trigger_pulse
            static string names[2] = '{"local_active_req", "remote_l2_exit_req"};
            for (int i = 0; i < 2; i++) begin
                do_async_reset();
                @(negedge clk) l2_enable = 1'b1;
                repeat (5) @(posedge clk);
                @(negedge clk);
                case (i)
                    0: local_active_req   = 1'b1;
                    1: remote_l2_exit_req = 1'b1;
                endcase
                @(negedge clk) clear_triggers();
                fork
                    begin wait (l2_done === 1'b1); end
                    begin repeat (10) @(posedge clk); $error("3.%0d pulse timeout", i); errors++; end
                join_any; disable fork;
                check(l2_done === 1'b1, $sformatf("3.%0d: pulse on %s latched -> done", i, names[i]));
                @(negedge clk) l2_enable = 1'b0;
                @(posedge clk);
            end
        end

        // ---- Scenario 4: done held until l2_enable drops ----
        $display("\n-- Scenario 4: done held until enable drops --");
        do_async_reset();
        @(negedge clk) l2_enable = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk) local_active_req = 1'b1;
        @(negedge clk) local_active_req = 1'b0;
        wait (l2_done === 1'b1);
        repeat (50) @(posedge clk);
        check(l2_done === 1'b1, "4: done remains high in DONE_HOLD");
        @(negedge clk) l2_enable = 1'b0;
        @(posedge clk); #1;
        check(l2_done === 1'b0, "4: done drops after enable=0");

        // ---- Scenario 5: re-entry clears stickies ----
        $display("\n-- Scenario 5: re-entry clears stickies --");
        do_async_reset();
        @(negedge clk) l2_enable = 1'b1;
        @(negedge clk) remote_l2_exit_req = 1'b1;
        @(negedge clk) remote_l2_exit_req = 1'b0;
        wait (l2_done === 1'b1);
        @(negedge clk) l2_enable = 1'b0;
        @(posedge clk); #1;
        check(l2_done === 1'b0, "5: done cleared after enable drop");
        @(negedge clk) l2_enable = 1'b1;
        repeat (50) @(posedge clk); #1;
        check(l2_done === 1'b0, "5: re-entry with no trigger -> done stays low");
        @(negedge clk) local_active_req = 1'b1;
        wait (l2_done === 1'b1);
        check(l2_done === 1'b1, "5: fresh trigger after re-entry -> done");
        @(negedge clk) l2_enable = 1'b0; clear_triggers();
        @(posedge clk);

        // ---- Scenario 6: trigger pulsed while disabled is not retained ----
        $display("\n-- Scenario 6: trigger while disabled is not retained --");
        do_async_reset();
        @(negedge clk) remote_l2_exit_req = 1'b1;
        @(negedge clk) remote_l2_exit_req = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk) l2_enable = 1'b1;
        repeat (50) @(posedge clk); #1;
        check(l2_done === 1'b0,
              "6: pulse while disabled is NOT carried into enabled run");
        @(negedge clk) l2_enable = 1'b0;
        @(posedge clk);

        // ---- Scenario 7: both triggers concurrent ----
        $display("\n-- Scenario 7: both triggers concurrent --");
        do_async_reset();
        @(negedge clk) l2_enable = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk) begin
            local_active_req   = 1'b1;
            remote_l2_exit_req = 1'b1;
        end
        wait (l2_done === 1'b1);
        check(l2_done === 1'b1, "7: concurrent triggers asserts done");
        @(negedge clk) l2_enable = 1'b0; clear_triggers();
        @(posedge clk);

        // ---- Scenario 8: async rst_n -> IDLE ----
        $display("\n-- Scenario 8: async rst_n -> IDLE --");
        @(negedge clk) l2_enable = 1'b1;
        @(negedge clk) local_active_req = 1'b1;
        wait (l2_done === 1'b1);
        rst_n = 1'b0;
        #(CLK_PERIOD * 1.5);
        check(l2_done === 1'b0, "8: async rst_n -> done deasserts immediately");
        rst_n = 1'b1;
        @(posedge clk);

        $display("\n==== L2_tb summary: %0d error(s) ====", errors);
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
