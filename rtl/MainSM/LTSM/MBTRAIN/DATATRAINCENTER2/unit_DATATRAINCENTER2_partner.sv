// unit_DATATRAINCENTER2_partner.sv — MBTRAIN.DATATRAINCENTER2 PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled DATATRAINCENTER2 implementation.
//
// Role:
//   - Waits for Request SB messages from the partner die's LOCAL FSM
//   - Sends Response SB messages back to the partner die
//   - Holds MB lanes in the correct posture while the partner's LOCAL die
//     performs its TX PI centering sweep.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.DATATRAINCENTER2 (Partner — Responder):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.DATATRAINCENTER2 start req}     | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER2 start resp}    | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER2 end req}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER2 end resp}      | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.11 MBTRAIN.DATATRAINCENTER2

module unit_DATATRAINCENTER2_partner (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,
        input  logic        rst_n,

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        datatraincenter2_en ,
        input  logic        soft_rst_n          ,
        output logic        datatraincenter2_done,

        // MB RX Lane Control: moved to wrapper_DATATRAINCENTER2 as static assigns
        // (spec §4.5.3.4.11: RX CLK=1, DATA=1, VAL=1, TRK=0)
        // output logic        mb_rx_clk_lane_sel  ,
        // output logic        mb_rx_data_lane_sel ,
        // output logic        mb_rx_val_lane_sel  ,
        // output logic        mb_rx_trk_lane_sel  ,

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
        input  logic [7:0]  rx_sb_msg
        // input  logic [15:0] rx_msginfo          ,
        // input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    // FSM State Encoding
    localparam [2:0]
    DATATRAINCENTER2_PTR_IDLE            = 3'd0,
    DATATRAINCENTER2_PTR_WAIT_START_REQ  = 3'd1,
    DATATRAINCENTER2_PTR_SEND_START_RESP = 3'd2,
    DATATRAINCENTER2_PTR_WAIT_END_REQ    = 3'd3,
    DATATRAINCENTER2_PTR_SEND_END_RESP   = 3'd4,
    DATATRAINCENTER2_PTR_TO_LINKSPEED    = 3'd5;

    reg [2:0] current_state, next_state;

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= DATATRAINCENTER2_PTR_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= DATATRAINCENTER2_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC
        next_state = current_state;

        if (!datatraincenter2_en) begin
            next_state = DATATRAINCENTER2_PTR_IDLE;
        end
        else begin
            case (current_state)
                DATATRAINCENTER2_PTR_IDLE: begin
                    next_state = DATATRAINCENTER2_PTR_WAIT_START_REQ;
                end

                DATATRAINCENTER2_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER2_start_req) begin
                        next_state = DATATRAINCENTER2_PTR_SEND_START_RESP;
                    end
                end

                DATATRAINCENTER2_PTR_SEND_START_RESP: begin
                    next_state = DATATRAINCENTER2_PTR_WAIT_END_REQ;
                end

                DATATRAINCENTER2_PTR_WAIT_END_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER2_end_req) begin
                        next_state = DATATRAINCENTER2_PTR_SEND_END_RESP;
                    end
                end

                DATATRAINCENTER2_PTR_SEND_END_RESP: begin
                    next_state = DATATRAINCENTER2_PTR_TO_LINKSPEED;
                end

                DATATRAINCENTER2_PTR_TO_LINKSPEED: begin
                    next_state = DATATRAINCENTER2_PTR_TO_LINKSPEED;
                end

                default: begin
                    next_state = DATATRAINCENTER2_PTR_IDLE;
                end
            endcase
        end
    end

    always_comb begin : OUTPUT_COMB
        datatraincenter2_done = 1'b0;
        partner_sweep_en    = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB RX signals moved to wrapper as static assigns (CLK=1, DATA=1, VAL=1, TRK=0)

        case (current_state)
            DATATRAINCENTER2_PTR_IDLE: begin end

            DATATRAINCENTER2_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            DATATRAINCENTER2_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DATATRAINCENTER2_PTR_WAIT_END_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
            end

            DATATRAINCENTER2_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DATATRAINCENTER2_PTR_TO_LINKSPEED: begin
                datatraincenter2_done = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


