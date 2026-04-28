module unit_SPEEDIDLE #() (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.speedidle_mp speedidle_if
    );

    import UCIe_pkg::MBTRAIN_SPEEDIDLE_done_req ; // Msg Number: d43
    import UCIe_pkg::MBTRAIN_SPEEDIDLE_done_resp; // Msg Number: d44
    import UCIe_pkg::TRAINERROR_Entry_req       ; // Msg Number: d107
    import UCIe_pkg::NOTHING                    ; // Msg Number: 8'hFF

    // States names
    localparam  SPEEDIDLE_IDLE           = 4'h0, // (S0)
    SPEEDIDLE_CONFIG_SPEED   = 4'h1, // (S1)
    SPEEDIDLE_WAIT_PLL_LOCK  = 4'h2, // (S2)
    SPEEDIDLE_DONE_REQ       = 4'h3, // (S3)
    SPEEDIDLE_DONE_RESP      = 4'h4, // (S4)
    TO_TXSELFCAL             = 4'h5, // (S5)
    TO_TRAINERROR            = 4'h6; // (S6)

    reg [3:0] current_state, next_state, previous_state;
    wire data_incoherence ;

    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    assign data_incoherence = (current_state != previous_state) ? 1'b1 : 1'b0;

    reg [2:0] internal_phy_negotiated_speed; // Target Link Speed (0h: 4 GT/s; 1h: 8 GT/s; 2h: 12 GT/s; ... ; or 7h: 64 GT/s)
    assign speedidle_if.phy_negotiated_speed = internal_phy_negotiated_speed; // connect the internal wire to the interface.

    // Condition to check if speed degrade is not possible because we are already at minimum speed (4 GT/s)
    wire speed_degrade_error = (speedidle_if.state_n[1] == ltsm_state_n_pkg::LOG_MBTRAIN_LINKSPEED ||
        speedidle_if.state_n[1] == ltsm_state_n_pkg::LOG_PHYRETRAIN) &&
        (internal_phy_negotiated_speed == 3'b000);

    // Current State Logic & Speed memory handling
    always @(posedge speedidle_if.lclk or negedge speedidle_if.rst_n) begin
        if (!speedidle_if.rst_n) begin
            current_state  <= SPEEDIDLE_IDLE;
            previous_state <= SPEEDIDLE_IDLE;
            internal_phy_negotiated_speed <= 3'b000;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;

            // Speed logic based on the spec when transitioning from IDLE to processing SPEEDIDLE
            if (current_state == SPEEDIDLE_CONFIG_SPEED) begin
                if (speedidle_if.state_n[1] == ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF) begin
                    internal_phy_negotiated_speed <= speedidle_if.param_negotiated_max_speed;
                end else if (speedidle_if.state_n[1] == ltsm_state_n_pkg::LOG_L1_L2) begin
                    // restore last active speed - assumed retained currently
                    internal_phy_negotiated_speed <= internal_phy_negotiated_speed;
                end else if (speedidle_if.state_n[1] == ltsm_state_n_pkg::LOG_MBTRAIN_LINKSPEED ||
                        speedidle_if.state_n[1] == ltsm_state_n_pkg::LOG_PHYRETRAIN) begin
                    if (internal_phy_negotiated_speed != 3'b000) begin
                        internal_phy_negotiated_speed <= internal_phy_negotiated_speed - 1'b1;
                    end
                end
            end
        end
    end

    // Next State Logic of the FSM:
    always @(*) begin
        if(speedidle_if.timeout_8ms_occured | (speedidle_if.rx_sb_msg == TRAINERROR_Entry_req && speedidle_if.rx_sb_msg_valid == 1'b1)) begin
            // (S6)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start SPEEDIDLE FSM.
                SPEEDIDLE_IDLE: begin
                    if (speedidle_if.speedidle_en) begin
                        if (speed_degrade_error) next_state = TO_TRAINERROR;
                        else next_state = SPEEDIDLE_CONFIG_SPEED;
                    end
                    else next_state = SPEEDIDLE_IDLE;
                end
                // (S1) Configure the PHY speed.
                SPEEDIDLE_CONFIG_SPEED: begin
                    next_state = SPEEDIDLE_WAIT_PLL_LOCK;
                end
                // (S2) Wait for the PLL to lock after speed change.
                SPEEDIDLE_WAIT_PLL_LOCK: begin
                    if (speedidle_if.analog_settle_time_done) next_state = SPEEDIDLE_DONE_REQ;
                    else next_state = SPEEDIDLE_WAIT_PLL_LOCK;
                end
                // (S3) Send & Receive SB Message: {MBTRAIN.SPEEDIDLE done req}
                SPEEDIDLE_DONE_REQ: begin
                    if (speedidle_if.rx_sb_msg == MBTRAIN_SPEEDIDLE_done_req && speedidle_if.rx_sb_msg_valid == 1'b1) next_state = SPEEDIDLE_DONE_RESP;
                    else next_state = SPEEDIDLE_DONE_REQ;
                end
                // (S4) Send & Receive SB Message: {MBTRAIN.SPEEDIDLE done resp}.
                SPEEDIDLE_DONE_RESP: begin
                    if (speedidle_if.rx_sb_msg == MBTRAIN_SPEEDIDLE_done_resp && speedidle_if.rx_sb_msg_valid == 1'b1) next_state = TO_TXSELFCAL;
                    else next_state = SPEEDIDLE_DONE_RESP;
                end
                // (S5) End of SPEEDIDLE state, transition to TXSELFCAL via asserting speedidle_done.
                TO_TXSELFCAL: begin
                    next_state = (speedidle_if.speedidle_en) ? TO_TXSELFCAL : SPEEDIDLE_IDLE; // Stay here till "speedidle_if.speedidle_en" is cleared. To prevent re-implementing the FSM steps unintentionally.
                end
                // (S6) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = (speedidle_if.speedidle_en) ? TO_TRAINERROR : SPEEDIDLE_IDLE;
                end
                default: begin
                    next_state = (speedidle_if.speedidle_en) ? TO_TRAINERROR : SPEEDIDLE_IDLE; // Default case to avoid latches in synthesis.
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
        speedidle_if.speedidle_done   = 1'b0;
        speedidle_if.trainerror_req   = 1'b0;

        //==========================
        // Timers:
        //==========================
        speedidle_if.timeout_timer_en       = 1'b1;
        speedidle_if.analog_settle_timer_en = 1'b0;

        //=========================
        // MB signals:
        //=========================
        // Lane Behavior Control
        // Transmitters are held low; Clock receivers are enabled.
        speedidle_if.mb_tx_clk_lane_sel  = 2'b01; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        speedidle_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        speedidle_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        speedidle_if.mb_tx_trk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).

        speedidle_if.mb_rx_clk_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        speedidle_if.mb_rx_data_lane_sel = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        speedidle_if.mb_rx_val_lane_sel  = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        speedidle_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).


        //============================
        // SB signals:
        //============================
        // For SB TX:
        speedidle_if.tx_sb_msg_valid = 1'h0   ; // Tell the SB that the selected message is valid.
        speedidle_if.tx_sb_msg       = NOTHING; // Tell the Sideband the message that it should to send.
        speedidle_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
        speedidle_if.tx_data_field   = 64'h0  ; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state:
            SPEEDIDLE_IDLE: begin
                speedidle_if.timeout_timer_en = 1'b0;
            end

            // (S1) Configure the PHY speed.
            SPEEDIDLE_CONFIG_SPEED: begin
                // Disable clock lock for a moment if re-configuring speed
                // The applied action here is sequential logic. So, just apply the default signals.
            end

            // (S2) Wait for the PLL to lock after speed change.
            SPEEDIDLE_WAIT_PLL_LOCK: begin
                speedidle_if.analog_settle_timer_en = 1'b1;
            end

            // (S3) Send & Receive SB Message: {MBTRAIN.SPEEDIDLE done req}
            SPEEDIDLE_DONE_REQ: begin
                speedidle_if.tx_sb_msg_valid = (!data_incoherence);           // Tell the SB that the selected message is valid.
                speedidle_if.tx_sb_msg       = MBTRAIN_SPEEDIDLE_done_req;    // Tell the Sideband the message that it should to send.
            end

            // (S4) Send & Receive SB Message: {MBTRAIN.SPEEDIDLE done resp}.
            SPEEDIDLE_DONE_RESP: begin
                speedidle_if.tx_sb_msg_valid = (!data_incoherence);           // Tell the SB that the selected message is valid.
                speedidle_if.tx_sb_msg       = MBTRAIN_SPEEDIDLE_done_resp;   // Tell the Sideband the message that it should to send.
            end

            // (S5) End of SPEEDIDLE state, transition to TXSELFCAL via asserting speedidle_done.
            TO_TXSELFCAL: begin
                speedidle_if.speedidle_done = 1'b1;
                speedidle_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end

            // (S6) TRAINERROR state:
            TO_TRAINERROR: begin
                speedidle_if.speedidle_done   = 1'b1;
                speedidle_if.trainerror_req   = 1'b1;
                speedidle_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end

            default: begin
                // Default case to avoid latches in synthesis.
            end
        endcase
    end

endmodule
