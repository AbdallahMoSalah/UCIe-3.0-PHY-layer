// ====================================================================================================
// unit_TXSELFCAL_partner.sv — MBTRAIN.TXSELFCAL PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled TXSELFCAL substate.
// The Partner FSM:
//   - Waits for {MBTRAIN.TXSELFCAL Done req} sideband message from the partner.
//   - Responds with {MBTRAIN.TXSELFCAL Done resp} sideband message.
//
// Architecture: Single-FSM, SEND → WAIT pattern.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.TXSELFCAL (Partner — Responder):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.TXSELFCAL Done req}             | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.TXSELFCAL Done resp}            | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_TXSELFCAL_partner (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control Signals
        input  logic        txselfcal_en,
        input  logic        soft_rst_n,
        output logic        txselfcal_done,
        output logic        trainerror_req,

        // MB TX/RX Lane Control
        // output logic [1:0]  mb_tx_clk_lane_sel,
        // output logic [1:0]  mb_tx_data_lane_sel,
        // output logic [1:0]  mb_tx_val_lane_sel,
        // output logic [1:0]  mb_tx_trk_lane_sel,
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_data_lane_sel,
        output logic        mb_rx_val_lane_sel,
        output logic        mb_rx_trk_lane_sel,

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
        TXSELFCAL_PTR_IDLE           = 3'd0,
        TXSELFCAL_PTR_WAIT_REQ       = 3'd1,
        TXSELFCAL_PTR_SEND_RESP      = 3'd2,
        TXSELFCAL_PTR_DONE           = 3'd3,
        TXSELFCAL_PTR_TO_TRAINERROR  = 3'd4
    } state_t;

    state_t current_state, next_state;

    // FSM State Register
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG
        if (!rst_n) begin
            current_state <= TXSELFCAL_PTR_IDLE;
        end else if (!soft_rst_n) begin
            current_state <= TXSELFCAL_PTR_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Combinational Next-State Logic
    always_comb begin : NEXT_STATE_LOGIC
        next_state = current_state;

        // TRAINERROR Overrides
        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = TXSELFCAL_PTR_TO_TRAINERROR;
        end
        else if (!txselfcal_en) begin
            next_state = TXSELFCAL_PTR_IDLE;
        end
        else begin
            case (current_state)
                TXSELFCAL_PTR_IDLE: begin
                    next_state = TXSELFCAL_PTR_WAIT_REQ;
                end

                TXSELFCAL_PTR_WAIT_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_TXSELFCAL_Done_req) begin
                        next_state = TXSELFCAL_PTR_SEND_RESP;
                    end
                end

                TXSELFCAL_PTR_SEND_RESP: begin
                    next_state = TXSELFCAL_PTR_DONE;
                end

                TXSELFCAL_PTR_DONE: begin
                    next_state = TXSELFCAL_PTR_DONE;
                end

                TXSELFCAL_PTR_TO_TRAINERROR: begin
                    next_state = TXSELFCAL_PTR_TO_TRAINERROR;
                end

                default: next_state = TXSELFCAL_PTR_IDLE;
            endcase
        end
    end

    // Output Logic
    always_comb begin : OUTPUT_LOGIC
        // Defaults
        txselfcal_done      = 1'b0;
        trainerror_req      = 1'b0;

        // Transmitters are held in tri-state (2'b10) during TXSELFCAL
        mb_rx_clk_lane_sel  = 1'b0;
        mb_rx_data_lane_sel = 1'b0;
        mb_rx_val_lane_sel  = 1'b0;
        mb_rx_trk_lane_sel  = 1'b0;

        tx_sb_msg_valid     = 1'b0;
        tx_sb_msg           = NOTHING;
        tx_msginfo          = 16'h0;
        tx_data_field       = 64'h0;

        case (current_state)
            TXSELFCAL_PTR_IDLE: begin
                // idle
            end

            TXSELFCAL_PTR_WAIT_REQ: begin
                // Waiting
            end

            TXSELFCAL_PTR_SEND_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_TXSELFCAL_Done_resp;
            end

            TXSELFCAL_PTR_DONE: begin
                txselfcal_done   = 1'b1;
            end

            TXSELFCAL_PTR_TO_TRAINERROR: begin
                txselfcal_done   = 1'b1;
                trainerror_req   = 1'b1;
            end
        endcase
    end

endmodule
