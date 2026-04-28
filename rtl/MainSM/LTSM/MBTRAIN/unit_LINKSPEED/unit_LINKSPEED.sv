// =============================================================================
// Module  : unit_LINKSPEED
// Purpose : MBTRAIN.LINKSPEED sub-state FSM.
//           Coordinates the transition to the negotiated link speed by:
//             1. Performing a SB start handshake with the partner.
//             2. Checking all previous training fail-flags:
//                  - If any data/valid lane training step failed   → ERROR path → exit to REPAIR.
//                  - If speed > 32 GT/s and EQ preset not yet done → EQ path  → exit back to RXDESKEW.
//                  - Otherwise                                      → SUCCESS  → send done_req/resp → signal done.
//             3. Driving `phy_negotiated_speed` once the handshake succeeds.
//             4. Handling 8ms timeout and partner TRAINERROR as fatal events.
//
// UCIe 3.0 Spec Reference: Section 4.5.3.4.12 – MBTRAIN.LINKSPEED
//
// FSM States:
//   LS_IDLE            (S0)  Wait for linkspeed_en assertion.
//   LS_START_REQ       (S1)  Send & receive: MBTRAIN_LINKSPEED_start_req.
//   LS_START_RESP      (S2)  Send & receive: MBTRAIN_LINKSPEED_start_resp.
//   LS_EVAL            (S3)  Evaluate fail flags and decide exit path (1 lclk).
//   LS_ERROR_REQ       (S4)  Training errors detected: send error_req / receive error_req.
//   LS_ERROR_RESP      (S5)  Send & receive: error_resp  → exit to REPAIR.
//   LS_EQ_REQ          (S6)  EQ iteration needed (speed > 32 GT/s): send EQ preset req.
//   LS_EQ_RESP         (S7)  Send & receive: EQ resp      → exit back to RXDESKEW.
//   LS_SPEED_DEGRADE_REQ  (S8)  Speed cannot be reached: send speed-degrade req.
//   LS_SPEED_DEGRADE_RESP (S9)  Send & receive: speed-degrade resp → exit to REPAIR.
//   LS_DONE_REQ        (S10) Send & receive: MBTRAIN_LINKSPEED_done_req.
//   LS_DONE_RESP       (S11) Send & receive: MBTRAIN_LINKSPEED_done_resp.
//   TO_DONE            (S12) Assert linkspeed_done for 1 lclk; wait for en de-assert.
//   TO_REPAIR          (S13) Assert linkspeed_done + linkspeed_fail_flag; wait for en de-assert.
//   TO_RXDESKEW        (S14) Assert linkspeed_done for EQ loop; wait for en de-assert.
//   TO_TRAINERROR      (S15) Fatal: 8ms timeout or partner TRAINERROR.
// =============================================================================

module unit_LINKSPEED #(
        // Speed threshold above which EQ preset iteration is required (spec: > 32 GT/s = code 5).
        // phy_negotiated_speed encoding: 0h=4GT/s 1h=8GT/s 2h=12GT/s 3h=16GT/s 4h=32GT/s 5h=64GT/s …
        parameter HIGH_SPEED_THRESHOLD = 3'd4  // codes > 4 require EQ loop (i.e., 64GT/s and above)
    ) (
        internal_ltsm_if.linkspeed_mp ls_if
    );

    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_LINKSPEED_start_req                                      ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_start_resp                                     ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_error_req                                      ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_error_resp                                     ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_repair_req                             ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_repair_resp                            ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_speed_degrade_req                      ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp                     ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
    import UCIe_pkg::MBTRAIN_LINKSPEED_done_req                                       ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_done_resp                                      ;
    import UCIe_pkg::TRAINERROR_Entry_req;
    import UCIe_pkg::NOTHING;

    // =====================================================================
    // State encoding
    // =====================================================================
    localparam LS_IDLE               = 4'h0, // (S0)
               LS_START_REQ          = 4'h1, // (S1)
               LS_START_RESP         = 4'h2, // (S2)
               LS_EVAL               = 4'h3, // (S3)  Decide exit path
               LS_ERROR_REQ          = 4'h4, // (S4)  Training fail → error handshake
               LS_ERROR_RESP         = 4'h5, // (S5)
               LS_EQ_REQ             = 4'h6, // (S6)  EQ preset needed (> 32GT/s)
               LS_EQ_RESP            = 4'h7, // (S7)
               LS_SPEED_DEGRADE_REQ  = 4'h8, // (S8)  Speed not achievable
               LS_SPEED_DEGRADE_RESP = 4'h9, // (S9)
               LS_DONE_REQ           = 4'hA, // (S10)
               LS_DONE_RESP          = 4'hB, // (S11)
               TO_DONE               = 4'hC, // (S12) → linkspeed_done
               TO_REPAIR             = 4'hD, // (S13) → linkspeed_done + fail_flag
               TO_RXDESKEW           = 4'hE, // (S14) → linkspeed_done (EQ loop)
               TO_TRAINERROR         = 4'hF; // (S15) → TRAINERROR

    reg [3:0] current_state, next_state, previous_state;

    // Glitch-guard: suppress tx_sb_msg_valid on the cycle of a state transition.
    wire data_incoherence = (current_state != previous_state);

    // =====================================================================
    // Data-path registers
    // =====================================================================
    // latched negotiated speed (sampled from param_negotiated_max_speed at LS_START_REQ)
    reg [2:0] speed_r;

    // Purely combinational evaluation signals — sampled directly from the interface
    // so that LS_EVAL next-state sees them IMMEDIATELY on the same cycle.
    wire any_train_fail_w = ls_if.datatraincenter2_fail_flag |
                            ls_if.datatrainvref_fail_flag    |
                            ls_if.valtrainvref_fail_flag     |
                            ls_if.valtraincenter_fail_flag   ;
    wire eq_needed_w      = (speed_r > HIGH_SPEED_THRESHOLD);

    // fail flag output register
    reg       fail_flag_r;

    assign ls_if.linkspeed_fail_flag = fail_flag_r;

    // =====================================================================
    // (Block 1) Sequential: current state register
    // =====================================================================
    always @(posedge ls_if.lclk or negedge ls_if.rst_n) begin
        if (!ls_if.rst_n) begin
            current_state  <= LS_IDLE;
            previous_state <= LS_IDLE;
        end else begin
            current_state  <= next_state;
            previous_state <= current_state;
        end
    end

    // =====================================================================
    // (Block 2) Combinational: next-state logic
    // =====================================================================
    always @(*) begin
        // Global overrides: fatal conditions take priority over normal flow.
        if (ls_if.timeout_8ms_occured |
                (ls_if.rx_sb_msg == TRAINERROR_Entry_req && ls_if.rx_sb_msg_valid)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                // (S0) Wait for enable
                LS_IDLE: begin
                    next_state = ls_if.linkspeed_en ? LS_START_REQ : LS_IDLE;
                end

                // (S1) Send & receive: start_req
                LS_START_REQ: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_start_req &&
                                  ls_if.rx_sb_msg_valid) ? LS_START_RESP : LS_START_REQ;
                end

                // (S2) Send & receive: start_resp
                LS_START_RESP: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_start_resp &&
                                  ls_if.rx_sb_msg_valid) ? LS_EVAL : LS_START_RESP;
                end

                // (S3) 1-cycle evaluation: combinational wires decide path immediately
                LS_EVAL: begin
                    if (any_train_fail_w)
                        next_state = LS_ERROR_REQ;       // upstream training failures
                    else if (eq_needed_w)
                        next_state = LS_EQ_REQ;          // EQ preset iteration required
                    else
                        next_state = LS_DONE_REQ;        // clean success
                end

                // (S4) Training error path: send error_req / wait partner error_req
                LS_ERROR_REQ: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_error_req &&
                                  ls_if.rx_sb_msg_valid) ? LS_ERROR_RESP : LS_ERROR_REQ;
                end

                // (S5) Training error path: send error_resp / wait partner error_resp → exit to repair
                LS_ERROR_RESP: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_error_resp &&
                                  ls_if.rx_sb_msg_valid) ? TO_REPAIR : LS_ERROR_RESP;
                end

                // (S6) EQ preset path: send EQ req / wait partner EQ req
                LS_EQ_REQ: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req &&
                                  ls_if.rx_sb_msg_valid) ? LS_EQ_RESP : LS_EQ_REQ;
                end

                // (S7) EQ preset path: send EQ resp / wait partner EQ resp → exit back to RXDESKEW
                LS_EQ_RESP: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp &&
                                  ls_if.rx_sb_msg_valid) ? TO_RXDESKEW : LS_EQ_RESP;
                end

                // (S8) Speed degrade path: send speed_degrade_req / wait partner
                LS_SPEED_DEGRADE_REQ: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_speed_degrade_req &&
                                  ls_if.rx_sb_msg_valid) ? LS_SPEED_DEGRADE_RESP : LS_SPEED_DEGRADE_REQ;
                end

                // (S9) Speed degrade path: send speed_degrade_resp / wait partner → exit to repair
                LS_SPEED_DEGRADE_RESP: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp &&
                                  ls_if.rx_sb_msg_valid) ? TO_REPAIR : LS_SPEED_DEGRADE_RESP;
                end

                // (S10) Success path: send done_req / wait partner done_req
                LS_DONE_REQ: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_done_req &&
                                  ls_if.rx_sb_msg_valid) ? LS_DONE_RESP : LS_DONE_REQ;
                end

                // (S11) Success path: send done_resp / wait partner done_resp
                LS_DONE_RESP: begin
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_done_resp &&
                                  ls_if.rx_sb_msg_valid) ? TO_DONE : LS_DONE_RESP;
                end

                // (S12-S15) Terminal states: hold until enable de-asserted, then back to IDLE.
                TO_DONE, TO_REPAIR, TO_RXDESKEW, TO_TRAINERROR: begin
                    next_state = ls_if.linkspeed_en ? current_state : LS_IDLE;
                end

                default: next_state = ls_if.linkspeed_en ? TO_TRAINERROR : LS_IDLE;
            endcase
        end
    end

    // =====================================================================
    // (Block 3) Combinational: output logic
    // =====================================================================
    always @(*) begin
        // ── Safe defaults (prevent latches) ──────────────────────────────
        ls_if.linkspeed_done     = 1'b0;
        ls_if.trainerror_req     = 1'b0;
        ls_if.timeout_timer_en   = 1'b1;
        ls_if.analog_settle_timer_en = 1'b0;

        // MB lane defaults
        ls_if.mb_tx_clk_lane_sel  = 2'b01; // Clock lane active
        ls_if.mb_tx_data_lane_sel = 2'b01; // Data lanes active
        ls_if.mb_tx_val_lane_sel  = 2'b01; // Valid lane active
        ls_if.mb_tx_trk_lane_sel  = 2'b00; // Track lane low
        ls_if.mb_rx_clk_lane_sel  = 1'b1 ; // Rx clock lane enabled
        ls_if.mb_rx_data_lane_sel = 1'b1 ; // Rx data lanes enabled
        ls_if.mb_rx_val_lane_sel  = 1'b1 ; // Rx valid lane enabled
        ls_if.mb_rx_trk_lane_sel  = 1'b0 ; // Rx track lane disabled

        // PHY speed: keep driving the latched speed
        ls_if.phy_negotiated_speed = speed_r;

        // SB defaults
        ls_if.tx_sb_msg_valid = 1'b0;
        ls_if.tx_sb_msg       = NOTHING;
        ls_if.tx_msginfo      = 16'h0;
        ls_if.tx_data_field   = 64'h0;

        case (current_state)
            LS_IDLE: begin
                ls_if.timeout_timer_en = 1'b0; // No timeout while idle
            end

            LS_START_REQ: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_start_req;
                // MsgInfo[2:0] = negotiated speed code (Table 7-x in UCIe spec)
                ls_if.tx_msginfo      = {13'b0, speed_r};
                ls_if.tx_data_field   = 64'h0;
            end

            LS_START_RESP: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_start_resp;
                ls_if.tx_msginfo      = {13'b0, speed_r};
                ls_if.tx_data_field   = 64'h0;
            end

            LS_EVAL: begin
                // Purely combinational evaluation state (outputs remain at defaults).
                // Data-path sequential block latches any_train_fail_r / eq_needed_r this same cycle.
            end

            LS_ERROR_REQ: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_error_req;
                ls_if.tx_msginfo      = 16'h0;
                ls_if.tx_data_field   = 64'h0;
            end

            LS_ERROR_RESP: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_error_resp;
                ls_if.tx_msginfo      = 16'h0;
                ls_if.tx_data_field   = 64'h0;
            end

            LS_EQ_REQ: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req;
                ls_if.tx_msginfo      = {13'b0, speed_r}; // speed code in msginfo
                ls_if.tx_data_field   = 64'h0;
            end

            LS_EQ_RESP: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
                ls_if.tx_msginfo      = {13'b0, speed_r};
                ls_if.tx_data_field   = 64'h0;
            end

            LS_SPEED_DEGRADE_REQ: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_speed_degrade_req;
                ls_if.tx_msginfo      = 16'h0;
                ls_if.tx_data_field   = 64'h0;
            end

            LS_SPEED_DEGRADE_RESP: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp;
                ls_if.tx_msginfo      = 16'h0;
                ls_if.tx_data_field   = 64'h0;
            end

            LS_DONE_REQ: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_done_req;
                ls_if.tx_msginfo      = {13'b0, speed_r};
                ls_if.tx_data_field   = 64'h0;
            end

            LS_DONE_RESP: begin
                ls_if.tx_sb_msg_valid = !data_incoherence;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_done_resp;
                ls_if.tx_msginfo      = {13'b0, speed_r};
                ls_if.tx_data_field   = 64'h0;
            end

            TO_DONE: begin
                ls_if.linkspeed_done   = 1'b1;
                ls_if.timeout_timer_en = 1'b0;
            end

            TO_REPAIR: begin
                // fail_flag_r is already set by data-path block; drive done so MBTRAIN ctrl proceeds.
                ls_if.linkspeed_done   = 1'b1;
                ls_if.timeout_timer_en = 1'b0;
            end

            TO_RXDESKEW: begin
                // Signal done so MBTRAIN ctrl transitions back to RXDESKEW for EQ preset loop.
                ls_if.linkspeed_done   = 1'b1;
                ls_if.timeout_timer_en = 1'b0;
            end

            TO_TRAINERROR: begin
                ls_if.trainerror_req   = 1'b1;
                ls_if.linkspeed_done   = 1'b1;
                ls_if.timeout_timer_en = 1'b0;
            end

            default: begin end
        endcase
    end

    // =====================================================================
    // (Block 4) Sequential: data-path — latch speed code and fail flag
    //
    //  speed_r    — captured from param_negotiated_max_speed in LS_START_REQ.
    //  fail_flag_r — set in TO_REPAIR; cleared at reset and at LS_START_REQ.
    //
    // Note: any_train_fail_w and eq_needed_w are COMBINATIONAL wires above
    //       (driven directly from interface inputs), so no sequential latching needed.
    // =====================================================================
    always @(posedge ls_if.lclk or negedge ls_if.rst_n) begin
        if (!ls_if.rst_n) begin
            speed_r     <= 3'b0;
            fail_flag_r <= 1'b0;
        end else begin
            case (current_state)
                // Latch the negotiated speed at the start of a new run.
                LS_START_REQ: begin
                    speed_r     <= ls_if.param_negotiated_max_speed;
                    fail_flag_r <= 1'b0; // clear from any previous run
                end

                // Mark fail when exiting to REPAIR.
                TO_REPAIR: begin
                    fail_flag_r <= 1'b1;
                end

                default: begin end // other states: retain values
            endcase
        end
    end

endmodule
