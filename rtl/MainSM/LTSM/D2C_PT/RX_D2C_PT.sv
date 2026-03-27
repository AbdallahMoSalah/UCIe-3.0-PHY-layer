
module RX_D2C_PT  #() (
    // LTSM signals.
    input wire lclk,
    input wire rst_n,
    input wire rx_pt_trigger,
    input wire timeout_8ms,
    output reg test_d2c_done,


    
    //=====================================//
    // Control Signals To MB:              //
    //=====================================//
    
    //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
    // Clock Sampling Details Group:
    output reg         mb_tx_clk_sampling_en, // Enable changing Clock sampling/PI phase control state.
    output reg  [1:0]  mb_tx_clk_sampling, // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
    
    // Tx Pattern Generator Setup Group:
    output reg         mb_tx_pattern_en,       // 1: Send pattern immediately, 0: Don't send pattern.
    output reg  [2:0]  mb_tx_pattern_setup,    // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    output reg  [1:0]  mb_tx_data_pattern_sel, // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
    output reg  [1:0]  mb_tx_val_pattern_sel,  // 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
    output reg         mb_tx_lfsr_en,          // 1: Enable the Tx LFSR, 0: Disable the Tx LFSR.
    output reg         mb_tx_lfsr_rst,         // 1: Reset the Tx LFSR, 0: Keep the Tx LFSR ready.
    output reg         mb_rx_lfsr_en,          // 1: Enable the Rx LFSR, 0: Disable the Rx LFSR.
    output reg         mb_rx_lfsr_rst,         // 1: Reset the Rx LFSR, 0: Keep the Rx LFSR ready.
    
    // Tx Pattern Mode Setup Group:
    output reg         mb_tx_pattern_mode,       // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
    output reg  [15:0] mb_tx_burst_count,        // Burst Count: Indicates the duration of selected pattern (UI count).
    output reg  [3:0]  mb_tx_idle_count,         // IDLE Count: Indicates the duration of low following the burst (UI count).
    output reg  [3:0]  mb_tx_iter_count,         // Iterations: Indicates the iteration count of bursts followed by idle.
    input  wire        mb_tx_pattern_count_done, // Asserted (=1) once MB completes the iter_count.
    
    // Receiver Comparison Setup & Errors
    output reg         mb_rx_compare_en,             // 1: Enable the Rx comparison circuit, 0: Disable.
    output reg  [15:0] mb_rx_max_err_thresh_aggr,    // Max error Threshold in aggregate comparison.
    output reg  [11:0] mb_rx_max_err_thresh_perlane, // Max error Threshold in per Lane comparison.
    output reg  [1:0]  mb_rx_compare_setup,          // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.
    input  wire [15:0] mb_rx_aggr_err,               // The total calculated Aggregate Errors on Rx.
    input  wire [15:0] mb_rx_perlane_err,            // The Per-Lane Errors (Each bit represents one fail Data Lane).
    input  wire        mb_rx_val_err,                // The error coming from Valid Lane receiver in MB.
    input  wire        mb_rx_clk_err,                // The error coming from Clock Lane receiver in MB.
    input  wire        mb_rx_compare_done,           // From MB to LTSM to tell that comparison of burst_count is done.
    
    //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
    // Lane Selection
    output reg  [1:0]   mb_tx_clk_lane_sel,  // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
    output reg  [1:0]   mb_tx_data_lane_sel, // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
    output reg  [1:0]   mb_tx_val_lane_sel,  // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
    output reg  [1:0]   mb_tx_trk_lane_sel,  // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
    output reg          mb_rx_clk_lane_sel,  // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
    output reg          mb_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
    output reg          mb_rx_val_lane_sel,  // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
    output reg          mb_rx_trk_lane_sel,  // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).
     
    // PHY Level Control & Analog Interface
    // output reg  [1:0]  phy_tx_clk_lane_sel,  // 0b: Held Low, 1b: Active (Tx Physical Clock Lane).
    // output reg  [1:0]  phy_tx_data_lane_sel, // 0b: Held Low, 1b: Active (Tx Physical Data Lanes).
    // output reg  [1:0]  phy_tx_val_lane_sel,  // 0b: Held Low, 1b: Active (Tx Physical Valid Lane).
    // output reg  [1:0]  phy_tx_trk_lane_sel,  // 0b: Held Low, 1b: Active (Tx Physical Track Lane).
    // output reg         phy_rx_clk_lane_sel,  // 0b: Disabled, 1b: Enabled (Rx Physical Clock Lane).
    // output reg         phy_rx_data_lane_sel, // 0b: Disabled, 1b: Enabled (Rx Physical Data Lanes).
    // output reg         phy_rx_val_lane_sel,  // 0b: Disabled, 1b: Enabled (Rx Physical Valid Lane).
    // output reg         phy_rx_trk_lane_sel,  // 0b: Disabled, 1b: Enabled (Rx Physical Track Lane).
    

    
    //=====================================//
    // Control Signals From Sub-states:    //
    //=====================================//
    input wire  [1:0]  d2c_clk_sampling, // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
    output reg         d2c_timeout_or_error, // Tell the external Sub-state if timeout or error occurs during the test to move to TRAINERROR state.
    
    //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
    // Received Tx Pattern Generator Setup Group:
    input wire         d2c_lfsr_en,       // 1: Enable the Tx & Rx LFSR, 0: Disable the Tx & Rx LFSR.
    input wire  [2:0]  d2c_pattern_setup,    // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    input wire  [1:0]  d2c_data_pattern_sel, // Data pattern used during training: LFSR, ID, or all 0.
    input wire  [1:0]  d2c_val_pattern_sel,  // 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
    
    // Received Tx Pattern Mode Setup Group:
    input wire         d2c_pattern_mode, // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
    input wire  [15:0] d2c_burst_count,  // Burst Count: Indicates the duration of selected pattern (UI count).
    input wire  [3:0]  d2c_idle_count,   // IDLE Count: Indicates the duration of low following the burst (UI count).
    input wire  [3:0]  d2c_iter_count,   // Iteration Count: Indicates the iteration count of bursts followed by idle.
    
    // Received Receiver Comparison Setup & Errors
    input wire  [1:0]  d2c_compare_setup,          // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
    output reg  [15:0] d2c_aggr_err,               // The total calculated Aggregate Errors on Rx.
    output reg  [15:0] d2c_perlane_err,            // The Per-Lane Errors (Each bit represents one fail Data Lane).
    output reg         d2c_val_err,                // The error coming from Valid Lane receiver in MB.
    output reg         d2c_clk_err,                // The error coming from Clock Lane receiver in MB.
    

    //=====================================//
    // Sideband Control Signals:           //
    //=====================================//
    // For SB TX:
    output reg         tx_sb_msg_valid, // Tell the SB that the selected message is valid.
    output reg  [7:0]  tx_sb_msg,       // Tell the Sideband the message that it should to send. 
    output reg  [15:0] tx_msginfo,      // MsgInfo field of the SB message. 
    output reg  [63:0] tx_data_field,   // Data field of the SB message.
    
    // For SB RX:
    input wire         rx_sb_msg_valid, // Indicates that the sideband message is valid.  This msg is an output of PULSE_GEN module to set it high for 1 lclk cycle.
    input wire  [7:0]  rx_sb_msg,       // Get the Received SB msg.
    // input wire  [15:0] rx_msginfo,      // MsgInfo field of the SB message received.
    // input wire  [63:0] rx_data_field,   // Data field of the SB message.
    

    //=====================================//
    // Register File (RF) Control Signals: //
    //=====================================//
        
    // Training Setup 4 (Offset 1050h)
    // Note: 'Repair Lane mask' (Bits 3:0) is omitted as it only applies to Advanced Package.
    input  wire [11:0]  cfg_train4_max_err_thresh_perlane, // Max error Threshold in per-Lane comparison for error counting.
    input  wire [15:0]  cfg_train4_max_err_thresh_aggr    // Max error Threshold in aggregate comparison for error counting.

    
);
    
    // Sideband message Values:
    localparam MSG_START_REQ       = 8'hA0, // From LTSM to SB to request the start of Rx D2C Pattern Test.
               MSG_START_RESP      = 8'hA1, // From SB to LTSM to acknowledge the start of Rx D2C Pattern Test.
               MSG_CLR_ERR_REQ     = 8'hA2, // From LTSM to SB to request clearing of errors in MB before starting pattern generation.
               MSG_CLR_ERR_RESP    = 8'hA3, // From SB to LTSM to acknowledge the clearing of errors in MB.
               MSG_COUNT_DONE_REQ  = 8'hA5, // From LTSM to SB to ask if the pattern generation and error counting is done based on burst_count and iter_count.
               MSG_COUNT_DONE_RESP = 8'hA6, // From SB to LTSM to acknowledge that the pattern generation and error counting is done.
               MSG_END_REQ         = 8'hA7, // From LTSM to SB to request SB to end the pattern test and send results.
               MSG_END_RESP        = 8'hA8, // From SB to LTSM to acknowledge the end of the pattern test and sending of results.
               MSG_TRAINERROR_REQ  = 8'hFF; // From SB to LTSM to indicate that a TRAINERROR condition has occurred on the partner side (e.g., due to timeout or other errors during training).


    // States names
    localparam RX_PT_IDLE            = 4'h0, // (S0)
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
               TO_TRAINERROR         = 4'hB; // (S11)

    reg [3:0] current_state, next_state, previous_state; // The Current, Next states, and Previous state of the FSM.
    wire data_incoherence;
    
    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    assign data_incoherence = (current_state != previous_state) ? 1'b1 : 1'b0; 
    
    
    // Log Rx Comparison Results from MB:
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            d2c_perlane_err <= 16'b0;
            d2c_val_err     <= 1'b0;
            d2c_clk_err     <= 1'b0;
        end else if(mb_rx_compare_done) begin
            d2c_aggr_err    <= mb_rx_aggr_err;   // The total calculated Aggregate Errors on Rx.
            d2c_perlane_err <= mb_rx_perlane_err; // The Per-Lane Errors (Each bit represents one fail Data Lane).
            d2c_val_err     <= mb_rx_val_err;     // The error coming from Valid Lane receiver in MB.
            d2c_clk_err     <= mb_rx_clk_err;     // The error coming from Clock Lane receiver in MB.
        end
    end
  
    

    // Current State Logic of the FSM:
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            current_state  <= RX_PT_IDLE;
            previous_state <= RX_PT_IDLE;
        end else begin
            current_state <= next_state;
            previous_state <= current_state; // We use signal to avoid data incoherence when sending SB messages. It is set to 1 for 1 lclk cycle whenever the state changes, which is when the SB Msg data is updated with new values.
        end
    end

    // Next State Logic of the FSM:
    always @(*) begin
        if(timeout_8ms | (rx_sb_msg == MSG_TRAINERROR_REQ && rx_sb_msg_valid == 1'b1)) begin
            // (S11)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start the Rx D2C Pattern Test.
                RX_PT_IDLE: begin
                    if (rx_pt_trigger) next_state = RX_PT_START_REQ;
                    else next_state = RX_PT_IDLE;
                end
                // (S1) Send & Receive SB Message: {Start Rx Init D to C point test req}
                RX_PT_START_REQ: begin
                    if (rx_sb_msg == MSG_START_REQ && rx_sb_msg_valid == 1'b1) next_state = RX_PT_START_RESP;
                    else next_state = RX_PT_START_REQ;
                end
                // (S2) Send & Receive SB Message: {Start Rx Init D to C point test resp}.
                RX_PT_START_RESP: begin
                    if (rx_sb_msg == MSG_START_RESP && rx_sb_msg_valid == 1'b1) next_state = RX_PT_CLR_ERR_REQ;
                    else next_state = RX_PT_START_RESP;
                end
                // (S3) Send & Receive SB Message: {LFSR clear error req}.
                RX_PT_CLR_ERR_REQ: begin
                    if (rx_sb_msg == MSG_CLR_ERR_REQ && rx_sb_msg_valid == 1'b1) next_state = RX_PT_CLR_ERR_RESP;
                    else next_state = RX_PT_CLR_ERR_REQ;
                end
                // (S4) Send & Receive SB Message: {LFSR clear error resp}.
                RX_PT_CLR_ERR_RESP: begin
                    if (rx_sb_msg == MSG_CLR_ERR_RESP && rx_sb_msg_valid == 1'b1) next_state = RX_PT_PATTERN_GEN;
                    else next_state = RX_PT_CLR_ERR_RESP;
                end
                // (S5) Send & Receive MB Pattern
                RX_PT_PATTERN_GEN: begin
                    if (mb_tx_pattern_count_done) next_state = RX_PT_COUNT_DONE_REQ;
                    else next_state = RX_PT_PATTERN_GEN;
                end
                // (S6) Send & Receive SB Message {Rx Init D to C Tx count done req}.
                RX_PT_COUNT_DONE_REQ: begin
                    if (rx_sb_msg == MSG_COUNT_DONE_REQ && rx_sb_msg_valid == 1'b1) next_state = RX_PT_COUNT_DONE_RESP;
                    else next_state = RX_PT_COUNT_DONE_REQ;
                end
                // (S7) Send & Receive SB Message: {Rx Init D to C Tx count done resp}.
                RX_PT_COUNT_DONE_RESP: begin
                    if (rx_sb_msg == MSG_COUNT_DONE_RESP && rx_sb_msg_valid == 1'b1) next_state = RX_PT_END_REQ;
                    else next_state = RX_PT_COUNT_DONE_RESP;
                end
                // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
                RX_PT_END_REQ: begin
                    if (rx_sb_msg == MSG_END_REQ && rx_sb_msg_valid == 1'b1) next_state = RX_PT_END_RESP;
                    else next_state = RX_PT_END_REQ;
                end
                // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
                RX_PT_END_RESP: begin
                    if (rx_sb_msg == MSG_END_RESP && rx_sb_msg_valid == 1'b1) next_state = RX_PT_DONE;
                    else next_state = RX_PT_END_RESP;
                end
                // (S10)
                RX_PT_DONE: begin
                    next_state = RX_PT_IDLE; // Stay here for 1 lclk cycle.
                end
                // // (S11) TRAINERROR state:
                // TO_TRAINERROR: begin
                //     next_state = TO_TRAINERROR; // Stay in TRAINERROR state until reset.
                // end
                default: begin
                    next_state = TO_TRAINERROR; // Default case to avoid latches in synthesis.
                end
            endcase
        end

    end

    // Output logic based on current state
    always @(*) begin
        //=======================================================//
        //     Default values for outputs (to avoid latches)     //
        //=======================================================//
        // Default values for outputs (to avoid latches)
        test_d2c_done = 0;
        // I ordered the next signals as decribed in data field of the SB msg: {Start Rx Init D to C point test req}
        mb_rx_max_err_thresh_perlane = cfg_train4_max_err_thresh_perlane;  // Max error Threshold in per-Lane comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
        mb_rx_max_err_thresh_aggr    = cfg_train4_max_err_thresh_aggr   ;  // Max error Threshold in aggregate comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF. 
        mb_rx_compare_setup          = d2c_compare_setup                ;  // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
        mb_tx_iter_count             = d2c_iter_count                   ;  // Iteration Count: Indicates the iteration count of bursts followed by idle.
        mb_tx_idle_count             = d2c_idle_count                   ;  // IDLE Count: Indicates the duration of low following the burst (UI count).
        mb_tx_burst_count            = d2c_burst_count                  ;  // Burst Count: Indicates the duration of selected pattern (UI count).
        mb_tx_pattern_mode           = d2c_pattern_mode                 ;  // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        mb_tx_clk_sampling           = d2c_clk_sampling                 ;  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
        mb_tx_val_pattern_sel        = d2c_val_pattern_sel              ;  // 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
        mb_tx_data_pattern_sel       = d2c_data_pattern_sel             ;  // Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.

        
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling Details Group:
        mb_tx_clk_sampling_en = 0; // Enable changing Clock sampling/PI phase control state.
        d2c_timeout_or_error  = 0; // It will be set to 1 if timeout or error occurs during the test to move to TRAINERROR state.

        // Tx Pattern Generator Setup Group:
        mb_tx_pattern_setup    = d2c_pattern_setup;    // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        mb_tx_pattern_en       = 0;                    // 0: Don't send pattern.
        mb_tx_lfsr_en          = 0;                    // 0: Disable the Tx LFSR.
        mb_tx_lfsr_rst         = 0;                    // 0: Don't Reset the Tx LFSR.
        mb_rx_lfsr_en          = 0;                    // 0: Disable the Rx LFSR.
        mb_rx_lfsr_rst         = 0;                    // 0: Don't Reset the Rx LFSR.

        // Receiver Comparison Setup & Errors
        mb_rx_compare_en = 0;                 // 0: Disable the MB compare circuits.
    
        
        //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
        // Lane Selection & Shapes
        mb_tx_clk_lane_sel  = 2'b00; // 00b: Low (Tx Logical Clock Lane).
        mb_tx_data_lane_sel = 2'b00; // 00b: Low (Tx Logical Data Lanes).
        mb_tx_val_lane_sel  = 2'b00; // 00b: Low (Tx Logical Valid Lane).
        mb_tx_trk_lane_sel  = 2'b00; // 00b: Low (Tx Logical Track Lane).
        mb_rx_clk_lane_sel  = 1'b1 ; // 1b: Enabled  (Rx Logical Clock Lane).
        mb_rx_data_lane_sel = 1'b1 ; // 1b: Enabled  (Rx Logical Data Lanes).
        mb_rx_val_lane_sel  = 1'b1 ; // 1b: Enabled  (Rx Logical Valid Lane).
        mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled (Rx Logical Track Lane).
    
        
        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // For SB TX:
        tx_sb_msg_valid =  1'b0; // Tell the SB that the selected message is valid.
        tx_sb_msg       =  8'b0; // Tell the Sideband the message that it should to send. 
        tx_msginfo      = 16'b0; // MsgInfo field of the SB message. 
        tx_data_field   = 64'b0; // Data field of the SB message.

        
        case (current_state)
            // (S0) IDLE state.
            RX_PT_IDLE: begin
                // Use the above default values for outputs.
            end
            // (S1) Send & Receive SB Message: {Start Rx Init D to C point test req}
            RX_PT_START_REQ: begin
                // For Req MSG sent: (We send these information for inform perpose only).
                tx_sb_msg_valid      = (~data_incoherence); // Assert valid only when data incoherence flag is cleared, to avoid sending incorrect messages.
                tx_sb_msg            = MSG_START_REQ;
                tx_msginfo           = (d2c_compare_setup == 1)? {4'b0, cfg_train4_max_err_thresh_aggr} :    // Send aggregate comparison mode,
                                       (d2c_compare_setup == 0)? cfg_train4_max_err_thresh_perlane      : 0; // Send Per-lane comparison mode, otherwise 0.
                tx_data_field[63:60] = 4'b0;                     // Reserved for future use. Just set it to 0 for now.
                tx_data_field[59]    = (d2c_compare_setup != 0); // Comparison Mode (0: Per Lane; 1: Aggregate)
                tx_data_field[58:43] = d2c_iter_count          ; // Iteration Count Setting.
                tx_data_field[42:27] = d2c_idle_count          ; // Idle Count Setting.
                tx_data_field[26:11] = d2c_burst_count         ; // Burst Count Setting.
                tx_data_field[10]    = d2c_pattern_mode        ; // Pattern Mode (0: continuous mode, 1: Burst Mode).
                tx_data_field[9:6]   = d2c_clk_sampling        ; // Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
                tx_data_field[5:3]   = d2c_val_pattern_sel     ; // Valid Pattern (0h: Functional pattern).
                tx_data_field[2:0]   = d2c_data_pattern_sel    ; // Data pattern (0h: LFSR, 1h: Per Lane ID).

                // Configure the MB depending on the content of the received SB msg: {Start Rx Init D to C point test req}
                mb_rx_max_err_thresh_perlane = cfg_train4_max_err_thresh_perlane;  // Max error Threshold in per-Lane comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
                mb_rx_max_err_thresh_aggr    = cfg_train4_max_err_thresh_aggr   ;  // Max error Threshold in aggregate comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF. 
                mb_rx_compare_setup          = d2c_compare_setup                ;  // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
                mb_tx_iter_count             = d2c_iter_count                   ;  // Iteration Count: Indicates the iteration count of bursts followed by idle.
                mb_tx_idle_count             = d2c_idle_count                   ;  // IDLE Count: Indicates the duration of low following the burst (UI count).
                mb_tx_burst_count            = d2c_burst_count                  ;  // Burst Count: Indicates the duration of selected pattern (UI count).
                mb_tx_pattern_mode           = d2c_pattern_mode                 ;  // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                mb_tx_clk_sampling           = d2c_clk_sampling                 ;  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
                mb_tx_val_pattern_sel        = d2c_val_pattern_sel              ;  // 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
                mb_tx_data_pattern_sel       = d2c_data_pattern_sel             ;  // Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.
                mb_tx_pattern_setup          = d2c_pattern_setup                ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            end
            // (S2) Send & Receive SB Message: {Start Rx Init D to C point test resp}.
            RX_PT_START_RESP: begin
                // For Resp MSG sent: (We send these information for inform perpose only).
                tx_sb_msg_valid     = (~data_incoherence); // Assert valid only when data incoherence flag is cleared, to avoid sending incorrect messages.
                tx_sb_msg           = MSG_START_RESP;
                tx_msginfo          = 16'b0;
                tx_data_field[63:0] = 64'b0; // Reserved.
                
                // Configure the MB to be ready for the pattern generation:
                mb_tx_clk_sampling_en = 1; // Enable changing Clock sampling/PI phase control state.
                mb_rx_compare_en      = 1; // Enable the MB compare circuits to start comparing the received pattern with the expected pattern and count errors.    
            end
            // (S3) Send & Receive SB Message: {LFSR clear error req}.
            RX_PT_CLR_ERR_REQ: begin
                tx_sb_msg_valid     = (~data_incoherence);
                tx_sb_msg           = MSG_CLR_ERR_REQ;
                tx_msginfo          = 16'b0;
                tx_data_field[63:0] = 64'b0; // No payload.

                // Configure the MB to be ready for the pattern generation:
                mb_rx_compare_en    = 1;
                mb_tx_lfsr_en       = d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mb_tx_lfsr_rst      = 1; // Reset the Tx LFSR to clear the previous errors.
            end
            // (S4) Send & Receive SB Message: {LFSR clear error resp}.
            RX_PT_CLR_ERR_RESP: begin
                tx_sb_msg_valid     = (~data_incoherence);
                tx_sb_msg           = MSG_CLR_ERR_RESP;
                tx_msginfo          = 16'b0;
                tx_data_field[63:0] = 64'b0; // No payload.

                // Configure the MB to be ready for the pattern generation:
                mb_rx_compare_en    = 1;
                mb_tx_lfsr_en       = d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mb_rx_lfsr_en       = d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.
                mb_rx_lfsr_rst      = 1;           // Reset the Rx LFSR to clear the previous errors.
            end
            // (S5) Send & Receive MB Pattern
            RX_PT_PATTERN_GEN: begin
                mb_tx_pattern_en    = 1; // <====== 1: Send pattern immediately, 0: Don't send pattern.

                // For SB Msg:
                tx_sb_msg_valid     = 0;

                // For Comparison:
                mb_rx_compare_en    = 1;
                mb_tx_lfsr_en       = d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mb_rx_lfsr_en       = d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.

                // Logical Lane Selection:
                mb_tx_clk_lane_sel  = 2'b01;                  // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
                mb_tx_data_lane_sel = (d2c_pattern_setup[0]); // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
                mb_tx_val_lane_sel  = (d2c_pattern_setup[1]); // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
                mb_tx_trk_lane_sel  = 2'b00;                  // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).

            end
            // (S6) Send & Receive SB Message {Rx Init D to C Tx count done req}.
            RX_PT_COUNT_DONE_REQ: begin
                tx_sb_msg_valid     = (~data_incoherence);
                tx_sb_msg           = MSG_COUNT_DONE_REQ;
                tx_msginfo          = 16'b0;
                tx_data_field[63:0] = 64'b0; // No payload.

                mb_tx_pattern_en = 0; // <====== 1: Send pattern immediately, 0: Don't send pattern.
                mb_rx_compare_en = 1;
                mb_tx_lfsr_en    = 0;           // disable the Tx LFSR.
                mb_rx_lfsr_en    = d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.
            end
            // (S7) Send & Receive SB Message: {Rx Init D to C Tx count done resp}.
            RX_PT_COUNT_DONE_RESP: begin
                tx_sb_msg_valid     = (~data_incoherence);
                tx_sb_msg           = MSG_COUNT_DONE_RESP;
                tx_msginfo          = 16'b0;
                tx_data_field[63:0] = 64'b0; // No payload.


                mb_tx_pattern_en    = 0;
                mb_rx_compare_en    = 0; 
                mb_tx_lfsr_en       = 0; // disable the Tx LFSR.
                mb_rx_lfsr_en       = 0; // disable the Rx LFSR.
            end
            // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
            RX_PT_END_REQ: begin
                tx_sb_msg_valid     = (~data_incoherence);
                tx_sb_msg           = MSG_END_REQ;
                tx_msginfo          = 16'b0;
                tx_data_field[63:0] = 64'b0; // No payload.
            end
            // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
            RX_PT_END_RESP: begin
                tx_sb_msg_valid     = (~data_incoherence);
                tx_sb_msg           = MSG_END_RESP;
                tx_msginfo          = 16'b0;
                tx_data_field[63:0] = 64'b0; // No payload.
            end
            // (S10)
            RX_PT_DONE: begin
                tx_sb_msg_valid     = 0;
                tx_sb_msg           = MSG_END_RESP;
                tx_msginfo          = 16'b0;
                tx_data_field[63:0] = 64'b0; // No payload.
                test_d2c_done       = 1; // Assert the test done signal to tell the external Sub-state the completion of the test.
            end
            // (S11) TRAINERROR state:
            TO_TRAINERROR: begin
                test_d2c_done = 0;
                d2c_timeout_or_error = 1; // Set the timeout or error signal to tell the external Sub-state to move to TRAINERROR state.
            end
            default: begin
                // Do nothing. Just to avoid latches in synthesis.
            end
        endcase
    end

endmodule