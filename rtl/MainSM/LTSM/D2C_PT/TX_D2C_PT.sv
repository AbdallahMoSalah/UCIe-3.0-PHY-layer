
module TX_D2C_PT  #() (
        ltsm_if.clk_rst_mp clk_rst,

        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        ltsm_if.d2c2ltsm_mp d2c_if,

        //=====================================//
        // Control Signals for MB:             //
        //=====================================//
        ltsm_if.d2c2mb_mp mb_if,

        //=====================================//
        // Control Signals for SB:             //
        //=====================================//
        ltsm_if.ltsm2sb_mp sb_if,

        //=====================================//
        // Register File (RF) Control Signals: //
        //=====================================//
        ltsm_if.state_rf_offset_1050_mp rf_if
    );

    // Sideband message Values:
    localparam MSG_START_REQ       = 8'hA0, // From LTSM to SB to request the start of Rx D2C Pattern Test.
    MSG_START_RESP      = 8'hA1, // From SB to LTSM to acknowledge the start of Rx D2C Pattern Test.
    MSG_CLR_ERR_REQ     = 8'hA2, // From LTSM to SB to request clearing of errors in MB before starting pattern generation.
    MSG_CLR_ERR_RESP    = 8'hA3, // From SB to LTSM to acknowledge the clearing of errors in MB.
    MSG_RESULTS_REQ     = 8'hA5, // From LTSM to SB to ask if the pattern generation and error counting is done based on burst_count and iter_count.
    MSG_RESULTS_RESP    = 8'hA6, // From SB to LTSM to acknowledge that the pattern generation and error counting is done.
    MSG_END_REQ         = 8'hA7, // From LTSM to SB to request SB to end the pattern test and send results.
    MSG_END_RESP        = 8'hA8, // From SB to LTSM to acknowledge the end of the pattern test and sending of results.
    MSG_TRAINERROR_REQ  = 8'hFF; // From SB to LTSM to indicate that a TRAINERROR condition has occurred on the partner side (e.g., due to timeout or other errors during training).

    // States names
    localparam TX_PT_IDLE         = 4'h0, // (S0)
    TX_PT_START_REQ    = 4'h1, // (S1)
    TX_PT_START_RESP   = 4'h2, // (S2)
    TX_PT_CLR_ERR_REQ  = 4'h3, // (S3)
    TX_PT_CLR_ERR_RESP = 4'h4, // (S4)
    TX_PT_PATTERN_GEN  = 4'h5, // (S5)
    TX_PT_RESULTS_REQ  = 4'h6, // (S6)
    TX_PT_RESULTS_RESP = 4'h7, // (S7)
    TX_PT_END_REQ      = 4'h8, // (S8)
    TX_PT_END_RESP     = 4'h9, // (S9)
    TX_PT_DONE         = 4'hA, // (S10)
    TO_TRAINERROR      = 4'hB; // (S11)

    reg [3:0] current_state, next_state, previous_state; // The Current, Next states, and Previous state of the FSM.
    wire data_incoherence;

    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 clk_rst.lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    assign data_incoherence = (current_state != previous_state) ? 1'b1 : 1'b0;


    // Log Rx Comparison Results from MB:
    always @(posedge clk_rst.lclk or negedge clk_rst.rst_n) begin
        if (!clk_rst.rst_n) begin
            d2c_if.d2c_aggr_err    <= 16'b0;
            d2c_if.d2c_perlane_err <= 16'b0;
            d2c_if.d2c_val_err     <= 1'b0;
            d2c_if.d2c_clk_err     <= 1'b0;
        end else if(mb_if.mb_rx_compare_done) begin
            d2c_if.d2c_aggr_err    <= mb_if.mb_rx_aggr_err;   // The total calculated Aggregate Errors on Rx.
            d2c_if.d2c_perlane_err <= mb_if.mb_rx_perlane_err; // The Per-Lane Errors (Each bit represents one fail Data Lane).
            d2c_if.d2c_val_err     <= mb_if.mb_rx_val_err;     // The error coming from Valid Lane receiver in MB.
            d2c_if.d2c_clk_err     <= mb_if.mb_rx_clk_err;     // The error coming from Clock Lane receiver in MB.
        end
    end



    // Current State Logic of the FSM:
    always @(posedge clk_rst.lclk or negedge clk_rst.rst_n) begin
        if (!clk_rst.rst_n) begin
            current_state  <= TX_PT_IDLE;
            previous_state <= TX_PT_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state; // We use signal to avoid data incoherence when sending SB messages. It is set to 1 for 1 clk_rst.lclk cycle whenever the state changes, which is when the SB Msg data is updated with new values.
        end
    end

    // Next State Logic of the FSM:
    always @(*) begin
        if(d2c_if.timeout_8ms_occured | (sb_if.rx_sb_msg == MSG_TRAINERROR_REQ && sb_if.rx_sb_msg_valid == 1'b1)) begin
            // (S11)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start the Rx D2C Pattern Test.
                TX_PT_IDLE: begin
                    if (d2c_if.tx_pt_en) next_state = TX_PT_START_REQ;
                    else next_state = TX_PT_IDLE;
                end
                // (S1) Send & Receive SB Message: {Start Rx Init D to C point test req}
                TX_PT_START_REQ: begin
                    if (sb_if.rx_sb_msg == MSG_START_REQ && sb_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_START_RESP;
                    else next_state = TX_PT_START_REQ;
                end
                // (S2) Send & Receive SB Message: {Start Rx Init D to C point test resp}.
                TX_PT_START_RESP: begin
                    if (sb_if.rx_sb_msg == MSG_START_RESP && sb_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_CLR_ERR_REQ;
                    else next_state = TX_PT_START_RESP;
                end
                // (S3) Send & Receive SB Message: {LFSR clear error req}.
                TX_PT_CLR_ERR_REQ: begin
                    if (sb_if.rx_sb_msg == MSG_CLR_ERR_REQ && sb_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_CLR_ERR_RESP;
                    else next_state = TX_PT_CLR_ERR_REQ;
                end
                // (S4) Send & Receive SB Message: {LFSR clear error resp}.
                TX_PT_CLR_ERR_RESP: begin
                    if (sb_if.rx_sb_msg == MSG_CLR_ERR_RESP && sb_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_PATTERN_GEN;
                    else next_state = TX_PT_CLR_ERR_RESP;
                end
                // (S5) Send & Receive MB Pattern
                TX_PT_PATTERN_GEN: begin
                    if (mb_if.mb_tx_pattern_count_done) next_state = TX_PT_RESULTS_REQ;
                    else next_state = TX_PT_PATTERN_GEN;
                end
                // (S6) Send & Receive SB Message {Rx Init D to C Tx count done req}.
                TX_PT_RESULTS_REQ: begin
                    if (sb_if.rx_sb_msg == MSG_RESULTS_REQ && sb_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_RESULTS_RESP;
                    else next_state = TX_PT_RESULTS_REQ;
                end
                // (S7) Send & Receive SB Message: {Rx Init D to C Tx count done resp}.
                TX_PT_RESULTS_RESP: begin
                    if (sb_if.rx_sb_msg == MSG_RESULTS_RESP && sb_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_END_REQ;
                    else next_state = TX_PT_RESULTS_RESP;
                end
                // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
                TX_PT_END_REQ: begin
                    if (sb_if.rx_sb_msg == MSG_END_REQ && sb_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_END_RESP;
                    else next_state = TX_PT_END_REQ;
                end
                // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
                TX_PT_END_RESP: begin
                    if (sb_if.rx_sb_msg == MSG_END_RESP && sb_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_DONE;
                    else next_state = TX_PT_END_RESP;
                end
                // (S10)
                TX_PT_DONE: begin
                    next_state = TX_PT_IDLE; // Stay here for 1 clk_rst.lclk cycle.
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
        d2c_if.test_d2c_done = 0;

        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling Details Group:
        mb_if.mb_tx_clk_sampling_en = 0; // Enable changing Clock sampling/PI phase control state.
        d2c_if.d2c_timeout_or_error  = 0; // It will be set to 1 if timeout or error occurs during the test to move to TRAINERROR state.

        // Tx Pattern Generator Setup Group:
        mb_if.mb_tx_pattern_setup    = d2c_if.d2c_pattern_setup; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        mb_if.mb_tx_pattern_en       = 0;                 // 0: Don't send pattern.
        mb_if.mb_tx_lfsr_en          = 0;                 // 0: Disable the Tx LFSR.
        mb_if.mb_tx_lfsr_rst         = 0;                 // 0: Don't Reset the Tx LFSR.
        mb_if.mb_rx_lfsr_en          = 0;                 // 0: Disable the Rx LFSR.
        mb_if.mb_rx_lfsr_rst         = 0;                 // 0: Don't Reset the Rx LFSR.

        // Receiver Comparison Setup & Errors
        mb_if.mb_rx_compare_en = 0;                 // 0: Disable the MB compare circuits.


        //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
        // Lane Selection & Shapes
        mb_if.mb_tx_clk_lane_sel  = 2'b00; // 00b: Low (Tx Logical Clock Lane).
        mb_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low (Tx Logical Data Lanes).
        mb_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low (Tx Logical Valid Lane).
        mb_if.mb_tx_trk_lane_sel  = 2'b00; // 00b: Low (Tx Logical Track Lane).
        mb_if.mb_rx_clk_lane_sel  = 1'b1 ; // 1b: Enabled  (Rx Logical Clock Lane).
        mb_if.mb_rx_data_lane_sel = 1'b1 ; // 1b: Enabled  (Rx Logical Data Lanes).
        mb_if.mb_rx_val_lane_sel  = 1'b1 ; // 1b: Enabled  (Rx Logical Valid Lane).
        mb_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled (Rx Logical Track Lane).


        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // For SB TX:
        sb_if.tx_sb_msg_valid =  1'b0; // Tell the SB that the selected message is valid.
        sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(8'b0); // Tell the Sideband the message that it should to send.
        sb_if.tx_msginfo      = 16'b0; // MsgInfo field of the SB message.
        sb_if.tx_data_field   = 64'b0; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state.
            TX_PT_IDLE: begin
                // Use the above default values for outputs.
            end
            // (S1) Send & Receive SB Message: {Start Rx Init D to C point test req}
            TX_PT_START_REQ: begin
                // For Req MSG sent: (We send these information Because the partner uses it).
                sb_if.tx_sb_msg_valid      = (~data_incoherence); // Assert valid only when data incoherence flag is cleared, to avoid sending incorrect messages.
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_START_REQ);
                sb_if.tx_msginfo           = (d2c_if.d2c_compare_setup == 1)? {rf_if.cfg_train4_max_err_thresh_aggr}         :    // Send aggregate comparison mode,
                    (d2c_if.d2c_compare_setup == 0)? {4'b0, rf_if.cfg_train4_max_err_thresh_perlane}: 0; // Send Per-lane comparison mode, otherwise 0.
                sb_if.tx_data_field[63:60] = 4'b0                    ; // Reserved for future use. Just set it to 0 for now.
                sb_if.tx_data_field[59]    = (d2c_if.d2c_compare_setup != 0); // Comparison Mode (0: Per Lane; 1: Aggregate)
                sb_if.tx_data_field[58:43] = d2c_if.d2c_iter_count          ; // Iteration Count Setting.
                sb_if.tx_data_field[42:27] = d2c_if.d2c_idle_count          ; // Idle Count Setting.
                sb_if.tx_data_field[26:11] = d2c_if.d2c_burst_count         ; // Burst Count Setting.
                sb_if.tx_data_field[10]    = d2c_if.d2c_pattern_mode        ; // Pattern Mode (0: continuous mode, 1: Burst Mode).
                sb_if.tx_data_field[9:6]   = 4'(d2c_if.d2c_clk_sampling)    ; // Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
                sb_if.tx_data_field[5:3]   = 3'b000                  ; //d2c_if.d2c_val_pattern_sel always = 0 in this test // Valid Pattern (0h: Functional pattern).
                sb_if.tx_data_field[2:0]   = 3'(d2c_if.d2c_data_pattern_sel); // Data pattern (0h: LFSR, 1h: Per Lane ID).

                // Configure the MB depending on the content of the received SB msg: {Start Tx Init D to C point test req}
                mb_if.mb_tx_pattern_setup  = d2c_if.d2c_pattern_setup; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.

                // mb_if.mb_rx_max_err_thresh_perlane <= (Get these signals from the Partner (using the SB Msg):) rf_if.cfg_train4_max_err_thresh_perlane;  // Max error Threshold in per-Lane comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
                // mb_if.mb_rx_max_err_thresh_aggr    <= (Get these signals from the Partner (using the SB Msg):) rf_if.cfg_train4_max_err_thresh_aggr   ;  // Max error Threshold in aggregate comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
                // mb_if.mb_rx_compare_setup          <= (Get these signals from the Partner (using the SB Msg):) d2c_if.d2c_compare_setup                ;  // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
                // mb_if.mb_tx_iter_count             <= (Get these signals from the Partner (using the SB Msg):) d2c_if.d2c_iter_count                   ;  // Iteration Count: Indicates the iteration count of bursts followed by idle.
                // mb_if.mb_tx_idle_count             <= (Get these signals from the Partner (using the SB Msg):) d2c_if.d2c_idle_count                   ;  // IDLE Count: Indicates the duration of low following the burst (UI count).
                // mb_if.mb_tx_burst_count            <= (Get these signals from the Partner (using the SB Msg):) d2c_if.d2c_burst_count                  ;  // Burst Count: Indicates the duration of selected pattern (UI count).
                // mb_if.mb_tx_pattern_mode           <= (Get these signals from the Partner (using the SB Msg):) d2c_if.d2c_pattern_mode                 ;  // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                // mb_if.mb_tx_clk_sampling           <= (Get these signals from the Partner (using the SB Msg):) d2c_if.d2c_clk_sampling                 ;  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
                // mb_if.mb_tx_val_pattern_sel        <= (Get these signals from the Partner (using the SB Msg):) d2c_if.d2c_val_pattern_sel              ;  // 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
                // mb_if.mb_tx_data_pattern_sel       <= (Get these signals from the Partner (using the SB Msg):) d2c_if.d2c_data_pattern_sel             ;  // Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.
            end
            // (S2) Send & Receive SB Message: {Start Tx Init D to C point test resp}.
            TX_PT_START_RESP: begin
                // For Resp MSG sent: (We send these information for inform perpose only).
                sb_if.tx_sb_msg_valid     = (~data_incoherence); // Assert valid only when data incoherence flag is cleared, to avoid sending incorrect messages.
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_START_RESP);
                sb_if.tx_msginfo          = 16'b0;
                sb_if.tx_data_field[63:0] = 64'b0; // Reserved.

                // Configure the MB to be ready for the pattern generation:
                mb_if.mb_tx_clk_sampling_en = 1; // Enable changing Clock sampling/PI phase control state.
                mb_if.mb_rx_compare_en      = 1; // Enable the MB compare circuits to start comparing the received pattern with the expected pattern and count errors.
            end
            // (S3) Send & Receive SB Message: {LFSR clear error req}.
            TX_PT_CLR_ERR_REQ: begin
                sb_if.tx_sb_msg_valid     = (~data_incoherence);
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_CLR_ERR_REQ);
                sb_if.tx_msginfo          = 16'b0;
                sb_if.tx_data_field[63:0] = 64'b0; // No payload.

                // Configure the MB to be ready for the pattern generation:
                mb_if.mb_rx_compare_en    = 1;
                mb_if.mb_tx_lfsr_en       = d2c_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mb_if.mb_tx_lfsr_rst      = 1; // Reset the Tx LFSR to clear the previous errors.
            end
            // (S4) Send & Receive SB Message: {LFSR clear error resp}.
            TX_PT_CLR_ERR_RESP: begin
                sb_if.tx_sb_msg_valid     = (~data_incoherence);
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_CLR_ERR_RESP);
                sb_if.tx_msginfo          = 16'b0;
                sb_if.tx_data_field[63:0] = 64'b0; // No payload.

                // Configure the MB to be ready for the pattern generation:
                mb_if.mb_rx_compare_en    = 1;
                mb_if.mb_tx_lfsr_en       = d2c_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mb_if.mb_rx_lfsr_en       = d2c_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.
                mb_if.mb_rx_lfsr_rst      = 1;           // Reset the Rx LFSR to clear the previous errors.
            end
            // (S5) Send & Receive MB Pattern
            TX_PT_PATTERN_GEN: begin
                mb_if.mb_tx_pattern_en    = 1; // <====== 1: Send pattern immediately, 0: Don't send pattern.

                // For SB Msg:
                sb_if.tx_sb_msg_valid     = 0;

                // For Comparison:
                mb_if.mb_rx_compare_en    = 1;
                mb_if.mb_tx_lfsr_en       = d2c_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mb_if.mb_rx_lfsr_en       = d2c_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.

                // Logical Lane Selection:
                mb_if.mb_tx_clk_lane_sel  = 2'b01                       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
                mb_if.mb_tx_data_lane_sel = {1'b0, d2c_if.d2c_pattern_setup[0]}; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
                mb_if.mb_tx_val_lane_sel  = {1'b0, d2c_if.d2c_pattern_setup[1]}; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
                mb_if.mb_tx_trk_lane_sel  = 2'b00                       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
            end
            // (S6) Send & Receive SB Message {Tx Init D to C results req}.
            TX_PT_RESULTS_REQ: begin
                sb_if.tx_sb_msg_valid     = (~data_incoherence);
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_RESULTS_REQ);
                sb_if.tx_msginfo          = 16'b0;
                sb_if.tx_data_field[63:0] = 64'b0; // No payload.

                mb_if.mb_tx_pattern_en = 0; // <====== 1: Send pattern immediately, 0: Don't send pattern.
                mb_if.mb_rx_compare_en = 1;
                mb_if.mb_tx_lfsr_en    = 0;           // disable the Tx LFSR.
                mb_if.mb_rx_lfsr_en    = d2c_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.
            end
            // (S7) Send & Receive SB Message: {Tx Init D to C results resp}.
            TX_PT_RESULTS_RESP: begin
                // For Tx SB Msg:
                sb_if.tx_sb_msg_valid     = (~data_incoherence);
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_RESULTS_RESP);

                sb_if.tx_msginfo[15:6]    = 10'b0                ; // Reserved.
                sb_if.tx_msginfo[5]       = mb_if.mb_rx_val_err        ; // Valid Lane comparison results.
                sb_if.tx_msginfo[4]       = mb_if.mb_rx_aggr_err!=16'b0; // For Aggregate Comparison.
                sb_if.tx_msginfo[3:0]     = 4'b0                ; // Used only with Advanced Package for Redundent Lanes.

                sb_if.tx_data_field[63:0] = {48'b0, mb_if.mb_rx_perlane_err[15:0]}; // Send this per-lane result if the used Data Lanes are from 0 to 15.

                // For Resp SB Msg received: {Tx Init D to C results resp}: The next code is written in external sequential always block
                // if(sb_if.rx_sb_msg == MSG_RESULTS_REQ && sb_if.rx_sb_msg_valid == 1'b1) begin
                //     d2c_if.d2c_val_err     <= sb_if.rx_msginfo[5]      ; // Get the Valid Lane comparison results from the partner (based on the received SB message).
                //     d2c_if.d2c_aggr_err    <= sb_if.rx_msginfo[4]      ; // Get the Aggregate comparison results from the partner (based on the received SB message). We use 1 bit to indicate if there is error for aggregate comparison.
                //     d2c_if.d2c_perlane_err <= sb_if.rx_data_field[15:0]; // Get the Per-lane   comparison results from the partner (based on the received SB message).
                // end

                mb_if.mb_tx_pattern_en    = 0;
                mb_if.mb_rx_compare_en    = 0;
                mb_if.mb_tx_lfsr_en       = 0; // disable the Tx LFSR.
                mb_if.mb_rx_lfsr_en       = 0; // disable the Rx LFSR.
            end
            // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
            TX_PT_END_REQ: begin
                sb_if.tx_sb_msg_valid     = (~data_incoherence);
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_END_REQ);
                sb_if.tx_msginfo          = 16'b0;
                sb_if.tx_data_field[63:0] = 64'b0; // No payload.
            end
            // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
            TX_PT_END_RESP: begin
                sb_if.tx_sb_msg_valid     = (~data_incoherence);
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_END_RESP);
                sb_if.tx_msginfo          = 16'b0;
                sb_if.tx_data_field[63:0] = 64'b0; // No payload.
            end
            // (S10)
            TX_PT_DONE: begin
                sb_if.tx_sb_msg_valid     = 0;
                sb_if.tx_sb_msg = UCIe_pkg::msg_no_e'(MSG_END_RESP);
                sb_if.tx_msginfo          = 16'b0;
                sb_if.tx_data_field[63:0] = 64'b0; // No payload.
                d2c_if.test_d2c_done       = 1; // Assert the test done signal to tell the external Sub-state the completion of the test.
            end
            // (S11) TRAINERROR state:
            TO_TRAINERROR: begin
                d2c_if.test_d2c_done = 0;
                d2c_if.d2c_timeout_or_error = 1; // Set the timeout or error signal to tell the external Sub-state to move to TRAINERROR state.
            end
            default: begin
                // Do nothing. Just to avoid latches in synthesis.
            end
        endcase
    end

    always @(posedge clk_rst.lclk or negedge clk_rst.rst_n) begin
        if (!clk_rst.rst_n) begin
            mb_if.mb_rx_max_err_thresh_perlane <= 0;
            mb_if.mb_rx_max_err_thresh_aggr    <= 0;
            mb_if.mb_rx_compare_setup          <= 0;
            mb_if.mb_tx_iter_count             <= 0;
            mb_if.mb_tx_idle_count             <= 0;
            mb_if.mb_tx_burst_count            <= 0;
            mb_if.mb_tx_pattern_mode           <= 0;
            mb_if.mb_tx_clk_sampling           <= 0;
            mb_if.mb_tx_val_pattern_sel        <= 0;
            mb_if.mb_tx_data_pattern_sel       <= 0;
            d2c_if.d2c_val_err                  <= 0;
            d2c_if.d2c_aggr_err                 <= 0;
            d2c_if.d2c_perlane_err              <= 0;
        end
        // For Req SB Msg received: {Start Tx Init D to C point test req}
        else if(sb_if.rx_sb_msg == MSG_START_REQ && sb_if.rx_sb_msg_valid) begin
            // For the Tx Init D to C Point Test:
            mb_if.mb_rx_max_err_thresh_perlane <= (sb_if.rx_data_field[59] == 0)? 12'(sb_if.rx_msginfo) : '0; // Receive Per-lane error threshold.
            mb_if.mb_rx_max_err_thresh_aggr    <= (sb_if.rx_data_field[59] == 1)? 16'(sb_if.rx_msginfo) : '0; // Receive Aggregate error threshold.
            mb_if.mb_rx_compare_setup          <= (d2c_if.d2c_compare_setup == 2'b00 | d2c_if.d2c_compare_setup == 2'b01)? {1'b0, sb_if.rx_data_field[59]} : {d2c_if.d2c_compare_setup}; // Comparison Mode (0: Per Lane; 1: Aggregate)
            mb_if.mb_tx_iter_count             <=  sb_if.rx_data_field[58:43]  ; // Iteration Count Setting.
            mb_if.mb_tx_idle_count             <=  sb_if.rx_data_field[42:27]  ; // Idle Count Setting.
            mb_if.mb_tx_burst_count            <=  sb_if.rx_data_field[26:11]  ; // Burst Count Setting.
            mb_if.mb_tx_pattern_mode           <=  sb_if.rx_data_field[10]     ; // Pattern Mode (0: continuous mode, 1: Burst Mode).
            mb_if.mb_tx_clk_sampling           <=  2'(sb_if.rx_data_field[9:6]); // Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
            mb_if.mb_tx_val_pattern_sel        <=  2'(sb_if.rx_data_field[5:3]); // Valid Pattern (0h: Functional pattern).
            mb_if.mb_tx_data_pattern_sel       <=  2'(sb_if.rx_data_field[2:0]); // Data pattern (0h: LFSR, 1h: Per Lane ID).
        end
        // For Resp SB Msg received: {Tx Init D to C results resp}
        else if(sb_if.rx_sb_msg == MSG_RESULTS_REQ && sb_if.rx_sb_msg_valid == 1'b1) begin
            d2c_if.d2c_val_err     <= sb_if.rx_msginfo[5]         ; // Get the Valid Lane comparison results from the partner (based on the received SB message).
            d2c_if.d2c_aggr_err    <= {15'b0, sb_if.rx_msginfo[4]}; // Get the Aggregate comparison results from the partner (based on the received SB message). We use 1 bit to indicate if there is error for aggregate comparison.
            d2c_if.d2c_perlane_err <= sb_if.rx_data_field[15:0]   ; // Get the Per-lane   comparison results from the partner (based on the received SB message).
        end
    end

endmodule