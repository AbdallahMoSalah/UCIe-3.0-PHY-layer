// =============================================================================
// Module  : unit_RXDESKEW
// Purpose : MBTRAIN.RXDESKEW sub-state FSM.
//           Removes per-lane timing skew from Rx data lanes.  At speeds >32 GT/s
//           it also iterates through TX EQ presets and re-enters DATATRAINCENTER1
//           up to 4 times per preset to find the optimal EQ+deskew combination.
//
//           Key Spec Compliance (LTSM_from_MBTRAIN_tables.txt lines 627-735):
//           ─────────────────────────────────────────────────────────────────
//           S2: Speed≤32 + no accumulated fail → S3 (deskew sweep).
//               Speed≤32 + accumulated fail → S7 (exit for speed-degrade).
//               Speed>32 → S10 (EQ preset loop).
//           S10 (CHOOSE_PRESET): Change preset if accumulative_error.
//           S11-S12 (PRESET_REQ/RESP): Negotiate chosen preset with partner.
//           S13 (PRESET_CHECK): Decide if both dies need DTC1 re-entry.
//           S14 (LOOP_CHECK): Up to 4 DTC1 iterations per preset.
//           S15-S16 (EXIT_TO_DTC1_REQ/RESP): Handshake to re-enter DTC1.
//           S17 (TO_DTC1): Signal controller to run DTC1; re-enter at IDLE2.
//           IDLE2 (S18): Re-entry after DTC1; does NOT reset dtc1_loop_cnt.
//           SB: start(d69/d70), preset_req(d73/d74), end(d75/d76).
// =============================================================================

module unit_RXDESKEW #(
        parameter MAX_DESKEW_CODE = 7'h7F,
        parameter MIN_DESKEW_CODE = 7'h00,
        parameter MAX_EQ_PRESET   = 3'h5 , // P0-P5 (6 presets)
        parameter SPEED_32GTS     = 3'd5    // param_negotiated_max_speed value for 32GT/s
    ) (
        internal_ltsm_if.rxdeskew_mp    rxdeskew_if,
        internal_ltsm_if.substate2d2c_mp d2c_if
    );

    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_RXDESKEW_start_req                     ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_start_resp                    ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req  ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_end_req                       ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_end_resp                      ;
    import UCIe_pkg::TRAINERROR_Entry_req;
    import UCIe_pkg::NOTHING             ;

    // =====================================================================
    // State encoding (20 states)
    // =====================================================================
    localparam  RXDESKEW_IDLE         = 5'h00, // (S0)
    RXDESKEW_START_REQ        = 5'h01, // (S1)
    RXDESKEW_START_RESP       = 5'h02, // (S2)
    RXDESKEW_SET_DESKEW_CODE  = 5'h03, // (S3)
    RXDESKEW_RX_D2C_PT        = 5'h04, // (S4)
    RXDESKEW_LOG_RESULT       = 5'h05, // (S5)
    RXDESKEW_CALC_APPLY       = 5'h06, // (S6)
    RXDESKEW_END_REQ          = 5'h07, // (S7)
    RXDESKEW_END_RESP         = 5'h08, // (S8)
    TO_DTC2                   = 5'h09, // (S9)
    RXDESKEW_CHOOSE_PRESET    = 5'h0A, // (S10)
    RXDESKEW_PRESET_REQ       = 5'h0B, // (S11)
    RXDESKEW_PRESET_RESP      = 5'h0C, // (S12)
    RXDESKEW_PRESET_CHECK     = 5'h0D, // (S13)
    RXDESKEW_LOOP_CHECK       = 5'h0E, // (S14)
    RXDESKEW_EXIT_DTC1_REQ    = 5'h0F, // (S15)
    RXDESKEW_EXIT_DTC1_RESP   = 5'h10, // (S16)
    TO_DTC1                   = 5'h11, // (S17)
    RXDESKEW_IDLE2            = 5'h12, // (S18) Re-entry after DTC1
    TO_TRAINERROR             = 5'h13; // (S19)

    reg [4:0] current_state, next_state, previous_state;
    wire data_incoherence;
    assign data_incoherence = (current_state != previous_state);

    // Signals decoded from SB rx payload
    wire partner_has_new_preset = rxdeskew_if.rx_msginfo[0]; // Bit 0 of MsgInfo
    wire partner_accum_error    = rxdeskew_if.rx_msginfo[1]; // Bit 1

    // EQ preset tracking
    reg [2:0]  current_eq_preset;   // Our current EQ preset (P0-P5)
    reg [2:0]  dtc1_loop_cnt  ;     // DTC1 re-entry loop counter (max 4)
    reg        is_my_preset_new;     // Did we just change our preset?
    reg        preset_error_flag;    // All presets exhausted with accumulated errors
    reg        preset_fail_flag1;    // Current target preset invalid
    reg        preset_fail_flag2;    // All presets failed
    reg        r_first_entry_rxdeskew; // True = first entry since reset

    // Accumulated error flag (OR of upstream failures)
    wire accumulative_error = rxdeskew_if.valtraincenter_fail_flag |
                              rxdeskew_if.datatraincenter1_fail_flag;

    // Speed > 32 GT/s gate
    wire speed_gt_32 = (rxdeskew_if.param_negotiated_max_speed > SPEED_32GTS);

    // Deskew code
    reg [6:0] deskew_code;

    // ── Tracks whether we are in a DTC1 re-entry loop ────────────────────
    reg in_dtc1_loop_r; // 1 when FSM is doing DTC1 re-entries for preset calibration

    // ── Applied deskew and EQ registers driven from output block ─────────
    reg [6:0] deskew_applied_r;

    // Fail flag (registered)
    reg rxdeskew_fail_flag_r;
    assign rxdeskew_if.rxdeskew_fail_flag = rxdeskew_fail_flag_r;

    // =====================================================================
    // (Block 1) Sequential: current state
    // =====================================================================
    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin
        if (!rxdeskew_if.rst_n) begin
            current_state  <= RXDESKEW_IDLE;
            previous_state <= RXDESKEW_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // =====================================================================
    // (Block 2) Combinational: next state
    // =====================================================================
    always @(*) begin
        if (rxdeskew_if.timeout_8ms_occured |
            (rxdeskew_if.rx_sb_msg == TRAINERROR_Entry_req &&
             rxdeskew_if.rx_sb_msg_valid)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                RXDESKEW_IDLE: begin
                    next_state = (rxdeskew_if.rxdeskew_en) ?
                                  RXDESKEW_START_REQ : RXDESKEW_IDLE;
                end
                RXDESKEW_IDLE2: begin
                    // Re-entry after DTC1 — loop_cnt NOT reset here.
                    next_state = (rxdeskew_if.rxdeskew_en) ?
                                  RXDESKEW_START_REQ : RXDESKEW_IDLE2;
                end
                RXDESKEW_START_REQ: begin
                    next_state = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_start_req &&
                                  rxdeskew_if.rx_sb_msg_valid) ?
                                  RXDESKEW_START_RESP : RXDESKEW_START_REQ;
                end
                RXDESKEW_START_RESP: begin
                    if (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_start_resp &&
                        rxdeskew_if.rx_sb_msg_valid) begin
                        if (speed_gt_32 && in_dtc1_loop_r)
                            next_state = RXDESKEW_LOOP_CHECK;       // Re-entry: skip CHOOSE
                        else if (speed_gt_32 && !in_dtc1_loop_r)
                            next_state = RXDESKEW_CHOOSE_PRESET;    // S10 (first entry)
                        else if (!accumulative_error)
                            next_state = RXDESKEW_SET_DESKEW_CODE;  // S3
                        else
                            next_state = RXDESKEW_END_REQ;          // S7 (speed degrade)
                    end else begin
                        next_state = RXDESKEW_START_RESP;
                    end
                end
                RXDESKEW_SET_DESKEW_CODE: begin
                    next_state = (rxdeskew_if.analog_settle_time_done) ?
                                  RXDESKEW_RX_D2C_PT : RXDESKEW_SET_DESKEW_CODE;
                end
                RXDESKEW_RX_D2C_PT: begin
                    next_state = (d2c_if.test_d2c_done) ?
                                  RXDESKEW_LOG_RESULT : RXDESKEW_RX_D2C_PT;
                end
                RXDESKEW_LOG_RESULT: begin
                    next_state = (deskew_code == MAX_DESKEW_CODE) ?
                                  RXDESKEW_CALC_APPLY : RXDESKEW_SET_DESKEW_CODE;
                end
                RXDESKEW_CALC_APPLY: begin
                    // Speed≤32: go directly to END; speed>32 goes through already
                    next_state = RXDESKEW_END_REQ;
                end
                RXDESKEW_END_REQ: begin
                    next_state = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_end_req &&
                                  rxdeskew_if.rx_sb_msg_valid) ?
                                  RXDESKEW_END_RESP : RXDESKEW_END_REQ;
                end
                RXDESKEW_END_RESP: begin
                    next_state = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_end_resp &&
                                  rxdeskew_if.rx_sb_msg_valid) ?
                                  TO_DTC2 : RXDESKEW_END_RESP;
                end
                TO_DTC2: begin
                    next_state = (rxdeskew_if.rxdeskew_en) ?
                                  TO_DTC2 : RXDESKEW_IDLE;
                end
                // EQ Preset loop (speed > 32 GT/s path) ────────────────────
                RXDESKEW_CHOOSE_PRESET: begin
                    // Wait for analog settle if we changed the preset.
                    if (accumulative_error) begin
                        next_state = (rxdeskew_if.analog_settle_time_done) ?
                                      RXDESKEW_PRESET_REQ : RXDESKEW_CHOOSE_PRESET;
                    end else begin
                        next_state = RXDESKEW_PRESET_REQ; // No change → no settle needed
                    end
                end
                RXDESKEW_PRESET_REQ: begin
                    next_state = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req &&
                                  rxdeskew_if.rx_sb_msg_valid) ?
                                  RXDESKEW_PRESET_RESP : RXDESKEW_PRESET_REQ;
                end
                RXDESKEW_PRESET_RESP: begin
                    next_state = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp &&
                                  rxdeskew_if.rx_sb_msg_valid) ?
                                  RXDESKEW_PRESET_CHECK : RXDESKEW_PRESET_RESP;
                end
                RXDESKEW_PRESET_CHECK: begin
                    if (preset_fail_flag1)
                        next_state = RXDESKEW_CHOOSE_PRESET; // Try next preset
                    else if (preset_fail_flag2 || rxdeskew_if.valtraincenter_fail_flag)
                        next_state = RXDESKEW_END_REQ;       // Speed-degrade exit
                    else if (!is_my_preset_new && !partner_has_new_preset &&
                             !accumulative_error)
                        next_state = RXDESKEW_SET_DESKEW_CODE; // No new preset → deskew
                    else
                        next_state = RXDESKEW_LOOP_CHECK;   // New preset → DTC1 loop
                end
                RXDESKEW_LOOP_CHECK: begin
                    if (dtc1_loop_cnt < 4)
                        next_state = RXDESKEW_EXIT_DTC1_REQ;
                    else
                        next_state = RXDESKEW_END_REQ; // 4 iterations done
                end
                RXDESKEW_EXIT_DTC1_REQ: begin
                    next_state = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req &&
                                  rxdeskew_if.rx_sb_msg_valid) ?
                                  RXDESKEW_EXIT_DTC1_RESP : RXDESKEW_EXIT_DTC1_REQ;
                end
                RXDESKEW_EXIT_DTC1_RESP: begin
                    next_state = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp &&
                                  rxdeskew_if.rx_sb_msg_valid) ?
                                  TO_DTC1 : RXDESKEW_EXIT_DTC1_RESP;
                end
                TO_DTC1: begin
                    // Hold until controller ACKs (clears rxdeskew_en, runs DTC1,
                    // then re-asserts rxdeskew_en). Transition to IDLE2 on re-assert.
                    next_state = (rxdeskew_if.rxdeskew_en) ?
                                  TO_DTC1 : RXDESKEW_IDLE2;
                end
                TO_TRAINERROR: begin
                    next_state = (rxdeskew_if.rxdeskew_en) ?
                                  TO_TRAINERROR : RXDESKEW_IDLE;
                end
                default: next_state = (rxdeskew_if.rxdeskew_en) ?
                                       TO_TRAINERROR : RXDESKEW_IDLE;
            endcase
        end
    end

    // =====================================================================
    // (Block 3) Combinational: outputs
    // =====================================================================
    always @(*) begin
        rxdeskew_if.rxdeskew_done        = 1'b0;
        rxdeskew_if.trainerror_req       = 1'b0;
        rxdeskew_if.datatraincenter1_req = 1'b0;
        rxdeskew_if.timeout_timer_en     = 1'b1;
        rxdeskew_if.analog_settle_timer_en = 1'b0;

        d2c_if.rx_pt_en = 1'b0;
        d2c_if.tx_pt_en = 1'b0;
        d2c_if.d2c_clk_sampling    = 2'b00;
        d2c_if.d2c_lfsr_en         = 1'b1 ;
        d2c_if.d2c_pattern_setup   = 3'b001;
        d2c_if.d2c_data_pattern_sel = 2'b00; // LFSR
        d2c_if.d2c_val_pattern_sel  = 1'b0 ;
        d2c_if.d2c_pattern_mode    = 1'b0  ;
        d2c_if.d2c_burst_count     = 16'd4096;
        d2c_if.d2c_idle_count      = 16'd0;
        d2c_if.d2c_iter_count      = 16'd1;
        d2c_if.d2c_compare_setup   = 2'd0; // Per-Lane

        rxdeskew_if.mb_tx_clk_lane_sel  = 2'b01;
        rxdeskew_if.mb_tx_data_lane_sel = 2'b00; // Low (spec S1: force track/data/val low)
        rxdeskew_if.mb_tx_val_lane_sel  = 2'b00; // Low
        rxdeskew_if.mb_tx_trk_lane_sel  = 2'b00; // Low
        rxdeskew_if.mb_rx_clk_lane_sel  = 2'b01 ;
        rxdeskew_if.mb_rx_data_lane_sel  = 2'b01 ;
        rxdeskew_if.mb_rx_val_lane_sel  = 2'b00 ;
        rxdeskew_if.mb_rx_trk_lane_sel  = 2'b00 ;

        rxdeskew_if.phy_rx_deskew_ctrl[0]  = deskew_applied_r;
        rxdeskew_if.phy_tx_eq_preset_ctrl   = current_eq_preset;

        rxdeskew_if.tx_sb_msg_valid = 1'b0;
        rxdeskew_if.tx_sb_msg       = NOTHING;
        rxdeskew_if.tx_msginfo      = 16'h0;
        rxdeskew_if.tx_data_field   = 64'h0;

        case (current_state)
            RXDESKEW_IDLE, RXDESKEW_IDLE2: begin
                rxdeskew_if.timeout_timer_en = 1'b0;
            end

            RXDESKEW_START_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence             ;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_start_req    ;
                rxdeskew_if.tx_msginfo      = 16'h0                          ;
            end

            RXDESKEW_START_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence              ;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_start_resp    ;
                rxdeskew_if.tx_msginfo      = 16'h0                           ;
            end

            RXDESKEW_SET_DESKEW_CODE: begin
                rxdeskew_if.phy_rx_deskew_ctrl[0] = deskew_code; // Drive sweep code
                rxdeskew_if.analog_settle_timer_en = 1'b1;
            end

            RXDESKEW_RX_D2C_PT: begin
                rxdeskew_if.phy_rx_deskew_ctrl[0] = deskew_code; // Hold sweep code
                d2c_if.rx_pt_en               = 1'b1;
                rxdeskew_if.mb_tx_data_lane_sel = 2'b01; // Active during test
                rxdeskew_if.mb_tx_val_lane_sel  = 2'b01; // Operational Valid
            end

            RXDESKEW_LOG_RESULT: begin
                /* sequential processing */
            end

            RXDESKEW_CALC_APPLY: begin
                /* sequential apply */
            end

            RXDESKEW_END_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence          ;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_end_req   ;
                rxdeskew_if.tx_msginfo      = 16'h0                       ;
            end

            RXDESKEW_END_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence           ;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_end_resp   ;
                rxdeskew_if.tx_msginfo      = 16'h0                        ;
            end

            TO_DTC2: begin
                rxdeskew_if.rxdeskew_done    = 1'b1;
                rxdeskew_if.timeout_timer_en = 1'b0;
            end

            RXDESKEW_CHOOSE_PRESET: begin
                rxdeskew_if.analog_settle_timer_en = accumulative_error;
            end

            RXDESKEW_PRESET_REQ, RXDESKEW_EXIT_DTC1_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence                               ;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req   ;
                // MsgInfo: bit0=is_my_preset_new, bit1=accumulative_error, bits[5:2]=preset
                rxdeskew_if.tx_msginfo      = {10'h0, current_eq_preset,
                                               accumulative_error, is_my_preset_new};
            end

            RXDESKEW_PRESET_RESP, RXDESKEW_EXIT_DTC1_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence                                ;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp   ;
                rxdeskew_if.tx_msginfo      = {10'h0, current_eq_preset,
                                               accumulative_error, is_my_preset_new};
            end

            TO_DTC1: begin
                // Assert req to controller: "run DTC1 then come back via IDLE2".
                rxdeskew_if.datatraincenter1_req = 1'b1;
                rxdeskew_if.timeout_timer_en     = 1'b0;
            end

            TO_TRAINERROR: begin
                rxdeskew_if.rxdeskew_done    = 1'b1;
                rxdeskew_if.trainerror_req   = 1'b1;
                rxdeskew_if.timeout_timer_en = 1'b0;
            end

            default: begin end
        endcase
    end

    // =====================================================================
    // Sequential: deskew code counter + best-center calc
    // =====================================================================
    reg [6:0]  min_deskew, max_deskew, temp_min_deskew;
    reg        deskew_filled, is_in_pass_zone;

    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : RXDESKEW_PROC
        if (!rxdeskew_if.rst_n) begin
            deskew_code           <= MIN_DESKEW_CODE;
            rxdeskew_fail_flag_r  <= 1'b0;
            min_deskew            <= '0;
            max_deskew            <= '0;
            temp_min_deskew       <= '0;
            deskew_applied_r      <= '0;
            deskew_filled         <= 1'b0;
            is_in_pass_zone       <= 1'b0;
            current_eq_preset     <= '0;
            dtc1_loop_cnt         <= '0;
            in_dtc1_loop_r        <= 1'b0;
            is_my_preset_new      <= 1'b0;
            preset_error_flag     <= 1'b0;
            preset_fail_flag1     <= 1'b0;
            preset_fail_flag2     <= 1'b0;
            r_first_entry_rxdeskew<= 1'b1;
        end

        // ── Clear on IDLE (first entry only, not on IDLE2 re-entry) ───────
        else if (current_state == RXDESKEW_IDLE) begin
            deskew_code       <= MIN_DESKEW_CODE;
            deskew_filled     <= 1'b0;
            is_in_pass_zone   <= 1'b0;
            min_deskew        <= '0;
            max_deskew        <= '0;
            temp_min_deskew   <= '0;
            rxdeskew_fail_flag_r <= 1'b0;
            if (r_first_entry_rxdeskew) begin
                dtc1_loop_cnt         <= '0;
                current_eq_preset     <= '0;
                is_my_preset_new      <= 1'b0;
                preset_error_flag     <= 1'b0;
                preset_fail_flag1     <= 1'b0;
                preset_fail_flag2     <= 1'b0;
                r_first_entry_rxdeskew<= 1'b0;
            end
        end

        // ── Increment deskew code ─────────────────────────────────────────
        else if (current_state == RXDESKEW_LOG_RESULT) begin
            // Pass/fail per-lane (use aggregate: all-fail = d2c_aggr_err != 0)
            if (d2c_if.d2c_aggr_err == '0) begin
                // Pass
                if (!is_in_pass_zone) begin
                    is_in_pass_zone <= 1'b1;
                    temp_min_deskew <= deskew_code;
                    if (!deskew_filled) begin
                        deskew_filled <= 1'b1;
                        min_deskew    <= deskew_code;
                        max_deskew    <= deskew_code;
                    end
                end else begin
                    // Update max boundary
                    max_deskew <= deskew_code;
                end
            end else begin
                is_in_pass_zone <= 1'b0;
            end
            // Increment
            if (deskew_code != MAX_DESKEW_CODE)
                deskew_code <= deskew_code + 1;
        end

        // ── Apply best deskew center ──────────────────────────────────────
        else if (current_state == RXDESKEW_CALC_APPLY) begin
            if (deskew_filled) begin
                deskew_applied_r <=
                    ({1'b0, min_deskew} + {1'b0, max_deskew}) >> 1;
                rxdeskew_fail_flag_r  <= 1'b0;
            end else begin
                deskew_applied_r      <= '0;
                rxdeskew_fail_flag_r  <= 1'b1;
            end
        end

        // ── EQ Preset logic (runs only on FIRST cycle in CHOOSE_PRESET) ───────
        //    data_incoherence=1 when current_state just changed, so the
        //    increment fires only once even when settle keeps us here 10 cycles.
        else if (current_state == RXDESKEW_CHOOSE_PRESET && data_incoherence) begin
            if (accumulative_error) begin
                if (current_eq_preset < MAX_EQ_PRESET) begin
                    current_eq_preset    <= current_eq_preset + 1;
                    is_my_preset_new     <= 1'b1;
                    preset_fail_flag1    <= 1'b0;
                    preset_fail_flag2    <= 1'b0;
                end else begin
                    // All presets exhausted
                    is_my_preset_new  <= 1'b0;
                    preset_error_flag <= 1'b1;
                    preset_fail_flag2 <= 1'b1;
                end
            end else begin
                is_my_preset_new <= 1'b0;
            end
        end

        // ── PRESET_CHECK: decode partner response ─────────────────────────
        else if (current_state == RXDESKEW_PRESET_CHECK) begin
            // preset_fail_flag1: is the current preset encoding valid?
            preset_fail_flag1 <= (current_eq_preset > MAX_EQ_PRESET);
            // Reset DTC1 loop counter on new preset
            if (is_my_preset_new || partner_has_new_preset)
                dtc1_loop_cnt <= '0;
        end

        // ── LOOP_CHECK: increment loop counter ───────────────────────────
        else if (current_state == RXDESKEW_LOOP_CHECK) begin
            if (dtc1_loop_cnt < 4)
                dtc1_loop_cnt <= dtc1_loop_cnt + 1;
        end

        // ── Set / clear in_dtc1_loop_r ────────────────────────────────────
        if (current_state == TO_DTC1 && data_incoherence)
            in_dtc1_loop_r <= 1'b1;
        else if (current_state == RXDESKEW_IDLE)
            in_dtc1_loop_r <= 1'b0;
        // (stays 1 through IDLE2 → repeated re-entries)

    end

endmodule
