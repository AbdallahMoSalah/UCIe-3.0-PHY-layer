// unit_DATAVREF_partner.sv — MBTRAIN.DATAVREF PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled DATAVREF implementation.
//
// Role:
//   - Waits for Request SB messages from the partner die's LOCAL FSM
//   - Sends Response SB messages back to the partner die
//   - Holds MB TX lanes in the correct posture (forwarded clock phase at center of UI) while
//     the partner's LOCAL die performs its Data Lanes Vref sweep.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.DATAVREF (Partner — Responder):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.DATAVREF start req}             | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATAVREF start resp}            | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATAVREF end req}               | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATAVREF end resp}              | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.2 MBTRAIN.DATAVREF


module unit_DATAVREF_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,               // LTSM clock domain synchronous transitions.
        input  logic        rst_n,               // 0: Asynchronous reset → IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        datavref_en         , // 0: Disable (→ IDLE immediately). 1: Enable/start sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        datavref_done       , // 1: Sub-state completed; held until datavref_en = 0.

        // MB TX Lane Control: moved to wrapper_DATAVREF as static assigns
        // (spec §4.5.3.4.2: CLK TX active, DATA/VAL/TRK TX held low)

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
    // FSM State Encoding
    // =========================================================================
    localparam [2:0]
    DATAVREF_PTR_IDLE            = 3'd0,  // Wait for datavref_en.
    DATAVREF_PTR_WAIT_START_REQ  = 3'd1,  // Wait for {MBTRAIN.DATAVREF start req}.
    DATAVREF_PTR_SEND_START_RESP = 3'd2,  // TX {MBTRAIN.DATAVREF start resp} for 1 cycle.
    DATAVREF_PTR_WAIT_END_REQ    = 3'd3,  // Wait while Local sweeps; wait for {end req}.
    DATAVREF_PTR_SEND_END_RESP   = 3'd4,  // TX {MBTRAIN.DATAVREF end resp} for 1 cycle.
    DATAVREF_PTR_TO_SPEEDIDLE    = 3'd5;  // Terminal: datavref_done=1; wait for en deassert.
    // DATAVREF_PTR_TO_TRAINERROR   = 3'd6;  // Terminal: trainerror_req=1; wait for en deassert.

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [2:0] current_state, next_state;

    // =========================================================================
    // Sequential FSM: state register
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= DATAVREF_PTR_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= DATAVREF_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // Combinational Next-State Logic
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        next_state = current_state; // Default: hold

        if (!datavref_en) begin
            next_state = DATAVREF_PTR_IDLE;
        end
        else begin
            case (current_state)

                // ---------------------------------------------------------
                // IDLE: Wait for datavref_en.
                // ---------------------------------------------------------
                DATAVREF_PTR_IDLE: begin
                    next_state = DATAVREF_PTR_WAIT_START_REQ;
                end

                // ---------------------------------------------------------
                // WAIT_START_REQ: Poll for {MBTRAIN.DATAVREF start req}.
                // ---------------------------------------------------------
                DATAVREF_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATAVREF_start_req) begin
                        next_state = DATAVREF_PTR_SEND_START_RESP;
                    end
                end

                // ---------------------------------------------------------
                // SEND_START_RESP: tx_sb_msg_valid=1 for 1 cycle.
                // ---------------------------------------------------------
                DATAVREF_PTR_SEND_START_RESP: begin
                    next_state = DATAVREF_PTR_WAIT_END_REQ;
                end

                // ---------------------------------------------------------
                // WAIT_END_REQ: Wait for {MBTRAIN.DATAVREF end req}.
                // ---------------------------------------------------------
                DATAVREF_PTR_WAIT_END_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATAVREF_end_req) begin
                        next_state = DATAVREF_PTR_SEND_END_RESP;
                    end
                end

                // ---------------------------------------------------------
                // SEND_END_RESP: tx_sb_msg_valid=1 for 1 cycle.
                // ---------------------------------------------------------
                DATAVREF_PTR_SEND_END_RESP: begin
                    next_state = DATAVREF_PTR_TO_SPEEDIDLE;
                end

                // ---------------------------------------------------------
                // TO_SPEEDIDLE (Terminal): datavref_done=1.
                // ---------------------------------------------------------
                DATAVREF_PTR_TO_SPEEDIDLE: begin
                    next_state = DATAVREF_PTR_TO_SPEEDIDLE;
                end

                // ---------------------------------------------------------
                // TO_TRAINERROR (Terminal): trainerror_req=1.
                // ---------------------------------------------------------
                // DATAVREF_PTR_TO_TRAINERROR: begin
                //     next_state = DATAVREF_PTR_TO_TRAINERROR;
                // end

                default: begin
                    next_state = DATAVREF_PTR_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Moore Machine Output Logic
    // =========================================================================
    always_comb begin : OUTPUT_COMB

        // --- Defaults: safe inactive values ---
        datavref_done    = 1'b0;
        // trainerror_req   = 1'b0;
        partner_sweep_en = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB TX signals moved to wrapper as static assigns
        // (mb_tx_clk=datavref_en?01:00, mb_tx_data/val/trk=00)

        case (current_state)

            // ---------------------------------------------------------
            // IDLE: All outputs at minimum activity. Watchdog off.
            // ---------------------------------------------------------
            DATAVREF_PTR_IDLE: begin
                // MB signals handled in wrapper
            end

            // ---------------------------------------------------------
            // WAIT_START_REQ: No SB output. Watchdog active.
            // ---------------------------------------------------------
            DATAVREF_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            // ---------------------------------------------------------
            // SEND_START_RESP: Transmit {MBTRAIN.DATAVREF start resp}.
            // ---------------------------------------------------------
            DATAVREF_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATAVREF_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // ---------------------------------------------------------
            // WAIT_END_REQ: Hold MB TX active during sweep.
            // ---------------------------------------------------------
            DATAVREF_PTR_WAIT_END_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
            end

            // ---------------------------------------------------------
            // SEND_END_RESP: Transmit {MBTRAIN.DATAVREF end resp}.
            // ---------------------------------------------------------
            DATAVREF_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATAVREF_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // ---------------------------------------------------------
            // TO_SPEEDIDLE (Terminal): datavref_done=1.
            // ---------------------------------------------------------
            DATAVREF_PTR_TO_SPEEDIDLE: begin
                datavref_done     = 1'b1;
            end

            // ---------------------------------------------------------
            // TO_TRAINERROR (Terminal): trainerror_req=1.
            // ---------------------------------------------------------
            // DATAVREF_PTR_TO_TRAINERROR: begin
            //     datavref_done     = 1'b1;
            //     trainerror_req   = 1'b1;
            // end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


