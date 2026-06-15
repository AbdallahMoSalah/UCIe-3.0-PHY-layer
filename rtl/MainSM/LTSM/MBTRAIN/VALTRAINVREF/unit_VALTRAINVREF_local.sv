// unit_VALTRAINVREF_local.sv — MBTRAIN.VALTRAINVREF LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled VALTRAINVREF implementation.
//
// Role:
//   - Sends Request SB messages to the partner die
//   - Waits for Response SB messages from the partner die
//   - Controls the external unit_D2C_sweep module via sweep_en/sweep_done
//   - Applies swept_code to phy_rx_valvref_ctrl combinationally during the sweep
//   - Registers best_code[0] after sweep_done (Valid Lane = lane 0)
//
// Architecture: Single-FSM, SEND → WAIT pattern.

module unit_VALTRAINVREF_local #(
        parameter int unsigned MAX_VAL_VREF_CODE = 7'd16,
        parameter int unsigned MIN_VAL_VREF_CODE = 7'd1
    ) (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock domain
        input  logic        rst_n,              // 0: Async reset to IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        valtrainvref_en     , // 0: Disable (→ IDLE). 1: Enable/start VALTRAINVREF sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        valtrainvref_done   , // 1: Sub-state completed (held until valtrainvref_en = 0).
        output logic        trainerror_req      , // 1: Fatal error — requesting TRAINERROR state.
        output logic        update_lane_mask    , // 1: Pulse on entry to SEND_START_REQ to update lane mask.

        //=====================================//
        // PHY Vref Control:                   //
        //=====================================//
        output logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0] phy_rx_valvref_ctrl,

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
        input  logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0] swept_code          , // Current Vref code under test.
        input  wire logic [$clog2(MAX_VAL_VREF_CODE+1)-1:0] best_code [0:15]    , // Per-lane best midpoints.
        input  logic        sweep_done          , // 1: Full sweep complete.

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

    localparam int unsigned VW = $clog2(MAX_VAL_VREF_CODE + 1);

    // FSM State Encoding — SEND → WAIT pattern
    localparam [3:0]
    VALTRAINVREF_LCL_IDLE                = 4'd0,  // Wait for valtrainvref_en
    VALTRAINVREF_LCL_SEND_START_REQ      = 4'd1,  // TX {MBTRAIN.VALTRAINVREF start req}
    VALTRAINVREF_LCL_WAIT_START_RESP     = 4'd2,  // Wait for {MBTRAIN.VALTRAINVREF start resp}
    VALTRAINVREF_LCL_SWEEP               = 4'd3,  // Assert sweep_en; wait for sweep_done
    VALTRAINVREF_LCL_APPLY_BEST          = 4'd4,  // 1-cycle best midpoint stability stage
    VALTRAINVREF_LCL_SEND_END_REQ        = 4'd5,  // TX {MBTRAIN.VALTRAINVREF end req}
    VALTRAINVREF_LCL_WAIT_END_RESP       = 4'd6,  // Wait for {MBTRAIN.VALTRAINVREF end resp}
    VALTRAINVREF_LCL_TO_DATATRAINCENTER1 = 4'd7,  // Terminal: completed (next DTC1)
    VALTRAINVREF_LCL_TO_TRAINERROR       = 4'd8;  // Terminal: error

    reg [3:0] current_state, next_state;
    reg [VW-1:0] best_code_r;

    assign sweep_en = (current_state == VALTRAINVREF_LCL_SWEEP);

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= VALTRAINVREF_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= VALTRAINVREF_LCL_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC
        next_state = current_state;

        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = VALTRAINVREF_LCL_TO_TRAINERROR;
        end
        else if (!valtrainvref_en) begin
            next_state = VALTRAINVREF_LCL_IDLE;
        end
        else begin
            case (current_state)
                VALTRAINVREF_LCL_IDLE: begin
                    next_state = valtrainvref_en ? VALTRAINVREF_LCL_SEND_START_REQ : VALTRAINVREF_LCL_IDLE;
                end

                VALTRAINVREF_LCL_SEND_START_REQ: begin
                    next_state = VALTRAINVREF_LCL_WAIT_START_RESP;
                end

                VALTRAINVREF_LCL_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALTRAINVREF_start_resp) begin
                        next_state = VALTRAINVREF_LCL_SWEEP;
                    end
                end

                VALTRAINVREF_LCL_SWEEP: begin
                    next_state = sweep_done ? VALTRAINVREF_LCL_APPLY_BEST : VALTRAINVREF_LCL_SWEEP;
                end

                VALTRAINVREF_LCL_APPLY_BEST: begin
                    next_state = VALTRAINVREF_LCL_SEND_END_REQ;
                end

                VALTRAINVREF_LCL_SEND_END_REQ: begin
                    next_state = VALTRAINVREF_LCL_WAIT_END_RESP;
                end

                VALTRAINVREF_LCL_WAIT_END_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALTRAINVREF_end_resp) begin
                        next_state = VALTRAINVREF_LCL_TO_DATATRAINCENTER1;
                    end
                end

                VALTRAINVREF_LCL_TO_DATATRAINCENTER1: begin
                    next_state = valtrainvref_en ? VALTRAINVREF_LCL_TO_DATATRAINCENTER1 : VALTRAINVREF_LCL_IDLE;
                end

                VALTRAINVREF_LCL_TO_TRAINERROR: begin
                    next_state = valtrainvref_en ? VALTRAINVREF_LCL_TO_TRAINERROR : VALTRAINVREF_LCL_IDLE;
                end

                default: begin
                    next_state = VALTRAINVREF_LCL_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge lclk or negedge rst_n) begin : BEST_CODE_PROC
        if (!rst_n) begin
            best_code_r <= {VW{1'b0}};
        end
        else if (!soft_rst_n) begin
            best_code_r <= {VW{1'b0}};
        end
        else begin
            if (current_state == VALTRAINVREF_LCL_SWEEP && sweep_done) begin
                best_code_r <= best_code[0][VW-1:0];
            end
        end
    end

    always_comb begin : OUTPUT_COMB
        valtrainvref_done = 1'b0;
        trainerror_req    = 1'b0;
        update_lane_mask  = 1'b0;

        tx_sb_msg_valid   = 1'b0;
        tx_sb_msg         = NOTHING;
        tx_msginfo        = 16'h0;
        tx_data_field     = 64'h0;

        // MB lane selects (mirroring VALVREF)
        mb_tx_clk_lane_sel  = 2'b00; // Held Low during sweep
        mb_tx_data_lane_sel = 2'b00;
        mb_tx_val_lane_sel  = 2'b00;
        mb_tx_trk_lane_sel  = 2'b00;
        mb_rx_clk_lane_sel  = 1'b1;
        mb_rx_data_lane_sel = 1'b0;
        mb_rx_val_lane_sel  = 1'b1;  // Enabled Valid RX
        mb_rx_trk_lane_sel  = 1'b0;

        case (current_state)
            VALTRAINVREF_LCL_IDLE: begin
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
            end

            VALTRAINVREF_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = MBTRAIN_VALTRAINVREF_start_req;
                tx_msginfo       = 16'h0;
                tx_data_field    = 64'h0;
                update_lane_mask = 1'b1;
            end

            VALTRAINVREF_LCL_WAIT_START_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            VALTRAINVREF_LCL_SWEEP: begin
                // sweep_en driven combinational
            end

            VALTRAINVREF_LCL_APPLY_BEST: begin
                // Latch stable
            end

            VALTRAINVREF_LCL_SEND_END_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALTRAINVREF_end_req;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            VALTRAINVREF_LCL_WAIT_END_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            VALTRAINVREF_LCL_TO_DATATRAINCENTER1: begin
                valtrainvref_done = 1'b1;
            end

            VALTRAINVREF_LCL_TO_TRAINERROR: begin
                valtrainvref_done = 1'b1;
                trainerror_req    = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    assign phy_rx_valvref_ctrl =
        (current_state == VALTRAINVREF_LCL_SWEEP) ?
        swept_code[VW-1:0] :
        best_code_r;

endmodule


