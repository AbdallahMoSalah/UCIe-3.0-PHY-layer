// unit_DATATRAINVREF_partner.sv — MBTRAIN.DATATRAINVREF PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled DATATRAINVREF implementation.
//
// Role:
//   - Waits for Request SB messages from the partner die's LOCAL FSM
//   - Sends Response SB messages back to the partner die
//   - Holds MB lanes in the correct posture while the partner's LOCAL die
//     performs its RX Vref sweep.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.DATATRAINVREF (Partner — Responder):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.DATATRAINVREF start req}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINVREF start resp}      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINVREF end req}         | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINVREF end resp}        | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.9 MBTRAIN.DATATRAINVREF


module unit_DATATRAINVREF_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,
        input  logic        rst_n,

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        datatrainvref_en    ,
        input  logic        soft_rst_n          ,
        output logic        datatrainvref_done  ,
        // output logic        trainerror_req      ,

        // MB TX Lane Control: moved to wrapper_DATATRAINVREF as static assigns
        // (spec §4.5.3.4.9: CLK TX=01, DATA/VAL/TRK TX=00)
        // output logic [1:0]  mb_tx_clk_lane_sel  ,
        // output logic [1:0]  mb_tx_data_lane_sel ,
        // output logic [1:0]  mb_tx_val_lane_sel  ,
        // output logic [1:0]  mb_tx_trk_lane_sel  ,

        //=====================================//
        // Partner Sweep Enable:               //
        //=====================================//
        output logic        partner_sweep_en    ,

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        output logic        tx_sb_msg_valid     ,
        output logic [7:0]  tx_sb_msg           ,
        output logic [15:0] tx_msginfo          ,
        output logic [63:0] tx_data_field       ,

        input  logic        rx_sb_msg_valid     ,
        input  logic [7:0]  rx_sb_msg           ,
        input  logic [15:0] rx_msginfo          ,
        input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    // FSM State Encoding
    localparam [2:0]
    DATATRAINVREF_PTR_IDLE            = 3'd0,
    DATATRAINVREF_PTR_WAIT_START_REQ  = 3'd1,
    DATATRAINVREF_PTR_SEND_START_RESP = 3'd2,
    DATATRAINVREF_PTR_WAIT_END_REQ    = 3'd3,
    DATATRAINVREF_PTR_SEND_END_RESP   = 3'd4,
    DATATRAINVREF_PTR_TO_RXDESKEW     = 3'd5;
    // DATATRAINVREF_PTR_TO_TRAINERROR   = 3'd6;

    reg [2:0] current_state, next_state;

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC_PTR
        if (!rst_n) begin
            current_state <= DATATRAINVREF_PTR_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= DATATRAINVREF_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC_PTR
        next_state = current_state;

        if (!datatrainvref_en) begin
            next_state = DATATRAINVREF_PTR_IDLE;
        end
        else begin
            case (current_state)
                DATATRAINVREF_PTR_IDLE: begin
                    next_state = DATATRAINVREF_PTR_WAIT_START_REQ;
                end

                DATATRAINVREF_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINVREF_start_req) begin
                        next_state = DATATRAINVREF_PTR_SEND_START_RESP;
                    end
                end

                DATATRAINVREF_PTR_SEND_START_RESP: begin
                    next_state = DATATRAINVREF_PTR_WAIT_END_REQ;
                end

                DATATRAINVREF_PTR_WAIT_END_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINVREF_end_req) begin
                        next_state = DATATRAINVREF_PTR_SEND_END_RESP;
                    end
                end

                DATATRAINVREF_PTR_SEND_END_RESP: begin
                    next_state = DATATRAINVREF_PTR_TO_RXDESKEW;
                end

                DATATRAINVREF_PTR_TO_RXDESKEW: begin
                    next_state = DATATRAINVREF_PTR_TO_RXDESKEW;
                end

                // DATATRAINVREF_PTR_TO_TRAINERROR: begin
                //     next_state = DATATRAINVREF_PTR_TO_TRAINERROR;
                // end

                default: begin
                    next_state = DATATRAINVREF_PTR_IDLE;
                end
            endcase
        end
    end

    always_comb begin : OUTPUT_COMB_PTR
        datatrainvref_done = 1'b0;
        // trainerror_req      = 1'b0;
        partner_sweep_en    = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB TX signals moved to wrapper as static assigns (CLK=01, DATA/VAL/TRK=00)

        case (current_state)
            DATATRAINVREF_PTR_IDLE: begin end

            DATATRAINVREF_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            DATATRAINVREF_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINVREF_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DATATRAINVREF_PTR_WAIT_END_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
            end

            DATATRAINVREF_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINVREF_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DATATRAINVREF_PTR_TO_RXDESKEW: begin
                datatrainvref_done = 1'b1;
            end

            // DATATRAINVREF_PTR_TO_TRAINERROR: begin
            //     datatrainvref_done = 1'b1;
            //     trainerror_req      = 1'b1;
            // end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


