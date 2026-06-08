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
        input  logic        is_ltsm_out_of_reset, 
        input  logic        timeout_8ms_occured , 
        output logic        datatraincenter2_done, 
        output logic        trainerror_req      , 

        //=====================================//
        // Timer Control Signals:              //
        //=====================================//
        output logic        timeout_timer_en    , 

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
    localparam [3:0]
    DTC2_PTR_IDLE            = 4'd0,  
    DTC2_PTR_WAIT_START_REQ  = 4'd1,  
    DTC2_PTR_SEND_START_RESP = 4'd2,  
    DTC2_PTR_WAIT_END_REQ    = 4'd3,  
    DTC2_PTR_SEND_END_RESP   = 4'd4,  
    DTC2_PTR_TO_LINKSPEED    = 4'd5,  
    DTC2_PTR_TO_TRAINERROR   = 4'd6;  

    reg [3:0] current_state, next_state;

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= DTC2_PTR_IDLE;
        end
        else if (!is_ltsm_out_of_reset) begin
            current_state <= DTC2_PTR_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC
        next_state = current_state;

        if (timeout_8ms_occured ||
                (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req)) begin
            next_state = DTC2_PTR_TO_TRAINERROR;
        end
        else if (!datatraincenter2_en &&
                 current_state != DTC2_PTR_TO_LINKSPEED &&
                 current_state != DTC2_PTR_TO_TRAINERROR) begin
            next_state = DTC2_PTR_IDLE;
        end
        else begin
            case (current_state)
                DTC2_PTR_IDLE: begin
                    next_state = datatraincenter2_en ? DTC2_PTR_WAIT_START_REQ : DTC2_PTR_IDLE;
                end

                DTC2_PTR_WAIT_START_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER2_start_req) begin
                        next_state = DTC2_PTR_SEND_START_RESP;
                    end
                end

                DTC2_PTR_SEND_START_RESP: begin
                    next_state = DTC2_PTR_WAIT_END_REQ;
                end

                DTC2_PTR_WAIT_END_REQ: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER2_end_req) begin
                        next_state = DTC2_PTR_SEND_END_RESP;
                    end
                end

                DTC2_PTR_SEND_END_RESP: begin
                    next_state = DTC2_PTR_TO_LINKSPEED;
                end

                DTC2_PTR_TO_LINKSPEED: begin
                    next_state = datatraincenter2_en ? DTC2_PTR_TO_LINKSPEED : DTC2_PTR_IDLE;
                end

                DTC2_PTR_TO_TRAINERROR: begin
                    next_state = datatraincenter2_en ? DTC2_PTR_TO_TRAINERROR : DTC2_PTR_IDLE;
                end

                default: begin
                    next_state = DTC2_PTR_IDLE;
                end
            endcase
        end
    end

    always_comb begin : OUTPUT_COMB
        datatraincenter2_done = 1'b0;
        trainerror_req      = 1'b0;
        timeout_timer_en    = 1'b1;
        partner_sweep_en    = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        mb_tx_clk_lane_sel  = 2'b01; 
        mb_tx_data_lane_sel = 2'b00; 
        mb_tx_val_lane_sel  = 2'b00; 
        mb_tx_trk_lane_sel  = 2'b00; 
        mb_rx_clk_lane_sel  = 1'b1;  
        mb_rx_data_lane_sel = 1'b1;  
        mb_rx_val_lane_sel  = 1'b1;  
        mb_rx_trk_lane_sel  = 1'b0;  

        case (current_state)
            DTC2_PTR_IDLE: begin
                timeout_timer_en    = 1'b0;
                mb_tx_clk_lane_sel  = 2'b00;
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
            end

            DTC2_PTR_WAIT_START_REQ: begin
                tx_sb_msg_valid = 1'b0;
            end

            DTC2_PTR_SEND_START_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_start_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DTC2_PTR_WAIT_END_REQ: begin
                tx_sb_msg_valid  = 1'b0;
                partner_sweep_en = 1'b1;
            end

            DTC2_PTR_SEND_END_RESP: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_end_resp;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DTC2_PTR_TO_LINKSPEED: begin
                datatraincenter2_done = 1'b1;
                timeout_timer_en       = 1'b0;
            end

            DTC2_PTR_TO_TRAINERROR: begin
                datatraincenter2_done = 1'b1;
                trainerror_req         = 1'b1;
                timeout_timer_en       = 1'b0;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

endmodule


