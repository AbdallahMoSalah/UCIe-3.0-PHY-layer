// =============================================================================
// Module  : unit_VALTRAINVREF
// Purpose : MBTRAIN.VALTRAINVREF sub-state FSM.
//           Optionally optimizes the Vref used to sample the incoming Valid
//           signal at the actual operating data rate (post-VALTRAINCENTER).
//           The receiver sweeps its local Vref while running a
//           "Receiver-initiated Data to Clock Point Test" using the unscrambled
//           VALTRAIN pattern (11110000).
//
//           Key Spec Compliance (LTSM_from_MBTRAIN_tables.txt lines 439-499):
//           ---------------------------------------------------------------------
//           S2 (START_RESP): If valtraincenter_fail_flag == 1 on resp rcvd ->
//                            skip Vref sweep and jump directly to S7 (END_REQ).
//           S5 (LOG_RESULT): No TRAINERROR on all-fail; just continue to S6
//                            and assert valtrainvref_fail_flag.
//           S6 (CALC_APPLY): Must wait analog_settle_timer before exiting.
//           SB messages: start_req/resp (d57/d58), end_req/resp (d59/d60),
//                        per UCIe Spec Table 7-9 (B5h/BAh, sub 0Ah/0Bh).
// =============================================================================
module unit_VALTRAINVREF #(
        parameter MAX_VAL_VREF_CODE   = 7'D127,
        parameter MIN_VAL_VREF_CODE   = 7'D10
    ) (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.valtrainvref_mp valtrainvref_if,
        // ======================= //
        // D2C signals.            //
        // ======================= //
        internal_ltsm_if.mbtrain2d2c_mp d2c_if
    );
    // D2C pattern test configuration.
    // Spec defaults: 128 iterations × 8-cycle burst = 1024 UI.
    localparam D2C_ITER_COUNT      = 16'D128;
    localparam D2C_BURST_COUNT     = 16'D8;
    // For analog Voltage control.
    localparam VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE + 1);
    // To get the used SB messages for: (valtrainvref_if.tx_sb_msg, valtrainvref_if.rx_sb_msg)
    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_VALTRAINVREF_start_req ; // Msg Number: d57 -- MsgCode B5h, SubCode 0Ah
    import UCIe_pkg::MBTRAIN_VALTRAINVREF_start_resp; // Msg Number: d58 -- MsgCode BAh, SubCode 0Ah
    import UCIe_pkg::MBTRAIN_VALTRAINVREF_end_req   ; // Msg Number: d59 -- MsgCode B5h, SubCode 0Bh
    import UCIe_pkg::MBTRAIN_VALTRAINVREF_end_resp  ; // Msg Number: d60 -- MsgCode BAh, SubCode 0Bh
    import UCIe_pkg::TRAINERROR_Entry_req            ; // Msg Number: d107
    import UCIe_pkg::NOTHING                         ; // Msg Number: 8'hFF
    // =====================================================================
    // State encoding (11 states total)
    // =====================================================================
    localparam  VALTRAINVREF_IDLE          = 4'h0, // (S0)  Wait for trigger
    VALTRAINVREF_START_REQ     = 4'h1, // (S1)  SB: VALTRAINVREF start req
    VALTRAINVREF_START_RESP    = 4'h2, // (S2)  SB: VALTRAINVREF start resp
    VALTRAINVREF_SET_VREF_CODE = 4'h3, // (S3)  Drive Vref; wait analog settle
    VALTRAINVREF_RX_D2C_PT     = 4'h4, // (S4)  Rx D-to-C point test
    VALTRAINVREF_LOG_RESULT    = 4'h5, // (S5)  Log pass/fail; bump vref_code
    VALTRAINVREF_CALC_APPLY    = 4'h6, // (S6)  Compute midpoint; wait analog settle
    VALTRAINVREF_END_REQ       = 4'h7, // (S7)  SB: VALTRAINVREF end req
    VALTRAINVREF_END_RESP      = 4'h8, // (S8)  SB: VALTRAINVREF end resp
    TO_DATATRAINCENTER1        = 4'h9, // (S9)  Signal done; wait en de-assert
    TO_TRAINERROR              = 4'hA; // (S10) Fatal timeout / TRAINERROR msg
    reg [3:0] current_state, next_state, previous_state;
    // Asserted for one lclk cycle whenever the state changes; gates tx_sb_msg_valid
    // to prevent sending a stale message during the transition clock.
    wire is_tx_sb_msg_valid;
    assign is_tx_sb_msg_valid =
        (current_state != previous_state) && (
            (current_state == VALTRAINVREF_START_REQ ) ||
            (current_state == VALTRAINVREF_START_RESP) ||
            (current_state == VALTRAINVREF_END_REQ   ) ||
            (current_state == VALTRAINVREF_END_RESP  ) );


    // >> =====================  For the VALTRAINVREF stuck issue (To fix the issue of waiting for the SB message)  ===================== << //
    reg end_req_sb_msg_rcvd       ; // To detect the `end_req` SB MSG after the D2C_PT state. this is a flag.
    reg ready_for_end_resp_sb_msg ; // To detect the `ready_for_end_resp` after the D2C_PT state. this is a flag.
    always @(posedge valtrainvref_if.lclk or negedge valtrainvref_if.rst_n) begin : AFTER_D2C_PT_SB_MSGS
        if(!valtrainvref_if.rst_n) begin
            end_req_sb_msg_rcvd       <= 1'b0;
            ready_for_end_resp_sb_msg <= 1'b0;
        end
        else if (current_state == VALTRAINVREF_IDLE) begin // Reset the register once the LTSM gets out of reset.
            ready_for_end_resp_sb_msg <= 1'b0;
            end_req_sb_msg_rcvd       <= 1'b0;
        end
        else if(   (current_state == VALTRAINVREF_SET_VREF_CODE ||
                    current_state == VALTRAINVREF_RX_D2C_PT     ||
                    current_state == VALTRAINVREF_LOG_RESULT    ||
                    current_state == VALTRAINVREF_CALC_APPLY    ||
                    current_state == VALTRAINVREF_END_REQ       ) &&
                valtrainvref_if.rx_sb_msg == MBTRAIN_VALTRAINVREF_end_req && valtrainvref_if.rx_sb_msg_valid == 1'b1) begin
            end_req_sb_msg_rcvd <= 1'b1;
        end
        else if (current_state == VALTRAINVREF_END_REQ && (end_req_sb_msg_rcvd || (valtrainvref_if.rx_sb_msg == MBTRAIN_VALTRAINVREF_end_req && valtrainvref_if.rx_sb_msg_valid == 1'b1))) begin
            // Since we can't send 2 consecutive pulses on the signal `is_tx_sb_msg_valid` without a `0` in between for 1 lclk at least;
            // When this scenario happens when the partner Die applies less RX_D2C_PT iterations than our Die.
            // If we assume we won't use the `end_req_sb_msg_rcvd` signal, the FSM flow (in our Die) will be:
            //      [loop] -> 'VALTRAINVREF_RX_D2C_PT' -> 'VALTRAINVREF_LOG_RESULT' -> 'VALTRAINVREF_CALC_APPLY' -> 'VALTRAINVREF_END_REQ' (for 1 lclk duration) -> 'VALTRAINVREF_END_RESP'
            // We need this signal `ready_for_end_resp_sb_msg` extend the waiting time to wait 2 lclk cycles at least in the FSM state 'VALTRAINVREF_END_REQ' instead 1 lclk duration:
            //      1 lclk cycle for the HIGH period of the pulse.
            //      1 lclk cycle for the LOW  period of the pulse.
            ready_for_end_resp_sb_msg <= 1'b1;
        end
    end

    // >> =====================  For the RX_D2C_PT local-partner modules seperation  ===================== << //
    assign d2c_if.partner_tx_pt_en = 1'b0;
    always @(posedge valtrainvref_if.lclk or negedge valtrainvref_if.rst_n)
    begin
        if(!valtrainvref_if.rst_n) begin
            d2c_if.partner_rx_pt_en <= 1'b0;
        end
        else if(current_state == VALTRAINVREF_IDLE || current_state == VALTRAINVREF_END_RESP) begin // To force the synchronization after we send and receive the {... end req} SB message.
            d2c_if.partner_rx_pt_en <= 1'b0;
        end
        else if(current_state == VALTRAINVREF_SET_VREF_CODE ||
                current_state == VALTRAINVREF_RX_D2C_PT     ||
                current_state == VALTRAINVREF_LOG_RESULT    ||
                current_state == VALTRAINVREF_CALC_APPLY    ||
                current_state == VALTRAINVREF_END_REQ       ) begin
            if(d2c_if.partner_test_d2c_done) begin
                d2c_if.partner_rx_pt_en <= 1'b0;
            end else begin
                d2c_if.partner_rx_pt_en <= 1'b1;
            end
        end
    end
    // >> ===================== * ================================================ * ===================== << //

    // =====================================================================
    // (Block 1) Sequential: Current-State Register
    // =====================================================================
    always_ff @(posedge valtrainvref_if.lclk or negedge valtrainvref_if.rst_n) begin
        if (!valtrainvref_if.rst_n) begin
            current_state  <= VALTRAINVREF_IDLE;
            previous_state <= VALTRAINVREF_IDLE;
        end
        else if (!valtrainvref_if.is_ltsm_out_of_reset) begin
            current_state  <= VALTRAINVREF_IDLE;
            previous_state <= VALTRAINVREF_IDLE;
        end
        else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end
    // =====================================================================
    // (Block 2) Combinational: Next-State Logic
    // =====================================================================
    always_comb begin
        // Global override: timeout or remote TRAINERROR message
        // NOTE: valtrainvref_fail_flag does NOT cause TRAINERROR here (spec
        //       line 482-488: "vref_code == MAX_VREF_CODE -> GOTO S6" -- fail
        //       flag is set then execution continues to notify partner via SB).
        if (valtrainvref_if.timeout_8ms_occured | (valtrainvref_if.rx_sb_msg == TRAINERROR_Entry_req && valtrainvref_if.rx_sb_msg_valid == 1'b1)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                // (S0) Wait for enable trigger from MBTRAIN controller.
                VALTRAINVREF_IDLE: begin
                    next_state = (valtrainvref_if.valtrainvref_en) ? VALTRAINVREF_START_REQ : VALTRAINVREF_IDLE;
                end
                // (S1) Handshake: {MBTRAIN.VALTRAINVREF start req}
                VALTRAINVREF_START_REQ: begin
                    next_state = (valtrainvref_if.rx_sb_msg == MBTRAIN_VALTRAINVREF_start_req && valtrainvref_if.rx_sb_msg_valid == 1'b1) ? VALTRAINVREF_START_RESP : VALTRAINVREF_START_REQ;
                end
                // (S2) Handshake: {MBTRAIN.VALTRAINVREF start resp}
                VALTRAINVREF_START_RESP: begin
                    if (valtrainvref_if.rx_sb_msg == MBTRAIN_VALTRAINVREF_start_resp && valtrainvref_if.rx_sb_msg_valid == 1'b1) begin
                        next_state = VALTRAINVREF_SET_VREF_CODE;
                    end else begin
                        next_state = VALTRAINVREF_START_RESP;
                    end
                end
                // (S3) Drive Vref to PHY Rx; wait analog settle.
                VALTRAINVREF_SET_VREF_CODE: begin
                    next_state = (valtrainvref_if.analog_settle_time_done) ? VALTRAINVREF_RX_D2C_PT : VALTRAINVREF_SET_VREF_CODE;
                end
                // (S4) Run sub-FSM: Rx-initiated Data-to-Clock point test.
                VALTRAINVREF_RX_D2C_PT: begin
                    next_state = (d2c_if.local_test_d2c_done) ? VALTRAINVREF_LOG_RESULT : VALTRAINVREF_RX_D2C_PT;
                end
                // (S5) Log result; continue sweep or finish.
                //      SPEC: vref_code < MAX -> S3.  vref_code == MAX -> S6.
                //            NO TRAINERROR on all-fail (valtrainvref_fail_flag set in S6).
                VALTRAINVREF_LOG_RESULT: begin
                    next_state = (valtrainvref_if.phy_rx_valvref_ctrl == MAX_VAL_VREF_CODE) ? VALTRAINVREF_CALC_APPLY : VALTRAINVREF_SET_VREF_CODE;
                end
                // (S6) Calculate midpoint Vref and apply; wait analog settle.
                //      SPEC: "wait till the value of Vref_code be settled. (wait analog timer)
                //             IF(analog timer finished) GOTO S7"
                VALTRAINVREF_CALC_APPLY: begin
                    next_state = (valtrainvref_if.analog_settle_time_done) ? VALTRAINVREF_END_REQ : VALTRAINVREF_CALC_APPLY;
                end
                // (S7) Handshake: {MBTRAIN.VALTRAINVREF end req}
                VALTRAINVREF_END_REQ: begin
                    next_state = (end_req_sb_msg_rcvd && ready_for_end_resp_sb_msg) ? VALTRAINVREF_END_RESP : VALTRAINVREF_END_REQ;
                end
                // (S8) Handshake: {MBTRAIN.VALTRAINVREF end resp}
                VALTRAINVREF_END_RESP: begin
                    next_state = (valtrainvref_if.rx_sb_msg == MBTRAIN_VALTRAINVREF_end_resp && valtrainvref_if.rx_sb_msg_valid == 1'b1) ? TO_DATATRAINCENTER1 : VALTRAINVREF_END_RESP;
                end
                // (S9) Assert done; hold until enable is de-asserted by controller.
                TO_DATATRAINCENTER1: begin
                    next_state = (valtrainvref_if.valtrainvref_en) ? TO_DATATRAINCENTER1 : VALTRAINVREF_IDLE;
                end
                // (S10) TRAINERROR: hold until enable de-asserted.
                TO_TRAINERROR: begin
                    next_state = (valtrainvref_if.valtrainvref_en) ? TO_TRAINERROR : VALTRAINVREF_IDLE;
                end
                default: begin
                    next_state = (valtrainvref_if.valtrainvref_en) ? TO_TRAINERROR : VALTRAINVREF_IDLE;
                end
            endcase
        end
    end
    // =====================================================================
    // (Block 3) Combinational: Output Logic
    // =====================================================================
    always_comb begin
        // Safe defaults (prevent latches)
        // --- LTSM handshake ---
        valtrainvref_if.valtrainvref_done = 1'b0;
        valtrainvref_if.trainerror_req    = 1'b0;
        // --- Timers ---
        valtrainvref_if.timeout_timer_en       = 1'b1; // run 8ms timer by default
        valtrainvref_if.analog_settle_timer_en = 1'b0;
        // --- Rx D-to-C point test controls ---
        d2c_if.local_rx_pt_en = 1'b0;
        d2c_if.local_tx_pt_en = 1'b0;
        // Clock sampling: Eye Center.
        d2c_if.d2c_clk_sampling = 2'b00;
        // MB lane pattern: VALTRAIN on Valid lane, data lanes held Low.
        //   mb_tx_data_pattern_sel = 2'b11 → all-zero "data" (held Low).
        //   mb_tx_val_pattern_sel  = 1'b0  → VALTRAIN (11110000) pattern.
        d2c_if.d2c_pattern_setup    = 3'b010; // 010b: Valid Pattern active
        d2c_if.d2c_data_pattern_sel = 2'b11 ; // all-zero (data lanes Low)
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // VALTRAIN pattern
        d2c_if.d2c_pattern_mode =  1'b1     ; // Burst Mode for proper D2C wrapper iteration handling
        d2c_if.d2c_burst_count  = D2C_BURST_COUNT;
        d2c_if.d2c_idle_count   = 16'D0     ;
        d2c_if.d2c_iter_count   = D2C_ITER_COUNT;
        // Valid Lane comparison.
        d2c_if.d2c_compare_setup = 2'D2; // 2: Valid Lane Comparison
        // MB lane direction / enables (mirrors VALVREF):
        //   Clk Tx: Active (forward clock).
        //   Data Tx: Low (not active).
        //   Valid Tx: Active (VALTRAIN pattern).
        //   Track Tx: Tri-state.
        valtrainvref_if.mb_tx_clk_lane_sel  = 2'b01; // Active
        valtrainvref_if.mb_tx_data_lane_sel = 2'b00; // Low
        valtrainvref_if.mb_tx_val_lane_sel  = 2'b01; // Active
        valtrainvref_if.mb_tx_trk_lane_sel  = 2'b00; // Low
        valtrainvref_if.mb_rx_clk_lane_sel  = 1'b1 ; // Enabled
        valtrainvref_if.mb_rx_data_lane_sel = 1'b0 ; // Disabled
        valtrainvref_if.mb_rx_val_lane_sel  = 1'b1 ; // Enabled
        valtrainvref_if.mb_rx_trk_lane_sel  = 1'b0 ; // Disabled
        // SB TX defaults.
        valtrainvref_if.tx_sb_msg_valid = 1'b0   ;
        valtrainvref_if.tx_sb_msg       = NOTHING;
        valtrainvref_if.tx_msginfo      = 16'h0  ;
        valtrainvref_if.tx_data_field   = 64'h0  ;
        // Per-state output overrides
        case (current_state)
            // (S0) IDLE: timeout timer disabled while waiting for trigger.
            VALTRAINVREF_IDLE: begin
                valtrainvref_if.timeout_timer_en = 1'b0;
            end
            // (S1) Send {MBTRAIN.VALTRAINVREF start req}.
            VALTRAINVREF_START_REQ: begin
                valtrainvref_if.tx_sb_msg_valid = is_tx_sb_msg_valid              ;
                valtrainvref_if.tx_sb_msg       = MBTRAIN_VALTRAINVREF_start_req ;
                valtrainvref_if.tx_msginfo      = 16'h0                          ;
                valtrainvref_if.tx_data_field   = 64'h0                          ;
            end
            // (S2) Send {MBTRAIN.VALTRAINVREF start resp}.
            VALTRAINVREF_START_RESP: begin
                valtrainvref_if.tx_sb_msg_valid = is_tx_sb_msg_valid               ;
                valtrainvref_if.tx_sb_msg       = MBTRAIN_VALTRAINVREF_start_resp ;
                valtrainvref_if.tx_msginfo      = 16'h0                           ;
                valtrainvref_if.tx_data_field   = 64'h0                           ;
            end
            // (S3) Drive Vref; enable analog settle timer.
            VALTRAINVREF_SET_VREF_CODE: begin
                valtrainvref_if.analog_settle_timer_en = 1'b1;
            end
            // (S4) Enable Rx D-to-C point test sub-FSM.
            VALTRAINVREF_RX_D2C_PT: begin
                d2c_if.local_rx_pt_en = 1'b1;
            end
            // (S5) LOG_RESULT: sequential logic only — see VALTRAINVREF_LOG_RESULT_PROC.
            VALTRAINVREF_LOG_RESULT: begin
                /* no combinational outputs; all work done in sequential block */
            end
            // (S6) CALC_APPLY: wait analog settle after applying midpoint Vref.
            VALTRAINVREF_CALC_APPLY: begin
                valtrainvref_if.analog_settle_timer_en = 1'b1;
                // NOTE: the sequential block (VALTRAINVREF_CALC_APPLY_PROC) drives
                // phy_rx_valvref_ctrl to the midpoint on the cycle we enter this state.
            end
            // (S7) Send {MBTRAIN.VALTRAINVREF end req}.
            VALTRAINVREF_END_REQ: begin
                valtrainvref_if.tx_sb_msg_valid = is_tx_sb_msg_valid             ;
                valtrainvref_if.tx_sb_msg       = MBTRAIN_VALTRAINVREF_end_req  ;
                valtrainvref_if.tx_msginfo      = 16'h0                         ;
                valtrainvref_if.tx_data_field   = 64'h0                         ;
            end
            // (S8) Send {MBTRAIN.VALTRAINVREF end resp}.
            VALTRAINVREF_END_RESP: begin
                valtrainvref_if.tx_sb_msg_valid = is_tx_sb_msg_valid              ;
                valtrainvref_if.tx_sb_msg       = MBTRAIN_VALTRAINVREF_end_resp  ;
                valtrainvref_if.tx_msginfo      = 16'h0                          ;
                valtrainvref_if.tx_data_field   = 64'h0                          ;
            end
            // (S9) Done — activate next sub-state MBTRAIN.DATATRAINCENTER1.
            TO_DATATRAINCENTER1: begin
                valtrainvref_if.valtrainvref_done  = 1'b1;
                valtrainvref_if.timeout_timer_en   = 1'b0;
            end
            // (S10) TRAINERROR.
            TO_TRAINERROR: begin
                valtrainvref_if.valtrainvref_done  = 1'b1;
                valtrainvref_if.trainerror_req     = 1'b1;
                valtrainvref_if.timeout_timer_en   = 1'b0;
            end
            default: begin /* latches prevented by defaults above */ end
        endcase
    end
    // =====================================================================
    // Vref sweep data-path: registers tracking widest contiguous pass zone
    // =====================================================================
    wire valtrainvref_fail_flag;
    unit_val_sweep #(
        .MAX_VAL_VREF_CODE(MAX_VAL_VREF_CODE),
        .MIN_VAL_VREF_CODE(MIN_VAL_VREF_CODE)
    ) u_val_sweep (
        .lclk                 (valtrainvref_if.lclk),
        .rst_n                (valtrainvref_if.rst_n),
        .is_ltsm_out_of_reset (valtrainvref_if.is_ltsm_out_of_reset),
        .start_req_state      (current_state == VALTRAINVREF_START_REQ),
        .log_result_state     (current_state == VALTRAINVREF_LOG_RESULT),
        .calc_apply_state     (current_state == VALTRAINVREF_CALC_APPLY),
        .d2c_val_pass         (d2c_if.d2c_val_pass),
        .phy_rx_valvref_ctrl  (valtrainvref_if.phy_rx_valvref_ctrl),
        .valvref_fail_flag    (valtrainvref_fail_flag)
    );

    // // Asserted when sweep completes and no passing Vref was found.
    // // Registered so the flag remains valid past CALC_APPLY and is
    // // readable by the MBTRAIN controller after valtrainvref_done is asserted.
    // reg valtrainvref_fail_flag_r;
    // always_ff @(posedge valtrainvref_if.lclk or negedge valtrainvref_if.rst_n) begin
    //     if (!valtrainvref_if.rst_n) begin
    //         valtrainvref_fail_flag_r <= 1'b0;
    //     end else if (current_state == VALTRAINVREF_START_REQ) begin
    //         valtrainvref_fail_flag_r <= 1'b0;
    //     end else if (current_state == VALTRAINVREF_CALC_APPLY) begin
    //         valtrainvref_fail_flag_r <= valtrainvref_fail_flag;
    //     end
    // end
    // assign valtrainvref_if.valtrainvref_fail_flag = valtrainvref_fail_flag_r;

endmodule
