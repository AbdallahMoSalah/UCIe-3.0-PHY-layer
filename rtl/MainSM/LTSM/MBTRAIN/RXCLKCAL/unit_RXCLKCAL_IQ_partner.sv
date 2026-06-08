// ====================================================================================================
// Module      : unit_RXCLKCAL_IQ_partner
// Purpose     : MBTRAIN.RXCLKCAL IQ Phase Calibration FSM (Partner/Responder Side).
//               Reacts to IQ phase shift requests from the partner's Local FSM.
// ====================================================================================================
// Sideband Messages Used (IQ Partner):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.RXCLKCAL TCKN_L shift req}      | In  (RX)  | MsgInfo: [5:1]=shift; [0]=direction       |
// | {MBTRAIN.RXCLKCAL TCKN_L shift resp}     | Out (TX)  | MsgInfo: [0]=status (0=OK, 1=OutRange)    |
// | {MBTRAIN.RXCLKCAL done req}              | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_RXCLKCAL_IQ_partner
    import UCIe_pkg::*;
(
    // Clock and Reset
    input  logic        lclk,
    input  logic        rst_n,
    input  logic        is_ltsm_out_of_reset,

    // Interface with Main Partner FSM
    input  logic        iq_partner_en,          // Enable from main Partner FSM
    output logic        iq_partner_done,        // Completed (received done_req)
    output logic        iq_partner_error,       // Error (out of range)

    // PHY TCKN Shift Interface
    output logic        phy_tx_tckn_shift_en,
    output logic [4:0]  phy_tx_tckn_shift,
    output logic        phy_tx_decrement_shift,
    input  logic        phy_tx_tckn_shift_out_of_range,

    // Sideband Interface
    output logic        tx_sb_msg_valid,
    output logic [7:0]  tx_sb_msg,
    output logic [15:0] tx_msginfo,
    output logic [63:0] tx_data_field,

    input  logic        rx_sb_msg_valid,
    input  logic [7:0]  rx_sb_msg,
    input  logic [15:0] rx_msginfo
);

    // ============================================================================
    // State Encoding
    // ============================================================================
    typedef enum logic [2:0] {
        IQ_PTR_IDLE            = 3'h0,
        IQ_PTR_LISTEN          = 3'h1,
        IQ_PTR_SEND_SHIFT_RESP = 3'h2,
        IQ_PTR_DONE            = 3'h3,
        IQ_PTR_ERROR           = 3'h4
    } state_t;

    state_t current_state, next_state;

    // Registered shift values
    logic [4:0] shift_val_r;
    logic       direction_r;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            shift_val_r <= 5'h0;
            direction_r <= 1'b0;
        end
        else if (!is_ltsm_out_of_reset) begin
            shift_val_r <= 5'h0;
            direction_r <= 1'b0;
        end
        else if (current_state == IQ_PTR_IDLE) begin
            shift_val_r <= 5'h0;
            direction_r <= 1'b0;
        end
        else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_TCKN_L_shift_req && current_state == IQ_PTR_LISTEN) begin
            shift_val_r <= rx_msginfo[5:1];
            direction_r <= rx_msginfo[0];
        end
    end

    // ============================================================================
    // State Transitions
    // ============================================================================
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IQ_PTR_IDLE;
        end
        else if (!is_ltsm_out_of_reset) begin
            current_state <= IQ_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            IQ_PTR_IDLE: begin
                if (iq_partner_en) next_state = IQ_PTR_LISTEN;
                else               next_state = IQ_PTR_IDLE;
            end

            IQ_PTR_LISTEN: begin
                if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_TCKN_L_shift_req)
                    next_state = IQ_PTR_SEND_SHIFT_RESP;
                else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_done_req)
                    next_state = IQ_PTR_DONE;
                else
                    next_state = IQ_PTR_LISTEN;
            end

            IQ_PTR_SEND_SHIFT_RESP: begin
                // Transition unconditionally on the next cycle to ensure the
                // tx_sb_msg_valid response pulse lasts exactly 1 cycle.
                if (phy_tx_tckn_shift_out_of_range)
                    next_state = IQ_PTR_ERROR;
                else
                    next_state = IQ_PTR_LISTEN;
            end

            IQ_PTR_DONE: begin
                if (!iq_partner_en) next_state = IQ_PTR_IDLE;
                else                next_state = IQ_PTR_DONE;
            end

            IQ_PTR_ERROR: begin
                if (!iq_partner_en) next_state = IQ_PTR_IDLE;
                else                next_state = IQ_PTR_ERROR;
            end

            default: next_state = IQ_PTR_IDLE;
        endcase
    end

    // ============================================================================
    // Output Logic
    // ============================================================================
    always_comb begin
        // Safe defaults
        iq_partner_done        = 1'b0;
        iq_partner_error       = 1'b0;
        phy_tx_tckn_shift_en   = 1'b0;
        phy_tx_tckn_shift      = shift_val_r;
        phy_tx_decrement_shift = direction_r;

        tx_sb_msg_valid        = 1'b0;
        tx_sb_msg              = NOTHING;
        tx_msginfo             = 16'h0;
        tx_data_field          = 64'h0;

        case (current_state)
            IQ_PTR_IDLE: begin
                // Idle outputs
            end

            IQ_PTR_LISTEN: begin
                phy_tx_tckn_shift_en = 1'b1;
            end

            IQ_PTR_SEND_SHIFT_RESP: begin
                phy_tx_tckn_shift_en = 1'b1;
                tx_sb_msg_valid      = 1'b1;
                tx_sb_msg            = MBTRAIN_RXCLKCAL_TCKN_L_shift_resp;
                tx_msginfo           = {15'h0, phy_tx_tckn_shift_out_of_range};
                tx_data_field        = 64'h0;
            end

            IQ_PTR_DONE: begin
                phy_tx_tckn_shift_en = 1'b1; // Preserve settings throughout training
                iq_partner_done      = 1'b1;
            end

            IQ_PTR_ERROR: begin
                phy_tx_tckn_shift_en = 1'b1;
                iq_partner_done      = 1'b1;
                iq_partner_error     = 1'b1;
            end
        endcase
    end

endmodule
