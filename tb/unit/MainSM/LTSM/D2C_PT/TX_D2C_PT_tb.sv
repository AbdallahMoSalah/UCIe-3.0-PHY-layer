
`timescale 1ps / 1ps
module TX_D2C_PT_tb ();
    parameter LCLK_PERIOD    =   1*1000; // That means lclk period = 1ns (1GHz) and for the waveform persetion: multiply by 1000.
    parameter SB_CLK_PERIOD  = 1.25*1000; // That means SB clk period = 1.25ns (800Hz) and for the waveform persetion: multiply by 1000.
    parameter TIMEOUT_CYCLES = 100_000; // Number of lclk cycles to wait before declaring a timeout (e.g., for 8ms timeout at 1GHz, it would be 8 million cycles).
    // LTSM signals.
    reg  lclk         ;
    reg  rst_n        ;


    ltsm_if #(
        .MAX_VAL_VREF_CODE(64),
        .MAX_DATA_VREF_CODE(64)
    ) intf (
        .lclk(lclk),
        .rst_n(rst_n)
    );


    // States names
    typedef enum reg [3:0] {
        TX_PT_IDLE         = TX_D2C_PT_inst.TX_PT_IDLE        , // (S0)
        TX_PT_START_REQ    = TX_D2C_PT_inst.TX_PT_START_REQ   , // (S1)
        TX_PT_START_RESP   = TX_D2C_PT_inst.TX_PT_START_RESP  , // (S2)
        TX_PT_CLR_ERR_REQ  = TX_D2C_PT_inst.TX_PT_CLR_ERR_REQ , // (S3)
        TX_PT_CLR_ERR_RESP = TX_D2C_PT_inst.TX_PT_CLR_ERR_RESP, // (S4)
        TX_PT_PATTERN_GEN  = TX_D2C_PT_inst.TX_PT_PATTERN_GEN , // (S5)
        TX_PT_RESULTS_REQ  = TX_D2C_PT_inst.TX_PT_RESULTS_REQ  , // (S6)
        TX_PT_RESULTS_RESP = TX_D2C_PT_inst.TX_PT_RESULTS_RESP , // (S7)
        TX_PT_END_REQ      = TX_D2C_PT_inst.TX_PT_END_REQ     , // (S8)
        TX_PT_END_RESP     = TX_D2C_PT_inst.TX_PT_END_RESP    , // (S9)
        TX_PT_DONE         = TX_D2C_PT_inst.TX_PT_DONE        , // (S10)
        TO_TRAINERROR      = TX_D2C_PT_inst.TO_TRAINERROR       // (S11)
    } fsm_state_t;
    fsm_state_t current_state;

    always @(*) begin
        current_state  = fsm_state_t'(TX_D2C_PT_inst.current_state);
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
    // |  -------------------------      (Instance of the TX_D2C_PT module)      ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    TX_D2C_PT TX_D2C_PT_inst (
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
            timeout_8ms_counter <= 0;
            intf.timeout_8ms_occured         <= 0;
            counter_8ms_en      <= 0;
        end
        else begin
            timeout_8ms_counter <= (counter_8ms_en)? timeout_8ms_counter + 1 : 0;
            intf.timeout_8ms_occured         <= (timeout_8ms_counter < TIMEOUT_CYCLES)? 0 : 1; // Set intf.timeout_8ms_occured to 1 if the TIMEOUT counter reaches the defined TIMEOUT_CYCLES, otherwise keep it at 0.
        end
    end

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (MB Representation)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    integer burst_counter, idle_counter, iter_counter; // Counters to track the number of "Burst", "Idle", and "Iteration" count in the MB.
    reg [15:0] aggr_err    ; // Aggregate error for current comparison.
    reg [15:0] perlane_err ; // Per-lane  error for current comparison.
    reg        val_err     ; // valid error for current comparison.
    reg        clk_err     ; // clock error for current comparison.
    reg        wait_timeout; // Used to test the timeout condition by waiting for some time before setting intf.mb_tx_pattern_count_done to 1.

    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            // Reset all the control signals to MB to their default values.
            burst_counter            <= 0;
            idle_counter             <= 0;
            iter_counter             <= 0;
            intf.mb_tx_pattern_count_done <= 0;
            intf.mb_rx_perlane_err        <= 0;
            intf.mb_rx_val_err            <= 0;
            intf.mb_rx_clk_err            <= 0;
            intf.mb_rx_compare_done       <= 0;
            intf.mb_rx_aggr_err           <= 0;
            intf.mb_rx_perlane_err        <= 0;
            intf.mb_rx_val_err            <= 0;
            intf.mb_rx_clk_err            <= 0;

        end
        // Here we can add any sequential behavior of the MB control signals if needed for the test scenarios.
        else if(wait_timeout == 0) begin
            if(intf.mb_tx_pattern_en) begin
                if(burst_counter != intf.mb_tx_burst_count && iter_counter != intf.mb_tx_iter_count) begin
                    burst_counter <= burst_counter + 1; // Increment the burst counter when the pattern is enabled (indicating a burst is being sent).
                end
                else if(idle_counter != intf.mb_tx_idle_count && iter_counter != intf.mb_tx_iter_count) begin
                    idle_counter <= idle_counter + 1; // Increment the idle counter when the burst count is reached.
                end
                else if(iter_counter != intf.mb_tx_iter_count) begin
                    iter_counter  <= iter_counter + 1; // Increment the iteration counter when both burst count and idle count are reached.
                    burst_counter <= 0               ; // Reset the burst counter at the end of each iteration.
                    idle_counter  <= 0               ; // Reset the idle counter at the end of each iteration.
                end

                if(iter_counter == intf.mb_tx_iter_count) begin
                    intf.mb_tx_pattern_count_done <= 1; // Indicate that the pattern count is done after the assumed duration.
                end
                else begin
                    intf.mb_tx_pattern_count_done <= 0; // Keep it low until the burst count is reached.
                end
            end

            if(intf.mb_tx_pattern_count_done == 1'b1) begin
                intf.mb_rx_compare_done <= 1          ; // Indicate that the comparison is done after the pattern count is done.
                intf.mb_rx_aggr_err     <= aggr_err   ; // Update the aggregate error from the D2C block to MB after the comparison is done.
                intf.mb_rx_perlane_err  <= perlane_err;
                intf.mb_rx_val_err      <= val_err    ;
                intf.mb_rx_clk_err      <= clk_err    ;
            end
        end
        else begin // The timeout occurrs because of the MB.
            intf.mb_tx_pattern_count_done <= 0;
        end
    end


    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                (assume_errors)               ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/

    reg [15:0] rx_msginfo_value1, // The MsgInfo of the received SB signal {Start Tx Init D to C point test req}
    rx_msginfo_value2; // The MsgInfo of the received SB signal {Start Tx Init D to C results resp}
    reg [63:0] rx_data_field_value1, // The Data field of the received SB signal {Start Tx Init D to C point test req}
    rx_data_field_value2; // The Data field of the received SB signal {Start Tx Init D to C results resp}

    task assume_errors (
            input [15:0] task_aggr_err    = 16'b0, // The aggregate error to be assumed for the test scenario.
            input [15:0] task_perlane_err = 16'b0, // The per-lane error to be assumed for the test scenario.
            input        task_val_err     = 1'b0 , // The valid lane error to be assumed for the test scenario.
            input        task_clk_err     = 1'b0 , // The clock lane error to be assumed for the test scenario.
            input        partner_val_err  = 1'b0 , // From the Partner: Valid lane error result.
            input        partner_aggr_err = 1'b0   // From the Partner: The aggregate error here represents 1 bit.
        );
        aggr_err     = task_aggr_err    ;
        perlane_err  = task_perlane_err ;
        val_err      = task_val_err     ;
        clk_err      = task_clk_err     ;

        // The result Data received via SB after the end of the pattern test:
        rx_msginfo_value2    = {10'b0, partner_val_err, partner_aggr_err, 4'b0}; // The received MsgInfo field of the SB Msg {Start Tx Init D to C results resp}
        rx_data_field_value2 = {48'b0, intf.rx_data_field}; // The received Data field of the SB Msg {Start Tx Init D to C results resp}, where the lower 16 bits are used to capture the per-lane error from the D2C block to SB.
    endtask


    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (SB Representation)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    typedef enum reg[8:0] {
        MSG_START_REQ      = TX_D2C_PT_inst.MSG_START_REQ     , // From LTSM to SB to request the start of Rx D2C Pattern Test.
        MSG_START_RESP     = TX_D2C_PT_inst.MSG_START_RESP    , // From SB to LTSM to acknowledge the start of Rx D2C Pattern Test.
        MSG_CLR_ERR_REQ    = TX_D2C_PT_inst.MSG_CLR_ERR_REQ   , // From LTSM to SB to request clearing of errors in MB before starting pattern generation.
        MSG_CLR_ERR_RESP   = TX_D2C_PT_inst.MSG_CLR_ERR_RESP  , // From SB to LTSM to acknowledge the clearing of errors in MB.
        MSG_RESULTS_REQ    = TX_D2C_PT_inst.MSG_RESULTS_REQ   , // From LTSM to SB to ask if the pattern generation and error counting is done based on burst_count and iter_count.
        MSG_RESULTS_RESP   = TX_D2C_PT_inst.MSG_RESULTS_RESP  , // From SB to LTSM to acknowledge that the pattern generation and error counting is done.
        MSG_END_REQ        = TX_D2C_PT_inst.MSG_END_REQ       , // From LTSM to SB to request SB to end the pattern test and send results.
        MSG_END_RESP       = TX_D2C_PT_inst.MSG_END_RESP      , // From SB to LTSM to acknowledge the end of the pattern test and sending of results.
        MSG_TRAINERROR_REQ = TX_D2C_PT_inst.MSG_TRAINERROR_REQ  // From SB to LTSM to indicate that a TRAINERROR condition has occurred on the partner side (e.g., due to timeout or other errors during training).
    } sb_msg_t;
    sb_msg_t  tx_sb_msg_enum, rx_sb_msg_enum; // The SB message that the testbench will send to the RX_D2C_PT instance.
    reg [1:0]  rx_sb_msg_valid_reg ; // A register to hold the valid signal for the received SB message, used for generating a pulse of "intf.rx_sb_msg_valid" for one cycle.
    integer   sb_msg_waiting_time ; // A counter to track the waiting time for the SB message to be received, used for testing the timeout condition.
    reg       receive_wrong_sb_msg; // To identecate if we want to test the case of receiving wrong SB message by setting this signal to 1 and assigning a wrong SB message to "wrong_sb_msg".
    sb_msg_t  wrong_sb_msg_value  ; // A wrong SB message to be used in the test scenario of receiving wrong SB message.

    always @(*) begin
        tx_sb_msg_enum = sb_msg_t'(intf.tx_sb_msg); // Capture the received SB message from the RX_D2C_PT instance.
        rx_sb_msg_enum = sb_msg_t'(intf.rx_sb_msg); // Capture the received SB message from the RX_D2C_PT instance.
    end

    always @(posedge sb_clk or negedge rst_n) begin
        if(!rst_n) begin
            // Reset the SB TX signals.
            rx_sb_msg_valid_reg[1:0] <= 2'b0;
            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'(8'b0);
            sb_msg_waiting_time      <= 0;
        end
        else if(wait_timeout == 1'b0) begin
            if(intf.tx_sb_msg_valid) begin
                sb_msg_waiting_time <= sb_msg_waiting_time + 1; // Increment the waiting time for the SB message to be received.

                // Wait till the SB MSG Receives the partner MSG:
                if(sb_msg_waiting_time == 128) begin
                    rx_sb_msg_valid_reg[1:0] <= {1'b1, rx_sb_msg_valid_reg[1]}; // Set the valid signal in "rx_sb_msg_valid_reg[1]" to 1 to indicate that the SB message is now valid; also, store the previous value.

                    case (tx_sb_msg_enum)
                        MSG_START_REQ: begin
                            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'((receive_wrong_sb_msg)? wrong_sb_msg_value : MSG_START_REQ); // Capture the received SB message.
                            intf.rx_msginfo    <= rx_msginfo_value1   ; // Capture the received MsgInfo field of the SB message (that is coming from the testbench).
                            intf.rx_data_field <= rx_data_field_value1; // Capture the received Data field of the SB message (that is coming from the testbench).
                        end
                        MSG_START_RESP: begin
                            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'((receive_wrong_sb_msg)? wrong_sb_msg_value : MSG_START_RESP); // Capture the received SB message.
                            intf.rx_msginfo    <= 16'b0; // Capture the received MsgInfo field of the SB message (that is coming from the testbench).
                            intf.rx_data_field <= 64'b0; // Capture the received Data field of the SB message (that is coming from the testbench).
                        end
                        MSG_CLR_ERR_REQ: begin
                            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'((receive_wrong_sb_msg)? wrong_sb_msg_value : MSG_CLR_ERR_REQ); // Capture the received SB message.
                            intf.rx_msginfo    <= 16'b0; // Capture the received MsgInfo field of the SB message (that is coming from the testbench).
                            intf.rx_data_field <= 64'b0; // Capture the received Data field of the SB message (that is coming from the testbench).
                        end
                        MSG_CLR_ERR_RESP: begin
                            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'((receive_wrong_sb_msg)? wrong_sb_msg_value : MSG_CLR_ERR_RESP); // Capture the received SB message.
                            intf.rx_msginfo    <= 16'b0; // Capture the received MsgInfo field of the SB message (that is coming from the testbench).
                            intf.rx_data_field <= 64'b0; // Capture the received Data field of the SB message (that is coming from the testbench).
                        end
                        MSG_RESULTS_REQ: begin
                            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'((receive_wrong_sb_msg)? wrong_sb_msg_value : MSG_RESULTS_REQ); // Capture the received SB message.
                            intf.rx_msginfo    <= 16'b0; // Capture the received MsgInfo field of the SB message (that is coming from the testbench).
                            intf.rx_data_field <= 64'b0; // Capture the received Data field of the SB message (that is coming from the testbench).
                        end
                        MSG_RESULTS_RESP: begin
                            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'((receive_wrong_sb_msg)? wrong_sb_msg_value : MSG_RESULTS_RESP); // Capture the received SB message.
                            intf.rx_msginfo    <= rx_msginfo_value2   ; // Capture the received MsgInfo field of the SB message (that is coming from the testbench).
                            intf.rx_data_field <= rx_data_field_value2; // Capture the received Data field of the SB message (that is coming from the testbench).
                        end
                        MSG_END_REQ: begin
                            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'((receive_wrong_sb_msg)? wrong_sb_msg_value : MSG_END_REQ); // Capture the received SB message.
                            intf.rx_msginfo    <= 16'b0; // Capture the received MsgInfo field of the SB message (that is coming from the testbench).
                            intf.rx_data_field <= 64'b0; // Capture the received Data field of the SB message (that is coming from the testbench).
                        end
                        MSG_END_RESP: begin
                            intf.rx_sb_msg <= UCIe_pkg::msg_no_e'((receive_wrong_sb_msg)? wrong_sb_msg_value : MSG_END_RESP); // Capture the received SB message.
                            intf.rx_msginfo    <= 16'b0; // Capture the received MsgInfo field of the SB message (that is coming from the testbench).
                            intf.rx_data_field <= 64'b0; // Capture the received Data field of the SB message (that is coming from the testbench).
                        end
                    endcase
                end
                // Set the intf.rx_sb_msg_valid signal activated for some times (using SB clk) (ex: 15 cycles):
                else if(sb_msg_waiting_time >= (128 + 15) ) begin
                    rx_sb_msg_valid_reg <= 1'b0;
                    sb_msg_waiting_time <= 0; // Clear the waiting time after the message is received and valid signal is deactivated.
                end
            end else begin
                rx_sb_msg_valid_reg <= 1'b0; // Clear the valid signal if the intf.tx_sb_msg_valid is not active.
            end
        end
    end

    // Pulse Generator module for the signal: "intf.rx_sb_msg_valid".
    // Note we have to receive just a pulse of "intf.rx_sb_msg_valid" for a 1 lclk cycle. (We use lclk here).
    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            // Reset the SB RX signals.
            intf.rx_sb_msg_valid <= 1'b0;
        end
        else begin
            if(rx_sb_msg_valid_reg[1] && !rx_sb_msg_valid_reg[0]) begin
                intf.rx_sb_msg_valid <= 1'b1; // Set the valid signal to 1 for one cycle.
            end
            else begin
                intf.rx_sb_msg_valid <= 1'b0; // Clear the valid signal after one cycle.
            end
        end
    end



    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                 (Reset Task:)                ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task reset();
        rst_n                    = 0;
        intf.tx_pt_en            = 0;
        intf.timeout_8ms_occured              = 0;
        intf.mb_tx_pattern_count_done = 0;
        intf.mb_rx_perlane_err        = 0;
        intf.mb_rx_val_err            = 0;
        intf.mb_rx_clk_err            = 0;
        intf.mb_rx_compare_done       = 0;
        intf.d2c_clk_sampling         = 0;
        intf.d2c_lfsr_en              = 0;
        intf.d2c_pattern_setup        = 0;
        intf.d2c_data_pattern_sel     = 0;
        intf.d2c_val_pattern_sel      = 0;
        intf.d2c_pattern_mode         = 0;
        intf.d2c_burst_count          = 0;
        intf.d2c_idle_count           = 0;
        intf.d2c_iter_count           = 0;
        intf.d2c_compare_setup        = 0;
        intf.rx_sb_msg_valid          = 0;
        intf.rx_sb_msg = UCIe_pkg::msg_no_e'(0);
        intf.cfg_train4_max_err_thresh_perlane = 0;
        intf.cfg_train4_max_err_thresh_aggr    = 0;
        wait_timeout = 0; // Set wait_timeout to 0 to indicate that we are not testing the timeout condition at the beginning.
        #10;
        rst_n = 1;
    endtask




    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------             (Set Configurations)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task set_d2c_configuration (
            // Clock sampling/PI phase control:
            input reg [1:0] task_clk_sampling    , // Set the clock sampling/PI phase control state to ""Eye Center"", ""Left edge"", or ""Right edge"" for this test scenario.

            // Tx Pattern Generator Setup:
            input reg [2:0] task_pattern_setup   , // Set the pattern setup for this test scenario.
            input reg [1:0] task_data_pattern_sel, // Set the data pattern selection for this test scenario.
            input reg [1:0] task_val_pattern_sel , // Set the valid pattern selection for this test scenario.
            input reg       task_lfsr_en         ,

            // Tx Pattern Mode Setup:
            input reg        task_pattern_mode   ,
            input reg [15:0] task_burst_count    ,
            input reg [3:0]  task_idle_count     ,
            input reg [3:0]  task_iter_count     ,

            // Receiver Comparison Setup:
            input reg [1:0]  task_compare_setup     , // Set the comparison setup to Per-Lane for this test scenario.
            input reg [15:0] task_aggr_err_thresh   , // Set the aggregate error threshold from RF for this test scenario.
            input reg [15:0] task_perlane_err_thresh, // Set the per-lane error threshold from RF for this test scenario.

            // The configuration data received via SB from the partner:
            input reg [15:0] partner_max_err_thresh   = 16'h00  , // From the Partner: the maximum error threshold of Per-lane comparison if (intf.rx_data_field[59] == 0, in other words "partner_compare_setup == 0") else it will be of the aggregate comparison.
            input reg        partner_compare_setup    =  1'b0   , // From the Partner: Comparison Mode (0: Per Lane; 1: Aggregate)
            input reg [15:0] partner_iter_count       = 16'h1   , // From the Partner: Iteration Count Setting.
            input reg [15:0] partner_idle_count       = 16'h0   , // From the Partner: Idle Count Setting.
            input reg [15:0] partner_burst_count      = 16'd4096, // From the Partner: Burst Count Setting.
            input reg        partner_pattern_mode     =  1'b0   , // From the Partner: Pattern Mode (0: continuous mode, 1: Burst Mode).
            input reg [3:0]  partner_clk_sampling     =  1'h0   , // From the Partner: Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
            input reg [2:0]  partner_val_pattern_sel  =  3'b0   , // From the Partner: Valid Pattern (0h: Functional pattern).
            input reg [2:0]  partner_data_pattern_sel =  1'b0     // From the Partner: Data pattern (0h: LFSR, 1h: Per Lane ID).
        );
        // Clock sampling/PI phase control:
        intf.d2c_clk_sampling     = task_clk_sampling    ; // Set the clock sampling/PI phase control state for this test scenario.

        // Tx Pattern Generator Setup:
        intf.d2c_pattern_setup    = task_pattern_setup   ; // Set the pattern setup for this test scenario.
        intf.d2c_data_pattern_sel = task_data_pattern_sel; // Set the data pattern selection for this test scenario.
        intf.d2c_val_pattern_sel  = task_val_pattern_sel ; // Set the valid pattern selection for this test scenario.
        intf.d2c_lfsr_en          = task_lfsr_en         ;

        // Tx Pattern Mode Setup:
        intf.d2c_pattern_mode     = task_pattern_mode    ;
        intf.d2c_burst_count      = task_burst_count     ;
        intf.d2c_idle_count       = task_idle_count      ;
        intf.d2c_iter_count       = task_iter_count      ;

        // Receiver Comparison Setup:
        intf.d2c_compare_setup    = task_compare_setup                  ; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
        intf.cfg_train4_max_err_thresh_aggr    = task_aggr_err_thresh   ; // Set the aggregate error threshold from RF for this test scenario.
        intf.cfg_train4_max_err_thresh_perlane = task_perlane_err_thresh; // Set the per-lane error threshold from RF for this test scenario.

        // The configuration data received via SB from the partner:
        rx_msginfo_value1           = {partner_max_err_thresh};
        rx_data_field_value1[63:60] = 4'b0                    ; // Reseved.
        rx_data_field_value1[59   ] = partner_compare_setup   ; // Comparison Mode (0: Per Lane; 1: Aggregate)
        rx_data_field_value1[58:43] = partner_iter_count      ; // The number of iterations for the pattern generation.
        rx_data_field_value1[42:27] = partner_idle_count      ; // The number of 0s (idle cycles) between bursts for the pattern generation.
        rx_data_field_value1[26:11] = partner_burst_count     ; // The number of bursts in each iteration for the pattern generation.
        rx_data_field_value1[10   ] = partner_pattern_mode    ; // Pattern Mode (0: continuous mode, 1: Burst Mode).
        rx_data_field_value1[ 9:6 ] = partner_clk_sampling    ; // Clock sampling/PI phase control state (0: Eye Center, 1: Left Edge, 2: Right Edge)
        rx_data_field_value1[ 5:3 ] = partner_val_pattern_sel ; // Valid pattern selection for the pattern generation.
        rx_data_field_value1[ 2:0 ] = partner_data_pattern_sel; // Data pattern selection for the pattern generation.

    endtask



    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------               ( Start Test Task)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer lclk_counter = 0; // A counter to track the number of lclk cycles during the test execution, used for debugging and verification purposes.
    reg lclk_counter_run_flag = 0; // A flag to indicate whether the lclk counter should be running to count the lclk cycles during the test execution.

    task start_test(
            input integer  abort_mb_or_sb_after       = TIMEOUT_CYCLES    , // The input argument is used to determine whether the testbench should simulate the timeout condition caused by MB or SB by waiting for some time before setting intf.mb_tx_pattern_count_done to 1 or before sending the expected SB response, respectively.
            input integer  receive_wrong_sb_msg_after = TIMEOUT_CYCLES    , // The input argument is used to determine whether the testbench should simulate the timeout condition caused by SB by waiting for some time before sending the expected SB response.
            input sb_msg_t wrong_sb_msg               = MSG_TRAINERROR_REQ  // The wrong SB message to be sent if we want to test the case of receiving wrong SB message.
        );
        reg [11:0] entered_states;
        entered_states = 0;
        fork : test_execution
            begin
                counter_8ms_en = 1; // Enable the 8ms timeout counter at the start of the test.
                intf.tx_pt_en  = 1; // Trigger the Rx D2C Pattern Test.
                lclk_counter_run_flag = 1; // Start counting the lclk cycles from the moment we trigger the test.
                #(LCLK_PERIOD);     // Wait for one clock cycle after triggering the test.
                intf.tx_pt_en  = 0; // Clear the trigger after one cycle.

                wait(intf.test_d2c_done || intf.d2c_timeout_or_error); // Wait until the test is done or a timeout/error occurs.
                @(posedge lclk); // To keep the $monitor system function (that is used in the main initial block) print the final state of the FSM first, before the next $display content.
                if(intf.d2c_timeout_or_error == 1) begin
                    #1; // To make sure that the $monitor function has printed its sentence.
                    if(rx_sb_msg_enum == MSG_TRAINERROR_REQ) begin
                        $display("%8t ps: The test passed but is directed to TO_TRAINERROR due to receiving TRAINERROR SB message from the partner.\n", $realtime());
                    end
                    else begin
                        $display("%8t ps: The test passed but is directed to TO_TRAINERROR due to timeout.", $realtime());
                    end
                end
                else if(intf.d2c_timeout_or_error == 0) begin
                    repeat(1) @(posedge lclk); // To keep the $monitor system function print the IDLE state of the FSM, to prove that the FSM go back to the start point.
                    #1; // To make sure that the $monitor function has printed its sentence.
                    $display("%8t ps: The test passed successfully.", $realtime());
                end
                $display("=========   =========   =========   =========   =========   =========");
                counter_8ms_en = 0; // Disable the 8ms timeout counter at the end of the test.
                disable test_execution; // Disable the fork to end the test execution.
            end

            begin
                // Wait some lclk cycles = "receive_wrong_sb_msg_after" to simulate receiving wrong SB message condition caused by SB, then set the "intf.d2c_timeout_or_error" signal to 1 to indicate that an error has occurred during the test.
                for (int i=0; i<receive_wrong_sb_msg_after ; i++) begin
                    @(posedge lclk);
                    receive_wrong_sb_msg = 0;
                    wrong_sb_msg_value = wrong_sb_msg; // Assign the wrong SB message to be sent.
                end
                receive_wrong_sb_msg = 1; // Set the timeout_or_error signal to 1 after applying the wrong SB message.
            end

            begin
                // Wait some lclk cycles = "abort_mb_or_sb_after" to simulate the timeout condition caused by MB or SB, then set the "intf.d2c_timeout_or_error" signal to 1 to indicate that a timeout or error has occurred during the test.
                for (int i=0; i<abort_mb_or_sb_after ; i++) begin
                    @(posedge lclk);
                    wait_timeout = 0;
                end
                wait_timeout = 1; // Set the timeout_or_error signal to 1 after waiting for some time to simulate the timeout condition caused by MB or SB.
            end

            begin : check_fsm_transitions
                wait(current_state == TX_PT_IDLE); // Wait for the FSM to be in the IDLE state before starting the test.
                entered_states[1] = 1; // Mark that we have entered the IDLE.
                wait(current_state == TX_PT_START_REQ); // Wait for the FSM to transition to the START_REQ state.
                entered_states[0] = 1; // Mark that we have entered the START_REQ state.
                wait(current_state == TX_PT_START_RESP); // Wait for the FSM to transition to the START_RESP state.
                entered_states[2] = 1; // Mark that we have entered the START_RESP state.
                wait(current_state == TX_PT_CLR_ERR_REQ); // Wait for the FSM to transition to the CLR_ERR_REQ state.
                entered_states[3] = 1; // Mark that we have entered the CLR_ERR_REQ state.
                wait(current_state == TX_PT_CLR_ERR_RESP); // Wait for the FSM to transition to the CLR_ERR_RESP state.
                entered_states[4] = 1; // Mark that we have entered the CLR_ERR_RESP state.
                wait(current_state == TX_PT_PATTERN_GEN); // Wait for the FSM to transition to the PATTERN_GEN state.
                entered_states[5] = 1; // Mark that we have entered the PATTERN_GEN state.
                wait(current_state == TX_PT_RESULTS_REQ); // Wait for the FSM to transition to the RESULTS_REQ state.
                entered_states[6] = 1; // Mark that we have entered the RESULTS_REQ state.
                wait(current_state == TX_PT_RESULTS_RESP); // Wait for the FSM to transition to the RESULTS_RESP state.
                entered_states[7] = 1; // Mark that we have entered the RESULTS_RESP state.
                wait(current_state == TX_PT_END_REQ); // Wait for the FSM to transition to the END_REQ state.
                entered_states[8] = 1; // Mark that we have entered the END_REQ state.
                wait(current_state == TX_PT_END_RESP); // Wait for the FSM to transition to the END_RESP state.
                entered_states[9] = 1; // Mark that we have entered the END_RESP state.
                wait(current_state == TX_PT_DONE); // Wait for the FSM to transition to the DONE state.
                entered_states[10] = 1; // Mark that we have entered the DONE state.
                wait(current_state == TX_PT_IDLE); // Wait for the FSM to transition to the TO_TRAINERROR state if a timeout or error occurs.
                entered_states[11] = 1; // Mark that we have entered the TO_TRAINERROR state.
            end
        join

        #1step;
        if(entered_states == 12'b111111111111) begin
            $display("%8t ps, (Total lclk cycles: %0d): The FSM entered all the expected states in the correct order.\n", $realtime(), lclk_counter);
        end
        else if ((intf.d2c_timeout_or_error == 1'b1 && (wait_timeout == 1'b1 || receive_wrong_sb_msg == 1'b1)) ||
                (receive_wrong_sb_msg == 1'b1 &&  wrong_sb_msg == MSG_TRAINERROR_REQ)) begin
            $display("%8t ps, (Total lclk cycles: %0d): The FSM entered the \"TO_TRAINERROR\" state as expected correctly.", $realtime(), lclk_counter);
            if(receive_wrong_sb_msg) begin
                $display("\t\t That happens because the wrong Msg \"%s\" after passing %0d clock of lclk (Note we assume timeout be at %0d)\n",
                    wrong_sb_msg_value.name(),
                    receive_wrong_sb_msg_after,
                    TIMEOUT_CYCLES);
            end
            else begin
                $display("\0"); // Just write a new line.
            end
        end else begin
            $display("%8t ps, (Total lclk cycles: %0d): The FSM did not enter all the expected states in the correct order. <================================= [Error]\n", $realtime(), lclk_counter);
            $stop;
        end

        #1step;
        lclk_counter_run_flag = 0; // Stop counting the lclk cycles at the end of the test.
        wait_timeout          = 0; // Clear the timeout_or_error signal after the test is done.
        receive_wrong_sb_msg  = 0; // Clear the receive_wrong_sb_msg signal after the test is done.
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
    int burst_lcounter = 1000, idle_lcounter = 100, iter_lcounter = 4; // Local counters to track the number of bursts, idles, and iterations during the test execution for debugging and verification purposes.
    bit lpattern_mode = 1; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
    sb_msg_t random_msg; // A random SB message to be used in the test scenarios that do not require specific SB message.
    integer random_clocks=0; // A random number of clock cycles to be used in the test scenarios that do not require specific timing for SB message reception or timeout.
    initial begin
        // Reset the system.
        reset();

        // Monitor the current state of the RX_D2C_PT instance for debugging purposes.
        $monitor("%8t ps : The Currernt state:     (\"%s\")", $realtime(), current_state.name());


        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the VALTRAINCENTER test scenario.     //
        /////////////////////////////////////////////////////////////////////////
        $display("\n1) Test Scenario 1: VALTRAINCENTER");
        $display("=========>  Start (VALTRAINCENTER) Test Scenario:  <=========");

        set_d2c_configuration (
            // Clock sampling/PI phase control:
            .task_clk_sampling   (2'b0), // Set the clock sampling/PI phase control state to "0: "Eye Center"", "1: "Left edge"", or "2: "Right edge"" for this test scenario.

            // Tx Pattern Generator Setup:
            .task_pattern_setup   (3'b010), // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            .task_data_pattern_sel(2'b11 ), // Data pattern used during training: (0: LFSR; 1: ID; 3: All 0)
            .task_val_pattern_sel (3'b000), // 0: VALTRAIN pattern, 1: Valid lane is Held low, 2: Operational Valid.
            .task_lfsr_en         (0     ), // 1: Enable the LFSR, 0: Disable the LFSR for both Rx and Tx.

            // Tx Pattern Mode Setup:
            .task_pattern_mode(1'b0), // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
            .task_burst_count (128 ), // Burst Count: Indicates the duration of selected pattern (UI count).
            .task_idle_count  (4'h0), // IDLE Count: Indicates the duration of low following the burst (UI count).
            .task_iter_count  (4'h1), // Iterations: Indicates the iteration count of bursts followed by idle.

            // Receiver Comparison Setup:
            .task_compare_setup     ( 2'b10  ), // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
            .task_aggr_err_thresh   (16'h00AA), // Set the aggregate error threshold from RF for this test scenario.
            .task_perlane_err_thresh(16'h00BB), // Set the per-lane error threshold from RF for this test scenario.

            // The configuration data received via SB from the partner:
            .partner_max_err_thresh  (16'h0F  ), // From the Partner: the maximum error threshold of Per-lane comparison if  (intf.rx_data_field[59] == 0, in other words "partner_compare_setup == 0")  else it will be of the aggregate comparison.
            .partner_compare_setup   ( 1'b0   ), // From the Partner: Comparison Mode (0: Per Lane; 1: Aggregate)
            .partner_iter_count      (16'h1   ), // From the Partner: Iteration Count Setting.
            .partner_idle_count      (16'h0   ), // From the Partner: Idle Count Setting.
            .partner_burst_count     (16'd128 ), // From the Partner: Burst Count Setting.
            .partner_pattern_mode    ( 1'b0   ), // From the Partner: Pattern Mode (0: continuous mode, 1: Burst Mode).
            .partner_clk_sampling    ( 1'h0   ), // From the Partner: Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
            .partner_val_pattern_sel ( 3'b0   ), // From the Partner: Valid Pattern (0h: Functional pattern).
            .partner_data_pattern_sel( 1'b1   )  // From the Partner: Data pattern (0h: LFSR, 1h: Per Lane ID).
        );

        assume_errors (
            .task_aggr_err     (16'h0011), // The aggregate error to be assumed for the test scenario.
            .task_perlane_err  (16'h0011), // The per-lane error to be assumed for the test scenario.
            .task_val_err      (1'b0    ), // The valid lane error to be assumed for the test scenario.
            .task_clk_err      (1'b0    ), // The clock lane error to be assumed for the test scenario.
            .partner_val_err   ( 1'b1   ), // From the Partner: Valid lane error result.
            .partner_aggr_err  ( 1'b1   )  // From the Partner: The aggregate error here represents 1 bit.
        );
        start_test();


        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the DATATRAINCENTER1 test scenario.   //
        /////////////////////////////////////////////////////////////////////////
        $display("\n2) Test Scenario 2: DATATRAINCENTER1");
        $display("=========>  Start (DATATRAINCENTER1) Test Scenario:  <=========");


        set_d2c_configuration (
            // Clock sampling/PI phase control:
            .task_clk_sampling   (2'b0), // Set the clock sampling/PI phase control state to "0: "Eye Center"", "1: "Left edge"", or "2: "Right edge"" for this test scenario.

            // Tx Pattern Generator Setup:
            .task_pattern_setup   (3'b011), // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            .task_data_pattern_sel(2'b11 ), // Data pattern used during training: (0: LFSR; 1: ID; 3: All 0)
            .task_val_pattern_sel (3'b000), // 0: VALTRAIN pattern, 1: Valid lane is Held low, 2: Operational Valid.
            .task_lfsr_en         (1     ), // 1: Enable the LFSR, 0: Disable the LFSR for both Rx and Tx.

            // Tx Pattern Mode Setup:
            .task_pattern_mode(1'b0), // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
            .task_burst_count (4096), // Burst Count: Indicates the duration of selected pattern (UI count).
            .task_idle_count  (4'h0), // IDLE Count: Indicates the duration of low following the burst (UI count).
            .task_iter_count  (4'h1), // Iterations: Indicates the iteration count of bursts followed by idle.

            // Receiver Comparison Setup:
            .task_compare_setup     ( 2'b00  ), // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
            .task_aggr_err_thresh   (16'h0000), // Set the aggregate error threshold from RF for this test scenario.
            .task_perlane_err_thresh(16'h0000), // Set the per-lane error threshold from RF for this test scenario.

            // The configuration data received via SB from the partner:
            .partner_max_err_thresh  (16'h0F  ), // From the Partner: the maximum error threshold of Per-lane comparison if  (intf.rx_data_field[59] == 0, in other words "partner_compare_setup == 0")  else it will be of the aggregate comparison.
            .partner_compare_setup   ( 1'b0   ), // From the Partner: Comparison Mode (0: Per Lane; 1: Aggregate)
            .partner_iter_count      (16'h1   ), // From the Partner: Iteration Count Setting.
            .partner_idle_count      (16'h0   ), // From the Partner: Idle Count Setting.
            .partner_burst_count     (16'd4096), // From the Partner: Burst Count Setting.
            .partner_pattern_mode    ( 1'b0   ), // From the Partner: Pattern Mode (0: continuous mode, 1: Burst Mode).
            .partner_clk_sampling    ( 1'h0   ), // From the Partner: Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
            .partner_val_pattern_sel ( 3'b0   ), // From the Partner: Valid Pattern (0h: Functional pattern).
            .partner_data_pattern_sel( 1'b0   )  // From the Partner: Data pattern (0h: LFSR, 1h: Per Lane ID).
        );

        assume_errors (
            .task_aggr_err     (16'h0011), // The aggregate error to be assumed for the test scenario.
            .task_perlane_err  (16'h0022), // The per-lane error to be assumed for the test scenario.
            .task_val_err      (1'b0    ), // The valid lane error to be assumed for the test scenario.
            .task_clk_err      (1'b0    ), // The clock lane error to be assumed for the test scenario.
            .partner_val_err   ( 1'b1   ), // From the Partner: Valid lane error result.
            .partner_aggr_err  ( 1'b1   )  // From the Partner: The aggregate error here represents 1 bit.
        );
        start_test();




        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the DATATRAINCENTER1 test scenario.   //
        // Here we're testing some corner cases for coverage                   //
        /////////////////////////////////////////////////////////////////////////
        $display("\n3) Test Scenario 3: DATATRAINCENTER1");
        $display("=========>  Start (DATATRAINCENTER1) Test Scenario:  <=========");
        burst_lcounter = 1000; idle_lcounter = 100; iter_lcounter = 10; // Local counters to track the number of bursts, idles, and iterations during the test execution for debugging and verification purposes.
        lpattern_mode = 1; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        for (int i=0; i<4; i++) begin
            set_d2c_configuration (
                // Clock sampling/PI phase control:
                .task_clk_sampling   (i), // Set the clock sampling/PI phase control state to "0: "Eye Center"", "1: "Left edge"", or "2: "Right edge"" for this test scenario.

                // Tx Pattern Generator Setup:
                .task_pattern_setup   (3'b011), // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
                .task_data_pattern_sel(  1  ), // Data pattern used during training: (0: LFSR; 1: ID; 3: All 0)
                .task_val_pattern_sel (3'b000), // 0: VALTRAIN pattern, 1: Valid lane is Held low, 2: Operational Valid (Valid Framing).
                .task_lfsr_en         (1     ), // 1: Enable the LFSR, 0: Disable the LFSR for both Rx and Tx.

                // Tx Pattern Mode Setup:
                .task_pattern_mode(lpattern_mode), // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                .task_burst_count (burst_lcounter), // Burst Count: Indicates the duration of selected pattern (UI count).
                .task_idle_count  (idle_lcounter), // IDLE Count: Indicates the duration of low following the burst (UI count).
                .task_iter_count  (iter_lcounter), // Iterations: Indicates the iteration count of bursts followed by idle.

                // Receiver Comparison Setup:
                .task_compare_setup     (    0   ), // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
                .task_aggr_err_thresh   (16'hFFFF), // Set the aggregate error threshold from RF for this test scenario.
                .task_perlane_err_thresh(16'hFFFF), // Set the per-lane error threshold from RF for this test scenario.

                // The configuration data received via SB from the partner:
                .partner_max_err_thresh  (i), // From the Partner: the maximum error threshold of Per-lane comparison if  (intf.rx_data_field[59] == 0, in other words "partner_compare_setup == 0")  else it will be of the aggregate comparison.
                .partner_compare_setup   (0), // From the Partner: Comparison Mode (0: Per Lane; 1: Aggregate)
                .partner_iter_count      (iter_lcounter), // From the Partner: Iteration Count Setting.
                .partner_idle_count      (idle_lcounter), // From the Partner: Idle Count Setting.
                .partner_burst_count     (burst_lcounter), // From the Partner: Burst Count Setting.
                .partner_pattern_mode    (lpattern_mode), // From the Partner: Pattern Mode (0: continuous mode, 1: Burst Mode).
                .partner_clk_sampling    (2'(i+1)), // From the Partner: Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
                .partner_val_pattern_sel (3'b000), // From the Partner: Valid Pattern (0h: Functional pattern).
                .partner_data_pattern_sel(1)  // From the Partner: Data pattern (0h: LFSR, 1h: Per Lane ID).
            );

            assume_errors (
                .task_aggr_err     (16'hFFFF), // The aggregate error to be assumed for the test scenario.
                .task_perlane_err  (16'hFFFF), // The per-lane error to be assumed for the test scenario.
                .task_val_err      (i[0]    ), // The valid lane error to be assumed for the test scenario.
                .task_clk_err      (i[1]    ), // The clock lane error to be assumed for the test scenario.
                .partner_val_err   ( 1'b0   ), // From the Partner: Valid lane error result.
                .partner_aggr_err  ( 1'b0   )  // From the Partner: The aggregate error here represents 1 bit.
            );

            start_test();
        end

        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the DATATRAINCENTER1 test scenario.   //
        // Here we're testing the timeout caused by the connection interruption//
        /////////////////////////////////////////////////////////////////////////
        $display("\n4) Test Scenario 4: (timeout 8ms)");
        $display("=========>  Start (timeout 8ms) Test Scenario:  <=========");

        // Start the test with the previous configurations.
        start_test(.abort_mb_or_sb_after(600)); // We can use the same configuration as the previous test scenario, as we are just testing the timeout condition here.



        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the DATATRAINCENTER1 test scenario.   //
        // Here we are testing receiving TRAINERROR Msg on SB                  //
        /////////////////////////////////////////////////////////////////////////
        reset(); // because the previous test went to TO_TRAINERROR state, we need to reset the system before starting a new test scenario.
        $display("\n5) Test Scenario 5: (TRAINERROR Req Msg receiving)");
        $display("=========>  Start (TRAINERROR Req Msg receiving) Test Scenario:  <=========");

        // We can use the same configuration as the previous test scenario, as we are just testing TRAINERROR Req Msg receiving here.
        // Start the test with the previous configurations.
        start_test(
            .receive_wrong_sb_msg_after(600) ,
            .wrong_sb_msg(MSG_TRAINERROR_REQ)
        );


        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the DATATRAINCENTER1 test scenario.   //
        // Here we are testing receiving Wrong Msg on SB                       //
        /////////////////////////////////////////////////////////////////////////
        reset(); // because the previous test went to TO_TRAINERROR state, we need to reset the system before starting a new test scenario.
        $display("\n6) Test Scenario 6: (Wrong Msg receiving)");
        $display("=========>  Start (Wrong Msg receiving) Test Scenario:  <=========");

        // We can use the same configuration as the previous test scenario, as we are just testing TRAINERROR Req Msg receiving here.
        // Start the test with the previous configurations.
        for (int i = 0; i < 10; i++) begin
            case (i[3:0])
                0,9 : random_msg = MSG_START_REQ;
                1,10: random_msg = MSG_START_RESP;
                2,11: random_msg = MSG_CLR_ERR_REQ;
                3,12: random_msg = MSG_CLR_ERR_RESP;
                4,13: random_msg = MSG_RESULTS_REQ;
                5,14: random_msg = MSG_RESULTS_RESP;
                6,15: random_msg = MSG_END_REQ;
                7   : random_msg = MSG_END_RESP;
                8   : random_msg = MSG_TRAINERROR_REQ; // Although this is a valid SB message, we can still use it as a wrong message in this test scenario to test the behavior of the system when receiving TRAINERROR Req Msg.
            endcase

            // Determine a random number of clock cycles to wait before sending the wrong SB message, to simulate receiving the wrong SB message at any moment during the test execution.
            // After passing these clocks, the testbench will send the wrong SB message to the RX_D2C_PT instance by setting the "receive_wrong_sb_msg" signal to 1 and assigning the "random_msg" to "wrong_sb_msg_value", then it will set the "receive_wrong_sb_msg" signal back to 0 after one cycle to clear it.
            // The random value is between 0 and 1500 clocks because the fsm applies all fsm states successfully in around 1500 clocks of lclk.
            random_clocks = $urandom_range(0, 1500);

            start_test(
                .receive_wrong_sb_msg_after(random_clocks), // Randomize the time of receiving the wrong SB message to be at any moment.
                .wrong_sb_msg(random_msg) // We can use any expected SB message as the wrong SB message here, as we are just testing the case of receiving wrong SB message.
            );
            reset(); // Reset the system after each iteration to be able to start a new test scenario.
        end


        @(posedge lclk); // Just wait for some time to let the test scenario run and observe the behavior.
        $stop;
    end
endmodule

