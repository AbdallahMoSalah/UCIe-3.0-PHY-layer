
module unit_RX_D2C_PT  #() (
        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        internal_ltsm_if.d2c2substate_mp substate_if,

        //=====================================//
        // Control Signals for the MB and SB:  //
        //=====================================//
        internal_ltsm_if.d2c2mux_mp mux_if
    );

    // =========================
    // Rx Init D2C
    // =========================
    // To get the used SB messages for: (mux_if.tx_sb_msg, sb_it.rx_sb_msg)
    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::Start_Rx_Init_D_to_C_point_test_req ; // Msg Number: d121
    import UCIe_pkg::Start_Rx_Init_D_to_C_point_test_resp; // Msg Number: d122
    import UCIe_pkg::LFSR_clear_error_req                ; // Msg Number: d111
    import UCIe_pkg::LFSR_clear_error_resp               ; // Msg Number: d112
    import UCIe_pkg::Rx_Init_D_to_C_Tx_Count_Done_req    ; // Msg Number: d123
    import UCIe_pkg::Rx_Init_D_to_C_Tx_Count_Done_resp   ; // Msg Number: d124
    import UCIe_pkg::End_Rx_Init_D_to_C_point_test_req   ; // Msg Number: d125
    import UCIe_pkg::End_Rx_Init_D_to_C_point_test_resp  ; // Msg Number: d126
    import UCIe_pkg::TRAINERROR_Entry_req                ; // Msg Number: d107
    import UCIe_pkg::NOTHING                             ; // Msg Number: 8'hFF




    // // Sideband message Values:
    // localparam MSG_START_REQ       = 8'hA0, // From LTSM to SB to request the start of Rx D2C Pattern Test.
    //            MSG_START_RESP      = 8'hA1, // From SB to LTSM to acknowledge the start of Rx D2C Pattern Test.
    //            MSG_CLR_ERR_REQ     = 8'hA2, // From LTSM to SB to request clearing of errors in MB before starting pattern generation.
    //            MSG_CLR_ERR_RESP    = 8'hA3, // From SB to LTSM to acknowledge the clearing of errors in MB.
    //            MSG_COUNT_DONE_REQ  = 8'hA5, // From LTSM to SB to ask if the pattern generation and error counting is done based on burst_count and iter_count.
    //            MSG_COUNT_DONE_RESP = 8'hA6, // From SB to LTSM to acknowledge that the pattern generation and error counting is done.
    //            MSG_END_REQ         = 8'hA7, // From LTSM to SB to request SB to end the pattern test and send results.
    //            MSG_END_RESP        = 8'hA8, // From SB to LTSM to acknowledge the end of the pattern test and sending of results.
    //            MSG_TRAINERROR_REQ  = 8'hFF; // From SB to LTSM to indicate that a TRAINERROR condition has occurred on the partner side (e.g., due to timeout or other errors during training).


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
    always @(posedge mux_if.lclk or negedge mux_if.rst_n) begin
        if (!mux_if.rst_n) begin
            substate_if.d2c_aggr_err    <= 16'b0;
            substate_if.d2c_perlane_err <= 16'b0;
            substate_if.d2c_val_err     <= 1'b0;
            substate_if.d2c_clk_err     <= 1'b0;
        end else if(mux_if.mb_rx_compare_done) begin
            substate_if.d2c_aggr_err    <= mux_if.mb_rx_aggr_err;   // The total calculated Aggregate Errors on Rx.
            substate_if.d2c_perlane_err <= mux_if.mb_rx_perlane_err; // The Per-Lane Errors (Each bit represents one fail Data Lane).
            substate_if.d2c_val_err     <= mux_if.mb_rx_val_err;     // The error coming from Valid Lane receiver in MB.
            substate_if.d2c_clk_err     <= mux_if.mb_rx_clk_err;     // The error coming from Clock Lane receiver in MB.
        end
    end



    // Current State Logic of the FSM:
    always @(posedge mux_if.lclk or negedge mux_if.rst_n) begin
        if (!mux_if.rst_n) begin
            current_state  <= RX_PT_IDLE;
            previous_state <= RX_PT_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state; // We use signal to avoid data incoherence when sending SB messages. It is set to 1 for 1 lclk cycle whenever the state changes, which is when the SB Msg data is updated with new values.
        end
    end

    // Next State Logic of the FSM:
    always @(*) begin
        if(substate_if.substate_timeout_8ms_occured | (mux_if.rx_sb_msg == TRAINERROR_Entry_req && mux_if.rx_sb_msg_valid == 1'b1)) begin
            // (S11)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end
        else if(!substate_if.rx_pt_en) begin
            next_state = RX_PT_IDLE;
        end
        else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start the Rx D2C Pattern Test.
                RX_PT_IDLE: begin
                    if (substate_if.rx_pt_en) next_state = RX_PT_START_REQ;
                    else next_state = RX_PT_IDLE;
                end
                // (S1) Send & Receive SB Message: {Start Rx Init D to C point test req}
                RX_PT_START_REQ: begin
                    if (mux_if.rx_sb_msg == Start_Rx_Init_D_to_C_point_test_req && mux_if.rx_sb_msg_valid == 1'b1) next_state = RX_PT_START_RESP;
                    else next_state = RX_PT_START_REQ;
                end
                // (S2) Send & Receive SB Message: {Start Rx Init D to C point test resp}.
                RX_PT_START_RESP: begin
                    if (mux_if.rx_sb_msg == Start_Rx_Init_D_to_C_point_test_resp && mux_if.rx_sb_msg_valid == 1'b1) next_state = RX_PT_CLR_ERR_REQ;
                    else next_state = RX_PT_START_RESP;
                end
                // (S3) Send & Receive SB Message: {LFSR clear error req}.
                RX_PT_CLR_ERR_REQ: begin
                    if (mux_if.rx_sb_msg == LFSR_clear_error_req && mux_if.rx_sb_msg_valid == 1'b1) next_state = RX_PT_CLR_ERR_RESP;
                    else next_state = RX_PT_CLR_ERR_REQ;
                end
                // (S4) Send & Receive SB Message: {LFSR clear error resp}.
                RX_PT_CLR_ERR_RESP: begin
                    if (mux_if.rx_sb_msg == LFSR_clear_error_resp && mux_if.rx_sb_msg_valid == 1'b1) next_state = RX_PT_PATTERN_GEN;
                    else next_state = RX_PT_CLR_ERR_RESP;
                end
                // (S5) Send & Receive MB Pattern
                RX_PT_PATTERN_GEN: begin
                    if (mux_if.mb_tx_pattern_count_done) next_state = RX_PT_COUNT_DONE_REQ;
                    else next_state = RX_PT_PATTERN_GEN;
                end
                // (S6) Send & Receive SB Message {Rx Init D to C Tx count done req}.
                RX_PT_COUNT_DONE_REQ: begin
                    if (mux_if.rx_sb_msg == Rx_Init_D_to_C_Tx_Count_Done_req && mux_if.rx_sb_msg_valid == 1'b1) next_state = RX_PT_COUNT_DONE_RESP;
                    else next_state = RX_PT_COUNT_DONE_REQ;
                end
                // (S7) Send & Receive SB Message: {Rx Init D to C Tx count done resp}.
                RX_PT_COUNT_DONE_RESP: begin
                    if (mux_if.rx_sb_msg == Rx_Init_D_to_C_Tx_Count_Done_resp && mux_if.rx_sb_msg_valid == 1'b1) next_state = RX_PT_END_REQ;
                    else next_state = RX_PT_COUNT_DONE_RESP;
                end
                // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
                RX_PT_END_REQ: begin
                    if (mux_if.rx_sb_msg == End_Rx_Init_D_to_C_point_test_req && mux_if.rx_sb_msg_valid == 1'b1) next_state = RX_PT_END_RESP;
                    else next_state = RX_PT_END_REQ;
                end
                // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
                RX_PT_END_RESP: begin
                    if (mux_if.rx_sb_msg == End_Rx_Init_D_to_C_point_test_resp && mux_if.rx_sb_msg_valid == 1'b1) next_state = RX_PT_DONE;
                    else next_state = RX_PT_END_RESP;
                end
                // (S10)
                RX_PT_DONE: begin
                    next_state = (substate_if.rx_pt_en)? RX_PT_DONE : RX_PT_IDLE; // Stay here for 1 lclk cycle.
                end
                // (S11) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = (substate_if.rx_pt_en)? TO_TRAINERROR : RX_PT_IDLE; // Stay here for 1 lclk cycle.
                end
                default: begin
                    next_state =  (substate_if.rx_pt_en)? TO_TRAINERROR : RX_PT_IDLE; // Default case to avoid latches in synthesis.
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
        substate_if.test_d2c_done = 0;
        // I ordered the next signals as decribed in data field of the SB msg: {Start Rx Init D to C point test req}
        mux_if.mb_rx_max_err_thresh_perlane = mux_if.cfg_train4_max_err_thresh_perlane    ;  // Max error Threshold in per-Lane comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
        mux_if.mb_rx_max_err_thresh_aggr    = mux_if.cfg_train4_max_err_thresh_aggr       ;  // Max error Threshold in aggregate comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
        mux_if.mb_rx_compare_setup          = substate_if.d2c_compare_setup               ;  // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
        mux_if.mb_tx_iter_count             = substate_if.d2c_iter_count                  ;  // Iteration Count: Indicates the iteration count of bursts followed by idle.
        mux_if.mb_tx_idle_count             = substate_if.d2c_idle_count                  ;  // IDLE Count: Indicates the duration of low following the burst (UI count).
        mux_if.mb_tx_burst_count            = substate_if.d2c_burst_count                 ;  // Burst Count: Indicates the duration of selected pattern (UI count).
        mux_if.mb_tx_pattern_mode           = substate_if.d2c_pattern_mode                ;  // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        mux_if.mb_tx_clk_sampling           = substate_if.d2c_clk_sampling                ;  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
        mux_if.mb_tx_val_pattern_sel        = substate_if.d2c_val_pattern_sel             ;  // 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
        mux_if.mb_tx_data_pattern_sel       = substate_if.d2c_data_pattern_sel            ;  // Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.


        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling Details Group:
        mux_if.mb_tx_clk_sampling_en = 0; // Enable changing Clock sampling/PI phase control state.
        substate_if.d2c_timeout_or_error = 0; // It will be set to 1 if timeout or error occurs during the test to move to TRAINERROR state.

        // Tx Pattern Generator Setup Group:
        mux_if.mb_tx_pattern_setup    = substate_if.d2c_pattern_setup;// 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        mux_if.mb_tx_pattern_en       = 0;                       // 0: Don't send pattern.
        mux_if.mb_tx_lfsr_en          = 0;                       // 0: Disable the Tx LFSR.
        mux_if.mb_tx_lfsr_rst         = 0;                       // 0: Don't Reset the Tx LFSR.
        mux_if.mb_rx_lfsr_en          = 0;                       // 0: Disable the Rx LFSR.
        mux_if.mb_rx_lfsr_rst         = 0;                       // 0: Don't Reset the Rx LFSR.

        // Receiver Comparison Setup & Errors
        mux_if.mb_rx_compare_en = 0;                 // 0: Disable the MB compare circuits.


        //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
        // Lane Selection & Shapes
        mux_if.mb_tx_clk_lane_sel  = 2'b00; // 00b: Low (Tx Logical Clock Lane).
        mux_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low (Tx Logical Data Lanes).
        mux_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low (Tx Logical Valid Lane).
        mux_if.mb_tx_trk_lane_sel  = 2'b00; // 00b: Low (Tx Logical Track Lane).
        mux_if.mb_rx_clk_lane_sel  = 1'b1 ; // 1b: Enabled  (Rx Logical Clock Lane).
        mux_if.mb_rx_data_lane_sel = 1'b1 ; // 1b: Enabled  (Rx Logical Data Lanes).
        mux_if.mb_rx_val_lane_sel  = 1'b1 ; // 1b: Enabled  (Rx Logical Valid Lane).
        mux_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled (Rx Logical Track Lane).


        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // For SB TX:
        mux_if.tx_sb_msg_valid = 1'b0   ; // Tell the SB that the selected message is valid.
        mux_if.tx_sb_msg       = NOTHING; // Tell the Sideband the message that it should to send.
        mux_if.tx_msginfo      = 16'b0  ; // MsgInfo field of the SB message.
        mux_if.tx_data_field   = 64'b0  ; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state.
            RX_PT_IDLE: begin
                // Use the above default values for outputs.
            end
            // (S1) Send & Receive SB Message: {Start Rx Init D to C point test req}
            RX_PT_START_REQ: begin
                // For Req MSG sent: (We send these information for inform perpose only).
                mux_if.tx_sb_msg_valid      = (~data_incoherence); // Assert valid only when data incoherence flag is cleared, to avoid sending incorrect messages.
                mux_if.tx_sb_msg            = Start_Rx_Init_D_to_C_point_test_req;
                mux_if.tx_msginfo           = (substate_if.d2c_compare_setup == 1)? {mux_if.cfg_train4_max_err_thresh_aggr}         :    // Send aggregate comparison mode,
                    (substate_if.d2c_compare_setup == 0)? {4'b0, mux_if.cfg_train4_max_err_thresh_perlane}: 0; // Send Per-lane comparison mode, otherwise 0.
                mux_if.tx_data_field[63:60] = 4'b0;                     // Reserved for future use. Just set it to 0 for now.
                mux_if.tx_data_field[59]    = (substate_if.d2c_compare_setup != 0)     ; // Comparison Mode (0: Per Lane; 1: Aggregate)
                mux_if.tx_data_field[58:43] =  substate_if.d2c_iter_count              ; // Iteration Count Setting.
                mux_if.tx_data_field[42:27] =  substate_if.d2c_idle_count              ; // Idle Count Setting.
                mux_if.tx_data_field[26:11] =  substate_if.d2c_burst_count             ; // Burst Count Setting.
                mux_if.tx_data_field[10]    =  substate_if.d2c_pattern_mode            ; // Pattern Mode (0: continuous mode, 1: Burst Mode).
                mux_if.tx_data_field[9:6]   =  {2'b0, substate_if.d2c_clk_sampling}    ; // Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
                mux_if.tx_data_field[5:3]   =  {2'b0, substate_if.d2c_val_pattern_sel} ; // Valid Pattern (0h: Functional pattern).
                mux_if.tx_data_field[2:0]   =  {1'b0, substate_if.d2c_data_pattern_sel}; // Data pattern (0h: LFSR, 1h: Per Lane ID).

                // Configure the MB depending on the content of the received SB msg: {Start Rx Init D to C point test req}
                mux_if.mb_rx_max_err_thresh_perlane = mux_if.cfg_train4_max_err_thresh_perlane; // Max error Threshold in per-Lane comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
                mux_if.mb_rx_max_err_thresh_aggr    = mux_if.cfg_train4_max_err_thresh_aggr   ; // Max error Threshold in aggregate comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
                mux_if.mb_rx_compare_setup          = substate_if.d2c_compare_setup           ; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
                mux_if.mb_tx_iter_count             = substate_if.d2c_iter_count              ; // Iteration Count: Indicates the iteration count of bursts followed by idle.
                mux_if.mb_tx_idle_count             = substate_if.d2c_idle_count              ; // IDLE Count: Indicates the duration of low following the burst (UI count).
                mux_if.mb_tx_burst_count            = substate_if.d2c_burst_count             ; // Burst Count: Indicates the duration of selected pattern (UI count).
                mux_if.mb_tx_pattern_mode           = substate_if.d2c_pattern_mode            ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
                mux_if.mb_tx_clk_sampling           = substate_if.d2c_clk_sampling            ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
                mux_if.mb_tx_val_pattern_sel        = substate_if.d2c_val_pattern_sel         ; // 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.
                mux_if.mb_tx_data_pattern_sel       = substate_if.d2c_data_pattern_sel        ; // Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.
                mux_if.mb_tx_pattern_setup          = substate_if.d2c_pattern_setup           ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
            end
            // (S2) Send & Receive SB Message: {Start Rx Init D to C point test resp}.
            RX_PT_START_RESP: begin
                // For Resp MSG sent: (We send these information for inform perpose only).
                mux_if.tx_sb_msg_valid     = (~data_incoherence); // Assert valid only when data incoherence flag is cleared, to avoid sending incorrect messages.
                mux_if.tx_sb_msg           = Start_Rx_Init_D_to_C_point_test_resp;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // Reserved.

                // Configure the MB to be ready for the pattern generation:
                mux_if.mb_tx_clk_sampling_en = 1; // Enable changing Clock sampling/PI phase control state.
                mux_if.mb_rx_compare_en      = 1; // Enable the MB compare circuits to start comparing the received pattern with the expected pattern and count errors.
            end
            // (S3) Send & Receive SB Message: {LFSR clear error req}.
            RX_PT_CLR_ERR_REQ: begin
                mux_if.tx_sb_msg_valid     = (~data_incoherence);
                mux_if.tx_sb_msg           = LFSR_clear_error_req;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.

                // Configure the MB to be ready for the pattern generation:
                mux_if.mb_rx_compare_en    = 1;
                mux_if.mb_tx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mux_if.mb_tx_lfsr_rst      = 1; // Reset the Tx LFSR to clear the previous errors.
            end
            // (S4) Send & Receive SB Message: {LFSR clear error resp}.
            RX_PT_CLR_ERR_RESP: begin
                mux_if.tx_sb_msg_valid     = (~data_incoherence);
                mux_if.tx_sb_msg           = LFSR_clear_error_resp;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.

                // Configure the MB to be ready for the pattern generation:
                mux_if.mb_rx_compare_en    = 1;
                mux_if.mb_tx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mux_if.mb_rx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.
                mux_if.mb_rx_lfsr_rst      = 1;           // Reset the Rx LFSR to clear the previous errors.
            end
            // (S5) Send & Receive MB Pattern
            RX_PT_PATTERN_GEN: begin
                mux_if.mb_tx_pattern_en    = 1; // <====== 1: Send pattern immediately, 0: Don't send pattern.

                // For SB Msg:
                mux_if.tx_sb_msg_valid     = 0;

                // For Comparison:
                mux_if.mb_rx_compare_en    = 1;
                mux_if.mb_tx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mux_if.mb_rx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.

                // Logical Lane Selection:
                mux_if.mb_tx_clk_lane_sel  = 2'b01;                  // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
                mux_if.mb_tx_data_lane_sel = {1'b0, substate_if.d2c_pattern_setup[0]}; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
                mux_if.mb_tx_val_lane_sel  = {1'b0, substate_if.d2c_pattern_setup[1]}; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
                mux_if.mb_tx_trk_lane_sel  = 2'b00;                  // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).

            end
            // (S6) Send & Receive SB Message {Rx Init D to C Tx count done req}.
            RX_PT_COUNT_DONE_REQ: begin
                mux_if.tx_sb_msg_valid     = (~data_incoherence);
                mux_if.tx_sb_msg           = Rx_Init_D_to_C_Tx_Count_Done_req;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.

                mux_if.mb_tx_pattern_en = 0; // <====== 1: Send pattern immediately, 0: Don't send pattern.
                mux_if.mb_rx_compare_en = 1;
                mux_if.mb_tx_lfsr_en    = 0;           // disable the Tx LFSR.
                mux_if.mb_rx_lfsr_en    = substate_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.
            end
            // (S7) Send & Receive SB Message: {Rx Init D to C Tx count done resp}.
            RX_PT_COUNT_DONE_RESP: begin
                mux_if.tx_sb_msg_valid     = (~data_incoherence);
                mux_if.tx_sb_msg           = Rx_Init_D_to_C_Tx_Count_Done_resp;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.


                mux_if.mb_tx_pattern_en    = 0;
                mux_if.mb_rx_compare_en    = 0;
                mux_if.mb_tx_lfsr_en       = 0; // disable the Tx LFSR.
                mux_if.mb_rx_lfsr_en       = 0; // disable the Rx LFSR.
            end
            // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
            RX_PT_END_REQ: begin
                mux_if.tx_sb_msg_valid     = (~data_incoherence);
                mux_if.tx_sb_msg           = End_Rx_Init_D_to_C_point_test_req;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.
            end
            // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
            RX_PT_END_RESP: begin
                mux_if.tx_sb_msg_valid     = (~data_incoherence);
                mux_if.tx_sb_msg           = End_Rx_Init_D_to_C_point_test_resp;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.
            end
            // (S10)
            RX_PT_DONE: begin
                mux_if.tx_sb_msg_valid     = 0;
                mux_if.tx_sb_msg           = End_Rx_Init_D_to_C_point_test_resp;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.
                substate_if.test_d2c_done      = 1'b1 ; // Assert the test done signal to tell the external Sub-state the completion of the test.
            end
            // (S11) TRAINERROR state:
            TO_TRAINERROR: begin
                substate_if.test_d2c_done = 0;
                substate_if.d2c_timeout_or_error = 1; // Set the timeout or error signal to tell the external Sub-state to move to TRAINERROR state.
            end
            default: begin
                // Do nothing. Just to avoid latches in synthesis.
            end
        endcase
    end

endmodule
