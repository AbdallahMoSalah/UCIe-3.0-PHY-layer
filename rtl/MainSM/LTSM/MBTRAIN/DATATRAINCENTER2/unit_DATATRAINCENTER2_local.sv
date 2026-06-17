// unit_DATATRAINCENTER2_local.sv — MBTRAIN.DATATRAINCENTER2 LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled DATATRAINCENTER2 implementation.
// The Local FSM:
//   - Sends Request SB messages to the partner die
//   - Waits for Response SB messages from the partner die
//   - Controls the external unit_D2C_sweep module via sweep_en/sweep_done
//   - Drives phy_tx_data_pi_phase_ctrl lanes during the sweep
//   - Registers best_code[lane] per lane after sweep_done
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.DATATRAINCENTER2 (Local — Initiator):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.DATATRAINCENTER2 start req}     | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER2 start resp}    | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER2 end req}       | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATATRAINCENTER2 end resp}      | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.11 MBTRAIN.DATATRAINCENTER2

module unit_DATATRAINCENTER2_local #(
        parameter int unsigned MAX_DATA_PI_CODE = 'd16 // Maximum PI phase code
    ) (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock domain
        input  logic        rst_n,              // 0: Async reset to IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        datatraincenter2_en , // 0: Disable (→ IDLE). 1: Enable sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        datatraincenter2_done, // 1: Sub-state completed (held until en = 0).

        //=====================================//
        // PHY PI Control:                     //
        //=====================================//
        output logic [$clog2(MAX_DATA_PI_CODE+1)-1:0] phy_tx_data_pi_phase_ctrl [0:15],

        // MB TX Lane Control: moved to wrapper_DATATRAINCENTER2 as static assigns
        // (spec §4.5.3.4.11: CLK TX=01, DATA/VAL/TRK TX=00)
        // output logic [1:0]  mb_tx_clk_lane_sel  ,
        // output logic [1:0]  mb_tx_data_lane_sel ,
        // output logic [1:0]  mb_tx_val_lane_sel  ,
        // output logic [1:0]  mb_tx_trk_lane_sel  ,

        //=====================================//
        // D2C Sweep Interface:                //
        //=====================================//
        output logic        sweep_en            , // 1: Assert to start/hold sweep.
        input  logic [$clog2(MAX_DATA_PI_CODE+1)-1:0] swept_code          , // Current code under test.
        input  wire logic [$clog2(MAX_DATA_PI_CODE+1)-1:0] best_code [0:15]    , // Per-lane best midpoints.
        input  logic        sweep_done          , // 1: Full sweep complete.

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        output logic        tx_sb_msg_valid     , // Exactly 1 lclk cycle per message.
        output logic [7:0]  tx_sb_msg           , // MsgCode to transmit.
        output logic [15:0] tx_msginfo          , // MsgInfo payload.
        output logic [63:0] tx_data_field       , // 64-bit data payload.

        input  logic        rx_sb_msg_valid     , // Pulse when a valid SB msg is received.
        input  logic [7:0]  rx_sb_msg
        // input  logic [15:0] rx_msginfo          , // Received MsgInfo payload.
        // input  logic [63:0] rx_data_field         // Received 64-bit data payload.
    );

    import UCIe_pkg::*;

    localparam int unsigned PW = $clog2(MAX_DATA_PI_CODE + 1);

    // FSM State Encoding
    localparam [2:0]
    DATATRAINCENTER2_LCL_IDLE           = 3'd0,
    DATATRAINCENTER2_LCL_SEND_START_REQ = 3'd1,
    DATATRAINCENTER2_LCL_WAIT_START_RESP= 3'd2,
    DATATRAINCENTER2_LCL_SWEEP          = 3'd3,
    DATATRAINCENTER2_LCL_APPLY_BEST     = 3'd4,
    DATATRAINCENTER2_LCL_SEND_END_REQ   = 3'd5,
    DATATRAINCENTER2_LCL_WAIT_END_RESP  = 3'd6,
    DATATRAINCENTER2_LCL_TO_LINKSPEED   = 3'd7;

    reg [2:0] current_state, next_state;
    reg [PW-1:0] best_code_r [0:15];

    assign sweep_en = (current_state == DATATRAINCENTER2_LCL_SWEEP);

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= DATATRAINCENTER2_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= DATATRAINCENTER2_LCL_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    always_comb begin : NEXT_STATE_PROC
        next_state = current_state;

        if (!datatraincenter2_en) begin
            next_state = DATATRAINCENTER2_LCL_IDLE;
        end
        else begin
            case (current_state)
                DATATRAINCENTER2_LCL_IDLE: begin
                    next_state = DATATRAINCENTER2_LCL_SEND_START_REQ;
                end

                DATATRAINCENTER2_LCL_SEND_START_REQ: begin
                    next_state = DATATRAINCENTER2_LCL_WAIT_START_RESP;
                end

                DATATRAINCENTER2_LCL_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER2_start_resp) begin
                        next_state = DATATRAINCENTER2_LCL_SWEEP;
                    end
                end

                DATATRAINCENTER2_LCL_SWEEP: begin
                    next_state = sweep_done ? DATATRAINCENTER2_LCL_APPLY_BEST : DATATRAINCENTER2_LCL_SWEEP;
                end

                DATATRAINCENTER2_LCL_APPLY_BEST: begin
                    next_state = DATATRAINCENTER2_LCL_SEND_END_REQ;
                end

                DATATRAINCENTER2_LCL_SEND_END_REQ: begin
                    next_state = DATATRAINCENTER2_LCL_WAIT_END_RESP;
                end

                DATATRAINCENTER2_LCL_WAIT_END_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATATRAINCENTER2_end_resp) begin
                        next_state = DATATRAINCENTER2_LCL_TO_LINKSPEED;
                    end
                end

                DATATRAINCENTER2_LCL_TO_LINKSPEED: begin
                    next_state = DATATRAINCENTER2_LCL_TO_LINKSPEED;
                end

                default: begin
                    next_state = DATATRAINCENTER2_LCL_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge lclk or negedge rst_n) begin : BEST_CODE_PROC
        integer j;
        if (!rst_n) begin
            for (j = 0; j < 16; j = j + 1) begin
                best_code_r[j] <= {PW{1'b0}};
            end
        end
        else if (!soft_rst_n) begin
            for (j = 0; j < 16; j = j + 1) begin
                best_code_r[j] <= {PW{1'b0}};
            end
        end
        else begin
            if (current_state == DATATRAINCENTER2_LCL_SWEEP && sweep_done) begin
                for (j = 0; j < 16; j = j + 1) begin
                    best_code_r[j] <= best_code[j][PW-1:0];
                end
            end
        end
    end

    always_comb begin : OUTPUT_COMB
        datatraincenter2_done = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB TX signals moved to wrapper as static assigns (CLK=01, DATA/VAL/TRK=00)

        case (current_state)
            DATATRAINCENTER2_LCL_IDLE: begin end

            DATATRAINCENTER2_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = MBTRAIN_DATATRAINCENTER2_start_req;
                tx_msginfo       = 16'h0;
                tx_data_field    = 64'h0;
            end

            DATATRAINCENTER2_LCL_WAIT_START_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            DATATRAINCENTER2_LCL_SWEEP: begin
            end

            DATATRAINCENTER2_LCL_APPLY_BEST: begin
            end

            DATATRAINCENTER2_LCL_SEND_END_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATATRAINCENTER2_end_req;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            DATATRAINCENTER2_LCL_WAIT_END_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            DATATRAINCENTER2_LCL_TO_LINKSPEED: begin
                datatraincenter2_done = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    genvar l;
    generate
        for (l = 0; l < 16; l = l + 1) begin : PI_OUT_GEN
            assign phy_tx_data_pi_phase_ctrl[l] =
                (current_state == DATATRAINCENTER2_LCL_SWEEP) ?
                PW'(swept_code) :
                best_code_r[l];
        end
    endgenerate

endmodule


