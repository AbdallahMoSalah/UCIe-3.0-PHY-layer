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
        internal_ltsm_if.substate2d2c_mp d2c_if
    );
    // For analog Voltage control.
    localparam VREF_CODE_WIDTH = $clog2(MAX_VAL_VREF_CODE);

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
    wire data_incoherence;

    // Asserted for one lclk cycle whenever the state changes; gates tx_sb_msg_valid
    // to prevent sending a stale message during the transition clock.
    assign data_incoherence = (current_state != previous_state) ? 1'b1 : 1'b0;

    // =====================================================================
    // (Block 1) Sequential: Current-State Register
    // =====================================================================
    always @(posedge valtrainvref_if.lclk or negedge valtrainvref_if.rst_n) begin
        if (!valtrainvref_if.rst_n) begin
            current_state  <= VALTRAINVREF_IDLE;
            previous_state <= VALTRAINVREF_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // =====================================================================
    // (Block 2) Combinational: Next-State Logic
    // =====================================================================
    always @(*) begin
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
                //      SPEC: if valtraincenter_fail_flag == 1 → skip sweep → S7
                //            if valtraincenter_fail_flag == 0 → run sweep  → S3
                VALTRAINVREF_START_RESP: begin
                    if (valtrainvref_if.rx_sb_msg == MBTRAIN_VALTRAINVREF_start_resp && valtrainvref_if.rx_sb_msg_valid == 1'b1) begin
                        // valtraincenter_fail_flag is an INPUT: set by the previous
                        // VALTRAINCENTER sub-state and read here via the interface.
                        next_state = (valtrainvref_if.valtraincenter_fail_flag || d2c_if.partner_valtraincenter_fail_flag) ? VALTRAINVREF_END_REQ : VALTRAINVREF_SET_VREF_CODE;
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
                    next_state = (d2c_if.test_d2c_done) ? VALTRAINVREF_LOG_RESULT : VALTRAINVREF_RX_D2C_PT;
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
                    next_state = (valtrainvref_if.rx_sb_msg == MBTRAIN_VALTRAINVREF_end_req && valtrainvref_if.rx_sb_msg_valid == 1'b1) ? VALTRAINVREF_END_RESP : VALTRAINVREF_END_REQ;
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
    always @(*) begin
        // Safe defaults (prevent latches)

        // --- LTSM handshake ---
        valtrainvref_if.valtrainvref_done = 1'b0;
        valtrainvref_if.trainerror_req    = 1'b0;

        // --- Timers ---
        valtrainvref_if.timeout_timer_en       = 1'b1; // run 8ms timer by default
        valtrainvref_if.analog_settle_timer_en = 1'b0;

        // --- Rx D-to-C point test controls ---
        d2c_if.rx_pt_en = 1'b0;
        d2c_if.tx_pt_en = 1'b0;

        // Clock sampling: Eye Center.
        d2c_if.d2c_clk_sampling = 2'b00;

        // MB lane pattern: VALTRAIN on Valid lane, data lanes held Low.
        //   mb_tx_data_pattern_sel = 2'b11 → all-zero "data" (held Low).
        //   mb_tx_val_pattern_sel  = 1'b0  → VALTRAIN (11110000) pattern.
        d2c_if.d2c_lfsr_en          = 1'b0  ;
        d2c_if.d2c_pattern_setup    = 3'b010; // 010b: Valid Pattern active
        d2c_if.d2c_data_pattern_sel = 2'b11 ; // all-zero (data lanes Low)
        d2c_if.d2c_val_pattern_sel  = 1'b0  ; // VALTRAIN pattern

        d2c_if.d2c_pattern_mode =  1'b0     ; // Continuous
        d2c_if.d2c_burst_count  = 16'D1024  ; // 128 iteration = 128 * 8 UI = 1024 UI per spec S4
        d2c_if.d2c_idle_count   = 16'D0     ;
        d2c_if.d2c_iter_count   = 16'D1     ;

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
                valtrainvref_if.tx_sb_msg_valid = !data_incoherence              ;
                valtrainvref_if.tx_sb_msg       = MBTRAIN_VALTRAINVREF_start_req ;
                valtrainvref_if.tx_msginfo      = 16'h0                          ;
                valtrainvref_if.tx_data_field   = 64'h0                          ;
            end

            // (S2) Send {MBTRAIN.VALTRAINVREF start resp}.
            VALTRAINVREF_START_RESP: begin
                valtrainvref_if.tx_sb_msg_valid = !data_incoherence               ;
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
                d2c_if.rx_pt_en = 1'b1;
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
                valtrainvref_if.tx_sb_msg_valid = !data_incoherence             ;
                valtrainvref_if.tx_sb_msg       = MBTRAIN_VALTRAINVREF_end_req  ;
                valtrainvref_if.tx_msginfo      = 16'h0                         ;
                valtrainvref_if.tx_data_field   = 64'h0                         ;
            end

            // (S8) Send {MBTRAIN.VALTRAINVREF end resp}.
            VALTRAINVREF_END_RESP: begin
                valtrainvref_if.tx_sb_msg_valid = !data_incoherence              ;
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
    wire [VREF_CODE_WIDTH-1:0] vref_range    ; // width of best stored zone
    wire [VREF_CODE_WIDTH-1:0] temp_vref_range; // width of current zone being measured
    reg  [VREF_CODE_WIDTH-1:0] temp_min_vref ;  // start of current success zone
    reg  [VREF_CODE_WIDTH-1:0] min_vref_code ;  // start of widest success zone
    reg  [VREF_CODE_WIDTH-1:0] max_vref_code ;  // end   of widest success zone
    reg                        vref_code_filled; // 1 = at least one pass found

    assign vref_range      = vref_code_filled ? (max_vref_code - min_vref_code) : '0;
    assign temp_vref_range = (valtrainvref_if.phy_rx_valvref_ctrl - temp_min_vref);

    // valtrainvref_fail_flag:
    //   Asserted when sweep completes and no passing Vref was found.
    //   Per spec: this does NOT cause TRAINERROR; instead the FSM continues
    //   to S7/S8/S9 to complete the SB handshake and report the flag upstream.
    //
    //   IMPORTANT: Registered so the flag remains valid past CALC_APPLY and is
    //   readable by the MBTRAIN controller after valtrainvref_done is asserted.
    //   A purely combinational version (gated on current_state == CALC_APPLY)
    //   would silently drop back to 0 the moment the FSM exits that state.
    reg valtrainvref_fail_flag_r;

    always @(posedge valtrainvref_if.lclk or negedge valtrainvref_if.rst_n) begin : VALTRAINVREF_FAIL_FLAG_PROC
        if (!valtrainvref_if.rst_n) begin
            valtrainvref_fail_flag_r <= 1'b0;
        end else if (current_state == VALTRAINVREF_START_REQ) begin
            // Clear at the start of each run (supports back-to-back without reset).
            valtrainvref_fail_flag_r <= 1'b0;
        end else if (current_state == VALTRAINVREF_CALC_APPLY) begin
            // Latch result once it is known; stays high through S7 / S8 / S9.
            valtrainvref_fail_flag_r <= ~vref_code_filled;
        end
    end

    // Drive to modport output.
    assign valtrainvref_if.valtrainvref_fail_flag = valtrainvref_fail_flag_r;

    // Sequential: Vref code control (swept_code_r = phy_rx_valvref_ctrl)
    //
    // Unified signal names (for cross-module readability):
    //   valtrainvref_if.phy_rx_valvref_ctrl <-> swept_code_r (both sweep code and result)
    //   is_in_valid_region                  <-> zone_valid
    //   vref_code_filled                    <-> found_pass
    //   temp_min_vref                       <-> zone_min_r
    //   min_vref_code                       <-> best_lo
    //   max_vref_code                       <-> best_hi
    //
    // Two-zone algorithm (same as VALVREF / DATAVREF / DTVREF companion modules):
    //   Zone A (new contiguous pass zone starts):
    //     is_in_valid_region 0->1; temp_min_vref = swept_code_r (zone_min_r).
    //     If first-ever pass (vref_code_filled==0): seed min/max_vref_code.
    //   Zone B (extending the contiguous pass zone):
    //     If temp_vref_range (zone_range) > vref_range (best_range):
    //       update min_vref_code (best_lo) and max_vref_code (best_hi).
    //   Fail: is_in_valid_region -> 0 (hole detected in Valid-lane Vref eye).
    always @(posedge valtrainvref_if.lclk or negedge valtrainvref_if.rst_n) begin : VALTRAINVREF_CALC_APPLY_PROC
        if (!valtrainvref_if.rst_n) begin
            valtrainvref_if.phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE;
        end
        // Reset sweep at start of each run (allows back-to-back without full reset).
        else if (current_state == VALTRAINVREF_START_REQ) begin
            valtrainvref_if.phy_rx_valvref_ctrl <= MIN_VAL_VREF_CODE;
        end
        // Increment Vref after logging each result.
        else if (current_state == VALTRAINVREF_LOG_RESULT) begin
            if (valtrainvref_if.phy_rx_valvref_ctrl != MAX_VAL_VREF_CODE) begin
                valtrainvref_if.phy_rx_valvref_ctrl <= valtrainvref_if.phy_rx_valvref_ctrl + 1;
            end
        end
        // Apply best (midpoint) Vref when sweep is complete.
        else if (current_state == VALTRAINVREF_CALC_APPLY) begin
            if (vref_code_filled) begin
                // Midpoint of widest contiguous pass window.
                valtrainvref_if.phy_rx_valvref_ctrl <=
                    ({1'b0, min_vref_code} + {1'b0, max_vref_code}) >> 1;
            end else begin
                valtrainvref_if.phy_rx_valvref_ctrl <= '0; // fallback; fail flag asserted
            end
        end
    end

    // Sequential: Eye-map tracking (widest contiguous pass window)
    reg is_in_valid_region;

    always @(posedge valtrainvref_if.lclk or negedge valtrainvref_if.rst_n) begin : VALTRAINVREF_LOG_RESULT_PROC
        if (!valtrainvref_if.rst_n) begin
            min_vref_code      <= '0;
            max_vref_code      <= '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'b0;
            temp_min_vref      <= '0;
        end
        // Clear log at the start of each new run.
        else if (current_state == VALTRAINVREF_START_REQ) begin
            min_vref_code      <= '0;
            max_vref_code      <= '0;
            vref_code_filled   <= 1'b0;
            is_in_valid_region <= 1'b0;
            temp_min_vref      <= '0;
        end
        else if (current_state == VALTRAINVREF_LOG_RESULT) begin
            if (!d2c_if.d2c_val_err) begin
                // PASS: start or extend the contiguous pass zone.
                if (!is_in_valid_region || valtrainvref_if.phy_rx_valvref_ctrl == MIN_VAL_VREF_CODE) begin
                    // Start a new contiguous success zone.
                    is_in_valid_region <= 1'b1;
                    temp_min_vref      <= valtrainvref_if.phy_rx_valvref_ctrl;
                    if (!vref_code_filled) begin
                        // Very first pass point -- record it as both min and max.
                        vref_code_filled <= 1'b1;
                        min_vref_code    <= valtrainvref_if.phy_rx_valvref_ctrl;
                        max_vref_code    <= valtrainvref_if.phy_rx_valvref_ctrl;
                    end
                end else begin
                    // Continuing inside a success zone — update best window if wider.
                    if (temp_vref_range > vref_range) begin
                        min_vref_code <= temp_min_vref;
                        max_vref_code <= valtrainvref_if.phy_rx_valvref_ctrl;
                    end
                end
            end else begin
                // FAIL: break the current contiguous zone; next pass starts a fresh zone.
                is_in_valid_region <= 1'b0;
            end
        end
    end

endmodule
