`timescale 1ps/1ps
module unit_VALVREF_tb ();
    import UCIe_pkg::*;
    parameter LCLK_PERIOD          = 1*1000 ; // That means lclk period = 1ns (1GHz) and for the waveform persetion: multiply by 1000.
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Number of lclk cycles to wait the analog circuits in the MB to settle its signals.
    parameter MIN_VAL_VREF_CODE    = 7'D10  ;
    parameter MAX_VAL_VREF_CODE    = 7'D127 ;
    parameter SB_DELAY             = 20     ; // Delay in lclk cycles.
    // -----------------------------------------------------------------------
    // ITER_COUNT / BURST_COUNT: D2C pattern-test speed knobs.
    //   Spec: 128 iterations × 8-cycle burst = 1024 UI per Vref code.
    //   Reduce for faster simulation (e.g. ITER_COUNT=4, BURST_COUNT=2).
    //   Each Vref code takes: ANALOG_SETTLE_CYCLES + BURST_COUNT×(ITER_COUNT+1) lclk cycles.
    // -----------------------------------------------------------------------
    parameter ITER_COUNT      = 128   ; // Spec: 128 iterations
    parameter BURST_COUNT     = 8     ; // Spec: 8-cycle burst
    parameter VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE);
    // -----------------------------------------------------------------------
    // Auto-compute TIMEOUT_CYCLES so it scales with all speed parameters.
    // SWEEP_CYCLES = one complete sweep estimate:
    //   Per code : analog settle + (BURST_COUNT+1) lclk × ITER_COUNT iterations + 15 overhead
    //   SB overhead : 8 handshake pairs × SB_DELAY
    // TIMEOUT_CYCLES = 2 × SWEEP_CYCLES  (still overridable if needed).
    // -----------------------------------------------------------------------
    localparam integer CYCLES_PER_CODE = ANALOG_SETTLE_CYCLES + (BURST_COUNT + 1) * ITER_COUNT + 15;
    localparam integer SWEEP_CYCLES    = (MAX_VAL_VREF_CODE - MIN_VAL_VREF_CODE + 1) * CYCLES_PER_CODE + 8 * SB_DELAY ; // this is the aggregate (total) delay consumed in the wrapper_D2C_PT_top module (RX_D2C_PT delay)
    parameter TIMEOUT_CYCLES = SWEEP_CYCLES + SB_DELAY * 4 + SWEEP_CYCLES; // TIMEOUT_CYCLES = (RX_D2C_PT sweep delay) + (4 VALVREF SB MSGs sent) * (SB_DELAY) + (extra RX_D2C_PT sweep delay for safety).
    // LTSM signals.
    reg  lclk         ;
    reg  rst_n        ;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));
    assign intf.is_ltsm_out_of_reset = rst_n;

    // States names
    typedef enum reg [3:0] {
        VALVREF_IDLE          = unit_VALVREF_inst.VALVREF_IDLE         , // (S0)
        VALVREF_START_REQ     = unit_VALVREF_inst.VALVREF_START_REQ    , // (S1)
        VALVREF_START_RESP    = unit_VALVREF_inst.VALVREF_START_RESP   , // (S2)
        VALVREF_SET_VREF_CODE = unit_VALVREF_inst.VALVREF_SET_VREF_CODE, // (S3)
        VALVREF_RX_D2C_PT     = unit_VALVREF_inst.VALVREF_RX_D2C_PT    , // (S4)
        VALVREF_LOG_RESULT    = unit_VALVREF_inst.VALVREF_LOG_RESULT   , // (S5)
        VALVREF_CALC_APPLY    = unit_VALVREF_inst.VALVREF_CALC_APPLY   , // (S6)
        VALVREF_END_REQ       = unit_VALVREF_inst.VALVREF_END_REQ      , // (S7)
        VALVREF_END_RESP      = unit_VALVREF_inst.VALVREF_END_RESP     , // (S8)
        TO_DATAVREF           = unit_VALVREF_inst.TO_DATAVREF          , // (S9)
        TO_TRAINERROR         = unit_VALVREF_inst.TO_TRAINERROR        , // (S10)
        Continue_Repeating_The_Last_3_States = 'hF
    } fsm_state_t;
    fsm_state_t current_state, monitor_current_state;

    assign current_state  = fsm_state_t'(unit_VALVREF_inst.current_state);

    // For lclk:
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    unit_VALVREF #(
        .MAX_VAL_VREF_CODE(MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE(MIN_VAL_VREF_CODE)
    ) unit_VALVREF_inst (
        .d2c_if(intf),
        .valvref_if(intf)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY            )
    ) ltsm_tb_attachments_inst (
        .intf(intf)
    );

    // Some signals to store the and move the signals for the next always block.
    reg [VREF_CODE_WIDTH-1:0] current_task_vref_min    ;
    reg [VREF_CODE_WIDTH-1:0] current_task_vref_max    ;
    reg assume_holes_after_quarter_eye_start;

    task assume_errors (
            input [15:0] task_aggr_err     = 16'b0 ,
            input [15:0] task_perlane_pass = 16'hFFFF,
            input [VREF_CODE_WIDTH-1:0] task_vref_code_min  = VREF_CODE_WIDTH'(50 ),
            input [VREF_CODE_WIDTH-1:0] task_vref_code_max  = VREF_CODE_WIDTH'(100),
            input task_assume_holes_after_quarter_eye_start = 0
        );
        intf.tb_aggr_err     = task_aggr_err    ;
        intf.tb_perlane_pass = task_perlane_pass;
        current_task_vref_min     = task_vref_code_min;
        current_task_vref_max     = task_vref_code_max;
        assume_holes_after_quarter_eye_start = task_assume_holes_after_quarter_eye_start;
    endtask

    always @(*) begin
        if(intf.phy_rx_valvref_ctrl >= current_task_vref_min && intf.phy_rx_valvref_ctrl <= current_task_vref_max) begin
            if ((intf.phy_rx_valvref_ctrl == current_task_vref_min + (current_task_vref_max - current_task_vref_min)/4 ) &&
                    assume_holes_after_quarter_eye_start == 1 ) begin
                intf.tb_val_pass = 1'b0;  // Deliberate fail
            end
            else begin
                intf.tb_val_pass = 1'b1;  // Pass
            end
        end
        else begin
            intf.tb_val_pass = 1'b0;  // Fail
        end
    end

    task reset();
        rst_n                   = 0;
        intf.tb_aggr_err        = 0;
        intf.tb_perlane_pass    = 16'hFFFF;
        intf.tb_val_pass        = 1'b1;
        intf.tb_clk_pass        = 1'b1;

        intf.mb_rx_data_lane_mask = 3'b011;

        intf.tb_wait_timeout    = 0;
        intf.tb_wrong_sb_msg_en = 0;
        intf.tb_wrong_sb_msg    = NOTHING;
        intf.tb_wrong_msginfo   = 16'B0;
        intf.tb_wrong_data_field = 64'B0;

        // Reset partner control overrides
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;

        #10;
        rst_n = 1;
    endtask

    integer lclk_counter          = 0;
    reg     lclk_counter_run_flag = 0;
    integer success_count         = 0;
    integer fail_count            = 0;
    reg [10:0] entered_states;

    task start_test(
            input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES    ,
            input integer  receive_wrong_sb_msg_after = TIMEOUT_CYCLES    ,
            input msg_no_e wrong_sb_msg               = NOTHING,
            input integer  partner_completion_mode     = 0,
            input integer  partner_completion_delay    = 10
        );
        logic test_timeout_8ms_occured;
        logic vref_fail_flag;
        vref_fail_flag = (assume_holes_after_quarter_eye_start && current_task_vref_min == current_task_vref_max);
        entered_states = 0;
        fork : test_execution
            begin : main_test_wait
                intf.valvref_en = 1'b1;
                lclk_counter_run_flag = 1;
                wait(intf.valvref_done || intf.trainerror_req); #1step;

                intf.valvref_en = 1'b0;
                test_timeout_8ms_occured = (intf.trainerror_req);
                if(intf.trainerror_req != 1'b1) begin
                    logic [VREF_CODE_WIDTH-1:0] hole_pos;
                    logic [VREF_CODE_WIDTH-1:0] expected_best_center;
                    hole_pos               = (assume_holes_after_quarter_eye_start)? current_task_vref_min + (current_task_vref_max - current_task_vref_min)/4 : (current_task_vref_min-1);
                    expected_best_center   = ({1'b0, hole_pos + 1} + {1'b0, current_task_vref_max}) / 2;

                    if (( unit_VALVREF_inst.valvref_fail_flag !=  vref_fail_flag) ||
                            (!unit_VALVREF_inst.valvref_fail_flag && !vref_fail_flag && intf.phy_rx_valvref_ctrl != expected_best_center)) begin

                        repeat(5) $display("\t\t ************************** ERROR **************************");
                        $display("error valvref_fail_flag = %0d, vref_fail_flag = %0b, intf.phy_rx_valvref_ctrl = %0d, Expected Center = %0d, is_there_holes = %0b",
                            unit_VALVREF_inst.valvref_fail_flag,
                            vref_fail_flag,
                            intf.phy_rx_valvref_ctrl,
                            expected_best_center,
                            assume_holes_after_quarter_eye_start);
                        $stop;
                    end

                    wait(current_state == VALVREF_IDLE); #1step;
                end
                else begin
                    wait(current_state == TO_TRAINERROR); #1step;
                    // Wait for the FSM to exit TO_TRAINERROR → VALVREF_IDLE before
                    // returning, so the next scenario never starts while the FSM
                    // is still in TO_TRAINERROR (which would lock it there again
                    // the moment valvref_en is re-asserted).
                    wait(current_state == VALVREF_IDLE); #1step;
                end

                if(test_timeout_8ms_occured == 1) begin
                    if(intf.rx_sb_msg == TRAINERROR_Entry_req) begin
                        fail_count    = (intf.tb_wrong_sb_msg_en == 1'b1)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wrong_sb_msg_en == 1'b1)? success_count + 1 : success_count ;

                        if(intf.tb_wrong_sb_msg_en == 1'b1) begin
                            $display("%10t ps, (Total lclk cycles: %0d): The FSM entered the \"TO_TRAINERROR\" state as expected correctly (due to receiving TRAINERROR SB message from the partner).", $realtime(), lclk_counter);
                            $display("\t\t That happens because the wrong Msg \"%s\" after passing %0d clock of lclk (Note we assume timeout be at %0d)",
                                intf.tb_wrong_sb_msg.name(),
                                receive_wrong_sb_msg_after,
                                TIMEOUT_CYCLES);
                        end
                        else begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps, (Total lclk cycles: %0d): The FSM received unexpected {TRAINERROR Entry req} SB Message. <================================= [Error]\n", $realtime(), lclk_counter);
                            $stop;
                        end

                    end
                    else if (vref_fail_flag) begin
                        success_count++;
                        $display("%10t ps: The test passed correctly (directed to TO_TRAINERROR due to expected calibration failure).", $realtime());
                    end
                    else begin
                        fail_count    = (intf.tb_wait_timeout == 1'b1)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wait_timeout == 1'b1)? success_count + 1 : success_count ;

                        if(intf.tb_wrong_sb_msg_en == 1'b1) begin
                            $display("%10t ps: The test passed but is directed to TO_TRAINERROR (due to timeout).", $realtime());
                            $display("\t\t That happens because the wrong Msg \"%s\" after passing %0d clock of lclk (Note we assume timeout be at %0d)",
                                intf.tb_wrong_sb_msg.name(),
                                receive_wrong_sb_msg_after,
                                TIMEOUT_CYCLES);
                        end
                        else begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps, (Total lclk cycles: %0d): The FSM did not enter all the expected states in the correct order (Timeout occured). <================================= [Error]\n", $realtime(), lclk_counter);
                            $stop;
                        end
                    end
                end
                else begin
                    success_count++;
                    $display("%10t ps: The test passed successfully.", $realtime());
                end

                $display("________________________________(Success count = %0d, Fail count = %0d, The total lclk cycles: %0d)________________________________\n", success_count, fail_count, lclk_counter);
                disable test_execution;
            end

            begin : wrong_sb_simulation
                for (int i=0; i<receive_wrong_sb_msg_after ; i++) begin
                    @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 0;
                    intf.tb_wrong_sb_msg = wrong_sb_msg;
                end
                intf.tb_wrong_sb_msg_en = 1;
            end

            begin : timeout_simulation
                for (int i=0; i<abort_mb_or_sb_after ; i++) begin
                    @(posedge lclk);
                    intf.tb_wait_timeout = 0;
                end
                intf.tb_wait_timeout = 1;
            end

            begin : partner_control
                if (partner_completion_mode == 0) begin
                    ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
                    ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                end
                else if (partner_completion_mode == 1) begin
                    ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 1;
                    ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                    forever begin
                        wait(current_state == VALVREF_RX_D2C_PT);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 1;
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                        wait(intf.local_test_d2c_done == 1);
                        repeat (partner_completion_delay) @(posedge lclk);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 1;
                        @(posedge lclk);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                        wait(current_state != VALVREF_RX_D2C_PT);
                    end
                end
                else if (partner_completion_mode == 2) begin
                    forever begin
                        wait(current_state == VALVREF_RX_D2C_PT);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 1;
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                        repeat (partner_completion_delay) @(posedge lclk);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 1;
                        @(posedge lclk);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                        wait(current_state != VALVREF_RX_D2C_PT);
                    end
                end
                else if (partner_completion_mode == 3) begin
                    forever begin
                        wait(current_state == VALVREF_RX_D2C_PT);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 1;
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                        wait(intf.local_test_d2c_done == 1);
                        @(posedge lclk);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 1;
                        @(posedge lclk);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                        wait(current_state != VALVREF_RX_D2C_PT);
                    end
                end
                else if (partner_completion_mode == 4) begin
                    forever begin
                        wait(current_state == VALVREF_RX_D2C_PT);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 1;
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                        wait(ltsm_tb_attachments_inst.mb_tx_pattern_count_done == 1);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 1;
                        @(posedge lclk);
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
                        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
                        wait(current_state != VALVREF_RX_D2C_PT);
                    end
                end
            end

            begin : check_fsm_transitions
                wait(current_state == VALVREF_IDLE);
                entered_states[0] = 1;
                wait(current_state == VALVREF_START_REQ);
                entered_states[1] = 1;
                wait(current_state == VALVREF_START_RESP);
                entered_states[2] = 1;
                repeat((MAX_VAL_VREF_CODE - MIN_VAL_VREF_CODE) + 1) begin
                    wait(current_state == VALVREF_SET_VREF_CODE);
                    entered_states[3] = 1;
                    wait(current_state == VALVREF_RX_D2C_PT);
                    entered_states[4] = 1;
                    wait(current_state == VALVREF_LOG_RESULT);
                    entered_states[5] = 1;
                end
                wait(current_state == VALVREF_CALC_APPLY);
                entered_states[6] = 1;
                wait(current_state == VALVREF_END_REQ);
                entered_states[7] = 1;
                wait(current_state == VALVREF_END_RESP);
                entered_states[8] = 1;
                wait(current_state == TO_DATAVREF);
                entered_states[9] = 1;
                wait(current_state == VALVREF_IDLE);
                entered_states[10] = 1;
            end
        join

        #1step;
        entered_states          = 0;
        lclk_counter_run_flag   = 0;
        intf.tb_wait_timeout    = 0;
        intf.tb_wrong_sb_msg_en = 0;
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done_en = 0;
        ltsm_tb_attachments_inst.tb_partner_test_d2c_done    = 0;
        @(posedge lclk);
        #1step;
    endtask

    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            lclk_counter <= 0;
        end
        else if(lclk_counter_run_flag) begin
            lclk_counter <= lclk_counter + 1;
        end
        else begin
            lclk_counter <= 0;
        end
    end

    int test_scenario_no = 1;
    msg_no_e random_msg = NOTHING;
    integer random_clocks=0;
    logic   first_loop;
    integer temporary_var = 0;
    always @(posedge lclk or negedge rst_n) begin
        if(!lclk) begin
            first_loop = 1;
        end
        else if(entered_states[10:0] == 11'b000_0011_1111) begin
            first_loop = 0;
        end
        else begin
            first_loop = 1;
        end
    end

    assign monitor_current_state = (current_state == TO_TRAINERROR)? TO_TRAINERROR :
        ((entered_states[10:0] == 11'b000_0011_1111) && !first_loop)? Continue_Repeating_The_Last_3_States : current_state;

    // fsm_state_t prev_state;
    // always @(posedge lclk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         prev_state <= VALVREF_IDLE;
    //     // end else if (current_state != prev_state) begin
    //     //     $display("TRANSITION: time=%0d ps %s -> %s (vref=%0d, local_done=%b, partner_done=%b, partner_en=%b)",
    //     //              $realtime(), prev_state.name(), current_state.name(),
    //     //              intf.phy_rx_valvref_ctrl, intf.local_test_d2c_done, intf.partner_test_d2c_done, intf.partner_rx_pt_en);
    //     //     prev_state <= current_state;
    //     // end
    // end

    initial begin
        reset();
        // $monitor("%10t ps : The Currernt state: (\"%s\").", $realtime(), monitor_current_state.name());

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (1, 2, 3) : Happy Scenario (Symmetric).            //
        /////////////////////////////////////////////////////////////////////////
        for(int i = 0; i < 3; i++) begin
            $display("\n=========>  Test Scenario (%0d): Happy Scenario. <=========", test_scenario_no++);
            assume_errors (
                .task_aggr_err     (16'h0000),
                .task_perlane_pass (16'hFFF7), // Lane 3 error
                .task_vref_code_min(7'd50   ),
                .task_vref_code_max(7'd100  ),
                .task_assume_holes_after_quarter_eye_start(0)
            );
            start_test(.partner_completion_mode(0));
        end

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (4): Multi-run without reset in-between.           //
        /////////////////////////////////////////////////////////////////////////
        $display("\n=========>  Test Scenario (%0d): Multi-run without Reset (Run 1). <=========", test_scenario_no++);
        assume_errors (
            .task_aggr_err     (16'h0000),
            .task_perlane_pass (16'hFFFF),
            .task_vref_code_min(7'd60   ),
            .task_vref_code_max(7'd90   ),
            .task_assume_holes_after_quarter_eye_start(0)
        );
        start_test(.partner_completion_mode(0));

        $display("\n=========>  Test Scenario (%0d): Multi-run without Reset (Run 2). <=========", test_scenario_no++);
        assume_errors (
            .task_aggr_err     (16'h0000),
            .task_perlane_pass (16'hFFFF),
            .task_vref_code_min(7'd40   ),
            .task_vref_code_max(7'd80   ),
            .task_assume_holes_after_quarter_eye_start(0)
        );
        start_test(.partner_completion_mode(0));

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (5, 6, 7): Partner applies tests MORE than local die (Partner later).
        /////////////////////////////////////////////////////////////////////////
        $display("\n=========>  Test Scenario (%0d): Partner applies RX_D2C_PT more (delay 20 cycles). <=========", test_scenario_no++);
        assume_errors (
            .task_aggr_err     (16'h0000),
            .task_perlane_pass (16'hFFFF),
            .task_vref_code_min(7'd50   ),
            .task_vref_code_max(7'd100  ),
            .task_assume_holes_after_quarter_eye_start(0)
        );
        start_test(.partner_completion_mode(1), .partner_completion_delay(20));

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (8, 9, 10): Partner applies tests LESS than local die (Partner earlier).
        /////////////////////////////////////////////////////////////////////////
        $display("\n=========>  Test Scenario (%0d): Partner applies RX_D2C_PT less (delay 5 cycles). <=========", test_scenario_no++);
        assume_errors (
            .task_aggr_err     (16'h0000),
            .task_perlane_pass (16'hFFFF),
            .task_vref_code_min(7'd50   ),
            .task_vref_code_max(7'd100  ),
            .task_assume_holes_after_quarter_eye_start(0)
        );
        start_test(.partner_completion_mode(2), .partner_completion_delay(5));

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (11): Partner applies tests LESS by 1 cycle (Corner Case).
        /////////////////////////////////////////////////////////////////////////
        $display("\n=========>  Test Scenario (%0d): Partner applies RX_D2C_PT less by 1 cycle. <=========", test_scenario_no++);
        assume_errors (
            .task_aggr_err     (16'h0000),
            .task_perlane_pass (16'hFFFF),
            .task_vref_code_min(7'd50   ),
            .task_vref_code_max(7'd100  ),
            .task_assume_holes_after_quarter_eye_start(0)
        );
        start_test(.partner_completion_mode(4));

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (12): Partner applies tests MORE by 1 cycle.
        /////////////////////////////////////////////////////////////////////////
        $display("\n=========>  Test Scenario (%0d): Partner applies RX_D2C_PT more by 1 cycle. <=========", test_scenario_no++);
        assume_errors (
            .task_aggr_err     (16'h0000),
            .task_perlane_pass (16'hFFFF),
            .task_vref_code_min(7'd50   ),
            .task_vref_code_max(7'd100  ),
            .task_assume_holes_after_quarter_eye_start(0)
        );
        start_test(.partner_completion_mode(3));

        //////////////////////////////////////////////////////////////////////////
        // The test scenario (13, 14, 15) : SB Connection Interruption.         //
        //////////////////////////////////////////////////////////////////////////
        repeat(3) begin
            $display("\n=========>  Test Scenario (%0d): SB Connection Interruption. <=========", test_scenario_no++);
            // Inject SB silence at a random point within the sweep window so the
            // FSM always encounters the disruption before it completes normally.
            start_test(
                .abort_mb_or_sb_after      (TIMEOUT_CYCLES                    ),
                .receive_wrong_sb_msg_after($urandom_range(0, integer'(SWEEP_CYCLES))),
                .wrong_sb_msg              (NOTHING                            )
            );
            reset();
        end

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (16) : Receive {TRAINERROR Entry req} SB Msg.      //
        /////////////////////////////////////////////////////////////////////////
        $display("\n=========>  Test Scenario (%0d): Receive {TRAINERROR Entry req} SB Msg. <=========", test_scenario_no++);
        assume_errors (
            .task_aggr_err     (16'h0000),
            .task_perlane_pass (16'hFFFF),
            .task_vref_code_min(MIN_VAL_VREF_CODE),
            .task_vref_code_max(MAX_VAL_VREF_CODE)
        );
        // Inject TRAINERROR_Entry_req at SWEEP_CYCLES/2 so it always arrives
        // while the FSM is mid-sweep, regardless of MIN/MAX_VAL_VREF_CODE.
        start_test(
            .receive_wrong_sb_msg_after(SWEEP_CYCLES / 2     ),
            .wrong_sb_msg              (TRAINERROR_Entry_req )
        );
        reset();

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (17:30) : Receive Wrong SB Msg.                    //
        /////////////////////////////////////////////////////////////////////////
        for (int i = 17; i < 31; i++) begin
            $display("\n=========>  Test Scenario (%0d): Receive Wrong SB Msg.  <=========", test_scenario_no++);
            while (random_msg === msg_no_e'(8'hXX) || random_msg === TRAINERROR_Entry_req) begin
                random_msg = msg_no_e'($urandom_range(8'h0, 8'hFF));
            end
            // Cap random delay to SWEEP_CYCLES so the wrong msg always arrives
            // while the FSM is still running (before it completes the sweep).
            random_clocks = $urandom_range(0, integer'(SWEEP_CYCLES));
            start_test(
                .receive_wrong_sb_msg_after(random_clocks),
                .wrong_sb_msg              (random_msg   )
            );
            reset();
        end

        ////////////////////////////////////////////////////////////////////////////////////////////////////
        // The test scenario 31:40 : Check Holes Scenario.                                                //
        ////////////////////////////////////////////////////////////////////////////////////////////////////
        for(int i = 31; i <= 40; i++) begin
            $display("\n=========>  Test Scenario (%0d): Holes Scenario. <=========", test_scenario_no++);
            temporary_var = 0;
            while(temporary_var < MIN_VAL_VREF_CODE) begin
                temporary_var = VREF_CODE_WIDTH'($random());
            end
            assume_errors (
                .task_aggr_err     (16'h0000),
                .task_perlane_pass (~(16'($random()))),
                .task_vref_code_min(VREF_CODE_WIDTH'(temporary_var)),
                .task_vref_code_max(VREF_CODE_WIDTH'($urandom_range(temporary_var, MAX_VAL_VREF_CODE)) ),
                .task_assume_holes_after_quarter_eye_start(1)
            );
            start_test(.partner_completion_mode(0));
        end

        if(fail_count == 0) begin
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
