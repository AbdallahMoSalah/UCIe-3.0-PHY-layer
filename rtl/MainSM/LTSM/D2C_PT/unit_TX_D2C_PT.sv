
module unit_TX_D2C_PT  #() (
        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        internal_ltsm_if.tx_d2c2substate_mp substate_if,

        //=====================================//
        // Control Signals for MB, SB, LTSM:   //
        //=====================================//
        internal_ltsm_if.d2c2mux_mp mux_if
    );

    // Sideband message Names from UCIe_pkg:
    import UCIe_pkg::Start_Tx_Init_D_to_C_point_test_req;
    import UCIe_pkg::Start_Tx_Init_D_to_C_point_test_resp;
    import UCIe_pkg::LFSR_clear_error_req;
    import UCIe_pkg::LFSR_clear_error_resp;
    import UCIe_pkg::Tx_Init_D_to_C_results_req;
    import UCIe_pkg::Tx_Init_D_to_C_results_resp;
    import UCIe_pkg::End_Tx_Init_D_to_C_point_test_req;
    import UCIe_pkg::End_Tx_Init_D_to_C_point_test_resp;
    import UCIe_pkg::TRAINERROR_Entry_req;

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

    reg [3:0] current_state, next_state; // The Current, Next states, and Previous state of the FSM.
    wire data_valid_pulse;

    // This signal is used to apply a valid signal for 1 clk as a pulse for the Tx SB data when sending signals to SB accross the Asynchronous FIFO.
    assign data_valid_pulse = (current_state == next_state) ? 1'b1 : 1'b0;


    // NOTE: In the TX D2C test, our local Rx errors (d2c_aggr_err, d2c_perlane_err,
    // d2c_val_err, d2c_clk_err) are populated from the PARTNER's SB resp message
    // (extracted in the sequential block below), NOT from local mb_rx_compare signals.
    // The local mb_rx_* signals are sent TO the partner via our own SB resp message.



    // Current State Logic of the FSM:
    always @(posedge mux_if.lclk or negedge mux_if.rst_n) begin
        if (!mux_if.rst_n) begin
            current_state  <= TX_PT_IDLE;
        end else begin
            current_state  <= next_state;
        end
    end

    always @(*) begin
        if(!substate_if.tx_pt_en) begin
            next_state = TX_PT_IDLE;
        end
        else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start the Rx D2C Pattern Test.
                TX_PT_IDLE: begin
                    if (substate_if.tx_pt_en) next_state = TX_PT_START_REQ;
                    else next_state = TX_PT_IDLE;
                end
                // (S1) Send & Receive SB Message: {Start Rx Init D to C point test req}
                TX_PT_START_REQ: begin
                    if (mux_if.rx_sb_msg == Start_Tx_Init_D_to_C_point_test_req && mux_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_START_RESP;
                    else next_state = TX_PT_START_REQ;
                end
                // (S2) Send & Receive SB Message: {Start Rx Init D to C point test resp}.
                TX_PT_START_RESP: begin
                    if (mux_if.rx_sb_msg == Start_Tx_Init_D_to_C_point_test_resp && mux_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_CLR_ERR_REQ;
                    else next_state = TX_PT_START_RESP;
                end
                // (S3) Send & Receive SB Message: {LFSR clear error req}.
                TX_PT_CLR_ERR_REQ: begin
                    if (mux_if.rx_sb_msg == LFSR_clear_error_req && mux_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_CLR_ERR_RESP;
                    else next_state = TX_PT_CLR_ERR_REQ;
                end
                // (S4) Send & Receive SB Message: {LFSR clear error resp}.
                TX_PT_CLR_ERR_RESP: begin
                    if (mux_if.rx_sb_msg == LFSR_clear_error_resp && mux_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_PATTERN_GEN;
                    else next_state = TX_PT_CLR_ERR_RESP;
                end
                // (S5) Send & Receive MB Pattern
                TX_PT_PATTERN_GEN: begin
                    if (mux_if.mb_tx_pattern_count_done) next_state = TX_PT_RESULTS_REQ;
                    else next_state = TX_PT_PATTERN_GEN;
                end
                // (S6) Send & Receive SB Message {Rx Init D to C Tx count done req}.
                TX_PT_RESULTS_REQ: begin
                    if (mux_if.rx_sb_msg == Tx_Init_D_to_C_results_req && mux_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_RESULTS_RESP;
                    else next_state = TX_PT_RESULTS_REQ;
                end
                // (S7) Send & Receive SB Message: {Rx Init D to C Tx count done resp}.
                TX_PT_RESULTS_RESP: begin
                    if (mux_if.rx_sb_msg == Tx_Init_D_to_C_results_resp && mux_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_END_REQ;
                    else next_state = TX_PT_RESULTS_RESP;
                end
                // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
                TX_PT_END_REQ: begin
                    if (mux_if.rx_sb_msg == End_Tx_Init_D_to_C_point_test_req && mux_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_END_RESP;
                    else next_state = TX_PT_END_REQ;
                end
                // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
                TX_PT_END_RESP: begin
                    if (mux_if.rx_sb_msg == End_Tx_Init_D_to_C_point_test_resp && mux_if.rx_sb_msg_valid == 1'b1) next_state = TX_PT_DONE;
                    else next_state = TX_PT_END_RESP;
                end
                // (S10)
                TX_PT_DONE: begin
                    next_state = (substate_if.tx_pt_en)? TX_PT_DONE : TX_PT_IDLE; // Stay here for 1 mux_if.lclk cycle.
                end
                default: begin
                    next_state =  (substate_if.tx_pt_en)? current_state : TX_PT_IDLE; // Default case to avoid latches in synthesis.
                end
            endcase
        end

    end

    // Output logic based on current state
    always @(*) begin
        //=======================================================//
        //     Default values for outputs (to avoid latches)     //
        //=======================================================//
        substate_if.test_d2c_done = 0;

        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling Details Group:
        mux_if.mb_tx_clk_sampling_en = 0; // Enable changing Clock sampling/PI phase control state.

        // Tx Pattern Generator Setup Group:
        mux_if.mb_tx_pattern_setup    = substate_if.d2c_pattern_setup; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        mux_if.mb_tx_pattern_en       = 0;                 // 0: Don't send pattern.
        mux_if.mb_tx_lfsr_en          = 0;                 // 0: Disable the Tx LFSR.
        mux_if.mb_tx_lfsr_rst         = 0;                 // 0: Don't Reset the Tx LFSR.
        mux_if.mb_rx_lfsr_en          = 0;                 // 0: Disable the Rx LFSR.
        mux_if.mb_rx_lfsr_rst         = 0;                 // 0: Don't Reset the Rx LFSR.

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
        mux_if.tx_sb_msg_valid =  1'b0   ; // Tell the SB that the selected message is valid.
        mux_if.tx_sb_msg       = UCIe_pkg::NOTHING; // Tell the Sideband the message that it should to send.
        mux_if.tx_msginfo      = 16'b0; // MsgInfo field of the SB message.
        mux_if.tx_data_field   = 64'b0; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state.
            TX_PT_IDLE: begin
                // Use the above default values for outputs.
            end
            // (S1) Send & Receive SB Message: {Start Rx Init D to C point test req}
            TX_PT_START_REQ: begin
                // For Req MSG sent: We send our Tx-test configuration so the partner knows how
                // to set up its Rx comparison hardware.
                mux_if.tx_sb_msg_valid      = (data_valid_pulse); // Assert valid only when data incoherence flag is cleared.
                mux_if.tx_sb_msg            = Start_Tx_Init_D_to_C_point_test_req;
                // MsgInfo: carry the error threshold relevant to our compare mode.
                mux_if.tx_msginfo           = (substate_if.d2c_compare_setup == 2'd1) ? {mux_if.cfg_train4_max_err_thresh_aggr} :
                    (substate_if.d2c_compare_setup == 2'd0) ? {4'b0, mux_if.cfg_train4_max_err_thresh_perlane} : 16'b0;
                mux_if.tx_data_field[63:60] = 4'b0;                                    // Reserved.
                mux_if.tx_data_field[59]    = (substate_if.d2c_compare_setup != 2'd0); // Comparison Mode (0: Per Lane; 1: Aggregate or other)
                mux_if.tx_data_field[58:43] = substate_if.d2c_iter_count;              // Iteration Count.
                mux_if.tx_data_field[42:27] = substate_if.d2c_idle_count;              // Idle Count.
                mux_if.tx_data_field[26:11] = substate_if.d2c_burst_count;             // Burst Count.
                mux_if.tx_data_field[10]    = substate_if.d2c_pattern_mode;            // Pattern Mode.
                mux_if.tx_data_field[9:6]   = {2'b0, substate_if.d2c_clk_sampling};   // Clock Phase (4 bits sent, only [1:0] used).
                mux_if.tx_data_field[5:3]   = {2'b0, substate_if.d2c_val_pattern_sel};// Valid Pattern sel (1 bit, zero-padded).
                mux_if.tx_data_field[2:0]   = {1'b0, substate_if.d2c_data_pattern_sel};// Data Pattern sel (2 bits, zero-padded).

                // Tell the MB which pattern type to prepare.
                mux_if.mb_tx_pattern_setup  = substate_if.d2c_pattern_setup;
            end
            // (S2) Send & Receive SB Message: {Start Tx Init D to C point test resp}.
            TX_PT_START_RESP: begin
                mux_if.tx_sb_msg_valid     = (data_valid_pulse);
                mux_if.tx_sb_msg           = Start_Tx_Init_D_to_C_point_test_resp;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // Reserved.

                // Enable clock-sampling PI control and Rx comparison circuits
                // so that by the time we reach CLR_ERR states the MB is ready.
                mux_if.mb_tx_clk_sampling_en = 1;
                mux_if.mb_rx_compare_en      = 1;
            end
            // (S3) Send & Receive SB Message: {LFSR clear error req}.
            TX_PT_CLR_ERR_REQ: begin
                mux_if.tx_sb_msg_valid     = (data_valid_pulse);
                mux_if.tx_sb_msg = LFSR_clear_error_req;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.

                // Configure the MB to be ready for the pattern generation:
                mux_if.mb_rx_compare_en    = 1;
                mux_if.mb_tx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mux_if.mb_tx_lfsr_rst      = 1; // Reset the Tx LFSR to clear the previous errors.
            end
            // (S4) Send & Receive SB Message: {LFSR clear error resp}.
            TX_PT_CLR_ERR_RESP: begin
                mux_if.tx_sb_msg_valid     = (data_valid_pulse);
                mux_if.tx_sb_msg = LFSR_clear_error_resp;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.

                // Configure the MB to be ready for the pattern generation:
                mux_if.mb_rx_compare_en    = 1;
                mux_if.mb_tx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mux_if.mb_rx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.
                mux_if.mb_rx_lfsr_rst      = 1;           // Reset the Rx LFSR to clear the previous errors.
            end
            // (S5) Send & Receive MB Pattern
            TX_PT_PATTERN_GEN: begin
                mux_if.mb_tx_pattern_en    = 1; // <====== 1: Send pattern immediately, 0: Don't send pattern.

                // For SB Msg:
                mux_if.tx_sb_msg_valid     = 0;

                // For Comparison:
                mux_if.mb_rx_compare_en    = 1;
                mux_if.mb_tx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Tx LFSR to start generating the pattern based on the configured settings.
                mux_if.mb_rx_lfsr_en       = substate_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.

                // Logical Lane Selection:
                mux_if.mb_tx_clk_lane_sel  = 2'b01                       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
                mux_if.mb_tx_data_lane_sel = {1'b0, substate_if.d2c_pattern_setup[0]}; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
                mux_if.mb_tx_val_lane_sel  = {1'b0, substate_if.d2c_pattern_setup[1]}; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
                mux_if.mb_tx_trk_lane_sel  = 2'b00                       ; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
            end
            // (S6) Send & Receive SB Message {Tx Init D to C results req}.
            TX_PT_RESULTS_REQ: begin
                mux_if.tx_sb_msg_valid     = (data_valid_pulse);
                mux_if.tx_sb_msg = Tx_Init_D_to_C_results_req;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.

                mux_if.mb_tx_pattern_en = 0; // <====== 1: Send pattern immediately, 0: Don't send pattern.
                mux_if.mb_rx_compare_en = 1;
                mux_if.mb_tx_lfsr_en    = 0;           // disable the Tx LFSR.
                mux_if.mb_rx_lfsr_en    = substate_if.d2c_lfsr_en; // Enable the Rx LFSR to start generating the pattern based on the configured settings.
            end
            // (S7) Send & Receive SB Message: {Tx Init D to C results resp}.
            TX_PT_RESULTS_RESP: begin
                // For Tx SB Msg:
                mux_if.tx_sb_msg_valid     = (data_valid_pulse);
                mux_if.tx_sb_msg = Tx_Init_D_to_C_results_resp;

                mux_if.tx_msginfo[15:6]    = 10'b0                ; // Reserved.
                mux_if.tx_msginfo[5]       = mux_if.mb_rx_val_err        ; // Valid Lane comparison results.
                mux_if.tx_msginfo[4]       = mux_if.mb_rx_aggr_err!=16'b0; // For Aggregate Comparison.
                mux_if.tx_msginfo[3:0]     = 4'b0                ; // Used only with Advanced Package for Redundent Lanes.

                mux_if.tx_data_field[63:0] = {48'b0, mux_if.mb_rx_perlane_err[15:0]}; // Send this per-lane result if the used Data Lanes are from 0 to 15.

                // For Resp SB Msg received: {Tx Init D to C results resp}: The next code is written in external sequential always block
                // if(mux_if.rx_sb_msg == MSG_RESULTS_REQ && mux_if.rx_sb_msg_valid == 1'b1) begin
                //     substate_if.d2c_val_err     <= mux_if.rx_msginfo[5]      ; // Get the Valid Lane comparison results from the partner (based on the received SB message).
                //     substate_if.d2c_aggr_err    <= mux_if.rx_msginfo[4]      ; // Get the Aggregate comparison results from the partner (based on the received SB message). We use 1 bit to indicate if there is error for aggregate comparison.
                //     substate_if.d2c_perlane_err <= mux_if.rx_data_field[15:0]; // Get the Per-lane   comparison results from the partner (based on the received SB message).
                // end

                mux_if.mb_tx_pattern_en    = 0;
                mux_if.mb_rx_compare_en    = 0;
                mux_if.mb_tx_lfsr_en       = 0; // disable the Tx LFSR.
                mux_if.mb_rx_lfsr_en       = 0; // disable the Rx LFSR.
            end
            // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
            TX_PT_END_REQ: begin
                mux_if.tx_sb_msg_valid     = (data_valid_pulse);
                mux_if.tx_sb_msg = End_Tx_Init_D_to_C_point_test_req;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.
            end
            // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
            TX_PT_END_RESP: begin
                mux_if.tx_sb_msg_valid     = (data_valid_pulse);
                mux_if.tx_sb_msg = End_Tx_Init_D_to_C_point_test_resp;
                mux_if.tx_msginfo          = 16'b0;
                mux_if.tx_data_field[63:0] = 64'b0; // No payload.
            end
            // (S10) DONE
            TX_PT_DONE: begin
                mux_if.tx_sb_msg_valid         = 0;
                mux_if.tx_sb_msg               = UCIe_pkg::NOTHING;
                mux_if.tx_msginfo              = 16'b0;
                mux_if.tx_data_field[63:0]     = 64'b0;
                substate_if.test_d2c_done      = 1; // Assert done to parent FSM.
            end
            // (S11) TRAINERROR state:
            TO_TRAINERROR: begin
                substate_if.test_d2c_done = 0;
            end
            default: begin
                // Do nothing. Just to avoid latches in synthesis.
            end
        endcase
    end

    always @(posedge mux_if.lclk or negedge mux_if.rst_n) begin
        if (!mux_if.rst_n) begin
            mux_if.mb_rx_max_err_thresh_perlane <= 0;
            mux_if.mb_rx_max_err_thresh_aggr    <= 0;
            mux_if.mb_rx_compare_setup          <= 0;
            mux_if.mb_tx_iter_count             <= 0;
            mux_if.mb_tx_idle_count             <= 0;
            mux_if.mb_tx_burst_count            <= 0;
            mux_if.mb_tx_pattern_mode           <= 0;
            mux_if.mb_tx_clk_sampling           <= 0;
            mux_if.mb_tx_val_pattern_sel        <= 0;
            mux_if.mb_tx_data_pattern_sel       <= 0;
            substate_if.d2c_val_err                      <= 0;
            substate_if.d2c_aggr_err                     <= 0;
            substate_if.d2c_perlane_err                  <= 0;
            substate_if.partner_valtraincenter_fail_flag  <= 0;
        end
        // -- SB REQ from partner: extract pattern-gen config into MB registers --
        // The partner sends us how it wants us to drive our Tx (mirror of what
        // we sent in our own REQ message).
        else if(mux_if.rx_sb_msg == Start_Tx_Init_D_to_C_point_test_req && mux_if.rx_sb_msg_valid) begin
            // Error-threshold field: whose mode is it? The partner told us in rx_data_field[59].
            //   rx_data_field[59] == 0 -> per-lane comparison  -> load perlane thresh from MsgInfo
            //   rx_data_field[59] == 1 -> aggregate comparison -> load aggr thresh from MsgInfo
            mux_if.mb_rx_max_err_thresh_perlane <= (mux_if.rx_data_field[59] == 0) ? 12'(mux_if.rx_msginfo) : '0;
            mux_if.mb_rx_max_err_thresh_aggr    <= (mux_if.rx_data_field[59] == 1) ? 16'(mux_if.rx_msginfo) : '0;
            // Derive compare_setup from the partner's data field bit [59]:
            //   bit[59]==0 -> per-lane (2'b00); bit[59]==1 -> aggregate (2'b01).
            //   For valid-lane (2'b10) or clock-lane (2'b11) the partner would set
            //   bit[59]=1 but those modes are overridden by d2c_compare_setup locally;
            //   use d2c_compare_setup for modes 2 & 3 (valid/clock) as those are our
            //   own configured special modes that are not signalled differently in SB.
            mux_if.mb_rx_compare_setup <= (substate_if.d2c_compare_setup == 2'b00 ||
                substate_if.d2c_compare_setup == 2'b01) ?
                {1'b0, mux_if.rx_data_field[59]} :
                substate_if.d2c_compare_setup;
            mux_if.mb_tx_iter_count    <= mux_if.rx_data_field[58:43];
            mux_if.mb_tx_idle_count    <= mux_if.rx_data_field[42:27];
            mux_if.mb_tx_burst_count   <= mux_if.rx_data_field[26:11];
            mux_if.mb_tx_pattern_mode  <= mux_if.rx_data_field[10];
            mux_if.mb_tx_clk_sampling  <= 2'(mux_if.rx_data_field[9:6]); // Only lower 2 bits used.
            mux_if.mb_tx_val_pattern_sel <= |mux_if.rx_data_field[5:3]; // 0 if all 3 bits are 000 (VALTRAIN active), 1 otherwise (Low).
            mux_if.mb_tx_data_pattern_sel <= 2'(mux_if.rx_data_field[2:0]); // [1:0] of the 3-bit field.
        end
        // -- SB RESP from partner: extract their Rx comparison results --
        // The partner sends us the results of comparing what our Tx transmitted.
        // Per Table 7-11: MsgInfo[5]=Valid Lane, MsgInfo[4]=Cumulative, Data[15:0]=Per-lane.
        else if(mux_if.rx_sb_msg == Tx_Init_D_to_C_results_resp && mux_if.rx_sb_msg_valid == 1'b1) begin
            substate_if.d2c_val_err     <= mux_if.rx_msginfo[5];          // Bit[5]: Valid Lane comparison result.
            substate_if.d2c_aggr_err    <= {15'b0, mux_if.rx_msginfo[4]}; // Bit[4]: Aggregate error flag.
            substate_if.d2c_perlane_err <= mux_if.rx_data_field[15:0];    // Bits[15:0] of data field: per-lane error bitmap.

            // Set the valid-lane fail flag for valid-lane compare mode.
            substate_if.partner_valtraincenter_fail_flag <=
                (substate_if.d2c_compare_setup == 2'd2) ?  mux_if.rx_msginfo[5]        : // valid lane
                1'b0; // not applicable for per-lane/aggregate modes
        end
    end

endmodule
