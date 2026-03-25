
module VALVREF #(
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
        internal_ltsm_if.substate2d2c_mp d2c_if
    );
    // For analog Voltage control.
    localparam VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE);
    //reg [1:0] clk_sampling; // To know if the fsm has looped on all Clock sampling values (0h(Eye Center), 1h(Left edge), 2h(Right edge)).

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
    wire data_incoherence ;
    wire valvref_fail_flag; // To know if there is no successful Valid Receiver Vref Code.

    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    assign data_incoherence = (current_state != previous_state) ? 1'b1 : 1'b0;


    // Current State Logic of the FSM:
    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n) begin
        if (!valvref_if.rst_n) begin
            current_state  <= VALVREF_IDLE;
            previous_state <= VALVREF_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state; // We use signal to avoid data incoherence when sending SB messages. It is set to 1 for 1 lclk cycle whenever the state changes, which is when the SB Msg data is updated with new values.
        end
    end

    // Next State Logic of the FSM:
    always @(*) begin
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
                    if (d2c_if.test_d2c_done) next_state = VALVREF_LOG_RESULT;
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
                // (S7) Send & Receive SB Message: {MBTRAIN.VALVREFF end resp}. Also, drive Vref_code to the PHY MB Receiver Valid Lane.
                VALVREF_END_REQ: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_end_req && valvref_if.rx_sb_msg_valid == 1'b1) next_state = VALVREF_END_RESP;
                    else next_state = VALVREF_END_REQ;
                end
                // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
                VALVREF_END_RESP: begin
                    if (valvref_if.rx_sb_msg == MBTRAIN_VALVREF_end_resp && valvref_if.rx_sb_msg_valid == 1'b1) next_state = TO_DATAVREF;
                    else next_state = VALVREF_END_RESP;
                end
                // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
                TO_DATAVREF: begin
                    next_state = (valvref_if.valvref_en)? TO_DATAVREF : VALVREF_IDLE; // Stay here till "ltsm_if.valvref_en" is cleared.
                end
                // (S10) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = TO_TRAINERROR; // Stay in TRAINERROR state until reset.
                end
                default: begin
                    next_state = TO_TRAINERROR; // Default case to avoid latches in synthesis.
                end
            endcase
        end
    end


    // Output logic based on current state:
    always @(*) begin
        //==========================================================================//
        //              Default values for outputs (to avoid latches)               //
        //==========================================================================//

        //==========================
        // LTSM -> LTSM signals:
        //==========================
        valvref_if.valvref_done   = 1'b0;
        valvref_if.trainerror_req = 1'b0;

        //==========================
        // Timers:
        //==========================
        valvref_if.timeout_timer_en       = 1;
        valvref_if.analog_settle_timer_en = 0;

        //=================================================
        // Control Signals For (Rx init D to C point test):
        //=================================================
        d2c_if.rx_pt_en = 1'b0; // To enable Rx init Data to Clock Point Test
        d2c_if.tx_pt_en = 1'b0; // To enable Tx init Data to Clock Point Test

        // Clock sampling.
        d2c_if.d2c_clk_sampling = 2'b00;  // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge).

        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Received Tx Pattern Generator Setup Group:
        d2c_if.d2c_lfsr_en          = 1'b0  ; // 1: Enable the Tx & Rx LFSR when use the Rx or Tx FSM Test, 0: Disable the Tx & Rx LFSR.
        d2c_if.d2c_pattern_setup    = 3'b010; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        d2c_if.d2c_data_pattern_sel = 2'b00 ; // Data pattern used during training: LFSR, ID, or all 0.
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // 0: VALTRAIN pattern, 1: Held Low.

        // Received Tx Pattern Mode Setup Group:
        d2c_if.d2c_pattern_mode =  1'D0  ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        d2c_if.d2c_burst_count  = 16'D1  ; // Burst Count: Indicates the duration of selected pattern (UI count).
        d2c_if.d2c_idle_count   = 16'D0  ; // IDLE Count: Indicates the duration of low following the burst (UI count).
        d2c_if.d2c_iter_count   = 16'D128; // Iteration Count: Indicates the iteration count of bursts followed by idle.

        // Received Receiver Comparison Setup & Errors
        d2c_if.d2c_compare_setup = 2'D2; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.


        // //=========================
        // // MB signals:
        // //=========================
        // Lane Behavior Control
        valvref_if.mb_tx_clk_lane_sel  = 2'b01; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        valvref_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        valvref_if.mb_tx_val_lane_sel  = 2'b01; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        valvref_if.mb_tx_trk_lane_sel  = 2'b10; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).
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
                valvref_if.tx_sb_msg_valid = (!data_incoherence)      ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_start_req; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0                    ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0                    ; // Data field of the SB message.
            end

            // (S2) Send & Receive SB Message: {MBTRAIN.VALVREF start resp}.
            VALVREF_START_RESP: begin
                valvref_if.tx_sb_msg_valid = (!data_incoherence)       ; // Tell the SB that the selected message is valid.
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
                d2c_if.rx_pt_en = 1'b1; // To enable Rx init Data to Clock Point Test.
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
                valvref_if.tx_sb_msg_valid = (!data_incoherence)    ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_end_req; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end

            // (S8) Send & Receive SB Message: {End Rx Init D to C point test req}.
            VALVREF_END_RESP: begin
                valvref_if.tx_sb_msg_valid = (!data_incoherence)     ; // Tell the SB that the selected message is valid.
                valvref_if.tx_sb_msg       = MBTRAIN_VALVREF_end_resp; // Tell the Sideband the message that it should to send.
                valvref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                valvref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end

            // (S9) Send & Receive SB Message: {End Rx Init D to C point test resp}.
            TO_DATAVREF: begin
                valvref_if.valvref_done = 1'b1;
            end

            // (S10) TRAINERROR state:
            TO_TRAINERROR: begin
                valvref_if.valvref_done   = 1'b1;
                valvref_if.trainerror_req = 1'b1;
            end
            default: begin
                // Default case to avoid latches in synthesis.
            end
        endcase
    end


    //================================
    // Caluculate Vref Code:
    //================================
    wire [VREF_CODE_WIDTH-1:0] vref_range;
    wire [VREF_CODE_WIDTH-1:0] temp_vref_range;
    reg  [VREF_CODE_WIDTH-1:0] temp_min_vref;      // To store the start of the current valid Vref range.
    reg  [VREF_CODE_WIDTH-1:0] min_vref_code;
    reg  [VREF_CODE_WIDTH-1:0] max_vref_code;
    reg                        vref_code_filled; // To represent each "vref_code" register to know if it filled with correct data or not.

    // Get the Vref range of each clk_sampling.
    assign vref_range        = (vref_code_filled == 1'b1) ? (max_vref_code - min_vref_code) : '0;
    assign temp_vref_range   = (valvref_if.phy_rx_valvref_ctrl - temp_min_vref);
    assign valvref_fail_flag = (current_state == VALVREF_CALC_APPLY) & (~vref_code_filled);

    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n) begin : VALVREF_CALC_APPLY_PROC
        if(!valvref_if.rst_n) begin
            valvref_if.phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE; // To send (drive) the Vref value.
            // valvref_fail_flag              <= 1'b0             ; // To report if the Valid Vref calibration failed.
        end

        // This case not needed at all. I put it here to keep the module "VALVREF" more generalized and able to use it many times (not just 1 time).
        else if(current_state == VALVREF_START_REQ) begin
            valvref_if.phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE; // To send (drive) the Vref value.
            // valvref_fail_flag              <= 1'b0             ; // To report if the Valid Vref calibration failed.
        end

        // change the Vref value:
        else if(current_state == VALVREF_LOG_RESULT) begin
            if(valvref_if.phy_rx_valvref_ctrl != MAX_VAL_VREF_CODE) begin
                valvref_if.phy_rx_valvref_ctrl <= valvref_if.phy_rx_valvref_ctrl + 1;
            end
        end

        // Calculate the best Vref value:
        else if(current_state == VALVREF_CALC_APPLY) begin
            // Gets the best Vref value.
            if(vref_code_filled == 1'b1) begin
                valvref_if.phy_rx_valvref_ctrl <= ({1'b0, min_vref_code} + {1'b0, max_vref_code})>>1;
                // valvref_fail_flag <= 1'b0;
            end
            else begin
                valvref_if.phy_rx_valvref_ctrl <=   '0;
                // valvref_fail_flag              <= 1'b1; // To report if the Valid Vref calibration failed.
            end
        end
    end


    reg is_in_valid_region; // To know if we were inside a connected success zone.
    //=======================================
    // VALVREF_LOG_RESULT: Log the Vref Code:
    //=======================================
    // VALID RESULT LOG:
    always @(posedge valvref_if.lclk or negedge valvref_if.rst_n) begin : VALVREF_LOG_RESULT_PROC
        if(!valvref_if.rst_n) begin
            min_vref_code      <=   '0;
            max_vref_code      <=   '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'b0;
            temp_min_vref      <=   '0;
        end

        else if(current_state == VALVREF_START_REQ) begin
            min_vref_code      <=   '0;
            max_vref_code      <=   '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'd0;
            temp_min_vref      <=   '0;
        end

        else if(current_state == VALVREF_LOG_RESULT) begin

            // ----------------------------------------------------
            // If the result was success (No error)
            // ----------------------------------------------------
            if (!d2c_if.d2c_val_err) begin

                // Solve the problem of not stable Vref (Discontinuous Eye or Holes in the Eye Diagram).
                // 1. If we start a new connected Vref valid region (of the Eye Diagram). New Vref zone:
                if (!is_in_valid_region || valvref_if.phy_rx_valvref_ctrl == MIN_VAL_VREF_CODE) begin
                    is_in_valid_region <= 1'b1; // start new zone.
                    temp_min_vref      <= valvref_if.phy_rx_valvref_ctrl; // Save the start of the new valid Vref range.

                    if (!vref_code_filled) begin     // The 1st success point at all.
                        vref_code_filled <= 1'b1; // We consider the min Vref and the max Vref are filled with the same value.
                        min_vref_code    <= valvref_if.phy_rx_valvref_ctrl;
                        max_vref_code    <= valvref_if.phy_rx_valvref_ctrl;
                    end

                end

                // 2. If we continue within a current success zone (update if the current range is larger than the previous best range)
                else begin
                    if ((temp_vref_range) > (vref_range)) begin
                        min_vref_code <= temp_min_vref                 ;
                        max_vref_code <= valvref_if.phy_rx_valvref_ctrl;
                    end
                end
            end

            // ----------------------------------------------------------------------
            //  The result was "Fail" (Discontinuous Eye or Holes in the Eye Diagram)
            // ----------------------------------------------------------------------
            else begin
                is_in_valid_region <= 1'b0; // Break the current contnuous zone (to star storing new region later if there was a success).
            end
        end
    end


endmodule