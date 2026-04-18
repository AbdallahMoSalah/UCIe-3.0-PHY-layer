// =============================================================================
// Module  : unit_VALTRAINCENTER
// Purpose : MBTRAIN.VALTRAINCENTER sub-state FSM.
//           Performs valid-to-clock training to find the optimal phase centering
//           for the valid signal relative to the clock.
//           SB message payloads match UCIe Spec Rev 3.0 Chapter 7 Table 7-9.
// =============================================================================

module unit_VALTRAINCENTER #(
        parameter MAX_PHASE_CODE = 6'd63,
        parameter MIN_PHASE_CODE = 6'd0
    ) (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.valtraincenter_mp valtraincenter_if,

        // ======================= //
        // D2C signals.            //
        // ======================= //
        internal_ltsm_if.substate2d2c_mp d2c_if
    );
    // For Phase control
    localparam PHASE_CODE_WIDTH = $clog2(MAX_PHASE_CODE + 1);

    // Assumed threshold for finding a successful valid eye region.
    localparam VAL_SUCCESS_RANGE = 5;

    // To get the used SB messages
    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_VALTRAINCENTER_start_req ; // Msg Number: d53
    import UCIe_pkg::MBTRAIN_VALTRAINCENTER_start_resp; // Msg Number: d54
    import UCIe_pkg::MBTRAIN_VALTRAINCENTER_done_req  ; // Msg Number: d55
    import UCIe_pkg::MBTRAIN_VALTRAINCENTER_done_resp ; // Msg Number: d56
    import UCIe_pkg::TRAINERROR_Entry_req             ; // Msg Number: d107
    import UCIe_pkg::NOTHING                          ; // Msg Number: 8'hFF

    // States names
    localparam  VALTRAINCENTER_IDLE          = 4'h0, // (S0)
    VALTRAINCENTER_START_REQ     = 4'h1, // (S1)
    VALTRAINCENTER_START_RESP    = 4'h2, // (S2)
    VALTRAINCENTER_SET_PHASE     = 4'h3, // (S3)
    VALTRAINCENTER_TX_D2C_PT     = 4'h4, // (S4)
    VALTRAINCENTER_LOG_RESULT    = 4'h5, // (S5)
    VALTRAINCENTER_CALC_APPLY    = 4'h6, // (S6)
    VALTRAINCENTER_DONE_REQ      = 4'h7, // (S7)
    VALTRAINCENTER_DONE_RESP     = 4'h8, // (S8)
    TO_VALTRAINVREF              = 4'h9, // (S9)
    TO_TRAINERROR                = 4'hA; // (S10)

    reg [3:0] current_state, next_state, previous_state; // The Current, Next states, and Previous state of the FSM.
    wire data_incoherence ;

    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    assign data_incoherence = (current_state != previous_state) ? 1'b1 : 1'b0;


    // Current State Logic of the FSM:
    always @(posedge valtraincenter_if.lclk or negedge valtraincenter_if.rst_n) begin
        if (!valtraincenter_if.rst_n) begin
            current_state  <= VALTRAINCENTER_IDLE;
            previous_state <= VALTRAINCENTER_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // Next State Logic of the FSM:
    always @(*) begin
        if(valtraincenter_if.timeout_8ms_occured | (valtraincenter_if.rx_sb_msg == TRAINERROR_Entry_req && valtraincenter_if.rx_sb_msg_valid == 1'b1)) begin
            // (S10)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start VALTRAINCENTER FSM.
                VALTRAINCENTER_IDLE: begin
                    if (valtraincenter_if.valtraincenter_en) next_state = VALTRAINCENTER_START_REQ;
                    else next_state = VALTRAINCENTER_IDLE;
                end
                // (S1) Send & Receive SB Message: {MBTRAIN.VALTRAINCENTER start req}
                VALTRAINCENTER_START_REQ: begin
                    if (valtraincenter_if.rx_sb_msg == MBTRAIN_VALTRAINCENTER_start_req && valtraincenter_if.rx_sb_msg_valid == 1'b1) next_state = VALTRAINCENTER_START_RESP;
                    else next_state = VALTRAINCENTER_START_REQ;
                end
                // (S2) Wait for SB Message: {MBTRAIN.VALTRAINCENTER start resp} from partner.
                VALTRAINCENTER_START_RESP: begin
                    if (valtraincenter_if.rx_sb_msg == MBTRAIN_VALTRAINCENTER_start_resp && valtraincenter_if.rx_sb_msg_valid == 1'b1) next_state = VALTRAINCENTER_SET_PHASE;
                    else next_state = VALTRAINCENTER_START_RESP;
                end
                // (S3) Drive phase_code to PHY Tx PI Phase Ctrl. Wait for analog_settle_timer.
                VALTRAINCENTER_SET_PHASE: begin
                    if (valtraincenter_if.analog_settle_time_done) next_state = VALTRAINCENTER_TX_D2C_PT;
                    else next_state = VALTRAINCENTER_SET_PHASE;
                end
                // (S4) Implement the test (Tx Init Data to Clock Point Test).
                VALTRAINCENTER_TX_D2C_PT: begin
                    if (d2c_if.test_d2c_done) next_state = VALTRAINCENTER_LOG_RESULT;
                    else next_state = VALTRAINCENTER_TX_D2C_PT;
                end
                // (S5) Log the current phase_code value if the received pattern on MB Receiver is valid.
                VALTRAINCENTER_LOG_RESULT: begin
                    if (valtraincenter_if.phy_tx_pi_phase_ctrl == MAX_PHASE_CODE) next_state = VALTRAINCENTER_CALC_APPLY;
                    else next_state = VALTRAINCENTER_SET_PHASE;
                end
                // (S6) Calculate the best value for phase_code and apply it. Wait for analog settle timer.
                VALTRAINCENTER_CALC_APPLY: begin
                    if (valtraincenter_if.analog_settle_time_done) next_state = VALTRAINCENTER_DONE_REQ;
                    else next_state = VALTRAINCENTER_CALC_APPLY;
                end
                // (S7) Send & Receive SB Message: {MBTRAIN.VALTRAINCENTER done req}.
                VALTRAINCENTER_DONE_REQ: begin
                    if (valtraincenter_if.rx_sb_msg == MBTRAIN_VALTRAINCENTER_done_req && valtraincenter_if.rx_sb_msg_valid == 1'b1) next_state = VALTRAINCENTER_DONE_RESP;
                    else next_state = VALTRAINCENTER_DONE_REQ;
                end
                // (S8) Send & Receive SB Message: {MBTRAIN.VALTRAINCENTER done resp}.
                VALTRAINCENTER_DONE_RESP: begin
                    if (valtraincenter_if.rx_sb_msg == MBTRAIN_VALTRAINCENTER_done_resp && valtraincenter_if.rx_sb_msg_valid == 1'b1) next_state = TO_VALTRAINVREF;
                    else next_state = VALTRAINCENTER_DONE_RESP;
                end
                // (S9) Move to VALTRAINVREF.
                TO_VALTRAINVREF: begin
                    next_state = (valtraincenter_if.valtraincenter_en)? TO_VALTRAINVREF : VALTRAINCENTER_IDLE; // Stay here till "ltsm_if.valtraincenter_en" is cleared.
                end
                // (S10) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = (valtraincenter_if.valtraincenter_en)? TO_TRAINERROR : VALTRAINCENTER_IDLE;
                end
                default: begin
                    next_state = (valtraincenter_if.valtraincenter_en)? TO_TRAINERROR : VALTRAINCENTER_IDLE; // Default case to avoid latches in synthesis.
                end
            endcase
        end
    end


    // Output logic based on current state:
    always @(*) begin
        //==========================
        // LTSM -> LTSM signals:
        //==========================
        valtraincenter_if.valtraincenter_done   = 1'b0;
        valtraincenter_if.trainerror_req        = 1'b0;

        //==========================
        // Timers:
        //==========================
        valtraincenter_if.timeout_timer_en       = 1;
        valtraincenter_if.analog_settle_timer_en = 0;

        //=================================================
        // Control Signals For D2C point test
        //=================================================
        d2c_if.rx_pt_en = 1'b0;
        d2c_if.tx_pt_en = 1'b0;

        // Clock sampling.
        d2c_if.d2c_clk_sampling = 2'b00;  // Clock Phase control: 0h(Eye Center)

        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Received Tx Pattern Generator Setup Group:
        d2c_if.d2c_lfsr_en          = 1'b0  ; // Disable LFSR.
        d2c_if.d2c_pattern_setup    = 3'b010; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        d2c_if.d2c_data_pattern_sel = 2'b11 ; // Data pattern used during training: 2'b11 is "0" (all zeros)
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // 0: VALTRAIN pattern

        // Received Tx Pattern Mode Setup Group:
        d2c_if.d2c_pattern_mode =  1'D0   ; // 0: Continuous Pattern Mode
        d2c_if.d2c_burst_count  = 16'D8   ; // Burst Count: 8 UI (11110000)
        d2c_if.d2c_idle_count   = 16'D0   ; // IDLE Count: 0
        d2c_if.d2c_iter_count   = 16'D128 ; // Iteration Count: 1

        // Received Receiver Comparison Setup & Errors
        d2c_if.d2c_compare_setup = 2'D2; // 2: Valid Lane Comparison.

        // //=========================
        // // MB signals:
        // //=========================
        // Lane Behavior Control
        valtraincenter_if.mb_tx_clk_lane_sel  = 2'b01; // Active Clock Lane
        valtraincenter_if.mb_tx_data_lane_sel = 2'b00; // Low (Force Tx Data Lanes to Logic 0)
        valtraincenter_if.mb_tx_val_lane_sel  = 2'b01; // Active Valid Lane
        valtraincenter_if.mb_tx_trk_lane_sel  = 2'b00; // Low (Logic 0)

        valtraincenter_if.mb_rx_clk_lane_sel  = 1'b1 ; // Enabled Clock Rx
        valtraincenter_if.mb_rx_data_lane_sel = 1'b0 ; // Disabled
        valtraincenter_if.mb_rx_val_lane_sel  = 1'b1 ; // Enabled Valid Lane Rx
        valtraincenter_if.mb_rx_trk_lane_sel  = 1'b0 ; // Disabled

        //============================
        // SB signals:
        //============================
        valtraincenter_if.tx_sb_msg_valid = 1'h0   ;
        valtraincenter_if.tx_sb_msg       = NOTHING;
        valtraincenter_if.tx_msginfo      = 16'h0  ;
        valtraincenter_if.tx_data_field   = 64'h0  ;

        case (current_state)
            // (S0) IDLE state:
            VALTRAINCENTER_IDLE: begin
                valtraincenter_if.timeout_timer_en = 0;
            end

            // (S1) Send & Receive SB Message: {MBTRAIN.VALTRAINCENTER start req}
            VALTRAINCENTER_START_REQ: begin
                valtraincenter_if.tx_sb_msg_valid = (!data_incoherence)      ;
                valtraincenter_if.tx_sb_msg       = MBTRAIN_VALTRAINCENTER_start_req;
            end

            // (S2) Send & Receive SB Message: {MBTRAIN.VALTRAINCENTER start resp}.
            VALTRAINCENTER_START_RESP: begin
                valtraincenter_if.tx_sb_msg_valid = (!data_incoherence)       ;
                valtraincenter_if.tx_sb_msg       = MBTRAIN_VALTRAINCENTER_start_resp;
            end

            // (S3) Drive Phase_code to PHY. Let analog settle.
            VALTRAINCENTER_SET_PHASE: begin
                valtraincenter_if.analog_settle_timer_en = 1;
            end

            // (S4) Implement the test (Tx Init Data to Clock Point Test).
            VALTRAINCENTER_TX_D2C_PT: begin
                d2c_if.tx_pt_en = 1'b1; // Trigger "Tx Initiated Data to Clock Point Test"
            end

            // (S5) Log the current phase_code
            VALTRAINCENTER_LOG_RESULT: begin
                // Sequential logic handled in VALTRAINCENTER_LOG_RESULT_PROC
            end

            // (S6) Caluculate and Apply the best value for phase_code.
            VALTRAINCENTER_CALC_APPLY: begin
                valtraincenter_if.analog_settle_timer_en = 1; // Wait for analog_settle_timer after applying average
            end

            // (S7) Send & Receive SB Message: {MBTRAIN.VALTRAINCENTER done req}.
            VALTRAINCENTER_DONE_REQ: begin
                valtraincenter_if.tx_sb_msg_valid = (!data_incoherence)    ;
                valtraincenter_if.tx_sb_msg       = MBTRAIN_VALTRAINCENTER_done_req;
            end

            // (S8) Send & Receive SB Message: {MBTRAIN.VALTRAINCENTER done resp}.
            VALTRAINCENTER_DONE_RESP: begin
                valtraincenter_if.tx_sb_msg_valid = (!data_incoherence)     ;
                valtraincenter_if.tx_sb_msg       = MBTRAIN_VALTRAINCENTER_done_resp;
            end

            // (S9) done.
            TO_VALTRAINVREF: begin
                valtraincenter_if.valtraincenter_done = 1'b1;
                valtraincenter_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end

            // (S10) TRAINERROR state:
            TO_TRAINERROR: begin
                valtraincenter_if.valtraincenter_done = 1'b1;
                valtraincenter_if.trainerror_req      = 1'b1;
                valtraincenter_if.timeout_timer_en    = 1'b0;   // Disable timer in trainerror
            end
            default: begin
            end
        endcase
    end


    //================================
    // Caluculate Phase Code:
    //================================
    wire [PHASE_CODE_WIDTH-1:0] phase_range;
    wire [PHASE_CODE_WIDTH-1:0] temp_phase_range;
    reg  [PHASE_CODE_WIDTH-1:0] temp_min_phase;      // To store the start of the current valid Phase range.
    reg  [PHASE_CODE_WIDTH-1:0] min_phase_code;
    reg  [PHASE_CODE_WIDTH-1:0] max_phase_code;
    reg                         phase_code_filled;   // To represent each "phase_code" register to know if it filled with correct data or not.


    // Get the Phase range
    assign phase_range        = (phase_code_filled == 1'b1) ? (max_phase_code - min_phase_code) : '0;
    assign temp_phase_range   = (valtraincenter_if.phy_tx_pi_phase_ctrl - temp_min_phase);

    // We assign valtraincenter_fail_flag here directly. It goes back to main FSM.
    assign valtraincenter_if.valtraincenter_fail_flag = (current_state == VALTRAINCENTER_CALC_APPLY) & (~phase_code_filled | (phase_range < VAL_SUCCESS_RANGE));

    always @(posedge valtraincenter_if.lclk or negedge valtraincenter_if.rst_n) begin : VALTRAINCENTER_CALC_APPLY_PROC
        if(!valtraincenter_if.rst_n) begin
            valtraincenter_if.phy_tx_pi_phase_ctrl <= MIN_PHASE_CODE;
        end
        else if(current_state == VALTRAINCENTER_START_REQ) begin
            valtraincenter_if.phy_tx_pi_phase_ctrl <= MIN_PHASE_CODE;
        end
        // change the Phase value:
        else if(current_state == VALTRAINCENTER_LOG_RESULT) begin
            if(valtraincenter_if.phy_tx_pi_phase_ctrl != MAX_PHASE_CODE) begin
                valtraincenter_if.phy_tx_pi_phase_ctrl <= valtraincenter_if.phy_tx_pi_phase_ctrl + 1;
            end
        end
        // Calculate the best Phase value:
        else if(current_state == VALTRAINCENTER_CALC_APPLY) begin
            if(phase_code_filled == 1'b1) begin
                valtraincenter_if.phy_tx_pi_phase_ctrl <= ({1'b0, min_phase_code} + {1'b0, max_phase_code})>>1;
            end
            else begin
                valtraincenter_if.phy_tx_pi_phase_ctrl <= '0;
            end
        end
    end


    reg is_in_valid_region;
    //=============================================
    // VALTRAINCENTER_LOG_RESULT: Log the Phase Code:
    //=============================================
    always @(posedge valtraincenter_if.lclk or negedge valtraincenter_if.rst_n) begin : VALTRAINCENTER_LOG_RESULT_PROC
        if(!valtraincenter_if.rst_n) begin
            min_phase_code     <=   '0;
            max_phase_code     <=   '0;
            phase_code_filled  <= 1'b0;
            is_in_valid_region <= 1'b0;
            temp_min_phase     <=   '0;
        end
        else if(current_state == VALTRAINCENTER_START_REQ) begin
            min_phase_code     <=   '0;
            max_phase_code     <=   '0;
            phase_code_filled  <= 1'b0;
            is_in_valid_region <= 1'b0;
            temp_min_phase     <=   '0;
        end
        else if(current_state == VALTRAINCENTER_LOG_RESULT) begin
            // If the result was success (No error)
            if (!d2c_if.d2c_val_err) begin
                if (!is_in_valid_region || valtraincenter_if.phy_tx_pi_phase_ctrl == MIN_PHASE_CODE) begin
                    is_in_valid_region <= 1'b1;
                    temp_min_phase     <= valtraincenter_if.phy_tx_pi_phase_ctrl;

                    if (!phase_code_filled) begin
                        phase_code_filled <= 1'b1;
                        min_phase_code    <= valtraincenter_if.phy_tx_pi_phase_ctrl;
                        max_phase_code    <= valtraincenter_if.phy_tx_pi_phase_ctrl;
                    end
                end
                else begin
                    if ((temp_phase_range) > (phase_range)) begin
                        min_phase_code <= temp_min_phase;
                        max_phase_code <= valtraincenter_if.phy_tx_pi_phase_ctrl;
                    end
                end
            end
            // The result was "Fail"
            else begin
                is_in_valid_region <= 1'b0;
            end
        end
    end

endmodule
