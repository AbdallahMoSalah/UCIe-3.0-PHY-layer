// `timescale 1ps/1ps
module unit_DATAVREF #(
        parameter MAX_DATA_VREF_CODE  = 7'D127,
        parameter MIN_DATA_VREF_CODE  = 7'D10
    ) (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.datavref_mp datavref_if,

        // ======================= //
        // D2C signals.            //
        // ======================= //
        internal_ltsm_if.mbtrain2d2c_mp d2c_if
    );
    // For analog Voltage control.
    localparam DATA_VREF_CODE_WIDTH = $clog2(MAX_DATA_VREF_CODE + 1);

    // To get the used SB messages for: (datavref_if.tx_sb_msg, sb_it.rx_sb_msg)
    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_DATAVREF_start_req ; // Msg Number: d39
    import UCIe_pkg::MBTRAIN_DATAVREF_start_resp; // Msg Number: d40
    import UCIe_pkg::MBTRAIN_DATAVREF_end_req   ; // Msg Number: d41
    import UCIe_pkg::MBTRAIN_DATAVREF_end_resp  ; // Msg Number: d42
    import UCIe_pkg::TRAINERROR_Entry_req       ; // Msg Number: d107
    import UCIe_pkg::NOTHING                    ; // Msg Number: 8'hFF

    // States names
    localparam DATAVREF_IDLE          = 4'h0, // (S0)
    DATAVREF_START_REQ     = 4'h1, // (S1)
    DATAVREF_START_RESP    = 4'h2, // (S2)
    DATAVREF_SET_VREF_CODE = 4'h3, // (S3)
    DATAVREF_RX_D2C_PT     = 4'h4, // (S4)
    DATAVREF_LOG_RESULT    = 4'h5, // (S5)
    DATAVREF_CALC_APPLY    = 4'h6, // (S6)
    DATAVREF_END_REQ       = 4'h7, // (S7)
    DATAVREF_END_RESP      = 4'h8, // (S8)
    TO_SPEEDIDLE           = 4'h9, // (S9)
    TO_TRAINERROR          = 4'hA; // (S10)

    reg [3:0] current_state, next_state, previous_state; // The Current, Next states of the FSM.

    // ====================================================================
    // Vref sweep data-path signals
    // ====================================================================
    wire [DATA_VREF_CODE_WIDTH-1:0] swept_code_r; // Vref code currently being swept
    wire [DATA_VREF_CODE_WIDTH-1:0] best_vref_code [15:0]; // applied midpoint after CALC_APPLY

    // This signal is used to avoid data incoherence possibility when sending signals to SB.
    // It is set to 1 for 1 lclk cycle whenever the state changes, which is when the outputs are updated with new values.
    wire is_tx_sb_msg_valid;
    assign is_tx_sb_msg_valid =
        (current_state != previous_state) && (
            (current_state == DATAVREF_START_REQ ) ||
            (current_state == DATAVREF_START_RESP) ||
            (current_state == DATAVREF_END_REQ   ) ||
            (current_state == DATAVREF_END_RESP  ) );

    // >> =====================  For the DATAVREF stuck issue (To fix the issue of waiting for the SB message)  ===================== << //
    reg end_req_sb_msg_rcvd       ; // To detect the `end_req` SB MSG after the D2C_PT state. this is a flag.
    reg ready_for_end_resp_sb_msg ; // To detect the `ready_for_end_resp` after the D2C_PT state. this is a flag.
    always @(posedge datavref_if.lclk or negedge datavref_if.rst_n) begin : AFTER_D2C_PT_SB_MSGS
        if(!datavref_if.rst_n) begin
            end_req_sb_msg_rcvd       <= 1'b0;
            ready_for_end_resp_sb_msg <= 1'b0;
        end
        else if (current_state == DATAVREF_IDLE) begin // Reset the register once the LTSM gets out of reset.
            ready_for_end_resp_sb_msg <= 1'b0;
            end_req_sb_msg_rcvd       <= 1'b0;
        end
        else if(   (current_state == DATAVREF_SET_VREF_CODE ||
                    current_state == DATAVREF_RX_D2C_PT     ||
                    current_state == DATAVREF_LOG_RESULT    ||
                    current_state == DATAVREF_CALC_APPLY    ||
                    current_state == DATAVREF_END_REQ       ) &&
                datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_end_req && datavref_if.rx_sb_msg_valid == 1'b1) begin
            end_req_sb_msg_rcvd <= 1'b1;
        end
        else if (current_state == DATAVREF_END_REQ && (end_req_sb_msg_rcvd || (datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_end_req && datavref_if.rx_sb_msg_valid == 1'b1))) begin
            // Since we can't send 2 consecutive pulses on the signal `is_tx_sb_msg_valid` without a `0` in between for 1 lclk at least;
            // When this scenario happens when the partner Die applies less RX_D2C_PT iterations than our Die.
            // If we assume we won't use the `end_req_sb_msg_rcvd` signal, the FSM flow (in our Die) will be:
            //      [loop] -> 'DATAVREF_RX_D2C_PT' -> 'DATAVREF_LOG_RESULT' -> 'DATAVREF_CALC_APPLY' -> 'DATAVREF_END_REQ' (for 1 lclk duration) -> 'DATAVREF_END_RESP'
            // We need this signal `ready_for_end_resp_sb_msg` extend the waiting time to wait 2 lclk cycles at least in the FSM state 'DATAVREF_END_REQ' instead 1 lclk duration:
            //      1 lclk cycle for the HIGH period of the pulse.
            //      1 lclk cycle for the LOW  period of the pulse.
            ready_for_end_resp_sb_msg <= 1'b1;
        end
    end

    // >> =====================  For the RX_D2C_PT local-partner modules seperation  ===================== << //
    assign d2c_if.partner_tx_pt_en = 1'b0;
    always @(posedge datavref_if.lclk or negedge datavref_if.rst_n)
    begin
        if(!datavref_if.rst_n) begin
            d2c_if.partner_rx_pt_en <= 1'b0;
        end
        else if(current_state == DATAVREF_IDLE || current_state == DATAVREF_END_RESP) begin // To force the synchronization when we send and receive the {... end req} SB message.
            d2c_if.partner_rx_pt_en <= 1'b0;
        end
        else if(current_state == DATAVREF_SET_VREF_CODE ||
                current_state == DATAVREF_RX_D2C_PT     ||
                current_state == DATAVREF_LOG_RESULT    ||
                current_state == DATAVREF_CALC_APPLY    ||
                current_state == DATAVREF_END_REQ       ) begin
            if(d2c_if.partner_test_d2c_done) begin
                d2c_if.partner_rx_pt_en <= 1'b0;
            end else begin
                d2c_if.partner_rx_pt_en <= 1'b1;
            end
        end
    end
    // >> ===================== * ================================================ * ===================== << //


    // Current State Logic of the FSM:
    always @(posedge datavref_if.lclk or negedge datavref_if.rst_n) begin
        if (!datavref_if.rst_n) begin
            current_state  <= DATAVREF_IDLE;
            previous_state <= DATAVREF_IDLE;
        end
        else if (!datavref_if.is_ltsm_out_of_reset) begin
            current_state  <= DATAVREF_IDLE;
            previous_state <= DATAVREF_IDLE;
        end
        else begin
            current_state  <= next_state   ;
            previous_state <= current_state;
        end
    end

    // Next State Logic of the FSM:
    always_comb begin
        if (datavref_if.timeout_8ms_occured | (datavref_if.rx_sb_msg == TRAINERROR_Entry_req && datavref_if.rx_sb_msg_valid == 1'b1)) begin
            // (S10)
            next_state = TO_TRAINERROR; // If timeout or error occurs, transition to TRAINERROR state.
        end else begin
            case (current_state)
                // (S0) IDLE state: Wait for the trigger to start DATAVREF FSM.
                DATAVREF_IDLE: begin
                    if (datavref_if.datavref_en) next_state = DATAVREF_START_REQ;
                    else next_state = DATAVREF_IDLE;
                end
                // (S1) Send & Receive SB Message: {MBTRAIN.DATAVREF start req}
                DATAVREF_START_REQ: begin
                    if (datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_start_req && datavref_if.rx_sb_msg_valid == 1'b1) next_state = DATAVREF_START_RESP;
                    else next_state = DATAVREF_START_REQ;
                end
                // (S2) Send & Receive SB Message: {MBTRAIN.DATAVREF start resp}.
                DATAVREF_START_RESP: begin
                    if (datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_start_resp && datavref_if.rx_sb_msg_valid == 1'b1) next_state = DATAVREF_SET_VREF_CODE;
                    else next_state = DATAVREF_START_RESP;
                end
                // (S3) Drive Vref (swept_code_r) to PHY MB Receiver Data Lanes.
                DATAVREF_SET_VREF_CODE: begin
                    if (datavref_if.analog_settle_time_done) next_state = DATAVREF_RX_D2C_PT;
                    else next_state = DATAVREF_SET_VREF_CODE;
                end
                // (S4) Implement the test (Rx Init Data to Clock Point Test).
                DATAVREF_RX_D2C_PT: begin
                    if (d2c_if.local_test_d2c_done) next_state = DATAVREF_LOG_RESULT;
                    else next_state = DATAVREF_RX_D2C_PT;
                end
                // (S5) Log the current vref_code value if the received pattern on MB Receiver Data Lanes is valid.
                DATAVREF_LOG_RESULT: begin
                    if (swept_code_r == MAX_DATA_VREF_CODE) next_state = DATAVREF_CALC_APPLY;
                    else next_state = DATAVREF_SET_VREF_CODE;
                end
                // (S6) Caluculate the best value for vref_code for all 16 lanes independently.
                DATAVREF_CALC_APPLY: begin
                    next_state = DATAVREF_END_REQ;
                end
                // (S7) Send & Receive SB Message: {MBTRAIN.DATAVREF end req}.
                DATAVREF_END_REQ: begin
                    if (end_req_sb_msg_rcvd & ready_for_end_resp_sb_msg) next_state = DATAVREF_END_RESP;
                    else next_state = DATAVREF_END_REQ;
                end
                // (S8) Send & Receive SB Message: {MBTRAIN.DATAVREF end resp}.
                DATAVREF_END_RESP: begin
                    if (datavref_if.rx_sb_msg == MBTRAIN_DATAVREF_end_resp && datavref_if.rx_sb_msg_valid == 1'b1) next_state = TO_SPEEDIDLE;
                    else next_state = DATAVREF_END_RESP;
                end
                // (S9) Next sub-state.
                TO_SPEEDIDLE: begin
                    next_state = (datavref_if.datavref_en)? TO_SPEEDIDLE : DATAVREF_IDLE; // Stay here till "datavref_if.datavref_en" is cleared.
                end
                // (S10) TRAINERROR state:
                TO_TRAINERROR: begin
                    next_state = (datavref_if.datavref_en)? TO_TRAINERROR : DATAVREF_IDLE;
                end
                default: begin
                    next_state = (datavref_if.datavref_en)? TO_TRAINERROR : DATAVREF_IDLE; // Default case to avoid latches in synthesis.
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
        datavref_if.datavref_done  = 1'b0;
        datavref_if.trainerror_req = 1'b0;

        //==========================
        // Timers:
        //==========================
        datavref_if.timeout_timer_en       = 1;
        datavref_if.analog_settle_timer_en = 0;

        //=================================================
        // Control Signals For (Rx init D to C point test):
        //=================================================
        d2c_if.local_rx_pt_en = 1'b0; // To enable Rx init Data to Clock Point Test
        d2c_if.local_tx_pt_en = 1'b0; // To enable Tx init Data to Clock Point Test

        // Clock sampling.
        d2c_if.d2c_clk_sampling = 2'd0;  // Clock Phase control: Eye Center only.

        //-------------------- MB Rx/Tx Lane Pattern Configuration --------------------//
        // Received Tx Pattern Generator Setup Group:
        d2c_if.d2c_pattern_setup    = 3'b011; // Data Pattern with Valid lane framing.
        d2c_if.d2c_data_pattern_sel = 2'b00 ; // Data pattern used during training: LFSR
        d2c_if.d2c_val_pattern_sel  = 1'b1  ; // Held Low (don't care for data lanes)

        // Received Tx Pattern Mode Setup Group:
        d2c_if.d2c_pattern_mode =  1'D0  ; // 0: Continuous Pattern Mode, 1: Burst Pattern Mode.
        d2c_if.d2c_burst_count  = 16'D1  ; // Burst Count: Indicates the duration of selected pattern (UI count).
        d2c_if.d2c_idle_count   = 16'D0  ; // IDLE Count: Indicates the duration of low following the burst (UI count).
        d2c_if.d2c_iter_count   = 16'D128; // Iteration Count: Indicates the iteration count of bursts followed by idle.

        // Received Receiver Comparison Setup & Errors
        d2c_if.d2c_compare_setup = 2'D0; // 0: Per-Lane Comparison


        // //=========================
        // // MB signals:
        // //=========================
        // Lane Behavior Control
        datavref_if.mb_tx_clk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 10b: Tri-state (Tx Logical Clock Lane).
        datavref_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low, 01b: Active, 10b: Tri-state (Tx Logical Data Lanes).
        datavref_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 10b: Tri-state (Tx Logical Valid Lane).
        datavref_if.mb_tx_trk_lane_sel  = 2'b00; // 00b: Low, 01b: Active, 10b: Tri-state (Tx Logical Track Lane).
        datavref_if.mb_rx_clk_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Clock Lane).
        datavref_if.mb_rx_data_lane_sel = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Data Lanes).
        datavref_if.mb_rx_val_lane_sel  = 1'b1 ; // 0b: Disabled, 1b: Enabled (Rx Logical Valid Lane).
        datavref_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled, 1b: Enabled (Rx Logical Track Lane).


        //============================
        // SB signals:
        //============================
        // For SB TX:
        datavref_if.tx_sb_msg_valid = 1'h0   ; // Tell the SB that the selected message is valid.
        datavref_if.tx_sb_msg       = NOTHING; // Tell the Sideband the message that it should to send.
        datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
        datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.


        case (current_state)
            // (S0) IDLE state
            DATAVREF_IDLE: begin
                datavref_if.timeout_timer_en = 0;
            end
            // (S1) Send & Receive SB Message: {MBTRAIN.DATAVREF start req}
            DATAVREF_START_REQ: begin
                datavref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)     ; // Tell the SB that the selected message is valid.
                datavref_if.tx_sb_msg       = MBTRAIN_DATAVREF_start_req; // Tell the Sideband the message that it should to send.
                datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S2) Send & Receive SB Message: {MBTRAIN.DATAVREF start resp}.
            DATAVREF_START_RESP: begin
                datavref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)      ; // Tell the SB that the selected message is valid.
                datavref_if.tx_sb_msg       = MBTRAIN_DATAVREF_start_resp; // Tell the Sideband the message that it should to send.
                datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S3) Drive Vref
            DATAVREF_SET_VREF_CODE: begin
                datavref_if.analog_settle_timer_en = 1;
            end
            // (S4) Implement the test (Rx Init Data to Clock Point Test).
            DATAVREF_RX_D2C_PT: begin
                d2c_if.local_rx_pt_en = 1'b1; // To enable Rx init Data to Clock Point Test.
            end
            DATAVREF_LOG_RESULT: begin
                // Sequential logic handled in DATAVREF_LOG_RESULT_PROC
            end
            DATAVREF_CALC_APPLY: begin
                // Sequential logic handled in DATAVREF_CALC_APPLY_PROC
            end
            // (S7) Send & Receive SB Message: {MBTRAIN.DATAVREF end req}
            DATAVREF_END_REQ: begin
                datavref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)   ; // Tell the SB that the selected message is valid.
                datavref_if.tx_sb_msg       = MBTRAIN_DATAVREF_end_req; // Tell the Sideband the message that it should to send.
                datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S8) Send & Receive SB Message: {MBTRAIN.DATAVREF end resp}.
            DATAVREF_END_RESP: begin
                datavref_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)    ; // Tell the SB that the selected message is valid.
                datavref_if.tx_sb_msg       = MBTRAIN_DATAVREF_end_resp; // Tell the Sideband the message that it should to send.
                datavref_if.tx_msginfo      = 16'h0  ; // MsgInfo field of the SB message.
                datavref_if.tx_data_field   = 64'h0  ; // Data field of the SB message.
            end
            // (S9) Next Sub-state
            TO_SPEEDIDLE: begin
                datavref_if.datavref_done    = 1'b1;
                datavref_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end
            // (S10) TRAINERROR state:
            TO_TRAINERROR: begin
                datavref_if.datavref_done    = 1'b1;
                datavref_if.trainerror_req   = 1'b1;
                datavref_if.timeout_timer_en = 1'b0;   // No more timeout monitoring needed.
            end
            default: begin
            end
        endcase
    end
    // ==================================================
    // ==================================================
    // Data Vref Sweep Instantiation
    // ==================================================
    unit_data_sweep #(
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE(MIN_DATA_VREF_CODE)
    ) u_data_sweep (
        .lclk                (datavref_if.lclk),
        .rst_n               (datavref_if.rst_n),
        .is_ltsm_out_of_reset(datavref_if.is_ltsm_out_of_reset),
        .start_req_state     (current_state == DATAVREF_START_REQ),
        .log_result_state    (current_state == DATAVREF_LOG_RESULT),
        .calc_apply_state    (current_state == DATAVREF_CALC_APPLY),
        .mb_rx_data_lane_mask(datavref_if.mb_rx_data_lane_mask),
        .d2c_perlane_pass    (d2c_if.d2c_perlane_pass),
        .swept_code_r        (swept_code_r),
        .best_vref_code      (best_vref_code)
    );

    genvar lane;
    generate
        for(lane=0; lane<16; lane=lane+1) begin : VREF_CTRL_GEN
            // Drive swept_code_r to PHY during the sweep states (S1-S5),
            // then switch to the per-lane best midpoint (best_vref_code) afterwards.
            assign datavref_if.phy_rx_datavref_ctrl[lane] = (current_state == DATAVREF_START_REQ     ||
                    current_state == DATAVREF_START_RESP    ||
                    current_state == DATAVREF_SET_VREF_CODE ||
                    current_state == DATAVREF_RX_D2C_PT     ||
                    current_state == DATAVREF_LOG_RESULT) ? swept_code_r : best_vref_code[lane];
        end
    endgenerate

endmodule
