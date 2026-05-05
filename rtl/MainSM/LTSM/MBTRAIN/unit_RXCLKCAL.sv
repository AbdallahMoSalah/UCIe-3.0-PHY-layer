// =============================================================================
// Module  : unit_RXCLKCAL
// Purpose : MBTRAIN.RXCLKCAL sub-state FSM.
//           Performs forwarded-clock calibration on the Rx path and, for
//           operating speeds > 32 GT/s, runs the IQ phase correction loop.
//           SB message payloads match UCIe Spec Rev 3.0 Chapter 7 Table 7-9.
// =============================================================================
module unit_RXCLKCAL #() (
        // ======================= //
        // General signals.        //
        // ======================= //
        internal_ltsm_if.rxclkcal_mp rxclkcal_if
    );
    // ============================================================================
    // Used SB Messages (explicit imports to document all messages used by this FSM)
    // ============================================================================
    import UCIe_pkg::MBTRAIN_RXCLKCAL_start_req        ; // Msg Number: d47
    import UCIe_pkg::MBTRAIN_RXCLKCAL_start_resp       ; // Msg Number: d48
    import UCIe_pkg::MBTRAIN_RXCLKCAL_TCKN_L_shift_req ; // Msg Number: d49
    import UCIe_pkg::MBTRAIN_RXCLKCAL_TCKN_L_shift_resp; // Msg Number: d50
    import UCIe_pkg::MBTRAIN_RXCLKCAL_done_req         ; // Msg Number: d51
    import UCIe_pkg::MBTRAIN_RXCLKCAL_done_resp        ; // Msg Number: d52
    import UCIe_pkg::TRAINERROR_Entry_req              ; // Msg Number: d107
    import UCIe_pkg::NOTHING                           ; // Msg Number: 8'hFF
    reg [4:0] phy_tx_tckn_shift_reg     ;
    reg       phy_tx_decrement_shift_reg;
    // ============================================================================
    // State Encoding
    // ============================================================================
    // (S0)  RXCLKCAL_IDLE           : Wait for rxclkcal_en to start the FSM.
    // (S1)  RXCLKCAL_START_REQ      : Send & Receive {MBTRAIN.RXCLKCAL start req}.
    //                                 Both dies keep Tx low during this handshake.
    // (S2)  RXCLKCAL_START_RESP     : Send & Receive {MBTRAIN.RXCLKCAL start resp}.
    //                                 Both dies now drive the forwarded clock active.
    // (S3)  RXCLKCAL_CALIBRATE      : Enable Rx clock lock & track lock circuits,
    //                                 then wait for the analog settle timer.
    //                                 -> If speed > 32 GT/s: enter IQ calibration loop.
    //                                 -> Else: skip IQ and go straight to DONE_REQ.
    // (S4)  IQ_IDLE                 : Enable phase detector, wait for settle timer
    //                                 before beginning an IQ shift iteration.
    // (S5)  IQ_TCKN_L_SHIFT_REQ     : Send & Receive {MBTRAIN.RXCLKCAL TCKN_L shift req}.
    //                                 We send our measured shift via MsgInfo[5:1] (magnitude)
    //                                 and MsgInfo[0] (direction); wait for the partner echo.
    // (S6)  IQ_APPLY_TCKN_L_SHIFT   : Apply the partner-commanded shift (from rx_msginfo)
    //                                 to our die's TCKN_L, then wait for the analog
    //                                 settle timer for the PHY to physically apply it.
    // (S7)  IQ_TCKN_L_SHIFT_RESP    : Send & Receive {MBTRAIN.RXCLKCAL TCKN_L shift resp}.
    //                                 MsgInfo[0] carries our out-of-range flag.
    //                                 If partner's MsgInfo[0] = 1 -> TRAINERROR.
    // (S8)  IQ_OBSERVE_CLK          : Re-enable phase detector, wait for settle
    //                                 timer so the PHY can measure the new phase.
    // (S9)  IQ_CHECK_CALIBRATION    : Check if our PHY reports the required residual
    //                                 shift (phy_rx_tckn_shift) is now 0.
    //                                 -> If 0 : IQ calibration converged, go to DONE_REQ.
    //                                 -> If !=0: loop back to IQ_TCKN_L_SHIFT_REQ.
    // (S10) RXCLKCAL_DONE_REQ       : Send & Receive {MBTRAIN.RXCLKCAL done req}.
    //                                 Also handles late IQ loop-back from partner.
    // (S11) RXCLKCAL_DONE_RESP      : Send & Receive {MBTRAIN.RXCLKCAL done resp}.
    // (S12) TO_RXCLKCAL_DONE        : Assert rxclkcal_done = 1, stay here while
    //                                 rxclkcal_en is held high (matching TXSELFCAL).
    // (S13) TO_TRAINERROR           : Assert trainerror_req = 1, stay until
    //                                 rxclkcal_en is de-asserted, then return to IDLE.
    localparam  RXCLKCAL_IDLE = 4'h0,  // (S0)
    RXCLKCAL_START_REQ        = 4'h1,  // (S1)
    RXCLKCAL_START_RESP       = 4'h2,  // (S2)
    RXCLKCAL_CALIBRATE        = 4'h3,  // (S3)
    IQ_IDLE                   = 4'h4,  // (S4)
    IQ_TCKN_L_SHIFT_REQ       = 4'h5,  // (S5)
    IQ_APPLY_TCKN_L_SHIFT     = 4'h6,  // (S6)
    IQ_TCKN_L_SHIFT_RESP      = 4'h7,  // (S7)
    IQ_OBSERVE_CLK            = 4'h8,  // (S8)
    IQ_CHECK_CALIBRATION      = 4'h9,  // (S9)
    RXCLKCAL_DONE_REQ         = 4'hA,  // (S10): Send & Receive {RXCLKCAL done req}.
    RXCLKCAL_DONE_RESP        = 4'hB,  // (S11): Send & Receive {RXCLKCAL done resp}.
    TO_RXCLKCAL_DONE          = 4'hC,  // (S12): rxclkcal_done = 1; wait for en de-assert.
    TO_TRAINERROR             = 4'hD;  // (S13): trainerror_req = 1; wait for en de-assert.
    reg [3:0] current_state, next_state;
    // To handle the case when the current_state == RXCLKCAL_DONE_REQ and the partner has sent {MBTRAIN.RXCLKCAL TCKN_L shift req} but we expect to receive {MBTRAIN.RXCLKCAL done req}.
    localparam TIMER_MAX_VALUE = 3;
    localparam TIMER_WIDTH     = $clog2(TIMER_MAX_VALUE + 1'b1);
    reg [TIMER_WIDTH-1:0] req_msg_sent_timer;
    reg                   req_msg_rcvd      ;
    // This signal prevents SB message glitches whenever the state changes.
    // It is set to 1 for exactly 1 lclk cycle on any state transition,
    // which is the same cycle the output always block drives new values.
    // By masking tx_sb_msg_valid during that cycle we ensure no partial/
    // incoherent message is forwarded to the SB module. (Pattern from TXSELFCAL)
    wire is_tx_sb_msg_valid = (current_state == next_state);
    // ============================================================================
    // Always Block 1 — Sequential Logic: current_state, previous_state
    // ============================================================================
    always_ff @(posedge rxclkcal_if.lclk or negedge rxclkcal_if.rst_n) begin
        if (!rxclkcal_if.rst_n) begin
            current_state  <= RXCLKCAL_IDLE;
        end else begin
            current_state  <= next_state;
        end
    end
    // ============================================================================
    // Always Block 2 — Combinational Logic: next_state
    // ============================================================================
    always_comb begin
        // Global error override: any 8 ms timeout or partner {TRAINERROR Entry req}
        // immediately forces transition to TO_TRAINERROR, regardless of the current
        // FSM state (the per-state cases below are only evaluated when no error).
        if ( rxclkcal_if.timeout_8ms_occured | (rxclkcal_if.rx_sb_msg == TRAINERROR_Entry_req && rxclkcal_if.rx_sb_msg_valid == 1'b1) ) begin
            // (S13) — Force TRAINERROR on timeout or remote error request.
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                // -------------------------------------------------------------------
                // (S0) IDLE: Wait for the MBTRAIN controller to enable this sub-state.
                // -------------------------------------------------------------------
                RXCLKCAL_IDLE: begin
                    if (rxclkcal_if.rxclkcal_en) next_state = RXCLKCAL_START_REQ;
                    else                         next_state = RXCLKCAL_IDLE     ;
                end
                // -------------------------------------------------------------------
                // (S1) Both dies send the start request and wait to receive the same
                //      message from the partner. All Tx lanes are driven Low.
                // -------------------------------------------------------------------
                RXCLKCAL_START_REQ: begin
                    if (rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_start_req && rxclkcal_if.rx_sb_msg_valid == 1'b1)
                        next_state = RXCLKCAL_START_RESP;
                    else
                        next_state = RXCLKCAL_START_REQ;
                end
                // -------------------------------------------------------------------
                // (S2) Both dies drive the forwarded clock active, send the start
                //      response, and wait to receive the same response.
                // -------------------------------------------------------------------
                RXCLKCAL_START_RESP: begin
                    if (rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_start_resp && rxclkcal_if.rx_sb_msg_valid == 1'b1)
                        next_state = RXCLKCAL_CALIBRATE;
                    else
                        next_state = RXCLKCAL_START_RESP;
                end
                // -------------------------------------------------------------------
                // (S3) Enable Rx clock & track lock circuits, wait for settle timer.
                //      Decision: speed > 32 GT/s requires IQ calibration loop.
                //      phy_negotiated_speed encoding: 0h=4GT/s, 1h=8GT/s, 2h=12GT/s, 3h=16GT/s, 4h=24GT/s, 5h=32GT/s, 6h=48GT/s, 7h=64GT/s
                //      Any speed > 32 GT/s (i.e., phy_negotiated_speed > 5) needs IQ.
                // -------------------------------------------------------------------
                RXCLKCAL_CALIBRATE: begin
                    if (rxclkcal_if.analog_settle_time_done) begin
                        if (rxclkcal_if.phy_negotiated_speed > 3'd5) // speed > 32 GT/s
                            next_state = IQ_IDLE;
                        else
                            next_state = RXCLKCAL_DONE_REQ;
                    end else begin
                        next_state = RXCLKCAL_CALIBRATE;
                    end
                end
                // -------------------------------------------------------------------
                // (S4) Activate phase detector and allow it to settle before the
                //      first (or next) IQ shift iteration.
                // -------------------------------------------------------------------
                IQ_IDLE: begin
                    if (rxclkcal_if.analog_settle_time_done) next_state = IQ_TCKN_L_SHIFT_REQ;
                    else                                      next_state = IQ_IDLE;
                end
                // -------------------------------------------------------------------
                // (S5) Send & Receive {MBTRAIN.RXCLKCAL TCKN_L shift req}.
                //      MsgInfo[5:1] = phy_rx_tckn_shift   (magnitude, step = 1/64 UI)
                //      MsgInfo[0]   = phy_rx_decrement_shift (1=decrement, 0=increment)
                //      Wait for the partner to echo the same message back.
                // -------------------------------------------------------------------
                IQ_TCKN_L_SHIFT_REQ: begin
                    if ((rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_TCKN_L_shift_req && rxclkcal_if.rx_sb_msg_valid == 1'b1) ||
                            (req_msg_rcvd && req_msg_sent_timer == TIMER_MAX_VALUE)) // To handle the case when the current_state == IQ_TCKN_L_SHIFT_REQ and the partner has sent {MBTRAIN.RXCLKCAL TCKN_L shift req} but we haven't received it yet.
                        next_state = IQ_APPLY_TCKN_L_SHIFT;
                    else
                        next_state = IQ_TCKN_L_SHIFT_REQ;
                end
                // -------------------------------------------------------------------
                // (S6) Apply the shift value that the partner commanded (received in
                //      rx_msginfo during S5), then wait for the analog settle timer
                //      so the analog circuits stabilise after the shift.
                // -------------------------------------------------------------------
                IQ_APPLY_TCKN_L_SHIFT: begin
                    if (rxclkcal_if.analog_settle_time_done) next_state = IQ_TCKN_L_SHIFT_RESP;
                    else                                     next_state = IQ_APPLY_TCKN_L_SHIFT;
                end
                // -------------------------------------------------------------------
                // (S7) Send and receive the shift response. The response MsgInfo
                //      carries an out-of-range flag. If our partner reports that our
                //      commanded shift pushed it out of range -> TRAINERROR.
                // -------------------------------------------------------------------
                IQ_TCKN_L_SHIFT_RESP: begin
                    if (rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_TCKN_L_shift_resp && rxclkcal_if.rx_sb_msg_valid == 1'b1) begin
                        // rx_msginfo[0]: out-of-range flag from partner die.
                        if (rxclkcal_if.rx_msginfo[0] == 1'b1)
                            next_state = TO_TRAINERROR; // Partner shift exceeded hardware limits.
                        else
                            next_state = IQ_OBSERVE_CLK;
                    end else begin
                        next_state = IQ_TCKN_L_SHIFT_RESP;
                    end
                end
                // -------------------------------------------------------------------
                // (S8) Re-enable the phase detector and let it observe the clock after
                //      the shift has been applied. Wait for settle timer.
                // -------------------------------------------------------------------
                IQ_OBSERVE_CLK: begin
                    if (rxclkcal_if.analog_settle_time_done) next_state = IQ_CHECK_CALIBRATION;
                    else                                     next_state = IQ_OBSERVE_CLK;
                end
                // -------------------------------------------------------------------
                // (S9) Check convergence: the PHY reports the residual shift that
                //      our die's TCKN_L still needs (phy_rx_tckn_shift).
                //      If it is 0, the IQ phase is calibrated. Otherwise loop.
                // -------------------------------------------------------------------
                IQ_CHECK_CALIBRATION: begin
                    // Note here are 2 points:
                    //       1) we confirm the partner final clock-to-track calibration.
                    //       2) but we didn't confirm if our calibration is good or not.
                    // So, for point (1) we will apply check:
                    //      if (rxclkcal_if.phy_rx_tckn_shift == 5'd0).
                    // and for point (2) we will consider it is good and take the go back decision based on the next received SB message.
                    // that means that we can go to the next state "RXCLKCAL_DONE_REQ" then receive the SB Msg "MBTRAIN_RXCLKCAL_TCKN_L_shift_req"
                    // to go back to repeat the clock-to-track calibration loop:
                    //      if (rx_sb_msg = "MBTRAIN_RXCLKCAL_TCKN_L_shift_req") -> IQ_TCKN_L_SHIFT_REQ.
                    //      if (rx_sb_msg = "MBTRAIN_RXCLKCAL_done_req") -> no problem and continue your flow.
                    if (rxclkcal_if.phy_rx_tckn_shift == 5'd0)
                        next_state = RXCLKCAL_DONE_REQ; // Convergence achieved.
                    else
                        next_state = IQ_TCKN_L_SHIFT_REQ; // Loop back for another iteration.
                end
                // -------------------------------------------------------------------
                // (S10) Send & Receive {MBTRAIN.RXCLKCAL done req}.
                //       The partner may still require another IQ iteration; if it sends
                //       {TCKN_L shift req} instead of done_req, loop back to S5.
                // -------------------------------------------------------------------
                RXCLKCAL_DONE_REQ: begin
                    if (rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_done_req && rxclkcal_if.rx_sb_msg_valid == 1'b1)
                        next_state = TO_RXCLKCAL_DONE;
                    else if (rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_TCKN_L_shift_req && rxclkcal_if.rx_sb_msg_valid == 1'b1)
                        next_state = IQ_TCKN_L_SHIFT_REQ; // Partner needs another IQ iteration.
                    else
                        next_state = RXCLKCAL_DONE_REQ;
                end
                // -------------------------------------------------------------------
                // (S11) Send & Receive {MBTRAIN.RXCLKCAL done resp}.
                //       Final handshake: once received, move to the done terminal state.
                // -------------------------------------------------------------------
                RXCLKCAL_DONE_RESP: begin
                    if (rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_done_resp && rxclkcal_if.rx_sb_msg_valid == 1'b1)
                        next_state = TO_RXCLKCAL_DONE;
                    else
                        next_state = RXCLKCAL_DONE_RESP;
                end
                // -------------------------------------------------------------------
                // (S12) RXCLKCAL complete. Assert rxclkcal_done and stay here while
                //       the MBTRAIN controller keeps rxclkcal_en asserted. Once it
                //       de-asserts en, go back to IDLE (mirrors TXSELFCAL pattern).
                // -------------------------------------------------------------------
                TO_RXCLKCAL_DONE: begin
                    next_state = (rxclkcal_if.rxclkcal_en) ? TO_RXCLKCAL_DONE : RXCLKCAL_IDLE;
                end
                // -------------------------------------------------------------------
                // (S13) TRAINERROR: Assert trainerror_req. Stay here while
                //       rxclkcal_en is held high; return to IDLE once de-asserted.
                // -------------------------------------------------------------------
                TO_TRAINERROR: begin
                    next_state = (rxclkcal_if.rxclkcal_en) ? TO_TRAINERROR : RXCLKCAL_IDLE;
                end
                default: begin
                    // Illegal encoding: treat as TRAINERROR until rxclkcal_en clears.
                    next_state = (rxclkcal_if.rxclkcal_en) ? TO_TRAINERROR : RXCLKCAL_IDLE;
                end
            endcase
        end
    end
    // ============================================================================
    // Always Block 3 — Combinational Logic: Output Values
    // ============================================================================
    always_comb begin
        //==========================================================================//
        //              Default values for outputs (to avoid latches)               //
        //==========================================================================//
        //==========================
        // LTSM -> LTSM signals:
        //==========================
        rxclkcal_if.rxclkcal_done = 1'b0;
        rxclkcal_if.trainerror_req = 1'b0;
        //==========================
        // Timers:
        //==========================
        rxclkcal_if.timeout_timer_en       = 1'b1; // 8ms timer runs by default in all active states.
        rxclkcal_if.analog_settle_timer_en = 1'b0;
        //=========================
        // MB signals: (Mainband)
        //=========================
        // Lane Behavior Control defaults for this sub-state:
        //   Tx data, valid, and track lanes are driven Low (clock is not yet active).
        //   Rx clock and track lanes are disabled until we start the calibration.
        rxclkcal_if.mb_tx_clk_lane_sel  = 2'b00; // 00b: Low (Tx Logical Clock Lane), 01b: active (Tx Logical Clock Lane), 1xb: Tri-state (Tx Logical Clock Lane).
        rxclkcal_if.mb_tx_data_lane_sel = 2'b00; // 00b: Low (Tx Logical Data Lanes), 01b: active (Tx Logical Data Lanes), 1xb: Tri-state (Tx Logical Data Lanes).
        rxclkcal_if.mb_tx_val_lane_sel  = 2'b00; // 00b: Low (Tx Logical Valid Lane), 01b: active (Tx Logical Valid Lane), 1xb: Tri-state (Tx Logical Valid Lane).
        rxclkcal_if.mb_tx_trk_lane_sel  = 2'b00; // 00b: Low (Tx Logical Track Lane), 01b: active (Tx Logical Track Lane), 1xb: Tri-state (Tx Logical Track Lane).
        rxclkcal_if.mb_rx_clk_lane_sel  = 1'b0 ; // 0b: Disabled (Rx Logical Clock Lane).
        rxclkcal_if.mb_rx_data_lane_sel = 1'b0 ; // 0b: Disabled (Rx Logical Data Lanes).
        rxclkcal_if.mb_rx_val_lane_sel  = 1'b0 ; // 0b: Disabled (Rx Logical Valid Lane).
        rxclkcal_if.mb_rx_trk_lane_sel  = 1'b0 ; // 0b: Disabled (Rx Logical Track Lane).
        // Setting the pattern configeration for the pattern generator.
        rxclkcal_if.mb_tx_pattern_en      = 1'b0  ; // Enable pattern generator and send the clock immediately.
        rxclkcal_if.mb_tx_pattern_setup   = 3'b100; // Choose "Clock pattern" to send when we enable the pattern generator.
        rxclkcal_if.mb_tx_clk_pattern_sel = 2'd3  ; // Choose clock type: "Clk Mode 2".
        //=========================
        // PHY Rx/Tx Analog Controls:
        //=========================
        rxclkcal_if.phy_rx_clock_lock_en     = 1'b0;  // Rx clock lock circuit disabled by default.
        rxclkcal_if.phy_rx_track_lock_en     = 1'b0;  // Rx track lock circuit disabled by default.
        rxclkcal_if.phy_rx_phase_detector_en = 1'b0;  // Phase detector disabled by default.
        rxclkcal_if.phy_tx_tckn_shift_en     = 1'b0;  // TCKN_L shift circuit disabled by default.
        rxclkcal_if.phy_tx_tckn_shift        = phy_tx_tckn_shift_reg     ; // No shift applied by default.
        rxclkcal_if.phy_tx_decrement_shift   = phy_tx_decrement_shift_reg; // Default shift direction: later (0b).
        //============================
        // SB signals: (Sideband)
        //============================
        // For SB TX:
        rxclkcal_if.tx_sb_msg_valid = 1'b0   ; // No message valid by default.
        rxclkcal_if.tx_sb_msg       = NOTHING; // No message to send by default.
        rxclkcal_if.tx_msginfo      = 16'h0  ; // MsgInfo field is 0 by default.
        rxclkcal_if.tx_data_field   = 64'h0  ; // Data field is 0 by default.
        case (current_state)
            // -------------------------------------------------------------------
            // (S0) IDLE state: Timer is off; FSM is waiting.
            // -------------------------------------------------------------------
            RXCLKCAL_IDLE: begin
                rxclkcal_if.timeout_timer_en   = 1'b0 ; // No timeout while idle.
                // Tx lanes: All Low while clock is not yet forwarded.
                rxclkcal_if.mb_tx_clk_lane_sel  = 2'b00; // Low.
                rxclkcal_if.mb_tx_data_lane_sel = 2'b00; // Low.
                rxclkcal_if.mb_tx_val_lane_sel  = 2'b00; // Low.
                rxclkcal_if.mb_tx_trk_lane_sel  = 2'b00; // Low.
                rxclkcal_if.mb_rx_clk_lane_sel  = 1'b0 ; // disable.
                rxclkcal_if.mb_rx_data_lane_sel = 1'b0 ; // disable.
                rxclkcal_if.mb_rx_val_lane_sel  = 1'b0 ; // disable.
                rxclkcal_if.mb_rx_trk_lane_sel  = 1'b0 ; // disable.
            end
            // -------------------------------------------------------------------
            // (S1) Send & Receive {MBTRAIN.RXCLKCAL start req}:
            //   - All Tx lanes are Low: we are not yet forwarding the clock.
            //   - Continuously send the start_req until we receive the echo.
            // -------------------------------------------------------------------
            RXCLKCAL_START_REQ: begin
                // Tx lanes: All Low while clock is not yet forwarded.
                rxclkcal_if.mb_tx_clk_lane_sel  = 2'b00; // Low.
                rxclkcal_if.mb_tx_data_lane_sel = 2'b00; // Low.
                rxclkcal_if.mb_tx_val_lane_sel  = 2'b00; // Low.
                rxclkcal_if.mb_tx_trk_lane_sel  = 2'b00; // Low.
                rxclkcal_if.mb_rx_clk_lane_sel  = 1'b1; // enabled.
                rxclkcal_if.mb_rx_data_lane_sel = 1'b0; // disable.
                rxclkcal_if.mb_rx_val_lane_sel  = 1'b0; // disable.
                rxclkcal_if.mb_rx_trk_lane_sel  = 1'b1; // enabled.
                // SB:
                rxclkcal_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)         ; // Send request.
                rxclkcal_if.tx_sb_msg       = MBTRAIN_RXCLKCAL_start_req  ; // Message code.
            end
            // -------------------------------------------------------------------
            // (S2) Send & Receive {MBTRAIN.RXCLKCAL start resp}:
            //   - Clock and Track Tx lanes go Active: forwarded clock is now running.
            //   - Data and Valid Tx remain Low (no data is sent yet).
            //   - Rx clock and track lanes remain disabled until RXCLKCAL_CALIBRATE.
            // -------------------------------------------------------------------
            RXCLKCAL_START_RESP: begin
                // Tx lanes: Clock and Track now Active for forwarding.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01; // 01b: Active (Tx Logical Clock Lane).
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01; // 01b: Active (Tx Logical Track Lane).
                // Enable the pattern generator.
                rxclkcal_if.mb_tx_pattern_en      = 1'b1  ; // Enable pattern generator and send the clock immediately.
                // SB:
                rxclkcal_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)         ; // Send response.
                rxclkcal_if.tx_sb_msg       = MBTRAIN_RXCLKCAL_start_resp ; // Message code.
            end
            // -------------------------------------------------------------------
            // (S3) Calibrate: Enable Rx clock & track lock, wait for settle timer.
            //   - Rx clock and track lanes are enabled so the analog circuits can
            //     acquire and lock to the incoming forwarded clock.
            //   - phy_rx_clock_lock_en and phy_rx_track_lock_en instruct the PHY's
            //     analog PLL/DLL to attempt lock.
            //   - Tx clock and track remain Active (we continue forwarding the clock
            //     so the partner can also calibrate its Rx).
            // -------------------------------------------------------------------
            RXCLKCAL_CALIBRATE: begin
                // Tx: keep forwarding.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01; // Active.
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01; // Active.
                // Enable pattern generator.
                rxclkcal_if.mb_tx_pattern_en = 1'b1; // Enable pattern generator and send the clock immediately.
                // PHY: instruct analog circuits to lock.
                rxclkcal_if.phy_rx_clock_lock_en = 1'b1;  // Rx clock lock circuit disabled by default. Enable it now.
                rxclkcal_if.phy_rx_track_lock_en = 1'b1;  // Rx track lock circuit disabled by default. Enable it now.
                // rxclkcal_if.phy_rx_phase_detector_en = 1'b0;  // Phase detector enable signal: 1'b0(default value): disable; 1'b1: enable.
                // rxclkcal_if.phy_tx_tckn_shift_en     = 1'b0;  // TCKN_L shift   enable signal: 1'b0(default value): disable; 1'b1: enable.
                // Timer: wait for analog circuits to settle and lock.
                rxclkcal_if.analog_settle_timer_en = 1'b1;
            end
            // -------------------------------------------------------------------
            // (S4) IQ Idle: Activate phase detector and wait for it to settle before
            //   the first measurement. Rx and Tx lanes stay as in RXCLKCAL_CALIBRATE.
            // -------------------------------------------------------------------
            IQ_IDLE: begin
                // Tx: continue forwarding.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01; // Active.
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01; // Active.
                // Enable pattern generator.
                rxclkcal_if.mb_tx_pattern_en         = 1'b1  ; // Enable pattern generator and send the clock immediately.
                // PHY: keep lock circuits on and turn on phase detector.
                rxclkcal_if.phy_rx_clock_lock_en     = 1'b1;  // Rx clock lock circuit disabled by default. Enable it now.
                rxclkcal_if.phy_rx_track_lock_en     = 1'b1;  // Rx track lock circuit disabled by default. Enable it now.
                rxclkcal_if.phy_rx_phase_detector_en = 1'b1;  // Phase detector enable signal: 1'b0(default value): disable; 1'b1: enable.
                // rxclkcal_if.phy_tx_tckn_shift_en     = 1'b0;  // TCKN_L shift   enable signal: 1'b0(default value): disable; 1'b1: enable.
                // Timer: wait for the phase detector to stabilise.
                rxclkcal_if.analog_settle_timer_en = 1'b1;
            end
            // -------------------------------------------------------------------
            // (S5) IQ TCKN_L shift request:
            //   - Phase detector is turned OFF (measurement complete for this iter).
            //   - We send and receive: {MBTRAIN.RXCLKCAL TCKN_L shift req}.
            //   - We send the shift values our PHY measured to the partner via SB.
            //   - MsgInfo layout (per UCIe spec, Chapter 7 Table 7-9):
            //       [5:1] = phy_rx_tckn_shift  (shift magnitude, 0..12)
            //       [0]   = phy_rx_decrement_shift (1=decrement/earlier, 0=increment/later)
            //   - We wait for the partner to echo the same message back.
            // -------------------------------------------------------------------
            IQ_TCKN_L_SHIFT_REQ: begin
                // Tx: continue forwarding.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01;
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01;
                // Enable pattern generator.
                rxclkcal_if.mb_tx_pattern_en = 1'b1  ; // Enable pattern generator and send the clock immediately.
                // PHY: lock circuits ON, phase detector OFF (observation done).
                rxclkcal_if.phy_rx_clock_lock_en     = 1'b1;  // Rx clock lock circuit disabled by default. Enable it now.
                rxclkcal_if.phy_rx_track_lock_en     = 1'b1;  // Rx track lock circuit disabled by default. Enable it now.
                // rxclkcal_if.phy_rx_phase_detector_en = 1'b0;  // Phase detector enable signal: 1'b0(default value): disable; 1'b1: enable.
                // rxclkcal_if.phy_tx_tckn_shift_en     = 1'b0;  // TCKN_L shift   enable signal: 1'b0(default value): disable; 1'b1: enable.
                // SB: send shift request with our measured shift payload.
                rxclkcal_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)              ; // Mask for 1 cycle after state entry.
                rxclkcal_if.tx_sb_msg       = MBTRAIN_RXCLKCAL_TCKN_L_shift_req; // Message code.
                rxclkcal_if.tx_msginfo      = {10'h0,
                    rxclkcal_if.phy_rx_tckn_shift      , // [5:1]: shift magnitude.
                    rxclkcal_if.phy_rx_decrement_shift}; // [0]: shift direction.
            end
            // -------------------------------------------------------------------
            // (S6) Apply the TCKN_L shift commanded by the partner:
            //   - The partner's required shift was received in the MsgInfo of
            //     the TCKN_L shift req message that we echoed in S5.
            //   - rx_msginfo[5:1] : shift magnitude our die should apply.
            //   - rx_msginfo[0]   : direction (1=decrement/earlier, 0=increment).
            //   - phy_tx_tckn_shift_en activates the shift circuit in the PHY.
            //   - We wait for the analog settle timer so the PHY can physically
            //     apply the shift and allow the lanes to re-stabilise.
            // -------------------------------------------------------------------
            IQ_APPLY_TCKN_L_SHIFT: begin
                // Tx: continue forwarding.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01;
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01;
                // Enable pattern generator.
                rxclkcal_if.mb_tx_pattern_en = 1'b1  ; // Enable pattern generator and send the clock immediately.
                // PHY: keep lock circuits ON.
                // PHY: Apply the shift commanded by the partner (from latest rx_msginfo).
                rxclkcal_if.phy_rx_clock_lock_en     = 1'b1;
                rxclkcal_if.phy_rx_track_lock_en     = 1'b1;
                rxclkcal_if.phy_rx_phase_detector_en = 1'b0; // Phase detector enable signal: 1'b0(default value): disable; 1'b1: enable.
                rxclkcal_if.phy_tx_tckn_shift_en     = 1'b1; // Activate shift circuit.
                // Timer: wait for shift to settle before measuring the new phase.
                rxclkcal_if.analog_settle_timer_en = 1'b1;
            end
            // -------------------------------------------------------------------
            // (S7) IQ TCKN_L shift response:
            //   - We send and receive: {MBTRAIN.RXCLKCAL TCKN_L shift resp}.
            //   - We send our out-of-range flag back to the partner.
            //   - tx_msginfo[0] = phy_tx_tckn_shift_out_of_range
            //     (1 = the shift the partner asked exceeded our hardware limit).
            //   - We wait for the partner to echo the same message back.
            //   - If the partner's flag indicates out-of-range -> TRAINERROR.
            // -------------------------------------------------------------------
            IQ_TCKN_L_SHIFT_RESP: begin
                // Tx: continue forwarding.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01;
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01;
                // Enable pattern generator.
                rxclkcal_if.mb_tx_pattern_en = 1'b1  ; // Enable pattern generator and send the clock immediately.
                // PHY: keep lock circuits ON.
                rxclkcal_if.phy_rx_clock_lock_en     = 1'b1;  // Rx clock lock circuit disabled by default. Enable it now.
                rxclkcal_if.phy_rx_track_lock_en     = 1'b1;  // Rx track lock circuit disabled by default. Enable it now.
                // rxclkcal_if.phy_rx_phase_detector_en = 1'b0;  // Phase detector enable signal: 1'b0(default value): disable; 1'b1: enable.
                // rxclkcal_if.phy_tx_tckn_shift_en     = 1'b0;  // TCKN_L shift   enable signal: 1'b0(default value): disable; 1'b1: enable.
                // SB: send shift response with our out-of-range status.
                rxclkcal_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)                                                       ; // Mask for 1 cycle after state entry.
                rxclkcal_if.tx_sb_msg       = MBTRAIN_RXCLKCAL_TCKN_L_shift_resp                                        ; // Message code.
                rxclkcal_if.tx_msginfo      = {15'h0, rxclkcal_if.phy_tx_tckn_shift_out_of_range}                      ; // [0]: our out-of-range flag.
            end
            // -------------------------------------------------------------------
            // (S8) Observe clock after shift: re-activate phase detector and wait
            //   for the settle timer so the PHY measures the updated phase offset.
            // -------------------------------------------------------------------
            IQ_OBSERVE_CLK: begin
                // Tx: continue forwarding.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01;
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01;
                // Enable pattern generator.
                rxclkcal_if.mb_tx_pattern_en = 1'b1  ; // Enable pattern generator and send the clock immediately.
                // PHY: re-enable phase detector to measure the new residual offset.
                rxclkcal_if.phy_rx_clock_lock_en     = 1'b1;
                rxclkcal_if.phy_rx_track_lock_en     = 1'b1;
                rxclkcal_if.phy_rx_phase_detector_en = 1'b1;  // Measure the new phase after shift.
                // rxclkcal_if.phy_tx_tckn_shift_en     = 1'b0;  // TCKN_L shift   enable signal: 1'b0(default value): disable; 1'b1: enable.
                // Timer: wait for the observation period.
                rxclkcal_if.analog_settle_timer_en = 1'b1;
            end
            // -------------------------------------------------------------------
            // (S9) Check calibration convergence:
            //   - Lane and PHY signals remain active (combinational, no SB action).
            //   - The next-state logic (always block 2) reads phy_rx_tckn_shift and
            //     decides whether to loop or proceed to DONE_REQ.
            //   - No new output signals are needed here beyond what the defaults
            //     and the clock-forwarding group already provide.
            // -------------------------------------------------------------------
            IQ_CHECK_CALIBRATION: begin
                // Tx: continue forwarding.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01;
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01;
                // Enable pattern generator.
                rxclkcal_if.mb_tx_pattern_en = 1'b1  ; // Enable pattern generator and send the clock immediately.
                // PHY: lock circuits ON.
                rxclkcal_if.phy_rx_clock_lock_en = 1'b1;
                rxclkcal_if.phy_rx_track_lock_en = 1'b1;
                // rxclkcal_if.phy_rx_phase_detector_en = 1'b0;  // Phase detector enable signal: 1'b0(default value): disable; 1'b1: enable.
                // rxclkcal_if.phy_tx_tckn_shift_en     = 1'b0;  // TCKN_L shift   enable signal: 1'b0(default value): disable; 1'b1: enable.
                // (No SB activity in this state; next-state logic handles the exit.)
            end
            // -------------------------------------------------------------------
            // (S10) Send & Receive {MBTRAIN.RXCLKCAL done req}:
            //   - Clock is still forwarded; partner stops forwarding only after
            //     receiving done_req (UCIe Spec §4.5.3.4.5 Step 3).
            //   - Rx clock & track lanes remain enabled so we can still receive.
            //   - Next-state logic also handles the case where the partner sends
            //     another {TCKN_L shift req} instead (late IQ loop-back).
            // -------------------------------------------------------------------
            RXCLKCAL_DONE_REQ: begin
                // Tx: continue forwarding the clock while done handshake is pending.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01; // Active.
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01; // Active.
                // Rx: keep receivers active until the final handshake completes.
                rxclkcal_if.mb_rx_clk_lane_sel  = 1'b1; // Enabled.
                rxclkcal_if.mb_rx_trk_lane_sel  = 1'b1; // Enabled.
                // Enable pattern generator.
                rxclkcal_if.mb_tx_pattern_en = 1'b1; // Keep forwarding the clock pattern.
                // PHY: keep lock circuits ON until the done resp is received.
                rxclkcal_if.phy_rx_clock_lock_en = 1'b1;
                rxclkcal_if.phy_rx_track_lock_en = 1'b1;
                // rxclkcal_if.phy_rx_phase_detector_en = 1'b0;  // OFF by default.
                // rxclkcal_if.phy_tx_tckn_shift_en     = 1'b0;  // OFF by default.
                // SB: send done request.
                rxclkcal_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)      ; // Mask for 1 cycle after state entry.
                rxclkcal_if.tx_sb_msg       = MBTRAIN_RXCLKCAL_done_req; // Message code (MsgInfo = 0000h).
            end
            // -------------------------------------------------------------------
            // (S11) Send & Receive {MBTRAIN.RXCLKCAL done resp}:
            //   - Per UCIe Spec §4.5.3.4.5 Step 3: partner stops forwarding the
            //     clock upon receiving done_req; we respond with done_resp.
            //   - Tx clock & track can remain active while we send the response
            //     (the pattern generator is still running to keep the clock clean).
            // -------------------------------------------------------------------
            RXCLKCAL_DONE_RESP: begin
                // Tx: continue forwarding while sending the done response.
                rxclkcal_if.mb_tx_clk_lane_sel = 2'b01; // Active.
                rxclkcal_if.mb_tx_trk_lane_sel = 2'b01; // Active.
                // SB: send done response.
                rxclkcal_if.tx_sb_msg_valid = (is_tx_sb_msg_valid)       ; // Mask for 1 cycle after state entry.
                rxclkcal_if.tx_sb_msg       = MBTRAIN_RXCLKCAL_done_resp; // Message code (MsgInfo = 0000h).
            end
            // -------------------------------------------------------------------
            // (S12) RXCLKCAL Done:
            //   - Assert rxclkcal_done = 1 to inform the MBTRAIN controller.
            //   - FSM stays here while rxclkcal_en is high (MBTRAIN holds it
            //     asserted until it acknowledges the done pulse).
            //   - Next-state logic returns to IDLE once en is de-asserted.
            //   - All Tx/Rx lanes hold the safe Low/disabled defaults from above.
            //   - Mirrors the TO_RXCLKCAL pattern in unit_TXSELFCAL.
            // -------------------------------------------------------------------
            TO_RXCLKCAL_DONE: begin
                rxclkcal_if.rxclkcal_done    = 1'b1; // Signal completion to MBTRAIN controller.
                rxclkcal_if.timeout_timer_en = 1'b0; // No more timeout monitoring needed.
            end
            // -------------------------------------------------------------------
            // (S13) TRAINERROR:
            //   - Assert rxclkcal_done = 1 to unblock the MBTRAIN controller.
            //   - Assert trainerror_req = 1 to request an LTSM TRAINERROR entry.
            //   - FSM stays here while rxclkcal_en is high; next-state logic
            //     returns to IDLE once the MBTRAIN controller de-asserts en.
            // -------------------------------------------------------------------
            TO_TRAINERROR: begin
                rxclkcal_if.rxclkcal_done    = 1'b1; // Unblock MBTRAIN controller.
                rxclkcal_if.trainerror_req   = 1'b1; // Request LTSM to enter TRAINERROR state.
                rxclkcal_if.timeout_timer_en = 1'b0; // Stop timeout monitor so timeout flag can clear.
            end
            default: begin
                // Default case: no outputs changed beyond the safe defaults above.
            end
        endcase
    end
    // ============================================================================
    // Always Block 4 — Sequential Logic: Partner Shift Latch
    // ============================================================================
    // Captures the partner's commanded shift values from the rx_msginfo field
    // of the {MBTRAIN.RXCLKCAL TCKN_L shift req} message received in S5.
    // These latched values feed the PHY shift controls in S6 (IQ_APPLY_TCKN_L_SHIFT)
    // via phy_tx_tckn_shift and phy_tx_decrement_shift (driven in Always Block 3).
    // Reset/IDLE clear the registers so each new RXCLKCAL run starts from 0.
    always @(posedge rxclkcal_if.lclk or negedge rxclkcal_if.rst_n) begin
        if (!rxclkcal_if.rst_n) begin
            phy_tx_tckn_shift_reg      <= 5'b0; // Reset: no shift pending.
            phy_tx_decrement_shift_reg <= 1'b0; // Reset: direction = increment.
        end
        else if (current_state == IQ_TCKN_L_SHIFT_REQ &&
                rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_TCKN_L_shift_req &&
                rxclkcal_if.rx_sb_msg_valid == 1'b1) begin
            // Latch partner-commanded shift from rx_msginfo (UCIe Table 7-9):
            phy_tx_tckn_shift_reg      <= rxclkcal_if.rx_msginfo[5:1]; // [5:1]: shift magnitude.
            phy_tx_decrement_shift_reg <= rxclkcal_if.rx_msginfo[0]  ; // [0]  : shift direction.
        end
        else if (current_state == RXCLKCAL_IDLE) begin
            phy_tx_tckn_shift_reg      <= 5'b0; // Clear on return to IDLE.
            phy_tx_decrement_shift_reg <= 1'b0;
        end
    end
    // -------------------------------------------------------------------
    // In (S10) RXCLKCAL_DONE_REQ: we send {MBTRAIN.RXCLKCAL done req} and
    //       suppose that we receive {MBTRAIN.RXCLKCAL done req} because of the sync.
    //       The partner may still require another IQ iteration and send {TCKN_L shift req}
    //       instead of done_req, so we loop back to (S5) IQ_TCKN_L_SHIFT_REQ in that case.
    //
    // Here is the problem: when we loop back to (S5) we will wait to receive the
    //       {TCKN_L shift req} SB Msg again which is impossible because we already received it.
    //       The {TCKN_L shift req} SB Msg has received but we didn't sent it yet.
    //       So, the solution is to use a flag to indicate that we received the {TCKN_L shift req}
    //       SB Msg and we are waiting to make sure the SB catches our req Msg correctly.
    // -------------------------------------------------------------------
    always @(posedge rxclkcal_if.lclk or negedge rxclkcal_if.rst_n) begin : TCKN_L_SHIFT_REQ_PROC
        if(!rxclkcal_if.rst_n) begin
            req_msg_rcvd       <= 1'b0               ; // Default: NOT received (flag is only set for late-IQ scenario)
            req_msg_sent_timer <= {TIMER_WIDTH{1'b0}};
        end
        else if(current_state == RXCLKCAL_DONE_REQ && (rxclkcal_if.rx_sb_msg_valid && rxclkcal_if.rx_sb_msg == MBTRAIN_RXCLKCAL_TCKN_L_shift_req)) begin
            // Late-IQ detected: partner sent TCKN_L_shift_req while we were in DONE_REQ.
            // Set the flag so that when we loop back to IQ_TCKN_L_SHIFT_REQ, we don't
            // wait for the partner echo (we already received it).
            req_msg_rcvd       <= 1'b1               ;
            req_msg_sent_timer <= {TIMER_WIDTH{1'b0}};
        end
        else if(current_state == IQ_TCKN_L_SHIFT_REQ) begin
            // Count up while in IQ_TCKN_L_SHIFT_REQ; when req_msg_rcvd is set and
            // timer reaches TIMER_MAX_VALUE, the next-state logic advances without
            // waiting for the partner echo.
            req_msg_sent_timer <= req_msg_sent_timer + 1'b1;
        end
        else begin
            // Clear in all other states so the flag doesn't carry over to the next
            // normal IQ iteration (which MUST wait for the partner echo).
            req_msg_rcvd       <= 1'b0;
            req_msg_sent_timer <= {TIMER_WIDTH{1'b0}};
        end
    end
endmodule
