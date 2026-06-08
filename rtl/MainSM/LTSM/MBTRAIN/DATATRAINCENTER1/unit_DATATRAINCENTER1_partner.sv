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
        input  logic        is_ltsm_out_of_reset, // 0: Soft-reset active. 1: Normal.
        input  logic        timeout_8ms_occured , // 1: 8ms residency timeout → force TO_TRAINERROR.
        output logic        datatraincenter1_done, // 1: Sub-state completed; held until datatraincenter1_en = 0.
        output logic        trainerror_req      , // 1: Fatal error — request TRAINERROR state.

        //=====================================//
        // Timer Control Signals:              //
        //=====================================//
        output logic        timeout_timer_en    , // 1: Enable 8ms watchdog. 0: Disable.

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
        output logic        partner_sweep_en    , // 1: Hold partner MB active.

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        output logic        tx_sb_msg_valid     , // Exactly 1 lclk cycle per message.
        output logic [7:0]  tx_sb_msg           , // MsgCode to transmit.
        output logic [15:0] tx_msginfo          , // MsgInfo payload.
        output logic [63:0] tx_data_field       , // 64-bit data payload.

        input  logic        rx_sb_msg_valid     , // Pulse when a valid SB msg is received.
        input  logic [7:0]  rx_sb_msg           , // Received MsgCode.
        input  logic [15:0] rx_msginfo          , // Received MsgInfo payload.
        input  logic [63:0] rx_data_field         // Received 64-bit data payload.
    );

    import UCIe_pkg::*;

    // FSM State Encoding
    localparam [3:0]
    DTC1_PTR_IDLE            = 4'd0,  // Wait for en
    DTC1_PTR_WAIT_START_REQ  = 4'd1,  // Wait for {start req}
    DTC1_PTR_SEND_START_RESP = 4'd2,  // TX {start resp}
    DTC1_PTR_WAIT_END_REQ    = 4'd3,  // Wait while Local sweeps
    DTC1_PTR_SEND_END_RESP   = 4'd4,  // TX {end resp}
    DTC1_PTR_TO_VREF         = 4'd5,  // Terminal: completed
    DTC1_PTR_TO_TRAINERROR   = 4'd6;  // Terminal: error

    reg [3:0] current_state, next_state;

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC_PTR
        if (!rst_n) begin
            current_state <= DTC1_PTR_IDLE;
        end
        else if (!is_ltsm_out_of_reset) begin
            current_state <= DTC1_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC_PTR
        next_state = current_state;

        if (timeout_8ms_occured ||
                (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req)) begin
            next_state = DTC1_PTR_TO_TRAINERROR;
        end
        else if (!datatraincenter1_en &&
                 current_state != DTC1_PTR_TO_VREF &&
                 current_state != DTC1_PTR_TO_TRAINERROR) begin
            next_state = DTC1_PTR_IDLE;
        end
        else begin
            case (current_state)
                DTC1_PTR_IDLE: begin
                    next_state = datatraincenter1_en ? DTC1_PTR_WAIT_START_REQ : DTC1_PTR_IDLE;
                end

                DTC1_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER1_start_req) begin
                        next_state = DTC1_PTR_SEND_START_RESP;
                    end
                end

                DTC1_PTR_SEND_START_RESP: begin
                    next_state = DTC1_PTR_WAIT_END_REQ;
                end

                DTC1_PTR_WAIT_END_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER1_end_req) begin
                        next_state = DTC1_PTR_SEND_END_RESP;
                    end
                end

                DTC1_PTR_SEND_END_RESP: begin
                    next_state = DTC1_PTR_TO_VREF;
                end

                DTC1_PTR_TO_VREF: begin
                    next_state = datatraincenter1_en ? DTC1_PTR_TO_VREF : DTC1_PTR_IDLE;
                end

                DTC1_PTR_TO_TRAINERROR: begin
                    next_state = datatraincenter1_en ? DTC1_PTR_TO_TRAINERROR : DTC1_PTR_IDLE;
                end

                default: begin
                    next_state = DTC1_PTR_IDLE;
                end
            endcase
        end
    end

    always_comb begin : OUTPUT_COMB_PTR
        datatraincenter1_done = 1'b0;
        trainerror_req         = 1'b0;
        timeout_timer_en       = 1'b1;
        partner_sweep_en       = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB lane defaults for partner die (RX die)
        mb_tx_clk_lane_sel  = 2'b01; // Active center-phase forwarded clock
        mb_tx_data_lane_sel = 2'b00; // Held Low
        mb_tx_val_lane_sel  = 2'b00; // Held Low
        mb_tx_trk_lane_sel  = 2'b00; // Held Low
        mb_rx_clk_lane_sel  = 1'b1;  // Enabled
        mb_rx_data_lane_sel = 1'b1;  // Enabled
        mb_rx_val_lane_sel  = 1'b1;  // Enabled
        mb_rx_trk_lane_sel  = 1'b0;  // Disabled

        case (current_state)
            DTC1_PTR_IDLE: begin
                timeout_timer_en    = 1'b0;
                mb_tx_clk_lane_sel  = 2'b00;
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
            end

            DTC1_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            DTC1_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DTC1_PTR_WAIT_END_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
            end

            DTC1_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER1_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DTC1_PTR_TO_VREF: begin
                datatraincenter1_done = 1'b1;
                timeout_timer_en       = 1'b0;
            end

            DTC1_PTR_TO_TRAINERROR: begin
                datatraincenter1_done = 1'b1;
                trainerror_req         = 1'b1;
                timeout_timer_en       = 1'b0;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


