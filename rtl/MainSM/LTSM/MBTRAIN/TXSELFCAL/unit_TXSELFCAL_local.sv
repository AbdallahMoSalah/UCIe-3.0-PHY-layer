// ====================================================================================================
// unit_TXSELFCAL_local.sv — MBTRAIN.TXSELFCAL LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled TXSELFCAL substate.
// The Local FSM:
//   - Performs implementation specific Transmitter-related calibration (via phy_tx_selfcal_en).
//   - Sends {MBTRAIN.TXSELFCAL Done req} to the partner.
//   - Waits for {MBTRAIN.TXSELFCAL Done resp} from the partner's Partner FSM.
//
// Architecture: Single-FSM, SEND → WAIT pattern.
//   Each SEND state asserts tx_sb_msg_valid for exactly 1 lclk cycle,
//   then unconditionally transitions to the matching WAIT state.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.TXSELFCAL (Local — Initiator):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.TXSELFCAL Done req}             | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.TXSELFCAL Done resp}            | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_TXSELFCAL_local (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control Signals
        input  logic        txselfcal_en,
        input  logic        soft_rst_n,
        output logic        txselfcal_done,
        // output logic        trainerror_req,

        // Timer Control Signals
        output logic        analog_settle_timer_en,
        input  logic        analog_settle_time_done,

        // PHY Control Signals
        output logic        phy_tx_selfcal_en,

        // MB TX/RX Lane Control: moved to wrapper as static assigns
        // (spec §4.5.3.4.4: all TX tri-state, all RX disabled during TXSELFCAL)

        // Sideband Control Signals
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg
        // input  logic [15:0] rx_msginfo,
        // input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    // State encoding
    typedef enum logic [2:0] {
        TXSELFCAL_LCL_IDLE           = 3'd0,
        TXSELFCAL_LCL_EXECUTE        = 3'd1,
        TXSELFCAL_LCL_SEND_REQ       = 3'd2,
        TXSELFCAL_LCL_WAIT_RESP      = 3'd3,
        TXSELFCAL_LCL_TO_RXCLKCAL    = 3'd4
    } state_t;

    state_t current_state, next_state;

    // FSM State Register
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG
        if (!rst_n) begin
            current_state <= TXSELFCAL_LCL_IDLE;
        end else if (!soft_rst_n) begin
            current_state <= TXSELFCAL_LCL_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Combinational Next-State Logic
    always_comb begin : NEXT_STATE_LOGIC
        next_state = current_state;

        if (!txselfcal_en) begin
            next_state = TXSELFCAL_LCL_IDLE;
        end
        else begin
            case (current_state)
                TXSELFCAL_LCL_IDLE: begin
                    next_state = TXSELFCAL_LCL_EXECUTE;
                end

                TXSELFCAL_LCL_EXECUTE: begin
                    if (analog_settle_time_done) begin
                        next_state = TXSELFCAL_LCL_SEND_REQ;
                    end
                end

                TXSELFCAL_LCL_SEND_REQ: begin
                    next_state = TXSELFCAL_LCL_WAIT_RESP;
                end

                TXSELFCAL_LCL_WAIT_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_TXSELFCAL_Done_resp) begin
                        next_state = TXSELFCAL_LCL_TO_RXCLKCAL;
                    end
                end

                TXSELFCAL_LCL_TO_RXCLKCAL: begin
                    next_state = TXSELFCAL_LCL_TO_RXCLKCAL;
                end

                default: next_state = TXSELFCAL_LCL_IDLE;
            endcase
        end
    end

    // Output Logic
    always_comb begin : OUTPUT_LOGIC
        // Defaults
        txselfcal_done          = 1'b0;
        analog_settle_timer_en  = 1'b0;
        phy_tx_selfcal_en       = 1'b0;

        // MB signals removed — assigned statically in wrapper
        tx_sb_msg_valid         = 1'b0;
        tx_sb_msg               = NOTHING;
        tx_msginfo              = 16'h0;
        tx_data_field           = 64'h0;

        case (current_state)
            TXSELFCAL_LCL_IDLE: begin
                // idle
            end

            TXSELFCAL_LCL_EXECUTE: begin
                phy_tx_selfcal_en      = 1'b1;
                analog_settle_timer_en = 1'b1;
            end

            TXSELFCAL_LCL_SEND_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_TXSELFCAL_Done_req;
            end

            TXSELFCAL_LCL_WAIT_RESP: begin
                // Waiting, keep receivers disabled
            end

            TXSELFCAL_LCL_TO_RXCLKCAL: begin
                txselfcal_done   = 1'b1;
            end
        endcase
    end

endmodule
