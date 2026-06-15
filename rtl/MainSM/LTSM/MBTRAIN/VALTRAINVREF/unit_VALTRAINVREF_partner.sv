// unit_VALTRAINVREF_partner.sv — MBTRAIN.VALTRAINVREF PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled VALTRAINVREF implementation.
//
// Role:
//   - Waits for Request SB messages from the partner die's LOCAL FSM
//   - Sends Response SB messages back to the partner die
//   - Holds MB TX lanes in the correct posture (VALTRAIN pattern) while
//     the partner's LOCAL die performs its Vref optimization sweep
//
// Architecture: Single-FSM, WAIT → SEND pattern (exact mirror of Local SEND→WAIT).

module unit_VALTRAINVREF_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,               // LTSM clock domain.
        input  logic        rst_n,               // 0: Asynchronous reset → IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        valtrainvref_en     , // 0: Disable. 1: Enable/start sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        valtrainvref_done   , // 1: Sub-state completed; held until valtrainvref_en = 0.
        output logic        trainerror_req      , // 1: Fatal error — request TRAINERROR state.

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
    VALTRAINVREF_PTR_IDLE                = 4'd0,  // Wait for valtrainvref_en
    VALTRAINVREF_PTR_WAIT_START_REQ      = 4'd1,  // Wait for {MBTRAIN.VALTRAINVREF start req}
    VALTRAINVREF_PTR_SEND_START_RESP     = 4'd2,  // TX {MBTRAIN.VALTRAINVREF start resp}
    VALTRAINVREF_PTR_WAIT_END_REQ        = 4'd3,  // Wait for {MBTRAIN.VALTRAINVREF end req}
    VALTRAINVREF_PTR_SEND_END_RESP       = 4'd4,  // TX {MBTRAIN.VALTRAINVREF end resp}
    VALTRAINVREF_PTR_TO_DATATRAINCENTER1 = 4'd5,  // Terminal: completed (next DTC1)
    VALTRAINVREF_PTR_TO_TRAINERROR       = 4'd6;  // Terminal: error

    reg [3:0] current_state, next_state;

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= VALTRAINVREF_PTR_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= VALTRAINVREF_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC
        next_state = current_state;

        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = VALTRAINVREF_PTR_TO_TRAINERROR;
        end
        else if (!valtrainvref_en) begin
            next_state = VALTRAINVREF_PTR_IDLE;
        end
        else begin
            case (current_state)
                VALTRAINVREF_PTR_IDLE: begin
                    next_state = valtrainvref_en ? VALTRAINVREF_PTR_WAIT_START_REQ : VALTRAINVREF_PTR_IDLE;
                end

                VALTRAINVREF_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALTRAINVREF_start_req) begin
                        next_state = VALTRAINVREF_PTR_SEND_START_RESP;
                    end
                end

                VALTRAINVREF_PTR_SEND_START_RESP: begin
                    next_state = VALTRAINVREF_PTR_WAIT_END_REQ;
                end

                VALTRAINVREF_PTR_WAIT_END_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALTRAINVREF_end_req) begin
                        next_state = VALTRAINVREF_PTR_SEND_END_RESP;
                    end
                end

                VALTRAINVREF_PTR_SEND_END_RESP: begin
                    next_state = VALTRAINVREF_PTR_TO_DATATRAINCENTER1;
                end

                VALTRAINVREF_PTR_TO_DATATRAINCENTER1: begin
                    next_state = valtrainvref_en ? VALTRAINVREF_PTR_TO_DATATRAINCENTER1 : VALTRAINVREF_PTR_IDLE;
                end

                VALTRAINVREF_PTR_TO_TRAINERROR: begin
                    next_state = valtrainvref_en ? VALTRAINVREF_PTR_TO_TRAINERROR : VALTRAINVREF_PTR_IDLE;
                end

                default: begin
                    next_state = VALTRAINVREF_PTR_IDLE;
                end
            endcase
        end
    end

    always_comb begin : OUTPUT_COMB
        valtrainvref_done = 1'b0;
        trainerror_req    = 1'b0;
        partner_sweep_en  = 1'b0;

        tx_sb_msg_valid   = 1'b0;
        tx_sb_msg         = NOTHING;
        tx_msginfo        = 16'h0;
        tx_data_field     = 64'h0;

        mb_tx_clk_lane_sel  = 2'b01; // Active center-phase clock TX
        mb_tx_data_lane_sel = 2'b00;
        mb_tx_val_lane_sel  = 2'b01; // Active Valid TX (VALTRAIN pattern)
        mb_tx_trk_lane_sel  = 2'b00;
        mb_rx_clk_lane_sel  = 1'b1;
        mb_rx_data_lane_sel = 1'b1;
        mb_rx_val_lane_sel  = 1'b1;
        mb_rx_trk_lane_sel  = 1'b0;

        case (current_state)
            VALTRAINVREF_PTR_IDLE: begin
                mb_tx_clk_lane_sel  = 2'b00;
                mb_tx_val_lane_sel  = 2'b00;
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
            end

            VALTRAINVREF_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            VALTRAINVREF_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALTRAINVREF_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            VALTRAINVREF_PTR_WAIT_END_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
            end

            VALTRAINVREF_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALTRAINVREF_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            VALTRAINVREF_PTR_TO_DATATRAINCENTER1: begin
                valtrainvref_done = 1'b1;
            end

            VALTRAINVREF_PTR_TO_TRAINERROR: begin
                valtrainvref_done = 1'b1;
                trainerror_req    = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


