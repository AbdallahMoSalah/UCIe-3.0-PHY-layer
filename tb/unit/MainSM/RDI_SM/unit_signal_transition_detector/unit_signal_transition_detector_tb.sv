`timescale 1ns/1ps

// =============================================================================
// Testbench : unit_signal_transition_detector_tb
// DUT       : unit_signal_transition_detector
//
// Description:
//   Verifies that the signal transition detector correctly:
//     1. Detects a mismatch on any monitored input (phyinrecenter, inband_pres,
//        trainerror, state_sts) and raises signal_transition (CLK_HANDSHAKE state)
//     2. Waits in CLK_HANDSHAKE until clk_handshake_done is asserted
//     3. On clk_handshake_done, latches all monitored inputs into the pl_* registers
//        and returns to IDLE
//
// Signals checked each cycle:
//   - signal_transition   (combinational output of cs == CLK_HANDSHAKE)
//   - pl_phyinrecenter    (registered, updated on handshake completion)
//   - pl_inband_pres      (registered, updated on handshake completion)
//   - pl_trainerror       (registered, updated on handshake completion)
//   - pl_state_sts        (registered, updated on handshake completion)
//
// Golden model mirrors the DUT state machine exactly so every check is
// self-checking without hard-coded expected values.
// =============================================================================

import RDI_SM_pkg::*;

module unit_signal_transition_detector_tb();

    // =========================================================================
    // Signals
    // =========================================================================

    // DUT inputs
    logic     lclk;
    logic     phyinrecenter;
    logic     inband_pres;
    logic     trainerror;
    logic     clk_handshake_done;
    RDI_state rdi_state_sts;

    // DUT outputs
    logic     pl_phyinrecenter;
    logic     pl_inband_pres;
    logic     pl_trainerror;
    logic     signal_transition;
    RDI_state pl_state_sts;

    // Golden model signals
    logic     exp_pl_phyinrecenter = 1'b0;
    logic     exp_pl_inband_pres   = 1'b0;
    logic     exp_pl_trainerror    = 1'b0;
    RDI_state exp_pl_state_sts     = Reset;
    logic     exp_signal_transition;

    // Error counter
    int err_count = 0;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    unit_signal_transition_detector dut (
        .lclk               (lclk),
        .phyinrecenter      (phyinrecenter),
        .inband_pres        (inband_pres),
        .trainerror         (trainerror),
        .clk_handshake_done (clk_handshake_done),
        .rdi_state_sts      (rdi_state_sts),
        .pl_phyinrecenter   (pl_phyinrecenter),
        .pl_inband_pres     (pl_inband_pres),
        .pl_trainerror      (pl_trainerror),
        .signal_transition  (signal_transition),
        .pl_state_sts       (pl_state_sts)
    );

    // =========================================================================
    // Clock Generation  (100 MHz — 10 ns period)
    // =========================================================================
    initial begin
        lclk = 1'b0;
        forever #5 lclk = ~lclk;
    end

    // =========================================================================
    // Golden Model
    //   Mirrors the two-state FSM inside the DUT exactly.
    //   exp_pl_* registers are updated identically to the DUT pl_* registers.
    // =========================================================================
    localparam bit EXP_IDLE          = 1'b0;
    localparam bit EXP_CLK_HANDSHAKE = 1'b1;

    logic exp_state = EXP_IDLE;

    always_ff @(posedge lclk) begin
        case (exp_state)
            EXP_IDLE: begin
                if ((phyinrecenter !== exp_pl_phyinrecenter) ||
                    (inband_pres   !== exp_pl_inband_pres)   ||
                    (trainerror    !== exp_pl_trainerror)    ||
                    (rdi_state_sts !== exp_pl_state_sts)) begin
                    exp_state <= EXP_CLK_HANDSHAKE;
                end else begin
                    exp_state <= EXP_IDLE;
                end
            end

            EXP_CLK_HANDSHAKE: begin
                if (clk_handshake_done) begin
                    exp_state           <= EXP_IDLE;
                    exp_pl_phyinrecenter <= phyinrecenter;
                    exp_pl_inband_pres   <= inband_pres;
                    exp_pl_trainerror    <= trainerror;
                    exp_pl_state_sts     <= rdi_state_sts;
                end else begin
                    exp_state <= EXP_CLK_HANDSHAKE;
                end
            end

            default: exp_state <= EXP_IDLE;
        endcase
    end

    assign exp_signal_transition = (exp_state == EXP_CLK_HANDSHAKE);

    // =========================================================================
    // Tasks
    // =========================================================================

    // -------------------------------------------------------------------------
    // drive_inputs — asserts all DUT inputs on the falling clock edge to ensure
    //                setup time is met for the following rising edge.
    // -------------------------------------------------------------------------
    task automatic drive_inputs(
        input logic     driven_phyinrecenter,
        input logic     driven_inband_pres,
        input logic     driven_trainerror,
        input logic     driven_clk_handshake_done,
        input RDI_state driven_rdi_state_sts
    );
        @(negedge lclk);
        phyinrecenter      = driven_phyinrecenter;
        inband_pres        = driven_inband_pres;
        trainerror         = driven_trainerror;
        clk_handshake_done = driven_clk_handshake_done;
        rdi_state_sts      = driven_rdi_state_sts;
        $display("[%0t] DRIVER : phyinrecenter=%b  inband_pres=%b  trainerror=%b  clk_hs_done=%b  state_sts=%s",
            $time,
            driven_phyinrecenter, driven_inband_pres,
            driven_trainerror, driven_clk_handshake_done,
            driven_rdi_state_sts.name());
    endtask

    // -------------------------------------------------------------------------
    // check_outputs — compares DUT outputs against the golden model after the
    //                 next falling edge (giving the posedge time to propagate).
    // -------------------------------------------------------------------------
    task automatic check_outputs();
        @(negedge lclk);   // DUT registered outputs settle after posedge

        if (signal_transition  !== exp_signal_transition  ||
            pl_phyinrecenter   !== exp_pl_phyinrecenter   ||
            pl_inband_pres     !== exp_pl_inband_pres     ||
            pl_trainerror      !== exp_pl_trainerror      ||
            pl_state_sts       !== exp_pl_state_sts) begin

            $error("[%0t] CHECKER: MISMATCH!\n"
                   "          Expected: trans=%b  pl_phy=%b  pl_inb=%b  pl_trner=%b  pl_state=%s\n"
                   "          Actual  : trans=%b  pl_phy=%b  pl_inb=%b  pl_trner=%b  pl_state=%s  [exp_state=%b]",
                   $time,
                   exp_signal_transition, exp_pl_phyinrecenter, exp_pl_inband_pres,
                   exp_pl_trainerror, exp_pl_state_sts.name(),
                   signal_transition, pl_phyinrecenter, pl_inband_pres,
                   pl_trainerror, pl_state_sts.name(), exp_state);
            err_count++;
        end else begin
            $display("[%0t] CHECKER: MATCH    trans=%b  pl_phy=%b  pl_inb=%b  pl_trner=%b  pl_state=%s  [exp_state=%b]",
                   $time,
                   signal_transition, pl_phyinrecenter, pl_inband_pres,
                   pl_trainerror, pl_state_sts.name(), exp_state);
        end
    endtask

    // -------------------------------------------------------------------------
    // do_handshake — helper that completes a pending CLK_HANDSHAKE:
    //   1. Waits one cycle in handshake with clk_handshake_done=0
    //   2. Asserts clk_handshake_done for one posedge → latches pl_* values
    //   3. De-asserts clk_handshake_done, checks IDLE outputs
    // -------------------------------------------------------------------------
    task automatic do_handshake(
        input logic     p, i, t,
        input RDI_state s
    );
        // Stay in CLK_HANDSHAKE for one extra cycle
        drive_inputs(p, i, t, 1'b0, s);
        @(posedge lclk);
        check_outputs();

        // Assert handshake done → DUT latches values
        drive_inputs(p, i, t, 1'b1, s);
        @(posedge lclk);
        check_outputs();

        // De-assert done → DUT returns to IDLE
        drive_inputs(p, i, t, 1'b0, s);
        check_outputs();
    endtask

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        $display("========================================================");
        $display(" unit_signal_transition_detector Testbench — START");
        $display("========================================================");

        // ------------------------------------------------------------------
        // Initialization
        // ------------------------------------------------------------------
        phyinrecenter      = 1'b0;
        inband_pres        = 1'b0;
        trainerror         = 1'b0;
        clk_handshake_done = 1'b0;
        state_sts          = Reset;

        // Force pl_* regs to known-zero state (DUT has no reset port)
        #2;
        force dut.pl_phyinrecenter = 1'b0;
        force dut.pl_inband_pres   = 1'b0;
        force dut.pl_trainerror    = 1'b0;
        force dut.pl_state_sts     = Reset;
        force dut.cs               = 0;   // IDLE
        @(posedge lclk);
        release dut.pl_phyinrecenter;
        release dut.pl_inband_pres;
        release dut.pl_trainerror;
        release dut.pl_state_sts;
        release dut.cs;

        repeat(2) @(posedge lclk);

        // ==================================================================
        // Test 1 — No change, stays in IDLE
        // ==================================================================
        $display("\n--- Test 1: No change — stays IDLE ---");
        drive_inputs(1'b0, 1'b0, 1'b0, 1'b0, Reset);
        @(posedge lclk);
        check_outputs();

        // ==================================================================
        // Test 2 — phyinrecenter rises → triggers CLK_HANDSHAKE
        // ==================================================================
        $display("\n--- Test 2: phyinrecenter change → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b0, 1'b0, 1'b0, Reset);
        @(posedge lclk);
        check_outputs();   // Now in CLK_HANDSHAKE (signal_transition=1)
        do_handshake(1'b1, 1'b0, 1'b0, Reset);

        // ==================================================================
        // Test 3 — inband_pres rises → triggers CLK_HANDSHAKE
        // ==================================================================
        $display("\n--- Test 3: inband_pres change → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b0, 1'b0, Reset);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b0, Reset);

        // ==================================================================
        // Test 4 — trainerror rises → triggers CLK_HANDSHAKE
        // ==================================================================
        $display("\n--- Test 4: trainerror change → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b1, 1'b0, Reset);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b1, Reset);

        // ==================================================================
        // Test 5 — state_sts changes Reset → Active → triggers CLK_HANDSHAKE
        // ==================================================================
        $display("\n--- Test 5: state_sts Reset→Active → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b1, 1'b0, Active);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b1, Active);

        // ==================================================================
        // Test 6 — state_sts Active → L1
        // ==================================================================
        $display("\n--- Test 6: state_sts Active→L1 → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b1, 1'b0, L1);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b1, L1);

        // ==================================================================
        // Test 7 — state_sts L1 → L2
        // ==================================================================
        $display("\n--- Test 7: state_sts L1→L2 → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b1, 1'b0, L2);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b1, L2);

        // ==================================================================
        // Test 8 — state_sts L2 → Retrain
        // ==================================================================
        $display("\n--- Test 8: state_sts L2→Retrain → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b1, 1'b0, Retrain);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b1, Retrain);

        // ==================================================================
        // Test 9 — state_sts Retrain → LinkError
        // ==================================================================
        $display("\n--- Test 9: state_sts Retrain→LinkError → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b1, 1'b0, LinkError);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b1, LinkError);

        // ==================================================================
        // Test 10 — state_sts LinkError → Disabled
        // ==================================================================
        $display("\n--- Test 10: state_sts LinkError→Disabled → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b1, 1'b0, Disabled);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b1, Disabled);

        // ==================================================================
        // Test 11 — state_sts Disabled → LinkReset
        // ==================================================================
        $display("\n--- Test 11: state_sts Disabled→LinkReset → CLK_HANDSHAKE ---");
        drive_inputs(1'b1, 1'b1, 1'b1, 1'b0, LinkReset);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b1, 1'b1, 1'b1, LinkReset);

        // ==================================================================
        // Test 12 — Multiple signals change simultaneously
        //           phyinrecenter 1→0, inband_pres 1→0, state LinkReset→Active_PMNAK
        // ==================================================================
        $display("\n--- Test 12: Multiple simultaneous changes ---");
        drive_inputs(1'b0, 1'b0, 1'b1, 1'b0, Active_PMNAK);
        @(posedge lclk);
        check_outputs();
        do_handshake(1'b0, 1'b0, 1'b1, Active_PMNAK);

        // ==================================================================
        // Test 13 — Delayed handshake (clk_handshake_done held 0 for 4 cycles)
        // ==================================================================
        $display("\n--- Test 13: Delayed handshake (4-cycle wait) ---");
        drive_inputs(1'b0, 1'b0, 1'b0, 1'b0, Active_PMNAK);
        // No change from previous latched values — no transition expected;
        // artificially change trainerror to force a transition
        drive_inputs(1'b0, 1'b0, 1'b0, 1'b0, Nop);
        @(posedge lclk);
        check_outputs();   // state_sts changed → CLK_HANDSHAKE

        repeat(4) begin
            drive_inputs(1'b0, 1'b0, 1'b0, 1'b0, Nop);
            @(posedge lclk);
            check_outputs();   // Remains in CLK_HANDSHAKE (done=0)
        end

        drive_inputs(1'b0, 1'b0, 1'b0, 1'b1, Nop);
        @(posedge lclk);
        check_outputs();   // Done asserted → latch & return IDLE

        drive_inputs(1'b0, 1'b0, 1'b0, 1'b0, Nop);
        check_outputs();   // Verify IDLE with updated pl_*

        // ==================================================================
        // Test 14 — All inputs stable after final latch → stays IDLE
        // ==================================================================
        $display("\n--- Test 14: All stable — stays IDLE ---");
        repeat(3) begin
            drive_inputs(1'b0, 1'b0, 1'b0, 1'b0, Nop);
            @(posedge lclk);
            check_outputs();
        end

        // ==================================================================
        // Summary
        // ==================================================================
        $display("\n========================================================");
        if (err_count == 0)
            $display(" TEST PASSED — 0 mismatches.");
        else
            $display(" TEST FAILED — %0d mismatch(es).", err_count);
        $display("========================================================\n");

        $stop;
    end

endmodule
