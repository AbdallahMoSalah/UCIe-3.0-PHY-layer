module unit_VALVREF #(
        parameter MAX_VAL_VREF_CODE   = 7'D127,
        parameter MIN_VAL_VREF_CODE   = 7'D10
    ) (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.valvref_mp valvref_if,
        // ======================= //
        // D2C signals.            //
        // ======================= //
        internal_ltsm_if.mbtrain2d2c_mp d2c_if
    );
    // D2C pattern test configuration.
    // Spec defaults: 128 iterations × 8-cycle burst.
    localparam D2C_ITER_COUNT      = 16'D128;
    localparam D2C_BURST_COUNT     = 16'D8;
    // For analog Voltage control.
    localparam VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE + 1); // kept for documentation; sweep logic lives in unit_val_sweep.
    //reg [1:0] clk_sampling; // To know the Tx Clock sampling values (0h(Eye Center), 1h(Left edge), 2h(Right edge)).
    // To get the used SB messages for: (valvref_if.tx_sb_msg, sb_it.rx_sb_msg)
    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_VALVREF_start_req ; // Msg Number: d35
    import UCIe_pkg::MBTRAIN_VALVREF_start_resp; // Msg Number: d36
    import UCIe_pkg::MBTRAIN_VALVREF_end_req   ; // Msg Number: d37
    import UCIe_pkg::MBTRAIN_VALVREF_end_resp  ; // Msg Number: d38
    import UCIe_pkg::TRAINERROR_Entry_req      ; // Msg Number: d107
    import UCIe_pkg::NOTHING                   ; // Msg Number: 8'hFF
    // States names
    localparam  VALVREF_IDLE          = 4'h0, // (S0)
    VALVREF_START_REQ     = 4'h1, // (S1)
    VALVREF_START_RESP    = 4'h2, // (S2)
    VALVREF_SET_VREF_CODE = 4'h3, // (S3)
    VALVREF_RX_D2C_PT     = 4'h4, // (S4)
    VALVREF_LOG_RESULT    = 4'h5, // (S5)
    VALVREF_CALC_APPLY    = 4'h6, // (S6)
    VALVREF_END_REQ       = 4'h7, // (S7)
    VALVREF_END_RESP      = 4'h8, // (S8)
    TO_DATAVREF           = 4'h9, // (S9)
    TO_TRAINERROR         = 4'hA; // (S10)
    reg [3:0] current_state, next_state, previous_state; // The Current, Next states, and Previous state of the FSM.
    wire valvref_fail_flag; // To know if there is no successful Valid Receiver Vref Code.
    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    wire is_tx_sb_msg_valid;
    assign is_tx_sb_msg_valid =
        (current_state != previous_state) && (
            (current_state == VALVREF_START_REQ ) ||
            (current_state == VALVREF_START_RESP) ||
            (current_state == VALVREF_END_REQ   ) ||
            (current_state == VALVREF_END_RESP  ) );


    // >> =====================  For the VALVREF stuck issue (To fix the issue of waiting for the SB message)  ===================== << //
    reg end_req_sb_msg_rcvd       ; // To detect the `end_req` SB MSG after the D2C_PT state. this is a flag.
    reg ready_for_end_resp_sb_msg ; // To detect the `ready_for_end_resp` after the D2C_PT state. this is a flag.
    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n) begin : AFTER_D2C_PT_SB_MSGS
        if(!valvref_if.rst_n) begin
            end_req_sb_msg_rcvd       <= 1'b0;
            ready_for_end_resp_sb_msg <= 1'b0;
        end
        else if (current_state == VALVREF_IDLE) begin // Reset the register once the LTSM gets out of reset.
            ready_for_end_resp_sb_msg <= 1'b0;
            end_req_sb_msg_rcvd       <= 1'b0;
        end
        else if(   (current_state == VALVREF_SET_VREF_CODE ||
                    current_state == VALVREF_RX_D2C_PT     ||
                    current_state == VALVREF_LOG_RESULT    ||
                    current_state == VALVREF_CALC_APPLY    ||
                    current_state == VALVREF_END_REQ       ) &&
                valvref_if.rx_sb_msg == MBTRAIN_VALVREF_end_req && valvref_if.rx_sb_msg_valid == 1'b1) begin
            end_req_sb_msg_rcvd <= 1'b1;
        end
        else if (current_state == VALVREF_END_REQ && (end_req_sb_msg_rcvd || (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_end_req && valvref_if.rx_sb_msg_valid == 1'b1))) begin
            // Since we can't send 2 consecutive pulses on the signal `is_tx_sb_msg_valid` without a `0` in between for 1 lclk at least;
            // When this scenario happens when the partner Die applies less RX_D2C_PT iterations than our Die.
            // If we assume we won't use the `end_req_sb_msg_rcvd` signal, the FSM flow (in our Die) will be:
            //      [loop] -> 'VALVREF_RX_D2C_PT' -> 'VALVREF_LOG_RESULT' -> 'VALVREF_CALC_APPLY' -> 'VALVREF_END_REQ' (for 1 lclk duration) -> 'VALVREF_END_RESP'
            // We need this signal `ready_for_end_resp_sb_msg` extend the waiting time to wait 2 lclk cycles at least in the FSM state 'VALVREF_END_REQ' instead 1 lclk duration:
            //      1 lclk cycle for the HIGH period of the pulse.
            //      1 lclk cycle for the LOW  period of the pulse.
            ready_for_end_resp_sb_msg <= 1'b1;
        end
    end

    // >> =====================  For the RX_D2C_PT local-partner modules seperation  ===================== << //
    assign d2c_if.partner_tx_pt_en = 1'b0;
    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n)
    begin
        if(!valvref_if.rst_n) begin
            d2c_if.partner_rx_pt_en <= 1'b0;
        end
        else if(current_state == VALVREF_IDLE || current_state == VALVREF_END_RESP) begin // To force the synchronization when we send and receive the {... end req} SB message.
            d2c_if.partner_rx_pt_en <= 1'b0;
        end
        else if(current_state == VALVREF_SET_VREF_CODE ||
                current_state == VALVREF_RX_D2C_PT     ||
                current_state == VALVREF_LOG_RESULT    ||
                current_state == VALVREF_CALC_APPLY    ||
                current_state == VALVREF_END_REQ       ) begin
            if(d2c_if.partner_test_d2c_done) begin
                d2c_if.partner_rx_pt_en <= 1'b0;
            end else begin
                d2c_if.partner_rx_pt_en <= 1'b1;
            end
        end
    end
    // >> ===================== * ================================================ * ===================== << //

    // Current State Logic of the FSM:
    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n) begin
        if (!valvref_if.rst_n) begin
            current_state  <= VALVREF_IDLE;
            previous_state <= VALVREF_IDLE;
        end
        else if (!valvref_if.is_ltsm_out_of_reset) begin
            current_state  <= VALVREF_IDLE;
            previous_state <= VALVREF_IDLE;
        end
        else begin
            current_state  <= next_state   ;
            previous_state <= current_state;
        end
    end
    // Next State Logic of the FSM:
    always_comb begin
        if(valvref_if.timeout_8ms_occured | (valvref_if.rx_sb_msg == TRAINERROR_Entry_req && valvref_if.rx_sb_msg_valid == 1'b1) | valvref_fail_flag) begin
            // (S10)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start VALVREF FSM.
                VALVREF_IDLE: begin
                    if (valvref_if.valvref_en) next_state = VALVREF_START_REQ;
                    else next_state = VALVREF_IDLE;
                end
                // (S1) Send & Receive SB Message: {MBTRAIN.VALVREFF start req}
                VALVREF_START_REQ: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_start_req && valvref_if.rx_sb_msg_valid == 1'b1) next_state = VALVREF_START_RESP;
                    else next_state = VALVREF_START_REQ;
                end
                // (S2) Send & Receive SB Message: {MBTRAIN.VALVREFF start resp}.
                VALVREF_START_RESP: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_start_resp && valvref_if.rx_sb_msg_valid == 1'b1) next_state = VALVREF_SET_VREF_CODE;
                    else next_state = VALVREF_START_RESP;
                end
                // (S3) Drive Vref (vref_code) to PHY MB Receiver Valid Lane.
                VALVREF_SET_VREF_CODE: begin
                    if (valvref_if.analog_settle_time_done) next_state = VALVREF_RX_D2C_PT;
                    else next_state = VALVREF_SET_VREF_CODE;
                end
                // (S4) Implement the test (Rx Init Data to Clock Point Test).
                VALVREF_RX_D2C_PT: begin
                    // if (d2c_if.d2c_timeout_or_error) next_state = TO_TRAINERROR;
                    if (d2c_if.local_test_d2c_done) next_state = VALVREF_LOG_RESULT;
                    else next_state = VALVREF_RX_D2C_PT;
                end
                // (S5) Log the current vref_code value if the received pattern on MB Receiver is valid.
                VALVREF_LOG_RESULT: begin
                    if (valvref_if.phy_rx_valvref_ctrl == MAX_VAL_VREF_CODE) next_state = VALVREF_CALC_APPLY;
                    else next_state = VALVREF_SET_VREF_CODE;
                end
                // (S6) Caluculate the best value for vref_code.
                VALVREF_CALC_APPLY: begin
                    next_state = VALVREF_END_REQ;
                end
                // (S7) Send & Receive SB Message: {MBTRAIN.VALVREFF end req}. Also, drive Vref_code to the PHY MB Receiver Valid Lane.
                VALVREF_END_REQ: begin
                    // if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_end_req && valvref_if.rx_sb_msg_valid == 1'b1) next_state = VALVREF_END_RESP;
                    // We need to store if the {MBTRAIN.VALVREFF end req} SB Message has received while the partner still in the test RX_D2C_PT, so we use `end_req_sb_msg_rcvd`.
                    if (end_req_sb_msg_rcvd && ready_for_end_resp_sb_msg) next_state = VALVREF_END_RESP;
                    else next_state = VALVREF_END_REQ;
                end
                // (S8) Send & Receive SB Message: {MBTRAIN.VALVREFF end resp}.
                VALVREF_END_RESP: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_end_resp && valvref_if.rx_sb_msg_valid == 1'b1) next_state = TO_DATAVREF;
                    else next_state = VALVREF_END_RESP;
                end
                // (S9) Waiting to exit to DATAVREF substate.
                TO_DATAVREF: begin
                    next_state = (valvref_if.valvref_en)? TO_DATAVREF : VALVREF_IDLE; // Stay here till "valvref_if.valvref_en" is cleared.
                end
                // (S10) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = (valvref_if.valvref_en) ? TO_TRAINERROR : VALVREF_IDLE;
                end
                default: begin
                    next_state = (valvref_if.valvref_en) ? TO_TRAINERROR : VALVREF_IDLE; // Default case to avoid latches in synthesis.
                end
            endcase
        end
    end
    // Output logic based on current state:
    always_comb begin
        //==========================================================================//
        //              Default values for outputs (to avoid latches)               //
        //==========================================================================//
        //==========================
        // LTSM -> LTSM signals:
        //==========================
        valvref_if.valvref_done   = 1'b0;
        valvref_if.trainerror_req = 1'b0;
        valvref_if.update_lane_mask = 1'b0;
        //==========================
        // Timers:
        //==========================
        valvref_if.timeout_timer_en       = 1;
        valvref_if.analog_settle_timer_en = 0;
        //=================================================
        // Control Signals For (Rx init D to C point test):
        //=================================================
        d2c_if.local_rx_pt_en = 1'b0; // To enable Rx init Data to Clock Point Test
        d2c_if.local_tx_pt_en = 1'b0; // To enable Tx init Data to Clock Point Test
        // Clock sampling.
        d2c_if.d2c_clk_sampling = 2'b00;  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Received Tx Pattern Generator Setup Group:
        d2c_if.d2c_pattern_setup    = 3'b010; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        d2c_if.d2c_data_pattern_sel = 2'b11 ; // Data pattern used during training: LFSR, ID, or all 0.
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // 0: VALTRAIN pattern, 1: Held Low.
        // Received Tx Pattern Mode Setup Group:
        d2c_if.d2c_pattern_mode =  1'D0  ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        d2c_if.d2c_burst_count  = D2C_BURST_COUNT; // Burst Count: Indicates the duration of selected pattern (UI count).
        d2c_if.d2c_idle_count   = 16'D0          ; // IDLE Count: Indicates the duration of low following the burst (UI count).
        d2c_if.d2c_iter_count   = D2C_ITER_COUNT ; // Iteration Count: Indicates the iteration count of bursts followed by idle.
        // Received Receiver Comparison Setup & Errors
        d2c_if.d2c_compare_setup = 2'D2; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.
        // //=========================
        // // MB signals:
        // //=========================
        // Lane Behavior Control
        valvref_if.mb_tx_clk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 10b: Tri-state (Tx Logical Clock Lane).
        valvref_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low, 01b: Active, 10b: Tri-state (Tx Logical Data Lanes).
        valvref_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 10b: Tri-state (Tx Logical Valid Lane).
        valvref_if.mb_tx_trk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 10b: Tri-state (Tx Logical Track Lane).
        valvref_if.mb_rx_clk_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        valvref_if.mb_rx_data_lane_sel = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        valvref_if.mb_rx_val_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        valvref_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).
        //============================
        // SB signals:
        //============================
        // For SB TX:
        valvref_if.tx_sb_msg_valid = 1'h0   ; // Tell the SB that the selected message is valid.
        valvref_if.tx_sb_msg       = NOTHING; // Tell the Sideband the message that it should to send.
        valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
        valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state: Wait for the trigger to start VALVREF FSM.
            VALVREF_IDLE: begin
                //Nothing special
                valvref_if.timeout_timer_en = 0;
            end
            // (S1) Send & Receive SB Message: {MBTRAIN.VALVREF start req}
            VALVREF_START_REQ: begin
                valvref_if.update_lane_mask = 1'b1; // Tell the MBTRAIN.REPAIR substate to update the value of "mb_(rx/tx)_data_lane_mask" to take the value of "mbinit_(rx/tx)_data_lane_mask". It's used in the begining of the MBTRAIN.

                valvref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)      ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_start_req; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0                    ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0                    ; // Data field of the SB message.
            end
            // (S2) Send & Receive SB Message: {MBTRAIN.VALVREF start resp}.
            VALVREF_START_RESP: begin
                valvref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)       ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_start_resp; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S3) Drive Vref (vref_code) to PHY MB Receiver Valid Lane.
            VALVREF_SET_VREF_CODE: begin
                valvref_if.analog_settle_timer_en = 1;
            end
            // (S4) Implement the test (Rx Init Data to Clock Point Test).
            VALVREF_RX_D2C_PT: begin
                //=================================================
                // Control Signals For (Rx init D to C point test):
                //=================================================
                d2c_if.local_rx_pt_en = 1'b1; // To enable Rx init Data to Clock Point Test.
            end
            // (S5) Log the current vref_code value if the received pattern on MB Receiver is valid.
            VALVREF_LOG_RESULT: begin
                // There is only sequential logic here. we just log Vref of Valid lane (if was no valid lane error).
                // look at "VALVREF_LOG_RESULT_PROC" always block below.
            end
            // (S6) Caluculate the best value for vref_code.
            VALVREF_CALC_APPLY: begin
                // There is only sequential logic here. we calculate the best Vref value.
                // look at "VALVREF_CALC_APPLY_PROC" always block below.
            end
            // (S7) Send & Receive SB Message: {MBTRAIN.VALVREFF end resp}. Also, drive Vref_code to the PHY MB Receiver Valid Lane.
            VALVREF_END_REQ: begin
                valvref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)    ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_end_req; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
            VALVREF_END_RESP: begin
                valvref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)     ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_end_resp; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
            TO_DATAVREF: begin
                valvref_if.valvref_done     = 1'b1;
                valvref_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end
            // (S10) TRAINERROR state:
            TO_TRAINERROR: begin
                valvref_if.valvref_done     = 1'b1;
                valvref_if.trainerror_req   = 1'b1;
                valvref_if.timeout_timer_en = 1'b0;
            end
            default: begin
                // Default case to avoid latches in synthesis.
            end
        endcase
    end
    // =====================================================================
    // Vref Sweep Datapath — delegated to unit_val_sweep
    //
    // unit_val_sweep owns:
    //   - phy_rx_valvref_ctrl (swept code during S3-S5; best midpoint after S6)
    //   - valvref_fail_flag   (1 when CALC_APPLY finds no passing Vref code)
    //   - Two-zone eye-map tracking registers
    // =====================================================================
    unit_val_sweep #(
        .MAX_VAL_VREF_CODE(MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE(MIN_VAL_VREF_CODE)
    ) u_val_sweep (
        .lclk                 (valvref_if.lclk                     ),
        .rst_n                (valvref_if.rst_n                    ),
        .is_ltsm_out_of_reset (valvref_if.is_ltsm_out_of_reset     ),
        .start_req_state      (current_state == VALVREF_START_REQ  ),
        .log_result_state     (current_state == VALVREF_LOG_RESULT ),
        .calc_apply_state     (current_state == VALVREF_CALC_APPLY ),
        .d2c_val_pass         (d2c_if.d2c_val_pass                 ),
        .phy_rx_valvref_ctrl  (valvref_if.phy_rx_valvref_ctrl      ),
        .valvref_fail_flag    (valvref_fail_flag                   )
    );

endmodule
