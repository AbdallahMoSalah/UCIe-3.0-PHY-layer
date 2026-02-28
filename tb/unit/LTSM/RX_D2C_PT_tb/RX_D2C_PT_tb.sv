
`timescale 1ps / 1ps
module RX_D2C_PT_tb ();
    parameter LCLK_PERIOD    =   1*1000; // That means lclk period = 1ns (1GHz) and for the waveform persetion: multiply by 1000.
    parameter SB_CLK_PERIOD  = 1.25*1000; // That means SB clk period = 1.25ns (800Hz) and for the waveform persetion: multiply by 1000.
    parameter TIMEOUT_CYCLES = 10000; // Number of lclk cycles to wait before declaring a timeout (e.g., for 8ms timeout at 1GHz, it would be 8 million cycles).
    // LTSM signals.
    reg  lclk         ;
    reg  rst_n        ;
    reg  rx_pt_trigger;
    reg  timeout_8ms  ;
    wire test_d2c_done;

    //=====================================//
    // Control Signals To MB:              //
    //=====================================//
    //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
    // Clock Sampling Details Group:
    wire         mb_tx_clk_sampling_en; // Enable changing Clock sampling/PI phase control state.
    wire  [1:0]  mb_tx_clk_sampling   ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
    
    // Tx Pattern Generator Setup Group:
    wire        mb_tx_pattern_en      ; // 1: Send pattern immediately, 0: Don't send pattern.
    wire [2:0]  mb_tx_pattern_setup   ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    wire [1:0]  mb_tx_data_pattern_sel; // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
    wire [1:0]  mb_tx_val_pattern_sel ; // 0: VALTRAIN pattern, 1: Valid lane is Held low, 2: Operational Valid.
    wire        mb_tx_lfsr_en         ; // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
    wire        mb_tx_lfsr_rst        ; // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
    wire        mb_rx_lfsr_en         ; // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
    wire        mb_rx_lfsr_rst        ; // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.
    
    // Tx Pattern Mode Setup Group:
    wire        mb_tx_pattern_mode      ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
    wire [15:0] mb_tx_burst_count       ; // Burst Count: Indicates the duration of selected pattern (UI count).
    wire [3:0]  mb_tx_idle_count        ; // IDLE Count: Indicates the duration of low following the burst (UI count).
    wire [3:0]  mb_tx_iter_count        ; // Iterations: Indicates the iteration count of bursts followed by idle.
    reg         mb_tx_pattern_count_done; // Asserted (=1) once MB completes the iter_count.

    // Receiver Comparison Setup & Errors
    wire        mb_rx_compare_en            ; // 1: Enable the Rx comparison circuit, 0: Disable.
    wire [15:0] mb_rx_max_err_thresh_aggr   ; // Max error Threshold in aggregate comparison.
    wire [11:0] mb_rx_max_err_thresh_perlane; // Max error Threshold in per Lane comparison.
    wire [1:0]  mb_rx_compare_setup         ; // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
    reg  [15:0] mb_rx_aggr_err              ; // The total calculated Aggregate Errors on Rx.
    reg  [15:0] mb_rx_perlane_err           ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
    reg         mb_rx_val_err               ; // The error coming from Valid Lane receiver in MB.
    reg         mb_rx_clk_err               ; // The error coming from Clock Lane receiver in MB.
    reg         mb_rx_compare_done          ; // From MB to LTSM to tell that comparison of burst_count is done.
    
    //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
    // Lane Selection
    wire [1:0] mb_tx_clk_lane_sel ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
    wire [1:0] mb_tx_data_lane_sel; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
    wire [1:0] mb_tx_val_lane_sel ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
    wire [1:0] mb_tx_trk_lane_sel ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
    wire       mb_rx_clk_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
    wire       mb_rx_data_lane_sel; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
    wire       mb_rx_val_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
    wire       mb_rx_trk_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).
     
    // PHY Level Control & Analog Interface
    wire [1:0] phy_tx_clk_lane_sel ; // 0b: Held Low, 1b: Active (Tx Physical Clock Lane).
    wire [1:0] phy_tx_data_lane_sel; // 0b: Held Low, 1b: Active (Tx Physical Data Lanes).
    wire [1:0] phy_tx_val_lane_sel ; // 0b: Held Low, 1b: Active (Tx Physical Valid Lane).
    wire [1:0] phy_tx_trk_lane_sel ; // 0b: Held Low, 1b: Active (Tx Physical Track Lane).
    wire       phy_rx_clk_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Physical Clock Lane).
    wire       phy_rx_data_lane_sel; // 0b: Disabled, 1b: Enabled (Rx Physical Data Lanes).
    wire       phy_rx_val_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Physical Valid Lane).
    wire       phy_rx_trk_lane_sel ; // 0b: Disabled, 1b: Enabled (Rx Physical Track Lane).
    
    //=====================================//
    // Control Signals From Sub-states:    //
    //=====================================//
    reg  [1:0] d2c_clk_sampling    ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
    wire       d2c_timeout_or_error; // Tell the external Sub-state if timeout or error occurs during the test to move to TRAINERROR state.
    
    //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
    // Received Tx Pattern Generator Setup Group:
    reg        d2c_lfsr_en         ; // 1: Enable the Tx & Rx LFSR, 0: Disable the Tx & Rx LFSR.
    reg [2:0]  d2c_pattern_setup   ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    reg [1:0]  d2c_data_pattern_sel; // Data pattern used during training: (0: LFSR; 1: ID; 3: All 0). Note: d2c_data_pattern_sel can't = 2.
    reg [1:0]  d2c_val_pattern_sel ; // 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
    
    // Received Tx Pattern Mode Setup Group:
    reg        d2c_pattern_mode; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
    reg [15:0] d2c_burst_count ; // Burst Count: Indicates the duration of selected pattern (UI count).
    reg [3:0]  d2c_idle_count  ; // IDLE Count: Indicates the duration of low following the burst (UI count).
    reg [3:0]  d2c_iter_count  ; // Iteration Count: Indicates the iteration count of bursts followed by idle.
    
    // Received Receiver Comparison Setup & Errors
    reg  [1:0]  d2c_compare_setup; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
    wire [15:0] d2c_aggr_err     ; // The total calculated Aggregate Errors on Rx.
    wire [15:0] d2c_perlane_err  ; // The Per-Lane Errors (Each bit represents one fail Data Lane).
    wire        d2c_val_err      ; // The error coming from Valid Lane receiver in MB.
    wire        d2c_clk_err      ; // The error coming from Clock Lane receiver in MB.
    
    //=====================================//
    // Sideband Control Signals:           //
    //=====================================//
    // For SB TX:
    wire        tx_sb_msg_valid; // Tell the SB that the selected message is valid.
    wire [7:0]  tx_sb_msg      ; // Tell the Sideband the message that it should to send. 
    wire [15:0] tx_msginfo     ; // MsgInfo field of the SB message. 
    wire [63:0] tx_data_field  ; // Data field of the SB message.
    
    // For SB RX:
    reg        rx_sb_msg_valid; // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
    reg [7:0]  rx_sb_msg      ; // Get the Received SB msg.
    // reg [15:0] rx_msginfo    ;  // MsgInfo field of the SB message received.
    // reg [63:0] rx_data_field ;  // Data field of the SB message.
    

    //=====================================//
    // Register File (RF) Control Signals: //
    //=====================================//
        
    // Training Setup 4 (Offset 1050h)
    // Note: 'Repair Lane mask' (Bits 3:0) is omitted as it only applies to Advanced Package.
    reg [11:0]  cfg_train4_max_err_thresh_perlane; // Max error Threshold in per-Lane comparison for error counting from RF.
    reg [15:0]  cfg_train4_max_err_thresh_aggr   ; // Max error Threshold in aggregate comparison for error counting from RF. 
 

    // States names
    typedef enum reg [3:0] {
        RX_PT_IDLE            = RX_D2C_PT_inst.RX_PT_IDLE           , // (S0)
        RX_PT_START_REQ       = RX_D2C_PT_inst.RX_PT_START_REQ      , // (S1)
        RX_PT_START_RESP      = RX_D2C_PT_inst.RX_PT_START_RESP     , // (S2)
        RX_PT_CLR_ERR_REQ     = RX_D2C_PT_inst.RX_PT_CLR_ERR_REQ    , // (S3)
        RX_PT_CLR_ERR_RESP    = RX_D2C_PT_inst.RX_PT_CLR_ERR_RESP   , // (S4)
        RX_PT_PATTERN_GEN     = RX_D2C_PT_inst.RX_PT_PATTERN_GEN    , // (S5)
        RX_PT_COUNT_DONE_REQ  = RX_D2C_PT_inst.RX_PT_COUNT_DONE_REQ , // (S6)
        RX_PT_COUNT_DONE_RESP = RX_D2C_PT_inst.RX_PT_COUNT_DONE_RESP, // (S7)
        RX_PT_END_REQ         = RX_D2C_PT_inst.RX_PT_END_REQ        , // (S8)
        RX_PT_END_RESP        = RX_D2C_PT_inst.RX_PT_END_RESP       , // (S9)
        RX_PT_DONE            = RX_D2C_PT_inst.RX_PT_DONE           , // (S10)
        TO_TRAINERROR         = RX_D2C_PT_inst.TO_TRAINERROR          // (S11)
    } fsm_state_t;
    fsm_state_t current_state, previous_state;

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
    // |  -------------------------      (Instance of the RX_D2C_PT module)      ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    RX_D2C_PT RX_D2C_PT_inst (.*);

    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------         (timeout_8ms_counter module)         ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    integer timeout_8ms_counter;
    reg    counter_8ms_en;
    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            timeout_8ms_counter <= 0;
            timeout_8ms         <= 0;
            counter_8ms_en      <= 0;
        end 
        else begin
            timeout_8ms_counter <= (counter_8ms_en)? timeout_8ms_counter + 1 : 0;
            timeout_8ms         <= (timeout_8ms_counter < TIMEOUT_CYCLES)? 0 : 1; // Set timeout_8ms to 1 if the TIMEOUT counter reaches the defined TIMEOUT_CYCLES, otherwise keep it at 0.
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
    reg        wait_timeout; // Used to test the timeout condition by waiting for some time before setting mb_tx_pattern_count_done to 1. 
    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            // Reset all the control signals to MB to their default values.
            burst_counter            <= 0;
            idle_counter             <= 0;
            iter_counter             <= 0;
            mb_tx_pattern_count_done <= 0;
            mb_rx_perlane_err        <= 0;
            mb_rx_val_err            <= 0;
            mb_rx_clk_err            <= 0;
            mb_rx_compare_done       <= 0;
            mb_rx_aggr_err           <= 0;
            mb_rx_perlane_err        <= 0;
            mb_rx_val_err            <= 0;
            mb_rx_clk_err            <= 0;
            
        end
        // Here we can add any sequential behavior of the MB control signals if needed for the test scenarios.
        else if(wait_timeout == 0) begin
            if(mb_tx_pattern_en) begin
                if(burst_counter != mb_tx_burst_count && iter_counter != mb_tx_iter_count) begin
                    burst_counter <= burst_counter + 1; // Increment the burst counter when the pattern is enabled (indicating a burst is being sent).
                end
                else if(idle_counter != mb_tx_idle_count && iter_counter != mb_tx_iter_count) begin
                    idle_counter <= idle_counter + 1; // Increment the idle counter when the burst count is reached.
                end
                else if(iter_counter != mb_tx_iter_count) begin
                    iter_counter  <= iter_counter + 1; // Increment the iteration counter when both burst count and idle count are reached.
                    burst_counter <= 0               ; // Reset the burst counter at the end of each iteration.
                    idle_counter  <= 0               ; // Reset the idle counter at the end of each iteration.
                end
                
                if(iter_counter == mb_tx_iter_count) begin
                    mb_tx_pattern_count_done <= 1; // Indicate that the pattern count is done after the assumed duration.
                end
                else begin
                    mb_tx_pattern_count_done <= 0; // Keep it low until the burst count is reached.
                end
            end

            if(mb_tx_pattern_count_done == 1'b1) begin
                mb_rx_compare_done <= 1          ; // Indicate that the comparison is done after the pattern count is done.
                mb_rx_aggr_err     <= aggr_err   ; // Update the aggregate error from the D2C block to MB after the comparison is done.
                mb_rx_perlane_err  <= perlane_err;
                mb_rx_val_err      <= val_err    ;
                mb_rx_clk_err      <= clk_err    ;
            end
        end
        else begin // The timeout occurrs because of the MB.
            mb_tx_pattern_count_done <= 0;
        end
    end

    task assume_errors (
        input [15:0] task_aggr_err    , // The aggregate error to be assumed for the test scenario.
        input [15:0] task_perlane_err , // The per-lane error to be assumed for the test scenario.
        input        task_val_err     , // The valid lane error to be assumed for the test scenario.
        input        task_clk_err       // The clock lane error to be assumed for the test scenario.
    );
        aggr_err     = task_aggr_err    ;
        perlane_err  = task_perlane_err ;
        val_err      = task_val_err     ;
        clk_err      = task_clk_err     ;
    endtask

    
    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------              (SB Representation)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    typedef enum reg[8:0] {
        MSG_START_REQ       = RX_D2C_PT_inst.MSG_START_REQ      , // From LTSM to SB to request the start of Rx D2C Pattern Test.
        MSG_START_RESP      = RX_D2C_PT_inst.MSG_START_RESP     , // From SB to LTSM to acknowledge the start of Rx D2C Pattern Test.
        MSG_CLR_ERR_REQ     = RX_D2C_PT_inst.MSG_CLR_ERR_REQ    , // From LTSM to SB to request clearing of errors in MB before starting pattern generation.
        MSG_CLR_ERR_RESP    = RX_D2C_PT_inst.MSG_CLR_ERR_RESP   , // From SB to LTSM to acknowledge the clearing of errors in MB.
        MSG_COUNT_DONE_REQ  = RX_D2C_PT_inst.MSG_COUNT_DONE_REQ , // From LTSM to SB to ask if the pattern generation and error counting is done based on burst_count and iter_count.
        MSG_COUNT_DONE_RESP = RX_D2C_PT_inst.MSG_COUNT_DONE_RESP, // From SB to LTSM to acknowledge that the pattern generation and error counting is done.
        MSG_END_REQ         = RX_D2C_PT_inst.MSG_END_REQ        , // From LTSM to SB to request SB to end the pattern test and send results.
        MSG_END_RESP        = RX_D2C_PT_inst.MSG_END_RESP       , // From SB to LTSM to acknowledge the end of the pattern test and sending of results.
        MSG_TRAINERROR_REQ  = RX_D2C_PT_inst.MSG_TRAINERROR_REQ   // From SB to LTSM to indicate that a TRAINERROR condition has occurred on the partner side (e.g., due to timeout or other errors during training).
    } sb_msg_t;
    sb_msg_t  tx_sb_msg_enum, rx_sb_msg_enum; // The SB message that the testbench will send to the RX_D2C_PT instance.
    reg [1:0] rx_sb_msg_valid_reg; // A register to hold the valid signal for the received SB message, used for generating a pulse of "rx_sb_msg_valid" for one cycle.
    integer   sb_msg_waiting_time; // A counter to track the waiting time for the SB message to be received, used for testing the timeout condition.

    always @(*) begin
        tx_sb_msg_enum = RX_D2C_PT_inst.tx_sb_msg; // Capture the received SB message from the RX_D2C_PT instance.
        rx_sb_msg_enum = RX_D2C_PT_inst.rx_sb_msg; // Capture the received SB message from the RX_D2C_PT instance.
    end

    always @(posedge sb_clk or negedge rst_n) begin
        if(!rst_n) begin
            // Reset the SB TX signals.
            rx_sb_msg_valid_reg[1:0] <= 1'b0;
            rx_sb_msg                <= 8'b0;
            sb_msg_waiting_time      <= 0;
        end
        else if(wait_timeout == 1'b0) begin
            if(tx_sb_msg_valid) begin
                sb_msg_waiting_time <= sb_msg_waiting_time + 1; // Increment the waiting time for the SB message to be received.

                // Wait till the SB MSG Receives the partner MSG:
                if(sb_msg_waiting_time == 128) begin
                    rx_sb_msg_valid_reg[1:0] <= {1'b1, rx_sb_msg_valid_reg[1]}; // Set the valid signal in "rx_sb_msg_valid_reg[1]" to 1 to indicate that the SB message is now valid; also, store the previous value.
                    if(tx_sb_msg_enum == MSG_START_REQ       ||
                       tx_sb_msg_enum == MSG_START_RESP      ||
                       tx_sb_msg_enum == MSG_CLR_ERR_REQ     ||
                       tx_sb_msg_enum == MSG_CLR_ERR_RESP    ||
                       tx_sb_msg_enum == MSG_COUNT_DONE_REQ  ||
                       tx_sb_msg_enum == MSG_COUNT_DONE_RESP ||
                       tx_sb_msg_enum == MSG_END_REQ         || 
                       tx_sb_msg_enum == MSG_END_RESP         ) begin
                            rx_sb_msg <= tx_sb_msg; // Capture the received SB message.
                    end
                end 
                // Set the rx_sb_msg_valid signal activated for some times (using SB clk) (ex: 15 cycles):
                else if(sb_msg_waiting_time >= (128 + 15)) begin
                    rx_sb_msg_valid_reg <= 1'b0;
                    sb_msg_waiting_time <= 0; // Clear the waiting time after the message is received and valid signal is deactivated.
                end
            end else begin
                rx_sb_msg_valid_reg <= 1'b0; // Clear the valid signal if the tx_sb_msg_valid is not active.
            end
        end
    end

    // Pulse Generator module for the signal: "rx_sb_msg_valid".
    // Note we have to receive just a pulse of "rx_sb_msg_valid" for a 1 lclk cycle. (We use lclk here).
    always @(posedge lclk or negedge rst_n) begin
        if(!rst_n) begin
            // Reset the SB RX signals.
            rx_sb_msg_valid <= 1'b0;
        end
        else begin
            if(rx_sb_msg_valid_reg[1] && !rx_sb_msg_valid_reg[0]) begin
                rx_sb_msg_valid <= 1'b1; // Set the valid signal to 1 for one cycle.
            end
            else begin
                rx_sb_msg_valid <= 1'b0; // Clear the valid signal after one cycle.
            end
        end
    end


    
    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------                 (Reset Task:)                ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task reset();
        rst_n                    = 0;
        rx_pt_trigger            = 0;
        timeout_8ms              = 0;
        mb_tx_pattern_count_done = 0;
        mb_rx_perlane_err        = 0;
        mb_rx_val_err            = 0;
        mb_rx_clk_err            = 0;
        mb_rx_compare_done       = 0;
        d2c_clk_sampling         = 0;
        d2c_lfsr_en              = 0;
        d2c_pattern_setup        = 0;
        d2c_data_pattern_sel     = 0;
        d2c_val_pattern_sel      = 0;
        d2c_pattern_mode         = 0;
        d2c_burst_count          = 0;
        d2c_idle_count           = 0;
        d2c_iter_count           = 0;
        d2c_compare_setup        = 0;
        rx_sb_msg_valid          = 0;
        rx_sb_msg                = 0;
        cfg_train4_max_err_thresh_perlane = 0;
        cfg_train4_max_err_thresh_aggr    = 0;
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
        input reg [1:0]  task_compare_setup   , // Set the comparison setup to Per-Lane for this test scenario.
        input reg [15:0] task_aggr_err_thresh , // Set the aggregate error threshold from RF for this test scenario.
        input reg [15:0] task_perlane_err_thresh // Set the per-lane error threshold from RF for this test scenario.
    );
        // Clock sampling/PI phase control:
        d2c_clk_sampling     = task_clk_sampling    ; // Set the clock sampling/PI phase control state for this test scenario.
        
        // Tx Pattern Generator Setup:
        d2c_pattern_setup    = task_pattern_setup   ; // Set the pattern setup for this test scenario.
        d2c_data_pattern_sel = task_data_pattern_sel; // Set the data pattern selection for this test scenario.
        d2c_val_pattern_sel  = task_val_pattern_sel ; // Set the valid pattern selection for this test scenario.
        d2c_lfsr_en          = task_lfsr_en         ;
        
        // Tx Pattern Mode Setup:
        d2c_pattern_mode     = task_pattern_mode    ;
        d2c_burst_count      = task_burst_count     ;
        d2c_idle_count       = task_idle_count      ;
        d2c_iter_count       = task_iter_count      ;

        // Receiver Comparison Setup:
        d2c_compare_setup    = task_compare_setup                  ; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
        cfg_train4_max_err_thresh_aggr    = task_aggr_err_thresh   ; // Set the aggregate error threshold from RF for this test scenario.
        cfg_train4_max_err_thresh_perlane = task_perlane_err_thresh; // Set the per-lane error threshold from RF for this test scenario.
        
    endtask


    
    //  /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    // |  -------------------------               ( Start Test Task)             ---------------------------  |
    //  \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    task start_test(input integer abort_mb_or_sb_after = TIMEOUT_CYCLES); // The input argument is used to determine whether the testbench should simulate the timeout condition caused by MB or SB by waiting for some time before setting mb_tx_pattern_count_done to 1 or before sending the expected SB response, respectively.
        reg [11:0] entered_states;
        entered_states = 0;

        fork : test_execution
            begin
                counter_8ms_en = 1; // Enable the 8ms timeout counter at the start of the test.
                rx_pt_trigger  = 1; // Trigger the Rx D2C Pattern Test.
                #(LCLK_PERIOD);     // Wait for one clock cycle after triggering the test.
                rx_pt_trigger  = 0; // Clear the trigger after one cycle.

                wait(test_d2c_done || d2c_timeout_or_error); // Wait until the test is done or a timeout/error occurs.
                @(posedge lclk); // To keep the $monitor system function (that is used in the main initial block) print the final state of the FSM first, before the next $display content. 
                if(d2c_timeout_or_error == 1) begin
                    $display("%8t ps: The test passed but is directed to TO_TRAINERROR due to timeout.", $realtime());
                end
                else if(d2c_timeout_or_error == 0) begin
                    repeat(1) @(posedge lclk); // To keep the $monitor system function print the IDLE state of the FSM, to prove that the FSM go back to the start point. 
                    #1; // To make sure that the $monitor function has printed its sentence.
                    $display("%8t ps: The test passed successfully.", $realtime());
                end
                $display("=========   =========   =========   =========   =========   =========");
                counter_8ms_en = 0; // Disable the 8ms timeout counter at the end of the test.
                disable test_execution; // Disable the fork to end the test execution.
            end

            begin
                // Wait some lclk cycles = "abort_mb_or_sb_after" to simulate the timeout condition caused by MB or SB, then set the "d2c_timeout_or_error" signal to 1 to indicate that a timeout or error has occurred during the test.
                for (int i=0; i<abort_mb_or_sb_after ; i++) begin
                    @(posedge lclk);
                    wait_timeout = 0;
                end
                wait_timeout = 1; // Set the timeout_or_error signal to 1 after waiting for some time to simulate the timeout condition caused by MB or SB.
            end

            begin : check_fsm_transitions
                wait(current_state == RX_PT_IDLE); // Wait for the FSM to be in the IDLE state before starting the test.
                    entered_states[1] = 1; // Mark that we have entered the IDLE
                wait(current_state == RX_PT_START_REQ); // Wait for the FSM to transition to the START_REQ state.
                    entered_states[0] = 1; // Mark that we have entered the START_REQ state.
                wait(current_state == RX_PT_START_RESP); // Wait for the FSM to transition to the START_RESP state.
                    entered_states[2] = 1; // Mark that we have entered the START_RESP state.
                wait(current_state == RX_PT_CLR_ERR_REQ); // Wait for the FSM to transition to the CLR_ERR_REQ state.
                    entered_states[3] = 1; // Mark that we have entered the CLR_ERR_REQ state.
                wait(current_state == RX_PT_CLR_ERR_RESP); // Wait for the FSM to transition to the CLR_ERR_RESP state.
                    entered_states[4] = 1; // Mark that we have entered the CLR_ERR_RESP state.
                wait(current_state == RX_PT_PATTERN_GEN); // Wait for the FSM to transition to the PATTERN_GEN state.
                    entered_states[5] = 1; // Mark that we have entered the PATTERN_GEN state. 
                wait(current_state == RX_PT_COUNT_DONE_REQ); // Wait for the FSM to transition to the COUNT_DONE_REQ state.
                    entered_states[6] = 1; // Mark that we have entered the COUNT_DONE_REQ state.
                wait(current_state == RX_PT_COUNT_DONE_RESP); // Wait for the FSM to transition to the COUNT_DONE_RESP state.
                    entered_states[7] = 1; // Mark that we have entered the COUNT_DONE_RESP state.
                wait(current_state == RX_PT_END_REQ); // Wait for the FSM to transition to the END_REQ state.
                    entered_states[8] = 1; // Mark that we have entered the END_REQ state.
                wait(current_state == RX_PT_END_RESP); // Wait for the FSM to transition to the END_RESP state.
                    entered_states[9] = 1; // Mark that we have entered the END_RESP state.
                wait(current_state == RX_PT_DONE); // Wait for the FSM to transition to the DONE state.
                    entered_states[10] = 1; // Mark that we have entered the DONE state.   
                wait(current_state == RX_PT_IDLE); // Wait for the FSM to transition to the TO_TRAINERROR state if a timeout or error occurs.
                    entered_states[11] = 1; // Mark that we have entered the TO_TRAINERROR state.
            end
        join

        wait_timeout = 0; // Clear the timeout_or_error signal after the test is done.

        if(entered_states == 12'b111111111111) begin
            $display("%8t ps: The FSM entered all the expected states in the correct order.\n", $realtime());
        end
        else if (d2c_timeout_or_error == 1'b1) begin
            $display("%8t ps: The FSM entered the \"TO_TRAINERROR\" state as expected correctly.\n", $realtime());
        end else begin
            $display("%8t ps: The FSM did not enter all the expected states in the correct order. <================================= [Error]\n", $realtime());
            $stop;
        end
    endtask



    // \\\\\\\\\\\\\\\\\\\\\                                                                  ////////////////////////
    //    \\\\\\\\\\\\\\\\\\\\\\                                                          ////////////////////////
    //     /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    //    |  -------------------------          (Test Bench Main Actions:)          ---------------------------  |
    //     \______________________/‾‾‾‾‾\________________________________________/‾‾‾‾‾\________________________/
    //    //////////////////////                                                          \\\\\\\\\\\\\\\\\\\\\\\\
    // /////////////////////                                                                  \\\\\\\\\\\\\\\\\\\\\\\\ 

    initial begin
        // Reset the system.
        reset();

        // Monitor the current state of the RX_D2C_PT instance for debugging purposes.
        $monitor("%8t ps : The Currernt state:     (\"%s\")", $realtime(), current_state.name());


        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the VALVREF test scenario.            //  
        /////////////////////////////////////////////////////////////////////////
        $display("=========>  Start (VALVREF) Test Scenario:  <=========");

        set_d2c_configuration (
            // Clock sampling/PI phase control:
            .task_clk_sampling   (2'b0), // Set the clock sampling/PI phase control state to "0: "Eye Center"", "1: "Left edge"", or "2: "Right edge"" for this test scenario.
            
            // Tx Pattern Generator Setup:
            .task_pattern_setup   (1     ), // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            .task_data_pattern_sel(2'b11 ), // Data pattern used during training: (0: LFSR; 1: ID; 3: All 0)
            .task_val_pattern_sel (3'b000), // 0: VALTRAIN pattern, 1: Valid lane is Held low, 2: Operational Valid.
            .task_lfsr_en         (0     ), // 1: Enable the LFSR, 0: Disable the LFSR for both Rx and Tx.
            
            // Tx Pattern Mode Setup:
            .task_pattern_mode(1'b0), // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
            .task_burst_count (128 ), // Burst Count: Indicates the duration of selected pattern (UI count).
            .task_idle_count  (4'h0), // IDLE Count: Indicates the duration of low following the burst (UI count).
            .task_iter_count  (4'h1), // Iterations: Indicates the iteration count of bursts followed by idle.

            // Receiver Comparison Setup:
            .task_compare_setup     (2'b00   ), // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
            .task_aggr_err_thresh   (16'h0000), // Set the aggregate error threshold from RF for this test scenario.
            .task_perlane_err_thresh(16'h0000)  // Set the per-lane error threshold from RF for this test scenario.
        );

        assume_errors (
            .task_aggr_err     (16'h0000), // The aggregate error to be assumed for the test scenario.
            .task_perlane_err  (16'h0000), // The per-lane error to be assumed for the test scenario.
            .task_val_err      (1'b0    ), // The valid lane error to be assumed for the test scenario.
            .task_clk_err      (1'b0    )  // The clock lane error to be assumed for the test scenario.
        );
        start_test();


        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the DATAVREF test scenario.           //  
        /////////////////////////////////////////////////////////////////////////
        $display("=========>  Start (DATAVREF) Test Scenario:  <=========");

        set_d2c_configuration (
            // Clock sampling/PI phase control:
            .task_clk_sampling   (2'b0), // Set the clock sampling/PI phase control state to "0: "Eye Center"", "1: "Left edge"", or "2: "Right edge"" for this test scenario.
            
            // Tx Pattern Generator Setup:
            .task_pattern_setup   (3'b011), // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            .task_data_pattern_sel(2'b00 ), // Data pattern used during training: (0: LFSR; 1: ID; 3: All 0)
            .task_val_pattern_sel (3'b10 ), // 0: VALTRAIN pattern, 1: Valid lane is Held low, 2: Operational Valid (Valid Framing).
            .task_lfsr_en         (1     ), // 1: Enable the LFSR, 0: Disable the LFSR for both Rx and Tx.
            
            // Tx Pattern Mode Setup:
            .task_pattern_mode(1'b0), // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
            .task_burst_count (4096), // Burst Count: Indicates the duration of selected pattern (UI count).
            .task_idle_count  (4'h0), // IDLE Count: Indicates the duration of low following the burst (UI count).
            .task_iter_count  (4'h1), // Iterations: Indicates the iteration count of bursts followed by idle.

            // Receiver Comparison Setup:
            .task_compare_setup     (2'b00   ), // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
            .task_aggr_err_thresh   (16'h0000), // Set the aggregate error threshold from RF for this test scenario.
            .task_perlane_err_thresh(16'h0000)  // Set the per-lane error threshold from RF for this test scenario.
        );

        assume_errors (
            .task_aggr_err     (16'h0000), // The aggregate error to be assumed for the test scenario.
            .task_perlane_err  (16'h0000), // The per-lane error to be assumed for the test scenario.
            .task_val_err      (1'b0    ), // The valid lane error to be assumed for the test scenario.
            .task_clk_err      (1'b0    )  // The clock lane error to be assumed for the test scenario.
        );

        start_test();



        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the VALVREF test scenario.            //  
        /////////////////////////////////////////////////////////////////////////
        $display("=========>  Start (timeout 8ms) Test Scenario:  <=========");

        // Start the test with the previous configurations.
        start_test(.abort_mb_or_sb_after(600)); // We can use the same configuration as the previous test scenario, as we are just testing the timeout condition here.
        


        /////////////////////////////////////////////////////////////////////////
        // Set the D2C configuration for the VALVREF test scenario.            //  
        /////////////////////////////////////////////////////////////////////////
        $display("=========>  Start (timeout 8ms) Test Scenario again:  <=========");

        // Start the test with the previous configurations.
        reset();
        start_test(.abort_mb_or_sb_after(400)); // We can use the same configuration as the previous test scenario, as we are just testing the timeout condition here.
        

        @(posedge lclk); // Just wait for some time to let the test scenario run and observe the behavior.
        $stop;
    end
endmodule

