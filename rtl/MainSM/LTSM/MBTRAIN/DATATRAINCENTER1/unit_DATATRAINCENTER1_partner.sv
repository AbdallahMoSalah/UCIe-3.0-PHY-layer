// unit_DATATRAINCENTER1_partner.sv — MBTRAIN.DATATRAINCENTER1 PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled DATATRAINCENTER1 implementation.
//
// Role:
//   - Waits for Request SB messages from the partner die's LOCAL FSM
//   - Sends Response SB messages back to the partner die
//   - Holds MB lanes in the correct posture while the partner's LOCAL die
//     performs its TX PI centering sweep.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.DATATRAINCENTER1 (Partner — Responder):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.DATATRAINCENTER1 start req}     | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER1 start resp}    | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER1 end req}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER1 end resp}      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.8 MBTRAIN.DATATRAINCENTER1

module unit_DATATRAINCENTER1_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,               // LTSM clock domain
        input  logic        rst_n,               // 0: Asynchronous reset → IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        datatraincenter1_en , // 0: Disable (→ IDLE immediately). 1: Enable sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        datatraincenter1_done, // 1: Sub-state completed; held until datatraincenter1_en = 0.
        // output logic        trainerror_req      , // 1: Fatal error — request TRAINERROR state.

        // MB RX Lane Control: moved to wrapper_DATATRAINCENTER1 as static assigns
        // (spec §4.5.3.4.8: RX CLK=1, DATA=1, VAL=1, TRK=0)
        // output logic        mb_rx_clk_lane_sel  ,
        // output logic        mb_rx_data_lane_sel ,
        // output logic        mb_rx_val_lane_sel  ,
        // output logic        mb_rx_trk_lane_sel  ,

        //=====================================//
        // Partner Sweep Enable:               //
        //=====================================//
        output logic        partner_sweep_en    , // 1: Hold partner MB active.

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        output logic        tx_sb_msg_valid     , // Exactly 1 lclk cycle per message.
        output logic [7:0]  tx_sb_msg           , // MsgCode to transmit.
        output logic [15:0] tx_msginfo          , // MsgInfo payload.
        output logic [63:0] tx_data_field       , // 64-bit data payload.

        input  logic        rx_sb_msg_valid     , // Pulse when a valid SB msg is received.
        input  logic [7:0]  rx_sb_msg             // Received MsgCode.
        // input  logic [15:0] rx_msginfo          , // Received MsgInfo payload.
        // input  logic [63:0] rx_data_field         // Received 64-bit data payload.
    );

    import UCIe_pkg::*;

    // FSM State Encoding
    localparam [2:0]
    DATATRAINCENTER1_PTR_IDLE                = 3'd0,  // Wait for en
    DATATRAINCENTER1_PTR_WAIT_START_REQ      = 3'd1,  // Wait for {start req}
    DATATRAINCENTER1_PTR_SEND_START_RESP     = 3'd2,  // TX {start resp}
    DATATRAINCENTER1_PTR_WAIT_END_REQ        = 3'd3,  // Wait while Local sweeps
    DATATRAINCENTER1_PTR_SEND_END_RESP       = 3'd4,  // TX {end resp}
    DATATRAINCENTER1_PTR_TO_DATATRAINVREF    = 3'd5;  // Terminal: completed
    // DATATRAINCENTER1_PTR_TO_TRAINERROR       = 4'd6;  // Terminal: error

    reg [2:0] current_state, next_state;

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC_PTR
        if (!rst_n) begin
            current_state <= DATATRAINCENTER1_PTR_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= DATATRAINCENTER1_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC_PTR
        next_state = current_state;

        if (!datatraincenter1_en) begin
            next_state = DATATRAINCENTER1_PTR_IDLE;
        end
        else begin
            case (current_state)
                DATATRAINCENTER1_PTR_IDLE: begin
                    next_state = DATATRAINCENTER1_PTR_WAIT_START_REQ;
                end

                DATATRAINCENTER1_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER1_start_req) begin
                        next_state = DATATRAINCENTER1_PTR_SEND_START_RESP;
                    end
                end

                DATATRAINCENTER1_PTR_SEND_START_RESP: begin
                    next_state = DATATRAINCENTER1_PTR_WAIT_END_REQ;
                end

                DATATRAINCENTER1_PTR_WAIT_END_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER1_end_req) begin
                        next_state = DATATRAINCENTER1_PTR_SEND_END_RESP;
                    end
                end

                DATATRAINCENTER1_PTR_SEND_END_RESP: begin
                    next_state = DATATRAINCENTER1_PTR_TO_DATATRAINVREF;
                end

                DATATRAINCENTER1_PTR_TO_DATATRAINVREF: begin
                    next_state = DATATRAINCENTER1_PTR_TO_DATATRAINVREF;
                end

                // DATATRAINCENTER1_PTR_TO_TRAINERROR: begin
                //     next_state = DATATRAINCENTER1_PTR_TO_TRAINERROR;
                // end

                default: begin
                    next_state = DATATRAINCENTER1_PTR_IDLE;
                end
            endcase
        end
    end

    always_comb begin : OUTPUT_COMB_PTR
        datatraincenter1_done = 1'b0;
        // trainerror_req         = 1'b0;
        partner_sweep_en       = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB RX signals moved to wrapper as static assigns (CLK=1, DATA=1, VAL=1, TRK=0)

        case (current_state)
            DATATRAINCENTER1_PTR_IDLE: begin end

            DATATRAINCENTER1_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            DATATRAINCENTER1_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DATATRAINCENTER1_PTR_WAIT_END_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
            end

            DATATRAINCENTER1_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DATATRAINCENTER1_PTR_TO_DATATRAINVREF: begin
                datatraincenter1_done = 1'b1;
            end

            // DATATRAINCENTER1_PTR_TO_TRAINERROR: begin
            //     datatraincenter1_done = 1'b1;
            //     trainerror_req        = 1'b1;
            // end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


