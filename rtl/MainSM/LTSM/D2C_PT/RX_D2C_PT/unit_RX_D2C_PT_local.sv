// unit_RX_D2C_PT_local.sv — RX D2C Point Test LOCAL die
// Mixed Initiator: Uses WAIT and 1-cycle SEND states. Initiates test, but partner initiates Clear and Count_Done.
//
// ====================================================================================================
// Sideband Messages Used in RX-initiated D2C Point Test (Local):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {Start Rx Init D to C point test req}    | Out (TX)  | MsgInfo: [15:0]: Max compare err thresh   |
// |                                          |           | Data:    [63:60]: Reserved                |
// |                                          |           |          [59]: Comparison Mode            |
// |                                          |           |          [58:43]: Iteration Count         |
// |                                          |           |          [42:27]: Idle Count              |
// |                                          |           |          [26:11]: Burst Count             |
// |                                          |           |          [10]: Pattern Mode               |
// |                                          |           |          [9:6]: Clock Phase control at Tx |
// |                                          |           |          [5:3]: Valid Pattern             |
// |                                          |           |          [2:0]: Data pattern              |
// | {Start Rx Init D to C point test resp}   | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {LFSR clear error req}                   | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {LFSR clear error resp}                  | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {Rx Init D to C Tx Count Done req}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {Rx Init D to C Tx Count Done resp}      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {End Rx Init D to C point test req}      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {End Rx Init D to C point test resp}     | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_RX_D2C_PT_local (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock domain (1 GHz or 2 GHz). All FSM transitions synchronous to this clock.
        input  logic        rst_n,              // 0: Reset FSM to RX_PT_IDLE and clear error registers. 1: Normal operation.

        //=====================================//
        // Control Signals for Sub-states:     //
        //=====================================//
        input  logic        rx_pt_en                   , // 0: Disable/reset test (FSM→IDLE). 1: Enable/trigger test (FSM initiates handshake).
        output logic        test_d2c_done              , // 0: Test in progress or inactive. 1: Test sequence completed (held until rx_pt_en deasserted).

        // For D2C interface configuration from sub-states:
        input  logic [1:0]  d2c_clk_sampling           , // 00: Eye Center (In-phase), 01: Left Edge, 10: Right Edge, 11: Reserved.
        // input  logic        d2c_lfsr_en                , // I discovered we don't need it at all. The signal "d2c_data_pattern_sel" can replace this signal.
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
        output logic [15:0] d2c_perlane_pass           , // Per-lane error status; each bit=1 if that lane passed. (didn't excesse the threshold)
        output logic        d2c_aggr_pass              , // 16-bit aggregate error count across all data lanes. (1: success, 0: failed)
        output logic        d2c_val_pass               , // 1: No Valid Lane error, 0: Valid Lane pattern mismatch detected.

        //=====================================//
        // Mainband Control Signals:           //
        //=====================================//
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Clock Sampling Details Group:
        // (Note: Unused at local RX. Kept/commented for Organization)
        // output logic        mb_tx_clk_sampling_en,
        // output logic [1:0]  mb_tx_clk_sampling,

        // Tx Pattern Generator Setup Group:
        // (Note: Local die does NOT drive TX pattern generator. Config sent via SB data field to Partner.)
        // output logic [2:0]  mb_tx_pattern_setup,
        // output logic        mb_tx_pattern_en,
        // output logic        mb_tx_lfsr_en   ,
        // output logic        mb_tx_lfsr_rst  ,

        output logic [2:0]  mb_rx_pattern_setup   , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        output logic        mb_rx_lfsr_en         , // 0: Disable RX LFSR descrambler. 1: Enable RX LFSR descrambler.
        output logic        mb_rx_lfsr_rst        , // 0: Normal operation. 1: Synchronously reset RX LFSR to default seed.

        // Rx Pattern Generator Configuration Group (New signals):
        output logic [15:0] mb_rx_iter_count      , // (For Rx) Iteration Count: Indicates the iteration count of bursts followed by idle.  (TODO: New signal. Add it in the interface.)
        output logic [15:0] mb_rx_idle_count      , // (For Rx) IDLE Count: Indicates the duration of low following the burst (UI count).   (TODO: New signal. Add it in the interface.)
        output logic [15:0] mb_rx_burst_count     , // (For Rx) Burst Count: Indicates the duration of selected pattern (UI count).         (TODO: New signal. Add it in the interface.)
        output logic        mb_rx_pattern_mode    , // (For Rx) 0: Continuous Pattern Mode, 1: Burst Pattern Mode.                          (TODO: New signal. Add it in the interface.)
        output logic        mb_rx_val_pattern_sel , // (For Rx) 0: VALTRAIN pattern, 1: Don't use VALTRAIN, 2: Operational Valid.           (TODO: New signal. Add it in the interface.)
        output logic [1:0]  mb_rx_data_pattern_sel, // (For Rx) Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.              (TODO: New signal. Add it in the interface.)

        // Receiver Comparison Setup & Errors:
        output logic        mb_rx_compare_en            , // 0: Disable RX comparison circuit. 1: Enable RX comparison, start error accumulation.
        output logic [11:0] mb_rx_max_err_thresh_perlane, // Drives per-lane max error threshold to RX comparison block.
        output logic [15:0] mb_rx_max_err_thresh_aggr   , // Drives aggregate max error threshold to RX comparison block.
        output logic [1:0]  mb_rx_compare_setup         , // 00: Per-Lane, 01: Aggregate, 10: Valid Lane, 11: Clock Lane comparison.

        input  logic        mb_rx_compare_done          , // 0: Comparison in progress. 1: Comparison of configured pattern iterations is complete.
        input  logic        mb_rx_aggr_pass             , // 16-bit cumulative error count from the RX comparison circuit.
        input  logic [15:0] mb_rx_perlane_pass          , // 16-bit status vector; each bit corresponds to an operational lane.
        input  logic        mb_rx_val_pass              , // 1: Valid Lane pattern matched. 0: Valid Lane pattern mismatch detected.

        //-------------------- MB Rx/Tx Lane Logical and Physical Lanes --------------------//
        // Tx Lane Logical Selection:
        // output logic [1:0]  mb_tx_trk_lane_sel,
        // output logic [1:0]  mb_tx_clk_lane_sel,
        // output logic [1:0]  mb_tx_val_lane_sel,
        // output logic [1:0]  mb_tx_data_lane_sel,

        // Rx Lane Logical Selection:
        output logic        mb_rx_trk_lane_sel ,  // 0: Disabled (RX logical tracking lane inactive). 1: Enabled.
        output logic        mb_rx_clk_lane_sel ,  // 0: Disabled. 1: Enabled (RX logical clock lane active).
        output logic        mb_rx_val_lane_sel ,  // 0: Disabled. 1: Enabled (RX logical valid lane active).
        output logic        mb_rx_data_lane_sel,  // 0: Disabled. 1: Enabled (RX logical data lanes active).


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
        input  logic [7:0]  rx_sb_msg        // Received MsgCode value from partner die.
    );
    import UCIe_pkg::*;

    localparam [3:0]
    RX_PT_IDLE                 = 4'h0,
    RX_PT_SEND_START_REQ       = 4'h1, // Sends {Start Rx Init D to C point test req} message
    RX_PT_WAIT_START_RESP      = 4'h2, // Waits for {Start Rx Init D to C point test resp} response
    RX_PT_WAIT_CLR_ERR_REQ     = 4'h3, // Waits for {LFSR clear error req} request from Partner
    RX_PT_SEND_CLR_ERR_RESP    = 4'h4, // Sends {LFSR clear error resp} response to Partner
    RX_PT_WAIT_COUNT_DONE_REQ  = 4'h5, // Waits for {Rx Init D to C Tx Count Done req} request from Partner
    RX_PT_SEND_COUNT_DONE_RESP = 4'h6, // Sends {Rx Init D to C Tx Count Done resp} response to Partner
    RX_PT_LOG_RESULT           = 4'h7, // State to log MB Rx comparison results and separate SB message pulses
    RX_PT_SEND_END_REQ         = 4'h8, // Sends {End Rx Init D to C point test req} message
    RX_PT_WAIT_END_RESP        = 4'h9, // Waits for {End Rx Init D to C point test resp} response
    RX_PT_DONE                 = 4'hA;

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
                    next_state = RX_PT_SEND_START_REQ;
                RX_PT_SEND_START_REQ:
                    next_state = RX_PT_WAIT_START_RESP;
                RX_PT_WAIT_START_RESP:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == Start_Rx_Init_D_to_C_point_test_resp) ? RX_PT_WAIT_CLR_ERR_REQ : RX_PT_WAIT_START_RESP;
                RX_PT_WAIT_CLR_ERR_REQ:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == LFSR_clear_error_req) ? RX_PT_SEND_CLR_ERR_RESP : RX_PT_WAIT_CLR_ERR_REQ;
                RX_PT_SEND_CLR_ERR_RESP: // Here we Reset the MB Rx LFSR and send SB msg.
                    next_state = RX_PT_WAIT_COUNT_DONE_REQ;
                RX_PT_WAIT_COUNT_DONE_REQ: // Here we wait for the SB msg and also, activate the MB RX comparison circuit.
                    next_state = (rx_sb_msg_valid && rx_sb_msg == Rx_Init_D_to_C_Tx_Count_Done_req) ? RX_PT_SEND_COUNT_DONE_RESP : RX_PT_WAIT_COUNT_DONE_REQ;
                RX_PT_SEND_COUNT_DONE_RESP:
                    next_state = RX_PT_LOG_RESULT;
                RX_PT_LOG_RESULT: // Here we log the MB Rx comparison result. Also, we need this state to seperate between 2 consecutive pulses of the 'tx_sb_msg_valid'. we seperate between the pulse in 'RX_PT_SEND_COUNT_DONE_RESP' and 'RX_PT_SEND_END_REQ'.
                    next_state = RX_PT_SEND_END_REQ;
                RX_PT_SEND_END_REQ:
                    next_state = RX_PT_WAIT_END_RESP;
                RX_PT_WAIT_END_RESP:
                    next_state = (rx_sb_msg_valid && rx_sb_msg == End_Rx_Init_D_to_C_point_test_resp) ? RX_PT_DONE : RX_PT_WAIT_END_RESP;
                RX_PT_DONE:
                    next_state = RX_PT_DONE;
                default:
                    next_state = RX_PT_IDLE;
            endcase
    end

    // Latched results from MB compare
    reg [15:0] d2c_perlane_pass_r;
    reg        d2c_aggr_pass_r;
    reg        d2c_val_pass_r;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            d2c_perlane_pass_r <= 16'b0;
            d2c_aggr_pass_r    <= 1'b0 ;
            d2c_val_pass_r     <= 1'b0 ;
        end else if (mb_rx_compare_done) begin
            d2c_perlane_pass_r <= mb_rx_perlane_pass;
            d2c_aggr_pass_r    <= mb_rx_aggr_pass;
            d2c_val_pass_r     <= mb_rx_val_pass;
        end
    end

    // Output Logic
    always @(*) begin
        test_d2c_done   = 1'b0;

        //=====================================//
        // Mainband Control Signals:           //
        //=====================================//
        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // // Clock Sampling Details Group:
        // mb_tx_clk_sampling_en            = 1'b0                      ;
        // mb_tx_clk_sampling               = d2c_clk_sampling          ; // Clock Phase control: 0h(Eye Center), 1h(Left edge), 2h(Right edge). // Note: We get this signal from the partner. Not from the local Substates.

        // Tx Pattern Generator Setup Group:
        // (Note: Local die does NOT drive TX pattern generator directly. Config sent via SB data field.)
        // mb_tx_pattern_setup              = d2c_pattern_setup            ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        // mb_tx_pattern_en                 = 1'b0                      ; // 0: Don't send pattern.
        // mb_tx_lfsr_en                    = 1'b0                      ; // 0: Disable the Tx LFSR.
        // mb_tx_lfsr_rst                   = 1'b0                      ; // 0: Don't Reset the Tx LFSR.

        mb_rx_pattern_setup              = d2c_pattern_setup            ; // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
        mb_rx_lfsr_en                    = (d2c_data_pattern_sel== 2'b0 && d2c_pattern_setup[0]==1'b1); // (For Rx) Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.
        mb_rx_lfsr_rst                   = 1'b0                         ; // 0: Don't Reset the Rx LFSR.

        mb_rx_iter_count                 = d2c_iter_count               ; // (For Rx) Iteration Count: Indicates the iteration count of bursts followed by idle.
        mb_rx_idle_count                 = d2c_idle_count               ; // (For Rx) IDLE Count: Indicates the duration of low following the burst (UI count).
        mb_rx_burst_count                = d2c_burst_count              ; // (For Rx) Burst Count: Indicates the duration of selected pattern (UI count).
        mb_rx_pattern_mode               = d2c_pattern_mode             ; // (For Rx) 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        mb_rx_val_pattern_sel            = d2c_val_pattern_sel          ; // (For Rx) 0: VALTRAIN pattern, 1: Don't use VALTRAIN (just Low) value.
        mb_rx_data_pattern_sel           = d2c_data_pattern_sel         ; // (For Rx) Data pattern used during training: 0h: LFSR; 1h: ID, or all 0.

        // Receiver Comparison Setup & Errors:
        mb_rx_compare_en                 = 1'b0                         ; // 1'b0: Disable Pattern Comparison.
        mb_rx_max_err_thresh_perlane     = cfg_max_err_thresh_perlane   ; // Max error Threshold in per-Lane comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
        mb_rx_max_err_thresh_aggr        = cfg_max_err_thresh_aggr      ; // Max error Threshold in aggregate comparison for error counting. From "Training Setup 4 (Offset 1050h)" in RF.
        mb_rx_compare_setup              = d2c_compare_setup            ; // 0: Per-Lane, 1: Aggregate, 2: Valid Lane, 3: Clock Lane Comparison.

        // For D2C interface signals with the Sub-states:
        d2c_perlane_pass                 = d2c_perlane_pass_r           ;
        d2c_aggr_pass                    = d2c_aggr_pass_r              ;
        d2c_val_pass                     = d2c_val_pass_r               ;


        //-------------------- MB Rx/Tx Lane Logical and Phasical Lanes --------------------//
        // mb_tx_trk_lane_sel    = 2'b00; // 00b: Low (Tx Logical Track Lane).
        // mb_tx_clk_lane_sel    = 2'b00; // 00b: Low (Tx Logical Clock Lanes).
        // mb_tx_val_lane_sel    = 2'b00; // 00b: Low (Tx Logical Valid Lane).
        // mb_tx_data_lane_sel   = 2'b00; // 00b: Low (Tx Logical Data Lanes).
        mb_rx_trk_lane_sel    = 1'b0 ; // 0b: Disabled (Rx Logical Track Lane).
        mb_rx_clk_lane_sel    = 1'b1 ; // 1b: Enabled  (Rx Logical Clock Lane).
        mb_rx_val_lane_sel    = 1'b1 ; // 1b: Enabled  (Rx Logical Valid Lane).
        mb_rx_data_lane_sel   = 1'b1 ; // 1b: Enabled  (Rx Logical Data Lanes).


        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // For SB signals:
        tx_sb_msg_valid = 1'b0   ;
        tx_sb_msg       = NOTHING;
        tx_msginfo      = 16'b0  ;
        tx_data_field   = 64'b0  ;

        case (current_state)
            RX_PT_IDLE: begin
                mb_rx_compare_en = 1'b0;
                mb_rx_lfsr_en    = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "1. The UCIe Module enables the pattern comparison circuits to compare incoming mainband data to
            //      the locally generated expected pattern, sets up the Receiver parameters (shown in Table 4-5),
            //      sends a {Start Rx Init D to C point test req} sideband message to its UCIe Module Partner, and
            //      then waits for a response. The data field of this message includes the required parameters, shown
            //      in Table 4-5."
            RX_PT_SEND_START_REQ: begin
                // Enable pattern comparison circuit.
                mb_rx_compare_en     = 1'b1 ;

                // Send {Start Rx Init D to C point test req}
                tx_sb_msg_valid      = 1'b1; // Pulse for 1 cycle
                tx_sb_msg            = Start_Rx_Init_D_to_C_point_test_req;
                tx_msginfo           =
                    (d2c_compare_setup==2'd1)? cfg_max_err_thresh_aggr:                 // Send aggregate comparison mode,
                    (d2c_compare_setup==2'd0)? {4'b0,cfg_max_err_thresh_perlane}:16'b0; // Send Per-lane comparison mode, otherwise 0.
                tx_data_field[63:60] = 4'b0                        ; // Reserved. Just set it to 0 for now.
                tx_data_field[59]    = (d2c_compare_setup!=2'd0)   ; // Comparison Mode (0: Per Lane; 1: Aggregate)
                tx_data_field[58:43] = d2c_iter_count              ; // Iteration Count Setting.
                tx_data_field[42:27] = d2c_idle_count              ; // Idle Count Setting.
                tx_data_field[26:11] = d2c_burst_count             ; // Burst Count Setting.
                tx_data_field[10]    = d2c_pattern_mode            ; // Pattern Mode (0: continuous mode, 1: Burst Mode).
                tx_data_field[9:6]   = {2'b0, d2c_clk_sampling}    ; // Clock Phase control at Transmitter (0h: Clock PI Center, 1h: Left Edge, 2h: Right Edge).
                tx_data_field[5:3]   = {2'b0, d2c_val_pattern_sel} ; // Valid Pattern (0h: Functional pattern).
                tx_data_field[2:0]   = {1'b0, d2c_data_pattern_sel}; // Data pattern (0h: LFSR, 1h: Per Lane ID).
            end

            // UCIe 3.0 Reference Content:
            //     "Once the data to clock training parameters for its Transmitter are setup, the UCIe
            //      Module Partner responds with a {Start Rx Init D to C point test resp} sideband message."
            RX_PT_WAIT_START_RESP: begin
                mb_rx_compare_en = 1'b1 ;
                // Do nothing new.
            end

            // UCIe 3.0 Reference Content:
            //     "2. The UCIe Module Partner resets the LFSR (scrambler) on its mainband Transmitters and sends
            //      sideband message {LFSR clear error req}."
            RX_PT_WAIT_CLR_ERR_REQ: begin
                mb_rx_compare_en = 1'b1 ;
                // Do nothing new.
            end

            // UCIe 3.0 Reference Content:
            //     "... The UCIe Module resets the LFSR and clears any prior compare results on
            //      its mainband Receivers and responds with {LFSR clear error resp} sideband
            //      message."
            RX_PT_SEND_CLR_ERR_RESP: begin
                mb_rx_compare_en = 1'b1 ;

                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = LFSR_clear_error_resp;
                mb_rx_lfsr_rst  = 1'b1;
            end

            // UCIe 3.0 Reference Content:
            //     "3. The UCIe Module Partner sends the pattern (selected through "Tx Pattern Generator Setup") for
            //      the selected number of cycles ("Tx Pattern Mode Setup") on its mainband Transmitter.
            //      4. The UCIe Module performs the comparison on its mainband Receivers for each UI during the
            //      pattern transmission based on "Rx Compare Setup" and logs the results.
            //      5. The UCIe Module Partner sends a sideband message {Rx Init D to C Tx count done req} sideband
            //      message once the pattern count is complete."
            RX_PT_WAIT_COUNT_DONE_REQ: begin
                mb_rx_compare_en = 1'b1 ;
                // Do nothing new.
            end

            // UCIe 3.0 Reference Content:
            //     " The UCIe Module, stops comparison and responds
            //      with the sideband message {Rx Init D to C Tx count done resp}.
            //      The UCIe Module can now use the logged data for its Receiver Lanes."
            RX_PT_SEND_COUNT_DONE_RESP: begin
                mb_rx_compare_en = 1'b0 ;
                mb_rx_lfsr_en    = 1'b0;

                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = Rx_Init_D_to_C_Tx_Count_Done_resp;
            end

            // Just seperate between the two sent SB messages {Rx Init D to C Tx count done resp} and {End Rx Init D to C point test req}.
            // We need to seperate between each 2 pulses on 'tx_sb_msg_valid' signal by a 1 low cycle at least.
            // Also, here we can store (log) the MB Rx result (the pass / fail for: Valid Lane or Data Lanes).
            RX_PT_LOG_RESULT: begin
                mb_rx_compare_en = 1'b0 ;
                mb_rx_lfsr_en    = 1'b0;

                tx_sb_msg_valid  = 1'b0;
                // Do nothing new.
            end

            // UCIe 3.0 Reference Content:
            //     "6. The UCIe Module sends an {End Rx Init D to C point test req} sideband message and ..."
            RX_PT_SEND_END_REQ: begin
                mb_rx_compare_en = 1'b0 ;
                mb_rx_lfsr_en    = 1'b0;

                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = End_Rx_Init_D_to_C_point_test_req;
            end

            // UCIe 3.0 Reference Content:
            //     "... the UCIe Module Partner responds with an {End Rx Init D to C point test resp} sideband message."
            RX_PT_WAIT_END_RESP: begin
                mb_rx_compare_en = 1'b0 ;
                mb_rx_lfsr_en    = 1'b0;
            end

            // UCIe 3.0 Reference Content:
            //     "When a UCIe Module has received the {End Rx Init D to C point test resp} sideband message, the
            //      corresponding sequence has completed."
            RX_PT_DONE: begin
                mb_rx_compare_en = 1'b0;
                mb_rx_lfsr_en    = 1'b0;

                test_d2c_done    = 1'b1;
            end
            default: begin end
        endcase
    end
endmodule
