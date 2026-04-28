`timescale 1ps/1ps
module unit_SPEEDIDLE_tb ();
    import UCIe_pkg::*;
    parameter LCLK_PERIOD          = 1*1000 ; // 1 GHz
    parameter TIMEOUT_CYCLES       = 700_000;
    parameter ANALOG_SETTLE_CYCLES = 10;

    reg lclk;
    reg rst_n;
    internal_ltsm_if intf(.lclk(lclk), .rst_n(rst_n));

    // States
    typedef enum reg [3:0] {
        SPEEDIDLE_IDLE           = unit_SPEEDIDLE_inst.SPEEDIDLE_IDLE,
        SPEEDIDLE_CONFIG_SPEED   = unit_SPEEDIDLE_inst.SPEEDIDLE_CONFIG_SPEED,
        SPEEDIDLE_WAIT_PLL_LOCK  = unit_SPEEDIDLE_inst.SPEEDIDLE_WAIT_PLL_LOCK,
        SPEEDIDLE_DONE_REQ       = unit_SPEEDIDLE_inst.SPEEDIDLE_DONE_REQ,
        SPEEDIDLE_DONE_RESP      = unit_SPEEDIDLE_inst.SPEEDIDLE_DONE_RESP,
        TO_TXSELFCAL             = unit_SPEEDIDLE_inst.TO_TXSELFCAL,
        TO_TRAINERROR            = unit_SPEEDIDLE_inst.TO_TRAINERROR,
        Continue_Repeating = 'hF
    } fsm_state_t;
    fsm_state_t current_state;

    assign current_state = fsm_state_t'(unit_SPEEDIDLE_inst.current_state);

    // Clock
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    // Module Under Test
    unit_SPEEDIDLE #() unit_SPEEDIDLE_inst (
        .speedidle_if(intf)
    );

    // Attachments (Timers, SB simulation, MB simulation)
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (
        .intf(intf)
    );

    task reset();
        rst_n = 0;
        intf.tb_wait_timeout = 0;
        intf.tb_wrong_sb_msg_en = 0;
        intf.tb_wrong_sb_msg = NOTHING;
        intf.state_n[1] = ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF;
        intf.param_negotiated_max_speed = 3'b001;
        #10;
        rst_n = 1;
    endtask

    integer lclk_counter = 0;
    reg lclk_counter_run_flag = 0;
    integer success_count = 0;
    integer fail_count = 0;
    reg [6:0] entered_states;

    task start_test(
            input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES    ,
            input integer  receive_wrong_sb_msg_after = TIMEOUT_CYCLES    ,
            input msg_no_e wrong_sb_msg               = NOTHING
        );
        logic test_timeout_8ms_occured;
        entered_states = 0;

        fork : test_execution
            begin
                intf.speedidle_en = 1'b1;
                lclk_counter_run_flag = 1;
                wait(intf.speedidle_done || intf.trainerror_req); #1step;

                intf.speedidle_en = 1'b0;
                test_timeout_8ms_occured = intf.trainerror_req;

                if (intf.trainerror_req != 1'b1) begin
                    wait(current_state == SPEEDIDLE_IDLE); #1step;
                end else begin
                    wait(current_state == TO_TRAINERROR); #1step;
                end

                if (test_timeout_8ms_occured == 1) begin
                    if (intf.rx_sb_msg == TRAINERROR_Entry_req) begin
                        fail_count    = (intf.tb_wrong_sb_msg_en == 1'b1)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wrong_sb_msg_en == 1'b1)? success_count + 1 : success_count ;
                        if (intf.tb_wrong_sb_msg_en == 1'b1) begin
                            $display("Pass: Handled TRAINERROR successfully");
                        end else begin
                            $display("Fail: Unexpected TRAINERROR");
                            $stop;
                        end
                    end else if (intf.state_n[1] == ltsm_state_n_pkg::LOG_MBTRAIN_LINKSPEED && unit_SPEEDIDLE_inst.internal_phy_negotiated_speed == 3'b000 && !intf.tb_wait_timeout && !intf.tb_wrong_sb_msg_en) begin
                        fail_count    = fail_count;
                        success_count = success_count + 1;
                        // No timeout needed if we degraded from 000
                        $display("Pass: Handled speed degrade error correctly on entry.");
                    end else begin
                        fail_count    = (intf.tb_wait_timeout == 1'b1)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wait_timeout == 1'b1)? success_count + 1 : success_count ;
                        if (intf.tb_wrong_sb_msg_en == 1'b1 || intf.tb_wait_timeout == 1'b1) begin
                            $display("Pass: Handled expected timeout/error successfully");
                        end else begin
                            $display("Fail: Unexpected Timeout");
                            $stop;
                        end
                    end
                end else begin
                    success_count++;
                    $display("%10t ps: The test passed successfully.", $realtime());
                end
                disable test_execution;
            end

            begin
                for (int i=0; i<receive_wrong_sb_msg_after ; i++) begin
                    @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 0;
                    intf.tb_wrong_sb_msg = wrong_sb_msg;
                end
                intf.tb_wrong_sb_msg_en = 1;
            end

            begin
                for (int i=0; i<abort_mb_or_sb_after ; i++) begin
                    @(posedge lclk);
                    intf.tb_wait_timeout = 0;
                end
                intf.tb_wait_timeout = 1;
            end

            begin : check_fsm_transitions
                wait(current_state == SPEEDIDLE_IDLE);
                entered_states[0] = 1;

                if (intf.state_n[1] == ltsm_state_n_pkg::LOG_MBTRAIN_LINKSPEED && unit_SPEEDIDLE_inst.internal_phy_negotiated_speed == 3'b000) begin
                    // If degrade error, should immediately exit to TO_TRAINERROR
                    wait(current_state == TO_TRAINERROR);
                    entered_states[6] = 1;
                    wait(current_state == TO_TRAINERROR); // Wait a bit
                end else begin
                    wait(current_state == SPEEDIDLE_CONFIG_SPEED);
                    entered_states[1] = 1;
                    wait(current_state == SPEEDIDLE_WAIT_PLL_LOCK);
                    entered_states[2] = 1;

                    if (abort_mb_or_sb_after < TIMEOUT_CYCLES || receive_wrong_sb_msg_after < TIMEOUT_CYCLES) begin
                        wait(current_state == TO_TRAINERROR);
                        entered_states[6] = 1;
                    end else begin
                        wait(current_state == SPEEDIDLE_DONE_REQ);
                        entered_states[3] = 1;
                        wait(current_state == SPEEDIDLE_DONE_RESP);
                        entered_states[4] = 1;
                        wait(current_state == TO_TXSELFCAL);
                        entered_states[5] = 1;
                        wait(current_state == SPEEDIDLE_IDLE);
                        entered_states[0] = 1;
                    end
                end
            end
        join

        #1step;
        entered_states = 0;
        lclk_counter_run_flag = 0;
        intf.tb_wait_timeout = 0;
        intf.tb_wrong_sb_msg_en = 0;
        @(posedge lclk);
        #1step;
    endtask

    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            lclk_counter <= 0;
        end else if(lclk_counter_run_flag) begin
            lclk_counter <= lclk_counter + 1;
        end else begin
            lclk_counter <= 0;
        end
    end

    int test_scenario_no = 1;

    initial begin
        reset();
        $monitor("%10t ps : Current state: (\"%s\").", $realtime(), current_state.name());

        // Scenario 1: Happy Path from DATAVREF
        $display("\n=========>  Test Scenario (%0d): Happy Path (DATAVREF) <=========", test_scenario_no++);
        intf.state_n[1] = ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF;
        intf.param_negotiated_max_speed = 3'b010;
        start_test();

        // Scenario 2: Error on Degrade (from 4GT/s)
        $display("\n=========>  Test Scenario (%0d): Error on Degrade from 4GT/s <=========", test_scenario_no++);
        reset();
        intf.state_n[1] = ltsm_state_n_pkg::LOG_MBTRAIN_LINKSPEED;
        start_test();

        // Scenario 3: Timeout Settle
        $display("\n=========>  Test Scenario (%0d): Analog Settle Timeout <=========", test_scenario_no++);
        reset();
        intf.state_n[1] = ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF;
        start_test(.abort_mb_or_sb_after(20)); // Should timeout

        // Scenario 4: Receive TRAINERROR
        $display("\n=========>  Test Scenario (%0d): Receive TRAINERROR SB Msg <=========", test_scenario_no++);
        reset();
        intf.state_n[1] = ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF;
        start_test(.receive_wrong_sb_msg_after(5), .wrong_sb_msg(TRAINERROR_Entry_req));

        if (fail_count == 0) begin
            $display("      ================================================     ");
            $display("    ================  Congratulations!  ================   ");
            $display("  ==================  The tests passed  ================== ");
            $display("    ================    Successfully    ================   ");
            $display("      ================================================     \n\n");
        end
        @(posedge lclk);
        $stop;
    end
endmodule
