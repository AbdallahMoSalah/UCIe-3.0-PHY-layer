`timescale 1ps/1ps
module unit_VALTRAINCENTER_tb ();
    import UCIe_pkg::*;
    parameter LCLK_PERIOD          = 1*1000 ; // That means lclk period = 1ns (1GHz) and for the waveform persetion: multiply by 1000.
    parameter TIMEOUT_CYCLES       = 700_000; // Number of lclk cycles to wait before declaring a timeout (e.g., for 8ms timeout at 1GHz, it would be 8 million cycles). Here i will use 700_000 cycles to run the simulation faster.
    parameter ANALOG_SETTLE_CYCLES = 10     ; // Number of lclk cycles to wait the analog circuits in the MB to settle its signals.
    parameter MIN_PHASE_CODE       = 6'D0   ;
    parameter MAX_PHASE_CODE       = 6'D63  ;
    parameter PHASE_CODE_WIDTH     = $clog2(MAX_PHASE_CODE + 1);
    
    // LTSM signals.
    reg  lclk         ;
    reg  rst_n        ;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // States names
    typedef enum reg [3:0] {
        VALTRAINCENTER_IDLE          = unit_VALTRAINCENTER_inst.VALTRAINCENTER_IDLE         , // (S0)
        VALTRAINCENTER_START_REQ     = unit_VALTRAINCENTER_inst.VALTRAINCENTER_START_REQ    , // (S1)
        VALTRAINCENTER_START_RESP    = unit_VALTRAINCENTER_inst.VALTRAINCENTER_START_RESP   , // (S2)
        VALTRAINCENTER_SET_PHASE     = unit_VALTRAINCENTER_inst.VALTRAINCENTER_SET_PHASE    , // (S3)
        VALTRAINCENTER_TX_D2C_PT     = unit_VALTRAINCENTER_inst.VALTRAINCENTER_TX_D2C_PT    , // (S4)
        VALTRAINCENTER_LOG_RESULT    = unit_VALTRAINCENTER_inst.VALTRAINCENTER_LOG_RESULT   , // (S5)
        VALTRAINCENTER_CALC_APPLY    = unit_VALTRAINCENTER_inst.VALTRAINCENTER_CALC_APPLY   , // (S6)
        VALTRAINCENTER_DONE_REQ      = unit_VALTRAINCENTER_inst.VALTRAINCENTER_DONE_REQ     , // (S7)
        VALTRAINCENTER_DONE_RESP     = unit_VALTRAINCENTER_inst.VALTRAINCENTER_DONE_RESP    , // (S8)
        TO_VALTRAINVREF              = unit_VALTRAINCENTER_inst.TO_VALTRAINVREF             , // (S9)
        TO_TRAINERROR                = unit_VALTRAINCENTER_inst.TO_TRAINERROR               , // (S10)
        Continue_Repeating_The_Last_3_States = 'hF
    } fsm_state_t;
    fsm_state_t current_state, monitor_current_state;

    assign current_state  = fsm_state_t'(unit_VALTRAINCENTER_inst.current_state);


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
    // |  -------------------------       (Instance of the VALTRAINCENTER module)       ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    unit_VALTRAINCENTER #(
        .MAX_PHASE_CODE(MAX_PHASE_CODE),
        .MIN_PHASE_CODE(MIN_PHASE_CODE)
    ) unit_VALTRAINCENTER_inst (
        .d2c_if(intf),
        .valtraincenter_if(intf)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ), 
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)  
    ) ltsm_tb_attachments_inst (
        .intf(intf)
    );

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                (assume_errors)               ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    reg [PHASE_CODE_WIDTH-1:0] current_task_phase_min    ;
    reg [PHASE_CODE_WIDTH-1:0] current_task_phase_max    ;
    reg assume_holes_after_quarter_eye_start;

    task assume_errors (
            input [15:0] task_aggr_err     = 16'b0 , 
            input [15:0] task_perlane_err  = 16'b0 , 
            input [PHASE_CODE_WIDTH-1:0] task_phase_code_min  = PHASE_CODE_WIDTH'(15),
            input [PHASE_CODE_WIDTH-1:0] task_phase_code_max  = PHASE_CODE_WIDTH'(45),
            input task_assume_holes_after_quarter_eye_start = 0
        );
        intf.tb_aggr_err          = task_aggr_err    ;
        intf.tb_perlane_err       = task_perlane_err ;
        current_task_phase_min    = task_phase_code_min;
        current_task_phase_max    = task_phase_code_max;

        assume_holes_after_quarter_eye_start = task_assume_holes_after_quarter_eye_start;
    endtask

    always @(*) begin
        if(intf.phy_tx_pi_phase_ctrl >= current_task_phase_min && intf.phy_tx_pi_phase_ctrl <= current_task_phase_max) begin

            // =============================================================================================== //
            // Adding a deliberate hole (hole) in the eye to force the RTL to test all pathways.               //
            // For simplicity: Consider the hole be added after the (1/4) of the correct Phase range.          //
            // =============================================================================================== //
            if ((intf.phy_tx_pi_phase_ctrl == current_task_phase_min + (current_task_phase_max - current_task_phase_min)/4 ) &&
                    assume_holes_after_quarter_eye_start == 1 ) begin
                intf.tb_val_err = 1'b1;  // A deliberate mistake in the middle!
            end
            else begin // (Inside Eye Diagram)
                intf.tb_val_err = 1'b0; // The right point that is inside the Eye Diagram.
            end
        end
        else begin
            intf.tb_val_err = 1'b1; // The points are too low Phase or too high Phase.
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

        intf.tb_wait_timeout    = 0;
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
    integer lclk_counter          = 0;
    reg     lclk_counter_run_flag = 0;
    integer success_count         = 0;
    integer fail_count            = 0;
    reg [10:0] entered_states;

    task start_test(
            input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES    ,
            input integer  receive_wrong_sb_msg_after = TIMEOUT_CYCLES    ,
            input msg_no_e wrong_sb_msg               = NOTHING            
        );
        logic test_timeout_8ms_occured;
        entered_states = 0;
        fork : test_execution
            begin
                intf.valtraincenter_en = 1'b1;
                lclk_counter_run_flag = 1; 
                wait(intf.valtraincenter_done || intf.trainerror_req); #1step; 

                intf.valtraincenter_en = 1'b0;
                test_timeout_8ms_occured = (intf.trainerror_req);
                if(intf.trainerror_req != 1'b1) begin
                    integer hole_pos;
                    integer expected_best_center;
                    logic                        phase_fail_flag;
                    
                    hole_pos               = (assume_holes_after_quarter_eye_start)? current_task_phase_min + (current_task_phase_max - current_task_phase_min)/4 : (current_task_phase_min-1);
                    expected_best_center   = (hole_pos + 1 + current_task_phase_max) / 2;
                    phase_fail_flag        = (assume_holes_after_quarter_eye_start && current_task_phase_min == current_task_phase_max);

                    if (( intf.valtraincenter_fail_flag !=  phase_fail_flag) ||
                            (!intf.valtraincenter_fail_flag && !phase_fail_flag && intf.phy_tx_pi_phase_ctrl != expected_best_center)) begin

                        repeat(5) $display("\t\t ************************** ERROR **************************");
                        $display("error valtraincenter_fail_flag = %0d, phase_fail_flag = %0b, intf.phy_tx_pi_phase_ctrl = %0d, Expected Center = %0d, is_there_holes = %0b",
                            intf.valtraincenter_fail_flag,
                            phase_fail_flag,
                            intf.phy_tx_pi_phase_ctrl,
                            expected_best_center,
                            assume_holes_after_quarter_eye_start);
                        $stop;
                    end

                    wait(current_state == VALTRAINCENTER_IDLE); #1step;
                end
                else begin
                    wait(current_state == TO_TRAINERROR); #1step;
                end

                if(test_timeout_8ms_occured == 1) begin
                    if(intf.rx_sb_msg == TRAINERROR_Entry_req) begin 
                        fail_count    = (intf.tb_wrong_sb_msg_en == 1'b1)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wrong_sb_msg_en == 1'b1)? success_count + 1 : success_count ;

                        if(intf.tb_wrong_sb_msg_en == 1'b1) begin
                            $display("%10t ps, (Total lclk cycles: %0d): The FSM entered the \"TO_TRAINERROR\" state as expected correctly (due to receiving TRAINERROR SB message from the partner).", $realtime(), lclk_counter);
                            $display("\t\t That happens because the wrong Msg \"%s\" after passing %0d clock of lclk",
                                intf.tb_wrong_sb_msg.name(), receive_wrong_sb_msg_after);
                        end else begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps: The FSM received unexpected {TRAINERROR Entry req} SB Message. <================================= [Error]\n", $realtime());
                            $stop;
                        end

                    end
                    else begin
                        fail_count    = (intf.tb_wait_timeout == 1'b1)? fail_count        : fail_count + 1;
                        success_count = (intf.tb_wait_timeout == 1'b1)? success_count + 1 : success_count ;

                        if(intf.tb_wrong_sb_msg_en == 1'b1) begin
                            $display("%10t ps: The test passed but is directed to TO_TRAINERROR (due to timeout).", $realtime());
                        end else begin
                            repeat(5) $display("\t\t ************************** ERROR **************************");
                            $display("%10t ps: FSM logic failed (Timeout). <================================= [Error]\n", $realtime());
                            $stop;
                        end
                    end
                end
                else begin
                    success_count++;
                    $display("%10t ps: The test passed successfully.", $realtime());
                end

                $display("_____(Success count = %0d, Fail count = %0d, The total lclk cycles: %0d)_____\n", success_count, fail_count, lclk_counter);
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
                wait(current_state == VALTRAINCENTER_IDLE);         
                entered_states[0] = 1;                       
                wait(current_state == VALTRAINCENTER_START_REQ);    
                entered_states[1] = 1;                       
                wait(current_state == VALTRAINCENTER_START_RESP);   
                entered_states[2] = 1;                       
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
    msg_no_e random_msg = NOTHING;
    integer random_clocks=0;
    logic   first_loop;
    integer temporary_var = 0;
    
    always @(posedge lclk or negedge rst_n) begin
        if(!lclk) begin
            first_loop = 1;
        end else if(entered_states[10:0] == 11'b000_0011_1111) begin
            first_loop = 0;
        end else begin
            first_loop = 1;
        end
    end

    assign monitor_current_state = (current_state == TO_TRAINERROR)? TO_TRAINERROR :
        ((entered_states[10:0] == 11'b000_0011_1111) && !first_loop)? Continue_Repeating_The_Last_3_States : current_state;

    initial begin
        reset();
        $monitor("%10t ps : The Currernt state: (\"%s\").", $realtime(), monitor_current_state.name());

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (1, 2, 3) : Happy Scenario.                       //
        /////////////////////////////////////////////////////////////////////////
        for(int i = 0; i < 3; i++) begin
            $display("\n=========>  Test Scenario (%0d): Happy Scenario. <=========", test_scenario_no++);
            assume_errors (
                .task_aggr_err     (16'h0009),
                .task_perlane_err  (16'h0008), 
                .task_phase_code_min(6'd15),
                .task_phase_code_max(6'd45),
                .task_assume_holes_after_quarter_eye_start(0)
            );
            start_test();
        end

        //////////////////////////////////////////////////////////////////////////
        // The test scenario (4, 5, 6) : SB Connection Interruption.            //
        //////////////////////////////////////////////////////////////////////////
        repeat(3) begin
            $display("\n=========>  Test Scenario (%0d): SB Connection Interruption. <=========", test_scenario_no++);
            $display(  "=========>               (timeout 8ms occurs)                <=========");
            start_test(
                .abort_mb_or_sb_after      (TIMEOUT_CYCLES),
                .receive_wrong_sb_msg_after($urandom_range(0, 'D560_000)),
                .wrong_sb_msg              (NOTHING)
            );
            reset(); 
        end

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (7) : Receive {TRAINERROR Entry req} SB Msg.      //
        /////////////////////////////////////////////////////////////////////////
        $display("\n=========>  Test Scenario (%0d): Receive {TRAINERROR Entry req} SB Msg. <=========", test_scenario_no++);
        $display(  "=========>                   (timeout doesn't occur)                    <=========");
        assume_errors (
            .task_phase_code_min(MIN_PHASE_CODE),
            .task_phase_code_max(MAX_PHASE_CODE)
        );
        start_test(
            .receive_wrong_sb_msg_after(400_000),
            .wrong_sb_msg              (TRAINERROR_Entry_req)
        );
        reset();

        /////////////////////////////////////////////////////////////////////////
        // The test scenario (8:30) : Receive Wrong SB Msg.                    //
        /////////////////////////////////////////////////////////////////////////
        for (int i = 8; i < 31; i++) begin
            $display("\n=========>  Test Scenario (%0d): Receive Wrong SB Msg.  <=========", test_scenario_no++);
            $display(  "=========>             (timeout 8ms occurs)             <=========");
            while (random_msg === msg_no_e'(8'hXX) || random_msg === TRAINERROR_Entry_req) begin
                random_msg = msg_no_e'($urandom_range(8'h0, 8'hFF));
            end
            random_clocks = $urandom_range(0, 500000);
            start_test(
                .receive_wrong_sb_msg_after(random_clocks),
                .wrong_sb_msg              (random_msg)
            );
            reset();
        end

        ////////////////////////////////////////////////////////////////////////////////////////////////////
        // The test scenario 31:100 : Check Holes Scenario.                                               //
        ////////////////////////////////////////////////////////////////////////////////////////////////////
        for(int i = 31; i <= 100; i++) begin
            $display("\n=========>  Test Scenario (%0d): Holes Scenario. <=========", test_scenario_no++);
            temporary_var = 0;
            while(temporary_var < MIN_PHASE_CODE) begin
                temporary_var = PHASE_CODE_WIDTH'($random());
            end
            assume_errors (
                .task_aggr_err       (16'($random())),
                .task_perlane_err    (16'($random())),
                .task_phase_code_min (PHASE_CODE_WIDTH'(temporary_var)),
                .task_phase_code_max (PHASE_CODE_WIDTH'($urandom_range(temporary_var, MAX_PHASE_CODE))),
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
            $display("        ============================================       \n\n"); 
        end
        @(posedge lclk);
        $stop;
    end
endmodule
