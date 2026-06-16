// unit_VALVREF_local.sv — MBTRAIN.VALVREF LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled VALVREF implementation.
// The Local FSM:
//   - Sends Request SB messages to the partner die
//   - Waits for Response SB messages from the partner die
//   - Controls the external unit_D2C_sweep module via sweep_en/sweep_done
//   - Applies swept_code to phy_rx_valvref_ctrl combinationally during the sweep
//   - Registers best_code[0] after sweep_done (Valid Lane = lane 0)
//
// The PARTNER FSM (unit_VALVREF_partner.sv) handles:
//   - Receiving request SB messages from the partner's Local
//   - Sending response SB messages back
//   - Holding MB TX lanes in the correct state while Local sweeps
//
// Architecture: Single-FSM, SEND → WAIT pattern.
//   Each SEND state asserts tx_sb_msg_valid for exactly 1 lclk cycle,
//   then unconditionally transitions to the matching WAIT state.
//
// Early end_req handling:
//   The partner die finishes its sweep independently. It may send {end req}
//   BEFORE our Local has finished sweeping. We latch that early arrival in
//   end_req_rcvd and keep the FSM in WAIT_END_RESP until the resp arrives.
//   Since our Local sends {end req} first and the partner replies with
//   {end resp}, we don't need any "ready" flag — only the resp matters.
//
// D2C Sweep Connection:
//   - unit_D2C_sweep is NOT instantiated here. It lives externally
//     (ltsm_tb_attachments in TB, wrapper_MBTRAIN in RTL).
//   - This module asserts sweep_en and waits for sweep_done.
//   - During the sweep, swept_code is passed combinationally to phy_rx_valvref_ctrl.
//   - Once sweep_done asserts, best_code[0] (Valid Lane) is registered.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.VALVREF (Local — Initiator):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.VALVREF start req}              | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF start resp}             | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF end req}                | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF end resp}               | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.1 MBTRAIN.VALVREF

module unit_VALVREF_local #(
        parameter int unsigned MAX_VAL_VREF_CODE = 16 // Maximum Vref code
    ) (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock (1 GHz or 2 GHz). All transitions synchronous.
        input  logic        rst_n,              // 0: Async reset to IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        valvref_en          , // 0: Disable (→ IDLE). 1: Enable/start VALVREF sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        valvref_done        , // 1: Sub-state completed (held until valvref_en = 0).
        output logic        trainerror_req      , // 1: Fatal error — requesting TRAINERROR state.
        output logic        update_lane_mask    , // 1: Pulse on entry to SEND_START_REQ to update lane mask.

        //=====================================//
        // PHY Vref Control:                   //
        //=====================================//
        // Valid Lane Vref code output (7-bit code for the MB RX Valid Lane).
        // During D2C sweep: driven combinationally from swept_code.
        // After sweep_done: driven from registered best_code_r (Valid Lane = lane 0).
        output logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0] phy_rx_valvref_ctrl,

        //=====================================//
        // MB Lane Control Outputs:            //
        //=====================================//
        // Spec §4.5.3.4.1:
        //   - All data lanes and Track TX: held low.
        //   - Valid RX: enabled (we sample Valid lane pattern for Vref sweep).
        //   - Clock RX: enabled.
        //   - Clock TX: held differential low.
        //   - Track RX: permitted to be disabled.
        // output logic [1:0]  mb_tx_clk_lane_sel  , // 00=Held Low (spec: diff low during VALVREF)
        // output logic [1:0]  mb_tx_data_lane_sel , // 00=Held Low (spec: data lanes held low)
        // output logic [1:0]  mb_tx_val_lane_sel  , // 00=Held Low (spec: Local TX valid held low)
        // output logic [1:0]  mb_tx_trk_lane_sel  , // 00=Held Low (spec: track held low)
        output logic        mb_rx_clk_lane_sel  , // 1=Enabled  (Clock RX always enabled)
        output logic        mb_rx_data_lane_sel , // 0=Disabled (data lanes held low, no data RX)
        output logic        mb_rx_val_lane_sel  , // 1=Enabled  (Valid RX — we sample this)
        output logic        mb_rx_trk_lane_sel  , // 0=Disabled (Track RX permitted to disable)

        //=====================================//
        // D2C Sweep Interface:                //
        //=====================================//
        output logic        sweep_en            , // 1: Assert to external unit_D2C_sweep to start/hold sweep.
        input  logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0]  swept_code          , // Current Vref code under test (from unit_D2C_sweep).
        input  wire logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0]  best_code [0:15]    , // Per-lane best midpoints (lane 0 = Valid Lane).
        input  logic        sweep_done          , // 1: Full sweep complete (from unit_D2C_sweep).

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        output logic        tx_sb_msg_valid     , // Exactly 1 lclk cycle per message.
        output logic [7:0]  tx_sb_msg           , // MsgCode to transmit.
        output logic [15:0] tx_msginfo          , // MsgInfo payload.
        output logic [63:0] tx_data_field       , // 64-bit data payload.

        input  logic        rx_sb_msg_valid     , // Pulse (1 lclk) when a valid SB msg is received.
        input  logic [7:0]  rx_sb_msg             // Received MsgCode from partner die.
        // input  logic [15:0] rx_msginfo          , // Received MsgInfo payload.
        // input  logic [63:0] rx_data_field         // Received 64-bit data payload.
    );

    import UCIe_pkg::*;

    // =========================================================================
    // Local parameter — Vref code bit width
    // =========================================================================
    localparam int unsigned VW = $clog2(MAX_VAL_VREF_CODE + 1); // 7 bits for codes 0–127

    // =========================================================================
    // FSM State Encoding — SEND → WAIT pattern.
    //
    // SEND states:  assert tx_sb_msg_valid for exactly 1 cycle, then move to WAIT.
    // WAIT states:  poll rx_sb_msg until expected response arrives.
    // SWEEP state:  assert sweep_en, wait for sweep_done from unit_D2C_sweep.
    // =========================================================================
    localparam [3:0]
    VALVREF_LCL_IDLE           = 4'd0,  // Wait for valvref_en.
    VALVREF_LCL_SEND_START_REQ = 4'd1,  // TX {MBTRAIN.VALVREF start req} for 1 cycle.
    VALVREF_LCL_WAIT_START_RESP= 4'd2,  // Wait for {MBTRAIN.VALVREF start resp}.
    VALVREF_LCL_SWEEP          = 4'd3,  // Assert sweep_en; wait for sweep_done.
    VALVREF_LCL_APPLY_BEST     = 4'd4,  // 1-cycle: register best_code[0] → already done in seq.
    VALVREF_LCL_SEND_END_REQ   = 4'd5,  // TX {MBTRAIN.VALVREF end req} for 1 cycle.
    VALVREF_LCL_WAIT_END_RESP  = 4'd6,  // Wait for {MBTRAIN.VALVREF end resp}.
    VALVREF_LCL_TO_DATAVREF    = 4'd7,  // Terminal: valvref_done=1; wait for en deassert.
    VALVREF_LCL_TO_TRAINERROR  = 4'd8;  // Terminal: trainerror_req=1; wait for en deassert.

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [3:0] current_state, next_state;

    // =========================================================================
    // Registered best Vref code (Valid Lane = lane 0).
    // Captured when sweep_done is observed in VALVREF_LCL_SWEEP.
    // Drives phy_rx_valvref_ctrl after sweep completes.
    // =========================================================================
    reg [VW-1:0] best_code_r;

    // =========================================================================
    // sweep_en: asserted combinationally whenever FSM is in VALVREF_LCL_SWEEP.
    // Deasserting it causes unit_D2C_sweep to return to IDLE.
    // =========================================================================
    assign sweep_en = (current_state == VALVREF_LCL_SWEEP);

    // =========================================================================
    // Sequential FSM: state register
    // Rule: rst_n (async) and soft_rst_n (sync) in SEPARATE branches.
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= VALVREF_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= VALVREF_LCL_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // Combinational Next-State Logic
    // Priority: TRAINERROR override > valvref_en deassertion > normal FSM
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        next_state = current_state; // Default: hold

        // ------------------------------------------------------------------
        // HIGHEST PRIORITY: TRAINERROR conditions.
        // Source: Partner sent {TRAINERROR entry req}.
        // ------------------------------------------------------------------
        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = VALVREF_LCL_TO_TRAINERROR;
        end
        // ------------------------------------------------------------------
        // SECOND PRIORITY: valvref_en deassertion.
        // If the controller disables this substate, return to IDLE immediately.
        // (Applies to all non-terminal states).
        // ------------------------------------------------------------------
        else if (!valvref_en) begin
            next_state = VALVREF_LCL_IDLE;
        end
        // ------------------------------------------------------------------
        // NORMAL FSM TRANSITIONS
        // ------------------------------------------------------------------
        else begin
            case (current_state)

                // ---------------------------------------------------------
                // IDLE: Wait for valvref_en from MBTRAIN_ctrl_local.
                // ---------------------------------------------------------
                VALVREF_LCL_IDLE: begin
                    next_state = VALVREF_LCL_SEND_START_REQ;
                end

                // ---------------------------------------------------------
                // SEND_START_REQ: tx_sb_msg_valid=1 for this 1 cycle.
                // Unconditionally → WAIT_START_RESP.
                // ---------------------------------------------------------
                VALVREF_LCL_SEND_START_REQ: begin
                    next_state = VALVREF_LCL_WAIT_START_RESP;
                end

                // ---------------------------------------------------------
                // WAIT_START_RESP: Poll for {MBTRAIN.VALVREF start resp}
                // from the partner's PARTNER FSM.
                // ---------------------------------------------------------
                VALVREF_LCL_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALVREF_start_resp) begin
                        next_state = VALVREF_LCL_SWEEP;
                    end
                end

                // ---------------------------------------------------------
                // SWEEP: sweep_en is asserted combinationally.
                // The external unit_D2C_sweep runs through MIN→MAX Vref codes.
                // Wait here until sweep_done is asserted.
                // ---------------------------------------------------------
                VALVREF_LCL_SWEEP: begin
                    next_state = sweep_done ? VALVREF_LCL_APPLY_BEST : VALVREF_LCL_SWEEP;
                end

                // ---------------------------------------------------------
                // APPLY_BEST (1-cycle):
                // best_code_r was registered by the sequential block when
                // sweep_done arrived. This state gives 1 cycle for the
                // registered value to be stable before we send {end req}.
                // → Unconditionally → SEND_END_REQ.
                // ---------------------------------------------------------
                VALVREF_LCL_APPLY_BEST: begin
                    next_state = VALVREF_LCL_SEND_END_REQ;
                end

                // ---------------------------------------------------------
                // SEND_END_REQ: tx_sb_msg_valid=1 for this 1 cycle.
                // Unconditionally → WAIT_END_RESP.
                // ---------------------------------------------------------
                VALVREF_LCL_SEND_END_REQ: begin
                    next_state = VALVREF_LCL_WAIT_END_RESP;
                end

                // ---------------------------------------------------------
                // WAIT_END_RESP: Poll for {MBTRAIN.VALVREF end resp}
                // from the partner's PARTNER FSM.
                // ---------------------------------------------------------
                VALVREF_LCL_WAIT_END_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALVREF_end_resp) begin
                        next_state = VALVREF_LCL_TO_DATAVREF;
                    end
                end

                // ---------------------------------------------------------
                // TO_DATAVREF (Terminal): valvref_done=1.
                // Hold until MBTRAIN_ctrl_local deasserts valvref_en.
                // ---------------------------------------------------------
                VALVREF_LCL_TO_DATAVREF: begin
                    next_state = VALVREF_LCL_TO_DATAVREF;
                end

                // ---------------------------------------------------------
                // TO_TRAINERROR (Terminal): trainerror_req=1.
                // Hold until MBTRAIN_ctrl_local deasserts valvref_en.
                // ---------------------------------------------------------
                VALVREF_LCL_TO_TRAINERROR: begin
                    next_state = VALVREF_LCL_TO_TRAINERROR;
                end

                default: begin
                    next_state = VALVREF_LCL_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Sequential Block: best_code capture and lane mask update.
    //
    // Handles:
    //   1. best_code_r: latched when sweep_done is observed in SWEEP state.
    //      Cleared on reset or soft-reset.
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : BEST_CODE_PROC
        if (!rst_n) begin
            best_code_r <= {VW{1'b0}};
        end
        else if (!soft_rst_n) begin
            best_code_r <= {VW{1'b0}};
        end
        else begin
            // Capture best_code for the Valid Lane (lane index 0) when sweep finishes.
            if (current_state == VALVREF_LCL_SWEEP && sweep_done) begin
                best_code_r <= best_code[0][VW-1:0];
            end
        end
    end

    // =========================================================================
    // Moore Machine Output Logic
    // =========================================================================
    always_comb begin : OUTPUT_COMB
        // --- Defaults: safe inactive values ---
        valvref_done     = 1'b0;
        trainerror_req   = 1'b0;
        update_lane_mask = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB Lane defaults (spec §4.5.3.4.1):
        //   Data lanes and Track TX: held low.
        //   Clock TX: held differential low (simultaneous low for Quad clocking).
        //   Clock RX: enabled.
        //   Valid RX: enabled (we sample Valid Lane for Vref calibration).
        //   Data RX: disabled (data lanes not used).
        //   Track RX: disabled (permitted to disable per spec).
        // mb_tx_clk_lane_sel  = 2'b00; // Held Low (diff low during VALVREF)
        // mb_tx_data_lane_sel = 2'b00; // Held Low
        // mb_tx_val_lane_sel  = 2'b00; // Held Low
        // mb_tx_trk_lane_sel  = 2'b00; // Held Low
        mb_rx_clk_lane_sel  = 1'b1;  // Enabled
        mb_rx_data_lane_sel = 1'b0;  // Disabled (data lanes not tested in VALVREF)
        mb_rx_val_lane_sel  = 1'b1;  // Enabled (Valid Lane is what we calibrate)
        mb_rx_trk_lane_sel  = 1'b0;  // Disabled

        case (current_state)

            // ---------------------------------------------------------
            // IDLE: RX disabled in IDLE.
            // ---------------------------------------------------------
            VALVREF_LCL_IDLE: begin
                mb_rx_clk_lane_sel  = 1'b0; // All RX disabled in IDLE
                mb_rx_val_lane_sel  = 1'b0;
            end

            // ---------------------------------------------------------
            // SEND_START_REQ: Transmit {MBTRAIN.VALVREF start req}.
            // Also pulse update_lane_mask so the controller captures
            // the current negotiated lane mask for this session.
            // ---------------------------------------------------------
            VALVREF_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = MBTRAIN_VALVREF_start_req;
                tx_msginfo       = 16'h0;
                tx_data_field    = 64'h0;
                update_lane_mask = 1'b1; // Capture lane mask at session start
            end

            // ---------------------------------------------------------
            // WAIT_START_RESP: No TX. MB at default posture.
            // ---------------------------------------------------------
            VALVREF_LCL_WAIT_START_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            // ---------------------------------------------------------
            // SWEEP: sweep_en is driven combinationally above.
            // MB: Partner's TX drives VALTRAIN pattern. Our RX samples it.
            // ---------------------------------------------------------
            VALVREF_LCL_SWEEP: begin
                // sweep_en asserted via assign above.
                // MB lanes stay at default: RX valid enabled, all TX held low.
            end

            // ---------------------------------------------------------
            // APPLY_BEST (1-cycle pipeline): No outputs change.
            // ---------------------------------------------------------
            VALVREF_LCL_APPLY_BEST: begin
                // Nothing to set here. Sequential block already latched best_code_r.
            end

            // ---------------------------------------------------------
            // SEND_END_REQ: Transmit {MBTRAIN.VALVREF end req}.
            // ---------------------------------------------------------
            VALVREF_LCL_SEND_END_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALVREF_end_req;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // ---------------------------------------------------------
            // WAIT_END_RESP: No TX. MB at default posture.
            // ---------------------------------------------------------
            VALVREF_LCL_WAIT_END_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            // ---------------------------------------------------------
            // TO_DATAVREF (Terminal): Assert valvref_done.
            // ---------------------------------------------------------
            VALVREF_LCL_TO_DATAVREF: begin
                valvref_done     = 1'b1;
            end

            // ---------------------------------------------------------
            // TO_TRAINERROR (Terminal): Assert trainerror_req+valvref_done.
            // ---------------------------------------------------------
            VALVREF_LCL_TO_TRAINERROR: begin
                valvref_done     = 1'b1;
                trainerror_req   = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // PHY Vref Control: drive phy_rx_valvref_ctrl combinationally.
    //
    // During VALVREF_LCL_SWEEP (sweep_en = 1):
    //   Drive swept_code so the PHY tests each Vref setting.
    //   unit_D2C_sweep steps swept_code from MIN_VAL_VREF_CODE to MAX_VAL_VREF_CODE.
    //   (note: MIN_VAL_VREF_CODE is not used in the current file)
    //
    // In all other states (APPLY_BEST onwards):
    //   Drive registered best_code_r (best Valid Lane Vref midpoint found).
    //   Held permanently until soft_rst_n = 0 clears it.
    // =========================================================================
    assign phy_rx_valvref_ctrl =
        (current_state == VALVREF_LCL_SWEEP) ?
        swept_code[VW-1:0] :
        best_code_r;

endmodule


