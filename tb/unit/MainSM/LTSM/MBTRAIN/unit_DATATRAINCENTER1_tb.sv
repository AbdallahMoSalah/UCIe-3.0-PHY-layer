`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_DATATRAINCENTER1_tb
// Purpose   : Self-checking testbench for unit_DATATRAINCENTER1 FSM.
//
//             Mirrors the structure and coverage of unit_DATATRAINVREF_tb exactly,
//             adapted for PI phase sweep and state variables.
// =============================================================================
module unit_DATATRAINCENTER1_tb ();
    import UCIe_pkg::*;

    // ─── Parameters ──────────────────────────────────────────────────────────
    parameter LCLK_PERIOD          = 1*1000 ; // 1 ns at 1 GHz (ps timescale)
    parameter ANALOG_SETTLE_CYCLES = 10     ;
    parameter MIN_PHASE_CODE       = 6'd0   ;
    parameter MAX_PHASE_CODE       = 6'd63  ;
    parameter SB_DELAY             = 20     ; // lclk cycles

    localparam integer ITER_COUNT  = 1;     // d2c_iter_count = 1 inside DUT
    localparam integer BURST_COUNT = 4096;  // d2c_burst_count = 4096 inside DUT

    localparam integer CYCLES_PER_CODE =
        ANALOG_SETTLE_CYCLES + (BURST_COUNT + 1) * ITER_COUNT + 15;
    localparam integer SWEEP_CYCLES    =
        (MAX_PHASE_CODE - MIN_PHASE_CODE + 1) * CYCLES_PER_CODE + 8 * SB_DELAY;
    parameter TIMEOUT_CYCLES =
        SWEEP_CYCLES + SB_DELAY * 4 + SWEEP_CYCLES;

    localparam PW = $clog2(MAX_PHASE_CODE + 1);

    // ─── Clock & reset ────────────────────────────────────────────────────────
    reg lclk, rst_n;
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // ─── Interface ───────────────────────────────────────────────────────────
    internal_ltsm_if #(
        .MAX_VAL_VREF_CODE ('D127),
        .MAX_DATA_VREF_CODE('D127),
        .MAX_PI_PHASE_CODE (MAX_PHASE_CODE),
        .MAX_DESKEW_CODE   ('D127)
    ) intf (.lclk(lclk), .rst_n(rst_n));

    // ─── FSM state enum (mirrors DUT constants) ───────────────────────────────
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
        Continue_Repeating_The_Last_3_States = 'hF
    } fsm_state_t;

    fsm_state_t current_state, monitor_current_state;
    assign current_state = fsm_state_t'(unit_DATATRAINCENTER1_inst.current_state);

    // Suppress sweep-loop repetition in the $monitor transcript
    reg [10:0] entered_states;
    logic first_loop;
    always @(posedge lclk or negedge rst_n) begin
        if (!lclk) first_loop = 1;
        else if (entered_states[10:0] == 11'b000_0011_1111) first_loop = 0;
        else first_loop = 1;
    end
    assign monitor_current_state =
        (current_state == TO_TRAINERROR) ? TO_TRAINERROR :
        ((entered_states[10:0] == 11'b000_0011_1111) && !first_loop) ?
        Continue_Repeating_The_Last_3_States : current_state;

    // ─── DUT ─────────────────────────────────────────────────────────────────
    unit_DATATRAINCENTER1 #(
        .MAX_PHASE_CODE(MAX_PHASE_CODE),
        .MIN_PHASE_CODE(MIN_PHASE_CODE)
    ) unit_DATATRAINCENTER1_inst (
        .dtc1_if(intf),
        .d2c_if   (intf)
    );

    // ─── TB Attachments (timers, SB delay-line, wrapper_D2C_PT_top) ──────────
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY            )
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ─── Per-lane phase eye model ──────────────────────────────────────────────
    reg [PW-1:0] current_task_phase_min [15:0];
    reg [PW-1:0] current_task_phase_max [15:0];
    reg [15:0]   assume_holes_after_quarter_eye_start;

    task assume_errors (
            input [15:0]   task_aggr_err          = 16'b0         ,
            input [15:0]   task_perlane_pass       = 16'hFFFF      ,
            input [PW-1:0] task_phase_code_min [15:0] = '{default: PW'(MIN_PHASE_CODE + (MAX_PHASE_CODE - MIN_PHASE_CODE) / 4)},
            input [PW-1:0] task_phase_code_max [15:0] = '{default: PW'(MIN_PHASE_CODE + 3 * (MAX_PHASE_CODE - MIN_PHASE_CODE) / 4)},
            input [15:0]   task_assume_holes_after_quarter_eye_start = 16'b0,
            input [2:0]    task_mb_rx_data_lane_mask = 3'b011
        );
        intf.mb_rx_data_lane_mask = task_mb_rx_data_lane_mask;
        intf.tb_aggr_err          = task_aggr_err;
        intf.tb_perlane_pass      = task_perlane_pass;
        for (int i = 0; i < 16; i++) begin
            current_task_phase_min[i] = task_phase_code_min[i];
            current_task_phase_max[i] = task_phase_code_max[i];
            assume_holes_after_quarter_eye_start[i] =
                task_assume_holes_after_quarter_eye_start[i];
        end
    endtask

    always @(*) begin
        for (int j = 0; j < 16; j++) begin
            if (intf.phy_tx_data_pi_phase_ctrl[j] >= current_task_phase_min[j] &&
                    intf.phy_tx_data_pi_phase_ctrl[j] <= current_task_phase_max[j]) begin
                // Inside the eye — optionally inject a deliberate hole at the 1/4 point.
                if ((intf.phy_tx_data_pi_phase_ctrl[j] ==
                            current_task_phase_min[j] +
                            (current_task_phase_max[j] - current_task_phase_min[j])/4) &&
                        assume_holes_after_quarter_eye_start[j] == 1) begin
                    intf.tb_perlane_pass[j] = 1'b0; // deliberate hole
                end else begin
                    intf.tb_perlane_pass[j] = 1'b1; // pass
                end
            end else begin
                intf.tb_perlane_pass[j] = 1'b0; // outside eye → fail
            end
        end
        intf.tb_val_pass = 1'b1;
        intf.tb_clk_pass = 1'b1;
    end

    // ─── Reset task ──────────────────────────────────────────────────────────
    task reset();
        rst_n                     = 0;
        intf.tb_aggr_err          = 0;
        intf.tb_perlane_pass      = 16'hFFFF;
        intf.tb_val_pass          = 1'b1;
        intf.tb_clk_pass          = 1'b1;
        intf.mb_rx_data_lane_mask = 3'b011; // All 16 lanes active
        intf.tb_wait_timeout      = 0;
        intf.tb_wrong_sb_msg_en   = 0;
        intf.tb_wrong_sb_msg      = NOTHING;
        intf.tb_wrong_msginfo     = 16'h0;
        intf.tb_wrong_data_field  = 64'h0;
        intf.valtraincenter_fail_flag = 1'b0;

        // Reset partner control overrides
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;

        // Default eye covers the full phase range
        for (int i = 0; i < 16; i++) begin
            current_task_phase_min[i] = MIN_PHASE_CODE;
            current_task_phase_max[i] = MAX_PHASE_CODE;
        end
        assume_holes_after_quarter_eye_start = 16'h0;

        #10; rst_n = 1;
    endtask

    // ─── Cycle counter ───────────────────────────────────────────────────────
    integer lclk_counter          = 0;
    reg     lclk_counter_run_flag = 0;
    integer success_count         = 0;
    integer fail_count            = 0;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_counter_run_flag) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    // ─── start_test task ─────────────────────────────────────────────────────
    task start_test(
            input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES,
            input integer  receive_wrong_sb_msg_after = TIMEOUT_CYCLES,
            input msg_no_e wrong_sb_msg               = NOTHING
        );
        logic test_timeout_8ms_occured;
        entered_states        = 0;
        lclk_counter_run_flag = 1;

        fork : test_execution
            // ── Arm 1: main stimulus & checker ──────────────────────────────
            begin
                intf.datatraincenter1_en = 1'b1;
                wait(intf.datatraincenter1_done || intf.trainerror_req); #1step;

                intf.datatraincenter1_en = 1'b0;
                test_timeout_8ms_occured = (intf.trainerror_req);

                if (!intf.trainerror_req) begin
                    // ── Verify per-lane midpoint accuracy ─────────────────────
                    logic                   any_lane_failed;
                    logic                   global_vref_fail_flag;
                    logic [15:0]            vref_fail_flag;
                    int                     hole_pos          [15:0];
                    int                     expected_best_center [15:0];
                    logic [15:0]            active_lanes;

                    any_lane_failed     = 1'b0;
                    global_vref_fail_flag = 1'b0;
                    case (intf.mb_rx_data_lane_mask)
                        3'b000:  active_lanes = 16'h0000;
                        3'b001:  active_lanes = 16'h00FF;
                        3'b010:  active_lanes = 16'hFF00;
                        3'b011:  active_lanes = 16'hFFFF;
                        3'b100:  active_lanes = 16'h000F;
                        3'b101:  active_lanes = 16'h00F0;
                        default: active_lanes = 16'h0000;
                    endcase

                    for (int k = 0; k < 16; k++) begin
                        hole_pos[k] = (assume_holes_after_quarter_eye_start[k]) ?
                            int'(current_task_phase_min[k]) +
                            (int'(current_task_phase_max[k]) - int'(current_task_phase_min[k]))/4 :
                            (int'(current_task_phase_min[k]) - 1);
                        expected_best_center[k] =
                            (hole_pos[k] + 1 + int'(current_task_phase_max[k])) / 2;

                        if (active_lanes[k]) begin
                            vref_fail_flag[k] =
                                (assume_holes_after_quarter_eye_start[k] &&
                                    current_task_phase_min[k] == current_task_phase_max[k]);
                            if (vref_fail_flag[k]) global_vref_fail_flag = 1'b1;
                        end else begin
                            vref_fail_flag[k] = 1'b0;
                        end
                    end

                    for (int k = 0; k < 16; k++) begin
                        if (active_lanes[k]) begin
                            if (!vref_fail_flag[k] &&
                                    intf.phy_tx_data_pi_phase_ctrl[k] != expected_best_center[k]) begin
                                any_lane_failed = 1'b1;
                                repeat(5) $display("\t\t ************************** ERROR **************************");
                                $display("error lane[%0d]: phy_tx_data_pi_phase_ctrl=%0d, expected_center=%0d, hole=%0b",
                                    k,
                                    intf.phy_tx_data_pi_phase_ctrl[k],
                                    expected_best_center[k],
                                    assume_holes_after_quarter_eye_start[k]);
                            end
                        end
                    end
                    if (any_lane_failed) begin
                        $stop;
                    end

                    wait(current_state == DTC1_IDLE); #1step;
                end else begin
                    wait(current_state == TO_TRAINERROR); #1step;
                end

                // ── Pass/fail accounting ──────────────────────────────────────
                if (test_timeout_8ms_occured == 1) begin
                    if (intf.rx_sb_msg == TRAINERROR_Entry_req) begin
                        // TRAINERROR caused by a partner TRAINERROR SB message
                        fail_count    = (intf.tb_wrong_sb_msg_en == 1'b1) ?
                            fail_count        : fail_count + 1;
                        success_count = (intf.tb_wrong_sb_msg_en == 1'b1) ?
                            success_count + 1 : success_count;
                        if (intf.tb_wrong_sb_msg_en == 1'b1) begin
                            $display("%10t ps, (lclk: %0d): FSM -> TO_TRAINERROR as expected (TRAINERROR SB).",
                                $realtime(), lclk_counter);
                        end else begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps: Unexpected TRAINERROR SB msg. <======= [Error]", $realtime());
                            $stop;
                        end
                    end else begin
                        // TRAINERROR caused by 8ms timeout
                        fail_count    = (intf.tb_wait_timeout == 1'b1) ?
                            fail_count        : fail_count + 1;
                        success_count = (intf.tb_wait_timeout == 1'b1) ?
                            success_count + 1 : success_count;
                        if (intf.tb_wait_timeout == 1'b1) begin
                            $display("%10t ps, (lclk: %0d): FSM -> TO_TRAINERROR as expected (8ms timeout).",
                                $realtime(), lclk_counter);
                        end else begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps, (lclk: %0d): Timeout — FSM did not finish. <====== [Error]",
                                $realtime(), lclk_counter);
                            $stop;
                        end
                    end
                end else begin
                    success_count++;
                    $display("%10t ps: The test passed successfully.", $realtime());
                end

                $display("_________(Success=%0d  Fail=%0d  lclk cycles=%0d)_________\n",
                    success_count, fail_count, lclk_counter);
                disable test_execution;
            end

            // ── Arm 2: wrong SB message injection ───────────────────────────
            begin
                for (int i = 0; i < receive_wrong_sb_msg_after; i++) begin
                    @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 0;
                    intf.tb_wrong_sb_msg    = wrong_sb_msg;
                end
                intf.tb_wrong_sb_msg_en = 1;
            end

            // ── Arm 3: 8ms timeout injection ────────────────────────────────
            begin
                for (int i = 0; i < abort_mb_or_sb_after; i++) begin
                    @(posedge lclk);
                    intf.tb_wait_timeout = 0;
                end
                intf.tb_wait_timeout = 1;
            end

            // ── Arm 4: FSM-state sequence checker ────────────────────────────
            begin : check_fsm_transitions
                wait(current_state == DTC1_IDLE);
                entered_states[0] = 1;
                wait(current_state == DTC1_START_REQ);
                entered_states[1] = 1;
                wait(current_state == DTC1_START_RESP);
                entered_states[2] = 1;
                repeat(MAX_PHASE_CODE - MIN_PHASE_CODE + 1) begin
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

        #1step;
        entered_states          = 0;
        lclk_counter_run_flag   = 0;
        intf.tb_wait_timeout    = 0;
        intf.tb_wrong_sb_msg_en = 0;
        @(posedge lclk); #1step;
    endtask

    // ─── Helper arrays for per-lane eye configuration ────────────────────────
    int test_scenario_no = 1;
    msg_no_e random_msg  = NOTHING;
    integer  random_clocks = 0;

    logic [PW-1:0] phase_min_arr [15:0];
    logic [PW-1:0] phase_max_arr [15:0];
    logic [15:0]   holes_arr;
    integer        temporary_var;

    // ─── Main test sequence ───────────────────────────────────────────────────
    initial begin
        reset();
        $monitor("%10t ps: State=(%s)", $realtime(), monitor_current_state.name());

        // =====================================================================
        // Scenarios 1-3: Happy path (three back-to-back sweeps)
        // =====================================================================
        for (int i = 0; i < 3; i++) begin
            for (int j = 0; j < 16; j++) begin
                phase_min_arr[j] = PW'(MIN_PHASE_CODE + (MAX_PHASE_CODE - MIN_PHASE_CODE) / 4);
                phase_max_arr[j] = PW'(MIN_PHASE_CODE + 3 * (MAX_PHASE_CODE - MIN_PHASE_CODE) / 4);
            end
            holes_arr = 16'h0000;
            $display("\n==========>  Test Scenario (%0d): Happy Scenario. <==========", test_scenario_no++);
            assume_errors(
                .task_aggr_err    (16'h0000),
                .task_perlane_pass(16'hFFFF),
                .task_phase_code_min(phase_min_arr),
                .task_phase_code_max(phase_max_arr),
                .task_assume_holes_after_quarter_eye_start(holes_arr)
            );
            start_test();
        end

        // =====================================================================
        // Scenarios 4-6: SB connection interruption (8ms timeout)
        // =====================================================================
        repeat(3) begin
            $display("\n==========>  Test Scenario (%0d): SB Connection Interruption. <==========", test_scenario_no++);
            $display(  "==========>               (timeout 8ms occurs)                <==========");
            start_test(
                .abort_mb_or_sb_after      (TIMEOUT_CYCLES              ),
                .receive_wrong_sb_msg_after($urandom_range(0, TIMEOUT_CYCLES * 2)),
                .wrong_sb_msg              (NOTHING                     )
            );
            reset();
        end

        // =====================================================================
        // Scenario 7: Partner TRAINERROR SB message
        // =====================================================================
        $display("\n==========>  Test Scenario (%0d): Partner TRAINERROR SB Msg. <==========", test_scenario_no++);
        for (int j = 0; j < 16; j++) begin
            phase_min_arr[j] = MIN_PHASE_CODE;
            phase_max_arr[j] = MAX_PHASE_CODE;
        end
        holes_arr = 16'h0000;
        assume_errors(
            .task_aggr_err    (16'h0000),
            .task_perlane_pass(16'hFFFF),
            .task_phase_code_min(phase_min_arr),
            .task_phase_code_max(phase_max_arr),
            .task_assume_holes_after_quarter_eye_start(holes_arr)
        );
        start_test(
            .receive_wrong_sb_msg_after(SWEEP_CYCLES / 2),
            .wrong_sb_msg              (TRAINERROR_Entry_req)
        );
        reset();

        // =====================================================================
        // Scenarios 8-17: Random wrong SB message at a random time
        // =====================================================================
        for (int i = 8; i < 18; i++) begin
            $display("\n==========>  Test Scenario (%0d): Wrong SB Msg. <==========", test_scenario_no++);
            while (random_msg === msg_no_e'(8'hXX) || random_msg === TRAINERROR_Entry_req) begin
                random_msg = msg_no_e'($urandom_range(8'h0, 8'hFF));
            end
            random_clocks = $urandom_range(0, TIMEOUT_CYCLES * 2);
            start_test(
                .receive_wrong_sb_msg_after(random_clocks),
                .wrong_sb_msg              (random_msg   )
            );
            reset();
        end

        // =====================================================================
        // Scenarios 18-100: Randomised holes-in-eye, random lane-mask
        // =====================================================================
        for (int i = 18; i <= 100; i++) begin
            logic [2:0] rand_mask;
            $display("\n==========>  Test Scenario (%0d): Holes Scenario. <==========", test_scenario_no++);

            rand_mask = 3'($urandom_range(0, 5));
            holes_arr = 16'($urandom_range(0, 16'hFFFF));

            for (int j = 0; j < 16; j++) begin
                temporary_var = 0;
                while (temporary_var < int'(MIN_PHASE_CODE)) begin
                    temporary_var = $urandom_range(int'(MIN_PHASE_CODE),
                        int'(MAX_PHASE_CODE) - 5);
                end
                phase_min_arr[j] = PW'(temporary_var);
                phase_max_arr[j] = PW'($urandom_range(temporary_var, int'(MAX_PHASE_CODE)));
            end

            assume_errors(
                .task_aggr_err    (16'($random())),
                .task_perlane_pass(16'($random())),
                .task_phase_code_min(phase_min_arr),
                .task_phase_code_max(phase_max_arr),
                .task_assume_holes_after_quarter_eye_start(holes_arr),
                .task_mb_rx_data_lane_mask(rand_mask)
            );
            start_test();
        end

        // ─── Final result ─────────────────────────────────────────────────────
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
