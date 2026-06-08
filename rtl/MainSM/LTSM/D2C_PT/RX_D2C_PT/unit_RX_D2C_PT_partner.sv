// unit_RX_D2C_PT_partner.sv — RX D2C Point Test PARTNER die
// Mixed Target: Uses WAIT and 1-cycle SEND states. Initiates Clear and Count_Done.
//
// ====================================================================================================
// Sideband Messages Used in RX-initiated D2C Point Test (Partner):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {Start Rx Init D to C point test req}    | In  (RX)  | MsgInfo: [15:0]: Max compare err thresh   |
// |                                          |           | Data:    [63:60]: Reserved                |
// |                                          |           |          [59]: Comparison Mode            |
// |                                          |           |          [58:43]: Iteration Count         |
// |                                          |           |          [42:27]: Idle Count              |
// |                                          |           |          [26:11]: Burst Count             |
// |                                          |           |          [10]: Pattern Mode               |
// |                                          |           |          [9:6]: Clock Phase control at Tx |
// |                                          |           |          [5:3]: Valid Pattern             |
// |                                          |           |          [2:0]: Data pattern              |
// | {Start Rx Init D to C point test resp}   | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {LFSR clear error req}                   | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {LFSR clear error resp}                  | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {Rx Init D to C Tx Count Done req}       | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {Rx Init D to C Tx Count Done resp}      | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {End Rx Init D to C point test req}      | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {End Rx Init D to C point test resp}     | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_RX_D2C_PT_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk,              // LTSM clock domain (1 GHz or 2 GHz). All FSM transitions synchronous to this clock.
        input  logic        rst_n,             // 0: Reset FSM to RX_PT_IDLE and clear decoded config registers. 1: Normal operation.

        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        input  logic        rx_pt_en     ,     // 0: Disable/reset test (FSM→IDLE). 1: Enable/trigger test (FSM waits for Start REQ).
        output logic        test_d2c_done,     // 0: Test in progress or inactive. 1: Test sequence completed (held until rx_pt_en deasserted).

        //=====================================//
        // Mainband Control Signals:           //
        //=====================================//
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling Details Group:
        output logic        mb_tx_clk_sampling_en   , // 0: TX Clock phase unchanged. 1: Update TX Clock phase with mb_tx_clk_sampling value.
        output logic [1:0]  mb_tx_clk_sampling      , // 00: Eye Center, 01: Left Edge, 10: Right Edge. (Decoded from rx_data_field[9:6].)

        // Tx Pattern Generator Setup Group:
        output logic        mb_tx_pattern_en        , // 0: TX in static idle. 1: Drive active training pattern on configured TX lanes.
        output logic [2:0]  mb_tx_pattern_setup     , // Bit0: Data Enable, Bit1: Valid Enable, Bit2: Clock Enable. (Decoded from rx_data_field.)
        output logic        mb_tx_lfsr_en           , // 0: Disable TX LFSR. 1: Enable TX LFSR scrambler.
        output logic        mb_tx_lfsr_rst          , // 0: Normal operation. 1: Synchronously reset TX LFSR to default seed.

        // Tx Pattern Generator Configuration Group:
        output logic        mb_tx_pattern_mode      , // 0: Continuous mode, 1: Burst mode. (Decoded from rx_data_field[10].)
        output logic [15:0] mb_tx_burst_count       , // Unsigned 16-bit burst duration in UI. (Decoded from rx_data_field[26:11].)
        output logic [15:0] mb_tx_idle_count        , // Unsigned 16-bit idle duration in UI. (Decoded from rx_data_field[42:27].)
        output logic [15:0] mb_tx_iter_count        , // Unsigned 16-bit iteration count. (Decoded from rx_data_field[58:43].)
        output logic [1:0]  mb_tx_data_pattern_sel  , // 00: LFSR, 01: Per-Lane ID, 10: All Zeros. (Decoded from rx_data_field[2:0].)
        output logic        mb_tx_val_pattern_sel   , // 0: VALTRAIN/functional, 1: Held Low. (Decoded from rx_data_field[5:3].)
        input  logic        mb_tx_pattern_count_done, // 0: TX pattern generator transmitting. 1: TX pattern generator completed all iterations.

        //-------------------- MB Rx/Tx Lane Logical and Physical Lanes --------------------//
        // Tx Lane Logical Selection:
        output logic [1:0]  mb_tx_trk_lane_sel      , // 00: Driven Low, 01: Active pattern, 10: Tri-stated. (For Tx)
        output logic [1:0]  mb_tx_clk_lane_sel      , // 00: Driven Low, 01: Active pattern, 10: Tri-stated. (For Tx)
        output logic [1:0]  mb_tx_val_lane_sel      , // 00: Driven Low, 01: Active pattern, 10: Tri-stated. (For Tx)
        output logic [1:0]  mb_tx_data_lane_sel     , // 00: Driven Low, 01: Active pattern, 10: Tri-stated. (For Tx)

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // SB TX:
        output logic        tx_sb_msg_valid, // Asserted for exactly 1 lclk cycle to transmit a sideband message.
        output logic [7:0]  tx_sb_msg      , // MsgCode value to transmit. See SB message table above.
        output logic [15:0] tx_msginfo     , // MsgInfo payload field (16'h0 for all Partner-sent messages).
        output logic [63:0] tx_data_field  , // 64-bit data payload (64'h0 for all Partner-sent messages).

        // SB RX:
        input  logic        rx_sb_msg_valid, // Pulse (1 lclk cycle) when a valid sideband message has been received from partner.
        input  logic [7:0]  rx_sb_msg      , // Received MsgCode value from partner die.
        // input  logic [15:0] rx_msginfo     , // Not used...
        input  logic [63:0] rx_data_field    // Received 64-bit data payload. Config decoded from Start REQ message.
    );
    import UCIe_pkg::*;

    localparam [3:0]
    RX_PT_IDLE                 = 4'h0,
    RX_PT_WAIT_START_REQ       = 4'h1,
    RX_PT_SEND_START_RESP      = 4'h2, // Sends {Start Rx Init D to C point test resp} response
    RX_PT_TX_LFSR_RST          = 4'h3, // Resets LFSR of the MB Tx and separates SB message pulses
    RX_PT_SEND_CLR_ERR_REQ     = 4'h4, // Sends {LFSR clear error req} request to Local
    RX_PT_WAIT_CLR_ERR_RESP    = 4'h5, // Waits for {LFSR clear error resp} response from Local
    RX_PT_PATTERN_GEN          = 4'h6, // Drives test pattern on MB Transmitters
    RX_PT_SEND_COUNT_DONE_REQ  = 4'h7, // Sends {Rx Init D to C Tx Count Done req} request to Local
    RX_PT_WAIT_COUNT_DONE_RESP = 4'h8, // Waits for {Rx Init D to C Tx Count Done resp} response from Local
    RX_PT_WAIT_END_REQ         = 4'h9, // Waits for {End Rx Init D to C point test req} request from Local
    RX_PT_SEND_END_RESP        = 4'hA, // Sends {End Rx Init D to C point test resp} response to Local
    RX_PT_DONE                 = 4'hB;

    reg [3:0] current_state, next_state;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) current_state <= RX_PT_IDLE;
        else        current_state <= next_state;
    end

    // Next State Logic
    always @(*) begin
        if (!rx_pt_en) next_state = RX_PT_IDLE;
        else case (current_state)
                RX_PT_IDLE:
                    next_state = RX_PT_WAIT_START_REQ;
                RX_PT_WAIT_START_REQ:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == Start_Rx_Init_D_to_C_point_test_req) ? RX_PT_SEND_START_RESP : RX_PT_WAIT_START_REQ;
                RX_PT_SEND_START_RESP:
                    next_state = RX_PT_TX_LFSR_RST;
                RX_PT_TX_LFSR_RST: // Here we Reset the LFSR of the MB Tx. alse, we use this state as a seperation between the pulse of 'tx_sb_msg_valid' in the state of 'RX_PT_SEND_START_RESP' and 'RX_PT_SEND_CLR_ERR_REQ'.
                    next_state = RX_PT_SEND_CLR_ERR_REQ;
                RX_PT_SEND_CLR_ERR_REQ: // Here we send the SB msg at the same moment.
                    next_state = RX_PT_WAIT_CLR_ERR_RESP;
                RX_PT_WAIT_CLR_ERR_RESP:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == LFSR_clear_error_resp) ? RX_PT_PATTERN_GEN : RX_PT_WAIT_CLR_ERR_RESP;
                RX_PT_PATTERN_GEN:
                    next_state = mb_tx_pattern_count_done ? RX_PT_SEND_COUNT_DONE_REQ : RX_PT_PATTERN_GEN;
                RX_PT_SEND_COUNT_DONE_REQ:
                    next_state = RX_PT_WAIT_COUNT_DONE_RESP;
                RX_PT_WAIT_COUNT_DONE_RESP:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == Rx_Init_D_to_C_Tx_Count_Done_resp) ? RX_PT_WAIT_END_REQ : RX_PT_WAIT_COUNT_DONE_RESP;
                RX_PT_WAIT_END_REQ:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == End_Rx_Init_D_to_C_point_test_req) ? RX_PT_SEND_END_RESP : RX_PT_WAIT_END_REQ;
                RX_PT_SEND_END_RESP:
                    next_state = RX_PT_DONE;
                RX_PT_DONE:
                    next_state = RX_PT_DONE;
                default:
                    next_state = RX_PT_IDLE;
            endcase
    end

    // Config decoded from REQ's START_REQ data_field
    reg [15:0] mb_tx_iter_count_r, mb_tx_idle_count_r, mb_tx_burst_count_r;
    reg        mb_tx_pattern_mode_r, decoded_lfsr_en_r;
    reg [1:0]  mb_tx_clk_sampling_r, mb_tx_data_pattern_sel_r;
    reg        mb_tx_val_pattern_sel_r;
    reg [2:0]  mb_tx_pattern_setup_r;

    always @(posedge lclk or negedge rst_n) begin : START_REQ_PROC
        if (!rst_n) begin
            mb_tx_iter_count_r       <= 16'b0;
            mb_tx_idle_count_r       <= 16'b0;
            mb_tx_burst_count_r      <= 16'b0;
            mb_tx_pattern_mode_r     <= 1'b0;
            mb_tx_clk_sampling_r     <= 2'b0;
            mb_tx_val_pattern_sel_r  <= 1'b0;
            mb_tx_data_pattern_sel_r <= 2'b0;
            mb_tx_pattern_setup_r    <= 3'b0;
            decoded_lfsr_en_r        <= 1'b0;
        end
        else if (current_state == RX_PT_WAIT_START_REQ && rx_sb_msg == Start_Rx_Init_D_to_C_point_test_req && rx_sb_msg_valid) begin
            mb_tx_iter_count_r       <= rx_data_field[58:43]        ;
            mb_tx_idle_count_r       <= rx_data_field[42:27]        ;
            mb_tx_burst_count_r      <= rx_data_field[26:11]        ;
            mb_tx_pattern_mode_r     <= rx_data_field[10]           ;
            mb_tx_clk_sampling_r     <= 2'(rx_data_field[9:6])      ;
            mb_tx_val_pattern_sel_r  <= |rx_data_field[5:3]         ;
            mb_tx_data_pattern_sel_r <= 2'(rx_data_field[2:0])      ;
            mb_tx_pattern_setup_r[0] <= (rx_data_field[2:0] <= 3'h1); // Data pattern enabled // Data pattern (0h: LFSR, 1h: Per Lane ID).
            mb_tx_pattern_setup_r[1] <= (rx_data_field[5:3] == 3'h0); // Valid pattern enabled
            mb_tx_pattern_setup_r[2] <= 1'b0                        ; // Clock pattern not driven by pattern generator
            decoded_lfsr_en_r        <= (rx_data_field[2:0] == 3'h0); // 0h: LFSR pattern and else : no LFSR pattern (Perlane ID pattern)
        end
    end

    // Output Logic
    always @(*) begin
        test_d2c_done            = 1'b0;
        tx_sb_msg_valid          = 1'b0;
        tx_sb_msg                = NOTHING;
        tx_msginfo               = 16'b0;
        tx_data_field            = 64'b0;

        mb_tx_pattern_en         = 1'b0;
        mb_tx_lfsr_en            = 1'b0;
        mb_tx_lfsr_rst           = 1'b0;
        mb_tx_clk_sampling_en    = 1'b0;

        mb_tx_clk_lane_sel       = 2'b00;
        mb_tx_data_lane_sel      = 2'b00;
        mb_tx_val_lane_sel       = 2'b00;
        mb_tx_trk_lane_sel       = 2'b00;

        mb_tx_pattern_setup      = mb_tx_pattern_setup_r;
        mb_tx_iter_count         = mb_tx_iter_count_r;
        mb_tx_idle_count         = mb_tx_idle_count_r;
        mb_tx_burst_count        = mb_tx_burst_count_r;
        mb_tx_pattern_mode       = mb_tx_pattern_mode_r;
        mb_tx_clk_sampling       = mb_tx_clk_sampling_r;
        mb_tx_val_pattern_sel    = mb_tx_val_pattern_sel_r;
        mb_tx_data_pattern_sel   = mb_tx_data_pattern_sel_r;

        case (current_state)
            RX_PT_IDLE: begin end // Do nothing.

            // UCIe 3.0 Reference Content:
            //     "1. The UCIe Module enables the pattern comparison circuits to compare incoming mainband data to
            //      the locally generated expected pattern, sets up the Receiver parameters (shown in Table 4-5),
            //      sends a {Start Rx Init D to C point test req} sideband message to its UCIe Module Partner, and
            //      then waits for a response. The data field of this message includes the required parameters, shown
            //      in Table 4-5. ..."
            RX_PT_WAIT_START_REQ: begin
                // Do Sequential Logic in START_REQ_PROC always block.
            end

            // UCIe 3.0 Reference Content:
            //     "... Once the data to clock training parameters for its Transmitter are setup, the UCIe
            //      Module Partner responds with a {Start Rx Init D to C point test resp} sideband message."
            RX_PT_SEND_START_RESP: begin
                mb_tx_clk_sampling_en = 1'b1; // To apply the received clk sampling PI on the Tx.
                tx_sb_msg_valid       = 1'b1; // Pulse for 1 cycle
                tx_sb_msg             = Start_Rx_Init_D_to_C_point_test_resp;
            end

            // Reset the Tx LFSR.
            // Also, we need to seperate between each 2 pulses on 'tx_sb_msg_valid' signal by a 1 low cycle at least.
            RX_PT_TX_LFSR_RST: begin
                tx_sb_msg_valid = 1'b0; // Low for 1 cycle
                mb_tx_lfsr_rst  = 1'b1;
            end

            // UCIe 3.0 Reference Content:
            //     "2. The UCIe Module Partner resets the LFSR (scrambler) on its mainband Transmitters and sends
            //      sideband message {LFSR clear error req}. ..."
            RX_PT_SEND_CLR_ERR_REQ: begin
                tx_sb_msg_valid = 1'b1;
                mb_tx_lfsr_rst  = 1'b1;
                tx_sb_msg       = LFSR_clear_error_req;
            end

            // UCIe 3.0 Reference Content:
            //     "... The UCIe Module resets the LFSR and clears any prior
            //      compare results on its mainband Receivers and responds with {LFSR clear error resp} sideband
            //      message."
            RX_PT_WAIT_CLR_ERR_RESP: begin
                mb_tx_lfsr_en  = decoded_lfsr_en_r;
                mb_tx_lfsr_rst = 1'b1             ;
            end

            // UCIe 3.0 Reference Content:
            //     "3. The UCIe Module Partner sends the pattern (selected through "Tx Pattern Generator Setup") for
            //      the selected number of cycles ("Tx Pattern Mode Setup") on its mainband Transmitter."
            RX_PT_PATTERN_GEN: begin
                mb_tx_pattern_en    = 1'b1             ;
                mb_tx_lfsr_en       = decoded_lfsr_en_r;

                mb_tx_clk_lane_sel  = 2'b01;
                mb_tx_data_lane_sel = {1'b0, mb_tx_pattern_setup_r[0]};
                mb_tx_val_lane_sel  = {1'b0, mb_tx_pattern_setup_r[1]};
                mb_tx_trk_lane_sel  = 2'b00;
            end

            // UCIe 3.0 Reference Content:
            //     "4. The UCIe Module performs the comparison on its mainband Receivers for each UI during the
            //      pattern transmission based on "Rx Compare Setup" and logs the results.
            //      5. The UCIe Module Partner sends a sideband message {Rx Init D to C Tx count done req} sideband
            //      message once the pattern count is complete. "
            RX_PT_SEND_COUNT_DONE_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = Rx_Init_D_to_C_Tx_Count_Done_req;
            end

            // UCIe 3.0 Reference Content:
            //     "... The UCIe Module, stops comparison and responds
            //      with the sideband message {Rx Init D to C Tx count done resp}. The UCIe Module can now use
            //      the logged data for its Receiver Lanes."
            RX_PT_WAIT_COUNT_DONE_RESP: begin end // Do nothing.


            // UCIe 3.0 Reference Content:
            //     "6. The UCIe Module sends an {End Rx Init D to C point test req} sideband message and ...".
            RX_PT_WAIT_END_REQ: begin end // Do nothing.

            // UCIe 3.0 Reference Content:
            //     "...  and the UCIe Module Partner responds with an {End Rx Init D to C point test resp} sideband message. ..."
            RX_PT_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = End_Rx_Init_D_to_C_point_test_resp;
            end

            // UCIe 3.0 Reference Content:
            //     "...  When a UCIe Module has received the {End Rx Init D to C point test resp} sideband message, the
            //      corresponding sequence has completed."
            RX_PT_DONE: begin
                test_d2c_done = 1'b1;
            end

            default: begin end // Should never happen.
        endcase
    end
endmodule


