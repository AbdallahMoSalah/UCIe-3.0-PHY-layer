// =============================================================================
// Testbench  : unit_RXCLKCAL_tb
// DUT        : unit_RXCLKCAL
// Purpose    : Functional verification of the MBTRAIN.RXCLKCAL sub-state FSM.
//
// --- Test Phases -------------------------------------------------------------
//
//  Phase 1 -- Deterministic Regression (8 scenarios)
//    * 32 GT/s happy path  (no IQ loop)
//    * 48 GT/s happy path  (1 IQ iteration)
//    * 64 GT/s happy path  (2 IQ iterations)
//    * 64 GT/s happy path  (3 IQ iterations)
//    * 8-ms timeout        -> TO_TRAINERROR
//    * Partner TRAINERROR SB message
//    * Out-of-range IQ shift (rx_msginfo[0]=1)
//    * Late IQ loop-back at RXCLKCAL_DONE_REQ
//
//  Phase 2 -- No-Reset Back-to-Back Chains (4 multi-test sequences)
//    * Pairs / triples of start_test() calls with NO hardware reset between
//      them -- verifies that the FSM's IDLE-state self-clearing is sufficient
//      for clean re-entry.
//
//  Phase 3 -- Randomized Tests (NUM_RAND_TESTS iterations)
//    * Fully randomized stimulus via the RxClkCalStim class:
//        speed (0-7), iq_iters (1-4), do_timeout, do_wrong_sb,
//        do_oor, do_late_iq
//    • Every 3rd successful test is immediately followed by a chained test
//      executed WITHOUT a hardware reset.
//
// --- IQ Iteration Control ----------------------------------------------------
//  Thread thr_iq_ctrl watches for IQ_OBSERVE_CLK completions.  IQ_OBSERVE_CLK
//  is held for ANALOG_SETTLE_CYCLES before IQ_CHECK_CALIBRATION, giving the
//  thread a safe setup window to drive phy_rx_tckn_shift before the
//  combinational next-state decision is latched.
// =============================================================================
`timescale 1ps/1ps

module unit_RXCLKCAL_tb ();
    import UCIe_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter  LCLK_PERIOD          = 1*1000;  // 1 GHz lclk (1000 ps period)
    parameter  TIMEOUT_CYCLES       = 700_000; // Simulated 8 ms timeout
    parameter  ANALOG_SETTLE_CYCLES = 10;
    parameter int NUM_RAND_TESTS    = 200;     // Randomized iterations (Phase 3)

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    reg lclk;
    reg rst_n;
    internal_ltsm_if intf(.lclk(lclk), .rst_n(rst_n));

    // =========================================================================
    // FSM State Mirror (assign from DUT internal signal for use in waits)
    // =========================================================================
    typedef enum reg [3:0] {
        RXCLKCAL_IDLE         = unit_RXCLKCAL_inst.RXCLKCAL_IDLE,
        RXCLKCAL_START_REQ    = unit_RXCLKCAL_inst.RXCLKCAL_START_REQ,
        RXCLKCAL_START_RESP   = unit_RXCLKCAL_inst.RXCLKCAL_START_RESP,
        RXCLKCAL_CALIBRATE    = unit_RXCLKCAL_inst.RXCLKCAL_CALIBRATE,
        IQ_IDLE               = unit_RXCLKCAL_inst.IQ_IDLE,
        IQ_TCKN_L_SHIFT_REQ   = unit_RXCLKCAL_inst.IQ_TCKN_L_SHIFT_REQ,
        IQ_APPLY_TCKN_L_SHIFT = unit_RXCLKCAL_inst.IQ_APPLY_TCKN_L_SHIFT,
        IQ_TCKN_L_SHIFT_RESP  = unit_RXCLKCAL_inst.IQ_TCKN_L_SHIFT_RESP,
        IQ_OBSERVE_CLK        = unit_RXCLKCAL_inst.IQ_OBSERVE_CLK,
        IQ_CHECK_CALIBRATION  = unit_RXCLKCAL_inst.IQ_CHECK_CALIBRATION,
        RXCLKCAL_DONE_REQ     = unit_RXCLKCAL_inst.RXCLKCAL_DONE_REQ,
        RXCLKCAL_DONE_RESP    = unit_RXCLKCAL_inst.RXCLKCAL_DONE_RESP,
        TO_RXCLKCAL_DONE      = unit_RXCLKCAL_inst.TO_RXCLKCAL_DONE,
        TO_TRAINERROR         = unit_RXCLKCAL_inst.TO_TRAINERROR
    } fsm_state_t;

    fsm_state_t current_state;
    assign current_state = fsm_state_t'(unit_RXCLKCAL_inst.current_state);

    // =========================================================================
    // lclk Generator
    // =========================================================================
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    // =========================================================================
    // DUT
    // =========================================================================
    unit_RXCLKCAL #() unit_RXCLKCAL_inst (
        .rxclkcal_if(intf.rxclkcal_mp)
    );

    // =========================================================================
    // Attachments  (SB/MB simulator + timers)
    // =========================================================================
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (
        .intf(intf)
    );

    // =========================================================================
    // Score-keeping
    // =========================================================================
    integer success_count = 0;
    integer fail_count    = 0;

    // =========================================================================
    // Randomization Stimulus Class
    // =========================================================================
    class RxClkCalStim;

        // -- Randomizable Fields -----------------------------------------------
        rand bit  [2:0] speed;        // 0h=4, 1h=8, …, 5h=32 (no IQ), 6h=48, 7h=64 GT/s
        rand int  unsigned iq_iters;  // Number of full IQ calibration iterations
        rand bit  do_timeout;         // Trigger the 8-ms watchdog early
        rand bit  do_wrong_sb;        // Inject a wrong (TRAINERROR) SB message
        rand bit  do_oor;             // Partner reports out-of-range TCKN_L shift
        rand bit  do_late_iq;         // Re-inject TCKN_L_shift_req at DONE_REQ

        // -- Constraints -------------------------------------------------------

        // At most ONE error injection per test to keep results deterministic
        constraint c_single_error_c {
            (do_timeout + do_wrong_sb + do_oor) <= 1;
        }

        // OOR (out-of-range) and late-IQ (increment) only make sense in the IQ state machine (speed > 5) -> (speed > 32 GT/s)
        constraint c_iq_speed_c {
            if (speed <= 3'd5) {
                do_oor     == 1'b0;
                do_late_iq == 1'b0;
                iq_iters   == 1;
            }
        }

        // Constrain IQ iterations to a reasonable range
        constraint c_iq_iters_c {
            if (speed > 3'd5 && !do_oor && !do_timeout && !do_wrong_sb)
                iq_iters inside {[1:4]};
            else
                iq_iters == 1;
        }

        // Late IQ loopback is incompatible with other error injections
        constraint c_late_iq_c {
            if (do_timeout || do_wrong_sb || do_oor) do_late_iq == 1'b0;
        }

        // Exercise high-speed IQ paths as much as no-IQ paths
        constraint c_speed_dist_c {
            speed dist { [3'd0 : 3'd5] := 50, [3'd6 : 3'd7] := 50 };
        }

        // -- Helpers -----------------------------------------------------------
        function bit expects_error();
            return (do_timeout | do_wrong_sb | do_oor);
        endfunction

        function string to_string();
            string s;
            s = $sformatf("speed=3'd%0d  iq_iters=%0d", speed, iq_iters);
            if (do_timeout)  s = {s, "  [TIMEOUT]"};
            if (do_wrong_sb) s = {s, "  [WRONG_SB]"};
            if (do_oor)      s = {s, "  [OOR_SHIFT]"};
            if (do_late_iq)  s = {s, "  [LATE_IQ]"};
            return s;
        endfunction

    endclass : RxClkCalStim

    // =========================================================================
    // TASK: apply_reset
    //   Full hardware reset.  Drives rst_n low, clears every stimulus signal,
    //   then releases rst_n.  Call this before the FIRST test in any chain.
    // =========================================================================
    task apply_reset();
        rst_n                           = 1'b0;
        intf.rxclkcal_en                = 1'b0;
        intf.tb_wait_timeout            = 1'b0;
        intf.tb_wrong_sb_msg_en         = 1'b0;
        intf.tb_wrong_sb_msg            = NOTHING;
        intf.tb_rx_msginfo              = 16'h0;
        intf.tb_rx_data_field           = 64'h0;
        intf.tx_pt_en                   = 1'b0;
        intf.rx_pt_en                   = 1'b0;
        intf.phy_rx_tckn_shift          = 5'd0;
        intf.phy_rx_decrement_shift     = 1'b0;
        intf.phy_tx_tckn_shift_out_of_range = 1'b0;
        intf.phy_negotiated_speed       = 3'd0;
        #(10*LCLK_PERIOD);
        rst_n = 1'b1;
        #(2*LCLK_PERIOD);
    endtask

    // =========================================================================
    // TASK: clear_stimuli
    //   Clears only the TB-driven stimulus signals — NO hardware rst_n toggle.
    //   Used to chain a second start_test() immediately after the first one
    //   has returned, without issuing a hardware reset.  Gives the FSM one
    //   extra clock edge to settle back to IDLE (which happens automatically
    //   once rxclkcal_en is de-asserted by the previous start_test call).
    // =========================================================================
    task clear_stimuli();
        intf.tb_wait_timeout            = 1'b0;
        intf.tb_wrong_sb_msg_en         = 1'b0;
        intf.tb_wrong_sb_msg            = NOTHING;
        intf.tb_rx_msginfo              = 16'h0;
        intf.phy_rx_tckn_shift          = 5'd0;
        intf.phy_rx_decrement_shift     = 1'b0;
        intf.phy_tx_tckn_shift_out_of_range = 1'b0;
        // Give the FSM enough clocks to finish IDLE transition & clear timeout flags
        repeat(3) @(posedge lclk); #1step;
    endtask

    // =========================================================================
    // TASK: start_test  (automatic -- each invocation gets its own stack frame)
    //
    //  Enables the DUT, runs a parallel stimulus fork, scores the result, and
    //  cleans up.  All threads inside the fork are killed by "disable
    //  test_execution" once the drive thread (thr_drive) finishes.
    //
    //  Parameters
    //  ----------
    //  abort_after     : Cycles before tb_wait_timeout fires  (TIMEOUT_CYCLES -> OFF)
    //  wrong_sb_after  : Cycles before wrong SB msg injection  (TIMEOUT_CYCLES -> OFF)
    //  wrong_sb_msg    : The wrong message enum value to inject
    //  oor_after       : Cycles before (out-of-range) oor flag injection (TIMEOUT_CYCLES -> OFF)
    //  num_iq_iters    : How many full IQ calibration loops the DUT should run
    //  late_iq         : 1 -> re-inject TCKN_L_shift_req once FSM reaches DONE_REQ
    //  may_error       : 1 -> a TO_TRAINERROR outcome is *expected* (scores PASS)
    // =========================================================================
    task automatic start_test(
            input integer  abort_after     = TIMEOUT_CYCLES,
            input integer  wrong_sb_after  = TIMEOUT_CYCLES,
            input msg_no_e wrong_sb_msg    = NOTHING,
            input integer  oor_after       = TIMEOUT_CYCLES,
            input int      num_iq_iters    = 1,
            input bit      late_iq         = 1'b0,
            input bit      may_error       = 1'b0
        );
        logic result_is_error;
        result_is_error = 1'b0;

        // --- Pre-load IQ shift to 5'd3: forces the IQ loop to repeat ----------
        // thr_iq_ctrl will switch this to 5'd0 once enough iterations are done.
        // Start high so IQ_CHECK_CALIBRATION loops back by default; the thread
        // changes it to 0 at the right time to exit toward RXCLKCAL_DONE_REQ.
        intf.phy_rx_tckn_shift = 5'd3;

        fork : test_execution

            // ------------------------------------------------------------------
            // thr_drive : enable DUT -> wait for terminal state -> score -> clean
            // ------------------------------------------------------------------
            begin : thr_drive
                intf.rxclkcal_en = 1'b1;

                // Block until the FSM declares done or requests TRAINERROR
                wait(intf.rxclkcal_done || intf.trainerror_req); #1step;

                intf.rxclkcal_en = 1'b0;
                result_is_error  = intf.trainerror_req;

                if (!result_is_error)
                    wait(current_state == RXCLKCAL_IDLE);    // normal exit
                else
                    wait(current_state == TO_TRAINERROR);    // error exit

                #1step;

                // -- Scoring --------------------------------------------------
                if (result_is_error) begin
                    if (may_error) begin
                        success_count++;
                        $display("%10t ps: PASS -- Expected TRAINERROR reached correctly.", $realtime());
                    end else begin
                        fail_count++;
                        $display("%10t ps: FAIL -- Unexpected TRAINERROR!", $realtime());
                        $stop;
                    end
                end else begin
                    success_count++;
                    $display("%10t ps: PASS -- FSM completed normally to IDLE.", $realtime());
                end

                disable test_execution; // kill all sibling threads
            end

            // ──────────────────────────────────────────────────────────────────
            // thr_wrong_sb : inject wrong SB message after N cycles  (optional)
            // ──────────────────────────────────────────────────────────────────
            begin : thr_wrong_sb
                if (wrong_sb_after < TIMEOUT_CYCLES) begin
                    for (int i = 0; i < wrong_sb_after; i++) @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 1'b1;
                    intf.tb_wrong_sb_msg    = wrong_sb_msg;
                end
                wait(1'b0); // stay alive until disabled
            end

            // ──────────────────────────────────────────────────────────────────
            // thr_timeout : assert tb_wait_timeout after N cycles  (optional)
            // ──────────────────────────────────────────────────────────────────
            begin : thr_timeout
                if (abort_after < TIMEOUT_CYCLES) begin
                    for (int i = 0; i < abort_after; i++) @(posedge lclk);
                    intf.tb_wait_timeout = 1'b1;
                end
                wait(1'b0); // stay alive until disabled
            end

            // ──────────────────────────────────────────────────────────────────
            // thr_iq_ctrl : drive phy_rx_tckn_shift for IQ iteration control
            //
            //  Strategy:
            //   1. Wait for IQ_OBSERVE_CLK to become active.
            //      (The FSM holds IQ_OBSERVE_CLK for ANALOG_SETTLE_CYCLES before
            //       advancing to IQ_CHECK_CALIBRATION, giving us a safe setup
            //       window that is ANALOG_SETTLE_CYCLES wide.)
            //   2. Increment our local iteration counter.
            //   3. If we have completed enough iterations, drive shift = 0
            //      so that IQ_CHECK_CALIBRATION exits toward DONE_REQ.
            //   4. Wait for state to leave IQ_OBSERVE_CLK before looping back.
            // ──────────────────────────────────────────────────────────────────
            begin : thr_iq_ctrl
                int iter_done;
                iter_done = 0;
                forever begin
                    wait(current_state == IQ_OBSERVE_CLK); #1step;
                    iter_done++;
                    // Signal convergence once enough iterations are complete
                    if (iter_done >= num_iq_iters)
                        intf.phy_rx_tckn_shift = 5'd0;
                    // Deglitch: wait until the state leaves IQ_OBSERVE_CLK
                    wait(current_state != IQ_OBSERVE_CLK); #1step;
                end
            end

            // ──────────────────────────────────────────────────────────────────
            // thr_oor : inject out-of-range flag in IQ_TCKN_L_SHIFT_RESP
            //
            //  Setting tb_rx_msginfo[0]=1 causes ltsm_tb_attachments to echo
            //  an rx_msginfo with bit-0 set, which the FSM interprets as
            //  "partner's TCKN_L shift is out of range" -> TO_TRAINERROR.
            // ──────────────────────────────────────────────────────────────────
            begin : thr_oor
                if (oor_after < TIMEOUT_CYCLES) begin
                    for (int i = 0; i < oor_after; i++) @(posedge lclk);
                    // IQ must have started before we can hit IQ_TCKN_L_SHIFT_RESP
                    wait(current_state == IQ_TCKN_L_SHIFT_RESP); #1step;
                    @(posedge lclk); // one settling cycle
                    intf.tb_rx_msginfo = 16'h0001; // [0]=1 → out-of-range
                end
                wait(1'b0); // stay alive until disabled
            end

            // ──────────────────────────────────────────────────────────────────
            // thr_late_iq : partner re-sends TCKN_L_shift_req at DONE_REQ
            //
            //  Simulates the partner still needing another IQ calibration step
            //  after we have already reached RXCLKCAL_DONE_REQ.  The FSM should
            //  accept this and loop back to IQ_TCKN_L_SHIFT_REQ.
            // ──────────────────────────────────────────────────────────────────
            begin : thr_late_iq
                if (late_iq) begin
                    wait(current_state == RXCLKCAL_DONE_REQ); #1step;
                    intf.tb_wrong_sb_msg_en = 1'b1;
                    intf.tb_wrong_sb_msg    = MBTRAIN_RXCLKCAL_TCKN_L_shift_req;
                    repeat(3) @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 1'b0;
                    intf.tb_wrong_sb_msg    = NOTHING;
                end
                wait(1'b0); // stay alive until disabled
            end

        join // blocking — exits only when disable test_execution fires

        // -- Cleanup (always executed after join) -----------------------------
        intf.tb_wait_timeout    = 1'b0;
        intf.tb_wrong_sb_msg_en = 1'b0;
        intf.tb_rx_msginfo      = 16'h0;
        intf.phy_rx_tckn_shift  = 5'd0;
        @(posedge lclk); #1step;
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    int scenario_no = 1;
    initial begin
        $monitor("%10t ps : state=(%s)", $realtime(), current_state.name());

        // =====================================================================
        // --- PHASE 1 : Deterministic Regression -----------------------------
        // =====================================================================
        $display("\n\n####################################################################");
        $display("## PHASE 1 -- Deterministic Regression Tests                       ##");
        $display("####################################################################\n");

        //----------------------------------------------------------------------
        // Scenario 1: 32 GT/s  — no IQ loop
        //----------------------------------------------------------------------
        $display("\n=========> Scenario %0d: Happy Path -- 32 GT/s (no IQ) <=========", scenario_no++);
        apply_reset();
        intf.phy_negotiated_speed = 3'd5;
        start_test();

        //----------------------------------------------------------------------
        // Scenario 2: 48 GT/s  — 1 IQ iteration
        //----------------------------------------------------------------------
        $display("\n=========> Scenario %0d: Happy Path -- 48 GT/s, 1 IQ iter <=========", scenario_no++);
        apply_reset();
        intf.phy_negotiated_speed = 3'd6;
        start_test(.num_iq_iters(1));

        //----------------------------------------------------------------------
        // Scenario 3: 64 GT/s  — 2 IQ iterations
        //----------------------------------------------------------------------
        $display("\n=========> Scenario %0d: Happy Path -- 64 GT/s, 2 IQ iters <=========", scenario_no++);
        apply_reset();
        intf.phy_negotiated_speed = 3'd7;
        start_test(.num_iq_iters(2));

        //----------------------------------------------------------------------
        // Scenario 4: 64 GT/s  — 3 IQ iterations
        //----------------------------------------------------------------------
        $display("\n=========> Scenario %0d: Happy Path -- 64 GT/s, 3 IQ iters <=========", scenario_no++);
        apply_reset();
        intf.phy_negotiated_speed = 3'd7;
        start_test(.num_iq_iters(3));

        //----------------------------------------------------------------------
        // Scenario 5: 8-ms timeout  → TO_TRAINERROR
        //----------------------------------------------------------------------
        $display("\n=========> Scenario %0d: 8-ms Timeout -> TRAINERROR <=========", scenario_no++);
        apply_reset();
        intf.phy_negotiated_speed = 3'd5;
        start_test(.abort_after(15), .may_error(1'b1));

        //----------------------------------------------------------------------
        // Scenario 6: Partner sends TRAINERROR_Entry_req → TO_TRAINERROR
        //----------------------------------------------------------------------
        $display("\n=========> Scenario %0d: Partner TRAINERROR SB msg <=========", scenario_no++);
        apply_reset();
        intf.phy_negotiated_speed = 3'd5;
        start_test(.wrong_sb_after(5), .wrong_sb_msg(TRAINERROR_Entry_req), .may_error(1'b1));

        //----------------------------------------------------------------------
        // Scenario 7: Out-of-range IQ shift  → TO_TRAINERROR
        //----------------------------------------------------------------------
        $display("\n=========> Scenario %0d: Out-of-range IQ shift -> TRAINERROR <=========", scenario_no++);
        apply_reset();
        intf.phy_negotiated_speed = 3'd7;
        start_test(.oor_after(0), .may_error(1'b1));

        //----------------------------------------------------------------------
        // Scenario 8: Late IQ loop-back at RXCLKCAL_DONE_REQ  → completes OK
        //----------------------------------------------------------------------
        $display("\n=========> Scenario %0d: Late IQ loop-back at DONE_REQ <=========", scenario_no++);
        apply_reset();
        intf.phy_negotiated_speed = 3'd7;
        start_test(.num_iq_iters(1), .late_iq(1'b1));

        // =====================================================================
        // --- PHASE 2 : No-Reset Back-to-Back Chains -------------------------
        // =====================================================================
        $display("\n\n####################################################################");
        $display("## PHASE 2 -- No-Reset Back-to-Back Chains                        ##");
        $display("##  start_test() is called consecutively WITHOUT apply_reset().  ##");
        $display("##  Verifies FSM correctly self-clears via IDLE state entry.     ##");
        $display("####################################################################\n");

        //----------------------------------------------------------------------
        // Chain A : 32 GT/s  →  48 GT/s (1 IQ)   — no reset between
        //----------------------------------------------------------------------
        $display("\n=========> Chain A: 32 GT/s -> 48 GT/s (no reset between) <=========", );
        apply_reset();

        intf.phy_negotiated_speed = 3'd5;
        start_test();                       // A.1

        clear_stimuli();                    // ← no rst_n, just signal cleanup
        intf.phy_negotiated_speed = 3'd6;
        start_test(.num_iq_iters(1));       // A.2

        //----------------------------------------------------------------------
        // Chain B : 64 GT/s (2 IQ)  →  Timeout   — no reset between
        //----------------------------------------------------------------------
        $display("\n=========> Chain B: 64 GT/s (2 IQ) -> Timeout (no reset between) <=========");
        apply_reset();

        intf.phy_negotiated_speed = 3'd7;
        start_test(.num_iq_iters(2));       // B.1

        clear_stimuli();
        intf.phy_negotiated_speed = 3'd5;
        start_test(.abort_after(20), .may_error(1'b1)); // B.2 -- timeout

        //----------------------------------------------------------------------
        // Chain C : TRAINERROR  →  32 GT/s happy path  — no reset between
        //   After TRAINERROR the FSM still returns to IDLE once rxclkcal_en
        //   is de-asserted.  The next test must succeed without a reset.
        //----------------------------------------------------------------------
        $display("\n=========> Chain C: TRAINERROR -> 32 GT/s clean (no reset between) <=========");
        apply_reset();

        intf.phy_negotiated_speed = 3'd5;
        start_test(.abort_after(15), .may_error(1'b1)); // C.1 -- error

        clear_stimuli();
        intf.phy_negotiated_speed = 3'd6;
        start_test(.num_iq_iters(1));                   // C.2 -- must pass

        //----------------------------------------------------------------------
        // Chain D : Triple — 32 GT/s  →  OOR error  →  48 GT/s (2 IQ)
        //   Three consecutive tests with ONLY ONE apply_reset() at the start.
        //----------------------------------------------------------------------
        $display("\n=========> Chain D: Triple 32 GT/s -> OOR -> 48 GT/s 2IQ (no reset) <=========");
        apply_reset();

        intf.phy_negotiated_speed = 3'd5;
        start_test();                                   // D.1

        clear_stimuli();
        intf.phy_negotiated_speed = 3'd7;
        start_test(.oor_after(0), .may_error(1'b1));    // D.2 -- OOR error

        clear_stimuli();
        intf.phy_negotiated_speed = 3'd6;
        start_test(.num_iq_iters(2));                   // D.3 -- must pass

        // =====================================================================
        // --- PHASE 3 : Randomized Tests -------------------------------------
        // =====================================================================
        $display("\n\n####################################################################");
        $display("## PHASE 3 -- Randomized Tests  (%0d iterations)              ##", NUM_RAND_TESTS);
        $display("##  Every 3rd successful test chains a 2nd test without reset.  ##");
        $display("####################################################################\n");

        begin : rand_phase
            RxClkCalStim stim        = new();
            RxClkCalStim chain_stim  = new();
            bit prev_was_clean_pass;
            int rand_no;

            prev_was_clean_pass = 1'b0;
            rand_no = 0;

            for (int i = 0; i < NUM_RAND_TESTS; i++) begin
                rand_no++;

                // -- Randomize primary stimulus --------------------------------
                if (!stim.randomize()) begin
                    $display("ERROR: stim.randomize() failed at rand_no=%0d", rand_no);
                    $stop;
                end

                $display("\n--- Rand %4d/%4d --- %s", rand_no, NUM_RAND_TESTS, stim.to_string());

                apply_reset();
                intf.phy_negotiated_speed = stim.speed;

                start_test(
                    .abort_after   (stim.do_timeout  ? $urandom_range(15, 100) : TIMEOUT_CYCLES),
                    .wrong_sb_after(stim.do_wrong_sb ? $urandom_range(5, 50)   : TIMEOUT_CYCLES),
                    .wrong_sb_msg  (stim.do_wrong_sb ? TRAINERROR_Entry_req    : NOTHING       ),
                    .oor_after     (stim.do_oor       ? 0                      : TIMEOUT_CYCLES),
                    .num_iq_iters  (stim.iq_iters),
                    .late_iq       (stim.do_late_iq),
                    .may_error     (stim.expects_error())
                );

                // Track whether this primary test was a clean success
                prev_was_clean_pass = !stim.expects_error();

                // -- No-reset chain: every 3rd test, run a chained test --------
                // Chain only when the previous test was a clean success so the
                // FSM is guaranteed to be in IDLE before the chained test starts.
                if (prev_was_clean_pass && (i % 3 == 0)) begin

                    if (!chain_stim.randomize()) begin
                        $display("ERROR: chain_stim.randomize() failed at rand_no=%0d", rand_no);
                        $stop;
                    end

                    $display("     |_ Chained (no reset): %s", chain_stim.to_string());

                    // NO apply_reset() here — only clear stimulus signals
                    clear_stimuli();
                    intf.phy_negotiated_speed = chain_stim.speed;

                    start_test(
                        .abort_after   (chain_stim.do_timeout  ? $urandom_range(15, 100) : TIMEOUT_CYCLES),
                        .wrong_sb_after(chain_stim.do_wrong_sb ? $urandom_range(5, 50)   : TIMEOUT_CYCLES),
                        .wrong_sb_msg  (chain_stim.do_wrong_sb ? TRAINERROR_Entry_req    : NOTHING       ),
                        .oor_after     (chain_stim.do_oor       ? 0                      : TIMEOUT_CYCLES),
                        .num_iq_iters  (chain_stim.iq_iters),
                        .late_iq       (chain_stim.do_late_iq),
                        .may_error     (chain_stim.expects_error())
                    );
                end

            end // for

        end : rand_phase

        // =====================================================================
        // --- Final Result ----------------------------------------------------
        // =====================================================================
        $display("\n");
        if (fail_count == 0) begin
            $display("      ================================================     ");
            $display("    ================  Congratulations!  ================   ");
            $display("  ==================  All %0d tests passed!  ============= ", success_count);
            $display("    ================    Successfully    ================   ");
            $display("      ================================================     \n");
        end else begin
            $display("  ==========================================");
            $display("  FAIL: %0d tests failed out of %0d total.", fail_count, success_count + fail_count);
            $display("  ==========================================");
        end

        @(posedge lclk);
        $stop;
    end

endmodule
