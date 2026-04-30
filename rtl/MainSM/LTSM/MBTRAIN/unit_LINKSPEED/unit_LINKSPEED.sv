// =============================================================================
// Module  : unit_LINKSPEED
// Purpose : MBTRAIN.LINKSPEED sub-state FSM (UCIe 3.0 Spec 4.5.3.4.12).
//           Steps:
//             1. SB Start handshake with partner.
//             2. Run Tx Init D2C Point Test (via substate2d2c_mp interface).
//             3. Evaluate result:
//                  - No errors -> Done handshake -> TO_LINKINIT
//                  - Errors, speed > 0 -> Error handshake -> Speed Degrade -> TO_SPEEDIDLE
//                  - Errors, speed == 0 -> Error handshake -> Repair -> TO_REPAIR
//                  - Timeout / partner TRAINERROR -> TO_TRAINERROR
//
// Interface naming follows project convention:
//   ls_if  : linkspeed_mp   (LTSM control: en/done, timers, SB, lane selects)
//   d2c_if : substate2d2c_mp (D2C PT control: enable, results, config)
//
// Note: both ls_if and d2c_if are the same physical internal_ltsm_if;
//       the testbench (following DATATRAINVREF pattern) connects both to intf.
// =============================================================================
module unit_LINKSPEED (
        internal_ltsm_if.linkspeed_mp    ls_if,
        internal_ltsm_if.substate2d2c_mp d2c_if
    );

    import UCIe_pkg::msg_no_e;
    import UCIe_pkg::MBTRAIN_LINKSPEED_start_req                                             ; // {MBTRAIN.LINKSPEED start req}
    import UCIe_pkg::MBTRAIN_LINKSPEED_start_resp                                            ; // {MBTRAIN.LINKSPEED start resp}
    import UCIe_pkg::MBTRAIN_LINKSPEED_error_req                                             ; // {MBTRAIN.LINKSPEED error req}
    import UCIe_pkg::MBTRAIN_LINKSPEED_error_resp                                            ; // {MBTRAIN.LINKSPEED error resp}
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_repair_req                                    ; // {MBTRAIN.LINKSPEED exit to repair req}
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_repair_resp                                   ; // {MBTRAIN.LINKSPEED exit to repair resp}
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_speed_degrade_req                             ; // {MBTRAIN.LINKSPEED exit to speed degrade req}
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp                            ; // {MBTRAIN.LINKSPEED exit to speed degrade resp}
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req ; // {MBTRAIN.LINKSPEED exit to phy retrain req}
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp; // {MBTRAIN.LINKSPEED exit to phy retrain resp}
    import UCIe_pkg::MBTRAIN_LINKSPEED_done_req                                              ; // {MBTRAIN.LINKSPEED done req}
    import UCIe_pkg::MBTRAIN_LINKSPEED_done_resp                                             ; // {MBTRAIN.LINKSPEED done resp}
    import UCIe_pkg::TRAINERROR_Entry_req                                                    ; // {TRAINERROR Entry req}
    import UCIe_pkg::NOTHING                                                                 ; // nothing

    // =========================================================================
    // State Encoding  (S0..S20 per user specification)
    // =========================================================================
    localparam [4:0]
    LINKSPEED_IDLE                       = 5'h00, // S0
    LINKSPEED_START_REQ                  = 5'h01, // S1
    LINKSPEED_START_RESP                 = 5'h02, // S2
    LINKSPEED_TX_D2C_PT                  = 5'h03, // S3
    LINKSPEED_EVAL_RESULT                = 5'h04, // S4
    LINKSPEED_DONE_REQ                   = 5'h05, // S5
    LINKSPEED_DONE_RESP                  = 5'h06, // S6
    TO_LINKINIT                          = 5'h07, // S7
    LINKSPEED_ERROR_REQ                  = 5'h08, // S8
    LINKSPEED_ERROR_RESP                 = 5'h09, // S9
    LINKSPEED_RECOVERY_DECISION          = 5'h0A, // S10
    LINKSPEED_EXIT_TO_REPAIR_REQ         = 5'h0B, // S11
    LINKSPEED_EXIT_TO_REPAIR_RESP        = 5'h0C, // S12
    TO_REPAIR                            = 5'h0D, // S13
    LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ  = 5'h0E, // S14
    LINKSPEED_EXIT_TO_SPEED_DEGRADE_RESP = 5'h0F, // S15
    TO_SPEEDIDLE                         = 5'h10, // S16
    LINKSPEED_EXIT_RETRAIN_REQ           = 5'h11, // S17  (PHY retrain path) {MBTRAIN.LINKSPEED exit to phy retrain req}
    LINKSPEED_EXIT_RETRAIN_RESP          = 5'h12, // S18  {MBTRAIN.LINKSPEED exit to phy retrain resp}
    TO_PHYRETRAIN                        = 5'h13, // S19
    TO_TRAINERROR                        = 5'h14; // S20

    reg [4:0] current_state, next_state;

    // Glitch-guard: hold tx_sb_msg_valid LOW on the cycle the state changes so
    // that the SB message is already stable when the pulse fires.
    wire is_sb_data_valid = (current_state == next_state);

    // This signals is asserted if we don't receive a sync msg from the partner.
    // Each time we send a req msg, we wait for the same req msg from the partner.
    // If we didn't receive the same req msg and received other req msg then we assert this signal.
    reg dont_wait_req; // Just send req msg only. Don't wait for the same req msg from the partner.

    // ========================================================================
    // The receved SB messages after the minimum seperation time has passed.
    // ========================================================================
    logic              is_sb_msg_valid_rcvd;
    UCIe_pkg::msg_no_e rx_sb_msg_rcvd      ;


    // =========================================================================
    // SB separation timer constants (computed from module parameters)
    // TIMER_MAX_VALUE = number of lclk cycles that represent a seperation time between
    // 2 msgs sent — this is the required minimum gap between consecutive SB sends.
    // =========================================================================
    localparam integer TIMER_MAX_VALUE = 3;
    localparam integer TIMER_SIZE      = $clog2(TIMER_MAX_VALUE + 1);

    // To count the minimum seperation time between each 2 consecutive SB messages we send.
    logic [TIMER_SIZE-1:0] send_timer; // It counts from 31 down to 0 (satisified period).


    // =========================================================================
    // Data-path registers
    // =========================================================================
    reg d2c_fail_r         ; // Latched when TX D2C test reports any error
    reg req_speed_degrade_r; // 1 = degrade speed, 0 = repair

    // =========================================================================
    // (Block 1) Sequential: state register
    // =========================================================================
    always @(posedge ls_if.lclk or negedge ls_if.rst_n) begin
        if (!ls_if.rst_n)
            current_state <= LINKSPEED_IDLE;
        else
            current_state <= next_state;
    end

    // =========================================================================
    // (Block 2) Combinational: next-state logic
    // =========================================================================
    always @(*) begin
        // ── Global overrides (fatal conditions) ─────────────────────────────
        if ( ls_if.timeout_8ms_occured || (ls_if.rx_sb_msg == TRAINERROR_Entry_req && ls_if.rx_sb_msg_valid) ) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                // (S0) Wait for enable
                LINKSPEED_IDLE:
                    next_state = ls_if.linkspeed_en ? LINKSPEED_START_REQ : LINKSPEED_IDLE;

                // (S1) Send start req; wait for partner echo
                LINKSPEED_START_REQ:
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_start_req && ls_if.rx_sb_msg_valid)? LINKSPEED_START_RESP : LINKSPEED_START_REQ;

                // (S2) Send start resp; wait for partner echo
                LINKSPEED_START_RESP:
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_start_resp && ls_if.rx_sb_msg_valid)? LINKSPEED_TX_D2C_PT : LINKSPEED_START_RESP;

                // (S3) Tx D2C point test running; wait for completion
                LINKSPEED_TX_D2C_PT:
                    next_state = d2c_if.test_d2c_done ? LINKSPEED_EVAL_RESULT : LINKSPEED_TX_D2C_PT;

                // (S4) One-cycle evaluation (data-path latched in Block 4)
                LINKSPEED_EVAL_RESULT:
                    next_state = (d2c_fail_r) ? LINKSPEED_ERROR_REQ :
                        (ls_if.linkspeed_PHY_IN_RETRAIN && ls_if.params_changed)? LINKSPEED_EXIT_RETRAIN_REQ :
                        LINKSPEED_DONE_REQ;

                // ── Success path ──────────────────────────────────────────
                // (S5) Send done req; wait for partner echo
                LINKSPEED_DONE_REQ:
                    next_state =
                        (rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req && is_sb_msg_valid_rcvd) ? LINKSPEED_EXIT_RETRAIN_REQ :
                        (rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_error_req && is_sb_msg_valid_rcvd) ? LINKSPEED_ERROR_REQ :
                        (rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_done_req  && is_sb_msg_valid_rcvd) ? LINKSPEED_DONE_RESP :
                        LINKSPEED_DONE_REQ;

                // (S6) Send done resp; wait for partner echo
                LINKSPEED_DONE_RESP:
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_done_resp && ls_if.rx_sb_msg_valid) ? TO_LINKINIT : LINKSPEED_DONE_RESP;

                // ── Error path ────────────────────────────────────────────
                // (S8) Send error req; wait for partner echo
                LINKSPEED_ERROR_REQ:
                    if(rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req && is_sb_msg_valid_rcvd)
                        next_state = LINKSPEED_EXIT_RETRAIN_REQ;
                    else if((rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_error_req && is_sb_msg_valid_rcvd) ||
                            (dont_wait_req && send_timer == '0))
                        next_state = LINKSPEED_ERROR_RESP;
                    else
                        next_state = LINKSPEED_ERROR_REQ;


                // (S9) Send error resp; wait for partner echo
                LINKSPEED_ERROR_RESP:
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_error_resp && ls_if.rx_sb_msg_valid)? LINKSPEED_RECOVERY_DECISION : LINKSPEED_ERROR_RESP;

                // (S10) Branch: repair or speed-degrade?
                LINKSPEED_RECOVERY_DECISION:
                    next_state = req_speed_degrade_r? LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ : LINKSPEED_EXIT_TO_REPAIR_REQ;

                // ── Repair path ───────────────────────────────────────────
                // (S11)
                LINKSPEED_EXIT_TO_REPAIR_REQ:
                    if (rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_exit_to_speed_degrade_req && is_sb_msg_valid_rcvd)
                        next_state = LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ;
                    else if (rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_exit_to_repair_req && is_sb_msg_valid_rcvd)
                        next_state = LINKSPEED_EXIT_TO_REPAIR_RESP;
                    else
                        next_state = LINKSPEED_EXIT_TO_REPAIR_REQ;

                // (S12)
                LINKSPEED_EXIT_TO_REPAIR_RESP:
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_repair_resp && ls_if.rx_sb_msg_valid) ? TO_REPAIR : LINKSPEED_EXIT_TO_REPAIR_RESP;

                // ── Speed-degrade path ────────────────────────────────────
                // (S14)
                LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ:
                    if ((ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_speed_degrade_req && ls_if.rx_sb_msg_valid) ||
                            (dont_wait_req && send_timer == '0))
                        next_state = LINKSPEED_EXIT_TO_SPEED_DEGRADE_RESP;
                    else
                        next_state = LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ;

                // (S15)
                LINKSPEED_EXIT_TO_SPEED_DEGRADE_RESP:
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp && ls_if.rx_sb_msg_valid) ?
                        TO_SPEEDIDLE : LINKSPEED_EXIT_TO_SPEED_DEGRADE_RESP;

                // ── PHY-retrain path (provided for spec completeness) ─────
                // (S17)
                LINKSPEED_EXIT_RETRAIN_REQ:
                    next_state = ((ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req && ls_if.rx_sb_msg_valid) ||
                        (dont_wait_req && send_timer == '0)) ?
                        LINKSPEED_EXIT_RETRAIN_RESP : LINKSPEED_EXIT_RETRAIN_REQ;

                // (S18)
                LINKSPEED_EXIT_RETRAIN_RESP:
                    next_state = (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp && ls_if.rx_sb_msg_valid) ?
                        TO_PHYRETRAIN : LINKSPEED_EXIT_RETRAIN_RESP;

                // ── Terminal states: hold until en de-asserts ─────────────
                TO_LINKINIT, TO_REPAIR, TO_SPEEDIDLE, TO_PHYRETRAIN, TO_TRAINERROR:
                    next_state = ls_if.linkspeed_en ? current_state : LINKSPEED_IDLE;

                default:
                    next_state = ls_if.linkspeed_en ? TO_TRAINERROR : LINKSPEED_IDLE;
            endcase
        end
    end

    // =========================================================================
    // (Block 3) Combinational: output logic
    // =========================================================================
    always @(*) begin
        // ── LTSM handshake defaults ──────────────────────────────────────────
        ls_if.linkspeed_done     = 1'b0;
        ls_if.trainerror_req     = 1'b0;
        ls_if.speedidle_req      = 1'b0;
        ls_if.repair_req         = 1'b0;
        ls_if.linkinit_req       = 1'b0;
        ls_if.phyretrain_req     = 1'b0;
        ls_if.timeout_timer_en   = 1'b1; // Run 8ms timer in all active states
        ls_if.analog_settle_timer_en = 1'b0;

        // ── MB lane configuration defaults ───────────────────────────────────
        ls_if.mb_tx_clk_lane_sel  = 2'b01; // Active
        ls_if.mb_tx_data_lane_sel = 2'b00; // Low
        ls_if.mb_tx_val_lane_sel  = 2'b00; // Low
        ls_if.mb_tx_trk_lane_sel  = 2'b00; // Low (track not used in LINKSPEED)
        ls_if.mb_rx_clk_lane_sel  = 1'b1 ;
        ls_if.mb_rx_data_lane_sel = 1'b1 ;
        ls_if.mb_rx_val_lane_sel  = 1'b1 ;
        ls_if.mb_rx_trk_lane_sel  = 1'b0 ;

        // ── SB TX defaults ───────────────────────────────────────────────────
        ls_if.tx_sb_msg_valid = 1'b0;
        ls_if.tx_sb_msg       = NOTHING;
        ls_if.tx_msginfo      = 16'h0;
        ls_if.tx_data_field   = 64'h0;

        // ── D2C PT interface defaults ─────────────────────────────────────────
        // tx_pt_en=0, rx_pt_en=0 -> ltsm_tb_attachments uses the RXDESKEW FSM path
        d2c_if.rx_pt_en             = 1'b0    ;
        d2c_if.tx_pt_en             = 1'b0    ;
        d2c_if.d2c_clk_sampling     = 2'b00   ; // Eye Center
        d2c_if.d2c_lfsr_en          = 1'b1    ; // Enable LFSR
        d2c_if.d2c_pattern_setup    = 3'b001  ; // Data pattern
        d2c_if.d2c_data_pattern_sel = 2'b00   ; // LFSR
        d2c_if.d2c_val_pattern_sel  = 1'b0    ;
        d2c_if.d2c_pattern_mode     = 1'b0    ; // Continuous
        d2c_if.d2c_burst_count      = 16'd4096;
        d2c_if.d2c_idle_count       = 16'd0   ;
        d2c_if.d2c_iter_count       = 16'd1   ;
        d2c_if.d2c_compare_setup    = 2'd1    ; // Per-Lane comparison

        case (current_state)
            LINKSPEED_IDLE: begin
                ls_if.timeout_timer_en = 1'b0;
            end

            LINKSPEED_START_REQ: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_start_req;
            end

            LINKSPEED_START_RESP: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_start_resp;
            end

            LINKSPEED_TX_D2C_PT: begin
                // Launch Tx-initiated D2C point test
                d2c_if.tx_pt_en = 1'b1;
                ls_if.mb_tx_clk_lane_sel  = 2'b01; // Active
                ls_if.mb_tx_data_lane_sel = 2'b01; // Active
                ls_if.mb_tx_val_lane_sel  = 2'b01; // Active
            end

            LINKSPEED_EVAL_RESULT: begin
                // Keep tx_pt_en=1 so the d2c_if routing through ltsm_tb_attachments
                // stays on the TX_D2C_PT path while d2c_fail_r is evaluated.
                d2c_if.tx_pt_en = 1'b1;
            end

            LINKSPEED_DONE_REQ: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_done_req;
            end

            LINKSPEED_DONE_RESP: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_done_resp;
            end

            // {MBTRAIN.LINKSPEED error req}. here we set the transmitters in Electrical-Idle state. (Low)
            LINKSPEED_ERROR_REQ: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_error_req;
                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            LINKSPEED_ERROR_RESP: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_error_resp;
                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            LINKSPEED_RECOVERY_DECISION: begin
                // Pure decision: no SB message
                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            LINKSPEED_EXIT_TO_REPAIR_REQ: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_repair_req;
                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            LINKSPEED_EXIT_TO_REPAIR_RESP: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_repair_resp;
                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_speed_degrade_req;
                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            LINKSPEED_EXIT_TO_SPEED_DEGRADE_RESP: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp;
                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            LINKSPEED_EXIT_RETRAIN_REQ: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req;
            end

            LINKSPEED_EXIT_RETRAIN_RESP: begin
                ls_if.tx_sb_msg_valid = is_sb_data_valid;
                ls_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
            end

            TO_LINKINIT: begin
                ls_if.linkspeed_done   = 1'b1;
                ls_if.linkinit_req     = 1'b1;
                ls_if.timeout_timer_en = 1'b0;
            end

            TO_REPAIR: begin
                ls_if.linkspeed_done   = 1'b1;
                ls_if.repair_req       = 1'b1;
                ls_if.timeout_timer_en = 1'b0;

                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            TO_SPEEDIDLE: begin
                ls_if.linkspeed_done   = 1'b1;
                ls_if.speedidle_req    = 1'b1;
                ls_if.timeout_timer_en = 1'b0;

                ls_if.mb_tx_clk_lane_sel  = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_data_lane_sel = 2'b00; // Low (Electrical-Idle)
                ls_if.mb_tx_val_lane_sel  = 2'b00; // Low (Electrical-Idle)
            end

            TO_PHYRETRAIN: begin
                ls_if.linkspeed_done   = 1'b1;
                ls_if.phyretrain_req   = 1'b1;
                ls_if.timeout_timer_en = 1'b0;
            end

            TO_TRAINERROR: begin
                ls_if.linkspeed_done   = 1'b1;
                ls_if.trainerror_req   = 1'b1;
                ls_if.timeout_timer_en = 1'b0;
            end

            default: begin end
        endcase
    end
    // ==================================================
    // MB Lane Control
    // To convert the "mb_rx_data_lane_mask" from 3 bits to 16 bits, we use "negotiated_data_lanes".
    // 000b:  None (Degrade not possible)
    // 001b: Logical Lanes 0 to 7
    // 010b: Logical Lanes 8 to 15
    // 011b: Logical Lanes 0 to 15
    // 100b: Logical Lanes 0 to 3
    // 101b: Logical Lanes 4 to 7
    logic [15:0] negotiated_data_lanes;
    logic [15:0] active_lanes;
    assign active_lanes = negotiated_data_lanes & (~d2c_if.d2c_perlane_err); // All the lanes that passed the D2C test.
    assign ls_if.linkspeed_success_lanes = active_lanes;
    always @(*) begin
        case(ls_if.mb_rx_data_lane_mask)
            3'b000:  negotiated_data_lanes = 16'h0000;
            3'b001:  negotiated_data_lanes = 16'h00FF;
            3'b010:  negotiated_data_lanes = 16'hFF00;
            3'b011:  negotiated_data_lanes = 16'hFFFF;
            3'b100:  negotiated_data_lanes = 16'h000F;
            3'b101:  negotiated_data_lanes = 16'h00F0;
            default: negotiated_data_lanes = 16'h0000;
        endcase
    end

    // =========================================================================
    // (Block 4) Sequential: data-path — D2C result evaluation
    // =========================================================================
    always @(posedge ls_if.lclk or negedge ls_if.rst_n) begin
        if (!ls_if.rst_n) begin
            d2c_fail_r          <= 1'b0;
            req_speed_degrade_r <= 1'b0;
        end else begin
            case (current_state)
                // Clear decision registers at the beginning of each run
                LINKSPEED_START_REQ: begin
                    d2c_fail_r          <= 1'b0;
                    req_speed_degrade_r <= 1'b0;
                end

                // Latch D2C result the cycle test_d2c_done is asserted
                LINKSPEED_TX_D2C_PT: begin
                    if (d2c_if.test_d2c_done) begin
                        if (d2c_if.d2c_perlane_err != 0) begin
                            d2c_fail_r          <= 1'b1;

                            // ─────────────────────────────────────────────────────────────────────
                            // Width-Degrade Feasibility Check  (spec 4.5.3.4.12, Step 3)
                            // ─────────────────────────────────────────────────────────────────────
                            // Context
                            // ───────
                            // After the Tx D2C PT, some data lanes may have failed (d2c_perlane_err
                            // bit = 1).  Before escalating to Speed Degrade, we must first check
                            // whether the SURVIVING lanes are enough to form a valid degraded-width
                            // link.  Width Degrade is always preferred over Speed Degrade because it
                            // keeps the highest possible data rate.
                            //
                            // Inputs consumed
                            // ───────────────
                            //  active_lanes       [15:0] : bit-mask of lanes that PASSED D2C.
                            //                              = negotiated_data_lanes & ~d2c_perlane_err
                            //                              Each bit maps to one Logical Data Lane
                            //                              per Table 4-9 (Standard Package Logical
                            //                              Lane Map).
                            //
                            //  rf_ctrl_target_link_width  : Target Link Width field from the Link
                            //                              Control register (Table 9-9, bits [5:2]).
                            //                              2 = x16,  1 = x8.
                            //
                            //  rf_cap_SPMW               : Standard Package Module Width bit from
                            //                              the Link Capability register (Table 9-8,
                            //                              bit [22]).
                            //                              0 = x16 module,  1 = x8 module.
                            //
                            // Lane Group Map (Table 4-9)
                            // ──────────────────────────
                            //  active_lanes[7:0]  → Logical Lanes 0-7   (lower half of x16 link)
                            //  active_lanes[15:8] → Logical Lanes 8-15  (upper half of x16 link)
                            //  active_lanes[3:0]  → Logical Lanes 0-3   (lower half of x8 link)
                            //  active_lanes[7:4]  → Logical Lanes 4-7   (upper half of x8 link)
                            //
                            // Decision Logic (spec 4.3.7 – Width Degrade in Standard Package)
                            // ──────────────────────────────────────────────────────────────────
                            //  Case A — x16 Standard Package (rf_cap_SPMW=0, rf_ctrl=x16):
                            //    The link is currently running at x16. A Width Degrade to x8
                            //    is possible ONLY IF at least one contiguous group of 8 lanes
                            //    is completely error-free:
                            //      • active_lanes[7:0]  == 8'hFF  → lanes 0-7  all passed  → degrade to lower  x8 group, OR
                            //      • active_lanes[15:8] == 8'hFF  → lanes 8-15 all passed  → degrade to upper x8 group.
                            //
                            //  Case B — x8 mode (rf_ctrl=x8, regardless of rf_cap_SPMW):
                            //    The link is running (or forced) at x8.  A Width Degrade to x4
                            //    is possible ONLY IF at least one contiguous group of 4 lanes
                            //    is completely error-free:
                            //      • active_lanes[3:0] == 4'hF  → lanes 0-3 all passed → degrade to lower x4 group, OR
                            //      • active_lanes[7:4] == 4'hF  → lanes 4-7 all passed → degrade to upper x4 group.
                            //
                            //  Outcome
                            //  ───────
                            //   Width Degrade feasible  →  req_speed_degrade_r = 0
                            //                              FSM will route to LINKSPEED_EXIT_TO_REPAIR_REQ
                            //                              (a Repair sub-state handles the lane remapping).
                            //
                            //   Width Degrade NOT feasible → req_speed_degrade_r = 1
                            //                              FSM will route to LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ
                            //                              (Speed Degrade is the last resort).
                            // ─────────────────────────────────────────────────────────────────────
                            if (((active_lanes[7:0] == 8'hFF || active_lanes[15:8] == 8'hFF) && ls_if.rf_ctrl_target_link_width == 4'h2 && ls_if.rf_cap_SPMW == 1'b0) || // If we work on x16 Standerd Package. (We need to read the "Link Capability" register (rf_cap_SPMW != x8) & the "Link Control" register (rf_ctrl_target_link_width = x16)).
                                    ((active_lanes[3:0] == 4'hF || active_lanes[7:4] == 4'hF) && ls_if.rf_ctrl_target_link_width == 4'h1 ) // If we work on x8 Standerd Package (rf_cap_SPMW = x8) OR want to work on x8 Mode (while our package is x16 Standerd Package (rf_cap_SPMW != x8)) (when rf_ctrl_target_link_width == x8).
                                ) begin
                                req_speed_degrade_r <= 1'b0; // We can apply width degrade (via repair path).
                            end
                            else begin
                                req_speed_degrade_r <= 1'b1; // We have to apply speed degrade.
                            end

                        end else begin
                            d2c_fail_r          <= 1'b0;
                            req_speed_degrade_r <= 1'b0;
                        end
                    end
                end

                default: begin end
            endcase
        end
    end


    // =========================================================================
    // (Block 5) Sequential: Is the partner's msg synchronized with our msg?
    //
    // Background — UCIe 4.5.3.4.12 priority ordering (highest → lowest):
    //   TRAINERROR > PHY-retrain > Error > Done
    //
    // Both sides send their state-driven message simultaneously.
    // If the partner's received message has HIGHER priority than ours, we do
    // NOT need to wait for an echo of our own lower-priority req — instead we
    // pivot immediately to the partner's higher-priority path.
    // 'dont_wait_req' is set to signal that skip so the next-state logic can
    // advance as soon as the send_timer has expired (SB separation respected).
    //
    // Conditions per state:
    //
    //  LINKSPEED_DONE_REQ  (we send: done_req – lowest priority)
    //    → Partner may have sent: error_req (higher) or phy_retrain_req (highest).
    //    → Assert dont_wait_req=1 when we observe a HIGHER-priority rx message.
    //      (Next-state logic routes immediately to ERROR_REQ or EXIT_RETRAIN_REQ.
    //       The flag then carries into that next REQ state, where (dont_wait_req & timer==0)
    //       lets us advance to the RESP state without waiting for a redundant echo.)
    //
    //  LINKSPEED_ERROR_REQ  (we send: error_req – mid priority)
    //    → Partner may have sent: phy_retrain_req (higher priority).
    //    → Assert dont_wait_req=1 when we observe phy_retrain_req from partner.
    //      (Next-state logic routes to LINKSPEED_EXIT_RETRAIN_REQ; the flag carries
    //       into that state so (dont_wait_req & timer==0) skips the redundant echo-wait.)
    //    → If partner sent error_req (same priority): both sides are in sync.
    //      The normal echo-wait handles the transition — dont_wait_req is cleared.
    //
    //  LINKSPEED_EXIT_TO_REPAIR_REQ  (we send: exit_to_repair_req)
    //    → Partner may have already decided speed-degrade (higher priority).
    //    → Assert dont_wait_req=1 when we observe exit_to_speed_degrade_req.
    //      (Next-state logic routes to LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ.)
    //
    //  All other REQ states use normal echo-wait (dont_wait_req stays 0).
    // =========================================================================
    always @(posedge ls_if.lclk or negedge ls_if.rst_n) begin
        if (!ls_if.rst_n) begin
            dont_wait_req <= 1'b0;
        end else begin
            // this signal 'dont_wait_req' is asserted under conditions in the states:
            // LINKSPEED_DONE_REQ
            // LINKSPEED_ERROR_REQ
            // LINKSPEED_EXIT_TO_REPAIR_REQ
            // Note: The states that we assert 'dont_wait_req' in, are the states with lower priority than the state we will go to directly.

            case (current_state)
                // Clear in all states except the three REQ states that may detect a priority mismatch
                // (DONE_REQ, ERROR_REQ, EXIT_TO_REPAIR_REQ). Note: this includes non-response states
                // such as IDLE, TX_D2C_PT, EVAL_RESULT and RECOVERY_DECISION.
                LINKSPEED_IDLE                      ,
                LINKSPEED_START_REQ                 ,
                LINKSPEED_START_RESP                ,
                LINKSPEED_TX_D2C_PT                 ,
                LINKSPEED_EVAL_RESULT               ,
                LINKSPEED_DONE_RESP                 ,
                TO_LINKINIT                         ,
                LINKSPEED_ERROR_RESP                ,
                LINKSPEED_RECOVERY_DECISION         ,
                LINKSPEED_EXIT_TO_REPAIR_RESP       ,
                TO_REPAIR                           ,
                LINKSPEED_EXIT_TO_SPEED_DEGRADE_RESP,
                TO_SPEEDIDLE                        ,
                LINKSPEED_EXIT_RETRAIN_RESP         ,
                TO_PHYRETRAIN                       ,
                TO_TRAINERROR
                : begin
                    dont_wait_req <= 1'b0;
                end
                // ── LINKSPEED_DONE_REQ (S5) ──────────────────────────────────
                // We send:  done_req  (lowest-priority outgoing message).
                // Partner may have already decided to exit to phy-retrain (highest)
                // or to the error path (higher).
                // → Assert dont_wait_req if partner sent a HIGHER-priority msg:
                //     • phy_retrain_req  (highest — pivot to retrain path)
                //     • error_req        (higher  — pivot to error path)
                // When asserted, next-state logic routes immediately to that higher-priority
                // REQ state; the flag then carries there so (dont_wait_req & timer==0)
                // advances to RESP without waiting for a redundant echo.
                LINKSPEED_DONE_REQ: begin
                    if (ls_if.rx_sb_msg_valid &&
                            (ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req ||
                                ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_error_req))
                        dont_wait_req <= 1'b1;
                    // If partner echoed done_req (same priority), clear flag — normal flow.
                    else if (ls_if.rx_sb_msg_valid && ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_done_req)
                        dont_wait_req <= 1'b0;
                end

                // ── LINKSPEED_ERROR_REQ (S8) ─────────────────────────────────
                // We send:  error_req.
                // Partner may have already decided to exit to phy-retrain (highest).
                // → Assert dont_wait_req=1 ONLY if partner sent phy_retrain_req (higher priority).
                //   The flag carries into EXIT_RETRAIN_REQ where (dont_wait_req & timer==0)
                //   skips waiting for the redundant echo.
                // → If partner sent error_req (same priority): both sides synchronized.
                //   The rx_sb_msg_rcvd == error_req condition in next-state handles the
                //   transition normally — dont_wait_req is cleared (not needed).
                LINKSPEED_ERROR_REQ: begin
                    if (ls_if.rx_sb_msg_valid &&
                            ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req)
                        dont_wait_req <= 1'b1;
                    // Same-priority (error_req): use it to advance normally.
                    else if (ls_if.rx_sb_msg_valid && ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_error_req)
                        dont_wait_req <= 1'b0; // same-priority: both sides synchronized — normal echo-wait handles transition, no flag needed.
                    else if (ls_if.rx_sb_msg_valid)
                        dont_wait_req <= 1'b0;
                end

                // ── LINKSPEED_EXIT_TO_REPAIR_REQ (S11) ───────────────────────────
                // We send:  exit_to_repair_req.
                // Partner may have already decided speed-degrade (higher priority in
                // the exit negotiation: degrade > repair per spec priority table).
                // → Assert dont_wait_req if partner sent exit_to_speed_degrade_req.
                // Next-state logic then routes to LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ.
                LINKSPEED_EXIT_TO_REPAIR_REQ: begin
                    if (ls_if.rx_sb_msg_valid &&
                            ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_speed_degrade_req)
                        dont_wait_req <= 1'b1;
                    // Partner echoed exit_to_repair_req (same): normal flow, no flag needed.
                    else if (ls_if.rx_sb_msg_valid && ls_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_repair_req)
                        dont_wait_req <= 1'b0;
                end

                // All other states: keep current value (flag is only cleared in the states
                // listed in the first case branch and when same-priority echo is received above).
                default: begin end
            endcase
        end
    end

    // =========================================================================
    // (Block 6) Sequential: SB separation timer + rx-message buffer
    //
    // Problem: when the FSM pivots to a higher-priority exit state (e.g. from
    // ERROR_REQ to EXIT_RETRAIN_REQ), it must send a NEW SB message immediately.
    //
    // Solution: when tx_sb_msg_valid pulses (= we just sent a new message),
    // LOAD the timer with TIMER_MAX_VALUE (= 2 SB periods in lclk units) and
    // count it down.  While the timer is non-zero:
    //   • is_sb_msg_valid_rcvd is held 0  → next-state logic cannot advance.
    //   • any rx_sb_msg that arrives is captured in rx_sb_msg_r so it is not
    //     lost once the timer expires.
    // =========================================================================
    reg                tx_sb_msg_valid_r; // used to convert the signal on 'tx_sb_msg_valid' into a pulse.
    logic              rx_sb_msg_valid_r;
    UCIe_pkg::msg_no_e rx_sb_msg_r      ;

    always @(posedge ls_if.lclk or negedge ls_if.rst_n) begin
        if (!ls_if.rst_n) begin
            tx_sb_msg_valid_r <= 1'b0;
            send_timer        <= '0  ;
            rx_sb_msg_valid_r <= 1'b0;
            rx_sb_msg_r       <= NOTHING;
            // rx_msginfo_r      <= '0;

        end
        else if (current_state == LINKSPEED_IDLE) begin
            // Reset buffer and timer between LINKSPEED invocations.
            tx_sb_msg_valid_r <= 1'b0;
            send_timer        <= '0  ;
            rx_sb_msg_valid_r <= 1'b0;
            rx_sb_msg_r       <= NOTHING;
            // rx_msginfo_r   <= '0;
        end
        else begin
            tx_sb_msg_valid_r <= ls_if.tx_sb_msg_valid;

            // ================== *************  Send Timer  ************* ================== //
            // On every rising edge where we assert tx_sb_msg_valid, LOAD the
            // timer.  If the timer is already running (non-zero) and no new
            // send, decrement it.  When it reaches 0 the gap is satisfied.
            if ((ls_if.tx_sb_msg_valid == 1'b1) && (tx_sb_msg_valid_r == 1'b0))
                send_timer <= TIMER_MAX_VALUE[TIMER_SIZE-1:0];
            else if (send_timer != 5'd0)
                send_timer <= send_timer - 1'b1;

            // ================== *************  Receive Buffer  ************* ================== //
            // Buffer any rx message that arrives DURING the separation window
            // (while send_timer > 0) so it is not lost.
            if (send_timer != 5'd0) begin
                if (ls_if.rx_sb_msg_valid) begin
                    rx_sb_msg_valid_r <= 1'b1;
                    rx_sb_msg_r       <= ls_if.rx_sb_msg;
                    // rx_msginfo_r      <= ls_if.rx_msginfo;
                end
            end
            else begin // timer == 0: window expired, clear buffer
                rx_sb_msg_valid_r <= 1'b0;
            end
        end
    end

    // Expose the buffered-or-live rx message to the next-state logic.
    // During the separation window: suppress valid to stall the FSM.
    // After the window: prefer the buffered message (captured during window)
    // over the live bus to avoid a one-cycle gap.
    assign is_sb_msg_valid_rcvd = (send_timer != 5'b0) ? 1'b0 : (rx_sb_msg_valid_r | ls_if.rx_sb_msg_valid);
    assign rx_sb_msg_rcvd       = (send_timer == 5'b0 && rx_sb_msg_valid_r) ? rx_sb_msg_r : ls_if.rx_sb_msg;


    // =========================================================================
    // (Block 7) Sequential: latch linkspeed_PHY_IN_RETRAIN
    //
    // Spec 4.5.3.4.12: if PHY_IN_RETRAIN was asserted by the PHYRETRAIN state
    // (phyretrain_PHY_IN_RETRAIN=1) when we enter LINKSPEED, AND the link
    // parameters changed (params_changed=1), we must exit directly to
    // LINKSPEED_EXIT_RETRAIN_REQ instead of the normal DONE path.
    //
    // The value is sampled once at LINKSPEED_START_REQ (beginning of the sub-
    // state) and held stable throughout.  It is cleared when the error/recovery
    // decision is reached so it does not bleed into the next invocation.
    // =========================================================================
    always_ff @(posedge ls_if.lclk or negedge ls_if.rst_n) begin
        if (!ls_if.rst_n) begin
            ls_if.linkspeed_PHY_IN_RETRAIN <= '0;
        end
        else if (current_state == LINKSPEED_START_REQ) begin
            // Sample phyretrain_PHY_IN_RETRAIN once at the start of this sub-state.
            ls_if.linkspeed_PHY_IN_RETRAIN <= ls_if.phyretrain_PHY_IN_RETRAIN;
        end
        else if (current_state == LINKSPEED_RECOVERY_DECISION) begin
            // Clear once we have already branched into the error-recovery path;
            // PHY_IN_RETRAIN is only relevant for the clean (no-error) exit.
            ls_if.linkspeed_PHY_IN_RETRAIN <= '0;
        end
    end
endmodule
