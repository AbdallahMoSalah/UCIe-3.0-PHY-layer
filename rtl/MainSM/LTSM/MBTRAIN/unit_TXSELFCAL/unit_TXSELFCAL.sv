module unit_TXSELFCAL #() (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.txselfcal_mp txselfcal_if
    );

    import UCIe_pkg::MBTRAIN_TXSELFCAL_Done_req ; // Msg Number: d45
    import UCIe_pkg::MBTRAIN_TXSELFCAL_Done_resp; // Msg Number: d46
    import UCIe_pkg::TRAINERROR_Entry_req       ; // Msg Number: d107
    import UCIe_pkg::NOTHING                    ; // Msg Number: 8'hFF

    // States names
    localparam  TXSELFCAL_IDLE          = 4'h0, // (S0)
    TXSELFCAL_EXECUTE_TX_CAL = 4'h1, // (S1)
    TXSELFCAL_DONE_REQ      = 4'h2, // (S2)
    TXSELFCAL_DONE_RESP     = 4'h3, // (S3)
    TO_RXCLKCAL             = 4'h4, // (S4)
    TO_TRAINERROR           = 4'h5; // (S5)

    reg [3:0] current_state, next_state, previous_state;
    wire data_incoherence;

    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    assign data_incoherence = (current_state != previous_state) ? 1'b1 : 1'b0;

    // Current State Logic
    always @(posedge txselfcal_if.lclk or negedge txselfcal_if.rst_n) begin
        if (!txselfcal_if.rst_n) begin
            current_state  <= TXSELFCAL_IDLE;
            previous_state <= TXSELFCAL_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // Next State Logic of the FSM:
    always @(*) begin
        if(txselfcal_if.timeout_8ms_occured | (txselfcal_if.rx_sb_msg == TRAINERROR_Entry_req && txselfcal_if.rx_sb_msg_valid == 1'b1)) begin
            // (S5)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start TXSELFCAL FSM.
                TXSELFCAL_IDLE: begin
                    if (txselfcal_if.txselfcal_en) next_state = TXSELFCAL_EXECUTE_TX_CAL;
                    else next_state = TXSELFCAL_IDLE;
                end
                // (S1) Wait for the analog settle timer to complete internal calibration.
                TXSELFCAL_EXECUTE_TX_CAL: begin
                    if (txselfcal_if.analog_settle_time_done) next_state = TXSELFCAL_DONE_REQ;
                    else next_state = TXSELFCAL_EXECUTE_TX_CAL;
                end
                // (S2) Send & Receive SB Message: {MBTRAIN.TXSELFCAL done req}
                TXSELFCAL_DONE_REQ: begin
                    if (txselfcal_if.rx_sb_msg == MBTRAIN_TXSELFCAL_Done_req && txselfcal_if.rx_sb_msg_valid == 1'b1) next_state = TXSELFCAL_DONE_RESP;
                    else next_state = TXSELFCAL_DONE_REQ;
                end
                // (S3) Send & Receive SB Message: {MBTRAIN.TXSELFCAL done resp}.
                TXSELFCAL_DONE_RESP: begin
                    if (txselfcal_if.rx_sb_msg == MBTRAIN_TXSELFCAL_Done_resp && txselfcal_if.rx_sb_msg_valid == 1'b1) next_state = TO_RXCLKCAL;
                    else next_state = TXSELFCAL_DONE_RESP;
                end
                // (S4) End of TXSELFCAL state, transition by asserting txselfcal_done.
                TO_RXCLKCAL: begin
                    next_state = (txselfcal_if.txselfcal_en) ? TO_RXCLKCAL : TXSELFCAL_IDLE; // Stay here till "txselfcal_if.txselfcal_en" is cleared.
                end
                // (S5) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = (txselfcal_if.txselfcal_en) ? TO_TRAINERROR : TXSELFCAL_IDLE;
                end
                default: begin
                    next_state = (txselfcal_if.txselfcal_en) ? TO_TRAINERROR : TXSELFCAL_IDLE; // Default case to avoid latches in synthesis.
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
        txselfcal_if.txselfcal_done   = 1'b0;
        txselfcal_if.trainerror_req   = 1'b0;

        //==========================
        // Timers:
        //==========================
        txselfcal_if.timeout_timer_en       = 1'b1;
        txselfcal_if.analog_settle_timer_en = 1'b0;

        //=========================
        // MB signals: (Mainband)
        //=========================
        // Lane Behavior Control
        // Transmitters are held Tri-state; Receivers are permitted to be disabled (we hold them 0b logic).
        txselfcal_if.mb_tx_clk_lane_sel  = 2'b10; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Clock Lane).
        txselfcal_if.mb_tx_data_lane_sel = 2'b10; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Data Lanes).
        txselfcal_if.mb_tx_val_lane_sel  = 2'b10; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Valid Lane).
        txselfcal_if.mb_tx_trk_lane_sel  = 2'b10; // 00b: Low, 01b: Active, 1xb: Tri-state (Tx Logical Track Lane).

        txselfcal_if.mb_rx_clk_lane_sel  = 2'b00 ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        txselfcal_if.mb_rx_data_lane_sel  = 2'b00 ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        txselfcal_if.mb_rx_val_lane_sel  = 2'b00 ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        txselfcal_if.mb_rx_trk_lane_sel  = 2'b00 ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).

        txselfcal_if.phy_tx_selfcal_en   = 1'b0 ; // Enable Tx Self Calibration (To adjust the MB Tx analog circuits).

        //============================
        // SB signals:
        //============================
        // For SB TX:
        txselfcal_if.tx_sb_msg_valid = 1'h0   ; // Tell the SB that the selected message is valid.
        txselfcal_if.tx_sb_msg       = NOTHING; // Tell the Sideband the message that it should to send.
        txselfcal_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
        txselfcal_if.tx_data_field   = 64'h0  ; // Data field of the SB message.

        case (current_state)
            // (S0) IDLE state:
            TXSELFCAL_IDLE: begin
                txselfcal_if.timeout_timer_en = 1'b0;
            end

            // (S1) Wait for analog settle
            TXSELFCAL_EXECUTE_TX_CAL: begin
                txselfcal_if.analog_settle_timer_en = 1'b1;
                txselfcal_if.phy_tx_selfcal_en      = 1'b1 ; // Enable Tx Self Calibration (To adjust the MB Tx analog circuits).
            end

            // (S2) Send & Receive SB Message: {MBTRAIN.TXSELFCAL done req}
            TXSELFCAL_DONE_REQ: begin
                txselfcal_if.tx_sb_msg_valid = (!data_incoherence);             // Tell the SB that the selected message is valid.
                txselfcal_if.tx_sb_msg       = MBTRAIN_TXSELFCAL_Done_req;      // Tell the Sideband the message that it should to send.
            end

            // (S3) Send & Receive SB Message: {MBTRAIN.TXSELFCAL done resp}.
            TXSELFCAL_DONE_RESP: begin
                txselfcal_if.tx_sb_msg_valid = (!data_incoherence);             // Tell the SB that the selected message is valid.
                txselfcal_if.tx_sb_msg       = MBTRAIN_TXSELFCAL_Done_resp;     // Tell the Sideband the message that it should to send.
            end

            // (S4) End of TXSELFCAL state.
            TO_RXCLKCAL: begin
                txselfcal_if.txselfcal_done   = 1'b1;
                txselfcal_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end

            // (S5) TRAINERROR state:
            TO_TRAINERROR: begin
                txselfcal_if.txselfcal_done   = 1'b1;
                txselfcal_if.trainerror_req   = 1'b1;
                txselfcal_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end

            default: begin
                // Default case to avoid latches in synthesis.
            end
        endcase
    end

endmodule
