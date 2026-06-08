// ====================================================================================================
// Module      : unit_RXCLKCAL_partner
// Purpose     : MBTRAIN.RXCLKCAL sub-state FSM (Partner/Responder Side).
//               Reacts to Receiver Clock Calibration requests from the partner.
// ====================================================================================================
// Sideband Messages Used (Partner):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.RXCLKCAL start req}             | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL start resp}            | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL done req}              | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.RXCLKCAL done resp}             | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR Entry req}                   | In  (RX)  | From partner                              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_RXCLKCAL_partner
    import UCIe_pkg::*;
    (
        // Clock and Reset
        input  logic        lclk,
        input  logic        rst_n,
        input  logic        is_ltsm_out_of_reset,

        // Control and Status
        input  logic        rxclkcal_partner_en,
        output logic        rxclkcal_partner_done,
        output logic        trainerror_req,

        // Link Configuration
        input  logic        is_high_speed,          // 1 = operating speed > 32 GT/s
        input  logic        is_continuous_clk_mode, // 1 = partner advertised continuous clock mode

        // Interface to separated IQ Partner sub-module
        output logic        iq_partner_en,
        input  logic        iq_partner_done,
        input  logic        iq_partner_error,

        // MB TX Lane Control Outputs (Partner FSM controls transmitter settings)
        output logic [1:0]  mb_tx_clk_lane_sel,
        output logic [1:0]  mb_tx_trk_lane_sel,
        output logic        mb_tx_pattern_en,

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
        RXCLKCAL_PTR_IDLE       = 3'h0,
        RXCLKCAL_WAIT_START_REQ = 3'h1,
        RXCLKCAL_SEND_START_RESP= 3'h2,
        RXCLKCAL_PARTNER_IQ_LOOP= 3'h3,
        RXCLKCAL_SEND_DONE_RESP = 3'h4,
        TO_VALTRAINCENTER_RESP  = 3'h5,
        TO_TRAINERROR_RESP      = 3'h6
    } state_t;

    state_t current_state, next_state;

    // State-based clock active register
    logic tx_clk_active_r;

    // ============================================================================
    // State Transitions
    // ============================================================================
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= RXCLKCAL_PTR_IDLE;
        end
        else if (!is_ltsm_out_of_reset) begin
            current_state <= RXCLKCAL_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;

        // Global Error Override
        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = TO_TRAINERROR_RESP;
        end
        else begin
            case (current_state)
                RXCLKCAL_PTR_IDLE: begin
                    if (rxclkcal_partner_en) next_state = RXCLKCAL_WAIT_START_REQ;
                    else                     next_state = RXCLKCAL_PTR_IDLE;
                end

                RXCLKCAL_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_start_req)
                        next_state = RXCLKCAL_SEND_START_RESP;
                    else
                        next_state = RXCLKCAL_WAIT_START_REQ;
                end

                RXCLKCAL_SEND_START_RESP: begin
                    next_state = RXCLKCAL_PARTNER_IQ_LOOP;
                end

                RXCLKCAL_PARTNER_IQ_LOOP: begin
                    if (iq_partner_done) begin
                        if (iq_partner_error)
                            next_state = TO_TRAINERROR_RESP;
                        else
                            next_state = RXCLKCAL_SEND_DONE_RESP;
                    end
                    else begin
                        next_state = RXCLKCAL_PARTNER_IQ_LOOP;
                    end
                end

                RXCLKCAL_SEND_DONE_RESP: begin
                    next_state = TO_VALTRAINCENTER_RESP;
                end

                TO_VALTRAINCENTER_RESP: begin
                    next_state = (rxclkcal_partner_en) ? TO_VALTRAINCENTER_RESP : RXCLKCAL_PTR_IDLE;
                end

                TO_TRAINERROR_RESP: begin
                    next_state = (rxclkcal_partner_en) ? TO_TRAINERROR_RESP : RXCLKCAL_PTR_IDLE;
                end

                default: next_state = RXCLKCAL_PTR_IDLE;
            endcase
        end
    end

    // ============================================================================
    // Clock Forwarding State Tracking Register
    // ============================================================================
    // Tracks whether the Clock Transmitters on the Partner (Responder) die are
    // actively forwarding clock and track signals to the Local die.
    //
    // Specification Context (Section 4.5.3.4.5 MBTRAIN.RXCLKCAL):
    // 1. When entering MBTRAIN.RXCLKCAL, if the speed is <= 32 GT/s and Strobe mode
    //    is advertised, the Clock Transmitters are held low.
    // 2. Upon receiving the {MBTRAIN.RXCLKCAL start req} sideband message, the
    //    Partner starts sending the forwarded clock and track (tx_clk_active_r = 1).
    // 3. Upon receiving the {MBTRAIN.RXCLKCAL done req} sideband message:
    //    - If operating speed <= 32 GT/s AND Strobe mode was advertised
    //      (!is_high_speed && !is_continuous_clk_mode), the partner stops sending
    //      the forwarded clock and track, holding them low (tx_clk_active_r = 0).
    //    - If operating speed > 32 GT/s OR Continuous clock mode was advertised,
    //      the partner must continue sending the free-running clock (so tx_clk_active_r
    //      remains unchanged or clk_active logic enforces that they stay free-running).
    // 4. When Partner calibration is not active (rxclkcal_partner_en = 0), this
    //    tracking register resets to 1'b0.
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            tx_clk_active_r <= 1'b0;
        end
        else if (!is_ltsm_out_of_reset) begin
            tx_clk_active_r <= 1'b0;
        end
        else if (rxclkcal_partner_en) begin
            if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_start_req) begin
                tx_clk_active_r <= 1'b1;
            end
            else if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_RXCLKCAL_done_req) begin
                // Stop clock forwarding only if speed is low and strobe mode is active.
                if (!is_high_speed && !is_continuous_clk_mode) begin
                    tx_clk_active_r <= 1'b0;
                end
            end
        end
        else if(next_state == RXCLKCAL_PTR_IDLE && current_state != RXCLKCAL_PTR_IDLE)begin
            tx_clk_active_r <= 1'b0;
        end
    end

    // Clock active logic
    logic clk_active;
    assign clk_active = tx_clk_active_r | is_high_speed | is_continuous_clk_mode;

    // ============================================================================
    // Output Logic
    // ============================================================================
    always_comb begin
        // Safe Defaults
        rxclkcal_partner_done  = 1'b0;
        trainerror_req         = 1'b0;
        iq_partner_en          = 1'b0;

        tx_sb_msg_valid        = 1'b0;
        tx_sb_msg              = NOTHING;
        tx_msginfo             = 16'h0;
        tx_data_field          = 64'h0;

        case (current_state)
            RXCLKCAL_PTR_IDLE: begin
                // Idle state
            end

            RXCLKCAL_WAIT_START_REQ: begin
                // Waiting for partner start request
            end

            RXCLKCAL_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXCLKCAL_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            RXCLKCAL_PARTNER_IQ_LOOP: begin
                iq_partner_en = 1'b1;
            end

            RXCLKCAL_SEND_DONE_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_RXCLKCAL_done_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            TO_VALTRAINCENTER_RESP: begin
                rxclkcal_partner_done = 1'b1;
            end

            TO_TRAINERROR_RESP: begin
                rxclkcal_partner_done = 1'b1;
                trainerror_req        = 1'b1;
            end
        endcase
    end

    // Transmitter Select Controls
    assign mb_tx_clk_lane_sel = clk_active ? 2'b01 : 2'b00;
    assign mb_tx_trk_lane_sel = clk_active ? 2'b01 : 2'b00;
    assign mb_tx_pattern_en   = clk_active;

endmodule
