// unit_VALTRAINCENTER_partner.sv — MBTRAIN.VALTRAINCENTER PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled VALTRAINCENTER implementation.
//
// Role:
//   - Waits for Request SB messages from the partner die's LOCAL FSM
//   - Sends Response SB messages back to the partner die
//   - Holds MB TX lanes in the correct posture (VALTRAIN pattern) while
//     the partner's LOCAL die performs its valid centering sweep
//
// Architecture: Single-FSM, WAIT → SEND pattern (exact mirror of Local SEND→WAIT).
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.VALTRAINCENTER (Partner — Responder):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.VALTRAINCENTER start req}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALTRAINCENTER start resp}      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALTRAINCENTER done req}        | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALTRAINCENTER done resp}       | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_VALTRAINCENTER_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,               // LTSM clock domain.
        input  logic        rst_n,               // 0: Asynchronous reset → IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        valtraincenter_en   , // 0: Disable. 1: Enable/start sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        valtraincenter_done , // 1: Sub-state completed; held until valtraincenter_en = 0.
        output logic        trainerror_req      , // 1: Fatal error — request TRAINERROR state.

        //=====================================//
        // MB Lane Control Configuration:       //
        //=====================================//
        input  logic        mb_tx_continuous_or_strobe_clk,
        input  logic [2:0]  phy_negotiated_speed          ,

        //=====================================//
        // MB Lane Control Outputs:            //
        //=====================================//
        output logic [1:0]  mb_tx_clk_lane_sel  ,
        output logic [1:0]  mb_tx_data_lane_sel ,
        output logic [1:0]  mb_tx_val_lane_sel  ,
        output logic [1:0]  mb_tx_trk_lane_sel  ,
        output logic        mb_rx_clk_lane_sel  ,
        output logic        mb_rx_data_lane_sel ,
        output logic        mb_rx_val_lane_sel  ,
        output logic        mb_rx_trk_lane_sel  ,

        //=====================================//
        // Partner Sweep Enable:               //
        //=====================================//
        output logic        partner_sweep_en    , // 1: Hold partner TX pattern active.

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        output logic        tx_sb_msg_valid     , // Exactly 1 lclk cycle per message.
        output logic [7:0]  tx_sb_msg           , // MsgCode to transmit.
        output logic [15:0] tx_msginfo          , // MsgInfo payload.
        output logic [63:0] tx_data_field       , // 64-bit data payload.

        input  logic        rx_sb_msg_valid     , // Pulse (1 lclk) when a valid SB msg is received.
        input  logic [7:0]  rx_sb_msg           , // Received MsgCode from partner die.
        input  logic [15:0] rx_msginfo          , // Received MsgInfo payload.
        input  logic [63:0] rx_data_field         // Received 64-bit data payload.
    );

    import UCIe_pkg::*;

    // FSM State Encoding — WAIT → SEND pattern
    localparam [3:0]
    VALTRAINCENTER_PTR_IDLE            = 4'd0,  // Wait for valtraincenter_en
    VALTRAINCENTER_PTR_WAIT_START_REQ  = 4'd1,  // Wait for {MBTRAIN.VALTRAINCENTER start req}
    VALTRAINCENTER_PTR_SEND_START_RESP = 4'd2,  // TX {MBTRAIN.VALTRAINCENTER start resp}
    VALTRAINCENTER_PTR_WAIT_DONE_REQ   = 4'd3,  // Wait for {MBTRAIN.VALTRAINCENTER done req}
    VALTRAINCENTER_PTR_SEND_DONE_RESP  = 4'd4,  // TX {MBTRAIN.VALTRAINCENTER done resp}
    VALTRAINCENTER_PTR_TO_VALTRAINVREF = 4'd5,  // Terminal: completed
    VALTRAINCENTER_PTR_TO_TRAINERROR   = 4'd6;  // Terminal: error

    reg [3:0] current_state, next_state;

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= VALTRAINCENTER_PTR_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= VALTRAINCENTER_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC
        next_state = current_state;

        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = VALTRAINCENTER_PTR_TO_TRAINERROR;
        end
        else if (!valtraincenter_en) begin
            next_state = VALTRAINCENTER_PTR_IDLE;
        end
        else begin
            case (current_state)
                VALTRAINCENTER_PTR_IDLE: begin
                    next_state = valtraincenter_en ? VALTRAINCENTER_PTR_WAIT_START_REQ : VALTRAINCENTER_PTR_IDLE;
                end

                VALTRAINCENTER_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALTRAINCENTER_start_req) begin
                        next_state = VALTRAINCENTER_PTR_SEND_START_RESP;
                    end
                end

                VALTRAINCENTER_PTR_SEND_START_RESP: begin
                    next_state = VALTRAINCENTER_PTR_WAIT_DONE_REQ;
                end

                VALTRAINCENTER_PTR_WAIT_DONE_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALTRAINCENTER_done_req) begin
                        next_state = VALTRAINCENTER_PTR_SEND_DONE_RESP;
                    end
                end

                VALTRAINCENTER_PTR_SEND_DONE_RESP: begin
                    next_state = VALTRAINCENTER_PTR_TO_VALTRAINVREF;
                end

                VALTRAINCENTER_PTR_TO_VALTRAINVREF: begin
                    next_state = valtraincenter_en ? VALTRAINCENTER_PTR_TO_VALTRAINVREF : VALTRAINCENTER_PTR_IDLE;
                end

                VALTRAINCENTER_PTR_TO_TRAINERROR: begin
                    next_state = valtraincenter_en ? VALTRAINCENTER_PTR_TO_TRAINERROR : VALTRAINCENTER_PTR_IDLE;
                end

                default: begin
                    next_state = VALTRAINCENTER_PTR_IDLE;
                end
            endcase
        end
    end

    always_comb begin : OUTPUT_COMB
        valtraincenter_done = 1'b0;
        trainerror_req      = 1'b0;
        partner_sweep_en    = 1'b0;

        tx_sb_msg_valid     = 1'b0;
        tx_sb_msg           = NOTHING;
        tx_msginfo          = 16'h0;
        tx_data_field       = 64'h0;

        // Default MB lane select behaviors based on spec for VALTRAINCENTER active states.
        // During active training/gating actions, clock TX must be active center-phase (2'b01)
        // and Valid TX must be active pattern (2'b01).
        mb_tx_clk_lane_sel  = 2'b01;
        mb_tx_data_lane_sel = 2'b00;
        mb_tx_val_lane_sel  = 2'b01; // Partner drives VALTRAIN pattern
        mb_tx_trk_lane_sel  = 2'b00;
        mb_rx_clk_lane_sel  = 1'b1;
        mb_rx_data_lane_sel = 1'b1;
        mb_rx_val_lane_sel  = 1'b1;
        mb_rx_trk_lane_sel  = 1'b0;

        case (current_state)
            VALTRAINCENTER_PTR_IDLE: begin
                mb_tx_clk_lane_sel  = (mb_tx_continuous_or_strobe_clk && phy_negotiated_speed <= 3'b101) ? 2'b00 : 2'b01;
                mb_tx_val_lane_sel  = 2'b00;
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
            end

            VALTRAINCENTER_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            VALTRAINCENTER_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALTRAINCENTER_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            VALTRAINCENTER_PTR_WAIT_DONE_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
            end

            VALTRAINCENTER_PTR_SEND_DONE_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALTRAINCENTER_done_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            VALTRAINCENTER_PTR_TO_VALTRAINVREF: begin
                valtraincenter_done = 1'b1;
                mb_tx_clk_lane_sel  = (mb_tx_continuous_or_strobe_clk && phy_negotiated_speed <= 3'b101) ? 2'b00 : 2'b01;
            end

            VALTRAINCENTER_PTR_TO_TRAINERROR: begin
                valtraincenter_done = 1'b1;
                trainerror_req      = 1'b1;
                mb_tx_clk_lane_sel  = 2'b00;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


