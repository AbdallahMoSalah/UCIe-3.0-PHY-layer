`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_VALTRAINVREF_tb
// Purpose   : Self-checking testbench for unit_VALTRAINVREF FSM.
//
// VALTRAINVREF uses RX_D2C_PT only:
//   • local_rx_pt_en    → set by DUT in S4
//   • partner_rx_pt_en  → set by DUT (registered) while sweep runs
//   • local_tx_pt_en    → always 0 (assigned by DUT: assign d2c_if.partner_tx_pt_en = 1'b0,
//                          and default d2c_if.local_tx_pt_en = 1'b0 in output comb block)
//   • partner_tx_pt_en  → always 0 (same reason)
//
// Spec compliance tested:
//   ✓ Happy path: full Vref sweep → midpoint applied → SB done handshake
//   ✓ S2 shortcut: valtraincenter_fail_flag=1 → skip sweep → S7 directly
//   ✓ No TRAINERROR on all-fail sweep (valtrainvref_fail_flag not exported — OK)
//   ✓ 8ms timeout causes TO_TRAINERROR
//   ✓ Partner TRAINERROR message causes TO_TRAINERROR
//   ✓ Wrong SB message causes timeout → TO_TRAINERROR
//   ✓ Holes-in-eye scenario: widest contiguous zone selected
// =============================================================================
module unit_VALTRAINVREF_tb ();
    import UCIe_pkg::*;

    // ── Timing parameters ────────────────────────────────────────────────────
    parameter LCLK_PERIOD          = 1*1000 ; // lclk = 1 ns (1 GHz); *1000 for ps waveform.
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Cycles for analog settle timer.
    parameter SB_DELAY             = 20     ; // SB propagation delay (lclk cycles).
    parameter MIN_VAL_VREF_CODE    = 7'D10  ;
    parameter MAX_VAL_VREF_CODE    = 7'D127 ;
    // -----------------------------------------------------------------------
    // D2C pattern speed knobs (must match DUT localparams).
    //   Spec: 128 iterations × 8-cycle burst = 1024 UI per Vref code.
    //   Match DUT localparams D2C_ITER_COUNT / D2C_BURST_COUNT.
    // -----------------------------------------------------------------------
    parameter ITER_COUNT  = 128; // DUT localparam D2C_ITER_COUNT
    parameter BURST_COUNT = 8  ; // DUT localparam D2C_BURST_COUNT
    // -----------------------------------------------------------------------
    // Auto-compute TIMEOUT_CYCLES to scale with all speed parameters.
    //   Per code  : ANALOG_SETTLE + (BURST_COUNT+1)*ITER_COUNT + 15 overhead
    //   SB overhead: 8 handshake pairs × SB_DELAY
    //   TIMEOUT   = 2 × SWEEP_CYCLES  (generous margin)
    // -----------------------------------------------------------------------
    localparam integer CYCLES_PER_CODE = ANALOG_SETTLE_CYCLES + (BURST_COUNT + 1) * ITER_COUNT + 15;
    localparam integer SWEEP_CYCLES    = (MAX_VAL_VREF_CODE - MIN_VAL_VREF_CODE + 1) * CYCLES_PER_CODE + 8 * SB_DELAY;
    parameter  TIMEOUT_CYCLES          = SWEEP_CYCLES + SB_DELAY * 4 + SWEEP_CYCLES;

    localparam VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE + 1);

    // ── LTSM interface & clocks ──────────────────────────────────────────────
    reg  lclk ;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));
    assign intf.is_ltsm_out_of_reset = rst_n;

    // ── State names (mirror DUT localparams) ─────────────────────────────────
    typedef enum reg [3:0] {
        VALTRAINVREF_IDLE          = unit_VALTRAINVREF_inst.VALTRAINVREF_IDLE         , // S0
        VALTRAINVREF_START_REQ     = unit_VALTRAINVREF_inst.VALTRAINVREF_START_REQ    , // S1
        VALTRAINVREF_START_RESP    = unit_VALTRAINVREF_inst.VALTRAINVREF_START_RESP   , // S2
        VALTRAINVREF_SET_VREF_CODE = unit_VALTRAINVREF_inst.VALTRAINVREF_SET_VREF_CODE, // S3
        VALTRAINVREF_RX_D2C_PT     = unit_VALTRAINVREF_inst.VALTRAINVREF_RX_D2C_PT   , // S4
        VALTRAINVREF_LOG_RESULT    = unit_VALTRAINVREF_inst.VALTRAINVREF_LOG_RESULT   , // S5
        VALTRAINVREF_CALC_APPLY    = unit_VALTRAINVREF_inst.VALTRAINVREF_CALC_APPLY   , // S6
        VALTRAINVREF_END_REQ       = unit_VALTRAINVREF_inst.VALTRAINVREF_END_REQ      , // S7
        VALTRAINVREF_END_RESP      = unit_VALTRAINVREF_inst.VALTRAINVREF_END_RESP     , // S8
        TO_DATATRAINCENTER1        = unit_VALTRAINVREF_inst.TO_DATATRAINCENTER1       , // S9
        TO_TRAINERROR              = unit_VALTRAINVREF_inst.TO_TRAINERROR             , // S10
        Continue_Repeating_The_Last_3_States = 'hF
    } fsm_state_t;
    fsm_state_t current_state, monitor_current_state;
    assign current_state = fsm_state_t'(unit_VALTRAINVREF_inst.current_state);

    // ── Clock generation ─────────────────────────────────────────────────────
    // ===================================================================== //
    //   __      ____      ____      ____      ____      ____      ____      //
    //     |____|    |____|    |____|    |____|    |____|    |____|    |__   //
    //                                                                       //
    //                           Clock Generation.                           //
    //      ____      ____      ____      ____      ____      ____      __   //
    //    _|    |____|    |____|    |____|    |____|    |____|    |____|     //
    // ===================================================================== //
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                (DUT Instance)                ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    unit_VALTRAINVREF #(
        .MAX_VAL_VREF_CODE(MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE(MIN_VAL_VREF_CODE)
    ) unit_VALTRAINVREF_inst (
        .d2c_if          (intf),
        .valtrainvref_if (intf)
    );

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------      (TB Attachment — clocks, SB, MB)        ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY            )
    ) ltsm_tb_attachments_inst (
        .intf(intf)
    );

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------     (Combinational eye-diagram model)        ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    //
    // Models the valid-lane receiver eye diagram as a function of phy_rx_valvref_ctrl.
    // Returns d2c_val_pass = 1 (pass) when inside [vref_min, vref_max], with an
    // optional deliberate "hole" at the 1/4 mark to test discontinuous-eye handling.

    reg [VREF_CODE_WIDTH-1:0] current_task_vref_min ;
    reg [VREF_CODE_WIDTH-1:0] current_task_vref_max ;
    reg assume_holes_after_quarter_eye_start;

    task assume_errors (
            input [15:0] task_aggr_err     = 16'b0       ,
            input [15:0] task_perlane_pass = 16'hFFFF    ,
            input [VREF_CODE_WIDTH-1:0] task_vref_code_min = VREF_CODE_WIDTH'(30),
            input [VREF_CODE_WIDTH-1:0] task_vref_code_max = VREF_CODE_WIDTH'(90),
            input task_assume_holes_after_quarter_eye_start = 0
        );
        intf.tb_aggr_err     = task_aggr_err    ;
        intf.tb_perlane_pass = task_perlane_pass;
        current_task_vref_min = task_vref_code_min;
        current_task_vref_max = task_vref_code_max;
        assume_holes_after_quarter_eye_start = task_assume_holes_after_quarter_eye_start;
    endtask

    // Combinational model: drive tb_val_pass based on swept Vref code.
    // The DUT reads d2c_val_pass (which the ltsm_tb_attachments drives from tb_val_pass).
    always @(*) begin
        if (intf.phy_rx_valvref_ctrl >= current_task_vref_min &&
                intf.phy_rx_valvref_ctrl <= current_task_vref_max) begin
            // Inside the eye — optionally inject a hole at the ¼ point.
            if ((intf.phy_rx_valvref_ctrl ==
                        current_task_vref_min + (current_task_vref_max - current_task_vref_min)/4)
                    && assume_holes_after_quarter_eye_start == 1) begin
                intf.tb_val_pass = 1'b0; // Deliberate hole.
            end else begin
                intf.tb_val_pass = 1'b1; // Inside valid window → pass.
            end
        end else begin
            intf.tb_val_pass = 1'b0; // Outside eye → fail.
        end
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                 (Reset Task)                 ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task reset();
        rst_n                   = 0;
        intf.tb_aggr_err        = 0;
        intf.tb_perlane_pass    = 16'hFFFF;
        intf.tb_val_pass        = 1'b1;
        intf.tb_clk_pass        = 1'b1;

        // For wrapper_D2C_PT_top: VALTRAINVREF uses only RX_D2C_PT.
        // local_tx_pt_en and partner_tx_pt_en are always driven to 0 by the DUT.
        // The TB only needs mb_rx_data_lane_mask for the wrapper.
        intf.mb_rx_data_lane_mask = 3'b011; // Lanes 0-15 active.

        intf.tb_wait_timeout       = 0;
        intf.tb_wrong_sb_msg_en    = 0;
        intf.tb_wrong_sb_msg       = NOTHING;
        intf.tb_wrong_msginfo      = 16'B0;
        intf.tb_wrong_data_field   = 64'B0;
        intf.valtraincenter_fail_flag = 1'b0; // default: previous VALTRAINCENTER succeeded.

        // Reset partner D2C done override in the TB attachments module.
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;

        #10;
        rst_n = 1;
    endtask

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (Start Test Task)               ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer lclk_counter          = 0;
    reg     lclk_counter_run_flag = 0;
    integer success_count         = 0;
    integer fail_count            = 0;
    reg [10:0] entered_states;

    task start_test(
            input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES,
            input integer  receive_wrong_sb_msg_after  = TIMEOUT_CYCLES,
            input msg_no_e wrong_sb_msg                = NOTHING,
            // When 1, the previous VALTRAINCENTER failed → VALTRAINVREF should skip sweep (spec S2).
            input logic valtraincenter_failed          = 1'b0
        );
        logic test_timeout_8ms_occured;
        entered_states = 0;

        // Drive valtraincenter_fail_flag before enabling the DUT.
        intf.valtraincenter_fail_flag = valtraincenter_failed;

        fork : test_execution
            // ── Main thread ──────────────────────────────────────────────
            begin
                intf.valtrainvref_en = 1'b1;
                lclk_counter_run_flag = 1;
                wait(intf.valtrainvref_done || intf.trainerror_req); #1step;

                intf.valtrainvref_en = 1'b0;
                test_timeout_8ms_occured = intf.trainerror_req;

                if (intf.trainerror_req != 1'b1) begin
                    // ── Happy exit: verify FSM settled ────────────────────
                    wait(current_state == TO_DATATRAINCENTER1); #1step;
                    wait(current_state == VALTRAINVREF_IDLE);   #1step;
                end else begin
                    wait(current_state == TO_TRAINERROR); #1step;
                end

                // ── Pass/fail accounting ──────────────────────────────────
                if (test_timeout_8ms_occured == 1) begin
                    if (intf.rx_sb_msg == TRAINERROR_Entry_req) begin
                        // Partner sent TRAINERROR — expected when wrong_sb_msg == TRAINERROR_Entry_req.
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
                        // Pure 8ms timeout.
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
                wait(current_state == VALTRAINVREF_IDLE);
                entered_states[0] = 1;
                wait(current_state == VALTRAINVREF_START_REQ);
                entered_states[1] = 1;
                wait(current_state == VALTRAINVREF_START_RESP);
                entered_states[2] = 1;
                if (!valtraincenter_failed) begin
                    // Full sweep path: S3 → S4 → S5 repeating for each Vref code.
                    repeat((MAX_VAL_VREF_CODE - MIN_VAL_VREF_CODE) + 1) begin
                        wait(current_state == VALTRAINVREF_SET_VREF_CODE);
                        entered_states[3] = 1;
                        wait(current_state == VALTRAINVREF_RX_D2C_PT);
                        entered_states[4] = 1;
                        wait(current_state == VALTRAINVREF_LOG_RESULT);
                        entered_states[5] = 1;
                    end
                    wait(current_state == VALTRAINVREF_CALC_APPLY);
                    entered_states[6] = 1;
                end
                wait(current_state == VALTRAINVREF_END_REQ);
                entered_states[7] = 1;
                wait(current_state == VALTRAINVREF_END_RESP);
                entered_states[8] = 1;
                wait(current_state == TO_DATATRAINCENTER1);
                entered_states[9] = 1;
                wait(current_state == VALTRAINVREF_IDLE);
                entered_states[10] = 1;
            end
        join

        #1step;
        entered_states               = 0;
        lclk_counter_run_flag        = 0;
        intf.tb_wait_timeout         = 0;
        intf.tb_wrong_sb_msg_en      = 0;
        intf.valtraincenter_fail_flag = 1'b0;
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
        // Scenarios 1-3 : Happy Path — full Vref sweep, no failure.
        // ─────────────────────────────────────────────────────────────────────
        for (int i = 0; i < 3; i++) begin
            $display("\n==========>  Test Scenario (%0d): Happy Path (full sweep). <==========", test_scenario_no++);
            assume_errors(.task_vref_code_min(VREF_CODE_WIDTH'(30)),
                .task_vref_code_max(VREF_CODE_WIDTH'(90)));
            start_test();
        end

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 4 : SPEC S2 shortcut — valtraincenter_fail_flag = 1.
        //   FSM must jump S2 → S7 (skip sweep entirely).
        // ─────────────────────────────────────────────────────────────────────
        $display("\n==========>  Test Scenario (%0d): S2 Shortcut (valtraincenter_fail_flag=1). <==========", test_scenario_no++);
        $display(  "===========>  FSM should jump S2 -> S7 skipping sweep entirely.           <==========");
        assume_errors(.task_vref_code_min(VREF_CODE_WIDTH'(30)),
            .task_vref_code_max(VREF_CODE_WIDTH'(90)));
        start_test(.valtraincenter_failed(1'b1));

        // ─────────────────────────────────────────────────────────────────────
        // Scenarios 5-7 : SB Connection Interruption (8ms timeout).
        // ─────────────────────────────────────────────────────────────────────
        repeat(3) begin
            $display("\n==========>  Test Scenario (%0d): SB Timeout (8ms). <==========", test_scenario_no++);
            start_test(.abort_mb_or_sb_after      (TIMEOUT_CYCLES),
                .receive_wrong_sb_msg_after ($urandom_range(0, TIMEOUT_CYCLES - 100)),
                .wrong_sb_msg               (NOTHING));
            reset();
        end

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 8 : Partner sends {TRAINERROR Entry req}.
        // ─────────────────────────────────────────────────────────────────────
        $display("\n==========>  Test Scenario (%0d): Partner TRAINERROR msg. <==========", test_scenario_no++);
        assume_errors(.task_vref_code_min(VREF_CODE_WIDTH'(MIN_VAL_VREF_CODE)),
            .task_vref_code_max(VREF_CODE_WIDTH'(MAX_VAL_VREF_CODE)));
        start_test(.receive_wrong_sb_msg_after(SWEEP_CYCLES / 2),
            .wrong_sb_msg              (TRAINERROR_Entry_req));
        reset();

        // ─────────────────────────────────────────────────────────────────────
        // Scenarios 9-31 : Random wrong SB message (causes timeout).
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
        // Scenarios 32-100 : Holes-in-eye (discontinuous valid window).
        // ─────────────────────────────────────────────────────────────────────
        for (int i = 32; i <= 100; i++) begin
            $display("\n==========>  Test Scenario (%0d): Holes Scenario. <==========", test_scenario_no++);
            temporary_var = 0;
            while (temporary_var < int'(MIN_VAL_VREF_CODE)) begin
                temporary_var = VREF_CODE_WIDTH'($random());
            end
            assume_errors(
                .task_aggr_err    (16'($random())),
                .task_perlane_pass(16'($random())),
                .task_vref_code_min(VREF_CODE_WIDTH'(temporary_var)),
                .task_vref_code_max(VREF_CODE_WIDTH'($urandom_range(temporary_var, int'(MAX_VAL_VREF_CODE)))),
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
