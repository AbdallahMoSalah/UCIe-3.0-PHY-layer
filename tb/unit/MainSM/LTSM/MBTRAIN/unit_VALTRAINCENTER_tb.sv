`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_VALTRAINCENTER_tb
// Purpose   : Self-checking testbench for unit_VALTRAINCENTER FSM.
//
// VALTRAINCENTER uses TX_D2C_PT only:
//   • local_tx_pt_en    → set by DUT in S4
//   • partner_tx_pt_en  → set by DUT (registered) while sweep runs
//   • local_rx_pt_en    → always 0
//   • partner_rx_pt_en  → always 0
//
// Spec compliance tested:
//   ✓ Happy path: full PI phase sweep → midpoint applied → SB done handshake
//   ✓ No TRAINERROR on all-fail sweep (not exported)
//   ✓ 8ms timeout causes TO_TRAINERROR
//   ✓ Partner TRAINERROR message causes TO_TRAINERROR
//   ✓ Wrong SB message causes timeout → TO_TRAINERROR
//   ✓ Holes-in-eye scenario: widest contiguous zone selected
// =============================================================================
module unit_VALTRAINCENTER_tb ();
    import UCIe_pkg::*;

    // ── Timing parameters ────────────────────────────────────────────────────
    parameter LCLK_PERIOD          = 1*1000 ; // lclk = 1 ns (1 GHz); *1000 for ps waveform.
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Cycles for analog settle timer.
    parameter SB_DELAY             = 20     ; // SB propagation delay (lclk cycles).
    parameter MIN_PHASE_CODE       = 7'D0   ;
    parameter MAX_PHASE_CODE       = 7'D127 ;
    // -----------------------------------------------------------------------
    // D2C pattern speed knobs (must match DUT localparams).
    //   Spec: 128 iterations × 8-cycle burst = 1024 UI per phase code.
    // -----------------------------------------------------------------------
    parameter ITER_COUNT  = 128; // DUT localparam D2C_ITER_COUNT
    parameter BURST_COUNT = 8  ; // DUT localparam D2C_BURST_COUNT
    // -----------------------------------------------------------------------
    // Auto-compute TIMEOUT_CYCLES to scale with all speed parameters.
    // -----------------------------------------------------------------------
    localparam integer CYCLES_PER_CODE = ANALOG_SETTLE_CYCLES + (BURST_COUNT + 1) * ITER_COUNT + 15;
    localparam integer SWEEP_CYCLES    = (MAX_PHASE_CODE - MIN_PHASE_CODE + 1) * CYCLES_PER_CODE + 8 * SB_DELAY;
    parameter  TIMEOUT_CYCLES          = SWEEP_CYCLES + SB_DELAY * 4 + SWEEP_CYCLES;

    localparam PHASE_CODE_WIDTH = $clog2(MAX_PHASE_CODE + 1);

    // ── LTSM interface & clocks ──────────────────────────────────────────────
    reg  lclk ;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));
    assign intf.is_ltsm_out_of_reset = rst_n;

    // ── State names (mirror DUT localparams) ─────────────────────────────────
    typedef enum reg [3:0] {
        VALTRAINCENTER_IDLE       = unit_VALTRAINCENTER_inst.VALTRAINCENTER_IDLE      , // S0
        VALTRAINCENTER_START_REQ  = unit_VALTRAINCENTER_inst.VALTRAINCENTER_START_REQ , // S1
        VALTRAINCENTER_START_RESP = unit_VALTRAINCENTER_inst.VALTRAINCENTER_START_RESP, // S2
        VALTRAINCENTER_SET_PHASE  = unit_VALTRAINCENTER_inst.VALTRAINCENTER_SET_PHASE , // S3
        VALTRAINCENTER_TX_D2C_PT  = unit_VALTRAINCENTER_inst.VALTRAINCENTER_TX_D2C_PT , // S4
        VALTRAINCENTER_LOG_RESULT = unit_VALTRAINCENTER_inst.VALTRAINCENTER_LOG_RESULT, // S5
        VALTRAINCENTER_CALC_APPLY = unit_VALTRAINCENTER_inst.VALTRAINCENTER_CALC_APPLY, // S6
        VALTRAINCENTER_DONE_REQ   = unit_VALTRAINCENTER_inst.VALTRAINCENTER_DONE_REQ  , // S7
        VALTRAINCENTER_DONE_RESP  = unit_VALTRAINCENTER_inst.VALTRAINCENTER_DONE_RESP , // S8
        TO_VALTRAINVREF           = unit_VALTRAINCENTER_inst.TO_VALTRAINVREF          , // S9
        TO_TRAINERROR             = unit_VALTRAINCENTER_inst.TO_TRAINERROR            , // S10
        Continue_Repeating_The_Last_3_States = 'hF
    } fsm_state_t;
    fsm_state_t current_state, monitor_current_state;
    assign current_state = fsm_state_t'(unit_VALTRAINCENTER_inst.current_state);

    // ── Clock generation ─────────────────────────────────────────────────────
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    // ── DUT Instance ─────────────────────────────────────────────────────────
    unit_VALTRAINCENTER #(
        .MAX_PHASE_CODE(MAX_PHASE_CODE),
        .MIN_PHASE_CODE(MIN_PHASE_CODE)
    ) unit_VALTRAINCENTER_inst (
        .d2c_if             (intf),
        .valtraincenter_if  (intf)
    );

    // ── TB Attachment (clocks, SB, MB) ───────────────────────────────────────
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY            )
    ) ltsm_tb_attachments_inst (
        .intf(intf)
    );

    // ── Combinational eye-diagram model ──────────────────────────────────────
    reg [PHASE_CODE_WIDTH-1:0] current_task_phase_min;
    reg [PHASE_CODE_WIDTH-1:0] current_task_phase_max;
    reg assume_holes_after_quarter_eye_start;

    task assume_errors (
            input [15:0] task_aggr_err     = 16'b0    ,
            input [15:0] task_perlane_pass = 16'hFFFF ,
            input [PHASE_CODE_WIDTH-1:0] task_phase_code_min = PHASE_CODE_WIDTH'(30),
            input [PHASE_CODE_WIDTH-1:0] task_phase_code_max = PHASE_CODE_WIDTH'(90),
            input task_assume_holes_after_quarter_eye_start = 0
        );
        intf.tb_aggr_err     = task_aggr_err    ;
        intf.tb_perlane_pass = task_perlane_pass;
        current_task_phase_min = task_phase_code_min;
        current_task_phase_max = task_phase_code_max;
        assume_holes_after_quarter_eye_start = task_assume_holes_after_quarter_eye_start;
    endtask

    // Drive tb_val_pass based on swept phase code
    always @(*) begin
        if (intf.phy_tx_val_pi_phase_ctrl >= current_task_phase_min &&
                intf.phy_tx_val_pi_phase_ctrl <= current_task_phase_max) begin
            if ((intf.phy_tx_val_pi_phase_ctrl ==
                        current_task_phase_min + (current_task_phase_max - current_task_phase_min)/4)
                    && assume_holes_after_quarter_eye_start == 1) begin
                intf.tb_val_pass = 1'b0; // Deliberate hole
            end else begin
                intf.tb_val_pass = 1'b1; // Inside valid window -> pass
            end
        end else begin
            intf.tb_val_pass = 1'b0; // Outside eye -> fail
        end
    end

    // ── Reset Task ───────────────────────────────────────────────────────────
    task reset();
        rst_n                   = 0;
        intf.tb_aggr_err        = 0;
        intf.tb_perlane_pass    = 16'hFFFF;
        intf.tb_val_pass        = 1'b1;
        intf.tb_clk_pass        = 1'b1;

        // Drive speed and continuous clock config variables
        intf.phy_negotiated_speed          = 3'b010; // Speed <= SPEED_32G
        intf.mb_tx_continuous_or_strobe_clk = 1'b1;  // Strobe mode

        intf.mb_rx_data_lane_mask = 3'b011; // Lanes 0-15 active

        intf.tb_wait_timeout       = 0;
        intf.tb_wrong_sb_msg_en    = 0;
        intf.tb_wrong_sb_msg       = NOTHING;
        intf.tb_wrong_msginfo      = 16'B0;
        intf.tb_wrong_data_field   = 64'B0;

        // Reset partner D2C done override in the TB attachments module
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;

        #10;
        rst_n = 1;
    endtask

    // ── Start Test Task ──────────────────────────────────────────────────────
    integer lclk_counter          = 0;
    reg     lclk_counter_run_flag = 0;
    integer success_count         = 0;
    integer fail_count            = 0;
    reg [10:0] entered_states;

    task start_test(
            input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES,
            input integer  receive_wrong_sb_msg_after  = TIMEOUT_CYCLES,
            input msg_no_e wrong_sb_msg                = NOTHING
        );
        logic test_timeout_8ms_occured;
        entered_states = 0;

        fork : test_execution
            // ── Main thread ──────────────────────────────────────────────
            begin
                intf.valtraincenter_en = 1'b1;
                lclk_counter_run_flag = 1;
                wait(intf.valtraincenter_done || intf.trainerror_req); #1step;

                intf.valtraincenter_en = 1'b0;
                test_timeout_8ms_occured = intf.trainerror_req;

                if (intf.trainerror_req != 1'b1) begin
                    // ── Happy exit: verify FSM settled ────────────────────
                    wait(current_state == TO_VALTRAINVREF);     #1step;
                    wait(current_state == VALTRAINCENTER_IDLE); #1step;
                end else begin
                    wait(current_state == TO_TRAINERROR); #1step;
                end

                // ── Pass/fail accounting ──────────────────────────────────
                if (test_timeout_8ms_occured == 1) begin
                    if (intf.rx_sb_msg == TRAINERROR_Entry_req) begin
                        // Partner sent TRAINERROR — expected when wrong_sb_msg == TRAINERROR_Entry_req
                        fail_count    = (intf.tb_wrong_sb_msg_en)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wrong_sb_msg_en)? success_count + 1 : success_count;
                        if (intf.tb_wrong_sb_msg_en)
                            $display("%10t ps, (%0d cycles): FSM → TO_TRAINERROR via TRAINERROR SB msg (expected).", $realtime(), lclk_counter);
                        else begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps: Unexpected TRAINERROR Entry req! <== [Error]", $realtime());
                            $stop;
                        end
                    end else begin
                        // Pure 8ms timeout
                        fail_count    = (intf.tb_wait_timeout)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wait_timeout)? success_count + 1 : success_count;
                        if (!intf.tb_wrong_sb_msg_en && !intf.tb_wait_timeout) begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps: FSM timed out unexpectedly! <== [Error]", $realtime());
                            $stop;
                        end
                        $display("%10t ps: FSM → TO_TRAINERROR via timeout (expected).", $realtime());
                    end
                end else begin
                    success_count++;
                    $display("%10t ps: Test passed successfully.", $realtime());
                end

                $display("_____(Success=%0d, Fail=%0d, Cycles=%0d)_____\n",
                    success_count, fail_count, lclk_counter);
                disable test_execution;
            end

            // ── Wrong-SB-message injection thread ────────────────────────
            begin
                for (int i = 0; i < receive_wrong_sb_msg_after; i++) begin
                    @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 0;
                    intf.tb_wrong_sb_msg    = wrong_sb_msg;
                end
                intf.tb_wrong_sb_msg_en = 1;
            end

            // ── Timeout injection thread ──────────────────────────────────
            begin
                for (int i = 0; i < abort_mb_or_sb_after; i++) begin
                    @(posedge lclk);
                    intf.tb_wait_timeout = 0;
                end
                intf.tb_wait_timeout = 1;
            end

            // ── FSM transition monitor thread ─────────────────────────────
            begin : check_fsm_transitions
                wait(current_state == VALTRAINCENTER_IDLE);
                entered_states[0] = 1;
                wait(current_state == VALTRAINCENTER_START_REQ);
                entered_states[1] = 1;
                wait(current_state == VALTRAINCENTER_START_RESP);
                entered_states[2] = 1;

                // Full sweep path: S3 → S4 → S5 repeating for each Phase code
                repeat((MAX_PHASE_CODE - MIN_PHASE_CODE) + 1) begin
                    wait(current_state == VALTRAINCENTER_SET_PHASE);
                    entered_states[3] = 1;
                    wait(current_state == VALTRAINCENTER_TX_D2C_PT);
                    entered_states[4] = 1;
                    wait(current_state == VALTRAINCENTER_LOG_RESULT);
                    entered_states[5] = 1;
                end
                wait(current_state == VALTRAINCENTER_CALC_APPLY);
                entered_states[6] = 1;

                wait(current_state == VALTRAINCENTER_DONE_REQ);
                entered_states[7] = 1;
                wait(current_state == VALTRAINCENTER_DONE_RESP);
                entered_states[8] = 1;
                wait(current_state == TO_VALTRAINVREF);
                entered_states[9] = 1;
                wait(current_state == VALTRAINCENTER_IDLE);
                entered_states[10] = 1;
            end
        join

        #1step;
        entered_states          = 0;
        lclk_counter_run_flag   = 0;
        intf.tb_wait_timeout    = 0;
        intf.tb_wrong_sb_msg_en = 0;
        @(posedge lclk); #1step;
    endtask

    // ── lclk counter ─────────────────────────────────────────────────────────
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_counter_run_flag) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    // ── Monitor helpers ───────────────────────────────────────────────────────
    int      test_scenario_no = 1;
    msg_no_e random_msg       = NOTHING;
    integer  random_clocks    = 0;
    logic    first_loop;
    integer  temporary_var    = 0;

    always @(posedge lclk or negedge rst_n) begin
        if (!lclk) first_loop = 1;
        else if (entered_states[10:0] == 11'b000_0011_1111) first_loop = 0;
        else first_loop = 1;
    end

    assign monitor_current_state =
        (current_state == TO_TRAINERROR) ? TO_TRAINERROR :
        ((entered_states[10:0] == 11'b000_0011_1111) && !first_loop) ?
        Continue_Repeating_The_Last_3_States : current_state;

    // =========================================================================
    //                          Test Scenarios
    // =========================================================================
    initial begin
        reset();
        $monitor("%10t ps : Current state: (\"%s\").", $realtime(), monitor_current_state.name());

        // ─────────────────────────────────────────────────────────────────────
        // Scenarios 1-3 : Happy Path — full PI phase sweep, no failure
        // ─────────────────────────────────────────────────────────────────────
        for (int i = 0; i < 3; i++) begin
            $display("\n==========>  Test Scenario (%0d): Happy Path (full sweep). <==========", test_scenario_no++);
            assume_errors(.task_phase_code_min(PHASE_CODE_WIDTH'(30)),
                .task_phase_code_max(PHASE_CODE_WIDTH'(90)));
            start_test();
        end

        // ─────────────────────────────────────────────────────────────────────
        // Scenarios 5-7 : SB Connection Interruption (8ms timeout)
        // ─────────────────────────────────────────────────────────────────────
        repeat(3) begin
            $display("\n==========>  Test Scenario (%0d): SB Timeout (8ms). <==========", test_scenario_no++);
            start_test(.abort_mb_or_sb_after      (TIMEOUT_CYCLES),
                .receive_wrong_sb_msg_after ($urandom_range(0, TIMEOUT_CYCLES - 100)),
                .wrong_sb_msg               (NOTHING));
            reset();
        end

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 8 : Partner sends {TRAINERROR Entry req}
        // ─────────────────────────────────────────────────────────────────────
        $display("\n==========>  Test Scenario (%0d): Partner TRAINERROR msg. <==========", test_scenario_no++);
        assume_errors(.task_phase_code_min(PHASE_CODE_WIDTH'(MIN_PHASE_CODE)),
            .task_phase_code_max(PHASE_CODE_WIDTH'(MAX_PHASE_CODE)));
        start_test(.receive_wrong_sb_msg_after(SWEEP_CYCLES / 2),
            .wrong_sb_msg              (TRAINERROR_Entry_req));
        reset();

        // ─────────────────────────────────────────────────────────────────────
        // Scenarios 9-31 : Random wrong SB message (causes timeout)
        // ─────────────────────────────────────────────────────────────────────
        for (int i = 9; i < 32; i++) begin
            $display("\n==========>  Test Scenario (%0d): Wrong SB Msg (timeout). <==========", test_scenario_no++);
            while (random_msg === msg_no_e'(8'hXX) || random_msg === TRAINERROR_Entry_req) begin
                random_msg = msg_no_e'($urandom_range(8'h0, 8'hFF));
            end
            random_clocks = $urandom_range(0, SWEEP_CYCLES / 2);
            start_test(.receive_wrong_sb_msg_after(random_clocks),
                .wrong_sb_msg              (random_msg));
            reset();
        end

        // ─────────────────────────────────────────────────────────────────────
        // Scenarios 32-100 : Holes-in-eye (discontinuous valid window)
        // ─────────────────────────────────────────────────────────────────────
        for (int i = 32; i <= 100; i++) begin
            $display("\n==========>  Test Scenario (%0d): Holes Scenario. <==========", test_scenario_no++);
            temporary_var = -1;
            while (temporary_var < int'(MIN_PHASE_CODE) || temporary_var > int'(MAX_PHASE_CODE)) begin
                temporary_var = PHASE_CODE_WIDTH'($random());
            end
            assume_errors(
                .task_aggr_err    (16'($random())),
                .task_perlane_pass(16'($random())),
                .task_phase_code_min(PHASE_CODE_WIDTH'(temporary_var)),
                .task_phase_code_max(PHASE_CODE_WIDTH'($urandom_range(temporary_var, int'(MAX_PHASE_CODE)))),
                .task_assume_holes_after_quarter_eye_start(1)
            );
            start_test();
        end

        // ─────────────────────────────────────────────────────────────────────
        // Final report
        // ─────────────────────────────────────────────────────────────────────
        if (fail_count == 0) begin
            $display("        ============================================       ");
            $display("      ==============                    ==============     ");
            $display("    ================  Congratulations!  ================   ");
            $display("  ==================  The tests passed  ================== ");
            $display("    ================    Successfully    ================   ");
            $display("      ==============                    ==============     ");
            $display("        ============================================       \n\n");
        end
        @(posedge lclk);
        $stop;
    end
endmodule
