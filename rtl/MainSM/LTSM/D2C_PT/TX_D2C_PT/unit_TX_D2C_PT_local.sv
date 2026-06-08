// unit_TX_D2C_PT_local.sv — TX D2C Point Test LOCAL die
// Strict Initiator: Uses WAIT and 1-cycle SEND states. Initiates test and all commands.
//
// ====================================================================================================
// Sideband Messages Used in TX-initiated D2C Point Test (Local):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {Start Tx Init D to C point test req}    | Out (TX)  | MsgInfo: [15:0]: Max compare err thresh   |
// |                                          |           | Data:    [63:60]: Reserved                |
// |                                          |           |          [59]: Comparison Mode            |
// |                                          |           |          [58:43]: Iteration Count         |
// |                                          |           |          [42:27]: Idle Count              |
// |                                          |           |          [26:11]: Burst Count             |
// |                                          |           |          [10]: Pattern Mode               |
// |                                          |           |          [9:6]: Clock Phase control at Tx |
// |                                          |           |          [5:3]: Valid Pattern             |
// |                                          |           |          [2:0]: Data pattern              |
// | {Start Tx Init D to C point test resp}   | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {LFSR clear error req}                   | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {LFSR clear error resp}                  | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {Tx Init D to C results req}             | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {Tx Init D to C results resp}            | In  (RX)  | MsgInfo: Error status fields logged       |
// | {End Tx Init D to C point test req}      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {End Tx Init D to C point test resp}     | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_TX_D2C_PT_local (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock domain (1 GHz or 2 GHz). All FSM transitions synchronous to this clock.
        input  logic        rst_n,              // 0: Reset FSM to TX_PT_IDLE and clear error registers. 1: Normal operation.

        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        input  logic        tx_pt_en                   , // 0: Disable/reset test (FSM→IDLE). 1: Enable/trigger test (FSM initiates handshake).
        output logic        test_d2c_done              , // 0: Test in progress or inactive. 1: Test sequence completed (held until tx_pt_en deasserted).

        // For D2C interface configuration from sub-states:
        input  logic [1:0]  d2c_clk_sampling           , // 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.
        // input  logic        d2c_lfsr_en                , // Unused. Derived from d2c_data_pattern_sel == 2'b0 instead.
        input  logic [2:0]  d2c_pattern_setup          , // Bit0: Data Pattern Enable, Bit1: Valid Pattern Enable, Bit2: Clock Pattern Enable.
        input  logic [1:0]  d2c_data_pattern_sel       , // 00: LFSR pattern, 01: Per-Lane ID, 10: Fixed All Zeros, 11: Reserved.
        input  logic        d2c_val_pattern_sel        , // 0: VALTRAIN/functional pattern, 1: Held Low / Operational Valid.
        input  logic        d2c_pattern_mode           , // 0: Continuous mode (indefinite), 1: Burst mode (burst/idle counts).
        input  logic [15:0] d2c_burst_count            , // Unsigned 16-bit burst duration in Unit Intervals (UI).
        input  logic [15:0] d2c_idle_count             , // Unsigned 16-bit idle duration in Unit Intervals (UI).
        input  logic [15:0] d2c_iter_count             , // Unsigned 16-bit iteration count of burst-idle cycles.
        input  logic [1:0]  d2c_compare_setup          , // 00: Per-Lane comparison, 01: Aggregate, 10: Valid Lane, 11: Clock Lane.
        input  logic [11:0] cfg_max_err_thresh_perlane , // Unsigned 12-bit max error threshold per lane from Register File.
        input  logic [15:0] cfg_max_err_thresh_aggr    , // Unsigned 16-bit max aggregate error threshold from Register File.

        // For D2C interface error signals output to sub-states:
        output logic [15:0] d2c_perlane_pass            , // Per-lane error status; each bit=1 if that lane exceeds cfg_max_err_thresh_perlane.
        output logic        d2c_aggr_pass               , // 1-bit cumulative aggregate pass: HIGH if total errors did not exceed threshold.
        output logic        d2c_val_pass                , // 0: No Valid Lane error, 1: Valid Lane pattern mismatch detected.

        //=====================================//
        // Mainband Control Signals (TX Only): //
        //=====================================//
        //-------------------- MB Tx Lane Pattern Configuration --------------------//
        // Clock Phase Sampling Setup:
        output logic        mb_tx_clk_sampling_en      , // 0: TX Clock phase unchanged. 1: Update TX Clock phase.
        output logic [1:0]  mb_tx_clk_sampling         , // 00: Eye Center, 01: Left Edge, 10: Right Edge.

        // TX Pattern Generator Enable and Configuration:
        output logic        mb_tx_pattern_en           , // 0: TX in static idle. 1: Drive active training pattern on configured TX lanes.
        output logic [2:0]  mb_tx_pattern_setup        , // Bit0: Data Enable, Bit1: Valid Enable, Bit2: Clock Enable.
        output logic        mb_tx_lfsr_en              , // 0: Disable TX LFSR. 1: Enable TX LFSR scrambler.
        output logic        mb_tx_lfsr_rst             , // 0: Normal operation. 1: Synchronously reset TX LFSR to default seed.
        output logic        mb_tx_pattern_mode         , // 0: Continuous mode, 1: Burst mode.
        output logic [15:0] mb_tx_burst_count          , // Unsigned 16-bit burst duration UI count.
        output logic [15:0] mb_tx_idle_count           , // Unsigned 16-bit idle duration UI count.
        output logic [15:0] mb_tx_iter_count           , // Unsigned 16-bit iteration count.
        output logic [1:0]  mb_tx_data_pattern_sel     , // 00: LFSR, 01: Per-Lane ID, 10: Fixed All Zeros.
        output logic        mb_tx_val_pattern_sel      , // 0: VALTRAIN/functional, 1: Held Low.
        input  logic        mb_tx_pattern_count_done   , // 0: TX pattern generator is transmitting. 1: Completed all iterations.

        // TX Lane Logical selection (Determines pattern/low/tri-state):
        output logic [1:0]  mb_tx_trk_lane_sel         , // 00: Driven Low, 01: Active pattern, 1x: Tri-stated.
        output logic [1:0]  mb_tx_clk_lane_sel         , // 00: Driven Low, 01: Active pattern, 1x: Tri-stated.
        output logic [1:0]  mb_tx_val_lane_sel         , // 00: Driven Low, 01: Active pattern, 1x: Tri-stated.
        output logic [1:0]  mb_tx_data_lane_sel        , // 00: Driven Low, 01: Active pattern, 1x: Tri-stated.

        //=====================================//
        // Mainband RX Control Signals:        //
        //=====================================//
        // (Note: Unused at local TX. Kept/commented for Organization)
        // output logic [2:0]  mb_rx_pattern_setup,
        // output logic        mb_rx_lfsr_en,
        // output logic        mb_rx_lfsr_rst,
        // output logic [15:0] mb_rx_iter_count,
        // output logic [15:0] mb_rx_idle_count,
        // output logic [15:0] mb_rx_burst_count,
        // output logic        mb_rx_pattern_mode,
        // output logic        mb_rx_val_pattern_sel,
        // output logic [1:0]  mb_rx_data_pattern_sel,
        // output logic        mb_rx_compare_en            , // 0: Disable RX comparison circuit. 1: Enable RX comparison, start error accumulation.
        // output logic [11:0] mb_rx_max_err_thresh_perlane, // Drives per-lane max error threshold to RX comparison block.
        // output logic [15:0] mb_rx_max_err_thresh_aggr   , // Drives aggregate max error threshold to RX comparison block.
        // output logic [1:0]  mb_rx_compare_setup         , // 00: Per-Lane, 01: Aggregate, 10: Valid Lane, 11: Clock Lane comparison.
        // input  logic        mb_rx_compare_done          , // 0: Comparison in progress. 1: Comparison of configured pattern iterations is complete.
        // input  logic [15:0] mb_rx_aggr_pass              , // 16-bit cumulative error count from the RX comparison circuit.
        // input  logic [15:0] mb_rx_perlane_pass           , // 16-bit status vector; each bit corresponds to an operational lane.
        // input  logic        mb_rx_val_pass               , // 0: Valid Lane pattern matched. 1: Valid Lane pattern mismatch detected.
        // output logic        mb_rx_trk_lane_sel ,  // 0: Disabled (RX logical tracking lane inactive). 1: Enabled.
        // output logic        mb_rx_clk_lane_sel ,  // 0: Disabled. 1: Enabled (RX logical clock lane active).
        // output logic        mb_rx_val_lane_sel ,  // 0: Disabled. 1: Enabled (RX logical valid lane active).
        // output logic        mb_rx_data_lane_sel,  // 0: Disabled. 1: Enabled (RX logical data lanes active).

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // SB TX:
        output logic        tx_sb_msg_valid, // Asserted for exactly 1 lclk cycle to transmit a sideband message.
        output logic [7:0]  tx_sb_msg      , // MsgCode value to transmit. See SB message table above.
        output logic [15:0] tx_msginfo     , // MsgInfo payload field (varies by message type).
        output logic [63:0] tx_data_field  , // 64-bit data payload (varies by message type).

        // SB RX:
        input  logic        rx_sb_msg_valid, // Pulse (1 lclk cycle) when a valid sideband message has been received from partner.
        input  logic [7:0]  rx_sb_msg      , // Received MsgCode value from partner die.
        input  logic [15:0] rx_msginfo     , // Received MsgInfo payload field.
        input  logic [63:0] rx_data_field    // Received 64-bit data payload.
    );
    import UCIe_pkg::*;

    localparam [3:0]
    TX_PT_IDLE                 = 4'h0,
    TX_PT_SEND_START_REQ       = 4'h1, // Sends {Start Tx Init D to C point test req} message
    TX_PT_WAIT_START_RESP      = 4'h2, // Waits for {Start Tx Init D to C point test resp} response
    TX_PT_SEND_CLR_ERR_REQ     = 4'h3, // Sends {LFSR clear error req} message
    TX_PT_WAIT_CLR_ERR_RESP    = 4'h4, // Waits for {LFSR clear error resp} response
    TX_PT_PATTERN_GEN          = 4'h5, // Drives test pattern on MB Transmitters
    TX_PT_SEND_RESULTS_REQ     = 4'h6, // Sends {Tx Init D to C results req} message
    TX_PT_WAIT_RESULTS_RESP    = 4'h7, // Waits for {Tx Init D to C results resp} response
    TX_PT_SEND_END_REQ         = 4'h8, // Sends {End Tx Init D to C point test req} message
    TX_PT_WAIT_END_RESP        = 4'h9, // Waits for {End Tx Init D to C point test resp} response
    TX_PT_DONE                 = 4'hA;

    reg [3:0] current_state, next_state;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) current_state <= TX_PT_IDLE;
        else        current_state <= next_state;
    end

    // Next State Logic
    always @(*) begin
        if (!tx_pt_en) next_state = TX_PT_IDLE;
        else case (current_state)
                TX_PT_IDLE:
                    next_state = TX_PT_SEND_START_REQ;
                TX_PT_SEND_START_REQ:
                    next_state = TX_PT_WAIT_START_RESP;
                TX_PT_WAIT_START_RESP:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == Start_Tx_Init_D_to_C_point_test_resp) ? TX_PT_SEND_CLR_ERR_REQ : TX_PT_WAIT_START_RESP;
                TX_PT_SEND_CLR_ERR_REQ:
                    next_state = TX_PT_WAIT_CLR_ERR_RESP;
                TX_PT_WAIT_CLR_ERR_RESP:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == LFSR_clear_error_resp) ? TX_PT_PATTERN_GEN : TX_PT_WAIT_CLR_ERR_RESP;
                TX_PT_PATTERN_GEN:
                    next_state = mb_tx_pattern_count_done ? TX_PT_SEND_RESULTS_REQ : TX_PT_PATTERN_GEN;
                TX_PT_SEND_RESULTS_REQ:
                    next_state = TX_PT_WAIT_RESULTS_RESP;
                TX_PT_WAIT_RESULTS_RESP:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == Tx_Init_D_to_C_results_resp) ? TX_PT_SEND_END_REQ : TX_PT_WAIT_RESULTS_RESP;
                TX_PT_SEND_END_REQ:
                    next_state = TX_PT_WAIT_END_RESP;
                TX_PT_WAIT_END_RESP:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == End_Tx_Init_D_to_C_point_test_resp) ? TX_PT_DONE : TX_PT_WAIT_END_RESP;
                TX_PT_DONE:
                    next_state = TX_PT_DONE;
                default:
                    next_state = TX_PT_IDLE;
            endcase
    end

    // Configuration / Error results logged from the received Results Resp
    reg [15:0] d2c_perlane_pass_r; // 16-bit per-lane pass vector (bit=1 means that lane passed)
    reg        d2c_aggr_pass_r;    // 1-bit cumulative aggregate pass (captured from rx_msginfo[4])
    reg        d2c_val_pass_r;

    always @(posedge lclk or negedge rst_n) begin : RESULTS_RESP_PROC
        if (!rst_n) begin
            d2c_perlane_pass_r <= 16'b0;
            d2c_aggr_pass_r    <=  1'b0; // 1-bit reset
            d2c_val_pass_r     <=  1'b0;
        end else if (current_state == TX_PT_WAIT_RESULTS_RESP && rx_sb_msg_valid && rx_sb_msg == Tx_Init_D_to_C_results_resp) begin
            d2c_perlane_pass_r <= rx_data_field[15:0];
            d2c_aggr_pass_r    <= rx_msginfo[4];       // 1-bit: 1=Pass, 0=Fail
            d2c_val_pass_r     <= rx_msginfo[5];
        end
    end

    // Moore Machine Output Logic
    always @(*) begin
        // --- Default all outputs to prevent latches ---
        test_d2c_done                    = 1'b0;
        tx_sb_msg_valid                  = 1'b0;
        tx_sb_msg                        = NOTHING;
        tx_msginfo                       = 16'h0000;
        tx_data_field                    = 64'h0000_0000_0000_0000;

        mb_tx_clk_sampling_en            = 1'b0;
        mb_tx_clk_sampling               = d2c_clk_sampling;

        mb_tx_pattern_en                 = 1'b0;
        mb_tx_pattern_setup              = d2c_pattern_setup;
        mb_tx_lfsr_en                    = 1'b0;
        mb_tx_lfsr_rst                   = 1'b0;

        mb_tx_pattern_mode               = d2c_pattern_mode;
        mb_tx_burst_count                = d2c_burst_count;
        mb_tx_idle_count                 = d2c_idle_count;
        mb_tx_iter_count                 = d2c_iter_count;
        mb_tx_data_pattern_sel           = d2c_data_pattern_sel;
        mb_tx_val_pattern_sel            = d2c_val_pattern_sel;

        // Transmitter initiated Data, Valid, and Track Transmitters drive low when not performing actions
        mb_tx_trk_lane_sel               = 2'b00; // 00: Driven Low
        mb_tx_clk_lane_sel               = 2'b00; // 00: Driven Low (Differential Low / Quadrature Low)
        mb_tx_val_lane_sel               = 2'b00; // 00: Driven Low
        mb_tx_data_lane_sel              = 2'b00; // 00: Driven Low

        // Error outputs mapping
        d2c_perlane_pass                 = d2c_perlane_pass_r;          // 16-bit: each bit = 1 means that lane passed
        d2c_aggr_pass                    = d2c_aggr_pass_r;             // 1-bit: 1=Pass, 0=Fail
        d2c_val_pass                     = d2c_val_pass_r;

        case (current_state)
            TX_PT_IDLE: begin
                // In IDLE, keep all control outputs disabled
                tx_sb_msg_valid = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "1. The UCIe Module sets up the Transmitter parameters (shown in Table 4-5),
            //      sends a {Start Tx Init D to C point test req} sideband message to its UCIe Module Partner, and
            //      then waits for a response. The data field of this message includes the required parameters, shown
            //      in Table 4-5. The Receiver on the UCIe Module Partner must enable the pattern comparison circuits
            //      to compare incoming mainband data to the locally generated expected pattern."
            TX_PT_SEND_START_REQ: begin
                mb_tx_clk_sampling_en = 1'b1;

                tx_sb_msg_valid       = 1'b1;
                tx_sb_msg             = Start_Tx_Init_D_to_C_point_test_req;
                tx_msginfo            = (d2c_compare_setup == 2'b01) ? cfg_max_err_thresh_aggr : {4'h0, cfg_max_err_thresh_perlane};
                tx_data_field[2:0]   = {1'b0, d2c_data_pattern_sel};
                tx_data_field[5:3]   = {2'b0, d2c_val_pattern_sel};
                tx_data_field[9:6]   = {2'b0, d2c_clk_sampling};
                tx_data_field[10]    = d2c_pattern_mode;
                tx_data_field[26:11] = d2c_burst_count;
                tx_data_field[42:27] = d2c_idle_count;
                tx_data_field[58:43] = d2c_iter_count;
                tx_data_field[59]    = (d2c_compare_setup != 2'b00); // 0: Per-lane mode, 1: non-per-lane comparison mode
                tx_data_field[63:60] = 4'h0;
            end

            // UCIe 3.0 Reference Content:
            //     "Once the data to clock training parameters for its Receiver are setup, the UCIe
            //      Module Partner responds with a {Start Tx Init D to C point test resp} sideband message."
            TX_PT_WAIT_START_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "2. The UCIe Module resets the LFSR (scrambler) on its mainband Transmitters and sends
            //      the {LFSR clear error req} sideband message."
            TX_PT_SEND_CLR_ERR_REQ: begin
                mb_tx_lfsr_rst  = 1'b1;

                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = LFSR_clear_error_req;
            end

            // UCIe 3.0 Reference Content:
            //     "... The UCIe Module Partner resets the LFSR and clears any prior compare results on
            //      its mainband Receivers and responds with {LFSR clear error resp} sideband message."
            TX_PT_WAIT_CLR_ERR_RESP: begin
                mb_tx_lfsr_rst  = 1'b1;
                tx_sb_msg_valid = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "3. The UCIe Module sends the pattern (selected through “Tx Pattern Generator Setup”) for
            //      the selected number of cycles (“Tx Pattern Mode Setup”) on its mainband Transmitter.
            //      4. The UCIe Module Partner performs the comparison on its Receivers for each UI during the
            //      pattern transmission based on “Rx Compare Setup” and logs the results."
            TX_PT_PATTERN_GEN: begin
                mb_tx_pattern_en    = 1'b1;
                mb_tx_lfsr_en       = (d2c_data_pattern_sel == 2'b00 && d2c_pattern_setup[0]==1'b1); // Enable TX LFSR scrambler in LFSR mode

                // Lane selections are active during pattern generation
                mb_tx_clk_lane_sel  = d2c_pattern_setup[2] ? 2'b01 : 2'b00;
                mb_tx_val_lane_sel  = d2c_pattern_setup[1] ? 2'b01 : 2'b00;
                mb_tx_data_lane_sel = d2c_pattern_setup[0] ? 2'b01 : 2'b00;
                mb_tx_trk_lane_sel  = 2'b00; // Track is held low during point test
            end

            // UCIe 3.0 Reference Content:
            //     "5. The UCIe Module requests its UCIe Module Partner for the logged results in Step 4
            //      by sending {Tx Init D to C results req} sideband message."
            TX_PT_SEND_RESULTS_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = Tx_Init_D_to_C_results_req;
            end

            // UCIe 3.0 Reference Content:
            //     "... The UCIe Module Partner stops comparison on its mainband Receivers and
            //      responds with the logged results {Tx Init D to C results resp} sideband message."
            TX_PT_WAIT_RESULTS_RESP: begin
                tx_sb_msg_valid = 1'b0;
                // There is a sequential logic applied in RESULTS_RESP_PROC always block related to the received SB msg.
            end

            // UCIe 3.0 Reference Content:
            //     "6. The UCIe Module stops sending the pattern on its Transmitters and sends the
            //      {End Tx Init D to C point test req} sideband message and ..."
            TX_PT_SEND_END_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = End_Tx_Init_D_to_C_point_test_req;
            end

            // UCIe 3.0 Reference Content:
            //     "... the UCIe Module Partner responds with {End Tx Init D to C point test resp}."
            TX_PT_WAIT_END_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "When a UCIe Module has received the {End Tx Init D to C point test resp} sideband message, the
            //      corresponding sequence has completed."
            TX_PT_DONE: begin
                test_d2c_done   = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end
endmodule


