// unit_VALVREF_partner.sv — MBTRAIN.VALVREF PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled VALVREF implementation.
//
// Role:
//   - Waits for Request SB messages from the partner die's LOCAL FSM
//   - Sends Response SB messages back to the partner die
//   - Holds MB TX lanes in the correct posture (VALTRAIN pattern) while
//     the partner's LOCAL die performs its Valid Lane Vref sweep
//   - The PARTNER does NOT perform any D2C sweep itself
//
// Architecture: Single-FSM, WAIT → SEND pattern (exact mirror of Local SEND→WAIT).
//   Each WAIT state polls rx_sb_msg until the expected request arrives.
//   Each SEND state asserts tx_sb_msg_valid for exactly 1 lclk cycle, then transitions.
//
// MB Lane Posture (spec §4.5.3.4.1):
//   "The UCIe Module Partner must set the forwarded clock phase at the center
//    of the data UI on its mainband Transmitters."
//   "The transmit pattern must be set to send 128 iterations of continuous mode
//    VALTRAIN (four 1s and four 0s) pattern."
//   - All data lanes and Track TX: held low.
//   - Valid TX: active (driving VALTRAIN pattern for partner's RX to sample).
//   - Clock TX: active (center-phase forwarded clock).
//   - Clock RX, Data RX, Valid RX: enabled.
//   - Track RX: disabled (permitted per spec).
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.VALVREF (Partner — Responder):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.VALVREF start req}              | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF start resp}             | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF end req}                | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALVREF end resp}               | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.1 MBTRAIN.VALVREF

module unit_VALVREF_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,               // LTSM clock domain. All FSM transitions synchronous.
        input  logic        rst_n,               // 0: Asynchronous reset → IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        valvref_en          , // 0: Disable (→ IDLE immediately). 1: Enable/start sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        valvref_done        , // 1: Sub-state completed; held until valvref_en = 0.

        // MB TX Lane Control: moved to wrapper_VALVREF as static assigns
        // (spec §4.5.3.4.1: Clock TX active, Valid TX active=VALTRAIN, Data/Track TX held low)
        // output logic [1:0]  mb_tx_clk_lane_sel  ,
        // output logic [1:0]  mb_tx_data_lane_sel ,
        // output logic [1:0]  mb_tx_val_lane_sel  ,
        // output logic [1:0]  mb_tx_trk_lane_sel  ,
        // MB RX Lane Control: moved to wrapper_VALVREF as static assigns
        // output logic        mb_rx_clk_lane_sel  ,
        // output logic        mb_rx_data_lane_sel ,
        // output logic        mb_rx_val_lane_sel  ,
        // output logic        mb_rx_trk_lane_sel  ,

        //=====================================//
        // Partner Sweep Enable:               //
        //=====================================//
        // partner_sweep_en: asserted while Partner is in WAIT_END_REQ state.
        // Signals the shared unit_D2C_sweep that the partner die's TX pattern
        // should be kept active (partner_rx_pt_en in wrapper_D2C_PT_top).
        output logic        partner_sweep_en    , // 1: Hold partner TX D2C pattern active.

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
    // FSM State Encoding — WAIT → SEND pattern (mirror of Local SEND→WAIT).
    //
    // WAIT states:  poll rx_sb_msg until the expected request arrives.
    // SEND states:  assert tx_sb_msg_valid for exactly 1 cycle, then transition.
    // =========================================================================
    localparam [2:0]
    VALVREF_PTR_IDLE            = 3'd0,  // Wait for valvref_en.
    VALVREF_PTR_WAIT_START_REQ  = 3'd1,  // Wait for {MBTRAIN.VALVREF start req}.
    VALVREF_PTR_SEND_START_RESP = 3'd2,  // TX {MBTRAIN.VALVREF start resp} for 1 cycle.
    VALVREF_PTR_WAIT_END_REQ    = 3'd3,  // Wait while Local sweeps; wait for {end req}.
    VALVREF_PTR_SEND_END_RESP   = 3'd4,  // TX {MBTRAIN.VALVREF end resp} for 1 cycle.
    VALVREF_PTR_TO_DATAVREF     = 3'd5;  // Terminal: valvref_done=1; wait for en deassert.
    // VALVREF_PTR_TO_TRAINERROR   = 3'd6;  // Terminal: trainerror_req=1; wait for en deassert.

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [2:0] current_state, next_state;

    // =========================================================================
    // Sequential FSM: state register
    // Rule: rst_n (async) and soft_rst_n (sync) in SEPARATE branches.
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= VALVREF_PTR_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= VALVREF_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // Combinational Next-State Logic
    //
    // Priority:
    //   1. FIRST: valvref_en deasserted → return to IDLE.
    //   2. SECOND: normal FSM transitions.
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        next_state = current_state; // Default: hold

        // ------------------------------------------------------------------
        // FIRST PRIORITY: valvref_en deasserted.
        // Only applies to non-terminal states (terminal states gate on valvref_en below).
        // ------------------------------------------------------------------
        if (!valvref_en) begin
            next_state = VALVREF_PTR_IDLE;
        end
        // ------------------------------------------------------------------
        // SECOND PRIORITY: normal FSM transitions.
        // ------------------------------------------------------------------
        else begin
            case (current_state)

                // ---------------------------------------------------------
                // IDLE: Wait for valvref_en from MBTRAIN_ctrl_partner.
                // ---------------------------------------------------------
                VALVREF_PTR_IDLE: begin
                    next_state = VALVREF_PTR_WAIT_START_REQ;
                end

                // ---------------------------------------------------------
                // WAIT_START_REQ: Poll for {MBTRAIN.VALVREF start req}
                // from the other die's LOCAL FSM.
                // ---------------------------------------------------------
                VALVREF_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALVREF_start_req) begin
                        next_state = VALVREF_PTR_SEND_START_RESP;
                    end
                end

                // ---------------------------------------------------------
                // SEND_START_RESP: tx_sb_msg_valid=1 for 1 cycle.
                // → Unconditionally move to WAIT_END_REQ.
                // ---------------------------------------------------------
                VALVREF_PTR_SEND_START_RESP: begin
                    next_state = VALVREF_PTR_WAIT_END_REQ;
                end

                // ---------------------------------------------------------
                // WAIT_END_REQ: Main wait loop.
                //   - Hold MB lanes (partner drives VALTRAIN on Valid TX).
                //   - partner_sweep_en asserted to keep D2C pattern active.
                //   - Wait for {MBTRAIN.VALVREF end req} from the other die's LOCAL.
                //
                // SPEC §4.5.3.4.1:
                //   "When {MBTRAIN.VALVREF end req} is received, the UCIe Module
                //    Partner must respond with {MBTRAIN.VALVREF end resp}."
                // ---------------------------------------------------------
                VALVREF_PTR_WAIT_END_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALVREF_end_req) begin
                        next_state = VALVREF_PTR_SEND_END_RESP;
                    end
                end

                // ---------------------------------------------------------
                // SEND_END_RESP: tx_sb_msg_valid=1 for 1 cycle.
                // → TO_DATAVREF (normal completion).
                // ---------------------------------------------------------
                VALVREF_PTR_SEND_END_RESP: begin
                    next_state = VALVREF_PTR_TO_DATAVREF;
                end

                // ---------------------------------------------------------
                // TO_DATAVREF (Terminal): valvref_done=1.
                // Hold until MBTRAIN_ctrl_partner deasserts valvref_en.
                // ---------------------------------------------------------
                VALVREF_PTR_TO_DATAVREF: begin
                    next_state = VALVREF_PTR_TO_DATAVREF;
                end

                // ---------------------------------------------------------
                // TO_TRAINERROR (Terminal): trainerror_req=1.
                // Hold until MBTRAIN_ctrl_partner deasserts valvref_en.
                // ---------------------------------------------------------
                // VALVREF_PTR_TO_TRAINERROR: begin
                //     next_state = VALVREF_PTR_TO_TRAINERROR;
                // end

                default: begin
                    next_state = VALVREF_PTR_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Moore Machine Output Logic
    // All outputs depend only on current_state (pure Moore).
    // =========================================================================
    always_comb begin : OUTPUT_COMB

        // --- Defaults: safe inactive values ---
        valvref_done     = 1'b0;
        // trainerror_req   = 1'b0;
        partner_sweep_en = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB TX defaults (moved to wrapper as static assigns)
        // mb_tx_clk_lane_sel  = 2'b01;
        // mb_tx_data_lane_sel = 2'b00;
        // mb_tx_val_lane_sel  = 2'b01;
        // mb_tx_trk_lane_sel  = 2'b00;

        case (current_state)

            // ---------------------------------------------------------
            // IDLE: All outputs at minimum activity.
            // ---------------------------------------------------------
            VALVREF_PTR_IDLE: begin
                // MB signals handled in wrapper
            end

            // ---------------------------------------------------------
            // WAIT_START_REQ: No SB output. MB at default.
            // ---------------------------------------------------------
            VALVREF_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            // ---------------------------------------------------------
            // SEND_START_RESP: Transmit {MBTRAIN.VALVREF start resp}.
            // ---------------------------------------------------------
            VALVREF_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALVREF_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // ---------------------------------------------------------
            // WAIT_END_REQ: Main wait loop while Local performs sweep.
            //   - partner_sweep_en=1 keeps the D2C_PT TX pattern active.
            //   - MB TX Valid: active (driving VALTRAIN pattern).
            //   - MB TX Clock: active (center-phase forwarded clock).
            // ---------------------------------------------------------
            VALVREF_PTR_WAIT_END_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1; // Keep TX VALTRAIN pattern active
                // MB lanes: default values apply (valid TX active, clock TX active)
            end

            // ---------------------------------------------------------
            // SEND_END_RESP: Transmit {MBTRAIN.VALVREF end resp}.
            // ---------------------------------------------------------
            VALVREF_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALVREF_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // ---------------------------------------------------------
            // TO_DATAVREF (Terminal): Assert valvref_done.
            // ---------------------------------------------------------
            VALVREF_PTR_TO_DATAVREF: begin
                valvref_done     = 1'b1;
            end

            // ---------------------------------------------------------
            // TO_TRAINERROR (Terminal): Assert trainerror_req + valvref_done.
            // ---------------------------------------------------------
            // VALVREF_PTR_TO_TRAINERROR: begin
            //     valvref_done     = 1'b1;
            //     trainerror_req   = 1'b1;
            // end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


