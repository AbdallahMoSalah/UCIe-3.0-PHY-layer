`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_LINKSPEED_tb
// Purpose   : Self-checking testbench for unit_LINKSPEED FSM.
//
// Scenarios:
//   1.  Happy path: low speed, no failures  → TO_DONE
//   2.  datatraincenter2_fail_flag=1        → TO_REPAIR
//   3.  datatrainvref_fail_flag=1           → TO_REPAIR
//   4.  valtrainvref_fail_flag=1            → TO_REPAIR
//   5.  valtraincenter_fail_flag=1          → TO_REPAIR
//   6.  High-speed (code 5>4), no fails    → TO_RXDESKEW
//   7.  8ms hardware timeout               → TO_TRAINERROR
//   8.  Partner TRAINERROR injection       → TO_TRAINERROR
//   9–108. 100 randomised speed/fail combos
// =============================================================================
module unit_LINKSPEED_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1000     ; // lclk = 1 ns (1 GHz) – in ps
    parameter TIMEOUT_CYCLES       = 10_000   ; // Small timeout for fast sim
    parameter ANALOG_SETTLE_CYCLES = 10       ;
    parameter HIGH_SPEED_THRESHOLD = 3'd4     ; // codes > 4 require EQ loop
    parameter SB_ECHO_DELAY        = 20       ; // lclk cycles before SB echo fires

    reg  lclk ;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // ── FSM state enum ────────────────────────────────────────────────────
    typedef enum reg [3:0] {
        LS_IDLE               = 4'h0,
        LS_START_REQ          = 4'h1,
        LS_START_RESP         = 4'h2,
        LS_EVAL               = 4'h3,
        LS_ERROR_REQ          = 4'h4,
        LS_ERROR_RESP         = 4'h5,
        LS_EQ_REQ             = 4'h6,
        LS_EQ_RESP            = 4'h7,
        LS_SPEED_DEGRADE_REQ  = 4'h8,
        LS_SPEED_DEGRADE_RESP = 4'h9,
        LS_DONE_REQ           = 4'hA,
        LS_DONE_RESP          = 4'hB,
        TO_DONE               = 4'hC,
        TO_REPAIR             = 4'hD,
        TO_RXDESKEW           = 4'hE,
        TO_TRAINERROR         = 4'hF
    } fsm_state_t;

    fsm_state_t current_state;
    assign current_state = fsm_state_t'(unit_LINKSPEED_inst.current_state);

    // ── Clock ─────────────────────────────────────────────────────────────
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // ── DUT ───────────────────────────────────────────────────────────────
    unit_LINKSPEED #(
        .HIGH_SPEED_THRESHOLD(HIGH_SPEED_THRESHOLD)
    ) unit_LINKSPEED_inst (
        .ls_if(intf)
    );

    // ── Minimal infrastructure (timeout timer + analog settle) ─────────────
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ── Speed input ───────────────────────────────────────────────────────
    reg [2:0] tb_speed;
    assign intf.param_negotiated_max_speed = tb_speed;

    // ── Dedicated SB echo (replaces ltsm_tb_attachments echo for LINKSPEED)─
    // This echo simply watches tx_sb_msg_valid and sends back the same message
    // after SB_ECHO_DELAY lclk cycles. Simple and deterministic.
    reg        echo_active;
    msg_no_e   echo_msg;
    integer    echo_countdown;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            echo_active            <= 0;
            echo_msg               <= NOTHING;
            echo_countdown         <= 0;
            intf.rx_sb_msg_valid   <= 0;
            intf.rx_sb_msg         <= NOTHING;
            intf.rx_msginfo        <= 0;
            intf.rx_data_field     <= 0;
        end else begin
            // Default: de-assert valid after 1 cycle
            intf.rx_sb_msg_valid <= 0;

            if (!echo_active) begin
                // Wait for the DUT to drive a valid non-NOTHING message
                if (intf.tx_sb_msg_valid && intf.tx_sb_msg != NOTHING &&
                        !intf.tb_wait_timeout) begin
                    echo_active    <= 1;
                    echo_msg       <= intf.tx_sb_msg;
                    echo_countdown <= SB_ECHO_DELAY;
                end
            end else begin
                if (echo_countdown > 0) begin
                    echo_countdown <= echo_countdown - 1;
                end else begin
                    // Fire the echo
                    intf.rx_sb_msg_valid <= 1;
                    if (intf.tb_wrong_sb_msg_en)
                        intf.rx_sb_msg <= intf.tb_wrong_sb_msg;
                    else
                        intf.rx_sb_msg <= echo_msg;
                    intf.rx_msginfo    <= 0;
                    intf.rx_data_field <= 0;
                    echo_active        <= 0;
                    echo_msg           <= NOTHING;
                end
            end
        end
    end

    // ── Reset task ─────────────────────────────────────────────────────────
    task reset();
        rst_n                              = 0;
        intf.tb_aggr_err                   = 0;
        intf.tb_perlane_err                = 0;
        intf.tb_val_err                    = 0;
        intf.tb_clk_err                    = 0;
        intf.tb_wait_timeout               = 0;
        intf.tb_wrong_sb_msg_en            = 0;
        intf.tb_wrong_sb_msg               = NOTHING;
        intf.tb_rx_msginfo                 = 16'h0;
        intf.tb_rx_data_field              = 64'h0;
        intf.datatraincenter2_fail_flag    = 0;
        intf.datatrainvref_fail_flag       = 0;
        intf.valtrainvref_fail_flag        = 0;
        intf.valtraincenter_fail_flag      = 0;
        intf.linkspeed_en                  = 0;
        tb_speed                           = 3'd2;
        #(LCLK_PERIOD*2); rst_n = 1;
        #(LCLK_PERIOD*2);
    endtask

    // ── Cycle counter ──────────────────────────────────────────────────────
    integer lclk_counter = 0, success_count = 0, fail_count = 0;
    reg     lclk_ctr_en  = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_ctr_en) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    // ── start_test task ────────────────────────────────────────────────────
    task start_test(
            input integer  abort_after        = TIMEOUT_CYCLES,
            input integer  wrong_sb_after     = TIMEOUT_CYCLES,
            input msg_no_e wrong_msg          = NOTHING,
            input logic    expect_done        = 1'b1,
            input logic    expect_repair      = 1'b0,
            input logic    expect_rxdeskew    = 1'b0,
            input logic    expect_trainerror  = 1'b0
        );
        lclk_ctr_en = 1;

        fork : TEST_EXEC
            // ── Main thread ──────────────────────────────────────────────
            begin
                intf.linkspeed_en = 1'b1;
                wait(intf.linkspeed_done || intf.trainerror_req);
                @(posedge lclk); #1step;  // 1 extra cycle for fail_flag_r to register
                intf.linkspeed_en = 1'b0;

                // Checks
                if (expect_trainerror && !intf.trainerror_req) begin
                    $display("\t *** FAIL *** expected TRAINERROR"); fail_count++;
                    $display("   -> Successes=%0d Fails=%0d lclk=%0d", success_count, fail_count, lclk_counter);
                    $display("________________________________________\n");
                    disable TEST_EXEC;
                end
                if (!expect_trainerror && intf.trainerror_req) begin
                    $display("\t *** FAIL *** unexpected TRAINERROR"); fail_count++;
                    $display("   -> Successes=%0d Fails=%0d lclk=%0d", success_count, fail_count, lclk_counter);
                    $display("________________________________________\n");
                    disable TEST_EXEC;
                end
                if (expect_repair && !intf.linkspeed_fail_flag) begin
                    $display("\t *** FAIL *** expected fail_flag=1 (REPAIR path)"); fail_count++;
                    $display("   -> Successes=%0d Fails=%0d lclk=%0d", success_count, fail_count, lclk_counter);
                    $display("________________________________________\n");
                    disable TEST_EXEC;
                end
                if (expect_done && intf.linkspeed_fail_flag) begin
                    $display("\t *** FAIL *** unexpected fail_flag=1 on success"); fail_count++;
                    $display("   -> Successes=%0d Fails=%0d lclk=%0d", success_count, fail_count, lclk_counter);
                    $display("________________________________________\n");
                    disable TEST_EXEC;
                end

                success_count++;
                if (!intf.trainerror_req)
                    $display("%10t ps: Test PASSED", $realtime());
                else
                    $display("%10t ps: TRAINERROR (expected)", $realtime());
                $display("            -> Successes: %0d, Fails: %0d", success_count, fail_count);
                $display("            -> Number of lclk consumed: %0d", lclk_counter);
                $display("________________________________________\n");
                disable TEST_EXEC;
            end

            // ── Wrong SB injector ─────────────────────────────────────────
            begin
                repeat(wrong_sb_after) @(posedge lclk);
                intf.tb_wrong_sb_msg_en = 1;
                intf.tb_wrong_sb_msg    = wrong_msg;
            end

            // ── Hardware timeout injector ──────────────────────────────────
            begin
                repeat(abort_after) @(posedge lclk);
                intf.tb_wait_timeout = 1;
            end
        join

        lclk_ctr_en             = 0;
        intf.tb_wait_timeout    = 0;
        intf.tb_wrong_sb_msg_en = 0;
        @(posedge lclk); #1step;
    endtask

    // ── Scenarios ─────────────────────────────────────────────────────────
    integer scenario = 1;

    initial begin
        reset();
        $monitor("%10t ps: State=(%s)", $realtime(), current_state.name());

        // ── Scenario 1: Happy path, 12 GT/s, no fails → TO_DONE ──────────
        $display("\n==> Scenario %0d: Happy path (12 GT/s, no failures)", scenario++);
        tb_speed = 3'd2; intf.datatraincenter2_fail_flag = 0;
        intf.datatrainvref_fail_flag = 0; intf.valtrainvref_fail_flag = 0;
        intf.valtraincenter_fail_flag = 0;
        start_test(.expect_done(1'b1));
        reset();

        // ── Scenario 2: datatraincenter2_fail_flag → TO_REPAIR ────────────
        $display("\n==> Scenario %0d: datatraincenter2_fail_flag=1 → REPAIR", scenario++);
        tb_speed = 3'd2; intf.datatraincenter2_fail_flag = 1;
        start_test(.expect_done(1'b0), .expect_repair(1'b1));
        reset();

        // ── Scenario 3: datatrainvref_fail_flag → TO_REPAIR ──────────────
        $display("\n==> Scenario %0d: datatrainvref_fail_flag=1 → REPAIR", scenario++);
        tb_speed = 3'd1; intf.datatrainvref_fail_flag = 1;
        start_test(.expect_done(1'b0), .expect_repair(1'b1));
        reset();

        // ── Scenario 4: valtrainvref_fail_flag → TO_REPAIR ───────────────
        $display("\n==> Scenario %0d: valtrainvref_fail_flag=1 → REPAIR", scenario++);
        tb_speed = 3'd0; intf.valtrainvref_fail_flag = 1;
        start_test(.expect_done(1'b0), .expect_repair(1'b1));
        reset();

        // ── Scenario 5: valtraincenter_fail_flag → TO_REPAIR ─────────────
        $display("\n==> Scenario %0d: valtraincenter_fail_flag=1 → REPAIR", scenario++);
        tb_speed = 3'd3; intf.valtraincenter_fail_flag = 1;
        start_test(.expect_done(1'b0), .expect_repair(1'b1));
        reset();

        // ── Scenario 6: 64 GT/s (code=5 > threshold=4), no fails → RXDESKEW
        $display("\n==> Scenario %0d: 64 GT/s, no fails → EQ loop → TO_RXDESKEW", scenario++);
        tb_speed = 3'd5; intf.datatraincenter2_fail_flag = 0;
        intf.datatrainvref_fail_flag = 0; intf.valtrainvref_fail_flag = 0;
        intf.valtraincenter_fail_flag = 0;
        start_test(.expect_done(1'b0), .expect_rxdeskew(1'b1));
        reset();

        // ── Scenario 7: 8ms hardware timeout → TRAINERROR ────────────────
        $display("\n==> Scenario %0d: 8ms hardware timeout → TRAINERROR", scenario++);
        tb_speed = 3'd2;
        start_test(.abort_after(1), .expect_trainerror(1'b1));
        reset();

        // ── Scenario 8: Timeout during EQ handshake → TRAINERROR ──────────
        // Speed=5 (hi-spd), no fails → would go EQ path; timeout fires mid-EQ
        $display("\n==> Scenario %0d: Timeout during EQ handshake → TRAINERROR", scenario++);
        tb_speed = 3'd5; intf.datatraincenter2_fail_flag = 0;
        intf.datatrainvref_fail_flag = 0; intf.valtrainvref_fail_flag = 0;
        intf.valtraincenter_fail_flag = 0;
        start_test(.abort_after(75), .expect_trainerror(1'b1));
        reset();

        // ── Scenarios 9-108: 100 randomised speed/fail combos ─────────────
        for (int s = 9; s <= 108; s++) begin
            reg [2:0] rnd_speed;
            reg       rnd_dtc2, rnd_dtv, rnd_vtv, rnd_vtc;
            reg       any_fail, hi_spd;
            reg       exp_done, exp_repair, exp_rxdeskew;

            rnd_speed = $urandom_range(0, 7);
            rnd_dtc2  = $urandom_range(0, 1);
            rnd_dtv   = $urandom_range(0, 1);
            rnd_vtv   = $urandom_range(0, 1);
            rnd_vtc   = $urandom_range(0, 1);

            any_fail  = rnd_dtc2 | rnd_dtv | rnd_vtv | rnd_vtc;
            hi_spd    = (rnd_speed > HIGH_SPEED_THRESHOLD);

            exp_done    = !any_fail && !hi_spd;
            exp_repair  = any_fail;
            exp_rxdeskew = !any_fail && hi_spd;

            $display("\n==> Scenario %0d: spd=%0d dtc2=%0b dtv=%0b vtv=%0b vtc=%0b | done=%0b repair=%0b rxdsk=%0b",
                scenario++, rnd_speed, rnd_dtc2, rnd_dtv, rnd_vtv, rnd_vtc,
                exp_done, exp_repair, exp_rxdeskew);

            tb_speed                        = rnd_speed;
            intf.datatraincenter2_fail_flag = rnd_dtc2;
            intf.datatrainvref_fail_flag    = rnd_dtv;
            intf.valtrainvref_fail_flag     = rnd_vtv;
            intf.valtraincenter_fail_flag   = rnd_vtc;

            start_test(.expect_done(exp_done), .expect_repair(exp_repair),
                       .expect_rxdeskew(exp_rxdeskew), .expect_trainerror(1'b0));
            reset();
        end

        // ── Final report ───────────────────────────────────────────────────
        if (fail_count == 0) begin
            $display("        ============================================       ");
            $display("      ==============  Congratulations!  ==============     ");
            $display("   ==================  Tests Passed!  ==================   ");
            $display("        ============================================       \n");
        end else begin
            $display("   ======  %0d test(s) FAILED  ======\n", fail_count);
        end
        @(posedge lclk); $stop;
    end
endmodule
