// =============================================================================
// Module  : unit_RXDESKEW
// Purpose : MBTRAIN.RXDESKEW sub-state FSM.
// References:
//   - UCIe-3.0 specification §4.5.3.4.10 MBTRAIN.RXDESKEW.
//   - These part is Implemention spesific so, the next TODOs don't have high periority right now...
// TODO: don't forget to do the next TODO tasks descussed below:
//       1. what is the next_state when we are receiving RX_D2C_PT messages
//          (or receiving {MBTRAIN.RXDESKEW EQ Preset req}  (MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req)
//          when the current_state = RXDESKEW_EXIT_TO_DTC1_REQ_RESP)
//       2. The logic that tells unit_RX_D2C_PT: "you are enabled to responce on the received msg".
// =============================================================================
module unit_RXDESKEW #(
        parameter MAX_DESKEW_CODE         = 7'd127,
        parameter MIN_DESKEW_CODE         = 7'd0  ,
        parameter MAX_ARC_LIMIT           = 3'd4  ,
        parameter MIN_DESIRED_SWEEP_RANGE = (MAX_DESKEW_CODE - MIN_DESKEW_CODE) * 0.50
    ) (
        internal_ltsm_if.rxdeskew_mp     rxdeskew_if,
        internal_ltsm_if.substate2d2c_mp d2c_if
    );

    localparam SPEED_32G = 3'b101;

    import LTSM_state_pkg::RESET;
    import UCIe_pkg::msg_no_e   ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_start_req                                              ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_start_resp                                             ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_end_req                                                ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_end_resp                                               ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req                           ;
    import UCIe_pkg::MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp                          ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req ;
    import UCIe_pkg::MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
    import UCIe_pkg::TRAINERROR_Entry_req                                                    ;
    import UCIe_pkg::NOTHING                                                                 ;

    localparam [3:0]
    RXDESKEW_IDLE                  = 4'd0 , // S0:  Wait for rxdeskew_en.
    RXDESKEW_START_REQ_RESP        = 4'd1 , // S1:  MBTRAIN.RXDESKEW start req/resp.
    RXDESKEW_CHOOSE_PRESET         = 4'd2 , // S2:  (HS) Select next Tx EQ preset.
    RXDESKEW_PRESET_REQ_RESP       = 4'd3 , // S3:  (HS) Preset req/resp handshake.
    RXDESKEW_APPLY_SKEW_SWEEP      = 4'd4 , // S4:  Delegate full PI sweep to unit_phase_interpolator.
    RXDESKEW_EXIT_TO_DTC1_REQ_RESP = 4'd9 , // S9:  Exit-to-DTC1 req/resp.
    RXDESKEW_ARC_COUNT             = 4'd10, // S10: Count fine-tuning arc.
    TO_DTC1                        = 4'd11, // S11: Terminal — return to DataTrainCenter1.
    RXDESKEW_END_REQ_RESP          = 4'd12, // S12: MBTRAIN.RXDESKEW end req/resp.
    TO_DTC2                        = 4'd13, // S13: Terminal — proceed to DataTrainCenter2.
    TO_TRAINERROR                  = 4'd14; // S14: Terminal — TRAINERROR.

    reg [4:0] current_state, next_state;
    wire      is_high_speed;
    assign is_high_speed      = (rxdeskew_if.phy_negotiated_speed > SPEED_32G);

    reg       start_handshake_done;
    reg       partner_preset_fail_status_comb;
    reg       preset_handshake_done;
    reg       exit_to_dtc1_handshake_done;
    reg       end_handshake_done;

    // =========================================================================
    // Deskew code bit-width
    // =========================================================================
    localparam DW = $clog2(MAX_DESKEW_CODE + 1);

    // =========================================================================
    // unit_phase_interpolator (PI) handshake signals
    // =========================================================================
    logic        pi_en;            // Enable: asserted during RXDESKEW_APPLY_SKEW_SWEEP.
    logic        pi_session_start; // Pulse: new session start (IDLE → START_REQ_RESP).
    logic        pi_done;          // PI sweep complete (CALC_APPLY finished).
    logic        pi_abort;         // PI aborted (val-train fail detected).
    logic        pi_in_sweep;      // 1 while PI is in SET_CODE/RX_D2C_PT/LOG_RESULT.
    logic        pi_analog_settle_timer_en; // From PI → rxdeskew_if.
    logic        pi_rx_pt_en;              // From PI → d2c_if.
    logic [DW-1:0] swept_code_r_out;       // Current sweep code from PI.

    // =========================================================================
    // Outputs from unit_phase_interpolator (PI) sub-module
    // =========================================================================
    logic [DW-1:0] best_deskew_code       [15:0];
    logic          pi_fail_flag_r;
    logic [2:0]    best_preset_saved;
    logic [DW-1:0] overall_best_min_range;

    logic [DW-1:0] min_sweep_range;
    assign min_sweep_range                = overall_best_min_range;
    assign rxdeskew_if.rxdeskew_fail_flag = pi_fail_flag_r;

    // pi_en: held high for the duration of RXDESKEW_APPLY_SKEW_SWEEP.
    assign pi_en           = (current_state == RXDESKEW_APPLY_SKEW_SWEEP);
    // pi_session_start: one-cycle pulse on first entry from IDLE.
    assign pi_session_start = (current_state == RXDESKEW_IDLE && rxdeskew_if.rxdeskew_en);

    // =========================================================================
    // PHY deskew control drive:
    //   While PI is sweeping  → broadcast current swept code from PI.
    //   After PI CALC_APPLY   → drive per-lane optimal midpoint from PI.
    // =========================================================================
    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : DESKEW_CTRL_GEN
            assign rxdeskew_if.phy_rx_deskew_ctrl[lane] =
                pi_in_sweep ? swept_code_r_out : best_deskew_code[lane];
        end
    endgenerate

    // =========================================================================
    // FSM / Preset / Arc tracking registers
    // =========================================================================
    reg [2:0] preset_search_cnt;      // Number of Tx EQ presets swept so far (0-5).
    reg [2:0] dtc1_arc_cnt;           // Number of fine-tuning arcs back to DTC1 (spec limit = 4).
    reg [2:0] old_preset_saved;       // Preset applied at the last TO_DTC1 exit; 0 after TO_DTC2.
    reg [2:0] my_preset;              // Our local Tx EQ preset (set by partner's req msginfo).
    reg [2:0] partner_preset;         // Tx EQ preset we are asking the partner to apply.
    reg       my_preset_fail_status;  // 1 = we could not support the requested preset.
    reg       partner_preset_fail_status; // 1 = partner signalled fail on our preset request.

    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin
        if(~rxdeskew_if.rst_n) begin
            current_state  <= RXDESKEW_IDLE;
        end
        else begin
            current_state  <= next_state   ;
        end
    end

    always @(*) begin
        if (rxdeskew_if.timeout_8ms_occured | (rxdeskew_if.rx_sb_msg == TRAINERROR_Entry_req && rxdeskew_if.rx_sb_msg_valid == 1'b1)) begin
            next_state = TO_TRAINERROR;
        end
        else begin
            case(current_state)
                // -------------------------------------------------------------
                // (S0) IDLE: Wait for rxdeskew_en
                // -------------------------------------------------------------
                RXDESKEW_IDLE: begin
                    next_state = (rxdeskew_if.rxdeskew_en)? RXDESKEW_START_REQ_RESP : RXDESKEW_IDLE;
                end
                // -------------------------------------------------------------
                // (S1) RXDESKEW_START_REQ_RESP: send req & receive resp : {MBTRAIN.RXDESKEW start req/resp}.
                // -------------------------------------------------------------
                RXDESKEW_START_REQ_RESP: begin
                    if (start_handshake_done) begin
                        if (is_high_speed)
                            next_state = RXDESKEW_CHOOSE_PRESET;
                        else
                            next_state = RXDESKEW_APPLY_SKEW_SWEEP; // delegate to PI
                    end else begin
                        next_state = RXDESKEW_START_REQ_RESP;
                    end
                end
                // -------------------------------------------------------------
                // (S4) RXDESKEW_APPLY_SKEW_SWEEP: PI sub-module runs the full
                //   5-step sweep (SET_CODE → RX_D2C_PT → LOG_RESULT →
                //   [LOG_PRESET_RESULT] → CALC_APPLY) internally.
                //   This state holds until pi_done or pi_abort is asserted.
                // -------------------------------------------------------------
                RXDESKEW_APPLY_SKEW_SWEEP: begin
                    if (pi_abort) begin
                        // Val-train fail detected inside PI — skip to end.
                        next_state = RXDESKEW_END_REQ_RESP;
                    end else if (pi_done) begin
                        // PI finished CALC_APPLY. Apply same routing as old CALC_APPLY state.
                        if (is_high_speed) begin
                            if (min_sweep_range > (MIN_DESIRED_SWEEP_RANGE - 1'b1)) begin
                                next_state = RXDESKEW_END_REQ_RESP;
                            end else if ((preset_search_cnt != 3'd6 && preset_search_cnt != 3'd5) ||
                                    (preset_search_cnt == 3'd5 && best_preset_saved != partner_preset)) begin
                                next_state = RXDESKEW_CHOOSE_PRESET;
                            end else if (dtc1_arc_cnt != MAX_ARC_LIMIT) begin
                                next_state = (best_preset_saved == old_preset_saved) ?
                                    RXDESKEW_END_REQ_RESP : RXDESKEW_EXIT_TO_DTC1_REQ_RESP;
                            end else begin
                                next_state = RXDESKEW_END_REQ_RESP;
                            end
                        end else begin
                            next_state = RXDESKEW_END_REQ_RESP;
                        end
                    end else begin
                        next_state = RXDESKEW_APPLY_SKEW_SWEEP; // wait for PI
                    end
                end
                // -------------------------------------------------------------
                // (S7) RXDESKEW_END_REQ_RESP: Send req and receive resp {MBTRAIN.RXDESKEW end req/resp}.
                // -------------------------------------------------------------
                RXDESKEW_END_REQ_RESP: begin
                    if (end_handshake_done) begin
                        next_state = TO_DTC2;
                    end
                    // if the {MBTRAIN.RXDESKEW EQ Preset req} msg rcvd:
                    else if (is_high_speed && rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req) begin
                        next_state = RXDESKEW_CHOOSE_PRESET; // We assume that this FSM state choose the best preset to apply even if it was the already applied preset.
                    end
                    // if the {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req} msg rcvd:
                    else if (is_high_speed && rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req) begin
                        next_state = (dtc1_arc_cnt == 3'd4)? TO_TRAINERROR : RXDESKEW_EXIT_TO_DTC1_REQ_RESP;
                    end
                    else begin
                        next_state = RXDESKEW_END_REQ_RESP;
                    end
                end
                // -------------------------------------------------------------
                // (S9) TO_DTC2: Terminal State
                // -------------------------------------------------------------
                TO_DTC2: begin
                    next_state = (rxdeskew_if.rxdeskew_en) ? TO_DTC2 : RXDESKEW_IDLE;
                end
                //  _________________________________________________________________
                // ================================================================+'|
                // High-Speed Tx EQ Preset Loop States                             | |
                // ================================================================+'
                // -------------------------------------------------------------
                // (S10) RXDESKEW_CHOOSE_PRESET: Change the Tx EQ Preset that we ask
                //                               The partner to operate on.
                // -------------------------------------------------------------
                RXDESKEW_CHOOSE_PRESET: begin
                    next_state = RXDESKEW_PRESET_REQ_RESP;
                end
                // -------------------------------------------------------------
                // (S11) RXDESKEW_PRESET_REQ_RESP: Here we wait for the hand check of
                //          {MBTRAIN.RXDESKEW EQ Preset req} &
                //          {MBTRAIN.RXDESKEW EQ Preset resp} to be done completely.
                // -------------------------------------------------------------
                RXDESKEW_PRESET_REQ_RESP  : begin
                    if (preset_handshake_done) begin
                        next_state = RXDESKEW_APPLY_SKEW_SWEEP; // delegate to PI
                    end else begin
                        next_state = RXDESKEW_PRESET_REQ_RESP;
                    end
                end
                // -------------------------------------------------------------
                // (S13) RXDESKEW_EXIT_TO_DTC1_REQ_RESP:
                // -------------------------------------------------------------
                RXDESKEW_EXIT_TO_DTC1_REQ_RESP : begin
                    if(exit_to_dtc1_handshake_done) begin
                        next_state = RXDESKEW_ARC_COUNT;
                    end

                    // TODO: before integeration level: make sure to remove the following condition & prevent transition to the state RXDESKEW_CHOOSE_PRESET:
                    //       For now we leave it because if we remove it the and received this msg (in the condition here) the RTL logic here (of RXDESKEW)
                    //       will handle and responce with this msg but after that the the next handshake will not happen (of RX_D2C_PT)
                    //       because this unit_RX_D2C_PT FSM is not designed with ability to response on the received msg only.
                    //       It's now designed to send req and wait to receive req (which is not happening here because we don't want to send any req here (in current FSM (unit_RXDESKEW))).
                    // TODO: In case we will edit the D2C Test module, we will have to edit the code below to memorize that (the partner may send EXIT_DTC1_REQ but we have transited to RXDESKEW_CHOOSE_PRESET. we have to remember the EXIT_DTC1_REQ message has been rcvd and determine the next state and the next message we have to send according to that):
                    else if (rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req) begin
                        next_state = RXDESKEW_CHOOSE_PRESET;
                    end
                    else begin
                        next_state = RXDESKEW_EXIT_TO_DTC1_REQ_RESP;
                    end
                end
                // -------------------------------------------------------------
                // (S14) RXDESKEW_ARC_COUNT
                // -------------------------------------------------------------
                RXDESKEW_ARC_COUNT        : begin
                    next_state = TO_DTC1; // Here we count an arc counter to know how many times we loop for fine-tuning.
                end
                // -------------------------------------------------------------
                // (S16) TO_DTC1: Terminal State
                // -------------------------------------------------------------
                TO_DTC1: begin
                    next_state = (rxdeskew_if.rxdeskew_en) ? TO_DTC1 : RXDESKEW_IDLE;
                end
                // -------------------------------------------------------------
                // (S18) TO_TRAINERROR: Terminal State
                // -------------------------------------------------------------
                TO_TRAINERROR: begin
                    next_state = (rxdeskew_if.rxdeskew_en) ? TO_TRAINERROR : RXDESKEW_IDLE;
                end
                default: begin
                    next_state = RXDESKEW_IDLE;
                end
            endcase
        end
    end


    // =========================================================================
    // OLD_PRESET_SAVED tracking (TO_DTC1 / TO_DTC2)
    // Stays in this module because it is a pure FSM side-effect.
    // =========================================================================
    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : OLD_PRESET_PROC
        if (!rxdeskew_if.rst_n) begin
            old_preset_saved <= 3'd0;
        end else begin
            if (current_state == TO_DTC2) old_preset_saved <= 3'd0;           // Reset on DTC2 exit.
            if (current_state == TO_DTC1) old_preset_saved <= best_preset_saved; // Capture on DTC1 exit.
        end
    end

    // =========================================================================
    // unit_phase_interpolator_for_deskew instantiation
    // Handles: per-lane deskew eye-tracking, preset evaluation, CALC_APPLY midpoint.
    // =========================================================================
    unit_phase_interpolator_for_deskew #(
        .MAX_DESKEW_CODE (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE (MIN_DESKEW_CODE),
        .DW              (DW)
    ) u_phase_interpolator_for_deskew (
        .lclk                          (rxdeskew_if.lclk),
        .rst_n                         (rxdeskew_if.rst_n),
        // Handshake
        .pi_en                         (pi_en),
        .pi_session_start              (pi_session_start),
        // Abort triggers
        .valtraincenter_fail_flag      (rxdeskew_if.valtraincenter_fail_flag),
        .partner_valtraincenter_fail_flag (rxdeskew_if.partner_valtraincenter_fail_flag),
        // D2C PT interface
        .test_d2c_done                 (d2c_if.test_d2c_done),
        .d2c_perlane_err               (d2c_if.d2c_perlane_err),
        // Lane config
        .mb_rx_data_lane_mask          (rxdeskew_if.mb_rx_data_lane_mask),
        .is_high_speed                 (is_high_speed),
        // Preset eval inputs
        .partner_preset                (partner_preset),
        .partner_preset_fail_status    (partner_preset_fail_status),
        // Handshake outputs
        .pi_done                       (pi_done),
        .pi_abort                      (pi_abort),
        .pi_in_sweep                   (pi_in_sweep),
        // Control outputs
        .pi_analog_settle_timer_en     (pi_analog_settle_timer_en),
        .pi_rx_pt_en                   (pi_rx_pt_en),
        .swept_code_r_out              (swept_code_r_out),
        // Computation outputs
        .best_deskew_code              (best_deskew_code),
        .fail_flag_r                   (pi_fail_flag_r),
        // .current_preset_min_range_out  (), // Unused at this level
        .best_preset_saved             (best_preset_saved),
        .overall_best_min_range        (overall_best_min_range)
        // .overall_best_lo               (), // Unused at this level
        // .overall_best_hi               (), // Unused at this level
        // .overall_found_pass            ()  // Unused at this level
    );

    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : COUNTERS_PROC
        if (!rxdeskew_if.rst_n) begin
            preset_search_cnt <= 3'd0;
            dtc1_arc_cnt      <= 3'd0;
        end else begin
            // Reset the arc counter only when the FSM exits completely.
            if (current_state == TO_DTC2 || current_state == TO_TRAINERROR) begin
                dtc1_arc_cnt <= 3'd0;
            end

            // Reset the preset search when starting a new sweep run.
            if (current_state == RXDESKEW_IDLE && rxdeskew_if.rxdeskew_en) begin
                preset_search_cnt <= 3'd0;
                // dtc1_arc_cnt is NOT reset here, so it persists across DTC1 loops!
            end
            // Increment preset_search_cnt when PI sweep completes and RXDESKEW
            // decides to loop back to CHOOSE_PRESET for the next preset.
            else if (current_state == RXDESKEW_APPLY_SKEW_SWEEP && pi_done &&
                    next_state == RXDESKEW_CHOOSE_PRESET) begin
                preset_search_cnt <= preset_search_cnt + 1'b1;
            end

            // Increment fine-tuning arc count when transitioning into ARC_COUNT.
            if (next_state == RXDESKEW_ARC_COUNT) begin
                dtc1_arc_cnt <= dtc1_arc_cnt + 1'b1;
            end
        end
    end

    always @(*) begin
        rxdeskew_if.rxdeskew_done        = 1'b0;
        rxdeskew_if.trainerror_req       = 1'b0;
        rxdeskew_if.datatraincenter1_req = 1'b0;
        rxdeskew_if.timeout_timer_en       = 1'b1;
        rxdeskew_if.analog_settle_timer_en = 1'b0;
        rxdeskew_if.mb_tx_clk_lane_sel  = 2'b01;
        rxdeskew_if.mb_tx_data_lane_sel = 2'b00;
        rxdeskew_if.mb_tx_val_lane_sel  = 2'b00;
        rxdeskew_if.mb_tx_trk_lane_sel  = 2'b00;
        rxdeskew_if.mb_rx_clk_lane_sel  = 1'b1;
        rxdeskew_if.mb_rx_data_lane_sel = 1'b1;
        rxdeskew_if.mb_rx_val_lane_sel  = 1'b1;
        rxdeskew_if.mb_rx_trk_lane_sel  = 1'b0;
        rxdeskew_if.phy_tx_eq_preset_ctrl = my_preset;
        // SB signals are driven in the dedicated HANDSHAKE comb block
        d2c_if.rx_pt_en             = 1'b0;
        d2c_if.tx_pt_en             = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00;
        d2c_if.d2c_lfsr_en          = 1'b1;
        d2c_if.d2c_pattern_setup    = 3'b011;
        d2c_if.d2c_data_pattern_sel = 2'b00;
        d2c_if.d2c_val_pattern_sel  = 1'b0;
        d2c_if.d2c_pattern_mode     = 1'b0;
        d2c_if.d2c_burst_count      = 16'd1;
        d2c_if.d2c_idle_count       = 16'd0;
        d2c_if.d2c_iter_count       = 16'd1;
        d2c_if.d2c_compare_setup    = 2'd0;
        case(current_state)
            RXDESKEW_IDLE: begin
                rxdeskew_if.timeout_timer_en    = 1'b0;
                rxdeskew_if.mb_tx_clk_lane_sel  = 2'b00;
                rxdeskew_if.mb_tx_data_lane_sel = 2'b00;
                rxdeskew_if.mb_tx_val_lane_sel  = 2'b00;
                rxdeskew_if.mb_tx_trk_lane_sel  = 2'b00;
                rxdeskew_if.mb_rx_clk_lane_sel  = 1'b0;
                rxdeskew_if.mb_rx_data_lane_sel = 1'b0;
                rxdeskew_if.mb_rx_val_lane_sel  = 1'b0;
                rxdeskew_if.mb_rx_trk_lane_sel  = 1'b0;
            end
            RXDESKEW_START_REQ_RESP: begin
            end
            // PI internally drives analog_settle_timer_en and rx_pt_en.
            // Forward them to the interface while in the sweep state.
            RXDESKEW_APPLY_SKEW_SWEEP: begin
                rxdeskew_if.analog_settle_timer_en = pi_analog_settle_timer_en;
                d2c_if.rx_pt_en                    = pi_rx_pt_en;
            end
            RXDESKEW_END_REQ_RESP: begin
            end
            TO_DTC2: begin
                rxdeskew_if.rxdeskew_done      = 1'b1;
                rxdeskew_if.timeout_timer_en   = 1'b0;
            end
            RXDESKEW_CHOOSE_PRESET: begin
            end
            RXDESKEW_PRESET_REQ_RESP: begin
            end
            RXDESKEW_EXIT_TO_DTC1_REQ_RESP: begin
            end
            RXDESKEW_ARC_COUNT: begin
            end
            TO_DTC1: begin
                rxdeskew_if.datatraincenter1_req = 1'b1;
                rxdeskew_if.timeout_timer_en     = 1'b0;
            end
            TO_TRAINERROR: begin
                rxdeskew_if.trainerror_req     = 1'b1;
                rxdeskew_if.rxdeskew_done      = 1'b1;
                rxdeskew_if.timeout_timer_en   = 1'b0;
            end
            default: ;
        endcase
    end

    reg  [3:0]         send_sb_msg [1:0] ;
    reg               sb_msg_valid_pulse;

    localparam [3:0]
    NO_MSG         = 4'H0,
    START_REQ      = 4'H1,
    START_RESP     = 4'H2,
    PRESET_REQ     = 4'H3,
    PRESET_RESP    = 4'H4,
    EXIT_DTC1_REQ  = 4'H5,
    EXIT_DTC1_RESP = 4'H6,
    END_REQ        = 4'H7,
    END_RESP       = 4'H8;

    always_comb begin
        start_handshake_done = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_start_resp && rxdeskew_if.rx_sb_msg_valid);
        partner_preset_fail_status_comb = (rxdeskew_if.rx_msginfo[0]) & (rxdeskew_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp) & (rxdeskew_if.rx_sb_msg_valid);
        preset_handshake_done           = (~partner_preset_fail_status_comb & ~my_preset_fail_status);
        exit_to_dtc1_handshake_done = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp && rxdeskew_if.rx_sb_msg_valid);
        end_handshake_done = (rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_end_resp && rxdeskew_if.rx_sb_msg_valid);
    end

    always_comb begin
        if (    current_state == RXDESKEW_START_REQ_RESP        ||
                current_state == RXDESKEW_PRESET_REQ_RESP       ||
                current_state == RXDESKEW_EXIT_TO_DTC1_REQ_RESP ||
                current_state == RXDESKEW_END_REQ_RESP          ) begin
            // lclk >> sclk: a single edge-detect pulse is sufficient;
            // no periodic retransmit timer is needed.
            sb_msg_valid_pulse = (send_sb_msg[1] != send_sb_msg[0]);
        end
        else begin
            sb_msg_valid_pulse = 1'b0;
        end

        case (send_sb_msg[0])
            START_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_start_req;
            end
            START_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_start_resp;
            end
            PRESET_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req;
                rxdeskew_if.tx_msginfo      = {13'b0, partner_preset};
            end
            PRESET_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
                rxdeskew_if.tx_msginfo      = {15'b0, my_preset_fail_status};
            end
            EXIT_DTC1_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req;
            end
            EXIT_DTC1_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp;
            end
            END_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_end_req;
            end
            END_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_end_resp;
            end
            default: begin
                rxdeskew_if.tx_sb_msg_valid = 1'b0;
                rxdeskew_if.tx_sb_msg       = NOTHING;
                rxdeskew_if.tx_msginfo      = 16'h0;
                rxdeskew_if.tx_data_field   = 64'h0;
            end
        endcase
    end

    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : HANDSHAKE_PROC
        if (rxdeskew_if.rst_n == 1'b0) begin
            {send_sb_msg [1], send_sb_msg [0]} <= {NO_MSG, NO_MSG};
            my_preset_fail_status      <= 1'b0;
            partner_preset_fail_status <= 1'b0;
            partner_preset             <= 3'd0;
            my_preset                  <= 3'd0;
        end
        else if( current_state == RXDESKEW_IDLE && rxdeskew_if.rxdeskew_en)begin
            {send_sb_msg [1], send_sb_msg [0]} <= {NO_MSG, START_REQ};
            my_preset_fail_status      <= 1'b0;
            partner_preset_fail_status <= 1'b0;
            partner_preset             <= 3'd0;
            my_preset                  <= 3'd0;
        end
        else begin
            if (    current_state == RXDESKEW_START_REQ_RESP        ||
                    current_state == RXDESKEW_PRESET_REQ_RESP       ||
                    current_state == RXDESKEW_EXIT_TO_DTC1_REQ_RESP ||
                    current_state == RXDESKEW_END_REQ_RESP          ) begin
                send_sb_msg [1] <= send_sb_msg [0];
            end

            if(rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_start_req && rxdeskew_if.rx_sb_msg_valid)begin
                send_sb_msg [0] <= START_RESP;
            end
            else if(rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_start_resp && rxdeskew_if.rx_sb_msg_valid)begin
                send_sb_msg [0] <= (is_high_speed)? PRESET_REQ : NO_MSG;
            end
            else if(rxdeskew_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req && rxdeskew_if.rx_sb_msg_valid)begin
                send_sb_msg [0]       <= PRESET_RESP;
                my_preset             <= (rxdeskew_if.rx_msginfo[3:0] > 5)? my_preset : rxdeskew_if.rx_msginfo[2:0];
                my_preset_fail_status <= (rxdeskew_if.rx_msginfo[3:0] > 5);
            end
            else if(rxdeskew_if.rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp && rxdeskew_if.rx_sb_msg_valid)begin
                partner_preset_fail_status <= rxdeskew_if.rx_msginfo[0];
                if (rxdeskew_if.rx_msginfo[0]) begin
                    send_sb_msg [0] <= PRESET_REQ;
                end
                else if((!my_preset_fail_status) && (!rxdeskew_if.rx_msginfo[0])) begin
                    send_sb_msg [0] <= NO_MSG;
                end
                // else if (my_preset_fail_status && (!rxdeskew_if.rx_msginfo[0])) begin
                //     send_sb_msg [0] <= send_sb_msg [0]; // No change
                // end
            end

            // pi_abort: val-train fail was detected inside the PI sweep.
            else if (current_state == RXDESKEW_APPLY_SKEW_SWEEP && pi_abort) begin
                send_sb_msg [0] <= END_REQ;
            end

            // pi_done: PI sweep completed CALC_APPLY; apply the same routing as old CALC_APPLY.
            else if (current_state == RXDESKEW_APPLY_SKEW_SWEEP && pi_done) begin
                if (is_high_speed) begin
                    if (min_sweep_range > (MIN_DESIRED_SWEEP_RANGE - 1'b1)) begin
                        send_sb_msg[0] <= END_REQ;
                    end
                    else if ((preset_search_cnt != 3'd6 && preset_search_cnt != 3'd5) ||
                            (preset_search_cnt == 3'd5 && best_preset_saved != partner_preset)) begin
                        send_sb_msg[0] <= PRESET_REQ;
                        partner_preset <= (preset_search_cnt == 3'd5) ? best_preset_saved : partner_preset + 1'b1;
                    end
                    else if (dtc1_arc_cnt != MAX_ARC_LIMIT) begin
                        send_sb_msg[0] <= (best_preset_saved == old_preset_saved) ? END_REQ : EXIT_DTC1_REQ;
                    end
                    else begin
                        send_sb_msg[0] <= END_REQ;
                    end
                end
                else begin
                    send_sb_msg[0] <= END_REQ;
                end
            end
            // TODO: In case we will edit the D2C Test module, we will have to edit the code below to memorize that (the partner may send EXIT_DTC1_REQ but we have transited to RXDESKEW_CHOOSE_PRESET. we have to remember the EXIT_DTC1_REQ message has been rcvd and determine the next state and the next message we have to send according to that):
            else if(rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req && rxdeskew_if.rx_sb_msg_valid)begin
                send_sb_msg [0] <= (dtc1_arc_cnt != 4)? EXIT_DTC1_RESP : NO_MSG;
            end
            else if(rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp && rxdeskew_if.rx_sb_msg_valid)begin
                send_sb_msg [0] <= NO_MSG;
            end
            else if(rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_end_req && rxdeskew_if.rx_sb_msg_valid)begin
                send_sb_msg [0] <= (current_state == RXDESKEW_END_REQ_RESP)? END_RESP : send_sb_msg [0];
            end
            else if(rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_end_resp && rxdeskew_if.rx_sb_msg_valid)begin
                send_sb_msg [0] <= NO_MSG;
            end
        end
    end

    // // TODO: before integeration level: make sure to handle this logic below &
    // //       solve to problem above (of what is the next_state when we are receiving RX_D2C_PT messages):
    // always_comb begin
    //     if( rxdeskew_if.rx_sb_msg_valid && (
    //         rxdeskew_if.rx_sb_msg == Start_Rx_Init_D_to_C_point_test_req  ||
    //         rxdeskew_if.rx_sb_msg == Start_Rx_Init_D_to_C_point_test_resp ||
    //         rxdeskew_if.rx_sb_msg == Rx_Init_D_to_C_Tx_Count_Done_req     ||
    //         rxdeskew_if.rx_sb_msg == Rx_Init_D_to_C_Tx_Count_Done_resp    ||
    //         rxdeskew_if.rx_sb_msg == End_Rx_Init_D_to_C_point_test_req    ||
    //         rxdeskew_if.rx_sb_msg == End_Rx_Init_D_to_C_point_test_resp   ))begin
    //         rxdeskew_if.rx_pt_recever_en <= 1'b1;
    //     end
    //     else begin
    //         rxdeskew_if.rx_pt_recever_en <= 1'b0;
    //     end
    // end
endmodule