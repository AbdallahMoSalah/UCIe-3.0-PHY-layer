// unit_RXDESKEW_partner.sv — MBTRAIN.RXDESKEW PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled RXDESKEW implementation.
//
// Role:
//   - Waits for Request SB messages from the Local (Initiator) die
//   - Sends Response SB messages back to the Local die
//   - Holds MB lanes in the correct posture while Local performs its deskew sweep
//   - Applies TX EQ presets on its own TX side when requested by Local
//   - Tracks the RXDESKEW→DTC1 arc counter on the Partner side (spec §4.5.3.4.10)
//   - Enters TRAINERROR when arc limit is exceeded or timeout/TRAINERROR req received
//
// Architecture: Single-FSM, WAIT → SEND pattern (exact mirror of the Local SEND → WAIT).
//   Each WAIT state polls rx_sb_msg until the expected request arrives.
//   Each SEND state asserts tx_sb_msg_valid for exactly 1 lclk cycle, then transitions.
//
// Spec Rules (§4.5.3.4.10):
//   1. On receiving {start req}             → respond with {start resp}
//   2. On receiving {EQ Preset req}:
//        - Valid encoding (0–5)  → apply preset on TX, send {EQ Preset resp} Success (MsgInfo[0]=0)
//        - Invalid encoding      → do NOT apply preset, send {EQ Preset resp} Fail (MsgInfo[0]=1)
//        Local may repeat step 2 multiple times.
//   3. On receiving {exit to DTC1 req}:
//        - arc_cnt < MAX_ARC_LIMIT (4) → send {exit to DTC1 resp}, go to DTC1 (arc consumed)
//        - arc_cnt >= MAX_ARC_LIMIT    → perform TRAINERROR handshake
//   4. On receiving {end req}              → send {end resp}, go to DTC2
//
// After {exit to DTC1 resp} is sent, any pending {end req} messages are discarded
// (this is handled implicitly: partner goes to TO_DTC1 immediately after SEND_EXIT_DTC1_RESP,
//  so it can never reach SEND_END_RESP after an arc).
//
// After the partner sends {exit to DTC1 resp} and arcs to DTC1, the arc counter is
// incremented exactly once in the dedicated RXDESKEW_PTR_DTC1_ARC_INC state (1-cycle)
// before entering the terminal RXDESKEW_PTR_TO_DTC1 state, for the same reason as the
// local module: the terminal state is held for many lclk cycles.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.RXDESKEW (Partner — Responder):
// +----------------------------------------------------+-----------+----------------------------------------+
// | Message Name                                       | Direction | MsgInfo & Data Field Details           |
// +----------------------------------------------------+-----------+----------------------------------------+
// | {MBTRAIN.RXDESKEW start req}                       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW start resp}                      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW EQ Preset req}                   | In  (RX)  | MsgInfo[2:0]: EQ preset code (0–5)     |
// |   (= MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_     |           |                                        |
// |      MBTRAIN_RXDESKEW_EQ_Preset_req)               |           |                                        |
// | {MBTRAIN.RXDESKEW EQ Preset resp}                  | Out (TX)  | MsgInfo[0]: 0=Success, 1=Fail          |
// |   (= MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_     |           |                                        |
// |      MBTRAIN_RXDESKEW_EQ_Preset_resp)              |           |                                        |
// | {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req}    | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 resp}   | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW end req}                         | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW end resp}                        | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {TRAINERROR entry req}                             | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0 (partner sends) |
// | {TRAINERROR entry req}                             | In  (RX)  | Received from Local → force TRAINERROR |
// +----------------------------------------------------+-----------+----------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.10 MBTRAIN.RXDESKEW
// Memory: target_implementation_technique/details_of_implementation/details_of_MBTRAIN/details_of_RXDESKEW.md
// Local:  target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/MBTRAIN/RXDESKEW/unit_RXDESKEW_local.sv

module unit_RXDESKEW_partner #(
        // Valid TX EQ preset range: 0–5 (6 presets per UCIe 3.0 Table 5-7).
        // Any preset index outside [0, MAX_VALID_PRESET] is rejected (Fail response).
        parameter int unsigned MAX_VALID_PRESET = 4'd5
    ) (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,               // LTSM clock domain. All FSM transitions synchronous.
        input  logic        rst_n,               // 0: Asynchronous reset → IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        rxdeskew_en          , // 0: Disable (→ IDLE immediately). 1: Enable/start sequence.
        input  logic        soft_rst_n           , // 0: Soft-reset active (all regs → defaults). 1: Normal.
        output logic        rxdeskew_done        , // 1: Sub-state completed; held until rxdeskew_en = 0.
        output logic        datatraincenter1_req , // 1: Arc to DTC1 requested (partner side).
        output logic        trainerror_req       , // 1: Fatal error — request TRAINERROR state.
        output logic        partner_sweep_en     , // 1: Enable partner RX_D2C_PT sweep. 0: Disable.
        // Unified Arc Counter Export:
        // Exposes the PARTNER-side DTC1 arc count to the LOCAL FSM on the same die.
        // The LOCAL FSM reads this to decide whether another arc is permitted before
        // sending {exit to DTC1 req}. Both FSMs on the same die share one physical
        // counter this way, eliminating the duplicate register in unit_RXDESKEW_local.
        //
        // Spec §4.5.3.4.10: "The UCIe Module is permitted to take the RXDESKEW to
        // DATATRAINCENTER1 arc a maximum of four times."  When LOCAL consults this
        // count, it is reading the same accumulated arc total that the PARTNER uses
        // to gate its responses — so the same limit is enforced consistently on both
        // sides from a single register.
        output logic [2:0]  partner_arc_cnt_out  , // Unified arc counter: same die LOCAL reads this.

        //=====================================//
        // Cross-die Coordination:             //
        //=====================================//
        // From the LOCAL FSM on THIS die. Tells the PARTNER whether the
        // LOCAL has committed to the DTC1 arc path (sent {exit to DTC1 req}).
        // When asserted, PARTNER MUST NOT send {end resp} to the other die's
        // {end req}, per spec §4.5.3.4.10.
        input  logic        local_exit_dtc1_active,
        input  logic        local_arc_taken,
        input  logic        local_end_active,

        //=====================================//
        // PHY TX EQ Preset Control:           //
        //=====================================//
        // The partner applies the TX EQ preset received in {EQ Preset req} to its own
        // TX PHY. This is a registered value (latched from rx_msginfo[2:0]).
        output logic [2:0]  phy_tx_eq_preset_ctrl, // EQ preset code applied to this die's TX (0–5).
        output logic        phy_tx_eq_preset_en  , // 1: Apply phy_tx_eq_preset_ctrl this cycle.

        //=====================================//
        // MB Lane Control Outputs:            //
        //=====================================//
        // While acting as Partner during the Local's sweep:
        //   - Data and Valid TX: held low   (partner does not transmit data during Local's sweep)
        //   - Track TX: always held low     (spec §4.5.3.4.10)
        //   - Clock TX: free-running if > 32 GT/s OR continuous clk mode; else held low
        //   - Clock, Data, Valid RX: enabled (partner receives training data from Local)
        //   - Track RX: disabled
        output logic [1:0]  mb_tx_clk_lane_sel  , // 00=Low, 01=Active (fwd clk), 10=Tri-state
        output logic [1:0]  mb_tx_data_lane_sel , // 00=Held Low (always in partner during sweep)
        output logic [1:0]  mb_tx_val_lane_sel  , // 00=Held Low (always in partner during sweep)
        output logic [1:0]  mb_tx_trk_lane_sel  , // 00=Always Held Low (spec)
        output logic        mb_rx_clk_lane_sel  , // 1=Enabled (clock RX always enabled per spec)
        output logic        mb_rx_data_lane_sel , // 1=Enabled (data RX enabled per spec)
        output logic        mb_rx_val_lane_sel  , // 1=Enabled (valid RX enabled per spec)
        output logic        mb_rx_trk_lane_sel  , // 0=Disabled (track RX not used)

        //=====================================//
        // Speed and Clock Mode Inputs:        //
        //=====================================//
        input  logic        is_high_speed        , // 1 = speed > 32 GT/s
        input  logic        is_continuous_clk_mode, // 1 = partner advertised continuous clock mode

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // SB TX:
        output logic        tx_sb_msg_valid      , // Asserted for exactly 1 lclk cycle to transmit a SB msg.
        output logic [7:0]  tx_sb_msg            , // MsgCode to transmit.
        output logic [15:0] tx_msginfo           , // MsgInfo payload.
        output logic [63:0] tx_data_field        , // 64-bit data payload.

        // SB RX:
        input  logic        rx_sb_msg_valid      , // Pulse (1 lclk) when a valid SB msg has been received.
        input  logic [7:0]  rx_sb_msg            , // Received MsgCode.
        input  logic [15:0] rx_msginfo           , // Received MsgInfo payload.
        input  logic [63:0] rx_data_field          // Received 64-bit data payload (unused here).
    );

    import UCIe_pkg::*;

    // =========================================================================
    // FSM State Encoding — WAIT → SEND pattern (mirror of Local SEND → WAIT)
    //
    // The partner has a simpler FSM than the Local:
    //   - It waits in WAIT_START_REQ for {start req}, sends {start resp}.
    //   - Then enters the MAIN WAIT loop (WAIT_SWEEP_OR_REQ) where it accepts
    //     any of: {EQ Preset req}, {exit to DTC1 req}, or {end req}.
    //   - Each received req causes a 1-cycle SEND state for the response.
    //   - Arc-related states mirror the Local's DTC1_ARC_INC pattern.
    // =========================================================================
    localparam [3:0]
    RXDESKEW_PTR_IDLE                = 4'd0,   // Wait for rxdeskew_en.
    RXDESKEW_PTR_WAIT_START_REQ      = 4'd1,   // Wait for {MBTRAIN.RXDESKEW start req}.
    RXDESKEW_PTR_SEND_START_RESP     = 4'd2,   // Assert {MBTRAIN.RXDESKEW start resp} for 1 cycle.
    RXDESKEW_PTR_WAIT_SWEEP_OR_REQ   = 4'd3,   // Main wait loop: handle {EQ Preset req},
    //   {exit to DTC1 req}, or {end req}.
    //   MB held in idle posture while Local sweeps.
    RXDESKEW_PTR_SEND_PRESET_RESP    = 4'd4,   // Assert {EQ Preset resp} SUCCESS (MsgInfo[0]=0) for 1 cycle.
    RXDESKEW_PTR_SEND_PRESET_FAIL    = 4'd5,   // Assert {EQ Preset resp} FAIL   (MsgInfo[0]=1) for 1 cycle.
    RXDESKEW_PTR_SEND_EXIT_DTC1_RESP = 4'd6,   // Assert {exit to DTC1 resp} for 1 cycle.
    RXDESKEW_PTR_DTC1_ARC_INC        = 4'd7,   // (1-cycle ONLY) Increment dtc1_arc_cnt exactly once → TO_DTC1.
    // CRITICAL: NOT done in TO_DTC1 (terminal, held many cycles).
    RXDESKEW_PTR_SEND_END_RESP       = 4'd8,   // Assert {MBTRAIN.RXDESKEW end resp} for 1 cycle.
    // NOTE: No SEND_TRAINERROR_REQ state. The {TRAINERROR entry req} message is sent
    //       exclusively by unit_TRAINERROR (external module). When arc limit is exceeded
    //       or timeout fires, this FSM transitions directly to TO_TRAINERROR.
    RXDESKEW_PTR_TO_DTC2             = 4'd9,   // Terminal: rxdeskew_done=1, exit to DTC2.
    RXDESKEW_PTR_TO_DTC1             = 4'd10,  // Terminal: datatraincenter1_req=1, arc to DTC1.
    RXDESKEW_PTR_TO_TRAINERROR       = 4'd11;  // Terminal: trainerror_req=1, TRAINERROR.

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [3:0] current_state, next_state;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    reg [2:0] dtc1_arc_cnt;        // Counts how many times we have sent {exit to DTC1 resp}.
    reg [3:0] rx_preset_code_r;    // EQ preset code latched from rx_msginfo[2:0] on receipt of {EQ Preset req}.
    reg       end_req_rcvd;

    // =========================================================================
    // Sequential: state register
    // Rule: rst_n (async) and is_ltsm_out_of_reset (sync) in SEPARATE branches.
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= RXDESKEW_PTR_IDLE;
        end
        else if (!soft_rst_n) begin
            // Soft reset: return to IDLE synchronously.
            current_state <= RXDESKEW_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // Combinational Next-State Logic
    //
    // Priority:
    //   1. HIGHEST: TRAINERROR conditions (timeout or received {TRAINERROR entry req})
    //   2. SECOND:  rxdeskew_en deasserted → immediate return to IDLE
    //   3. NORMAL:  per-state FSM transitions
    //
    // NOTE: TRAINERROR and rxdeskew_en checks are NOT applied in terminal states
    //       (TO_DTC2, TO_DTC1, TO_TRAINERROR) — those states already hold until
    //       rxdeskew_en deasserts and then go to IDLE via the rxdeskew_en check.
    //       The timeout/TRAINERROR override MUST cover all non-terminal states.
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        next_state = current_state; // Default: hold

        // ------------------------------------------------------------------
        // HIGHEST PRIORITY: TRAINERROR override.
        // Applies to all states except the terminal states (which already hold).
        // ------------------------------------------------------------------
        if ((rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) ||
                (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req && (dtc1_arc_cnt == 3'd4))) begin
            next_state = RXDESKEW_PTR_TO_TRAINERROR;
        end
        // ------------------------------------------------------------------
        // SECOND PRIORITY: rxdeskew_en deasserted → return to IDLE.
        // ------------------------------------------------------------------
        else if (!rxdeskew_en) begin
            next_state = RXDESKEW_PTR_IDLE;
        end
        // ------------------------------------------------------------------
        // NORMAL FSM TRANSITIONS (rxdeskew_en=1, no TRAINERROR)
        // ------------------------------------------------------------------
        else begin
            case (current_state)

                // -------------------------------------------------------
                // IDLE: Wait for rxdeskew_en assertion, then go to WAIT_START_REQ.
                // -------------------------------------------------------
                RXDESKEW_PTR_IDLE: begin
                    next_state = rxdeskew_en ? RXDESKEW_PTR_WAIT_START_REQ : RXDESKEW_PTR_IDLE;
                end

                // -------------------------------------------------------
                // WAIT_START_REQ:
                // Poll for {MBTRAIN.RXDESKEW start req} from Local die.
                // -------------------------------------------------------
                RXDESKEW_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_start_req) begin
                        next_state = RXDESKEW_PTR_SEND_START_RESP;
                    end
                end

                // -------------------------------------------------------
                // SEND_START_RESP:
                // tx_sb_msg_valid asserted for this 1-cycle state.
                // → Unconditionally move to WAIT_SWEEP_OR_REQ (main loop).
                // -------------------------------------------------------
                RXDESKEW_PTR_SEND_START_RESP: begin
                    next_state = RXDESKEW_PTR_WAIT_SWEEP_OR_REQ;
                end

                // -------------------------------------------------------
                // WAIT_SWEEP_OR_REQ (main loop):
                // Hold in MB-idle posture while Local performs its sweep.
                // Accept any of the three possible incoming messages:
                //
                //   {EQ Preset req}        → validate encoding:
                //                            - Valid (0–5): SEND_PRESET_RESP (success)
                //                            - Invalid    : SEND_PRESET_FAIL (fail)
                //                            After sending resp, return here for next req.
                //
                //   {exit to DTC1 req}     → check arc counter:
                //                            - Under limit (< 4): SEND_EXIT_DTC1_RESP
                //                            - At/over limit (≥4): SEND_TRAINERROR_REQ
                //                            (Partner NEVER responds with {end resp} after
                //                             transitioning out of this state via arc path —
                //                             the arc resp causes immediate TO_DTC1 transition)
                //
                //   {end req}              → check local_exit_dtc1_active:
                //                            - LOCAL arcing: DISCARD (spec §4.5.3.4.10 —
                //                              "the UCIe Module must not send {end resp}")
                //                            - LOCAL not arcing: SEND_END_RESP (normal DTC2)
                //
                // SPEC NOTE: Any other message is silently ignored (hold in this state).
                // -------------------------------------------------------
                RXDESKEW_PTR_WAIT_SWEEP_OR_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req) begin
                        // EQ Preset request: validate the preset code.
                        // Valid range per UCIe 3.0 Table 5-7: 0–5.
                        if (rx_msginfo[3:0] <= MAX_VALID_PRESET[3:0]) begin
                            next_state = RXDESKEW_PTR_SEND_PRESET_RESP; // Apply and respond Success
                        end
                        else begin
                            next_state = RXDESKEW_PTR_SEND_PRESET_FAIL; // Reject and respond Fail
                        end
                    end
                    else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req) begin
                        // DTC1 arc request: check arc counter against spec limit.
                        // NOTE: arc_cnt reflects arcs ALREADY sent; if it is < 4, we
                        //       may send one more (which will be counted in DTC1_ARC_INC).
                        if (dtc1_arc_cnt < 3'd4) begin
                            next_state = RXDESKEW_PTR_SEND_EXIT_DTC1_RESP;
                        end
                        else begin
                            // Arc limit exceeded (arc_cnt >= 4) → TRAINERROR directly.
                            // NOTE: {TRAINERROR entry req} is sent by unit_TRAINERROR,
                            // not by this module. We simply assert trainerror_req=1.
                            next_state = RXDESKEW_PTR_TO_TRAINERROR;
                        end
                    end
                    else if ((rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_end_req) || end_req_rcvd) begin
                        // Cross-die coordination check (§4.5.3.4.10):
                        // If our LOCAL has committed to the DTC1 arc path,
                        // we MUST NOT send {end resp}. The {end req} from
                        // the other die is discarded. Stay in WAIT_SWEEP_OR_REQ
                        // until rxdeskew_en deasserts (controller follows LOCAL
                        // to DTC1).
                        if (local_exit_dtc1_active) begin
                            next_state = RXDESKEW_PTR_WAIT_SWEEP_OR_REQ; // Discard
                        end
                        else if (local_end_active) begin
                            next_state = RXDESKEW_PTR_SEND_END_RESP; // Respond when LOCAL is ready to end
                        end
                        else begin
                            next_state = RXDESKEW_PTR_WAIT_SWEEP_OR_REQ; // Hold until LOCAL is ready
                        end
                    end
                end

                // -------------------------------------------------------
                // SEND_PRESET_RESP:
                // Send {EQ Preset resp} with MsgInfo[0]=0 (Success) for 1 cycle.
                // phy_tx_eq_preset_ctrl is driven from the latched rx_preset_code_r.
                // Return to WAIT_SWEEP_OR_REQ: Local may request another preset.
                // -------------------------------------------------------
                RXDESKEW_PTR_SEND_PRESET_RESP: begin
                    next_state = RXDESKEW_PTR_WAIT_SWEEP_OR_REQ;
                end

                // -------------------------------------------------------
                // SEND_PRESET_FAIL:
                // Send {EQ Preset resp} with MsgInfo[0]=1 (Fail) for 1 cycle.
                // Return to WAIT_SWEEP_OR_REQ: Local may retry with another preset.
                // -------------------------------------------------------
                RXDESKEW_PTR_SEND_PRESET_FAIL: begin
                    next_state = RXDESKEW_PTR_WAIT_SWEEP_OR_REQ;
                end

                // -------------------------------------------------------
                // SEND_EXIT_DTC1_RESP:
                // Send {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 resp} for 1 cycle.
                // After sending → DTC1_ARC_INC (1-cycle) → TO_DTC1.
                // SPEC: After this resp is sent, any pending {end req} is discarded
                //       by the system (originator must not expect a response).
                // -------------------------------------------------------
                RXDESKEW_PTR_SEND_EXIT_DTC1_RESP: begin
                    next_state = RXDESKEW_PTR_DTC1_ARC_INC;
                end

                // -------------------------------------------------------
                // DTC1_ARC_INC (1-cycle):
                // Dedicated 1-cycle state: dtc1_arc_cnt incremented exactly once
                // in the sequential block below. Then unconditionally → TO_DTC1.
                //
                // CRITICAL: Arc counter MUST NOT be updated in TO_DTC1 (terminal),
                // because TO_DTC1 is held for many lclk cycles until rxdeskew_en
                // deasserts. Updating in terminal would cause multiple increments.
                // -------------------------------------------------------
                RXDESKEW_PTR_DTC1_ARC_INC: begin
                    next_state = RXDESKEW_PTR_TO_DTC1;
                end

                // -------------------------------------------------------
                // SEND_END_RESP:
                // Send {MBTRAIN.RXDESKEW end resp} for 1 cycle.
                // After sending → TO_DTC2.
                // -------------------------------------------------------
                RXDESKEW_PTR_SEND_END_RESP: begin
                    next_state = RXDESKEW_PTR_TO_DTC2;
                end

                // -------------------------------------------------------
                // TO_DTC2 (Terminal): rxdeskew_done=1.
                // Hold until MBTRAIN_ctrl_partner deasserts rxdeskew_en.
                // -------------------------------------------------------
                RXDESKEW_PTR_TO_DTC2: begin
                    next_state = rxdeskew_en ? RXDESKEW_PTR_TO_DTC2 : RXDESKEW_PTR_IDLE;
                end

                // -------------------------------------------------------
                // TO_DTC1 (Terminal): datatraincenter1_req=1.
                // Hold until MBTRAIN_ctrl_partner deasserts rxdeskew_en.
                // NOTE: dtc1_arc_cnt was already incremented in DTC1_ARC_INC.
                // -------------------------------------------------------
                RXDESKEW_PTR_TO_DTC1: begin
                    next_state = rxdeskew_en ? RXDESKEW_PTR_TO_DTC1 : RXDESKEW_PTR_IDLE;
                end

                // -------------------------------------------------------
                // TO_TRAINERROR (Terminal): trainerror_req=1.
                // Hold until MBTRAIN_ctrl_partner deasserts rxdeskew_en.
                // -------------------------------------------------------
                RXDESKEW_PTR_TO_TRAINERROR: begin
                    next_state = rxdeskew_en ? RXDESKEW_PTR_TO_TRAINERROR : RXDESKEW_PTR_IDLE;
                end

                default: begin
                    next_state = RXDESKEW_PTR_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Sequential Block: DTC1 Arc Counter + EQ Preset Latch
    //
    // Handles:
    //   1. dtc1_arc_cnt: incremented ONLY in DTC1_ARC_INC (1-cycle state).
    //      Reset when session starts (IDLE → active) or on TO_DTC2/TO_TRAINERROR.
    //      NOT reset on TO_DTC1 — persists across DTC1 loopbacks.
    //
    //   2. rx_preset_code_r / preset_valid_r:
    //      Latched on receipt of {EQ Preset req} while in WAIT_SWEEP_OR_REQ.
    //      Held until next preset req arrives (or reset).
    //      preset_valid_r=1 iff code is in [0, MAX_VALID_PRESET].
    //
    // Rule: rst_n (async) and is_ltsm_out_of_reset (sync) in SEPARATE branches.
    // =========================================================================
    reg is_dtc1_arc_cnt_inc_allowed;
    always_ff @(posedge lclk or negedge rst_n) begin : ARC_AND_PRESET_PROC
        if (!rst_n) begin
            dtc1_arc_cnt                <= 3'd0;
            rx_preset_code_r            <= 4'd0;
            is_dtc1_arc_cnt_inc_allowed <= 1'b1;
            end_req_rcvd                <= 1'b0;
        end
        else if (!soft_rst_n) begin
            dtc1_arc_cnt                <= 3'd0;
            rx_preset_code_r            <= 4'd0;
            is_dtc1_arc_cnt_inc_allowed <= 1'b1;
            end_req_rcvd                <= 1'b0;
        end
        else begin
            if (rxdeskew_en && rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_end_req) begin
                end_req_rcvd <= 1'b1;
            end
            else if (!rxdeskew_en) begin
                end_req_rcvd <= 1'b0;
            end

            if (current_state == RXDESKEW_PTR_WAIT_START_REQ) begin
                is_dtc1_arc_cnt_inc_allowed <= 1'b1;
            end
            // ------------------------------------------------------------------
            // TO_DTC2 or TO_TRAINERROR: Reset arc counter.
            // The arc counter persists across DTC1 loopbacks intentionally —
            // the spec limits total arcs to 4, so dtc1_arc_cnt must NOT be
            // reset on re-entry from DTC1. It is only reset when the RXDESKEW
            // substate truly completes (DTC2) or terminates with an error.
            // ------------------------------------------------------------------
            else if (current_state == RXDESKEW_PTR_TO_DTC2 || current_state == RXDESKEW_PTR_TO_TRAINERROR) begin
                dtc1_arc_cnt <= 3'd0;
            end

            // ------------------------------------------------------------------
            // DTC1_ARC_INC (1-cycle): Increment arc counter exactly once.
            // This happens exactly 1 lclk after SEND_EXIT_DTC1_RESP is done.
            // By design: cannot fire multiple times because DTC1_ARC_INC is a
            // transient 1-cycle state; the FSM moves to TO_DTC1 on the next cycle.
            // ------------------------------------------------------------------
            else if ((current_state == RXDESKEW_PTR_DTC1_ARC_INC || local_arc_taken) && is_dtc1_arc_cnt_inc_allowed) begin
                is_dtc1_arc_cnt_inc_allowed <= 1'b0;
                dtc1_arc_cnt <= dtc1_arc_cnt + 1'b1;
            end

            // ------------------------------------------------------------------
            // WAIT_SWEEP_OR_REQ: Latch EQ preset code when {EQ Preset req} arrives.
            // Latched here (in WAIT state) so that the SEND_PRESET_RESP/FAIL state
            // (1-cycle combinational output) can read rx_preset_code_r / preset_valid_r
            // as stable registered values.
            // ------------------------------------------------------------------
            else if (current_state == RXDESKEW_PTR_WAIT_SWEEP_OR_REQ &&
                    rx_sb_msg_valid &&
                    rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req) begin
                if (rx_msginfo[3:0] <= MAX_VALID_PRESET[3:0]) begin
                    rx_preset_code_r <= rx_msginfo[3:0];
                end
            end
        end
    end

    // =========================================================================
    // Moore Machine Output Logic
    // All outputs depend only on current_state (pure Moore — no comb input loops).
    // =========================================================================
    always_comb begin : OUTPUT_COMB

        // --- Defaults: all outputs at safe inactive values ---
        rxdeskew_done        = 1'b0;
        datatraincenter1_req = 1'b0;
        trainerror_req       = 1'b0;
        partner_sweep_en     = 1'b0;

        // PHY EQ preset defaults (hold current preset)
        phy_tx_eq_preset_ctrl = rx_preset_code_r[2:0];
        phy_tx_eq_preset_en   = 1'b0;

        // SB TX defaults (inactive)
        tx_sb_msg_valid = 1'b0;
        tx_sb_msg       = NOTHING;
        tx_msginfo      = 16'h0000;
        tx_data_field   = 64'h0;

        // MB Lane defaults for RXDESKEW partner (spec §4.5.3.4.10):
        //   "When not performing actions relevant to this state:"
        //   - Clock RX: enabled
        //   - Data and Valid RX: enabled
        //   - Track RX: disabled
        //   - Data and Valid TX: held low (partner holds these low while Local sweeps)
        //   - Track TX: always held low (spec)
        //   - Clock TX: free-running if > 32 GT/s OR continuous clock mode; else held low
        mb_rx_clk_lane_sel  = 1'b1;
        mb_rx_data_lane_sel = 1'b1;
        mb_rx_val_lane_sel  = 1'b1;
        mb_rx_trk_lane_sel  = 1'b0;
        mb_tx_trk_lane_sel  = 2'b00;
        mb_tx_data_lane_sel = 2'b00; // Held low while Local sweeps
        mb_tx_val_lane_sel  = 2'b00; // Held low while Local sweeps
        mb_tx_clk_lane_sel  = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00;

        // ------------------------------------------------------------------
        // Per-state output overrides
        // ------------------------------------------------------------------
        case (current_state)

            // -------------------------------------------------------
            // IDLE: All MB lanes disabled, watchdog off.
            // -------------------------------------------------------
            RXDESKEW_PTR_IDLE: begin
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
                mb_rx_trk_lane_sel  = 1'b0;
                mb_tx_clk_lane_sel  = 2'b00;
                mb_tx_data_lane_sel = 2'b00;
                mb_tx_val_lane_sel  = 2'b00;
                mb_tx_trk_lane_sel  = 2'b00;
            end

            // -------------------------------------------------------
            // WAIT_START_REQ: No SB output. Watchdog active.
            // MB lanes at default posture.
            // -------------------------------------------------------
            RXDESKEW_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            // -------------------------------------------------------
            // SEND_START_RESP: Transmit {MBTRAIN.RXDESKEW start resp}.
            // -------------------------------------------------------
            RXDESKEW_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // -------------------------------------------------------
            // WAIT_SWEEP_OR_REQ: Main wait loop. No SB output.
            // Partner holds its MB TX lanes low and RX lanes enabled
            // while the Local die performs its deskew sweep.
            // All MB signals remain at their default values above.
            // -------------------------------------------------------
            RXDESKEW_PTR_WAIT_SWEEP_OR_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
                // MB lanes: default values apply (data/valid TX held low,
                //           clock TX active if HS, all RX enabled).
            end

            // -------------------------------------------------------
            // SEND_PRESET_RESP: {EQ Preset resp} SUCCESS.
            // MsgInfo[0]=0 (Success). Apply preset to our TX PHY.
            // phy_tx_eq_preset_ctrl driven from latched rx_preset_code_r.
            // phy_tx_eq_preset_en=1 signals the PHY to apply it this cycle.
            // -------------------------------------------------------
            RXDESKEW_PTR_SEND_PRESET_RESP: begin
                tx_sb_msg_valid       = 1'b1;
                tx_sb_msg             = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
                tx_msginfo            = 16'h0000; // MsgInfo[0]=0: Success
                tx_data_field         = 64'h0;
                // Apply the EQ preset to this die's TX PHY.
                phy_tx_eq_preset_ctrl = rx_preset_code_r[2:0];
                phy_tx_eq_preset_en   = 1'b1;
            end

            // -------------------------------------------------------
            // SEND_PRESET_FAIL: {EQ Preset resp} FAIL.
            // MsgInfo[0]=1 (Fail). Preset NOT applied.
            // -------------------------------------------------------
            RXDESKEW_PTR_SEND_PRESET_FAIL: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;
                tx_msginfo      = 16'h0001; // MsgInfo[0]=1: Fail
                tx_data_field   = 64'h0;
                // phy_tx_eq_preset_en remains 0: preset NOT applied on fail.
            end

            // -------------------------------------------------------
            // SEND_EXIT_DTC1_RESP:
            // Transmit {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 resp}.
            // Spec: After sending, any pending {end req} is discarded.
            // Next cycle: DTC1_ARC_INC (1-cycle counter update) → TO_DTC1.
            // -------------------------------------------------------
            RXDESKEW_PTR_SEND_EXIT_DTC1_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // -------------------------------------------------------
            // DTC1_ARC_INC (1-cycle): No SB output. No special MB.
            // Sequential block increments dtc1_arc_cnt exactly once here.
            // -------------------------------------------------------
            RXDESKEW_PTR_DTC1_ARC_INC: begin
                // Only the sequential block acts here.
                tx_sb_msg_valid = 1'b0;
            end

            // -------------------------------------------------------
            // SEND_END_RESP: Transmit {MBTRAIN.RXDESKEW end resp}.
            // -------------------------------------------------------
            RXDESKEW_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // -------------------------------------------------------
            // TO_DTC2 (Terminal): rxdeskew_done=1. Disable watchdog.
            // Hold until MBTRAIN_ctrl_partner deasserts rxdeskew_en.
            // -------------------------------------------------------
            RXDESKEW_PTR_TO_DTC2: begin
                rxdeskew_done    = 1'b1;
            end

            // -------------------------------------------------------
            // TO_DTC1 (Terminal): datatraincenter1_req=1. Disable watchdog.
            // NOTE: dtc1_arc_cnt was already incremented in DTC1_ARC_INC.
            // -------------------------------------------------------
            RXDESKEW_PTR_TO_DTC1: begin
                datatraincenter1_req = 1'b1;
            end

            // -------------------------------------------------------
            // TO_TRAINERROR (Terminal): trainerror_req=1. Disable watchdog.
            // -------------------------------------------------------
            RXDESKEW_PTR_TO_TRAINERROR: begin
                trainerror_req   = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // Unified Arc Counter Output:
    // Wire the internal dtc1_arc_cnt register directly to the output port so
    // the LOCAL FSM instantiated alongside this module can read the same count.
    // This eliminates the duplicate arc register in unit_RXDESKEW_local.
    // =========================================================================
    assign partner_arc_cnt_out = dtc1_arc_cnt;

endmodule


