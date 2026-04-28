// =============================================================================
// Module  : unit_RXDESKEW
// Purpose : MBTRAIN.RXDESKEW sub-state FSM.
// It includes the packages:    .\rtl\MainSM\common\LTSM_state_pkg.sv
//                              .\rtl\MainSM\common\UCIe_pkg.sv


module unit_RXDESKEW #(
        parameter MAX_DESKEW_CODE = 7'd127,
        parameter MIN_DESKEW_CODE = 7'd0,
        parameter MAX_ARC_LIMIT   = 3'd4
    ) (
        internal_ltsm_if.rxdeskew_mp     rxdeskew_if,
        internal_ltsm_if.substate2d2c_mp d2c_if
    );
    localparam SPEED_32G = 3'b101; // To represent the 32 GT/s speed value stored in 'phy_negotiated_speed'.
    // ============================================================================
    // Used SB Messages (explicit imports to document all messages used by this FSM)
    // ============================================================================

    import LTSM_state_pkg::RESET;
    import UCIe_pkg::msg_no_e   ;

    // Imported SB Messages
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


    localparam [4:0]
    RXDESKEW_IDLE              = 5'd00, // S0
    RXDESKEW_START_REQ         = 5'd01, // S1
    RXDESKEW_START_RESP        = 5'd02, // S2
    RXDESKEW_SET_CODE          = 5'd03, // S3
    RXDESKEW_RX_D2C_PT         = 5'd04, // S4
    RXDESKEW_LOG_RESULT        = 5'd05, // S5
    RXDESKEW_CALC_APPLY        = 5'd06, // S6
    RXDESKEW_END_REQ           = 5'd07, // S7
    RXDESKEW_END_RESP          = 5'd08, // S8
    TO_DTC2                    = 5'd09, // S9

    RXDESKEW_CHOOSE_PRESET     = 5'd10, // S10
    RXDESKEW_PRESET_REQ_RESP   = 5'd11, // S11
    RXDESKEW_LOG_PRESET_RESULT = 5'd12, // S12
    RXDESKEW_EXIT_DTC1_REQ     = 5'd13, // S13
    RXDESKEW_ARC_COUNT         = 5'd14, // S14
    RXDESKEW_EXIT_DTC1_RESP    = 5'd15, // S15
    TO_DTC1                    = 5'd16, // S16
    RXDESKEW_IDLE2             = 5'd17, // S17
    TO_TRAINERROR              = 5'd18; // S18

    reg [4:0] current_state, next_state, previous_state;
    wire      is_high_speed;
    assign is_high_speed = (rxdeskew_if.phy_negotiated_speed > SPEED_32G);
    wire data_incoherence = (current_state != previous_state);

    // =========================================================================
    // Rx Deskew Sweep Signals
    // =========================================================================
    localparam DW = $clog2(MAX_DESKEW_CODE + 1);

    reg [DW-1:0] swept_code_r;

    reg [DW-1:0] zone_min_r [15:0];
    reg [DW-1:0] best_lo    [15:0];
    reg [DW-1:0] best_hi    [15:0];
    reg          found_pass [15:0];
    reg          zone_valid [15:0];
    reg [DW-1:0] best_deskew_code [15:0];

    logic [15:0] negotiated_data_lanes;
    always @(*) begin
        case (rxdeskew_if.mb_rx_data_lane_mask)
            3'b000:  negotiated_data_lanes = 16'h0000;
            3'b001:  negotiated_data_lanes = 16'h00FF; // Lanes 0-7
            3'b010:  negotiated_data_lanes = 16'hFF00; // Lanes 8-15
            3'b011:  negotiated_data_lanes = 16'hFFFF; // Lanes 0-15
            3'b100:  negotiated_data_lanes = 16'h000F; // Lanes 0-3
            3'b101:  negotiated_data_lanes = 16'h00F0; // Lanes 4-7
            default: negotiated_data_lanes = 16'h0000;
        endcase
    end

    // Range calculation wires (combinational)
    wire [DW-1:0] best_range [15:0]; // Width of the best recorded pass window per lane
    wire [DW-1:0] zone_range [15:0]; // Width of the current active pass zone per lane
    wire [15:0]   found_pass_bus;    // Packed version of found_pass array for bitwise reduction

    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : DESKEW_RANGE_GEN
            assign found_pass_bus[lane] = found_pass[lane];
            assign best_range[lane] = (found_pass[lane] == 1'b1) ? (best_hi[lane] - best_lo[lane]) : '0;
            assign zone_range[lane] = (swept_code_r - zone_min_r[lane]);

            assign rxdeskew_if.phy_rx_deskew_ctrl[lane] =
                (   current_state == RXDESKEW_SET_CODE   ||
                    current_state == RXDESKEW_RX_D2C_PT  ||
                    current_state == RXDESKEW_LOG_RESULT) ? swept_code_r : best_deskew_code[lane];
        end
    endgenerate


    // =========================================================================
    // Tx EQ Preset & Arc Loop Tracking Signals (High-Speed Only)
    // =========================================================================
    // Tracks the number of preset search loops (max 5 loops to test P0-P5)
    reg [2:0] preset_search_cnt;

    // Tracks the number of fine-tuning arcs back to DTC1. Spec limits this to 4.
    // If the partner requests a 5th fine-tuning arc, we trigger TRAINERROR.
    reg [2:0] dtc1_arc_cnt;

    // Captures the arrival of the partner's {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req} message
    // if received while still in RXDESKEW_END_REQ. The 'req_msg_sent_timer' provides a delay
    // (allowing our own request to be safely transmitted) before consuming the captured message.

    // we use them to wait for sending the req message for:
    //         1. {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req}
    //         2. {MBTRAIN.RXDESKEW end req}
    // Why have we to wait some time? We just want to make sure the "rxdeskew_if.tx_sb_msg_valid"
    // is asserted for a while. To make sure that the SB will capture the this req msg
    // before exiting the current FSM state. (e.g. 15 clock cycles will be very safe).
    // The Timer name is "req_msg_sent_timer". the req msg time done flag is "req_msg_sent".
    reg        req_msg_rcvd      ; // The Req msg recevied flag
    reg  [3:0] req_msg_sent_timer; // The Req Timer Name.
    wire       req_msg_sent      ; // The Req msg time done flag

    // The currently requested local Tx EQ preset (P0=0, ..., P5=5).
    reg [2:0] my_preset;
    reg [2:0] partner_preset;

    // send_req[1]: current value. send_req[0]: old value.
    // we use send_req[0] to cause a '0' value on 'tx_sb_msg_valid_r' for
    // (1 lclk) period before sending a {...req} SB message directly.
    // this (1 lclk) period give as an indication about the seperation
    // between the {...req} SB message and the previous SB message {...req}.
    // This handle the scenario of receiving incorrect Tx EQ Preset (my_preset > 5).
    reg [1:0] send_req             ;
    reg [1:0] send_resp            ; // send_resp[1]: current value. send_resp[0]: old value. we use send_resp[0] to cause a '0' value on 'tx_sb_msg_valid_r' for (1 lclk) period.
    reg       my_preset_fail_status;
    reg       handcheck_done       ;
    reg       tx_sb_msg_valid_r    ;

    // =========================================================================
    // Preset Evaluation Tracking Signals (High-Speed Only)
    // =========================================================================
    // These registers store the globally "best" preset found across all 6 sweeps
    // (P0-P5). At each RXDESKEW_LOG_PRESET_RESULT state, the current preset's
    // cumulative eye-margin (sum of best_range[] for all negotiated lanes) is
    // compared against overall_best_total_range. If the current preset wins, all
    // four variables below are overwritten with the winner's data.

    // Index of the preset (P0-P5) that produced the widest cumulative eye margin.
    // Initialized to P0; updated by PRESET_EVAL_PROC in LOG_PRESET_RESULT.
    reg [2:0]    best_preset_saved;

    // The widest *minimum* eye margin seen so far across all tested presets.
    // This is the running maximum of the weakest-lane margin against which
    // each new preset is compared.
    reg [DW-1:0] overall_best_min_range;

    // Per-lane left/right edges of the widest contiguous pass window for the
    // best-so-far preset. Written in PRESET_EVAL_PROC when a new winner is found.
    // Used in DESKEW_TRACKING_PROC (CALC_APPLY) to compute the per-lane midpoint.
    reg [DW-1:0] overall_best_lo    [15:0];
    reg [DW-1:0] overall_best_hi    [15:0];

    // Per-lane flag: 1 = at least one passing deskew code was found for this lane
    // under the best-so-far preset. Used in CALC_APPLY to skip lanes with no pass.
    reg          overall_found_pass [15:0];

    // Packed wire mirror of overall_found_pass[] needed for bitwise reduction in
    // DESKEW_TRACKING_PROC. Unpacked arrays cannot be used directly in SystemVerilog
    // reduction/bitwise operators, so we pack it through this generate-driven bus.
    wire [15:0]  overall_found_pass_bus;

    // Combinational comparator: minimum of best_range[lane] over all negotiated lanes
    // for the *current* preset being swept. Recomputed every cycle. Compared against
    // overall_best_min_range in PRESET_EVAL_PROC at the LOG_PRESET_RESULT state.
    logic [DW-1:0] current_preset_min_range [0:16];

    // Fail flag: set in CALC_APPLY if any negotiated lane produced zero passing codes.
    // Exported via the continuous assign below to rxdeskew_if.rxdeskew_fail_flag.
    reg fail_flag_r;
    assign rxdeskew_if.rxdeskew_fail_flag = fail_flag_r;

    // req_msg_sent: asserted when req_msg_sent_timer saturates at 4'hF (15 lclk cycles).
    // This confirms our outgoing {req} SB message has been held valid long enough for
    // the Sideband IP to latch it before we exit the current FSM state.
    // Used in RXDESKEW_EXIT_DTC1_REQ, RXDESKEW_END_REQ, and RXDESKEW_PRESET_REQ_RESP
    // as an early-exit guard (see REQ_MSG_RCVD_AND_SENT_PROC for full details).
    assign req_msg_sent = (req_msg_sent_timer == 4'hF);

    // Captures the MsgInfo field of a prematurely-consumed SB message.
    // When req_msg_rcvd is set (a message was consumed in a PRIOR state),
    // rx_msginfo is valid for only that one clock cycle. We save it here so
    // that the DESTINATION state can still correctly read the preset field
    // (e.g. my_preset = captured_rx_msginfo[2:0]) even after rx_msginfo has
    // gone stale.
    reg [15:0] captured_rx_msginfo;

    // Tracks the partner's pass/fail verdict on the preset WE requested.
    // Set from rx_msginfo[0] of the received EQ_Preset_resp. Used together
    // with my_preset_fail_status to determine handcheck_done.
    reg        partner_preset_fail_status;

    // =========================================================================
    // overall_found_pass_bus: packed mirror of overall_found_pass[] unpacked array
    // =========================================================================
    generate
        genvar l;
        for (l = 0; l < 16; l = l + 1) begin : OVERALL_PASS_GEN
            assign overall_found_pass_bus[l] = overall_found_pass[l];
        end
    endgenerate


    // =========================================================================
    // Current State
    // =========================================================================
    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin
        if(~rxdeskew_if.rst_n) begin
            current_state  <= RXDESKEW_IDLE;
            previous_state <= RXDESKEW_IDLE;
        end
        else begin
            current_state  <= next_state   ;
            previous_state <= current_state;
        end
    end

    // =========================================================================
    // Next State
    // =========================================================================
    always @(*) begin
        // Global error override: any 8 ms timeout or partner {TRAINERROR Entry req}
        // immediately forces transition to TO_TRAINERROR
        if (rxdeskew_if.timeout_8ms_occured | (rxdeskew_if.rx_sb_msg == TRAINERROR_Entry_req && rxdeskew_if.rx_sb_msg_valid == 1'b1)) begin
            next_state = TO_TRAINERROR; // (S18)
        end
        else begin
            case(current_state)
                // -------------------------------------------------------------
                // (S0) IDLE: Wait for rxdeskew_en
                // -------------------------------------------------------------
                RXDESKEW_IDLE: begin
                    next_state = (rxdeskew_if.rxdeskew_en)? RXDESKEW_START_REQ : RXDESKEW_IDLE;
                end

                // -------------------------------------------------------------
                // (S1) RXDESKEW_START_REQ: send & receive {MBTRAIN.RXDESKEW start req}.
                // -------------------------------------------------------------
                RXDESKEW_START_REQ: begin
                    if ((rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_start_req) || (req_msg_rcvd && req_msg_sent)) begin
                        next_state = RXDESKEW_START_RESP;
                    end else begin
                        next_state = RXDESKEW_START_REQ;
                    end
                end

                // -------------------------------------------------------------
                // (S2) RXDESKEW_START_RESP: send & receive {MBTRAIN.RXDESKEW start resp}.
                // -------------------------------------------------------------
                RXDESKEW_START_RESP: begin
                    if (rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_start_resp) begin
                        if (is_high_speed) begin
                            // High-Speed: go evaluate Tx EQ Presets
                            next_state = RXDESKEW_CHOOSE_PRESET;
                        end else begin
                            // Standard Speed: start deskew sweep
                            next_state = RXDESKEW_SET_CODE;
                        end
                    end
                    else begin
                        next_state = RXDESKEW_START_RESP;
                    end
                end

                // -------------------------------------------------------------
                // (S3) RXDESKEW_SET_CODE: Set code and wait for analog settle timer.
                // -------------------------------------------------------------
                RXDESKEW_SET_CODE: begin
                    if (rxdeskew_if.valtraincenter_fail_flag | rxdeskew_if.partner_valtraincenter_fail_flag) begin
                        next_state = RXDESKEW_END_REQ;
                    end
                    else if (rxdeskew_if.analog_settle_time_done) begin
                        next_state = RXDESKEW_RX_D2C_PT;
                    end
                    else begin
                        next_state = RXDESKEW_SET_CODE;
                    end
                end

                // -------------------------------------------------------------
                // (S4) RXDESKEW_RX_D2C_PT: Run Rx init D2C Point test and wait for result.
                // -------------------------------------------------------------
                RXDESKEW_RX_D2C_PT: begin
                    if (d2c_if.test_d2c_done) begin
                        next_state = RXDESKEW_LOG_RESULT;
                    end
                    else begin
                        next_state = RXDESKEW_RX_D2C_PT;
                    end
                end

                // -------------------------------------------------------------
                // (S5) RXDESKEW_LOG_RESULT: Log the result for current code.
                // -------------------------------------------------------------
                RXDESKEW_LOG_RESULT: begin
                    if (swept_code_r == MAX_DESKEW_CODE[DW-1:0]) begin
                        next_state = (is_high_speed)? RXDESKEW_LOG_PRESET_RESULT : RXDESKEW_CALC_APPLY;
                    end else begin
                        next_state = RXDESKEW_SET_CODE; // Loop back for next code
                    end
                end

                // -------------------------------------------------------------
                // (S6) RXDESKEW_CALC_APPLY: Calculates the optimal midpoint deskew code for
                //          each lane based on logged results and applies it.
                //          If the speed > 32 GT/s, It applies the best calculateed optimal
                //          preset deskew code for each Tx EQ Preset (P0, P1, P2, P3, P4, P5)
                //          based on logged results in (S12) RXDESKEW_LOG_PRESET_RESULT state
                //          and applies it.
                // -------------------------------------------------------------
                RXDESKEW_CALC_APPLY: begin
                    // After all 6 presets have been swept (preset_search_cnt == 5), best_preset_saved
                    // holds the optimal Tx EQ Preset. We ALWAYS perform the PRESET_REQ_RESP handshake
                    // unconditionally — even if the last tested preset (P5) happened to be the best.
                    // Reason: forcing both sides through the same fixed sequence guarantees
                    // symmetric SB synchronization. The 'lucky-case' shortcut (skipping the
                    // handshake when partner_preset already equals best_preset_saved) is deliberately
                    // avoided to keep both sides on the same state-machine path at all times.
                    // PRESET_REQ_RESP_PROC has already set partner_preset = best_preset_saved
                    // unconditionally in its CALC_APPLY clause, so the handshake will always
                    // negotiate the correct optimal preset.
                    if (is_high_speed) begin
                        next_state = RXDESKEW_PRESET_REQ_RESP;
                    end else begin
                        // Standard speed: no preset negotiation exists, proceed to exit.
                        next_state = RXDESKEW_END_REQ;
                    end
                end

                // -------------------------------------------------------------
                // (S7) RXDESKEW_END_REQ: Send and receive {MBTRAIN.RXDESKEW end req}.
                // -------------------------------------------------------------
                RXDESKEW_END_REQ: begin
                    if (    (rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_end_req) ||
                            (req_msg_rcvd && req_msg_sent)) begin
                        next_state = RXDESKEW_END_RESP;
                    end
                    // if the {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req} msg rcvd:
                    else if (rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req) begin
                        next_state = (dtc1_arc_cnt == 3'd4)? TO_TRAINERROR : RXDESKEW_EXIT_DTC1_REQ;
                    end
                    else begin
                        next_state = RXDESKEW_END_REQ;
                    end
                end

                // -------------------------------------------------------------
                // (S8) RXDESKEW_END_RESP: Send and receive {MBTRAIN.RXDESKEW end resp}.
                // -------------------------------------------------------------
                RXDESKEW_END_RESP: begin
                    if (rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_end_resp) begin
                        next_state = TO_DTC2;
                    end else begin
                        next_state = RXDESKEW_END_RESP;
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
                // (S11) RXDESKEW_PRESET_REQ_RESP: Its logic is in the PRESET_REQ_RESP_PROC block below.
                //          Here we wait for the hand check of {MBTRAIN.RXDESKEW EQ Preset req} &
                //          {MBTRAIN.RXDESKEW EQ Preset resp} to be done completely.
                // -------------------------------------------------------------
                RXDESKEW_PRESET_REQ_RESP  : begin
                    if(handcheck_done) begin
                        // PRESET_REQ_RESP is entered from exactly two paths:
                        //
                        //   PATH A — Search phase  (CHOOSE_PRESET → PRESET_REQ_RESP):
                        //     preset_search_cnt < 5: still iterating through P0–P5.
                        //     Action: start the deskew sweep for the newly negotiated preset.
                        //
                        //   PATH B — Fine-tuning phase  (CALC_APPLY → PRESET_REQ_RESP):
                        //     preset_search_cnt == 5: all 6 presets swept, best preset confirmed.
                        //     Action: arc to DTC1 if arc budget remains, else exit cleanly.
                        //     Note: on re-entry (dtc1_arc_cnt > 0) the same PATH B logic applies;
                        //     the arc-budget check naturally handles all subsequent arcs.
                        if (preset_search_cnt < 3'd5) begin
                            // PATH A: search iteration complete.
                            // Run the deskew sweep for this newly negotiated preset.
                            next_state = RXDESKEW_SET_CODE;
                        end else if (dtc1_arc_cnt != MAX_ARC_LIMIT) begin
                            // PATH B — arc budget remains:
                            // Best preset confirmed on both sides. Arc back to DTC1 so
                            // Vref can be re-optimised under the selected best preset.
                            next_state = RXDESKEW_EXIT_DTC1_REQ;
                        end else begin
                            // PATH B — arc budget exhausted:
                            // All MAX_ARC_LIMIT fine-tuning arcs used up. Exit RXDESKEW.
                            next_state = RXDESKEW_END_REQ;
                        end
                    end
                    // Escape [D-exit]: partner sent end_req while we are in PRESET_REQ_RESP.
                    // Scenario: partner finished their PRESET_REQ_RESP earlier and moved to
                    // END_REQ. We are still in PRESET_REQ_RESP. The end_req arrives here.
                    // REQ_MSG_RCVD_AND_SENT_PROC sets req_msg_rcvd=1. We go to END_REQ and use
                    // (req_msg_rcvd && req_msg_sent) to exit without waiting for a 2nd pulse.
                    else if (rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_end_req) begin
                        next_state = RXDESKEW_END_REQ;
                    end
                    // Escape [E-exit]: partner sent exit_to_DTC1_req while we are in PRESET_REQ_RESP.
                    // Scenario: partner skipped PRESET_REQ_RESP entirely (their preset was already
                    // optimal) and jumped directly to EXIT_DTC1_REQ. We receive their req here.
                    // REQ_MSG_RCVD_AND_SENT_PROC sets req_msg_rcvd=1. We go to EXIT_DTC1_REQ
                    // and use (req_msg_rcvd && req_msg_sent) as the substitute exit condition.
                    else if (rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req) begin
                        next_state = (dtc1_arc_cnt < MAX_ARC_LIMIT)? RXDESKEW_EXIT_DTC1_REQ : TO_TRAINERROR;
                    end
                    else begin
                        next_state = RXDESKEW_PRESET_REQ_RESP;
                    end
                end

                // -------------------------------------------------------------
                // (S12) RXDESKEW_LOG_PRESET_RESULT: Log the best deskew code result for current preset
                //                                   and check if we need to continue to next preset.
                // -------------------------------------------------------------
                RXDESKEW_LOG_PRESET_RESULT: begin
                    if(preset_search_cnt == 3'd5) begin
                        next_state = RXDESKEW_CALC_APPLY;
                    end
                    else begin
                        next_state = RXDESKEW_CHOOSE_PRESET;
                    end
                end

                // -------------------------------------------------------------
                // (S13) RXDESKEW_EXIT_DTC1_REQ:
                // -------------------------------------------------------------
                RXDESKEW_EXIT_DTC1_REQ    : begin
                    if((rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req) ||
                            (req_msg_rcvd && req_msg_sent)) begin
                        next_state = RXDESKEW_ARC_COUNT;
                    end
                    else begin
                        next_state = RXDESKEW_EXIT_DTC1_REQ;
                    end
                end

                // -------------------------------------------------------------
                // (S14) RXDESKEW_ARC_COUNT
                // -------------------------------------------------------------
                RXDESKEW_ARC_COUNT        : begin
                    next_state = RXDESKEW_EXIT_DTC1_RESP;
                end

                // -------------------------------------------------------------
                // (S15) RXDESKEW_EXIT_DTC1_RESP
                // -------------------------------------------------------------
                RXDESKEW_EXIT_DTC1_RESP   : begin
                    if(rxdeskew_if.rx_sb_msg_valid && rxdeskew_if.rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp) begin
                        next_state = TO_DTC1;
                    end
                    else begin
                        next_state = RXDESKEW_EXIT_DTC1_RESP;
                    end
                end

                // -------------------------------------------------------------
                // (S16) TO_DTC1: Terminal State
                // -------------------------------------------------------------
                TO_DTC1: begin
                    next_state = (rxdeskew_if.rxdeskew_en) ? TO_DTC1 : RXDESKEW_IDLE2;
                end

                // -------------------------------------------------------------
                // (S17) RXDESKEW_IDLE2
                // -------------------------------------------------------------
                RXDESKEW_IDLE2: begin
                    if (rxdeskew_if.rxdeskew_en) begin
                        // Resume execution after returning from DTC1 loop for fine-tuning.
                        // We must send the START_REQ handshake per spec.
                        next_state = RXDESKEW_START_REQ;
                    end else begin
                        next_state = RXDESKEW_IDLE2;
                    end
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
    // Deskew Sweep Tracking Logic
    // =========================================================================
    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : SWEPT_CODE_PROC
        if (!rxdeskew_if.rst_n) begin
            swept_code_r <= MIN_DESKEW_CODE[DW-1:0];
        end else if (current_state == RXDESKEW_START_RESP || current_state == RXDESKEW_PRESET_REQ_RESP) begin
            // Reset the sweep counter when about to enter a new deskew sweep.
            if (next_state == RXDESKEW_SET_CODE) begin
                swept_code_r <= MIN_DESKEW_CODE[DW-1:0];
            end
        end else if (current_state == RXDESKEW_LOG_RESULT) begin
            if (swept_code_r != MAX_DESKEW_CODE[DW-1:0]) begin
                swept_code_r <= swept_code_r + 1'b1;
            end
        end
    end

    // =========================================================================
    // PRESET_MIN_RANGE_PROC: Combinational minimum for current preset margin
    // =========================================================================
    // Finds the minimum best_range[lane] across all negotiated lanes to produce
    // current_preset_min_range. This value is compared in PRESET_EVAL_PROC
    // (at LOG_PRESET_RESULT) to decide if the current preset beats the global best.
    // All declarations are in the consolidated signal declarations section above.
    always @(*) begin
        current_preset_min_range[0] = MAX_DESKEW_CODE[DW-1:0];
        for (integer l = 0; l < 16; l = l + 1) begin
            current_preset_min_range[l + 1] = ((negotiated_data_lanes[l]) && (best_range[l] < current_preset_min_range[l]))?
                best_range[l] : current_preset_min_range[l];
        end
    end

    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : PRESET_EVAL_PROC
        integer i;
        if (!rxdeskew_if.rst_n) begin
            best_preset_saved <= 3'd0;
            overall_best_min_range <= '0;
            for (i = 0; i < 16; i = i + 1) begin
                overall_best_lo[i]    <= '0;
                overall_best_hi[i]    <= '0;
                overall_found_pass[i] <= 1'b0;
            end
        end else begin
            if (current_state == RXDESKEW_IDLE && rxdeskew_if.rxdeskew_en) begin
                best_preset_saved <= 3'd0;
                overall_best_min_range <= '0;
                for (i = 0; i < 16; i = i + 1) begin
                    overall_best_lo[i]    <= '0;
                    overall_best_hi[i]    <= '0;
                    overall_found_pass[i] <= 1'b0;
                end
            end

            if (current_state == RXDESKEW_LOG_PRESET_RESULT) begin
                if (current_preset_min_range[16] > overall_best_min_range || preset_search_cnt == 3'd0 || dtc1_arc_cnt > 0) begin
                    overall_best_min_range <= current_preset_min_range[16];
                    best_preset_saved      <= partner_preset;
                    for (i = 0; i < 16; i = i + 1) begin
                        overall_best_lo[i]    <= best_lo[i];
                        overall_best_hi[i]    <= best_hi[i];
                        overall_found_pass[i] <= found_pass[i];
                    end
                end
            end
        end
    end

    // NOTE: overall_found_pass_bus generate block, fail_flag_r, and their assigns
    // are declared in the consolidated signal declarations section above.

    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : DESKEW_TRACKING_PROC
        integer i;
        if (!rxdeskew_if.rst_n) begin
            fail_flag_r <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                zone_min_r[i]       <= '0;
                best_lo[i]          <= '0;
                best_hi[i]          <= '0;
                found_pass[i]       <= 1'b0;
                zone_valid[i]       <= 1'b0;
                best_deskew_code[i] <= MIN_DESKEW_CODE[DW-1:0];
            end
        end else begin
            // Reset tracking arrays when starting a new sweep for a preset
            if ((current_state == RXDESKEW_START_RESP || current_state == RXDESKEW_PRESET_REQ_RESP) && next_state == RXDESKEW_SET_CODE) begin
                for (i = 0; i < 16; i = i + 1) begin
                    zone_min_r[i]       <= '0;
                    best_lo[i]          <= '0;
                    best_hi[i]          <= '0;
                    found_pass[i]       <= 1'b0;
                    zone_valid[i]       <= 1'b0;
                end
                fail_flag_r <= 1'b0;
            end
            // Track results during the D2C test logging state
            else if (current_state == RXDESKEW_LOG_RESULT) begin
                for (i = 0; i < 16; i = i + 1) begin
                    if (!d2c_if.d2c_perlane_err[i]) begin
                        // PASS: Error-free timing point
                        if (!zone_valid[i]) begin
                            zone_valid[i] <= 1'b1;
                            zone_min_r[i] <= swept_code_r;
                            if (!found_pass[i] && negotiated_data_lanes[i]) begin
                                found_pass[i] <= 1'b1;
                                best_lo[i]    <= swept_code_r;
                                best_hi[i]    <= swept_code_r;
                            end
                        end else begin
                            if (zone_range[i] > best_range[i]) begin
                                best_lo[i] <= zone_min_r[i];
                                best_hi[i] <= swept_code_r;
                            end
                        end
                    end else begin
                        // FAIL: Error found
                        zone_valid[i] <= 1'b0;
                    end
                end
            end
            // Calculate and apply the best code
            else if (current_state == RXDESKEW_CALC_APPLY) begin
                if (is_high_speed) begin
                    for (i = 0; i < 16; i = i + 1) begin
                        if (overall_found_pass[i]) begin
                            best_deskew_code[i] <= ({1'b0, overall_best_lo[i]} + {1'b0, overall_best_hi[i]}) >> 1;
                        end else begin
                            best_deskew_code[i] <= MIN_DESKEW_CODE[DW-1:0];
                        end
                    end
                    fail_flag_r <= ~(&(overall_found_pass_bus | (~negotiated_data_lanes)));
                end else begin
                    for (i = 0; i < 16; i = i + 1) begin
                        if (found_pass[i]) begin
                            best_deskew_code[i] <= ({1'b0, best_lo[i]} + {1'b0, best_hi[i]}) >> 1;
                        end else begin
                            best_deskew_code[i] <= MIN_DESKEW_CODE[DW-1:0];
                        end
                    end
                    fail_flag_r <= ~(&(found_pass_bus | (~negotiated_data_lanes)));
                end
            end
        end
    end

    // =========================================================================
    // Counters Tracking Logic (Arcs & Preset loops)
    // =========================================================================
    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : COUNTERS_PROC
        if (!rxdeskew_if.rst_n) begin
            preset_search_cnt <= 3'd0;
            dtc1_arc_cnt      <= 3'd0;
        end else begin
            // Reset counters on new session entry
            if (current_state == RXDESKEW_IDLE && rxdeskew_if.rxdeskew_en) begin
                preset_search_cnt <= 3'd0;
                dtc1_arc_cnt      <= 3'd0;
            end

            // Increment preset search count
            if (current_state == RXDESKEW_LOG_PRESET_RESULT && next_state == RXDESKEW_CHOOSE_PRESET) begin
                preset_search_cnt <= preset_search_cnt + 1'b1;
            end

            // Increment fine-tuning arc count when transitioning to EXIT_DTC1_REQ
            if (next_state == RXDESKEW_EXIT_DTC1_REQ && current_state != RXDESKEW_EXIT_DTC1_REQ) begin
                dtc1_arc_cnt <= dtc1_arc_cnt + 1'b1;
            end
        end
    end

    // =========================================================================
    // Output logic Block:
    // =========================================================================
    always @(*) begin
        //==========================================================================//
        //              Default values for outputs (to avoid latches)               //
        //==========================================================================//

        // LTSM -> LTSM signals:
        rxdeskew_if.rxdeskew_done        = 1'b0;
        rxdeskew_if.trainerror_req       = 1'b0;
        rxdeskew_if.datatraincenter1_req = 1'b0;

        // Timers:
        rxdeskew_if.timeout_timer_en       = 1'b1; // 8ms timer runs by default in all active states.
        rxdeskew_if.analog_settle_timer_en = 1'b0;

        // MB signals: (Mainband)
        // All lanes active by default during training states
        rxdeskew_if.mb_tx_clk_lane_sel  = 2'b01;
        rxdeskew_if.mb_tx_data_lane_sel = 2'b01;
        rxdeskew_if.mb_tx_val_lane_sel  = 2'b01;
        rxdeskew_if.mb_tx_trk_lane_sel  = 2'b01;

        rxdeskew_if.mb_rx_clk_lane_sel  = 1'b1; // 1-bit: 1b = Enabled
        rxdeskew_if.mb_rx_data_lane_sel = 1'b1;
        rxdeskew_if.mb_rx_val_lane_sel  = 1'b1;
        rxdeskew_if.mb_rx_trk_lane_sel  = 1'b1;



        // PHY TX EQ Preset
        rxdeskew_if.phy_tx_eq_preset_ctrl = my_preset; // Update PHY with OUR negotiated preset

        // SB signals: (Sideband)
        rxdeskew_if.tx_sb_msg_valid = 1'b0   ;
        rxdeskew_if.tx_sb_msg       = NOTHING;
        rxdeskew_if.tx_msginfo      = 16'h0  ;
        rxdeskew_if.tx_data_field   = 64'h0  ;

        // Substate-to-D2C Interface:
        d2c_if.rx_pt_en             = 1'b0;
        d2c_if.tx_pt_en             = 1'b0;
        d2c_if.d2c_clk_sampling     = 2'b00;    // 00h: Eye Center.
        d2c_if.d2c_lfsr_en          = 1'b1;     // Enable Tx & Rx LFSR.
        d2c_if.d2c_pattern_setup    = 3'b011;   // Data + Valid pattern active.
        d2c_if.d2c_data_pattern_sel = 2'b00;    // Per-Lane LFSR pattern.
        d2c_if.d2c_val_pattern_sel  = 1'b0;     // VALTRAIN pattern (held no-care).
        d2c_if.d2c_pattern_mode     = 1'b0;     // Continuous mode.
        d2c_if.d2c_burst_count      = 16'd1;    // 1 UI burst to speed up sim.
        d2c_if.d2c_idle_count       = 16'd0;
        d2c_if.d2c_iter_count       = 16'd1;    // Important: 1 iteration to complete
        d2c_if.d2c_compare_setup    = 2'd0;     // Per-Lane comparison -> d2c_perlane_err[15:0].
        case(current_state)
            // -------------------------------------------------------------
            // (S0) IDLE: Wait for rxdeskew_en
            // -------------------------------------------------------------
            RXDESKEW_IDLE: begin
                rxdeskew_if.timeout_timer_en    = 1'b0;
                rxdeskew_if.mb_tx_clk_lane_sel  = 2'b00;
                rxdeskew_if.mb_tx_data_lane_sel = 2'b00;
                rxdeskew_if.mb_tx_val_lane_sel  = 2'b00;
                rxdeskew_if.mb_tx_trk_lane_sel  = 2'b00;
                rxdeskew_if.mb_rx_clk_lane_sel  = 1'b0; // 1-bit: 0b = Disabled
                rxdeskew_if.mb_rx_data_lane_sel = 1'b0;
                rxdeskew_if.mb_rx_val_lane_sel  = 1'b0;
                rxdeskew_if.mb_rx_trk_lane_sel  = 1'b0;
            end

            // -------------------------------------------------------------
            // (S1) RXDESKEW_START_REQ: send & receive {MBTRAIN.RXDESKEW start req}.
            // -------------------------------------------------------------
            RXDESKEW_START_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_start_req;
            end

            // -------------------------------------------------------------
            // (S2) RXDESKEW_START_RESP: send & receive {MBTRAIN.RXDESKEW start resp}.
            // -------------------------------------------------------------
            RXDESKEW_START_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_start_resp;
            end

            // -------------------------------------------------------------
            // (S3) RXDESKEW_SET_CODE: Set code and wait for analog settle timer.
            // -------------------------------------------------------------
            RXDESKEW_SET_CODE: begin
                rxdeskew_if.analog_settle_timer_en = 1'b1;
            end

            // -------------------------------------------------------------
            // (S4) RXDESKEW_RX_D2C_PT: Run Rx init D2C Point test and wait for result.
            // -------------------------------------------------------------
            RXDESKEW_RX_D2C_PT: begin
                d2c_if.rx_pt_en = 1'b1;
            end

            // -------------------------------------------------------------
            // (S5) RXDESKEW_LOG_RESULT: Log the result for current code.
            // -------------------------------------------------------------
            RXDESKEW_LOG_RESULT: begin
            end

            // -------------------------------------------------------------
            // (S6) RXDESKEW_CALC_APPLY: Calculates the optimal midpoint deskew code for
            //          each lane based on logged results and applies it.
            //          If the speed > 32 GT/s, It applies the best calculateed optimal
            //          preset deskew code for each Tx EQ Preset (P0, P1, P2, P3, P4, P5)
            //          based on logged results in (S12) RXDESKEW_LOG_PRESET_RESULT state
            //          and applies it.
            // -------------------------------------------------------------
            RXDESKEW_CALC_APPLY: begin
                // Applies calculated optimal value. Next state handled in next_state logic block.
            end

            // -------------------------------------------------------------
            // (S7) RXDESKEW_END_REQ: Send and receive {MBTRAIN.RXDESKEW end req}.
            // -------------------------------------------------------------
            RXDESKEW_END_REQ: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_end_req;
            end

            // -------------------------------------------------------------
            // (S8) RXDESKEW_END_RESP: Send and receive {MBTRAIN.RXDESKEW end resp}.
            // -------------------------------------------------------------
            RXDESKEW_END_RESP: begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_end_resp;
            end

            // -------------------------------------------------------------
            // (S9) TO_DTC2: Terminal State
            // -------------------------------------------------------------
            TO_DTC2: begin
                rxdeskew_if.rxdeskew_done      = 1'b1;
                rxdeskew_if.timeout_timer_en   = 1'b0;
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
            end

            // -------------------------------------------------------------
            // (S11) RXDESKEW_PRESET_REQ_RESP: Its logic is in the PRESET_REQ_RESP_PROC below block
            //          Here we wait for the hand check of {MBTRAIN.RXDESKEW EQ Preset req} &
            //          {MBTRAIN.RXDESKEW EQ Preset resp} done completely.
            // -------------------------------------------------------------
            RXDESKEW_PRESET_REQ_RESP  : begin
                rxdeskew_if.tx_sb_msg_valid = tx_sb_msg_valid_r;
                if (send_req[1]) begin
                    rxdeskew_if.tx_sb_msg  = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req;
                    rxdeskew_if.tx_msginfo = {12'd0, 1'b0, partner_preset};
                end else if (send_resp[1]) begin
                    rxdeskew_if.tx_sb_msg  = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
                    rxdeskew_if.tx_msginfo = {15'd0, my_preset_fail_status};
                end
            end

            // -------------------------------------------------------------
            // (S12) RXDESKEW_LOG_PRESET_RESULT: Log the best deskew code result for current preset
            //                                   and check if we need to continue to next preset.
            // -------------------------------------------------------------
            RXDESKEW_LOG_PRESET_RESULT: begin
            end

            // -------------------------------------------------------------
            // (S13) RXDESKEW_EXIT_DTC1_REQ:
            // -------------------------------------------------------------
            RXDESKEW_EXIT_DTC1_REQ    : begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req;
            end

            // -------------------------------------------------------------
            // (S14) RXDESKEW_ARC_COUNT
            // -------------------------------------------------------------
            RXDESKEW_ARC_COUNT        : begin
            end

            // -------------------------------------------------------------
            // (S15) RXDESKEW_EXIT_DTC1_RESP
            // -------------------------------------------------------------
            RXDESKEW_EXIT_DTC1_RESP   : begin
                rxdeskew_if.tx_sb_msg_valid = !data_incoherence;
                rxdeskew_if.tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp;
            end

            // -------------------------------------------------------------
            // (S16) TO_DTC1: Terminal State
            // -------------------------------------------------------------
            TO_DTC1: begin
                rxdeskew_if.datatraincenter1_req = 1'b1; // Trigger FSM jump back to DTC1
                rxdeskew_if.timeout_timer_en     = 1'b0;
            end

            // -------------------------------------------------------------
            // (S17) RXDESKEW_IDLE2
            // -------------------------------------------------------------
            RXDESKEW_IDLE2: begin
            end

            // -------------------------------------------------------------
            // (S18) TO_TRAINERROR: Terminal State
            // -------------------------------------------------------------
            TO_TRAINERROR: begin
                rxdeskew_if.trainerror_req     = 1'b1;
                rxdeskew_if.rxdeskew_done      = 1'b1; // Unblock LTSM
                rxdeskew_if.timeout_timer_en   = 1'b0;
            end

            default: ;
        endcase
    end
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================
// ===========================================================================================================================================================================================

    // =======================================================================================================
    // HANDCHECK_PROC
    // =======================================================================================================
    
    // [1] is the previous state msg, [0] is the current state msg.
    // We need the to compare them to generate just a  pulse (1 lclk cycle) of 'tx_sb_msg_valid' for each message sent. 
    reg  [3:0]         send_sb_msg [1:0] ;
    
    // It represents the tx SB valid signal but with duration = 1 lclk period.
    wire               sb_msg_valid_pulse;

    // These signals to store the unexpected reseived SB message in eary time (before we lost it).
    reg                rx_sb_msg_valid_r   ;
    UCIe_pkg::msg_no_e rx_sb_msg_r         ;
    reg [3:0]          rx_msginfo_r        ;

    // The timer that count from 31 to 0 after each SB message sending on our die Tx. 
    reg  [4:0]         send_timer          ;

    // The signals that handle the problem of early receiving SB messages.
    wire               is_sb_msg_valid_rcvd;
    UCIe_pkg::msg_no_e rx_sb_msg_rcvd      ;
    wire [3:0]         rx_msginfo_rcvd     ;

    assign sb_msg_valid_pulse   = (send_sb_msg[1] != send_sb_msg[0]);
    assign is_sb_msg_valid_rcvd = (send_timer != 5'b0                     )?     1'b0     : (rx_sb_msg_valid_r | rxdeskew_if.rx_sb_msg_valid);
    assign rx_msginfo_rcvd      = (send_timer == 5'b0 && rx_sb_msg_valid_r)? rx_msginfo_r : rxdeskew_if.rx_msginfo[3:0]                      ;
    assign rx_sb_msg_rcvd       = (send_timer == 5'b0 && rx_sb_msg_valid_r)? rx_sb_msg_r  : rxdeskew_if.rx_sb_msg                            ;

    // To represent the SB messages that will be discussed to send.
    localparam [3:0]   NO_MSG         = 4'H0,
                       START_REQ      = 4'H1,
                       START_RESP     = 4'H2,
                       PRESET_REQ     = 4'H3,
                       PRESET_RESP    = 4'H4,
                       EXIT_DTC1_REQ  = 4'H5,
                       EXIT_DTC1_RESP = 4'H6,
                       END_REQ        = 4'H7,
                       END_RESP       = 4'H8;

    always @(posedge rxdeskew_if.lclk or negedge rxdeskew_if.rst_n) begin : HANDCHECK_PROC
        if (rxdeskew_if.rst_n == 1'b0) begin
            handcheck_done      <= 1'b0     ;
            {send_sb_msg [1], send_sb_msg [0]} <= {NO_MSG, NO_MSG};
            my_preset_fail_status      <= 1'b0;
            // partner_preset_fail_status <= 1'b0;
        end
        else if( current_state == RXDESKEW_IDLE && rxdeskew_en)begin
            {send_sb_msg [1], send_sb_msg [0]} <= {NO_MSG, START_REQ};
            my_preset_fail_status      <= 1'b0;
            // partner_preset_fail_status <= 1'b0;
        end
        else begin
            send_sb_msg [1] <= send_sb_msg [0];

            // -----------------------------
            // For Tx SB Message Check
            // -----------------------------
            if(send_sb_msg[0] == START_REQ) begin
                rxdeskew_if.tx_sb_msg_valid  <= sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg        <= MBTRAIN_RXDESKEW_start_req;
                rxdeskew_if.tx_sb_msginfo    <= 16'h0;
                rxdeskew_if.tx_sb_data_field <= 64'h0;
            end
            else if(send_sb_msg[0] == START_RESP) begin
                rxdeskew_if.tx_sb_msg_valid  <= sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg        <= MBTRAIN_RXDESKEW_start_resp;
                rxdeskew_if.tx_sb_msginfo    <= 16'h0;
                rxdeskew_if.tx_sb_data_field <= 64'h0;
            end
            else if(send_sb_msg[0] == PRESET_REQ) begin
                rxdeskew_if.tx_sb_msg_valid  <= sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg        <= MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req;
                rxdeskew_if.tx_sb_msginfo    <= {13'b0, 3'partner_preset};
                rxdeskew_if.tx_sb_data_field <= 64'h0;
            end
            else if(send_sb_msg[0] == PRESET_RESP) begin
                rxdeskew_if.tx_sb_msg_valid  <= sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg        <= MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
                rxdeskew_if.tx_sb_msginfo    <= {15'b0, my_preset_fail_status};
                rxdeskew_if.tx_sb_data_field <= 64'h0;
            end
            else if(send_sb_msg[0] == EXIT_DTC1_REQ) begin
                rxdeskew_if.tx_sb_msg_valid  <= sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg        <= MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req;
                rxdeskew_if.tx_sb_msginfo    <= 16'h0;
                rxdeskew_if.tx_sb_data_field <= 64'h0;
            end
            else if(send_sb_msg[0] == EXIT_DTC1_RESP) begin
                rxdeskew_if.tx_sb_msg_valid  <= sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg        <= MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp;
                rxdeskew_if.tx_sb_msginfo    <= 16'h0;
                rxdeskew_if.tx_sb_data_field <= 64'h0;
            end
            else if(send_sb_msg[0] == END_REQ) begin
                rxdeskew_if.tx_sb_msg_valid  <= sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg        <= MBTRAIN_RXDESKEW_end_req;
                rxdeskew_if.tx_sb_msginfo    <= 16'h0;
                rxdeskew_if.tx_sb_data_field <= 64'h0;
            end
            else if(send_sb_msg[0] == END_RESP) begin
                rxdeskew_if.tx_sb_msg_valid  <= sb_msg_valid_pulse;
                rxdeskew_if.tx_sb_msg        <= MBTRAIN_RXDESKEW_end_resp;
                rxdeskew_if.tx_sb_msginfo    <= 16'h0;
                rxdeskew_if.tx_sb_data_field <= 64'h0;
            end

            // -----------------------------
            // For Rx SB Message Check
            // -----------------------------
            if (is_sb_msg_valid_rcvd) begin
                // for the partner handcheck.
                if(rx_sb_msg_rcvd == MBTRAIN_RXDESKEW_start_req)begin
                    send_sb_msg [0] <= START_RESP;
                    target_state <= RXDESKEW_START_REQ_RESP;
                end
                // for my die handcheck.
                else if(rx_sb_msg_rcvd == MBTRAIN_RXDESKEW_start_resp)begin
                    send_sb_msg [0] <= PRESET_REQ;
                    target_state <= (is_high_speed)? RXDESKEW_EQ_PRESET_REQ_RESP : RXDESKEW_SET_CODE;
                end
                //---------------------------------------------------------------------------
                
                // for the partner handcheck.
                else if(rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req)begin
                    send_sb_msg [0] <= PRESET_RESP;
                    my_preset             <= (rx_msginfo_rcvd[3:0] > 5)? my_preset : rx_msginfo_rcvd[2:0];
                    my_preset_fail_status <= (rx_msginfo_rcvd[3:0] > 5);
                    // Note: These 2 states 'RXDESKEW_END_REQ_RESP' & 'RXDESKEW_EXIT_DTC1_REQ_RESP' are the last states and the FSM is directed to them when the Tx EQ Preset is choosen and settled.
                    // So, when we want to synchronize our die FSM with the partner FSM without changing the preset, we choose to go to the 'RXDESKEW_EQ_PRESET_REQ_RESP' state just for synchronization (handshake).
                    target_state <= (current_state == RXDESKEW_END_REQ_RESP || current_state == RXDESKEW_EXIT_DTC1_REQ_RESP)? RXDESKEW_EQ_PRESET_REQ_RESP : RXDESKEW_CHOOSE_PRESET;
                end
                // for my die handcheck.
                else if(rx_sb_msg_rcvd == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp)begin
                    send_sb_msg [0]       <= (rx_msginfo_rcvd[0] | my_preset_fail_status) ? PRESET_REQ : RX_D2C_PT_START_REQ;
                    my_preset_fail_status <= (rx_msginfo_rcvd[0] | my_preset_fail_status);
                    // partner_preset_fail_status <= (rx_msginfo_rcvd[0] | my_preset_fail_status);
                    target_state <= (rx_msginfo_rcvd[0] | my_preset_fail_status) ? RXDESKEW_EQ_PRESET_REQ_RESP : RXDESKEW_SET_CODE;
                end
                //---------------------------------------------------------------------------

                // for the partner handcheck.
                else if(rx_sb_msg_rcvd == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req)begin
                    send_sb_msg [0] <= (arc_iter_cnt != 4)? EXIT_DTC1_RESP : NO_MSG; // To avoid the sending EXIT_DTC1_RESP for the 5th time that may happend when the (current_state = RXDESKEW_END_REQ_RESP) && (arc_iter_cnt = 4)
                    // change current state to RXDESKEW_EXIT_DTC1_REQ_RESP
                    target_state <= (current_state == RXDESKEW_END_REQ_RESP)? ((arc_iter_cnt != 4)? RXDESKEW_EXIT_DTC1_REQ_RESP : TO_TRAINERROR) : current_state;
                end
                // for my die handcheck.
                else if(rx_sb_msg_rcvd == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp)begin
                    send_sb_msg [0] <= NO_MSG;
                    target_state <= RXDESKEW_ARC_COUNT;
                end
                //---------------------------------------------------------------------------

                // for the partner handcheck.
                else if(rx_sb_msg_rcvd == MBTRAIN_RXDESKEW_end_req)begin
                    send_sb_msg [0] <= (current_state == RXDESKEW_END_REQ_RESP)? END_RESP : send_sb_msg [0];
                    target_state    <= (current_state == RXDESKEW_END_REQ_RESP)? RXDESKEW_END_REQ_RESP : current_state;
                end
                // for my die handcheck.
                else if(rx_sb_msg_rcvd == MBTRAIN_RXDESKEW_end_resp)begin
                    send_sb_msg [0] <= NO_MSG;
                    target_state <= RXDESKEW_END_REQ_RESP;
                end
                //---------------------------------------------------------------------------
            end

            // Timer that counts from 31 to 0 after each message we send on the SB Tx.
            // This timer is used for counting the minimum seperation clocks between the message we are sending and the next SB message we will send.  
            if(sb_msg_valid_pulse || (send_timer != 0)) begin
                send_timer <= send_timer - 1'b1;
            end

            // To seperate between each 2 SB message 31 Clock cycle at least.
            if(send_timer != 0) begin
                if(rxdeskew_if.rx_sb_msg_valid) begin
                    rx_sb_msg_valid_r[0] <= 1'b1;
                    rx_sb_msg_r          <= rxdeskew_if.rx_sb_msg;
                    rx_msginfo_r[3:0]    <= rxdeskew_if.rx_msginfo[3:0];
                end
            end
            else begin // (timer == 0)
                rx_sb_msg_valid_r <= 1'b0;
            end
        end
    end
                                
endmodule
