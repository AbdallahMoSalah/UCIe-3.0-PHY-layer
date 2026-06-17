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
// BUG FIXES applied in this revision (all related to unsupported-preset handling):
//
// BUG 1 — WAIT_PRESET_RESP: last-Fail short-circuited to SEND_END_REQ.
//   OLD: On Fail, if preset_search_cnt was already at MAX_PRESET_SEARCH-1, the
//        FSM jumped directly to SEND_END_REQ, bypassing CHOOSE_PRESET entirely.
//        This had two harmful side effects:
//          (a) The re-apply-best-preset opportunity (Case B in CHOOSE_PRESET) was
//              never taken, so the partner was left with whatever failed preset was
//              last sent rather than the preset that gave the best eye width.
//          (b) Even if a previous sweep had produced a wide-enough eye, the FSM
//              skipped APPLY_BEST_CODE and went straight to ending — missing the
//              chance to evaluate a DTC1 arc.
//   FIX: On any Fail response, ALWAYS return to CHOOSE_PRESET.  CHOOSE_PRESET is
//        the single decision point for "what next?" and sets preset_fail_no_sweep
//        only when truly nothing can be done.
//
// BUG 2 — CHOOSE_PRESET sequential block: preset_search_cnt overflow on re-apply.
//   OLD: preset_search_cnt was unconditionally incremented every time CHOOSE_PRESET
//        was entered, including the Case-B re-apply pass (when cnt >= MAX_PRESET_SEARCH).
//        This caused cnt to overflow past MAX_PRESET_SEARCH (e.g. 6 → 7), permanently
//        corrupting the "< MAX_PRESET_SEARCH" comparisons used in APPLY_BEST_CODE.
//   FIX: The three cases (advance / re-apply / bail) are now fully explicit.
//        preset_search_cnt is incremented ONLY in Case A (untried presets remain).
//        It is intentionally NOT touched in Case B (re-apply) or Case C (bail).
//
// BUG 3 — CHOOSE_PRESET: no exit path when ALL presets (including re-apply) fail.
//   OLD: There was no mechanism to break the Fail→CHOOSE_PRESET loop once the
//        re-applied best_preset also got a Fail response.  The FSM would loop
//        forever: CHOOSE_PRESET → SEND_PRESET_REQ → WAIT_PRESET_RESP (Fail) →
//        CHOOSE_PRESET → (re-apply again, same Fail) → ...
//   FIX: New register preset_fail_no_sweep is set in CHOOSE_PRESET Case C
//        (all tried AND partner_preset == best_preset, meaning the re-apply also
//        got a Fail).  The combinational next-state for CHOOSE_PRESET checks this
//        flag first and routes to SEND_END_REQ instead of SEND_PRESET_REQ.
//
// BUG 4 — APPLY_BEST_CODE: type-unsafe bit-slice comparison with MAX_PRESET_SEARCH.
//   OLD: preset_search_cnt < MAX_PRESET_SEARCH[3:0] — hard-codes a 4-bit slice,
//        which silently truncates if MAX_PRESET_SEARCH ever exceeds 4 bits.
//   FIX: preset_search_cnt < MAX_PRESET_SEARCH[PRESET_SEARCH_WIDTH-1:0], matching
//        the declared width of the counter register.
// ====================================================================================================
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
        parameter int unsigned MAX_DESKEW_CODE          = 'd16, // Maximum deskew code (inclusive)
        parameter int unsigned MIN_DESKEW_CODE          = 'd0  , // Minimum deskew code (inclusive)
        parameter int unsigned MAX_ARC_LIMIT            = 'd4  , // Maximum DTC1 arc iterations (spec = 4)
        parameter int unsigned MAX_VALID_PRESET         = 'd5  , // Maximum EQ presets to try (0–5, total 6)
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
        input  logic        soft_rst_n           , // 0: Soft-reset active (all regs → defaults). 1: Normal.
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
        //
        // Spec §4.5.3.4.10: "The UCIe Module is permitted to take the RXDESKEW to
        // DATATRAINCENTER1 arc a maximum of four times."  When LOCAL consults this
        // count, it is reading the same accumulated arc total that the PARTNER uses
        // to gate its responses — so the same limit is enforced consistently on both
        // sides from a single register.
        input  logic [2:0]  partner_arc_cnt      , // From PARTNER on same die: arcs taken so far.

        //=====================================//
        // PHY Deskew Control:                 //
        //=====================================//
        // Per-lane deskew code output (7-bit code per lane, range 0–127).
        // During the D2C sweep:
        //   Driven combinationally from swept_code (all lanes share the same swept code).
        // After sweep_done:
        //   Driven from registered best_code_r[lane] (per-lane best midpoint, permanently
        //   held until soft_rst_n = 0 or hard reset).
        output logic [$clog2(MAX_DESKEW_CODE+1)-1:0]  phy_rx_deskew_ctrl [15:0], // Deskew code applied to each RX data lane.

        //=====================================//
        // MB Lane Control Outputs:            //
        //=====================================//
        // MB RX signals moved to wrapper_RXDESKEW as static assigns:
        // (spec §4.5.3.4.10: RX CLK=1, DATA=1, VAL=1, TRK=0)
        // output logic        mb_rx_clk_lane_sel  ,
        // output logic        mb_rx_data_lane_sel ,
        // output logic        mb_rx_val_lane_sel  ,
        // output logic        mb_rx_trk_lane_sel  ,

        //=====================================//
        // Speed and Clock Mode:               //
        //=====================================//
        input  logic        is_high_speed         , // 1 = operating speed > 32 GT/s

        //=====================================//
        // D2C Sweep Interface:                //
        //=====================================//
        // Connection to the shared unit_D2C_sweep module (instantiated externally
        // in the top-level wrapper). This module does NOT instantiate unit_D2C_sweep.
        //
        // sweep_en  : asserted by this FSM while in RXDESKEW_LCL_TX_D2C_SWEEP state.
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
        output      logic                                  sweep_en             , // To unit_D2C_sweep: start/sustain sweep.
        input       logic [$clog2(MAX_DESKEW_CODE+1)-1:0]  swept_code           , // From unit_D2C_sweep: current code under test.
        input  wire logic [$clog2(MAX_DESKEW_CODE+1)-1:0]  best_code [0:15]     , // From unit_D2C_sweep: per-lane best midpoint.
        input       logic [$clog2(MAX_DESKEW_CODE+1)-1:0]  min_eye_width        , // From unit_D2C_sweep: narrowest eye across active lanes.
        input       logic                                  sweep_done           , // From unit_D2C_sweep: 1 = full sweep complete.

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
        input  logic [7:0]  rx_sb_msg           ,
        input  logic [15:0] rx_msginfo
        // input  logic [63:0] rx_data_field        // Received 64-bit data payload.
    );

    import UCIe_pkg::*;
    // =========================================================================
    // Local parameter
    // =========================================================================
    localparam int unsigned DW = $clog2(MAX_DESKEW_CODE + 1); // deskew code bit width.
    localparam int unsigned MAX_PRESET_SEARCH = MAX_VALID_PRESET + 1'b1; // Maximum EQ presets to try (0–5, total 6)
    localparam int unsigned PRESET_SEARCH_WIDTH = $clog2(MAX_PRESET_SEARCH+1); // Width of the counter that counts the number of EQ presets tried.

    // =========================================================================
    // FSM State Encoding
    // Single-FSM, SEND → WAIT pattern.
    // SEND states assert tx_sb_msg_valid for exactly 1 cycle, then move to WAIT.
    // =========================================================================
    localparam [3:0]
    RXDESKEW_LCL_IDLE               = 4'd0 , // Wait for rxdeskew_en.
    RXDESKEW_LCL_SEND_START_REQ     = 4'd1 , // Assert {MBTRAIN.RXDESKEW start req} for 1 cycle.
    RXDESKEW_LCL_WAIT_START_RESP    = 4'd2 , // Wait for {MBTRAIN.RXDESKEW start resp}.
    RXDESKEW_LCL_CHOOSE_PRESET      = 4'd3 , // (High Speed only) Select next EQ preset to request (1-cycle logic).
    RXDESKEW_LCL_SEND_PRESET_REQ    = 4'd4 , // (High Speed only) Assert {EQ Preset req} for 1 cycle.
    RXDESKEW_LCL_WAIT_PRESET_RESP   = 4'd5 , // (High Speed only) Wait for {EQ Preset resp}.
    RXDESKEW_LCL_TX_D2C_SWEEP       = 4'd6 , // Assert sweep_en to external unit_D2C_sweep; wait for sweep_done.
    RXDESKEW_LCL_APPLY_BEST_CODE    = 4'd7 , // (1-cycle) Evaluate sweep result and decide next step.
    RXDESKEW_LCL_SEND_EXIT_DTC1_REQ = 4'd8 , // (High Speed only) Assert {exit to DATATRAINCENTER1 req} for 1 cycle.
    RXDESKEW_LCL_WAIT_EXIT_DTC1_RESP= 4'd9 , // (High Speed only) Wait for {exit to DATATRAINCENTER1 resp}.
    RXDESKEW_LCL_SEND_END_REQ       = 4'd10, // Assert {MBTRAIN.RXDESKEW end req} for 1 cycle.
    RXDESKEW_LCL_WAIT_END_RESP      = 4'd11, // Wait for {MBTRAIN.RXDESKEW end resp}.
    RXDESKEW_LCL_TO_DTC2            = 4'd12, // Terminal: rxdeskew_done=1, exit to DTC2.
    RXDESKEW_LCL_TO_DTC1            = 4'd13, // Terminal: datatraincenter1_req=1, arc to DTC1.
    RXDESKEW_LCL_TO_TRAINERROR      = 4'd14; // Terminal: trainerror_req=1, TRAINERROR.

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [3:0] current_state, next_state;

    // EXIT to DTC1 request received
    reg       exit_to_dtc1_req_rcvd;

    // =========================================================================
    // EQ Preset tracking registers (RXDESKEW-specific, managed by this module)
    // =========================================================================
    reg [2:0]       partner_preset;      // EQ preset code being requested from partner (0–5).
    reg [2:0]       best_preset;         // EQ preset that gave the widest eye in this session.
    reg [2:0]       old_best_preset;     // Best preset from the last DTC1 arc session.
    reg [PRESET_SEARCH_WIDTH-1:0]       preset_search_cnt;   // How many EQ presets have been tried (incremented in CHOOSE_PRESET).
    reg [DW-1:0]    best_min_eye_width;  // Best min_eye_width found across all EQ presets.
    // NOTE: There is intentionally NO "preset_fail_no_sweep" flag register here.
    //
    // A registered flag set by the sequential block in CHOOSE_PRESET and then read
    // by the combinational next-state block in the SAME visit to CHOOSE_PRESET
    // would always be one cycle late: the sequential block writes on posedge, but
    // the combinational block reads the PRE-posedge (current) value.  The result
    // would be one extra spurious SEND_PRESET_REQ before the flag became visible.
    //
    // Instead, the exhaustion condition is computed COMBINATIONALLY inside the
    // CHOOSE_PRESET next-state case using the already-stable registered values of
    // preset_search_cnt, partner_preset, and best_preset.  See CHOOSE_PRESET below.

    // =========================================================================
    // Registered best deskew codes — latched when sweep_done is first observed.
    //
    // Rule:
    //   - Registered on the clock edge where (current_state == RXDESKEW_LCL_TX_D2C_SWEEP
    //     && sweep_done == 1).
    //   - Held stable in APPLY_BEST_CODE and all subsequent states, forming the
    //     permanent deskew setting for the rest of the LTSM training flow.
    //   - Only cleared by hard reset (rst_n=0) or soft reset (soft_rst_n=0) or when RXDESKEW substate is re-entered.
    // =========================================================================
    reg [DW-1:0]     best_code_r [0:15]; // Per-lane registered best midpoint code.

    // =========================================================================
    // sweep_en: asserted combinationally whenever FSM is in RXDESKEW_LCL_TX_D2C_SWEEP.
    // Deasserting it (when FSM leaves) causes unit_D2C_sweep to return to IDLE.
    // =========================================================================
    assign sweep_en = (current_state == RXDESKEW_LCL_TX_D2C_SWEEP);

    // =========================================================================
    // Sequential FSM: state register
    // Rule: rst_n and soft_rst_n in SEPARATE if/else-if branches.
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= RXDESKEW_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            // Software reset: return to IDLE without waiting for rst_n.
            current_state <= RXDESKEW_LCL_IDLE;
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
        // Two sources can force an immediate jump to TO_TRAINERROR:
        //   1. Partner sent TRAINERROR_Entry_req
        //   2. Partner sent exit_to_DTC1 req AND arc count at maximum limit
        // ---------------------------------------------------------------
        if (// (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) ||
                // partner_arc_cnt: use the PARTNER counter (owns the canonical arc count).
                // When PARTNER's arc count already reached 4, this die's PARTNER will also
                // reject the next arc req with TRAINERROR, so LOCAL pre-empts here.
                (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req && (partner_arc_cnt == 3'd4)) ) begin
            next_state = RXDESKEW_LCL_TO_TRAINERROR;
        end
        // ---------------------------------------------------------------
        // SECOND PRIORITY: If rxdeskew_en deasserts, return to IDLE.
        // ---------------------------------------------------------------
        else if (!rxdeskew_en) begin
            next_state = RXDESKEW_LCL_IDLE;
        end
        // ---------------------------------------------------------------
        // NORMAL FSM TRANSITIONS
        // ---------------------------------------------------------------
        else begin
            case (current_state)

                // -------------------------------------------------------
                // IDLE: Wait for rxdeskew_en assertion.
                // -------------------------------------------------------
                RXDESKEW_LCL_IDLE: begin
                    next_state = RXDESKEW_LCL_SEND_START_REQ;
                end

                // -------------------------------------------------------
                // SEND_START_REQ: tx_sb_msg_valid=1 for this cycle.
                // Unconditionally moves to WAIT after 1 cycle.
                // -------------------------------------------------------
                RXDESKEW_LCL_SEND_START_REQ: begin
                    next_state = RXDESKEW_LCL_WAIT_START_RESP;
                end

                // -------------------------------------------------------
                // WAIT_START_RESP: Poll for {MBTRAIN.RXDESKEW start resp}.
                // After receiving:
                //   - If high speed → go to CHOOSE_PRESET (EQ negotiation)
                //   - Otherwise     → go directly to RXDESKEW_LCL_TX_D2C_SWEEP
                // -------------------------------------------------------
                RXDESKEW_LCL_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_start_resp) begin
                        next_state = is_high_speed ? RXDESKEW_LCL_CHOOSE_PRESET : RXDESKEW_LCL_TX_D2C_SWEEP;
                    end
                    else begin
                        next_state = RXDESKEW_LCL_WAIT_START_RESP;
                    end
                end

                // -------------------------------------------------------
                // CHOOSE_PRESET (HS only, 1-cycle):
                // Decide which EQ preset to request next, or bail out if
                // every preset attempt has been exhausted with no successful
                // sweep.
                //
                // The exhaustion condition is evaluated COMBINATIONALLY from
                // already-stable registered values — NOT from a flag written
                // by the sequential block on the same clock edge.  A flag
                // written on posedge would only be visible on the NEXT visit
                // to CHOOSE_PRESET (one cycle late), causing one extra
                // spurious SEND_PRESET_REQ before the bail-out took effect.
                //
                // Combinational exhaustion logic:
                //
                //   all_tried:
                //     preset_search_cnt >= MAX_PRESET_SEARCH
                //     → All N fresh-preset slots have been consumed.
                //
                //   reapply_done:
                //     all_tried AND partner_preset == best_preset
                //     → The Case-B re-apply sweep was also attempted
                //       (sequential block set partner_preset = best_preset
                //       on a previous visit), and that attempt also got
                //       a Fail, so we are back here with nothing left to try.
                //
                // Routing:
                //   reapply_done == 1  → SEND_END_REQ   (bail cleanly, no more options)
                //   reapply_done == 0  → SEND_PRESET_REQ (a valid preset is ready)
                // -------------------------------------------------------
                RXDESKEW_LCL_CHOOSE_PRESET: begin
                    // Combinational exhaustion signals (read stable registered values).
                    if (preset_search_cnt >= MAX_PRESET_SEARCH[PRESET_SEARCH_WIDTH-1:0] &&
                            partner_preset == best_preset) begin
                        // Every option exhausted (fresh presets + re-apply); bail out.
                        next_state = RXDESKEW_LCL_SEND_END_REQ;
                    end else begin
                        // A preset has been (or will be) prepared; transmit the request.
                        next_state = RXDESKEW_LCL_SEND_PRESET_REQ;
                    end
                end

                // -------------------------------------------------------
                // SEND_PRESET_REQ: tx_sb_msg_valid=1 for this cycle.
                // Unconditionally moves to WAIT after 1 cycle.
                // -------------------------------------------------------
                RXDESKEW_LCL_SEND_PRESET_REQ: begin
                    next_state = RXDESKEW_LCL_WAIT_PRESET_RESP;
                end

                // -------------------------------------------------------
                // WAIT_PRESET_RESP: Poll for {MBTRAIN.RXDESKEW EQ Preset resp}.
                //   rx_msginfo[0] = 0 → Success: proceed to sweep.
                //   rx_msginfo[0] = 1 → Fail: ALWAYS return to CHOOSE_PRESET.
                //
                // BUG FIX: The old code short-circuited directly to SEND_END_REQ
                // on the final Fail (when preset_search_cnt was at max).  This is
                // wrong for two independent reasons:
                //
                //   (a) It bypassed the re-apply-best-preset path.  After all N
                //       presets have been tried, CHOOSE_PRESET is responsible for
                //       switching partner_preset back to best_preset for one final
                //       sweep.  Jumping straight to SEND_END_REQ skipped that
                //       opportunity entirely.
                //
                //   (b) It bypassed APPLY_BEST_CODE, which is the only place that
                //       evaluates the DTC1 arc opportunity.  Even when the eye width
                //       was acceptable after a *previous* successful sweep, the old
                //       code could end up in SEND_END_REQ before APPLY_BEST_CODE
                //       had a chance to evaluate whether a DTC1 arc was warranted.
                //
                // Correct design: on Fail, ALWAYS return to CHOOSE_PRESET.
                // CHOOSE_PRESET is the single centralised decision point that knows:
                //   • More untried presets exist  → advance partner_preset, try again.
                //   • All tried, best != current  → re-apply best_preset, sweep once more.
                //   • All tried, best == current,
                //     preset_fail_no_sweep set    → nothing left; go to SEND_END_REQ.
                // -------------------------------------------------------
                RXDESKEW_LCL_WAIT_PRESET_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp) begin
                        if (rx_msginfo[0] == 1'b0) begin
                            // Success: partner accepted the preset — run the D2C sweep.
                            next_state = RXDESKEW_LCL_TX_D2C_SWEEP;
                        end
                        else begin
                            // Fail: always let CHOOSE_PRESET decide what to do next.
                            // CHOOSE_PRESET will set preset_fail_no_sweep=1 when it
                            // detects that every option has been exhausted and will
                            // route to SEND_END_REQ from there.
                            next_state = RXDESKEW_LCL_CHOOSE_PRESET;
                        end
                    end
                    else begin
                        next_state = RXDESKEW_LCL_WAIT_PRESET_RESP;
                    end
                end

                // -------------------------------------------------------
                // RXDESKEW_LCL_TX_D2C_SWEEP:
                // sweep_en is asserted combinationally (= current_state == RXDESKEW_LCL_TX_D2C_SWEEP).
                // The external unit_D2C_sweep runs its own FSM autonomously.
                // This state holds until sweep_done is asserted by unit_D2C_sweep.
                // Once we leave this state, sweep_en deasserts and unit_D2C_sweep
                // returns to IDLE on the next lclk cycle.
                // -------------------------------------------------------
                RXDESKEW_LCL_TX_D2C_SWEEP: begin
                    next_state = sweep_done ? RXDESKEW_LCL_APPLY_BEST_CODE : RXDESKEW_LCL_TX_D2C_SWEEP;
                end

                // -------------------------------------------------------
                // APPLY_BEST_CODE (1-cycle):
                // best_code_r[] has been registered in the sequential block
                // on the cycle when sweep_done was observed.
                // Evaluate min_eye_width vs MIN_DESIRED_SWEEP_RANGE and
                // determine next step.
                //
                // High Speed (>32 GT/s): EQ Preset loop and DTC1 arc available.
                //
                //  Decision tree (evaluated with post-sweep values):
                //
                //  1. Eye wide enough
                //     → SEND_END_REQ (done — accept the current deskew codes).
                //
                //  2. Eye too narrow AND more presets still untried
                //     (preset_search_cnt < MAX_PRESET_SEARCH)
                //     → CHOOSE_PRESET (try the next EQ preset).
                //
                //  3. Eye too narrow AND all presets tried AND
                //     partner_preset != best_preset
                //     → CHOOSE_PRESET — the sequential block will set
                //       partner_preset = best_preset for one last re-apply sweep.
                //       (This is the "re-apply best" pass described in the spec.)
                //
                //  4. Eye too narrow AND all presets tried AND
                //     partner_preset == best_preset (re-apply already done)
                //     AND arc budget available AND best_preset changed since
                //     last DTC1 arc
                //     → SEND_EXIT_DTC1_REQ (take a DTC1 arc for TX EQ tuning).
                //
                //  5. All other cases (no arc budget, no new best, etc.)
                //     → SEND_END_REQ (give up; proceed with the best seen so far).
                //
                // Standard speed (≤ 32 GT/s): no EQ preset negotiation, no DTC1 arc.
                //   Always → SEND_END_REQ.
                //
                // NOTE: preset_fail_no_sweep is NOT checked here because
                // APPLY_BEST_CODE is only reached via TX_D2C_SWEEP → sweep_done,
                // which means at least one sweep completed successfully.  The
                // all-Fail-no-sweep path is handled entirely inside CHOOSE_PRESET.
                // -------------------------------------------------------
                RXDESKEW_LCL_APPLY_BEST_CODE: begin
                    if (is_high_speed) begin
                        if (best_min_eye_width >= MIN_DESIRED_SWEEP_RANGE[DW-1:0]) begin
                            // Eye wide enough — accept and finish.
                            next_state = RXDESKEW_LCL_SEND_END_REQ;
                        end
                        else if (preset_search_cnt < MAX_PRESET_SEARCH[PRESET_SEARCH_WIDTH-1:0]) begin
                            // More untried presets remain — keep searching.
                            next_state = RXDESKEW_LCL_CHOOSE_PRESET;
                        end
                        else if (partner_preset != best_preset) begin
                            // All presets tried but best_preset was not the last one
                            // applied.  Re-apply best_preset for a final sweep.
                            // CHOOSE_PRESET detects this condition and sets partner_preset
                            // = best_preset without advancing the counter.
                            next_state = RXDESKEW_LCL_CHOOSE_PRESET;
                        end
                        else begin
                            // All presets tried; best_preset is already applied on
                            // the partner.  Check whether a DTC1 arc is warranted.
                            next_state =
                                // Arc budget left AND best changed since last arc
                                (partner_arc_cnt < MAX_ARC_LIMIT[2:0] &&
                                    old_best_preset != best_preset) ?
                                RXDESKEW_LCL_SEND_EXIT_DTC1_REQ :
                                RXDESKEW_LCL_SEND_END_REQ;
                        end
                    end
                    else begin
                        // Standard speed — no EQ loop, no DTC1 arc.
                        next_state = RXDESKEW_LCL_SEND_END_REQ;
                    end
                end

                // -------------------------------------------------------
                // SEND_EXIT_DTC1_REQ (High Speed only):
                // Assert {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req}
                // for exactly 1 lclk cycle, then unconditionally move to WAIT.
                // -------------------------------------------------------
                RXDESKEW_LCL_SEND_EXIT_DTC1_REQ: begin
                    next_state = RXDESKEW_LCL_WAIT_EXIT_DTC1_RESP;
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
                RXDESKEW_LCL_WAIT_EXIT_DTC1_RESP: begin
                    if (rx_sb_msg_valid &&
                            rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp) begin
                        // Arc counter is owned by PARTNER (partner_arc_cnt).
                        // Go directly to TO_DTC1.
                        next_state = RXDESKEW_LCL_TO_DTC1;
                    end
                    else begin
                        // Stay here. Any {end req} received is silently ignored.
                        next_state = RXDESKEW_LCL_WAIT_EXIT_DTC1_RESP;
                    end
                end

                // -------------------------------------------------------
                // SEND_END_REQ:
                // Assert {MBTRAIN.RXDESKEW end req} for exactly 1 lclk
                // cycle, then unconditionally move to WAIT.
                // -------------------------------------------------------
                RXDESKEW_LCL_SEND_END_REQ: begin
                    next_state = RXDESKEW_LCL_WAIT_END_RESP;
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
                RXDESKEW_LCL_WAIT_END_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXDESKEW_end_resp) begin
                        next_state = RXDESKEW_LCL_TO_DTC2;
                    end
                    else if (exit_to_dtc1_req_rcvd) begin
                        // Other die's LOCAL sent {exit to DTC1 req}. Our PARTNER
                        // handles the handshake. Our {end req} is discarded.
                        // Go directly to TO_DTC1.
                        next_state = RXDESKEW_LCL_TO_DTC1;
                    end
                    else begin
                        next_state = RXDESKEW_LCL_WAIT_END_RESP;
                    end
                end

                // -------------------------------------------------------
                // TO_DTC2 (Terminal): rxdeskew_done=1.
                // -------------------------------------------------------
                RXDESKEW_LCL_TO_DTC2: begin
                    next_state = RXDESKEW_LCL_TO_DTC2;
                end

                // -------------------------------------------------------
                // TO_DTC1 (Terminal): datatraincenter1_req=1.
                // -------------------------------------------------------
                RXDESKEW_LCL_TO_DTC1: begin
                    next_state = RXDESKEW_LCL_TO_DTC1;
                end

                // -------------------------------------------------------
                // TO_TRAINERROR (Terminal): trainerror_req=1.
                // -------------------------------------------------------
                RXDESKEW_LCL_TO_TRAINERROR: begin
                    next_state = RXDESKEW_LCL_TO_TRAINERROR;
                end

                default: begin
                    next_state = RXDESKEW_LCL_IDLE;
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
    //      (current_state == RXDESKEW_LCL_TX_D2C_SWEEP && sweep_done == 1).
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : PRESET_ARC_BESTCODE_REGS_PROC
        integer i;
        if (!rst_n) begin
            partner_preset      <= 3'd0;
            best_preset         <= 3'd0;
            old_best_preset     <= 3'd7;
            preset_search_cnt   <= {PRESET_SEARCH_WIDTH{1'b0}};
            best_min_eye_width  <= {DW{1'b0}};
            for (i = 0; i < 16; i = i + 1) begin
                best_code_r[i]  <= {DW{1'd0}};
            end
        end
        else if (!soft_rst_n) begin
            partner_preset      <= 3'd0;
            best_preset         <= 3'd0;
            old_best_preset     <= 3'd7;
            preset_search_cnt   <= {PRESET_SEARCH_WIDTH{1'b0}};
            best_min_eye_width  <= {DW{1'b0}};
            for (i = 0; i < 16; i = i + 1) begin
                best_code_r[i]  <= {DW{1'd0}};
            end
        end
        else begin
            // ------------------------------------------------------------------
            // IDLE → SEND_START_REQ: New session — reset per-session counters.
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_LCL_IDLE && rxdeskew_en) begin
                partner_preset      <= 3'd0;
                preset_search_cnt   <= {PRESET_SEARCH_WIDTH{1'b0}};
                best_min_eye_width  <= {DW{1'b0}};
            end

            // ------------------------------------------------------------------
            // TO_DTC2 or TO_TRAINERROR: Reset old_best_preset so the next fresh
            // RXDESKEW session starts without stale preset comparison data.
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_LCL_TO_DTC2 || current_state == RXDESKEW_LCL_TO_TRAINERROR) begin
                old_best_preset <= 3'd7;
            end

            // ------------------------------------------------------------------
            // WAIT_EXIT_DTC1_RESP: Capture old_best_preset the cycle the resp
            // pulse arrives.
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_LCL_WAIT_EXIT_DTC1_RESP &&
                    rx_sb_msg_valid &&
                    rx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp) begin
                old_best_preset <= best_preset;
            end

            // ------------------------------------------------------------------
            // CHOOSE_PRESET: Prepare the next EQ preset to request.
            //
            // The COMBINATIONAL next-state block (above) has already decided
            // whether to go to SEND_PRESET_REQ or SEND_END_REQ by reading the
            // current registered values of preset_search_cnt, partner_preset,
            // and best_preset.  This sequential block prepares the values that
            // the NEXT visit to CHOOSE_PRESET (or SEND_PRESET_REQ) will read.
            //
            // Three mutually-exclusive cases:
            //
            // Case A — More untried presets exist (cnt < MAX_PRESET_SEARCH):
            //   • Advance partner_preset to the next code.
            //     Exception: on the very first call (cnt == 0), partner_preset
            //     is already 0 from the IDLE reset, so leave it unchanged.
            //   • Increment preset_search_cnt.
            //
            // Case B — All presets tried, re-apply not yet done
            //          (cnt >= MAX AND partner_preset != best_preset):
            //   • Set partner_preset = best_preset for one final sweep attempt.
            //   • Do NOT increment preset_search_cnt — avoids overflow and
            //     keeps the "all tried" sentinel stable for APPLY_BEST_CODE.
            //
            // Case C — All tried AND partner_preset == best_preset:
            //   • The combinational block already routed to SEND_END_REQ.
            //   • Nothing to update in the sequential block.
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_LCL_CHOOSE_PRESET) begin
                if (preset_search_cnt < MAX_PRESET_SEARCH[PRESET_SEARCH_WIDTH-1:0]) begin
                    // Case A: advance to the next untried preset.
                    if (preset_search_cnt != {PRESET_SEARCH_WIDTH{1'b0}}) begin
                        partner_preset <= partner_preset + 3'd1;
                    end
                    preset_search_cnt <= preset_search_cnt + {{(PRESET_SEARCH_WIDTH-1){1'b0}}, 1'b1};
                end
                else if (partner_preset != best_preset) begin
                    // Case B: re-apply the best-seen preset for one final attempt.
                    partner_preset <= best_preset;
                    // preset_search_cnt intentionally NOT incremented.
                end
                // Case C: nothing to update; combinational block handles the exit.
            end

            // ------------------------------------------------------------------
            // RXDESKEW_LCL_TX_D2C_SWEEP → APPLY_BEST_CODE:
            // When sweep_done is asserted, register best_code[] into best_code_r[].
            // ------------------------------------------------------------------
            if (current_state == RXDESKEW_LCL_TX_D2C_SWEEP && sweep_done) begin
                // Update best eye quality tracker.
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

        tx_sb_msg_valid         = 1'b0;
        tx_sb_msg               = NOTHING;
        tx_msginfo              = 16'h0000;
        tx_data_field           = 64'h0;

        // MB RX signals moved to wrapper as static assigns (CLK=1, DATA=1, VAL=1, TRK=0)

        case (current_state)
            RXDESKEW_LCL_IDLE: begin end
            RXDESKEW_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_start_req;
            end
            RXDESKEW_LCL_WAIT_START_RESP: begin end
            RXDESKEW_LCL_CHOOSE_PRESET: begin end
            RXDESKEW_LCL_SEND_PRESET_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req;
                tx_msginfo      = {13'h0, partner_preset};
            end
            RXDESKEW_LCL_WAIT_PRESET_RESP: begin end
            RXDESKEW_LCL_TX_D2C_SWEEP: begin end
            RXDESKEW_LCL_APPLY_BEST_CODE: begin end
            RXDESKEW_LCL_SEND_EXIT_DTC1_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req;
            end
            RXDESKEW_LCL_WAIT_EXIT_DTC1_RESP: begin end
            RXDESKEW_LCL_SEND_END_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXDESKEW_end_req;
            end
            RXDESKEW_LCL_WAIT_END_RESP: begin end
            RXDESKEW_LCL_TO_DTC2: begin
                rxdeskew_done    = 1'b1;
            end

            // -------------------------------------------------------
            // TO_DTC1 (Terminal): Assert datatraincenter1_req; disable watchdog.
            // Arc counter is owned by PARTNER (partner_arc_cnt_out wire).
            // -------------------------------------------------------
            RXDESKEW_LCL_TO_DTC1: begin
                datatraincenter1_req = 1'b1;
            end

            // -------------------------------------------------------
            // TO_TRAINERROR (Terminal): Assert trainerror_req and rxdeskew_done.
            // -------------------------------------------------------
            RXDESKEW_LCL_TO_TRAINERROR: begin
                trainerror_req   = 1'b1;
                rxdeskew_done    = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // PHY Deskew Control: Drive phy_rx_deskew_ctrl combinationally.
    //
    // During RXDESKEW_LCL_TX_D2C_SWEEP (sweep_en = 1):
    //   All lanes receive swept_code from unit_D2C_sweep. The external sweep
    //   module updates swept_code each step (min_code → max_code), and the PHY
    //   sees the changing deskew setting through this combinational path.
    //
    // In all other states (APPLY_BEST_CODE onwards):
    //   Each lane receives its own per-lane best_code_r[lane], which was
    //   registered when sweep_done was first observed. This value is permanent
    //   and persists for the remainder of all LTSM training (until
    //   soft_rst_n = 0 clears it).
    // =========================================================================
    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : DESKEW_CTRL_GEN
            assign phy_rx_deskew_ctrl[lane] = (current_state == RXDESKEW_LCL_TX_D2C_SWEEP) ?
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
    // RXDESKEW_DTC1_ARC_INC removed; LOCAL now goes directly WAIT_EXIT_DTC1_RESP → TO_DTC1.
    assign local_exit_dtc1_active = (current_state == RXDESKEW_LCL_SEND_EXIT_DTC1_REQ  ||
            current_state == RXDESKEW_LCL_WAIT_EXIT_DTC1_RESP ); // ||
    // current_state == RXDESKEW_LCL_TO_DTC1);

    assign local_end_active = (current_state == RXDESKEW_LCL_SEND_END_REQ ||
            current_state == RXDESKEW_LCL_WAIT_END_RESP ); // ||
    // current_state == RXDESKEW_LCL_TO_DTC2);

    // always_ff @(posedge lclk) begin
    //     if (current_state == RXDESKEW_LCL_APPLY_BEST_CODE) begin
    //         $display("# [DEBUG LOCAL APPLY_BEST_CODE at %0d ps]: partner_preset=%0d, best_preset=%0d, old_best_preset=%0d, partner_arc_cnt=%0d, preset_search_cnt=%0d, best_min_eye_width=%0d, MIN_DESIRED_SWEEP_RANGE=%0d",
    //             $realtime(), partner_preset, best_preset, old_best_preset, partner_arc_cnt, preset_search_cnt, best_min_eye_width, MIN_DESIRED_SWEEP_RANGE);
    //     end
    // end

endmodule


