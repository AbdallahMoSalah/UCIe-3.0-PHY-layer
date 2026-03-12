`timescale 1ps / 1ps
import UCIe_pkg::*;

module RX_D2C_PT_tb ();
    parameter LCLK_PERIOD    = 1.00*1000; // That means lclk period = 1ns (1GHz) and for the waveform persetion: multiply by 1000.
    parameter SB_CLK_PERIOD  = 1.25*1000; // That means SB clk period = 1.25ns (800Hz) and for the waveform persetion: multiply by 1000.
    parameter TIMEOUT_CYCLES = 10000; // Number of lclk cycles to wait before declaring a timeout (e.g., for 8ms timeout at 1GHz, it would be 8 million cycles).
    
    // Core clocks and resets
    reg  lclk         ;
    reg  rst_n        ;

    // States names from RTL implementation
    typedef enum reg [3:0] {
        RX_PT_IDLE            = 4'h0, // (S0)
        RX_PT_START_REQ       = 4'h1, // (S1)
        RX_PT_START_RESP      = 4'h2, // (S2)
        RX_PT_CLR_ERR_REQ     = 4'h3, // (S3)
        RX_PT_CLR_ERR_RESP    = 4'h4, // (S4)
        RX_PT_PATTERN_GEN     = 4'h5, // (S5)
        RX_PT_COUNT_DONE_REQ  = 4'h6, // (S6)
        RX_PT_COUNT_DONE_RESP = 4'h7, // (S7)
        RX_PT_END_REQ         = 4'h8, // (S8)
        RX_PT_END_RESP        = 4'h9, // (S9)
        RX_PT_DONE            = 4'hA, // (S10)
        TO_TRAINERROR         = 4'hB  // (S11)
    } fsm_state_t;
    
    fsm_state_t current_state, previous_state;

    // Monitor internal states
    always @(*) begin
        current_state  = fsm_state_t'(RX_D2C_PT_inst.current_state );
        previous_state = fsm_state_t'(RX_D2C_PT_inst.previous_state);
    end

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
    
    //For SB clk:
    reg sb_clk;
    initial begin
      sb_clk = 0;
      forever #(SB_CLK_PERIOD/2) sb_clk = ~sb_clk;
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------           (Interface Instantiation)          ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    ltsm_if #(
        .MAX_VAL_VREF_CODE(64),
        .MAX_DATA_VREF_CODE(64)
    ) intf (
        .lclk(lclk),
        .rst_n(rst_n)
    );

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------      (Instance of the RX_D2C_PT module)      ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    
    RX_D2C_PT RX_D2C_PT_inst (
        .clk_rst(intf.clk_rst_mp),
        .d2c_if(intf.d2c2ltsm_mp),
        .mb_if(intf.d2c2mb_mp),
        .sb_if(intf.ltsm2sb_mp),
        .rf_if(intf.state_rf_offset_1050_mp)
    );

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------         (timeout_8ms_counter module)         ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer timeout_8ms_counter;
    reg     counter_8ms_en;
    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            timeout_8ms_counter      <= 0;
            intf.timeout_8ms_occured <= 0;
            counter_8ms_en           <= 0;
        end 
        else begin
            timeout_8ms_counter      <= (counter_8ms_en)? timeout_8ms_counter + 1 : 0;
            intf.timeout_8ms_occured <= (timeout_8ms_counter < TIMEOUT_CYCLES)? 0 : 1;
        end
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (MB Representation)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    integer burst_counter, idle_counter, iter_counter; 
    reg [15:0] aggr_err    ; 
    reg [15:0] perlane_err ; 
    reg        val_err     ; 
    reg        clk_err     ; 
    reg        wait_timeout; 

    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            burst_counter                 <= 0;
            idle_counter                  <= 0;
            iter_counter                  <= 0;
            intf.mb_tx_pattern_count_done <= 0;
            intf.mb_rx_compare_done       <= 0;
            intf.mb_rx_aggr_err           <= 0;
            intf.mb_rx_perlane_err        <= 0;
            intf.mb_rx_val_err            <= 0;
            intf.mb_rx_clk_err            <= 0;
        end
        else if(wait_timeout == 0) begin
            if(intf.mb_tx_pattern_en) begin
                if(burst_counter != intf.mb_tx_burst_count && iter_counter != intf.mb_tx_iter_count) begin
                    burst_counter <= burst_counter + 1; 
                end
                else if(idle_counter != intf.mb_tx_idle_count && iter_counter != intf.mb_tx_iter_count) begin
                    idle_counter <= idle_counter + 1; 
                end
                else if(iter_counter != intf.mb_tx_iter_count) begin
                    iter_counter  <= iter_counter + 1; 
                    burst_counter <= 0               ; 
                    idle_counter  <= 0               ; 
                end
                
                if(iter_counter == intf.mb_tx_iter_count) begin
                    intf.mb_tx_pattern_count_done <= 1; 
                end
                else begin
                    intf.mb_tx_pattern_count_done <= 0; 
                end
            end

            if(intf.mb_tx_pattern_count_done == 1'b1) begin
                intf.mb_rx_compare_done <= 1          ; 
                intf.mb_rx_aggr_err     <= aggr_err   ; 
                intf.mb_rx_perlane_err  <= perlane_err;
                intf.mb_rx_val_err      <= val_err    ;
                intf.mb_rx_clk_err      <= clk_err    ;
            end
        end
        else begin 
            intf.mb_tx_pattern_count_done <= 0;
        end
    end

    task assume_errors (
        input [15:0] task_aggr_err    , 
        input [15:0] task_perlane_err , 
        input        task_val_err     , 
        input        task_clk_err       
    );
        aggr_err     = task_aggr_err    ;
        perlane_err  = task_perlane_err ;
        val_err      = task_val_err     ;
        clk_err      = task_clk_err     ;
    endtask

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (SB Representation)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    reg [1:0] rx_sb_msg_valid_reg ; 
    integer   sb_msg_waiting_time ; 
    reg       receive_wrong_sb_msg; 
    msg_no_e  wrong_sb_msg_value  ; 
    
    always @(posedge sb_clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_sb_msg_valid_reg[1:0] <= 1'b0;
            intf.rx_sb_msg           <= NOTHING;
            sb_msg_waiting_time      <= 0;
        end
        else if(wait_timeout == 1'b0) begin
            if(intf.tx_sb_msg_valid) begin
                sb_msg_waiting_time <= sb_msg_waiting_time + 1; 

                if(sb_msg_waiting_time == 128) begin
                    rx_sb_msg_valid_reg[1:0] <= {1'b1, rx_sb_msg_valid_reg[1]}; 
                    if( intf.tx_sb_msg == Start_Rx_Init_D_to_C_point_test_req ||
                        intf.tx_sb_msg == Start_Rx_Init_D_to_C_point_test_resp ||
                        intf.tx_sb_msg == LFSR_clear_error_req ||
                        intf.tx_sb_msg == LFSR_clear_error_resp ||
                        intf.tx_sb_msg == Rx_Init_D_to_C_Tx_Count_Done_req ||
                        intf.tx_sb_msg == Rx_Init_D_to_C_Tx_Count_Done_resp ||
                        intf.tx_sb_msg == End_Rx_Init_D_to_C_point_test_req || 
                        intf.tx_sb_msg == End_Rx_Init_D_to_C_point_test_resp ) begin
                            intf.rx_sb_msg <= (receive_wrong_sb_msg)? wrong_sb_msg_value : intf.tx_sb_msg;
                    end
                end 
                else if(sb_msg_waiting_time >= (128 + 15) ) begin
                    rx_sb_msg_valid_reg <= 1'b0;
                    sb_msg_waiting_time <= 0; 
                end
            end else begin
                rx_sb_msg_valid_reg <= 1'b0; 
            end
        end
    end

    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            intf.rx_sb_msg_valid <= 1'b0;
        end
        else begin
            if(rx_sb_msg_valid_reg[1] && !rx_sb_msg_valid_reg[0]) begin
                intf.rx_sb_msg_valid <= 1'b1; 
            end
            else begin
                intf.rx_sb_msg_valid <= 1'b0; 
            end
        end
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                 (Reset Task)                 ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task reset();
        rst_n                                  = 0;
        intf.rx_pt_en                          = 0;
        intf.mb_tx_pattern_count_done          = 0;
        intf.mb_rx_perlane_err                 = 0;
        intf.mb_rx_val_err                     = 0;
        intf.mb_rx_clk_err                     = 0;
        intf.mb_rx_compare_done                = 0;
        intf.d2c_clk_sampling                  = 0;
        intf.d2c_lfsr_en                       = 0;
        intf.d2c_pattern_setup                 = 0;
        intf.d2c_data_pattern_sel              = 0;
        intf.d2c_val_pattern_sel               = 0;
        intf.d2c_pattern_mode                  = 0;
        intf.d2c_burst_count                   = 0;
        intf.d2c_idle_count                    = 0;
        intf.d2c_iter_count                    = 0;
        intf.d2c_compare_setup                 = 0;
        intf.rx_sb_msg_valid                   = 0;
        intf.rx_sb_msg                         = NOTHING;
        intf.cfg_train4_max_err_thresh_perlane = 0;
        intf.cfg_train4_max_err_thresh_aggr    = 0;
        wait_timeout                           = 0;
        #10;
        rst_n = 1;
    endtask

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------             (Set Configurations)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task set_d2c_configuration (
        input reg [1:0]  task_clk_sampling    ,
        input reg [2:0]  task_pattern_setup   , 
        input reg [1:0]  task_data_pattern_sel, 
        input reg [1:0]  task_val_pattern_sel , 
        input reg        task_lfsr_en         ,
        input reg        task_pattern_mode    ,
        input reg [15:0] task_burst_count     ,
        input reg [3:0]  task_idle_count      ,
        input reg [3:0]  task_iter_count      ,
        input reg [1:0]  task_compare_setup   , 
        input reg [15:0] task_aggr_err_thresh , 
        input reg [15:0] task_perlane_err_thresh 
    );
        intf.d2c_clk_sampling                  = task_clk_sampling    ; 
        intf.d2c_pattern_setup                 = task_pattern_setup   ; 
        intf.d2c_data_pattern_sel              = task_data_pattern_sel; 
        intf.d2c_val_pattern_sel               = task_val_pattern_sel ; 
        intf.d2c_lfsr_en                       = task_lfsr_en         ;
        intf.d2c_pattern_mode                  = task_pattern_mode    ;
        intf.d2c_burst_count                   = task_burst_count     ;
        intf.d2c_idle_count                    = task_idle_count      ;
        intf.d2c_iter_count                    = task_iter_count      ;
        intf.d2c_compare_setup                 = task_compare_setup   ; 
        intf.cfg_train4_max_err_thresh_aggr    = task_aggr_err_thresh ; 
        intf.cfg_train4_max_err_thresh_perlane = task_perlane_err_thresh; 
    endtask

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------               ( Start Test Task)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer lclk_counter = 0; 
    reg lclk_counter_run_flag = 0; 

    task start_test(
        input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES    , 
        input integer  receive_wrong_sb_msg_after = TIMEOUT_CYCLES    , 
        input msg_no_e wrong_sb_msg               = TRAINERROR_Entry_req  
    );
        reg [11:0] entered_states;
        entered_states = 0;
        fork : test_execution
            begin
                counter_8ms_en = 1; 
                intf.rx_pt_en  = 1; 
                lclk_counter_run_flag = 1; 
                #(LCLK_PERIOD);     
                intf.rx_pt_en  = 0; 

                wait(intf.test_d2c_done || intf.d2c_timeout_or_error); 
                @(posedge lclk);  
                if(intf.d2c_timeout_or_error == 1) begin
                    #1; 
                    $display("%8t ps: The test passed but is directed to TO_TRAINERROR due to timeout.", $realtime());
                end
                else if(intf.d2c_timeout_or_error == 0) begin
                    repeat(1) @(posedge lclk); 
                    #1; 
                    $display("%8t ps: The test passed successfully.", $realtime());
                end
                $display("=========   =========   =========   =========   =========   =========");
                counter_8ms_en = 0; 
                disable test_execution; 
            end

            begin
                for (int i=0; i<receive_wrong_sb_msg_after ; i++) begin
                    @(posedge lclk);
                    receive_wrong_sb_msg = 0;
                    wrong_sb_msg_value   = wrong_sb_msg; 
                end
                receive_wrong_sb_msg = 1; 
            end

            begin
                for (int i=0; i<abort_mb_or_sb_after ; i++) begin
                    @(posedge lclk);
                    wait_timeout = 0;
                end
                wait_timeout = 1; 
            end

            begin : check_fsm_transitions
                wait(current_state == RX_PT_IDLE); 
                    entered_states[1] = 1; 
                wait(current_state == RX_PT_START_REQ); 
                    entered_states[0] = 1; 
                wait(current_state == RX_PT_START_RESP); 
                    entered_states[2] = 1; 
                wait(current_state == RX_PT_CLR_ERR_REQ); 
                    entered_states[3] = 1; 
                wait(current_state == RX_PT_CLR_ERR_RESP); 
                    entered_states[4] = 1; 
                wait(current_state == RX_PT_PATTERN_GEN); 
                    entered_states[5] = 1;  
                wait(current_state == RX_PT_COUNT_DONE_REQ); 
                    entered_states[6] = 1; 
                wait(current_state == RX_PT_COUNT_DONE_RESP); 
                    entered_states[7] = 1; 
                wait(current_state == RX_PT_END_REQ); 
                    entered_states[8] = 1; 
                wait(current_state == RX_PT_END_RESP); 
                    entered_states[9] = 1; 
                wait(current_state == RX_PT_DONE); 
                    entered_states[10] = 1;    
                wait(current_state == RX_PT_IDLE); 
                    entered_states[11] = 1; 
            end
        join

        #1step;
        if(entered_states == 12'b111111111111) begin
            $display("%8t ps, (Total lclk cycles: %0d): The FSM entered all the expected states in the correct order.\n", $realtime(), lclk_counter);
        end
        else if ((intf.d2c_timeout_or_error == 1'b1 && (wait_timeout == 1'b1 || receive_wrong_sb_msg == 1'b1)) ||
                 (receive_wrong_sb_msg == 1'b1 &&  wrong_sb_msg == TRAINERROR_Entry_req)) begin
            $display("%8t ps, (Total lclk cycles: %0d): The FSM entered the \"TO_TRAINERROR\" state as expected correctly.", $realtime(), lclk_counter);
            if(receive_wrong_sb_msg) begin
                $display("\t\t That happens because the wrong Msg \"%s\" after passing %0d clock of lclk (Note we assume timeout be at %0d)\n", 
                wrong_sb_msg_value.name(), 
                receive_wrong_sb_msg_after, 
                TIMEOUT_CYCLES);
            end 
            else begin
                $display("\0"); 
            end
        end else begin
            $display("%8t ps, (Total lclk cycles: %0d): The FSM did not enter all the expected states in the correct order. <================================= [Error]\n", $realtime(), lclk_counter);
            $stop;
        end

        #1step; 
        lclk_counter_run_flag = 0; 
        wait_timeout          = 0; 
        receive_wrong_sb_msg  = 0; 
        @(posedge lclk); 
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

    // /////////////////////                                                                  \\\\\\\\\\\\\\\\\\\\\\\\ 
    //     /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    //    |  -------------------------          (Test Bench Main Actions)           ---------------------------  |
    //     \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    msg_no_e random_msg; 
    integer random_clocks; 

    initial begin
        reset();

        $monitor("%8t ps : The Currernt state:     (\"%s\")", $realtime(), current_state.name());

        $display("\n1) Test Scenario 1: VALVREF");
        $display("=========>  Start (VALVREF) Test Scenario:  <=========");

        set_d2c_configuration (
            .task_clk_sampling   (2'b0), 
            .task_pattern_setup   (1     ), 
            .task_data_pattern_sel(2'b11 ), 
            .task_val_pattern_sel (3'b000), 
            .task_lfsr_en         (0     ), 
            .task_pattern_mode(1'b0), 
            .task_burst_count (128 ), 
            .task_idle_count  (4'h0), 
            .task_iter_count  (4'h1), 
            .task_compare_setup     (2'b00   ), 
            .task_aggr_err_thresh   (16'h0000), 
            .task_perlane_err_thresh(16'h0000)  
        );

        assume_errors (
            .task_aggr_err     (16'h0000), 
            .task_perlane_err  (16'h0000), 
            .task_val_err      (1'b0    ), 
            .task_clk_err      (1'b0    )  
        );
        start_test();


        $display("\n2) Test Scenario 2: DATAVREF");
        $display("=========>  Start (DATAVREF) Test Scenario:  <=========");

        set_d2c_configuration (
            .task_clk_sampling   (2'b0), 
            .task_pattern_setup   (3'b011), 
            .task_data_pattern_sel(2'b00 ), 
            .task_val_pattern_sel (3'b10 ), 
            .task_lfsr_en         (1     ), 
            .task_pattern_mode(1'b0), 
            .task_burst_count (4096), 
            .task_idle_count  (4'h0), 
            .task_iter_count  (4'h1), 
            .task_compare_setup     (2'b00   ), 
            .task_aggr_err_thresh   (16'h0000), 
            .task_perlane_err_thresh(16'h0000)  
        );

        assume_errors (
            .task_aggr_err     (16'h0000), 
            .task_perlane_err  (16'h0000), 
            .task_val_err      (1'b0    ), 
            .task_clk_err      (1'b0    )  
        );
        start_test();


        $display("\n3) Test Scenario 3: DATAVREF");
        $display("=========>  Start (DATAVREF) Test Scenario:  <=========");
        for (int i=0; i<4; i++) begin
            set_d2c_configuration (
                .task_clk_sampling   (i), 
                .task_pattern_setup   (3'b011), 
                .task_data_pattern_sel(   i  ), 
                .task_val_pattern_sel (3'b10 ), 
                .task_lfsr_en         (1     ), 
                .task_pattern_mode(1'b0), 
                .task_burst_count (4096), 
                .task_idle_count  (4'h0), 
                .task_iter_count  (4'h1), 
                .task_compare_setup     (    i   ), 
                .task_aggr_err_thresh   (16'hFFFF), 
                .task_perlane_err_thresh(16'hFFFF)  
            );

            assume_errors (
                .task_aggr_err     (16'hFFFF), 
                .task_perlane_err  (16'hFFFF), 
                .task_val_err      (i[0]    ), 
                .task_clk_err      (i[1]    )  
            );
            start_test();
        end

        $display("\n4) Test Scenario 4: (timeout 8ms)");
        $display("=========>  Start (timeout 8ms) Test Scenario:  <=========");
        start_test(.abort_mb_or_sb_after(600)); 


        reset(); 
        $display("\n5) Test Scenario 5: (TRAINERROR Req Msg receiving)");
        $display("=========>  Start (TRAINERROR Req Msg receiving) Test Scenario:  <=========");
        start_test(
            .receive_wrong_sb_msg_after(600) ,
            .wrong_sb_msg(TRAINERROR_Entry_req)
        );
        

        reset(); 
        $display("\n6) Test Scenario 6: (Wrong Msg receiving)");
        $display("=========>  Start (Wrong Msg receiving) Test Scenario:  <=========");

        for (int i = 0; i < 10; i++) begin
            case (i[3:0])
                0,9 : random_msg = Start_Rx_Init_D_to_C_point_test_req;
                1,10: random_msg = Start_Rx_Init_D_to_C_point_test_resp;
                2,11: random_msg = LFSR_clear_error_req;
                3,12: random_msg = LFSR_clear_error_resp;
                4,13: random_msg = Rx_Init_D_to_C_Tx_Count_Done_req;
                5,14: random_msg = Rx_Init_D_to_C_Tx_Count_Done_resp;
                6,15: random_msg = End_Rx_Init_D_to_C_point_test_req;
                7   : random_msg = End_Rx_Init_D_to_C_point_test_resp;
                8   : random_msg = TRAINERROR_Entry_req; 
            endcase

            random_clocks = $urandom_range(0, 1500); 

            start_test(
                .receive_wrong_sb_msg_after(random_clocks), 
                .wrong_sb_msg(random_msg) 
            );
            reset(); 
        end
        
        @(posedge lclk); 
        $stop;
    end
endmodule