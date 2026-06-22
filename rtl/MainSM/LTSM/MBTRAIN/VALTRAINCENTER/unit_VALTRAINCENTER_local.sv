// unit_VALTRAINCENTER_local.sv — MBTRAIN.VALTRAINCENTER LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled VALTRAINCENTER implementation.
//
// Role:
//   - Sends Request SB messages to the partner die
//   - Waits for Response SB messages from the partner die
//   - Controls the external unit_D2C_sweep module via sweep_en/sweep_done
//   - Applies swept_code to phy_tx_val_pi_phase_ctrl combinationally during the sweep
//   - Registers best_code[0] after sweep_done (Valid Lane = lane 0)
//
// Architecture: Single-FSM, SEND → WAIT pattern.
//
// Early done_req handling:
//   The partner die finishes its sweep independently. It may send {done req}
//   BEFORE our Local has finished sweeping. We latch that early arrival in
//   done_req_rcvd and keep the FSM in WAIT_DONE_RESP until the resp arrives.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.VALTRAINCENTER (Local — Initiator):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.VALTRAINCENTER start req}       | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALTRAINCENTER start resp}      | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALTRAINCENTER done req}        | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.VALTRAINCENTER done resp}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================

module unit_VALTRAINCENTER_local #(
        parameter int unsigned MAX_VAL_PI_CODE = 'd16
    ) (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock domain
        input  logic        rst_n,              // 0: Async reset to IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        valtraincenter_en   , // 0: Disable (→ IDLE). 1: Enable/start VALTRAINCENTER sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        valtraincenter_done, // 1: Sub-state completed (held until valtraincenter_en = 0).
        // output logic        trainerror_req      , // 1: Fatal error — requesting TRAINERROR state.
        // output logic        update_lane_mask    , // 1: Pulse on entry to SEND_START_REQ to update lane mask.

        //=====================================//
        // PHY PI Phase Control:               //
        //=====================================//
        output logic [$clog2(MAX_VAL_PI_CODE+1)-1:0] phy_tx_val_pi_phase_ctrl,

        // MB Lane Control: moved to wrapper_VALTRAINCENTER as static assigns
        // (spec §4.5.3.4.3: TX CLK=speed-dep, TX VAL=01, TX DATA/TRK=00)
        // Speed-dependent CLK and config inputs also moved to wrapper.

        //=====================================//
        // D2C Sweep Interface:                //
        //=====================================//
        output logic        sweep_en            , // 1: Assert to start/hold sweep.
        input  logic [$clog2(MAX_VAL_PI_CODE+1)-1:0] swept_code          , // Current code under test.
        input  logic [$clog2(MAX_VAL_PI_CODE+1)-1:0]  best_code     , // Per-lane best midpoint.
        input  logic        sweep_done          , // 1: Full sweep complete.

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        output logic        tx_sb_msg_valid     , // Exactly 1 lclk cycle per message.
        output logic [7:0]  tx_sb_msg           , // MsgCode to transmit.
        output logic [15:0] tx_msginfo          , // MsgInfo payload.
        output logic [63:0] tx_data_field       , // 64-bit data payload.

        input  logic        rx_sb_msg_valid     , // Pulse (1 lclk) when a valid SB msg is received.
        input  logic [7:0]  rx_sb_msg
        // input  logic [15:0] rx_msginfo          , // Received MsgInfo payload.
        // input  logic [63:0] rx_data_field         // Received 64-bit data payload.
    );

    import UCIe_pkg::*;

    localparam int unsigned VW = $clog2(MAX_VAL_PI_CODE + 1);

    // FSM State Encoding — SEND → WAIT pattern
    localparam [2:0]
    VALTRAINCENTER_LCL_IDLE           = 3'd0,  // Wait for valtraincenter_en
    VALTRAINCENTER_LCL_SEND_START_REQ = 3'd1,  // TX {MBTRAIN.VALTRAINCENTER start req}
    VALTRAINCENTER_LCL_WAIT_START_RESP= 3'd2,  // Wait for {MBTRAIN.VALTRAINCENTER start resp}
    VALTRAINCENTER_LCL_SWEEP          = 3'd3,  // Assert sweep_en; wait for sweep_done
    VALTRAINCENTER_LCL_APPLY_BEST     = 3'd4,  // 1-cycle best midpoint stability stage
    VALTRAINCENTER_LCL_SEND_DONE_REQ  = 3'd5,  // TX {MBTRAIN.VALTRAINCENTER done req}
    VALTRAINCENTER_LCL_WAIT_DONE_RESP = 3'd6,  // Wait for {MBTRAIN.VALTRAINCENTER done resp}
    VALTRAINCENTER_LCL_TO_VALTRAINVREF= 3'd7;  // Terminal: completed
    // VALTRAINCENTER_LCL_TO_TRAINERROR  = 4'd8;  // Terminal: error

    reg [2:0] current_state, next_state;
    reg [VW-1:0] best_code_r;

    assign sweep_en = (current_state == VALTRAINCENTER_LCL_SWEEP);

    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= VALTRAINCENTER_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= VALTRAINCENTER_LCL_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // // === DEBUG: VALTRAINCENTER state transitions ===
    // // synopsys translate_off
    // always_ff @(posedge lclk) begin
    //     if (valtraincenter_en && (current_state != next_state))
    //         $display("T=%0t | [VALTRAINCENTER_LCL DEBUG %m] state: %0d -> %0d, sweep_done=%b, rx_sb_msg_valid=%b, rx_sb_msg=%h",
    //                  $time, current_state, next_state, sweep_done, rx_sb_msg_valid, rx_sb_msg);
    // end
    // // synopsys translate_on

    always_comb begin : NEXT_STATE_PROC
        next_state = current_state;

        if (!valtraincenter_en) begin
            next_state = VALTRAINCENTER_LCL_IDLE;
        end
        else begin
            case (current_state)
                VALTRAINCENTER_LCL_IDLE: begin
                    next_state = VALTRAINCENTER_LCL_SEND_START_REQ;
                end

                VALTRAINCENTER_LCL_SEND_START_REQ: begin
                    next_state = VALTRAINCENTER_LCL_WAIT_START_RESP;
                end

                VALTRAINCENTER_LCL_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALTRAINCENTER_start_resp) begin
                        next_state = VALTRAINCENTER_LCL_SWEEP;
                    end
                end

                VALTRAINCENTER_LCL_SWEEP: begin
                    next_state = sweep_done ? VALTRAINCENTER_LCL_APPLY_BEST : VALTRAINCENTER_LCL_SWEEP;
                end

                VALTRAINCENTER_LCL_APPLY_BEST: begin
                    next_state = VALTRAINCENTER_LCL_SEND_DONE_REQ;
                end

                VALTRAINCENTER_LCL_SEND_DONE_REQ: begin
                    next_state = VALTRAINCENTER_LCL_WAIT_DONE_RESP;
                end

                VALTRAINCENTER_LCL_WAIT_DONE_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_VALTRAINCENTER_done_resp) begin
                        next_state = VALTRAINCENTER_LCL_TO_VALTRAINVREF;
                    end
                end

                VALTRAINCENTER_LCL_TO_VALTRAINVREF: begin
                    next_state = VALTRAINCENTER_LCL_TO_VALTRAINVREF;
                end

                default: begin
                    next_state = VALTRAINCENTER_LCL_IDLE;
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
            if (current_state == VALTRAINCENTER_LCL_SWEEP && sweep_done) begin
                best_code_r <= best_code;
            end
        end
    end

    always_comb begin : OUTPUT_COMB
        valtraincenter_done = 1'b0;
        // trainerror_req      = 1'b0;
        // update_lane_mask    = 1'b0;

        tx_sb_msg_valid     = 1'b0;
        tx_sb_msg           = NOTHING;
        tx_msginfo          = 16'h0;
        tx_data_field       = 64'h0;

        // MB TX signals moved to wrapper as static/conditional assigns

        case (current_state)
            VALTRAINCENTER_LCL_IDLE: begin  end

            VALTRAINCENTER_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = MBTRAIN_VALTRAINCENTER_start_req;
                tx_msginfo       = 16'h0;
                tx_data_field    = 64'h0;
                // update_lane_mask = 1'b1;
            end

            VALTRAINCENTER_LCL_WAIT_START_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            VALTRAINCENTER_LCL_SWEEP: begin
                // sweep_en driven combinational
            end

            VALTRAINCENTER_LCL_APPLY_BEST: begin
                // Latch stable
            end

            VALTRAINCENTER_LCL_SEND_DONE_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_VALTRAINCENTER_done_req;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            VALTRAINCENTER_LCL_WAIT_DONE_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            VALTRAINCENTER_LCL_TO_VALTRAINVREF: begin
                valtraincenter_done = 1'b1;
            end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    assign phy_tx_val_pi_phase_ctrl =
        (current_state == VALTRAINCENTER_LCL_SWEEP) ?
        swept_code[VW-1:0] :
        best_code_r;

endmodule


