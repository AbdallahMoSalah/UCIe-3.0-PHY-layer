// unit_RXDESKEW_local.sv — MBTRAIN.RXDESKEW LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled RXDESKEW implementation.
// The Local FSM:
//   - Sends Request SB messages to the partner die
//   - Waits for Response SB messages from the partner die
//   - Controls the external unit_D2C_sweep module via sweep_en/sweep_done
//   - Applies swept_code to phy_rx_deskew_ctrl combinationally during the sweep
//   - Registers best_code after sweep_done and drives phy_rx_deskew_ctrl permanently
//
// The PARTNER FSM (unit_RXDESKEW_partner.sv) handles:
//   - Receiving request SB messages from the partner's Local
//   - Sending response SB messages back
//   - Holding MB lanes in the correct state while partner Local sweeps
//
// Architecture: Single-FSM, SEND → WAIT pattern (no nested or implicit FSMs).
//   Each SEND state asserts tx_sb_msg_valid for exactly 1 lclk cycle,
//   then unconditionally transitions to the matching WAIT state.
//
// D2C Sweep Connection:
//   - unit_D2C_sweep is NOT instantiated here. It lives in the top-level wrapper
//     (wrapper_MBTRAIN_mbinit_top or similar) and is shared across substates.
//   - This module asserts sweep_en and waits for sweep_done.
//   - During the sweep, swept_code is passed combinationally to phy_rx_deskew_ctrl.
//   - Once sweep_done asserts, best_code is registered for permanent use.
//   - The registered best_code is held until is_ltsm_out_of_reset = 0.
//
// Unified Arc Counter (IMPORTANT DESIGN DECISION):
//   - This module does NOT maintain its own dtc1_arc_cnt register.
//   - Instead it receives partner_arc_cnt from unit_RXDESKEW_partner on the
//     SAME die via the partner_arc_cnt port (wired to partner_arc_cnt_out).
//   - The PARTNER's counter is the authoritative source: it increments exactly
//     once in the 1-cycle RXDESKEW_PTR_DTC1_ARC_INC state each time it sends
//     {exit to DTC1 resp}.
//   - LOCAL reads this count to gate its {exit to DTC1 req} decisions, ensuring
//     both sides of the same die enforce the 4-arc limit from a single register.
//   - As a result, the RXDESKEW_DTC1_ARC_INC state has been REMOVED from this
//     FSM. LOCAL transitions directly: WAIT_EXIT_DTC1_RESP → TO_DTC1.
//   - old_best_preset is now captured in the WAIT_EXIT_DTC1_RESP sequential
//     block when the resp pulse is observed, replacing the capture that was
//     previously done in the now-removed DTC1_ARC_INC state.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.RXDESKEW (Local — Initiator):
// +----------------------------------------------------+-----------+----------------------------------------+
// | Message Name                                       | Direction | MsgInfo & Data Field Details           |
// +----------------------------------------------------+-----------+----------------------------------------+
// | {MBTRAIN.RXDESKEW start req}                       | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW start resp}                      | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW EQ Preset req}                   | Out (TX)  | MsgInfo[3:0]: EQ preset code (0–5)     |
// |   (= MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_     |           | MsgInfo[15:3]: Reserved                |
// |      MBTRAIN_RXDESKEW_EQ_Preset_req)               |           | Data: 64'h0                            |
// | {MBTRAIN.RXDESKEW EQ Preset resp}                  | In  (RX)  | MsgInfo[0]: 0=Success, 1=Fail          |
// |   (= MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_     |           | MsgInfo[15:1]: Reserved                |
// |      MBTRAIN_RXDESKEW_EQ_Preset_resp)              |           | Data: 64'h0                            |
// | {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req}    | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 resp}   | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW end req}                         | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {MBTRAIN.RXDESKEW end resp}                        | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0            |
// | {TRAINERROR entry req}                             | In  (RX)  | Forces jump to TO_TRAINERROR           |
// +----------------------------------------------------+-----------+----------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.10 MBTRAIN.RXDESKEW
// Memory:  target_implementation_technique/details_of_implementation/details_of_MBTRAIN/details_of_RXDESKEW.md
// Old ref: UCIe-3.0-PHY-layer/rtl/MainSM/LTSM/MBTRAIN/unit_RXDESKEW/unit_RXDESKEW.sv
//          (DO NOT COPY — old file has design bugs)

module unit_RXDESKEW_local #(
        parameter int unsigned MAX_DESKEW_CODE          = 7'd127, // Maximum deskew code (inclusive)
        parameter int unsigned MIN_DESKEW_CODE          = 7'd0  , // Minimum deskew code (inclusive)
        parameter int unsigned MAX_ARC_LIMIT            = 3'd4  , // Maximum DTC1 arc iterations (spec = 4)
        parameter int unsigned MAX_PRESET_SEARCH        = 3'd6  , // Maximum EQ presets to try (0–5, total 6)
        // MIN_DESIRED_SWEEP_RANGE: Minimum acceptable eye width (in deskew codes) across all active lanes.
        // If best eye is narrower, Local tries another EQ preset.
        // Default: 75% of full code range.
        parameter int unsigned MIN_DESIRED_SWEEP_RANGE  = (MAX_DESKEW_CODE - MIN_DESKEW_CODE + 1) * 75 / 100
    ) (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock domain (1 GHz or 2 GHz). All FSM transitions synchronous.
        input  logic        rst_n,              // 0: Asynchronous reset to IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        rxdeskew_en          , // 0: Disable (→ IDLE). 1: Enable/start RXDESKEW sequence.
        input  logic        is_ltsm_out_of_reset , // 0: Soft-reset active (all regs → defaults). 1: Normal.
        input  logic        timeout_8ms_occured  , // 1: 8ms residency timeout → force TO_TRAINERROR.
        output logic        rxdeskew_done        , // 1: Sub-state completed (held until rxdeskew_en = 0).
        output logic        datatraincenter1_req , // 1: Arc request to DTC1 (for EQ-preset refinement).
        output logic        trainerror_req       , // 1: Fatal error, requesting TRAINERROR state.
        output logic        local_exit_dtc1_active, // 1: LOCAL has committed to DTC1 arc path.
        output logic        local_end_active      , // 1: LOCAL has committed to ending (DTC2 path)
        //    Used by PARTNER to suppress {end resp}
        //    per spec §4.5.3.4.10 cross-die coordination.
        // Unified Arc Counter Input:
        // Wired to partner_arc_cnt_out of unit_RXDESKEW_partner on the same die.
        // LOCAL uses this value (instead of maintaining its own dtc1_arc_cnt) to
        // decide whether another RXDESKEW→DTC1 arc is within the 4-arc budget.
        input  logic [2:0]  partner_arc_cnt      , // From PARTNER on same die: arcs taken so far.

        //=====================================//
        // Timer Control Signals:              //
        //=====================================//
        output logic        timeout_timer_en       , // 1: Enable 8ms watchdog. 0: Disable (in terminal/idle states).

        //=====================================//
        // PHY Deskew Control:                 //
        //=====================================//
        // Per-lane deskew code output (7-bit code per lane, range 0–127).
        // During the D2C sweep:
        //   Driven combinationally from swept_code (all lanes share the same swept code).
        // After sweep_done:
        //   Driven from registered best_code_r[lane] (per-lane best midpoint, permanently
        //   held until is_ltsm_out_of_reset = 0 or hard reset).
        output logic [6:0]  phy_rx_deskew_ctrl [15:0], // Deskew code applied to each RX data lane.

        //=====================================//
        // MB Lane Control Outputs:            //
        //=====================================//
        // Lane selection signals (all combinational from current_state)
        output logic [1:0]  mb_tx_clk_lane_sel  , // 00=Held Low / 01=Active (free-running fwd clk)
        output logic [1:0]  mb_tx_data_lane_sel , // 00=Held Low  / 01=Active
        output logic [1:0]  mb_tx_val_lane_sel  , // 00=Held Low  / 01=Active
        output logic [1:0]  mb_tx_trk_lane_sel  , // 00=Held Low (track TX always held low in RXDESKEW)
        output logic        mb_rx_clk_lane_sel  , // 1=Enabled  (clock RX always enabled per spec)
        output logic        mb_rx_data_lane_sel , // 1=Enabled  (data RX enabled per spec)
        output logic        mb_rx_val_lane_sel  , // 1=Enabled  (valid RX enabled per spec)
        output logic        mb_rx_trk_lane_sel  , // 0=Disabled (track RX not used here)

        //=====================================//
        // Speed and Clock Mode:               //
        //=====================================//
        input  logic        is_high_speed         , // 1 = operating speed > 32 GT/s
        input  logic        is_continuous_clk_mode, // 1 = partner uses continuous clock mode (not strobe)

        //=====================================//
        // D2C Sweep Interface:                //
        //=====================================//
        // Connection to the shared unit_D2C_sweep module (instantiated externally
        // in the top-level wrapper). This module does NOT instantiate unit_D2C_sweep.
        //
        // sweep_en  : asserted by this FSM while in RXDESKEW_TX_D2C_SWEEP state.
        //             Deasserted when sweep_done is seen (FSM advances to APPLY_BEST_CODE).
        //             Deasserting sweep_en causes unit_D2C_sweep to return to IDLE.
        //
        // swept_code: Current code being tested during the sweep (registered inside
        //             unit_D2C_sweep). Drives phy_rx_deskew_ctrl combinationally
        //             while sweep_en is asserted.
        //
        // best_code : Per-lane best midpoint codes (combinational out of unit_D2C_sweep).
        //             Registered into best_code_r here on the clock edge when sweep_done
        //             is observed. Thereafter drives phy_rx_deskew_ctrl permanently.
        //
        // min_eye_width: Narrowest best-window across active lanes (combinational).
        //
        // sweep_done: 1 = sweep complete. Held by unit_D2C_sweep until sweep_en deasserts.
        output logic        sweep_en             , // To unit_D2C_sweep: start/sustain sweep.
        input  logic [6:0]  swept_code           , // From unit_D2C_sweep: current code under test.
        input  wire logic [6:0]  best_code [0:15]     , // From unit_D2C_sweep: per-lane best midpoint.
        input  logic [6:0]  min_eye_width        , // From unit_D2C_sweep: narrowest eye across active lanes.
        input  logic        sweep_done           , // From unit_D2C_sweep: 1 = full sweep complete.

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        // SB TX:
        output logic        tx_sb_msg_valid     , // Asserted for exactly 1 lclk cycle to transmit a SB msg.
        output logic [7:0]  tx_sb_msg          , // MsgCode to transmit.
        output logic [15:0] tx_msginfo         , // MsgInfo payload.
        output logic [63:0] tx_data_field      , // 64-bit data payload.

        // SB RX:
        input  logic        rx_sb_msg_valid     , // Pulse (1 lclk) when a valid SB msg is received from partner.
        input  logic [7:0]  rx_sb_msg          , // Received MsgCode from partner die.
        input  logic [15:0] rx_msginfo         , // Received MsgInfo payload.
        input  logic [63:0] rx_data_field        // Received 64-bit data payload.
    );

    import UCIe_pkg::*;

    // =========================================================================
    // Local parameter — deskew code bit width
    // =========================================================================
    localparam int unsigned DW = $clog2(MAX_DESKEW_CODE + 1); // 7 bits for codes 0–127

    // =========================================================================
    // FSM State Encoding
    // Single-FSM, SEND → WAIT pattern.
    // SEND states assert tx_sb_msg_valid for exactly 1 cycle, then move to WAIT.
    // =========================================================================
    localparam [4:0]
    RXDESKEW_IDLE               = 5'd0 , // Wait for rxdeskew_en.
    RXDESKEW_SEND_START_REQ     = 5'd1 , // Assert {MBTRAIN.RXDESKEW start req} for 1 cycle.
    RXDESKEW_WAIT_START_RESP    = 5'd2 , // Wait for {MBTRAIN.RXDESKEW start resp}.
    RXDESKEW_CHOOSE_PRESET      = 5'd3 , // (High Speed only) Select next EQ preset to request (1-cycle logic).
    RXDESKEW_SEND_PRESET_REQ    = 5'd4 , // (High Speed only) Assert {EQ Preset req} for 1 cycle.
    RXDESKEW_WAIT_PRESET_RESP   = 5'd5 , // (High Speed only) Wait for {EQ Preset resp}.
    RXDESKEW_TX_D2C_SWEEP       = 5'd6 , // Assert sweep_en to external unit_D2C_sweep; wait for sweep_done.
    RXDESKEW_APPLY_BEST_CODE    = 5'd7 , // (1-cycle) Evaluate sweep result and decide next step.
    RXDESKEW_SEND_EXIT_DTC1_REQ = 5'd8 , // (High Speed only) Assert {exit to DATATRAINCENTER1 req} for 1 cycle.
    RXDESKEW_WAIT_EXIT_DTC1_RESP= 5'd9 , // (High Speed only) Wait for {exit to DATATRAINCENTER1 resp}.
    RXDESKEW_SEND_END_REQ       = 5'd10, // Assert {MBTRAIN.RXDESKEW end req} for 1 cycle.
    RXDESKEW_WAIT_END_RESP      = 5'd11, // Wait for {MBTRAIN.RXDESKEW end resp}.
    RXDESKEW_TO_DTC2            = 5'd12, // Terminal: rxdeskew_done=1, exit to DTC2.
    RXDESKEW_TO_DTC1            = 5'd13, // Terminal: datatraincenter1_req=1, arc to DTC1.
    RXDESKEW_TO_TRAINERROR      = 5'd14; // Terminal: trainerror_req=1, TRAINERROR.

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [4:0] current_state, next_state;

    // EXIT to DTC1 request received
    reg       exit_to_dtc1_req_rcvd;

    // =========================================================================
    // EQ Preset tracking registers (RXDESKEW-specific, managed by this module)
    // =========================================================================
    reg [2:0]       partner_preset;      // EQ preset code being requested from partner (0–5).
    reg [2:0]       best_preset;         // EQ preset that gave the widest eye in this session.
    reg [2:0]       old_best_preset;     // Best preset from the last DTC1 arc session.
    reg [2:0]       preset_search_cnt;   // How many EQ presets have been tried (incremented in CHOOSE_PRESET).
    reg [DW-1:0]    best_min_eye_width;  // Best min_eye_width found across all EQ presets.

    // =========================================================================
    // Registered best deskew codes — latched when sweep_done is first observed.
    //
    // Rule:
    //   - Registered on the clock edge where (current_state == RXDESKEW_TX_D2C_SWEEP
    //     && sweep_done == 1).
    //   - Held stable in APPLY_BEST_CODE and all subsequent states, forming the
    //     permanent deskew setting for the rest of the LTSM training flow.
    //   - Only cleared by hard reset (rst_n=0) or soft reset (is_ltsm_out_of_reset=0) or when RXDESKEW substate is re-entered.
    // =========================================================================
    reg [6:0]       best_code_r [0:15]; // Per-lane registered best midpoint code.

    // =========================================================================
    // sweep_en: asserted combinationally whenever FSM is in RXDESKEW_TX_D2C_SWEEP.
    // Deasserting it (when FSM leaves) causes unit_D2C_sweep to return to IDLE.
    // =========================================================================
    assign sweep_en = (current_state == RXDESKEW_TX_D2C_SWEEP);

    // =========================================================================
    // Sequential FSM: state register
    // Rule: rst_n and is_ltsm_out_of_reset in SEPARATE if/else-if branches.
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= RXDESKEW_IDLE;
        end
        else if (!is_ltsm_out_of_reset) begin
            // Software reset: return to IDLE without waiting for rst_n.
            current_state <= RXDESKEW_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // Combinational Next-State Logic
    // Priority: TRAINERROR override > rxdeskew_en=0 > normal FSM
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        // ---------------------------------------------------------------
        // HIGHEST PRIORITY: Global TRAINERROR conditions.
        // Three sources can force an immediate jump to TO_TRAINERROR:
        //   1. 8ms residency timeout
        //   2. Partner sent TRAINERROR_Entry_req
        //   3. Partner sent exit_to_DTC1 req AND arc count at maximum limit
        // ---------------------------------------------------------------
        if (timeout_8ms_occured ||
                (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) ||
                // partner_arc_cnt: use the PARTNER counter (owns the canonical arc count).
                // When PARTNER's arc count already reached 4, this die's PARTNER will also
                // reject the next arc req with TRAINERROR, so LOCAL pre-empts here.
                (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req && (partner_arc_cnt == 3'd4)) ) begin
            next_state = RXDESKEW_TO_TRAINERROR;
        end
        // ---------------------------------------------------------------
        // SECOND PRIORITY: If rxdeskew_en deasserts, return to IDLE.
        // ---------------------------------------------------------------
        else if (!rxdeskew_en) begin
            next_state = RXDESKEW_IDLE;
        end
        // ---------------------------------------------------------------
        // NORMAL FSM TRANSITIONS
        // ---------------------------------------------------------------
        else begin
            case (current_state)

                // -------------------------------------------------------
                // IDLE: Wait for rxdeskew_en assertion.
                // -------------------------------------------------------
                RXDESKEW_IDLE: begin
                    next_state = rxdeskew_en ? RXDESKEW_SEND_START_REQ : RXDESKEW_IDLE;
                end

                // -------------------------------------------------------
                // SEND_START_REQ: tx_sb_msg_valid=1 for this cycle.
                // Unconditionally moves to WAIT after 1 cycle.
                // -------------------------------------------------------
                RXDESKEW_SEND_START_REQ: begin
                    next_state = RXDESKEW_WAIT_START_RESP;
                end

                // -------------------------------------------------------
                // WAIT_START_RESP: Poll for {MBTRAIN.RXDESKEW start resp}.
                // After receiving:
                //   - If high speed → go to CHOOSE_PRESET (EQ negotiation)
                //   - Otherwise     → go directly to RXDESKEW_TX_D2C_SWEEP
                // -------------------------------------------------------
                RXDESKEW_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_start_resp) begin
                        next_state = is_high_speed ? RXDESKEW_CHOOSE_PRESET : RXDESKEW_TX_D2C_SWEEP;
                    end
                    else begin
                        next_state = RXDESKEW_WAIT_START_RESP;
                    end
                end

                // -------------------------------------------------------
                // CHOOSE_PRESET (HS only, 1-cycle):
                // Compute next preset to request. Sequential block advances
                // partner_preset. Unconditionally → SEND_PRESET_REQ.
                // -------------------------------------------------------
                RXDESKEW_CHOOSE_PRESET: begin
                    next_state = RXDESKEW_SEND_PRESET_REQ;
                end

                // -------------------------------------------------------
                // SEND_PRESET_REQ: tx_sb_msg_valid=1 for this cycle.
                // Unconditionally moves to WAIT after 1 cycle.
                // -------------------------------------------------------
                RXDESKEW_SEND_PRESET_REQ: begin
                    next_state = RXDESKEW_WAIT_PRESET_RESP;
                end

                // -------------------------------------------------------
                // WAIT_PRESET_RESP: Poll for {MBTRAIN.RXDESKEW EQ Preset resp}.
                //   rx_msginfo[0] = 0 → Success: proceed to sweep.
                //   rx_msginfo[0] = 1 → Fail:
                //     - If more presets to try → CHOOSE_PRESET
                //     - Otherwise (all exhausted) → SEND_END_REQ (give up)
                // -------------------------------------------------------
                RXDESKEW_WAIT_PRESET_RESP: begin
                    if (rx_sb_msg_valid &&
                            rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp) begin
                        if (rx_msginfo[0] == 1'b0) begin
                            // Success: apply this preset and run sweep.
                            next_state = RXDESKEW_TX_D2C_SWEEP;
                        end
                        else begin
                            // Fail: try next preset if available, else give up.
                            next_state = (preset_search_cnt < (MAX_PRESET_SEARCH[3:0] - 4'd1)) ?
                                RXDESKEW_CHOOSE_PRESET :
                                RXDESKEW_SEND_END_REQ;
                        end
                    end
                    else begin
                        next_state = RXDESKEW_WAIT_PRESET_RESP;
                    end
                end

                // -------------------------------------------------------
                // RXDESKEW_TX_D2C_SWEEP:
                // sweep_en is asserted combinationally (= current_state == RXDESKEW_TX_D2C_SWEEP).
                // The external unit_D2C_sweep runs its own FSM autonomously.
                // This state holds until sweep_done is asserted by unit_D2C_sweep.
                // Once we leave this state, sweep_en deasserts and unit_D2C_sweep
                // returns to IDLE on the next lclk cycle.
                // -------------------------------------------------------
                RXDESKEW_TX_D2C_SWEEP: begin
                    next_state = sweep_done ? RXDESKEW_APPLY_BEST_CODE : RXDESKEW_TX_D2C_SWEEP;
                end

                // -------------------------------------------------------
                // APPLY_BEST_CODE (1-cycle):
                // best_code_r[] has been registered in the sequential block
                // on the cycle when sweep_done was observed.
                // Evaluate min_eye_width vs MIN_DESIRED_SWEEP_RANGE and
                // determine next step.
                //
                // High Speed (>32 GT/s): EQ Preset loop and DTC1 arc available.
                //  1. Eye too narrow AND more presets available → CHOOSE_PRESET
                //  2. Presets exhausted AND partner_preset != best found → CHOOSE_PRESET
                //     (one extra loop to re-apply the best known preset before arcing)
                //  3. Arc budget available AND best_preset changed → EXIT_DTC1
                //  4. Eye wide enough OR no more options → SEND_END_REQ
                //
                // Standard speed (≤ 32 GT/s): Always → SEND_END_REQ
                // -------------------------------------------------------
                RXDESKEW_APPLY_BEST_CODE: begin
                    if (is_high_speed) begin
                        // Check if the narrowest eye width of the Data lanes is big enough to operate on (i.e. exit this substate) or not.
                        if (best_min_eye_width < MIN_DESIRED_SWEEP_RANGE[DW-1:0]) begin
                            if (preset_search_cnt < MAX_PRESET_SEARCH[3:0]) begin
                                // More presets available: try the next EQ preset.
                                next_state = RXDESKEW_CHOOSE_PRESET;
                            end
                            else begin
                                // All presets exhausted.
                                next_state =
                                    (partner_preset != best_preset)                                             ? RXDESKEW_CHOOSE_PRESET       : // Re-apply best TX EQ preset.
                                    // Use partner_arc_cnt: the unified arc counter owned by PARTNER on same die.
                                    (partner_arc_cnt < MAX_ARC_LIMIT[2:0] && (old_best_preset != best_preset)) ? RXDESKEW_SEND_EXIT_DTC1_REQ  : // Arc only if best preset changed and budget left.
                                    RXDESKEW_SEND_END_REQ;                                                                                       // No more options.
                            end
                        end
                        else begin
                            // Eye is wide enough: proceed to end handshake.
                            next_state = RXDESKEW_SEND_END_REQ;
                        end
                    end
                    else begin
                        // Standard speed (≤ 32 GT/s): no EQ preset loop, no DTC1 arc.
                        next_state = RXDESKEW_SEND_END_REQ;
                    end
                end

                // -------------------------------------------------------
                // SEND_EXIT_DTC1_REQ (High Speed only):
                // Assert {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req}
                // for exactly 1 lclk cycle, then unconditionally move to WAIT.
                // -------------------------------------------------------
                RXDESKEW_SEND_EXIT_DTC1_REQ: begin
                    next_state = RXDESKEW_WAIT_EXIT_DTC1_RESP;
                end

                // -------------------------------------------------------
                // WAIT_EXIT_DTC1_RESP (High Speed only):
                // Poll for {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 resp}.
                // When received → TO_DTC1 (arc back to DATATRAINCENTER1).
                //
                // SPEC RULE (§4.5.3.4.10): If {end req} is received from
                // partner while waiting here, IGNORE it — do NOT send
                // {end resp}. The Partner FSM on our die handles {end req}
                // independently.
                // -------------------------------------------------------
                RXDESKEW_WAIT_EXIT_DTC1_RESP: begin
                    if (rx_sb_msg_valid &&
                            rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp) begin
                        // Arc counter is owned by PARTNER (partner_arc_cnt).
                        // Go directly to TO_DTC1.
                        next_state = RXDESKEW_TO_DTC1;
                    end
                    else begin
                        // Stay here. Any {end req} received is silently ignored.
                        next_state = RXDESKEW_WAIT_EXIT_DTC1_RESP;
                    end
                end

                // -------------------------------------------------------
                // SEND_END_REQ:
                // Assert {MBTRAIN.RXDESKEW end req} for exactly 1 lclk
                // cycle, then unconditionally move to WAIT.
                // -------------------------------------------------------
                RXDESKEW_SEND_END_REQ: begin
                    next_state = RXDESKEW_WAIT_END_RESP;
                end

                // -------------------------------------------------------
                // WAIT_END_RESP:
                // Poll for {MBTRAIN.RXDESKEW end resp}.
                //
                // Two possible outcomes:
                //   1. {end resp} received → TO_DTC2 (normal completion)
                //   2. exit_to_dtc1_req_rcvd fires → TO_DTC1 (arc from other die)
                //
                // CROSS-DIE ARC HANDLING (§4.5.3.4.10):
                //   The other die's LOCAL may send {exit to DTC1 req} on the
                //   shared SB bus. This message is addressed to OUR PARTNER,
                //   which sends {exit to DTC1 resp} and transitions to DTC1.
                //   Meanwhile, OUR LOCAL (here) must ALSO follow the arc:
                //     - The spec says exit-to-DTC2 requires "sent AND received
                //       {end resp}". Our PARTNER never sent {end resp} (it
                //       handled {exit to DTC1 req} instead), so the exit-to-DTC2
                //       condition is NOT met.
                //     - Our pending {end req} is discarded per spec.
                //   → Go directly to TO_DTC1 (no arc counter increment — this
                //     arc was initiated by the other die, tracked by our PARTNER).
                // -------------------------------------------------------
                RXDESKEW_WAIT_END_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_end_resp) begin
                        next_state = RXDESKEW_TO_DTC2;
                    end
                    else if (exit_to_dtc1_req_rcvd) begin
                        // Other die's LOCAL sent {exit to DTC1 req}. Our PARTNER
                        // handles the handshake. Our {end req} is discarded.
                        // Go directly to TO_DTC1.
                        next_state = RXDESKEW_TO_DTC1;
                    end
                    else begin
                        next_state = RXDESKEW_WAIT_END_RESP;
                    end
                end

                // -------------------------------------------------------
                // TO_DTC2 (Terminal): rxdeskew_done=1.
                // -------------------------------------------------------
                RXDESKEW_TO_DTC2: begin
                    next_state = rxdeskew_en ? RXDESKEW_TO_DTC2 : RXDESKEW_IDLE;
                end

                // -------------------------------------------------------
                // TO_DTC1 (Terminal): datatraincenter1_req=1.
                // -------------------------------------------------------
                RXDESKEW_TO_DTC1: begin
                    next_state = rxdeskew_en ? RXDESKEW_TO_DTC1 : RXDESKEW_IDLE;
                end

                // -------------------------------------------------------
                // TO_TRAINERROR (Terminal): trainerror_req=1.
                // -------------------------------------------------------
                RXDESKEW_TO_TRAINERROR: begin
                    next_state = rxdeskew_en ? RXDESKEW_TO_TRAINERROR : RXDESKEW_IDLE;
                end

                default: begin
                    next_state = RXDESKEW_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Sequential Block: EQ Preset Tracking and Best Code Capture
    //
    // This block handles:
    //   1. EQ preset search (partner_preset, preset_search_cnt, best_preset,
    //      old_best_preset, best_min_eye_width)
    //   2. best_code_r[] — registered on the cycle when sweep_done is observed
    //      (current_state == RXDESKEW_TX_D2C_SWEEP && sweep_done == 1).
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : PRESET_ARC_BESTCODE_REGS_PROC
        integer i;
        if (!rst_n) begin
            partner_preset      <= 3'd0;
            best_preset         <= 3'd0;
            old_best_preset     <= 3'd7;
            preset_search_cnt   <= 3'd0;
            best_min_eye_width  <= {DW{1'b0}};
            for (i = 0; i < 16; i = i + 1) begin
                best_code_r[i]  <= 7'd0;
            end
        end
        else if (!is_ltsm_out_of_reset) begin
            // Soft reset: clear all working registers including best_code_r.
            partner_preset      <= 3'd0;
            best_preset         <= 3'd0;
            old_best_preset     <= 3'd7;
            preset_search_cnt   <= 3'd0;
            best_min_eye_width  <= {DW{1'b0}};
            for (i = 0; i < 16; i = i + 1) begin
                best_code_r[i]  <= 7'd0;
            end
        end
        else begin
            // ------------------------------------------------------------------
            // IDLE → SEND_START_REQ: New session — reset per-session counters.
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_IDLE && rxdeskew_en) begin
                partner_preset     <= 3'd0;
                preset_search_cnt  <= 3'd0;
                best_min_eye_width <= {DW{1'b0}};
            end

            // ------------------------------------------------------------------
            // TO_DTC2 or TO_TRAINERROR: Reset old_best_preset so the next fresh
            // RXDESKEW session starts without stale preset comparison data.
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_TO_DTC2 || current_state == RXDESKEW_TO_TRAINERROR) begin
                old_best_preset <= 3'd7;
            end

            // ------------------------------------------------------------------
            // WAIT_EXIT_DTC1_RESP: Capture old_best_preset the cycle the resp
            // pulse arrives.
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_WAIT_EXIT_DTC1_RESP &&
                    rx_sb_msg_valid &&
                    rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp) begin
                old_best_preset <= best_preset;
            end

            // ------------------------------------------------------------------
            // CHOOSE_PRESET: Advance the preset to try next.
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_CHOOSE_PRESET) begin
                if (preset_search_cnt >= MAX_PRESET_SEARCH[3:0]) begin
                    partner_preset <= best_preset;
                end
                else if (preset_search_cnt != 3'd0) begin
                    partner_preset <= partner_preset + 1'b1;
                end

                preset_search_cnt <= preset_search_cnt + 1'b1;
            end

            // ------------------------------------------------------------------
            // RXDESKEW_TX_D2C_SWEEP → APPLY_BEST_CODE:
            // When sweep_done is asserted, register best_code[] into best_code_r[].
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_TX_D2C_SWEEP && sweep_done) begin
                // Capture the best eye quality tracker.
                if (min_eye_width > best_min_eye_width) begin
                    best_min_eye_width <= min_eye_width;
                    best_preset        <= partner_preset;
                end
                // Register the per-lane best codes.
                for (i = 0; i < 16; i = i + 1) begin
                    best_code_r[i] <= best_code[i];
                end
            end
        end
    end

    // =========================================================================
    // Moore Machine Output Logic
    // =========================================================================
    always_comb begin : OUTPUT_COMB
        rxdeskew_done           = 1'b0;
        datatraincenter1_req    = 1'b0;
        trainerror_req          = 1'b0;
        timeout_timer_en        = 1'b1;

        tx_sb_msg_valid         = 1'b0;
        tx_sb_msg               = NOTHING;
        tx_msginfo              = 16'h0000;
        tx_data_field           = 64'h0;

        mb_rx_clk_lane_sel      = 1'b1;
        mb_rx_data_lane_sel     = 1'b1;
        mb_rx_val_lane_sel      = 1'b1;
        mb_rx_trk_lane_sel      = 1'b0;
        mb_tx_trk_lane_sel      = 2'b00;
        mb_tx_data_lane_sel     = 2'b00;
        mb_tx_val_lane_sel      = 2'b00;
        // Clock TX: active (free-running) if high speed OR continuous clock mode;
        //           held low if ≤ 32 GT/s AND strobe mode.
        mb_tx_clk_lane_sel      = (is_high_speed || is_continuous_clk_mode) ? 2'b01 : 2'b00;

        case (current_state)
            RXDESKEW_IDLE: begin end
            RXDESKEW_SEND_START_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_start_req;
            end
            RXDESKEW_WAIT_START_RESP: begin end
            RXDESKEW_CHOOSE_PRESET: begin end
            RXDESKEW_SEND_PRESET_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req;
                tx_msginfo      = {13'h0, partner_preset};
            end
            RXDESKEW_WAIT_PRESET_RESP: begin end
            RXDESKEW_TX_D2C_SWEEP: begin
                mb_tx_data_lane_sel = 2'b01;
                mb_tx_val_lane_sel  = 2'b01;
            end
            RXDESKEW_APPLY_BEST_CODE: begin end
            RXDESKEW_SEND_EXIT_DTC1_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req;
            end
            RXDESKEW_WAIT_EXIT_DTC1_RESP: begin end
            RXDESKEW_SEND_END_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_end_req;
            end
            RXDESKEW_WAIT_END_RESP: begin end
            RXDESKEW_TO_DTC2: begin
                rxdeskew_done    = 1'b1;
                timeout_timer_en = 1'b0;
            end

            // -------------------------------------------------------
            // TO_DTC1 (Terminal): Assert datatraincenter1_req; disable watchdog.
            // Arc counter is owned by PARTNER (partner_arc_cnt_out wire).
            // -------------------------------------------------------
            RXDESKEW_TO_DTC1: begin
                datatraincenter1_req = 1'b1;
                timeout_timer_en     = 1'b0;
            end

            // -------------------------------------------------------
            // TO_TRAINERROR (Terminal): Assert trainerror_req and rxdeskew_done.
            // -------------------------------------------------------
            RXDESKEW_TO_TRAINERROR: begin
                trainerror_req   = 1'b1;
                rxdeskew_done    = 1'b1;
                timeout_timer_en = 1'b0;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // PHY Deskew Control: Drive phy_rx_deskew_ctrl combinationally.
    //
    // During RXDESKEW_TX_D2C_SWEEP (sweep_en = 1):
    //   All lanes receive swept_code from unit_D2C_sweep. The external sweep
    //   module updates swept_code each step (min_code → max_code), and the PHY
    //   sees the changing deskew setting through this combinational path.
    //
    // In all other states (APPLY_BEST_CODE onwards):
    //   Each lane receives its own per-lane best_code_r[lane], which was
    //   registered when sweep_done was first observed. This value is permanent
    //   and persists for the remainder of all LTSM training (until
    //   is_ltsm_out_of_reset = 0 clears it).
    // =========================================================================
    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : DESKEW_CTRL_GEN
            assign phy_rx_deskew_ctrl[lane] = (current_state == RXDESKEW_TX_D2C_SWEEP) ?
                swept_code[DW-1:0] :   // During sweep: all lanes track the current swept code
                best_code_r[lane]  ;   // Otherwise:   per-lane registered best midpoint
        end
    endgenerate

    // =========================================================================
    // Mandatory EXIT to DTC1 received (Sticky Flag):
    //
    // Set when the OTHER die's LOCAL sends {exit to DTC1 req} on the shared
    // SB bus. This message is addressed to OUR PARTNER, but LOCAL also sees
    // it. The sticky flag survives across cycles so LOCAL can detect it in
    // WAIT_END_RESP or TO_DTC2 even if the message arrived earlier.
    //
    // Cleared only when rxdeskew_en deasserts (session teardown).
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin
        if (~rst_n) begin
            exit_to_dtc1_req_rcvd <= 1'b0;
        end
        else if (rxdeskew_en && rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req) begin
            exit_to_dtc1_req_rcvd <= 1'b1;
        end
        else if (~rxdeskew_en) begin
            exit_to_dtc1_req_rcvd <= 1'b0;
        end
    end

    // =========================================================================
    // Cross-die coordination signal:
    //
    // Tells the PARTNER FSM on THIS die that LOCAL has committed to the
    // DTC1 arc path. When this is asserted, the PARTNER MUST NOT send
    // {end resp} even if it receives {end req} from the other die.
    //
    // Spec §4.5.3.4.10: "If a UCIe Module receives an {MBTRAIN.RXDESKEW
    // end req} sideband message but the UCIe Module intends to send an
    // {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req} sideband message,
    // the UCIe Module must not send an {MBTRAIN.RXDESKEW end resp}
    // sideband message."
    // =========================================================================
    // Cross-die coordination signal:
    //
    // Tells the PARTNER FSM on THIS die that LOCAL has committed to the
    // DTC1 arc path. When this is asserted, the PARTNER MUST NOT send
    // {end resp} even if it receives {end req} from the other die.
    //
    // Spec §4.5.3.4.10: "If a UCIe Module receives an {MBTRAIN.RXDESKEW
    // end req} sideband message but the UCIe Module intends to send an
    // {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req} sideband message,
    // the UCIe Module must not send an {MBTRAIN.RXDESKEW end resp}
    // sideband message."
    // =========================================================================
    // RXDESKEW_DTC1_ARC_INC removed; LOCAL now goes directly WAIT_EXIT_DTC1_RESP → TO_DTC1.
    assign local_exit_dtc1_active = (current_state == RXDESKEW_SEND_EXIT_DTC1_REQ  ||
            current_state == RXDESKEW_WAIT_EXIT_DTC1_RESP ); // ||
    // current_state == RXDESKEW_TO_DTC1);

    assign local_end_active = (current_state == RXDESKEW_SEND_END_REQ ||
            current_state == RXDESKEW_WAIT_END_RESP ); // ||
    // current_state == RXDESKEW_TO_DTC2);

    // always_ff @(posedge lclk) begin
    //     if (current_state == RXDESKEW_APPLY_BEST_CODE) begin
    //         $display("# [DEBUG LOCAL APPLY_BEST_CODE at %0d ps]: partner_preset=%0d, best_preset=%0d, old_best_preset=%0d, partner_arc_cnt=%0d, preset_search_cnt=%0d, best_min_eye_width=%0d, MIN_DESIRED_SWEEP_RANGE=%0d",
    //             $realtime(), partner_preset, best_preset, old_best_preset, partner_arc_cnt, preset_search_cnt, best_min_eye_width, MIN_DESIRED_SWEEP_RANGE);
    //     end
    // end

endmodule


