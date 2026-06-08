// unit_TX_D2C_PT_partner.sv — TX D2C Point Test PARTNER die
// Strict Target: Waits for _req messages and sends 1-cycle _resp messages.
//
// ====================================================================================================
// Sideband Messages Used in TX-initiated D2C Point Test (Partner):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {Start Tx Init D to C point test req}    | In  (RX)  | MsgInfo: [15:0]: Max compare err thresh   |
// |                                          |           | Data:    [63:60]: Reserved                |
// |                                          |           |          [59]: Comparison Mode            |
// |                                          |           |          [58:43]: Iteration Count         |
// |                                          |           |          [42:27]: Idle Count              |
// |                                          |           |          [26:11]: Burst Count             |
// |                                          |           |          [10]: Pattern Mode               |
// |                                          |           |          [9:6]: Clock Phase control at Tx |
// |                                          |           |          [5:3]: Valid Pattern             |
// |                                          |           |          [2:0]: Data pattern              |
// | {Start Tx Init D to C point test resp}   | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {LFSR clear error req}                   | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {LFSR clear error resp}                  | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {Tx Init D to C results req}             | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {Tx Init D to C results resp}            | Out (TX)  | MsgInfo: Error status fields logged       |
// | {End Tx Init D to C point test req}      | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {End Tx Init D to C point test resp}     | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================


module unit_TX_D2C_PT_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock domain. All FSM transitions synchronous to this clock.
        input  logic        rst_n,              // 0: Reset FSM and clear error/config registers. 1: Normal operation.

        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        input  logic        tx_pt_en                   , // 0: Disable/reset test (FSM→IDLE). 1: Enable/trigger test (FSM waits for Start message).
        output logic        test_d2c_done              , // 0: Test in progress or inactive. 1: Test sequence completed (held until tx_pt_en deasserted).

        //=====================================//
        // Mainband Control Signals (RX Only): //
        //=====================================//
        //-------------------- MB Rx Lane Pattern Configuration --------------------//
        // (Note: Partner die does NOT drive TX pattern generator. Local die drives the TX patterns.
        //  Partner die only controls its RX comparison circuits to receive and compare the patterns.)
        // (Note: Unused at partner TX. Kept/commented for Organization)
        // output logic        mb_tx_clk_sampling_en,
        // output logic [1:0]  mb_tx_clk_sampling   ,
        // output logic        mb_tx_pattern_en      ,
        // output logic [2:0]  mb_tx_pattern_setup   ,
        // output logic        mb_tx_lfsr_en         ,
        // output logic        mb_tx_lfsr_rst        ,
        // output logic [15:0] mb_tx_burst_count     ,
        // output logic [15:0] mb_tx_idle_count      ,
        // output logic [15:0] mb_tx_iter_count      ,
        // output logic [1:0]  mb_tx_data_pattern_sel,
        // output logic        mb_tx_val_pattern_sel ,

        // RX Lane Logical Selection:
        output logic        mb_rx_trk_lane_sel         , // 0: Disabled (RX logical tracking lane inactive). 1: Enabled.
        output logic        mb_rx_clk_lane_sel         , // 0: Disabled. 1: Enabled (RX logical clock lane active).
        output logic        mb_rx_val_lane_sel         , // 0: Disabled. 1: Enabled (RX logical valid lane active).
        output logic        mb_rx_data_lane_sel        , // 0: Disabled. 1: Enabled (RX logical data lanes active).

        // RX Pattern Generator Setup Group:
        output logic [2:0]  mb_rx_pattern_setup        , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        output logic        mb_rx_lfsr_en              , // 0: Disable RX LFSR descrambler. 1: Enable RX LFSR descrambler.
        output logic        mb_rx_lfsr_rst             , // 0: Normal operation. 1: Synchronously reset RX LFSR to default seed.

        // RX Pattern Generator Configuration Group:
        output logic [15:0] mb_rx_iter_count           , // (For Rx) Iteration Count: Indicates the iteration count of bursts followed by idle.
        output logic [15:0] mb_rx_idle_count           , // (For Rx) IDLE Count: Indicates the duration of low following the burst (UI count).
        output logic [15:0] mb_rx_burst_count          , // (For Rx) Burst Count: Indicates the duration of selected pattern (UI count).
        output logic        mb_rx_pattern_mode         , // (For Rx) 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        output logic        mb_rx_val_pattern_sel      , // (For Rx) 0: VALTRAIN pattern, 1: Don't use VALTRAIN (just Low).
        output logic [1:0]  mb_rx_data_pattern_sel     , // (For Rx) Data pattern used during training: 00: LFSR; 01: Per-Lane ID; 10: All Zeros.

        // Receiver Comparison Setup & Errors:
        output logic        mb_rx_compare_en           , // 0: Disable RX comparison circuit. 1: Enable RX comparison, start error accumulation.
        output logic [1:0]  mb_rx_compare_setup        , // 00: Per-Lane, 01: Aggregate, 10: Valid Lane, 11: Clock Lane comparison.
        output logic [11:0] mb_rx_max_err_thresh_perlane, // Drives per-lane max error threshold to RX comparison block.
        output logic [15:0] mb_rx_max_err_thresh_aggr  , // Drives aggregate max error threshold to RX comparison block.

        // MB RX lane count for per-lane pass accumulation:
        input  logic [2:0]  mb_rx_data_lane_mask       , // 000: None, 001: Lanes 0-7, 010: Lanes 8-15, 011: Lanes 0-15, 100: Lanes 0-3, 101: Lanes 4-7.

        // RX Status/Errors inputs:
        input  logic        mb_rx_compare_done         , // 0: Comparison in progress. 1: Comparison of configured pattern iterations is complete.
        input  logic        mb_rx_aggr_pass            , // 1: Aggregate comparison passed (error count within threshold). 0: Failed.
        input  logic [15:0] mb_rx_perlane_pass         , // 16-bit status vector; each bit corresponds to an operational lane. If the bit=1 the lane passed, else failed.
        input  logic        mb_rx_val_pass             , // 1: Valid Lane pattern matched. 0: Valid Lane pattern mismatch detected.

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // SB TX:
        output logic        tx_sb_msg_valid, // Asserted for exactly 1 lclk cycle to transmit a sideband message.
        output logic [7:0]  tx_sb_msg      , // MsgCode value to transmit. See SB message table.
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
    TX_PT_IDLE                = 4'h0,
    TX_PT_WAIT_START_REQ      = 4'h1,
    TX_PT_SEND_START_RESP     = 4'h2,
    TX_PT_WAIT_CLR_ERR_REQ   = 4'h3,
    TX_PT_SEND_CLR_ERR_RESP  = 4'h4,
    TX_PT_WAIT_RESULTS_REQ   = 4'h5,
    TX_PT_SEND_RESULTS_RESP  = 4'h6,
    TX_PT_WAIT_END_REQ       = 4'h7,
    TX_PT_SEND_END_RESP      = 4'h8,
    TX_PT_DONE               = 4'h9;

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
                    next_state = TX_PT_WAIT_START_REQ;
                TX_PT_WAIT_START_REQ:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == Start_Tx_Init_D_to_C_point_test_req) ? TX_PT_SEND_START_RESP : TX_PT_WAIT_START_REQ;
                TX_PT_SEND_START_RESP:
                    next_state = TX_PT_WAIT_CLR_ERR_REQ;
                TX_PT_WAIT_CLR_ERR_REQ:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == LFSR_clear_error_req) ? TX_PT_SEND_CLR_ERR_RESP : TX_PT_WAIT_CLR_ERR_REQ;
                TX_PT_SEND_CLR_ERR_RESP:
                    next_state = TX_PT_WAIT_RESULTS_REQ;
                TX_PT_WAIT_RESULTS_REQ:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == Tx_Init_D_to_C_results_req) ? TX_PT_SEND_RESULTS_RESP : TX_PT_WAIT_RESULTS_REQ;
                TX_PT_SEND_RESULTS_RESP:
                    next_state = TX_PT_WAIT_END_REQ;
                TX_PT_WAIT_END_REQ:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == End_Tx_Init_D_to_C_point_test_req) ? TX_PT_SEND_END_RESP : TX_PT_WAIT_END_REQ;
                TX_PT_SEND_END_RESP:
                    next_state = TX_PT_DONE;
                TX_PT_DONE:
                    next_state = TX_PT_DONE;
                default:
                    next_state = TX_PT_IDLE;
            endcase
    end

    // Config decoded from REQ's START_REQ data_field
    reg [15:0] mb_rx_iter_count_r, mb_rx_idle_count_r, mb_rx_burst_count_r;
    reg        mb_rx_pattern_mode_r, decoded_lfsr_en_r;
    // reg [1:0]  mb_tx_clk_sampling_r;
    reg [1:0]  mb_rx_data_pattern_sel_r      ;
    reg [1:0]  mb_rx_compare_setup_r         ;
    reg        mb_rx_val_pattern_sel_r       ;
    reg [2:0]  mb_rx_pattern_setup_r         ;
    reg [11:0] mb_rx_max_err_thresh_perlane_r;
    reg [15:0] mb_rx_max_err_thresh_aggr_r   ;
    reg [15:0] d2c_perlane_pass_r            ;
    reg        d2c_aggr_pass_r               ;
    reg        d2c_val_pass_r                ;

    // ==================================================
    // MB Lane Control
    // Convert mb_rx_data_lane_mask (3 bits) to 16-bit negotiated_data_lanes mask.
    // 000b: None  001b: Lanes 0-7  010b: Lanes 8-15  011b: Lanes 0-15
    // 100b: Lanes 0-3  101b: Lanes 4-7
    // ==================================================
    logic [15:0] negotiated_data_lanes       ;
    logic        is_accumulative_perlane_pass;
    always_comb begin
        case (mb_rx_data_lane_mask)
            3'b000:  negotiated_data_lanes = 16'h0000;
            3'b001:  negotiated_data_lanes = 16'h00FF;
            3'b010:  negotiated_data_lanes = 16'hFF00;
            3'b011:  negotiated_data_lanes = 16'hFFFF;
            3'b100:  negotiated_data_lanes = 16'h000F;
            3'b101:  negotiated_data_lanes = 16'h00F0;
            default: negotiated_data_lanes = 16'h0000;
        endcase
    end
    assign is_accumulative_perlane_pass = &(d2c_perlane_pass_r | ~negotiated_data_lanes);
    //====================================================

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            mb_rx_iter_count_r             <= 16'b0;
            mb_rx_idle_count_r             <= 16'b0;
            mb_rx_burst_count_r            <= 16'b0;
            mb_rx_pattern_mode_r           <= 1'b0 ;
            // mb_tx_clk_sampling_r           <= 2'b0 ;
            mb_rx_val_pattern_sel_r        <= 1'b0 ;
            mb_rx_data_pattern_sel_r       <= 2'b0 ;
            mb_rx_compare_setup_r          <= 2'b0 ;
            mb_rx_max_err_thresh_perlane_r <= 12'b0;
            mb_rx_max_err_thresh_aggr_r    <= 16'b0;
            mb_rx_pattern_setup_r          <= 3'b0 ;
            decoded_lfsr_en_r              <= 1'b0 ;
            d2c_perlane_pass_r             <= 16'b0;
            d2c_aggr_pass_r                <= 1'b0 ;
            d2c_val_pass_r                 <= 1'b0 ;
        end
        else if (current_state == TX_PT_WAIT_START_REQ && rx_sb_msg == Start_Tx_Init_D_to_C_point_test_req && rx_sb_msg_valid) begin : START_REQ_PROC
            mb_rx_max_err_thresh_perlane_r <= (rx_data_field[59]==1'b0) ? 12'(rx_msginfo) : 12'b0;
            mb_rx_max_err_thresh_aggr_r    <= (rx_data_field[59]==1'b1) ? rx_msginfo : 16'b0;
            mb_rx_compare_setup_r          <= {1'b0, rx_data_field[59]};
            mb_rx_iter_count_r             <= rx_data_field[58:43];
            mb_rx_idle_count_r             <= rx_data_field[42:27];
            mb_rx_burst_count_r            <= rx_data_field[26:11];
            mb_rx_pattern_mode_r           <= rx_data_field[10];
            // mb_tx_clk_sampling_r           <= 2'(rx_data_field[9:6]);
            mb_rx_val_pattern_sel_r        <= |rx_data_field[5:3];
            mb_rx_data_pattern_sel_r       <= 2'(rx_data_field[2:0]);
            mb_rx_pattern_setup_r          <= {1'b0, |rx_data_field[5:3], |rx_data_field[2:0]};
            decoded_lfsr_en_r              <= (rx_data_field[2:0] == 3'h0); // 0h: LFSR pattern
        end
        else if (mb_rx_compare_done) begin
            d2c_perlane_pass_r <= mb_rx_perlane_pass;
            d2c_aggr_pass_r    <= mb_rx_aggr_pass;
            d2c_val_pass_r     <= mb_rx_val_pass;
        end
    end

    // Moore Machine Output Logic
    always @(*) begin
        // --- Default all outputs to prevent latches ---
        test_d2c_done                    = 1'b0;
        tx_sb_msg_valid                  = 1'b0;
        tx_sb_msg                        = NOTHING;
        tx_msginfo                       = 16'b0;
        tx_data_field                    = 64'b0;

        mb_rx_lfsr_en                    = 1'b0;
        mb_rx_lfsr_rst                   = 1'b0;
        mb_rx_compare_en                 = 1'b0;

        mb_rx_trk_lane_sel               = 1'b0; // 0: Disabled (RX logical tracking lane).
        mb_rx_clk_lane_sel               = 1'b1; // 1: Enabled  (RX logical clock lane).
        mb_rx_val_lane_sel               = 1'b1; // 1: Enabled  (RX logical valid lane).
        mb_rx_data_lane_sel              = 1'b1; // 1: Enabled  (RX logical data lanes).

        mb_rx_pattern_setup              = mb_rx_pattern_setup_r         ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        mb_rx_max_err_thresh_perlane     = mb_rx_max_err_thresh_perlane_r;
        mb_rx_max_err_thresh_aggr        = mb_rx_max_err_thresh_aggr_r   ;
        mb_rx_compare_setup              = mb_rx_compare_setup_r         ; // 00: Per-Lane, 01: Aggregate, 10: Valid Lane, 11: Clock Lane.
        mb_rx_iter_count                 = mb_rx_iter_count_r            ;
        mb_rx_idle_count                 = mb_rx_idle_count_r            ;
        mb_rx_burst_count                = mb_rx_burst_count_r           ;
        mb_rx_pattern_mode               = mb_rx_pattern_mode_r          ; // 0: Continuous Pattern Mode. 1: Burst Pattern Mode.
        // mb_rx_clk_sampling               = mb_tx_clk_sampling_r       ;
        mb_rx_val_pattern_sel            = mb_rx_val_pattern_sel_r       ; // 0: VALTRAIN pattern. 1: Don't use VALTRAIN (just Low).
        mb_rx_data_pattern_sel           = mb_rx_data_pattern_sel_r      ; // 00: LFSR. 01: Per-Lane ID. 10: All Zeros.

        case (current_state)
            TX_PT_IDLE: begin
                // Keep all control outputs disabled in IDLE
                tx_sb_msg_valid = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "1. The UCIe Module sets up the Transmitter parameters (shown in Table 4-5), sends a
            //      {Start Tx Init D to C point test req} sideband message to its UCIe Module Partner, and then waits
            //      for a response. The data field of this message includes the required parameters, shown in Table 4-5.
            TX_PT_WAIT_START_REQ: begin
                mb_rx_lfsr_en   = 1'b0;
                tx_sb_msg_valid = 1'b0;

                // There is also, sequentail logic related to this state in the START_REQ_PROC block.
            end

            // UCIe 3.0 Reference Content:
            //     "The Receiver on the UCIe Module Partner must enable the pattern comparison circuits
            //      to compare incoming mainband data to the locally generated expected pattern. Once the
            //      data to clock training parameters for its Receiver are setup, the UCIe Module Partner
            //      responds with a {Start Tx Init D to C point test resp} sideband message."
            TX_PT_SEND_START_RESP: begin
                tx_sb_msg_valid  = 1'b1; // Pulse for 1 cycle
                tx_sb_msg        = Start_Tx_Init_D_to_C_point_test_resp;
                mb_rx_lfsr_en    = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "2. The UCIe Module resets the LFSR (scrambler) on its mainband Transmitters and sends
            //      the {LFSR clear error req} sideband message."
            TX_PT_WAIT_CLR_ERR_REQ: begin
                tx_sb_msg_valid  = 1'b0             ;
                mb_rx_lfsr_en    = decoded_lfsr_en_r;
            end

            // UCIe 3.0 Reference Content:
            //     "... The UCIe Module Partner resets the LFSR and clears any prior compare results on
            //      its mainband Receivers and responds with {LFSR clear error resp} sideband message."
            TX_PT_SEND_CLR_ERR_RESP: begin
                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = LFSR_clear_error_resp;

                mb_rx_lfsr_rst   = 1'b1; // 1: Reset Rx LFSR during the send cycle.
                mb_rx_lfsr_en    = decoded_lfsr_en_r;
            end

            // UCIe 3.0 Reference Content:
            //     "3. The UCIe Module sends the pattern (selected through "Tx Pattern Generator Setup") for
            //      the selected number of cycles ("Tx Pattern Mode Setup") on its mainband Transmitter.
            //      4. The UCIe Module Partner performs the comparison on its Receivers for each UI during the
            //      pattern transmission based on "Rx Compare Setup" and logs the results.
            //      5. The UCIe Module requests its UCIe Module Partner for the logged results in Step 4
            //      by sending {Tx Init D to C results req} sideband message."
            TX_PT_WAIT_RESULTS_REQ: begin
                tx_sb_msg_valid  = 1'b0;

                mb_rx_compare_en = 1'b1; // 1: Enable RX comparison, start error accumulation.
                mb_rx_lfsr_en    = decoded_lfsr_en_r;
            end

            // UCIe 3.0 Reference Content:
            //     "... The UCIe Module Partner stops comparison on its mainband Receivers and
            //      responds with the logged results {Tx Init D to C results resp} sideband message."
            TX_PT_SEND_RESULTS_RESP: begin
                tx_sb_msg_valid      = 1'b1;
                tx_sb_msg            = Tx_Init_D_to_C_results_resp;
                tx_msginfo[15:6]     = 10'b0;
                tx_msginfo[5]        = d2c_val_pass_r;                      // 1: Valid Lane passed. 0: Valid Lane failed.
                tx_msginfo[4]        = (mb_rx_compare_setup_r == 2'b01)?
                    (d2c_aggr_pass_r)             :                          // 1: Aggregate comparison passed. 0: Failed.
                    (is_accumulative_perlane_pass);                          // 1: All per-lane comparisons passed. 0: At least one lane failed.
                tx_msginfo[3:0]      = 4'b0;
                tx_data_field[63:16] = 48'b0;
                tx_data_field[15:0]  = d2c_perlane_pass_r;                  // Per-lane pass/fail status bits.

                mb_rx_compare_en     = 1'b1; // Keep comparison enabled while sending results (stops after this cycle).
                mb_rx_lfsr_en        = decoded_lfsr_en_r;
            end

            // UCIe 3.0 Reference Content:
            //     "6. The UCIe Module stops sending the pattern on its Transmitters and sends the
            //      {End Tx Init D to C point test req} sideband message and ..."
            TX_PT_WAIT_END_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "... the UCIe Module Partner responds with {End Tx Init D to C point test resp}."
            TX_PT_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = End_Tx_Init_D_to_C_point_test_resp;
            end

            // UCIe 3.0 Reference Content:
            //     "When a UCIe Module has received the {End Tx Init D to C point test resp} sideband message, the
            //      corresponding sequence has completed."
            TX_PT_DONE: begin
                test_d2c_done = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end
endmodule


