// Testbench for rtl/MainSM/LTSM/ACTIVE.sv
`timescale 1ns/1ps

import RDI_SM_pkg::*;
import ltsm_state_n_pkg::*;

module ACTIVE_tb;

    localparam real CLK_PERIOD = 10.0; // ns

    // ---------------- DUT ports ----------------
    logic clk;
    logic rst_n;
    logic active_enable;
    RDI_state rdi_state;
    logic Start_UCIe_Link_Training;
    logic active_error;
    ltsm_ctrl_state_e next_ltsm_state;

    // Instantiate DUT
    ACTIVE dut (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .active_enable             (active_enable),
        .rdi_state                 (rdi_state),
        .Start_UCIe_Link_Training  (Start_UCIe_Link_Training),
        .active_error              (active_error),
        .next_ltsm_state           (next_ltsm_state)
    );

    // Clock Generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2.0) clk = ~clk;
    end

    // Error Tracking
    int errors = 0;
    task automatic check(input bit cond, input string msg);
        if (!cond) begin
            $error("[%0t] FAIL: %s", $time, msg);
            errors++;
        end else begin
            $display("[%0t] PASS: %s", $time, msg);
        end
    endtask

    task automatic do_reset();
        rst_n = 1'b0;
        active_enable = 1'b0;
        rdi_state = Nop;
        Start_UCIe_Link_Training = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;
        @(posedge clk);
    endtask

    // Tests
    initial begin
        $display("==== ACTIVE_tb start ====");

        // Test 1: Reset Behavior
        do_reset();
        check(active_error === 1'b0 && next_ltsm_state === CTRL_NOP, "Test 1: Reset state outputs incorrect");

        // Test 2: Stay in IDLE when active_enable is low
        @(negedge clk);
        rdi_state = Retrain;
        repeat (5) @(posedge clk);
        check(active_error === 1'b0 && next_ltsm_state === CTRL_NOP, "Test 2: active_enable low, should stay IDLE");

        // Test 3: transition to ACTIVE_RUN
        do_reset();
        @(negedge clk);
        active_enable = 1'b1;
        @(posedge clk); #1;
        check(active_error === 1'b0 && next_ltsm_state === CTRL_ACTIVE, "Test 3: Transition to ACTIVE_RUN");

        // Test 4: Transition to PHYRETRAIN
        do_reset();
        @(negedge clk);
        active_enable = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rdi_state = Retrain;
        @(posedge clk); #1;
        check(active_error === 1'b0 && next_ltsm_state === CTRL_PHYRETRAIN, "Test 4: Transition to PHYRETRAIN");

        // Test 5: Transition to L1
        do_reset();
        @(negedge clk);
        active_enable = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rdi_state = L_1;
        @(posedge clk); #1;
        check(active_error === 1'b0 && next_ltsm_state === CTRL_L1, "Test 5: Transition to L1");

        // Test 6: Transition to L2
        do_reset();
        @(negedge clk);
        active_enable = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rdi_state = L_2;
        @(posedge clk); #1;
        check(active_error === 1'b0 && next_ltsm_state === CTRL_L2, "Test 6: Transition to L2");

        // Test 7: Transition to TRAINERROR via rdi_state = LinkError
        do_reset();
        @(negedge clk);
        active_enable = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rdi_state = LinkError;
        @(posedge clk); #1;
        check(active_error === 1'b1 && next_ltsm_state === CTRL_TRAINERROR, "Test 7: Transition to TRAINERROR (rdi_state=LinkError)");

        // Test 8: Transition to TRAINERROR via Start_UCIe_Link_Training
        do_reset();
        @(negedge clk);
        active_enable = 1'b1;
        @(posedge clk);
        @(negedge clk);
        Start_UCIe_Link_Training = 1'b1;
        @(posedge clk); #1;
        check(active_error === 1'b0 && next_ltsm_state === CTRL_TRAINERROR, "Test 8: Transition to TRAINERROR (Start_UCIe_Link_Training=1)");

        // Test 10: Transition to TRAINERROR via rdi_state = LinkReset
        do_reset();
        @(negedge clk);
        active_enable = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rdi_state = LinkReset;
        @(posedge clk); #1;
        check(active_error === 1'b0 && next_ltsm_state === CTRL_TRAINERROR, "Test 10: Transition to TRAINERROR (rdi_state=LinkReset)");

        // Test 11: Transition to TRAINERROR via rdi_state = Disabled
        do_reset();
        @(negedge clk);
        active_enable = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rdi_state = Disabled;
        @(posedge clk); #1;
        check(active_error === 1'b0 && next_ltsm_state === CTRL_TRAINERROR, "Test 11: Transition to TRAINERROR (rdi_state=Disabled)");

        // Test 9: Deasserting active_enable returns to IDLE
        @(negedge clk);
        active_enable = 1'b0;
        @(posedge clk); #1;
        check(active_error === 1'b0 && next_ltsm_state === CTRL_NOP, "Test 9: Deasserting active_enable returns to IDLE");

        // Summary
        $display("\n==== ACTIVE_tb summary: %0d error(s) ====", errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("TESTS FAILED");
        $finish;
    end

    // Watchdog
    initial begin
        #(CLK_PERIOD * 1000);
        $error("Global TB watchdog expired");
        $finish;
    end

endmodule
