// unit_DATATRAINVREF_local.sv — MBTRAIN.DATATRAINVREF LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled DATATRAINVREF implementation.
// The Local FSM:
//   - Sends Request SB messages to the partner die
//   - Waits for Response SB messages from the partner die
//   - Controls the external unit_D2C_sweep module via sweep_en/sweep_done
//   - Drives phy_rx_datavref_ctrl lanes during the sweep
//   - Registers best_code[lane] per lane after sweep_done
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.DATATRAINVREF (Local — Initiator):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.DATATRAINVREF start req}        | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINVREF start resp}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINVREF end req}          | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINVREF end resp}         | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.9 MBTRAIN.DATATRAINVREF


module unit_DATATRAINVREF_local #(
        parameter int unsigned MAX_DATA_VREF_CODE = 7'd127,
        parameter int unsigned MIN_DATA_VREF_CODE = 7'd10
    ) (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock domain
        input  logic        rst_n,              // 0: Async reset to IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        datatrainvref_en    , // 0: Disable (→ IDLE). 1: Enable sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        datatrainvref_done  , // 1: Sub-state completed.
        output logic        trainerror_req      , // 1: Fatal error.
        output logic        update_lane_mask    , // 1: Pulse on entry to SEND_START_REQ.

        //=====================================//
        // PHY Vref Control:                   //
        //=====================================//
        output logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_datavref_ctrl [0:15],

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
        // D2C Sweep Interface:                //
        //=====================================//
        output logic        sweep_en            , // 1: Assert to start/hold sweep.
        input  logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] swept_code          , // Current code under test.
        input  wire logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] best_code [0:15]    , // Per-lane best midpoints.
        input  logic        sweep_done          , // 1: Full sweep complete.

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

    localparam int unsigned VW = $clog2(MAX_DATA_VREF_CODE + 1);

    // FSM State Encoding
    localparam [3:0]
    DATATRAINVREF_LCL_IDLE                = 4'd0,
    DATATRAINVREF_LCL_SEND_START_REQ      = 4'd1,
    DATATRAINVREF_LCL_WAIT_START_RESP     = 4'd2,
    DATATRAINVREF_LCL_SWEEP               = 4'd3,
    DATATRAINVREF_LCL_APPLY_BEST          = 4'd4,
    DATATRAINVREF_LCL_SEND_END_REQ        = 4'd5,
    DATATRAINVREF_LCL_WAIT_END_RESP       = 4'd6,
    DATATRAINVREF_LCL_TO_RXDESKEW         = 4'd7,
    DATATRAINVREF_LCL_TO_TRAINERROR       = 4'd8;

    reg [3:0] current_state, next_state;
    reg [VW-1:0] best_code_r [0:15];

    assign sweep_en = (current_state == DATATRAINVREF_LCL_SWEEP);

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= DATATRAINVREF_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= DATATRAINVREF_LCL_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC
        next_state = current_state;

        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = DATATRAINVREF_LCL_TO_TRAINERROR;
        end
        else if (!datatrainvref_en) begin
            next_state = DATATRAINVREF_LCL_IDLE;
        end
        else begin
            case (current_state)
                DATATRAINVREF_LCL_IDLE: begin
                    next_state = datatrainvref_en ? DATATRAINVREF_LCL_SEND_START_REQ : DATATRAINVREF_LCL_IDLE;
                end

                DATATRAINVREF_LCL_SEND_START_REQ: begin
                    next_state = DATATRAINVREF_LCL_WAIT_START_RESP;
                end

                DATATRAINVREF_LCL_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINVREF_start_resp) begin
                        next_state = DATATRAINVREF_LCL_SWEEP;
                    end
                end

                DATATRAINVREF_LCL_SWEEP: begin
                    next_state = sweep_done ? DATATRAINVREF_LCL_APPLY_BEST : DATATRAINVREF_LCL_SWEEP;
                end

                DATATRAINVREF_LCL_APPLY_BEST: begin
                    next_state = DATATRAINVREF_LCL_SEND_END_REQ;
                end

                DATATRAINVREF_LCL_SEND_END_REQ: begin
                    next_state = DATATRAINVREF_LCL_WAIT_END_RESP;
                end

                DATATRAINVREF_LCL_WAIT_END_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINVREF_end_resp) begin
                        next_state = DATATRAINVREF_LCL_TO_RXDESKEW;
                    end
                end

                DATATRAINVREF_LCL_TO_RXDESKEW: begin
                    next_state = datatrainvref_en ? DATATRAINVREF_LCL_TO_RXDESKEW : DATATRAINVREF_LCL_IDLE;
                end

                DATATRAINVREF_LCL_TO_TRAINERROR: begin
                    next_state = datatrainvref_en ? DATATRAINVREF_LCL_TO_TRAINERROR : DATATRAINVREF_LCL_IDLE;
                end

                default: begin
                    next_state = DATATRAINVREF_LCL_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge lclk or negedge rst_n) begin : BEST_CODE_PROC
        integer j;
        if (!rst_n) begin
            for (j = 0; j < 16; j = j + 1) begin
                best_code_r[j] <= {VW{1'b0}};
            end
        end
        else if (!soft_rst_n) begin
            for (j = 0; j < 16; j = j + 1) begin
                best_code_r[j] <= {VW{1'b0}};
            end
        end
        else begin
            if (current_state == DATATRAINVREF_LCL_SWEEP && sweep_done) begin
                for (j = 0; j < 16; j = j + 1) begin
                    best_code_r[j] <= best_code[j][VW-1:0];
                end
            end
        end
    end

    always_comb begin : OUTPUT_COMB
        datatrainvref_done = 1'b0;
        trainerror_req      = 1'b0;
        update_lane_mask    = 1'b0;

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
            DATATRAINVREF_LCL_IDLE: begin
                mb_tx_clk_lane_sel  = 2'b00;
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
            end

            DATATRAINVREF_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = MBTRAIN_DATATRAINVREF_start_req;
                tx_msginfo       = 16'h0;
                tx_data_field    = 64'h0;
                update_lane_mask = 1'b1;
            end

            DATATRAINVREF_LCL_WAIT_START_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            DATATRAINVREF_LCL_SWEEP: begin
            end

            DATATRAINVREF_LCL_APPLY_BEST: begin
            end

            DATATRAINVREF_LCL_SEND_END_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINVREF_end_req;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DATATRAINVREF_LCL_WAIT_END_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            DATATRAINVREF_LCL_TO_RXDESKEW: begin
                datatrainvref_done = 1'b1;
            end

            DATATRAINVREF_LCL_TO_TRAINERROR: begin
                datatrainvref_done = 1'b1;
                trainerror_req      = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    genvar l;
    generate
        for (l = 0; l < 16; l = l + 1) begin : VREF_OUT_GEN
            assign phy_rx_datavref_ctrl[l] =
                (current_state == DATATRAINVREF_LCL_SWEEP) ?
                VW'(swept_code) :
                best_code_r[l];
        end
    endgenerate

endmodule


