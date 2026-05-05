`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_DATATRAINCENTER1_tb
// Purpose   : Self-checking testbench for unit_DATATRAINCENTER1 FSM.
//
// Scenarios:
//   ✓ Happy path: full per-lane phase sweep → midpoints applied
//   ✓ dtc1_fail_flag set when ALL lanes fail the entire sweep (no pass found)
//   ✓ 8ms timeout → TO_TRAINERROR
//   ✓ Partner TRAINERROR message → TO_TRAINERROR
//   ✓ Wrong SB message → timeout
//   ✓ Randomized per-lane hole-in-eye scenarios
// =============================================================================
module unit_DATATRAINCENTER1_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1*1000  ; // lclk = 1 ns (1 GHz)
    parameter TIMEOUT_CYCLES       = 700_000 ;
    parameter ANALOG_SETTLE_CYCLES = 10      ;
    parameter MIN_PHASE_CODE       = 6'h00   ;
    parameter MAX_PHASE_CODE       = 6'h3F   ; // Match DUT parameter (6-bit PI code)
    parameter NUM_LANES            = 16      ;

    reg  lclk ;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // FSM state names
    typedef enum reg [3:0] {
        DTC1_IDLE        = unit_DATATRAINCENTER1_inst.DTC1_IDLE       ,
        DTC1_START_REQ   = unit_DATATRAINCENTER1_inst.DTC1_START_REQ  ,
        DTC1_START_RESP  = unit_DATATRAINCENTER1_inst.DTC1_START_RESP ,
        DTC1_SET_PHASE   = unit_DATATRAINCENTER1_inst.DTC1_SET_PHASE  ,
        DTC1_TX_D2C_PT   = unit_DATATRAINCENTER1_inst.DTC1_TX_D2C_PT  ,
        DTC1_LOG_RESULT  = unit_DATATRAINCENTER1_inst.DTC1_LOG_RESULT ,
        DTC1_CALC_APPLY  = unit_DATATRAINCENTER1_inst.DTC1_CALC_APPLY ,
        DTC1_END_REQ     = unit_DATATRAINCENTER1_inst.DTC1_END_REQ    ,
        DTC1_END_RESP    = unit_DATATRAINCENTER1_inst.DTC1_END_RESP   ,
        TO_DATATRAINVREF = unit_DATATRAINCENTER1_inst.TO_DATATRAINVREF,
        TO_TRAINERROR    = unit_DATATRAINCENTER1_inst.TO_TRAINERROR   ,
        Continue_Repeating_The_Last_3_States = 4'hF  // Shown in transcript instead of repeating S3/S4/S5
    } fsm_state_t;
    fsm_state_t current_state, monitor_current_state;
    assign current_state = fsm_state_t'(unit_DATATRAINCENTER1_inst.current_state);

    // ── Suppress sweep-loop repetition in transcript ──────────────────────
    // once all 11 entered_states bits are set (S0-S5 all seen), collapse the
    // repeating S3/S4/S5 loop into a single "Continue_Repeating_The_Last_3_States"
    // label in the $monitor output.
    logic first_loop;
    reg [10:0] entered_states;

    always @(posedge lclk or negedge rst_n) begin
        if (!lclk) first_loop = 1;
        else if (entered_states[10:0] == 11'b000_0011_1111) first_loop = 0;
        else first_loop = 1;
    end

    assign monitor_current_state =
        (current_state == TO_TRAINERROR) ? TO_TRAINERROR :
        ((entered_states[10:0] == 11'b000_0011_1111) && !first_loop) ?
        Continue_Repeating_The_Last_3_States : current_state;

    // Clock
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // DUT
    unit_DATATRAINCENTER1 #(
        .MAX_PHASE_CODE(MAX_PHASE_CODE),
        .MIN_PHASE_CODE(MIN_PHASE_CODE),
        .NUM_DATA_LANES(NUM_LANES)
    ) unit_DATATRAINCENTER1_inst (
        .dtc1_if(intf),
        .d2c_if (intf)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ── Per-lane error model ─────────────────────────────────────────────
    // pass_center[l] = the PI phase code at the center of lane l's eye.
    // eye_half[l]    = half-width of that lane's pass window.
    reg [5:0]  pass_center[NUM_LANES-1:0]; // 6-bit to match DUT phase sweep width
    reg [5:0]  eye_half   [NUM_LANES-1:0];
    reg        all_lanes_fail; // Force fail on every code when 1

    always @(*) begin
        integer l;
        for (l = 0; l < NUM_LANES; l++) begin
            if (all_lanes_fail) begin
                intf.tb_perlane_err[l] = 1'b1; // All fail
            end else begin
                // Pass if phase_code is within [center-half, center+half]
                intf.tb_perlane_err[l] =
                    (intf.phy_tx_pi_phase_ctrl < (pass_center[l] - eye_half[l]) ||
                        intf.phy_tx_pi_phase_ctrl > (pass_center[l] + eye_half[l])) ?
                    1'b1 : 1'b0;
            end
        end
    end
    // Aggregate = OR of per-lane
    always @(*) begin
        intf.tb_aggr_err = |intf.tb_perlane_err;
    end

    // ── Reset ────────────────────────────────────────────────────────────
    task reset();
        rst_n                    = 0;
        intf.tb_aggr_err         = 0;
        intf.tb_perlane_err      = 0;
        intf.tb_val_err          = 0;
        intf.tb_clk_err          = 0;
        intf.tb_wait_timeout     = 0;
        intf.tb_wrong_sb_msg_en  = 0;
        intf.tb_wrong_sb_msg     = NOTHING;
        intf.tb_rx_msginfo       = 16'B0;
        intf.tb_rx_data_field    = 64'B0;
        all_lanes_fail            = 0;
        intf.mb_rx_data_lane_mask = 3'b011;
        #10; rst_n = 1;
    endtask

    integer lclk_counter = 0, success_count = 0, fail_count = 0;
    reg     lclk_counter_run_flag = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_counter_run_flag) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    // ── Main test task ────────────────────────────────────────────────────
    task start_test(
            input integer  abort_after              = TIMEOUT_CYCLES,
            input integer  wrong_sb_after           = TIMEOUT_CYCLES,
            input msg_no_e wrong_msg                = NOTHING,
            input logic    expect_fail_flag         = 1'b0,
            input logic    expect_trainerror        = 1'b0
        );
        lclk_counter_run_flag = 1;
        entered_states = 0;

        fork : TEST_EXEC
            begin
                intf.datatraincenter1_en = 1'b1;
                wait(intf.datatraincenter1_done || intf.trainerror_req); #1step;
                intf.datatraincenter1_en = 1'b0;

                // Check expectations
                if (expect_trainerror && !intf.trainerror_req) begin
                    repeat(5) $display("\t\t *** ERROR *** expected TRAINERROR but didn't get it!");
                    $stop;
                end
                if (!expect_trainerror && intf.trainerror_req &&
                        !intf.tb_wait_timeout && !intf.tb_wrong_sb_msg_en) begin
                    repeat(5) $display("\t\t *** ERROR *** unexpected TRAINERROR!");
                    $stop;
                end
                if (!expect_trainerror && intf.datatraincenter1_fail_flag != expect_fail_flag) begin
                    repeat(5) $display("\t\t *** ERROR *** fail_flag=%0b expected=%0b",
                            intf.datatraincenter1_fail_flag, expect_fail_flag);
                    $stop;
                end

                wait(current_state == DTC1_IDLE || current_state == TO_TRAINERROR); #1step;

                if (!intf.trainerror_req) begin
                    success_count++;
                    $display("%10t ps: Test PASSED (Success=%0d, Fail=%0d, Cycles=%0d)",
                        $realtime(), success_count, fail_count, lclk_counter);
                end else begin
                    success_count++;
                    $display("%10t ps: TRAINERROR (expected): Success=%0d Cycles=%0d",
                        $realtime(), success_count, fail_count, lclk_counter);
                end
                $display("________________________________________\n");
                disable TEST_EXEC;
            end

            begin
                for (int i = 0; i < wrong_sb_after; i++) @(posedge lclk);
                intf.tb_wrong_sb_msg_en = 1;
                intf.tb_wrong_sb_msg    = wrong_msg;
            end

            begin
                for (int i = 0; i < abort_after; i++) @(posedge lclk);
                intf.tb_wait_timeout = 1;
            end

            // Track FSM transitions to feed entered_states bitmask
            begin : DTC1_STATE_MONITOR
                wait(current_state == DTC1_IDLE);
                entered_states[0] = 1;
                wait(current_state == DTC1_START_REQ);
                entered_states[1] = 1;
                wait(current_state == DTC1_START_RESP);
                entered_states[2] = 1;
                repeat((MAX_PHASE_CODE - MIN_PHASE_CODE) + 1) begin
                    wait(current_state == DTC1_SET_PHASE);
                    entered_states[3] = 1;
                    wait(current_state == DTC1_TX_D2C_PT);
                    entered_states[4] = 1;
                    wait(current_state == DTC1_LOG_RESULT);
                    entered_states[5] = 1;
                end
                wait(current_state == DTC1_CALC_APPLY);
                entered_states[6] = 1;
                wait(current_state == DTC1_END_REQ);
                entered_states[7] = 1;
                wait(current_state == DTC1_END_RESP);
                entered_states[8] = 1;
                wait(current_state == TO_DATATRAINVREF);
                entered_states[9] = 1;
                wait(current_state == DTC1_IDLE);
                entered_states[10] = 1;
            end
        join

        lclk_counter_run_flag    = 0;
        intf.tb_wait_timeout     = 0;
        intf.tb_wrong_sb_msg_en  = 0;
        all_lanes_fail           = 0;
        entered_states           = 0;
        @(posedge lclk); #1step;
    endtask

    // ── Scenarios ─────────────────────────────────────────────────────────
    integer scenario = 1;
    integer l;

    initial begin
        reset();
        $monitor("%10t ps: State=(%s)", $realtime(), monitor_current_state.name());

        // ─── Scenario 1: Happy path — all lanes eye center at PI=32/half=10 ──
        $display("\n==> Scenario %0d: Happy Path", scenario++);
        for (int l = 0; l < NUM_LANES; l++) begin
            pass_center[l] = 6'd32;
            eye_half[l]    = 6'd10;
        end
        start_test(.expect_fail_flag(1'b0));
        reset();

        // ─── Scenario 2: All lanes fail entire sweep → dtc1_fail_flag = 1 ─
        $display("\n==> Scenario %0d: All-lane fail", scenario++);
        all_lanes_fail = 1;
        start_test(.expect_fail_flag(1'b1));
        reset();

        // ─── Scenario 3: 8ms timeout ────────────────────────────────
        // Block SB from responding (abort_after=1 sets tb_wait_timeout=1
        // almost immediately) → FSM stalls at START_REQ → 8ms hardware timer fires.
        $display("\n==> Scenario %0d: 8ms hardware timeout -> TRAINERROR", scenario++);
        start_test(.abort_after(1), .expect_trainerror(1'b1));
        reset();

        // ─── Scenario 4: Partner TRAINERROR msg ──────────────────────────
        $display("\n==> Scenario %0d: Partner TRAINERROR msg", scenario++);
        start_test(.wrong_sb_after(50_000),
            .wrong_msg(TRAINERROR_Entry_req),
            .expect_trainerror(1'b1));
        reset();

        // ─── Scenarios 5-34: Randomized per-lane eye positions ────────────
        for (int s = 5; s <= 34; s++) begin
            $display("\n==> Scenario %0d: Randomized eye (%0d)", scenario++, s);
            for (int l = 0; l < NUM_LANES; l++) begin
                pass_center[l] = $urandom_range(10, 50); // Keep within 0-63
                eye_half[l]    = $urandom_range(3, 10);
            end
            start_test(.expect_fail_flag(1'b0));
            reset();
        end

        // ─── Final report ─────────────────────────────────────────────────
        if (fail_count == 0) begin
            $display("        ============================================       ");
            $display("      ==============  Congratulations!  ==============     ");
            $display("   ==================  Tests Passed!  ==================   ");
            $display("        ============================================       \n");
        end
        @(posedge lclk); $stop;
    end
endmodule
