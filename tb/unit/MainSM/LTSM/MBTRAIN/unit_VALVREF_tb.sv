`timescale 1ps/1ps
module unit_VALVREF_tb ();
    import UCIe_pkg::*;
    parameter LCLK_PERIOD          = 1*1000 ; // That means lclk period = 1ns (1GHz) and for the waveform persetion: multiply by 1000.
    parameter TIMEOUT_CYCLES       = 700_000; // Number of lclk cycles to wait before declaring a timeout (e.g., for 8ms timeout at 1GHz, it would be 8 million cycles). Here i will use 700_000 cycles to run the simulation faster.
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Number of lclk cycles to wait the analog circuits in the MB to settle its signals.
    parameter MIN_VAL_VREF_CODE    = 7'D10 ;
    parameter MAX_VAL_VREF_CODE    = 7'D127;
    parameter VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE);
    // LTSM signals.
    reg  lclk         ;
    reg  rst_n        ;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));


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


    // ===================================================================== //
    //   __      ____      ____      ____      ____      ____      ____      //
    //     |____|    |____|    |____|    |____|    |____|    |____|    |__   //
    //                                                                       //
    //                           Clock Generation.                           //
    //      ____      ____      ____      ____      ____      ____      __   //
    //    _|    |____|    |____|    |____|    |____|    |____|    |____|     //
    // ===================================================================== //
    // For lclk:
    initial begin
        lclk = 0;
        forever #(LCLK_PERIOD/2) lclk = ~lclk;
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------       (Instance of the VALVREF module)       ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    unit_VALVREF #(
        .MAX_VAL_VREF_CODE(MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE(MIN_VAL_VREF_CODE)
    ) unit_VALVREF_inst (
        .d2c_if(intf),
        .valvref_if(intf)
    );


    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ), // Number of lclk cycles to wait before declaring a timeout (e.g., for 8ms timeout at 1GHz, it would be 8 million cycles).
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)  // Number of lclk cycles to wait the analog circuits in the MB to settle its signals.
    ) ltsm_tb_attachments_inst (
        .intf(intf)
    );



    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                (assume_errors)               ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    // Some signals to store the and move the signals for the next always block.
    reg [VREF_CODE_WIDTH-1:0] current_task_vref_min    ;
    reg [VREF_CODE_WIDTH-1:0] current_task_vref_max    ;
    reg assume_holes_after_quarter_eye_start;

    task assume_errors (
            input [15:0] task_aggr_err     = 16'b0 , // The aggregate error to be assumed for the test scenario.
            input [15:0] task_perlane_err  = 16'b0 , // The per-lane error to be assumed for the test scenario.
            // input        task_val_err      = 1'b0  , // The valid lane error to be assumed for the test scenario.
            // input        task_clk_err      = 1'b0  , // The clock lane error to be assumed for the test scenario.
            input [VREF_CODE_WIDTH-1:0] task_vref_code_min  = VREF_CODE_WIDTH'(50 ),
            input [VREF_CODE_WIDTH-1:0] task_vref_code_max  = VREF_CODE_WIDTH'(100),
            input task_assume_holes_after_quarter_eye_start = 0
        );
        intf.tb_aggr_err     = task_aggr_err    ;
        intf.tb_perlane_err  = task_perlane_err ;
        // intf.tb_val_err      = task_val_err     ;
        // intf.tb_clk_err      = task_clk_err     ;
        current_task_vref_min     = task_vref_code_min;
        current_task_vref_max     = task_vref_code_max;

        assume_holes_after_quarter_eye_start = task_assume_holes_after_quarter_eye_start;
    endtask

    always @(*) begin
        if(intf.phy_rx_valvref_ctrl >= current_task_vref_min && intf.phy_rx_valvref_ctrl <= current_task_vref_max) begin

            // =============================================================================================== //
            // Adding a deliberate hole (hole) in the eye to force the RTL to test all pathways.               //
            // For simplicity: Consider the hole be added after the (1/4) of the correct Vref range.           //
            // =============================================================================================== //
            if ((intf.phy_rx_valvref_ctrl == current_task_vref_min + (current_task_vref_max - current_task_vref_min)/4 ) &&
                    assume_holes_after_quarter_eye_start == 1 ) begin
                intf.tb_val_err = 1'b1;  // A deliberate mistake in the middle!
            end
            // =============================================================================================== //

            else begin // (Inside Eye Diagram)
                intf.tb_val_err = 1'b0; // The right point that is inside the Eye Diagram.
            end
        end
        else begin
            intf.tb_val_err = 1'b1; // The points at too low Vref or too high Vref.
        end
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                 (Reset Task:)                ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task reset();
        rst_n                   = 0;
        intf.tb_aggr_err        = 0;
        intf.tb_perlane_err     = 0;
        intf.tb_val_err         = 0;
        intf.tb_clk_err         = 0;

        intf.tb_wait_timeout    = 0; // Set wait_timeout to 0 to indicate that we are not testing the timeout condition at the beginning.
        intf.tb_wrong_sb_msg_en = 0;
        intf.tb_wrong_sb_msg    = NOTHING;
        intf.tb_rx_msginfo      = 16'B0;
        intf.tb_rx_data_field   = 64'B0;
        #10;
        rst_n = 1;
    endtask



    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------               ( Start Test Task)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer lclk_counter          = 0; // A counter to track the number of lclk cycles during the test execution, used for debugging and verification purposes.
    reg     lclk_counter_run_flag = 0; // A flag to indicate whether the lclk counter should be running to count the lclk cycles during the test execution.
    integer success_count         = 0; // A counter to track the number of successful tests.
    integer fail_count            = 0; // A counter to track the number of failed tests.
    reg [10:0] entered_states;

    task start_test(
            input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES    , // The input argument is used to determine whether the testbench should simulate the timeout condition caused by MB or SB by waiting for some time before setting mb_tx_pattern_count_done to 1 or before sending the expected SB response, respectively.
            input integer  receive_wrong_sb_msg_after = TIMEOUT_CYCLES    , // The input argument is used to determine whether the testbench should simulate the timeout condition caused by SB by waiting for some time before sending the expected SB response.
            input msg_no_e wrong_sb_msg               = NOTHING             // The wrong SB message to be sent if we want to test the case of receiving wrong SB message.
        );
        logic test_timeout_8ms_occured;
        entered_states = 0;
        fork : test_execution
            begin
                // ======================================== //
                // Observe the if the FSM finished or not.  //
                // ======================================== //
                // ================= //
                // Start the test... //
                // ================= //
                intf.valvref_en = 1'b1;
                lclk_counter_run_flag = 1; // Start counting the lclk cycles from the moment we trigger the test.
                wait(intf.valvref_done || intf.trainerror_req); #1step; // Wait until the test is done or a timeout/error occurs.

                // ================= //
                // End the test.     //
                // Get the results.  //
                // ================= //
                intf.valvref_en = 1'b0;
                test_timeout_8ms_occured = (intf.trainerror_req);
                if(intf.trainerror_req != 1'b1) begin
                    // =========================================================================
                    // Calculating the expected center based on the presence of the hole
                    // Since the hole is in the first quarter, the RTL will choose the larger area, which is the remaining 3/4.
                    // =========================================================================
                    logic [VREF_CODE_WIDTH-1:0] hole_pos;
                    logic [VREF_CODE_WIDTH-1:0] expected_best_center;
                    logic                       vref_fail_flag;
                    hole_pos               = (assume_holes_after_quarter_eye_start)? current_task_vref_min + (current_task_vref_max - current_task_vref_min)/4 : (current_task_vref_min-1);
                    expected_best_center   = ({1'b0, hole_pos + 1} + {1'b0, current_task_vref_max}) / 2;
                    vref_fail_flag         = (assume_holes_after_quarter_eye_start && current_task_vref_min == current_task_vref_max);

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

                    wait(current_state == VALVREF_IDLE); #1step; // To keep the $monitor system function (that is used in the main initial block) print the final state of the FSM first, before the next $display content.
                end
                else begin
                    wait(current_state == TO_TRAINERROR); #1step;
                end

                if(test_timeout_8ms_occured == 1) begin
                    if(intf.rx_sb_msg == TRAINERROR_Entry_req) begin // if the fsm received {TRAINERROR Entry req} SB message.
                        fail_count    = (intf.tb_wrong_sb_msg_en == 1'b1)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wrong_sb_msg_en == 1'b1)? success_count + 1 : success_count ;

                        // when "success_count" increases:
                        if(intf.tb_wrong_sb_msg_en == 1'b1) begin
                            $display("%10t ps, (Total lclk cycles: %0d): The FSM entered the \"TO_TRAINERROR\" state as expected correctly (due to receiving TRAINERROR SB message from the partner).", $realtime(), lclk_counter);
                            $display("\t\t That happens because the wrong Msg \"%s\" after passing %0d clock of lclk (Note we assume timeout be at %0d)",
                                intf.tb_wrong_sb_msg.name(),
                                receive_wrong_sb_msg_after,
                                TIMEOUT_CYCLES);
                        end
                        // when "fail_count" increases:
                        else begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps, (Total lclk cycles: %0d): The FSM received unexpected {TRAINERROR Entry req} SB Message. <================================= [Error]\n", $realtime(), lclk_counter);
                            $stop;
                        end

                    end
                    else begin // If the timeout 8ms occured.
                        fail_count    = (intf.tb_wait_timeout == 1'b1)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wait_timeout == 1'b1)? success_count + 1 : success_count ;

                        // when "success_count" increases:
                        if(intf.tb_wrong_sb_msg_en == 1'b1) begin
                            $display("%10t ps: The test passed but is directed to TO_TRAINERROR (due to timeout).", $realtime());
                        end
                        // when "fail_count" increases:
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
                disable test_execution; // Disable the fork to end the test execution.
            end

            begin
                // ==================================================================================================================== //
                // Wait some lclk cycles = "receive_wrong_sb_msg_after" to simulate receiving wrong SB message condition caused by SB,  //
                // then set the "tb_wrong_sb_msg_en" signal to 1 to indicate that an error has occurred during the test.                //
                // ==================================================================================================================== //
                for (int i=0; i<receive_wrong_sb_msg_after ; i++) begin
                    @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 0;
                    intf.tb_wrong_sb_msg = wrong_sb_msg; // Assign the wrong SB message to be sent.
                end
                intf.tb_wrong_sb_msg_en = 1; // Set the timeout_or_error signal to 1 after applying the wrong SB message.
            end

            begin
                // ======================================================================================================================= //
                // Wait some lclk cycles = "abort_mb_or_sb_after" to simulate the timeout condition caused by MB or SB,                    //
                // then the signal "tb_wrong_sb_msg_en" will be set to 1 to indicate that a timeout or error has occurred during the test. //
                // ======================================================================================================================= //
                for (int i=0; i<abort_mb_or_sb_after ; i++) begin
                    @(posedge lclk);
                    intf.tb_wait_timeout = 0;
                end
                intf.tb_wait_timeout = 1; // Set the timeout_or_error signal to 1 after waiting for some time to simulate the timeout condition caused by MB or SB.
            end

            begin : check_fsm_transitions
                wait(current_state == VALVREF_IDLE);          // Wait for the FSM to be in the IDLE state before starting the test.
                entered_states[0] = 1;                        // Mark that we have entered the IDLE.
                wait(current_state == VALVREF_START_REQ);     // Wait for the FSM to transition to the START_REQ state.
                entered_states[1] = 1;                        // Mark that we have entered the START_REQ state.
                wait(current_state == VALVREF_START_RESP);    // Wait for the FSM to transition to the START_RESP state.
                entered_states[2] = 1;                        // Mark that we have entered the START_RESP state.
                repeat((MAX_VAL_VREF_CODE - MIN_VAL_VREF_CODE) + 1) begin
                    wait(current_state == VALVREF_SET_VREF_CODE); // Wait for the FSM to transition to the SET_VREF_CODE state.
                    entered_states[3] = 1;                        // Mark that we have entered the SET_VREF_CODE state.
                    wait(current_state == VALVREF_RX_D2C_PT);     // Wait for the FSM to transition to the RX_D2C_PT state.
                    entered_states[4] = 1;                        // Mark that we have entered the RX_D2C_PT state.
                    wait(current_state == VALVREF_LOG_RESULT);    // Wait for the FSM to transition to the LOG_RESULT state.
                    entered_states[5] = 1;                        // Mark that we have entered the LOG_RESULT state.
                end
                wait(current_state == VALVREF_CALC_APPLY);    // Wait for the FSM to transition to the CALC_APPLY state.
                entered_states[6] = 1;                        // Mark that we have entered the CALC_APPLY state.
                wait(current_state == VALVREF_END_REQ);       // Wait for the FSM to transition to the END_REQ state.
                entered_states[7] = 1;                        // Mark that we have entered the END_REQ state.
                wait(current_state == VALVREF_END_RESP);      // Wait for the FSM to transition to the END_RESP state.
                entered_states[8] = 1;                        // Mark that we have entered the END_RESP state.
                wait(current_state == TO_DATAVREF);           // Wait for the FSM to transition to the TO_DATAVREF state.
                entered_states[9] = 1;                        // Mark that we have entered the TO_DATAVREF state.
                wait(current_state == VALVREF_IDLE);          // Wait for the FSM to transition back to the VALVREF_IDLE state.
                entered_states[10] = 1;                       // Mark that we have entered the VALVREF_IDLE state again.
            end
        join


        #1step;
        entered_states          = 0;
        lclk_counter_run_flag   = 0; // Stop counting the lclk cycles at the end of the test.
        intf.tb_wait_timeout    = 0; // Clear the timeout_or_error signal after the test is done.
        intf.tb_wrong_sb_msg_en = 0; // Clear the receive_wrong_sb_msg signal after the test is done.
        @(posedge lclk); // To set the lclk_counter to 0 in the always block that is used to count the lclk cycles, to prepare for the next test execution.
        #1step;
    endtask


    // We use this always block to count the number of lclk cycles from the start of the test to print them in the results. not any thing else.
    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            lclk_counter <= 0; // Reset the lclk counter at the beginning of the test.
        end
        else if(lclk_counter_run_flag) begin
            lclk_counter <= lclk_counter + 1; // Increment the lclk counter at each clock cycle during the test execution.
        end
        else begin
            lclk_counter <= 0; // Reset the lclk counter when the flag is not set, to prepare for the next test execution.
        end
    end

    // \\\\\\\\\\\\\\\\\\\\\                                                                  ////////////////////////
    //    \\\\\\\\\\\\\\\\\\\\\\                                                          ////////////////////////
    //     /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    //    |  -------------------------          (Test Bench Main Actions:)          ---------------------------  |
    //     \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    //    //////////////////////                                                          \\\\\\\\\\\\\\\\\\\\\\\\
    // /////////////////////                                                                  \\\\\\\\\\\\\\\\\\\\\\\\
    int test_scenario_no = 1;
    msg_no_e random_msg = NOTHING; // A random SB message to be used in the test scenarios that do not require specific SB message.
    integer random_clocks=0; // A random number of clock cycles to be used in the test scenarios that do not require specific timing for SB message reception or timeout.
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

    initial begin
        // Reset the system.
        reset();

        // Monitor the current state of the RX_D2C_PT instance for debugging purposes.
        $monitor("%10t ps : The Currernt state: (\"%s\").", $realtime(), monitor_current_state.name());


        /////////////////////////////////////////////////////////////////////////
        // The test scenario (1, 2, 3) : Happy Scenario.                       //
        /////////////////////////////////////////////////////////////////////////
        for(int i = 0; i < 3; i++) begin
            $display("\n=========>  Test Scenario (%0d): Happy Scenario. <=========", test_scenario_no++);
            assume_errors (
                .task_aggr_err     (16'h0009), // The aggregate error to be assumed for the test scenario.
                .task_perlane_err  (16'h0008), // The per-lane error to be assumed for the test scenario.
                // .task_val_err      (1'b0    ), // The valid lane error to be assumed for the test scenario.
                // .task_clk_err      (1'b0    )  // The clock lane error to be assumed for the test scenario.
                .task_vref_code_min(7'd50   ),
                .task_vref_code_max(7'd100  ),
                .task_assume_holes_after_quarter_eye_start(0)
            );
            start_test();
        end


        //////////////////////////////////////////////////////////////////////////
        // The test scenario (4, 5, 6) : SB Connection Interruption.            //
        // Here we're testing the timeout caused by the connection interruption //
        //////////////////////////////////////////////////////////////////////////
        repeat(3) begin
            $display("\n=========>  Test Scenario (%0d): SB Connection Interruption. <=========", test_scenario_no++);
            $display(  "=========>               (timeout 8ms occurs)                <=========");

            // Start the test with the previous configurations (assumed errors).
            start_test(
                .abort_mb_or_sb_after      (TIMEOUT_CYCLES              ), // Used to simulate the timeout condition caused by MB or SB by waiting for some time before setting mb_tx_pattern_count_done to 1 or before sending the expected SB response, respectively.
                .receive_wrong_sb_msg_after($urandom_range(0, 'D560_000)), // Used to simulate the timeout condition caused by SB by waiting for some time before sending the expected SB response.
                .wrong_sb_msg              (NOTHING                     )  // The wrong SB message to be sent if we want to test the case of receiving wrong SB message.
            );
            reset(); // because the applied Test Scenario was directed to TO_TRAINERROR state, we need to reset the system before starting a new test scenario.
            //$stop;
        end

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (7) : Receive {TRAINERROR Entry req} SB Msg.      //
        // Here we are testing receiving {TRAINERROR Entry req} SB Message.    //
        /////////////////////////////////////////////////////////////////////////
        $display("\n=========>  Test Scenario (%0d): Receive {TRAINERROR Entry req} SB Msg. <=========", test_scenario_no++);
        $display(  "=========>                   (timeout doesn't occur)                    <=========");

        // Start the test with the previous configurations (assumed errors).
        assume_errors (
            .task_aggr_err     (16'h0009), // The aggregate error to be assumed for the test scenario.
            .task_perlane_err  (16'h0008), // The per-lane error to be assumed for the test scenario.
            // .task_val_err      (1'b0    ), // The valid lane error to be assumed for the test scenario.
            // .task_clk_err      (1'b0    )  // The clock lane error to be assumed for the test scenario.
            .task_vref_code_min(MIN_VAL_VREF_CODE),
            .task_vref_code_max(MAX_VAL_VREF_CODE)
        );
        start_test(
            .receive_wrong_sb_msg_after(400_000             ),
            .wrong_sb_msg              (TRAINERROR_Entry_req)
        );
        reset(); // because the applied Test Scenario was directed to TO_TRAINERROR state, we need to reset the system before starting a new test scenario.


        /////////////////////////////////////////////////////////////////////////
        // The test scenario (8:30) : Receive Wrong SB Msg.                    //
        // Here we are testing receiving Wrong Msg on SB                       //
        /////////////////////////////////////////////////////////////////////////

        // Start the test with the previous configurations.
        for (int i = 8; i < 31; i++) begin
            $display("\n=========>  Test Scenario (%0d): Receive Wrong SB Msg.  <=========", test_scenario_no++);
            $display(  "=========>             (timeout 8ms occurs)             <=========");
            while (random_msg === msg_no_e'(8'hXX) || random_msg === TRAINERROR_Entry_req) begin
                random_msg = msg_no_e'($urandom_range(8'h0, 8'hFF));
            end

            // Determine a random number of clock cycles to wait before sending the wrong SB message, to simulate receiving the wrong SB message at any moment during the test execution.
            // After passing these clocks, the testbench will send the wrong SB message to the RX_D2C_PT instance by setting the "receive_wrong_sb_msg" signal to 1 and assigning the "random_msg" to "wrong_sb_msg_value", then it will set the "receive_wrong_sb_msg" signal back to 0 after one cycle to clear it.
            // The random value is between 0 and 500000 clocks because the fsm applies all fsm states successfully in around 500000 clocks of lclk.
            random_clocks = $urandom_range(0, 500000);

            start_test(
                .receive_wrong_sb_msg_after(random_clocks), // Randomize the time of receiving the wrong SB message to be at any moment.
                .wrong_sb_msg              (random_msg   )  // We can use any expected SB message as the wrong SB message here, as we are just testing the case of receiving wrong SB message.
            );
            reset(); // because the applied Test Scenario was directed to TO_TRAINERROR state, we need to reset the system before starting a new test scenario.
        end


        ////////////////////////////////////////////////////////////////////////////////////////////////////
        // The test scenario 31:10000 or (31:10000 but it will take some minutes)): Check Holes Scenario. //
        ////////////////////////////////////////////////////////////////////////////////////////////////////
        // for(int i = 18; i <= 1000; i++) begin
        for(int i = 31; i <= 10; i++) begin
            $display("\n=========>  Test Scenario (%0d): Holes Scenario. <=========", test_scenario_no++);
            temporary_var = 0;
            while(temporary_var < MIN_VAL_VREF_CODE) begin
                temporary_var = VREF_CODE_WIDTH'($random());
            end
            assume_errors (
                .task_aggr_err     (16'($random())), // The aggregate error to be assumed for the test scenario.
                .task_perlane_err  (16'($random())), // The per-lane error to be assumed for the test scenario.
                // .task_val_err      (1'b0    ), // The valid lane error to be assumed for the test scenario.
                // .task_clk_err      (1'b0    )  // The clock lane error to be assumed for the test scenario.
                .task_vref_code_min(VREF_CODE_WIDTH'(temporary_var)),
                .task_vref_code_max(VREF_CODE_WIDTH'($urandom_range(temporary_var, MAX_VAL_VREF_CODE)) ),
                .task_assume_holes_after_quarter_eye_start(1)
            );
            start_test();
        end


        if(fail_count == 0) begin
            $display("        ============================================       ");
            $display("      ==============                    ==============     ");
            $display("    ================  Congratulations!  ================   ");
            $display("  ==================  The tests passed  ================== ");
            $display("    ================    Successfully    ================   ");
            $display("      ==============                    ==============     ");
            $display("        ============================================       \n\n"); end
        @(posedge lclk); // Just wait for some time to let the test scenario run and observe the behavior.
        $stop;
    end



endmodule


