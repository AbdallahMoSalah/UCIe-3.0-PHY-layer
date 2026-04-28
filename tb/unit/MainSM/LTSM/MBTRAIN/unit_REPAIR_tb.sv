`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_REPAIR_tb
// Purpose   : Self-checking testbench for unit_REPAIR FSM.
//
// Scenarios:
//   1. Happy REPAIR path: linkspeed_fail_flag=0
//      → INIT_REQ → INIT_RESP → APPLY_REPAIR_REQ → END_REQ → END_RESP → TO_DONE
//   2. DEGRADE path: linkspeed_fail_flag=1
//      → INIT_REQ → INIT_RESP → APPLY_DEGRADE_REQ → APPLY_DEGRADE_RESP → END_REQ → END_RESP → TO_DONE
//   3. 8ms hardware timeout → TO_TRAINERROR
//   4. Timeout mid-degrade path → TO_TRAINERROR
//   5–104. 100 randomised linkspeed_fail_flag combos
// =============================================================================
module unit_REPAIR_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1000    ; // lclk = 1 ns (1 GHz) – in ps
    parameter TIMEOUT_CYCLES       = 10_000  ;
    parameter ANALOG_SETTLE_CYCLES = 10      ;
    parameter SB_ECHO_DELAY        = 20      ; // lclk cycles before SB echo fires

    reg  lclk;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // ── FSM state enum (mirrors unit_REPAIR localparams) ─────────────────────
    typedef enum reg [3:0] {
        RP_IDLE               = 4'h0,
        RP_INIT_REQ           = 4'h1,
        RP_INIT_RESP          = 4'h2,
        RP_APPLY_REPAIR_REQ   = 4'h3,
        RP_APPLY_DEGRADE_REQ  = 4'h4,
        RP_APPLY_DEGRADE_RESP = 4'h5,
        RP_END_REQ            = 4'h6,
        RP_END_RESP           = 4'h7,
        TO_DONE               = 4'h8,
        TO_TRAINERROR         = 4'h9
    } fsm_state_t;

    fsm_state_t current_state;
    assign current_state = fsm_state_t'(unit_REPAIR_inst.current_state);

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // ── DUT ───────────────────────────────────────────────────────────────────
    unit_REPAIR unit_REPAIR_inst (
        .rp_if(intf)
    );

    // ── Minimal shared infrastructure (8ms timer + analog settle) ─────────────
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ── Dedicated SB echo ─────────────────────────────────────────────────────
    // Simple deterministic echo: watches tx_sb_msg_valid, after SB_ECHO_DELAY
    // cycles echoes the same message back on rx_sb_msg.
    // For RP_APPLY_REPAIR_REQ the partner drives apply_repair_req;
    // we inject it separately via the echo so the DUT receives it.
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
            intf.rx_sb_msg_valid <= 0; // Default deassert

            if (!echo_active) begin
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
                    intf.rx_sb_msg_valid <= 1;
                    intf.rx_sb_msg       <= echo_msg;
                    intf.rx_msginfo      <= 0;
                    intf.rx_data_field   <= 0;
                    echo_active          <= 0;
                    echo_msg             <= NOTHING;
                end
            end
        end
    end

    // ── Reset task ─────────────────────────────────────────────────────────────
    task reset();
        rst_n                   = 0;
        intf.tb_aggr_err        = 0;
        intf.tb_perlane_err     = 0;
        intf.tb_val_err         = 0;
        intf.tb_clk_err         = 0;
        intf.tb_wait_timeout    = 0;
        intf.tb_wrong_sb_msg_en = 0;
        intf.tb_wrong_sb_msg    = NOTHING;
        intf.tb_rx_msginfo      = 16'h0;
        intf.tb_rx_data_field   = 64'h0;
        intf.linkspeed_fail_flag = 0;
        intf.repair_en           = 0;
        #(LCLK_PERIOD*2); rst_n = 1;
        #(LCLK_PERIOD*2);
    endtask

    // ── Cycle counter ──────────────────────────────────────────────────────────
    integer lclk_counter = 0, success_count = 0, fail_count = 0;
    reg     lclk_ctr_en  = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_ctr_en) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    // ── start_test task ────────────────────────────────────────────────────────
    task start_test(
            input integer  abort_after       = TIMEOUT_CYCLES,
            input logic    expect_done       = 1'b1,
            input logic    expect_trainerror = 1'b0
        );
        lclk_ctr_en = 1;

        fork : TEST_EXEC
            // ── Main thread ──────────────────────────────────────────────────
            begin
                intf.repair_en = 1'b1;
                wait(intf.repair_done || intf.trainerror_req);
                @(posedge lclk); #1step;
                intf.repair_en = 1'b0;

                // Checks
                if (expect_trainerror && !intf.trainerror_req) begin
                    $display("\t *** FAIL *** expected TRAINERROR"); fail_count++;
                    $display("   -> Successes=%0d Fails=%0d lclk=%0d", success_count, fail_count, lclk_counter);
                    $display("________________________________________\n");
                    disable TEST_EXEC;
                end
                if (!expect_trainerror && intf.trainerror_req) begin
                    $display("\t *** FAIL *** unexpected TRAINERROR (state=%s)", current_state.name()); fail_count++;
                    $display("   -> Successes=%0d Fails=%0d lclk=%0d", success_count, fail_count, lclk_counter);
                    $display("________________________________________\n");
                    disable TEST_EXEC;
                end
                if (expect_done && !intf.repair_done) begin
                    $display("\t *** FAIL *** expected repair_done=1"); fail_count++;
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

            // ── Hardware timeout injector ──────────────────────────────────────
            begin
                repeat(abort_after) @(posedge lclk);
                intf.tb_wait_timeout = 1;
            end
        join

        lclk_ctr_en          = 0;
        intf.tb_wait_timeout = 0;
        @(posedge lclk); #1step;
    endtask

    // ── Scenarios ─────────────────────────────────────────────────────────────
    integer scenario = 1;

    initial begin
        reset();
        $monitor("%10t ps: State=(%s)", $realtime(), current_state.name());

        // ── Scenario 1: REPAIR path (linkspeed_fail_flag=0) ──────────────────
        $display("\n==> Scenario %0d: REPAIR path (linkspeed_fail_flag=0) → TO_DONE", scenario++);
        intf.linkspeed_fail_flag = 0;
        start_test(.expect_done(1'b1));
        reset();

        // ── Scenario 2: DEGRADE path (linkspeed_fail_flag=1) ─────────────────
        $display("\n==> Scenario %0d: DEGRADE path (linkspeed_fail_flag=1) → TO_DONE", scenario++);
        intf.linkspeed_fail_flag = 1;
        start_test(.expect_done(1'b1));
        reset();

        // ── Scenario 3: 8ms hardware timeout at INIT_REQ → TRAINERROR ────────
        $display("\n==> Scenario %0d: 8ms timeout at INIT_REQ → TRAINERROR", scenario++);
        intf.linkspeed_fail_flag = 0;
        start_test(.abort_after(1), .expect_trainerror(1'b1));
        reset();

        // ── Scenario 4: Timeout mid-degrade (abort after INIT is done) ────────
        $display("\n==> Scenario %0d: Timeout mid-DEGRADE → TRAINERROR", scenario++);
        intf.linkspeed_fail_flag = 1;
        // abort_after=75: enough time for INIT_REQ+INIT_RESP to complete (~44 cycles)
        // but not enough for APPLY_DEGRADE_REQ to echo (~65+)
        start_test(.abort_after(75), .expect_trainerror(1'b1));
        reset();

        // ── Scenarios 5-104: 100 randomised linkspeed_fail_flag combos ────────
        for (int s = 5; s <= 104; s++) begin
            reg rnd_fail;
            rnd_fail = $urandom_range(0, 1);

            $display("\n==> Scenario %0d: Rand linkspeed_fail_flag=%0b | path=%s",
                scenario++, rnd_fail, rnd_fail ? "DEGRADE" : "REPAIR");

            intf.linkspeed_fail_flag = rnd_fail;
            start_test(.expect_done(1'b1));
            reset();
        end

        // ── Final report ───────────────────────────────────────────────────────
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
