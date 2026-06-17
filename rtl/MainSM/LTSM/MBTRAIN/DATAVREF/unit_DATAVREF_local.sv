// unit_DATAVREF_local.sv — MBTRAIN.DATAVREF LOCAL (Initiator) FSM
//
// This is the LOCAL side of the decoupled DATAVREF implementation.
// The Local FSM:
//   - Sends Request SB messages to the partner die
//   - Waits for Response SB messages from the partner die
//   - Controls the external unit_D2C_sweep module via sweep_en/sweep_done
//   - Applies swept_code to all 16 phy_rx_datavref_ctrl lanes during the sweep
//   - Registers best_code[lane] per lane after sweep_done
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.DATAVREF (Local — Initiator):
// +------------------------------------------+-----------+-------------------------------------------+
// | Message Name                             | Direction | MsgInfo & Data Field Details              |
// +------------------------------------------+-----------+-------------------------------------------+
// | {MBTRAIN.DATAVREF start req}             | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATAVREF start resp}            | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATAVREF end req}               | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {MBTRAIN.DATAVREF end resp}              | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0               |
// | {TRAINERROR entry req}                   | In  (RX)  | Forces jump to TO_TRAINERROR              |
// +------------------------------------------+-----------+-------------------------------------------+
// ====================================================================================================
//
// Spec Reference: UCIe 3.0 §4.5.3.4.2 MBTRAIN.DATAVREF

module unit_DATAVREF_local #(
        parameter int unsigned MAX_DATA_VREF_CODE = 'd16 // Maximum Vref code
    ) (
        //=====================================//
        // Clock and Reset Signals:            //
        //=====================================//
        input  logic        lclk ,              // LTSM clock synchronous transitions
        input  logic        rst_n,              // 0: Async reset to IDLE. 1: Normal operation.

        //=====================================//
        // LTSM Control Signals:               //
        //=====================================//
        input  logic        datavref_en         , // 0: Disable (→ IDLE). 1: Enable/start DATAVREF sequence.
        input  logic        soft_rst_n          , // 0: Soft-reset active. 1: Normal.
        output logic        datavref_done       , // 1: Sub-state completed (held until datavref_en = 0).

        //=====================================//
        // PHY Vref Control:                   //
        //=====================================//
        // Data Lanes Vref code outputs (7-bit code per lane).
        // During D2C sweep: driven combinationally from swept_code.
        // After sweep_done: driven from registered best_code_r.
        output logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0] phy_rx_datavref_ctrl [0:15],

        // MB Lane Control: moved to wrapper_DATAVREF as static assigns
        // (spec §4.5.3.4.2: RX CLK=en, DATA=en, VAL=en, TRK=0)
        // output logic        mb_rx_clk_lane_sel  ,
        // output logic        mb_rx_data_lane_sel ,
        // output logic        mb_rx_val_lane_sel  ,
        // output logic        mb_rx_trk_lane_sel  ,

        //=====================================//
        // D2C Sweep Interface:                //
        //=====================================//
        output logic        sweep_en            , // 1: Assert to external unit_D2C_sweep to start/hold sweep.
        input  logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  swept_code          , // Current Vref code under test.
        input  wire logic [$clog2(MAX_DATA_VREF_CODE+1)-1:0]  best_code [0:15]    , // Per-lane best midpoints.
        input  logic        sweep_done          , // 1: Full sweep complete.

        //=====================================//
        // Sideband Control Signals:           //
        //=====================================//
        output logic        tx_sb_msg_valid     , // Exactly 1 lclk cycle per message.
        output logic [7:0]  tx_sb_msg           , // MsgCode to transmit.
        output logic [15:0] tx_msginfo          , // MsgInfo payload.
        output logic [63:0] tx_data_field       , // 64-bit data payload.

        input  logic        rx_sb_msg_valid     , // Pulse (1 lclk) when a valid SB msg is received.
        input  logic [7:0]  rx_sb_msg             // Received MsgCode from partner die.
        // input  logic [15:0] rx_msginfo          , // Received MsgInfo payload.
        // input  logic [63:0] rx_data_field         // Received 64-bit data payload.
    );

    import UCIe_pkg::*;

    // =========================================================================
    // Local parameter — Vref code bit width
    // =========================================================================
    localparam int unsigned VW = $clog2(MAX_DATA_VREF_CODE + 1);

    // =========================================================================
    // FSM State Encoding — SEND → WAIT pattern.
    // =========================================================================
    localparam [2:0]
    DATAVREF_LCL_IDLE           = 3'd0,  // Wait for datavref_en.
    DATAVREF_LCL_SEND_START_REQ = 3'd1,  // TX {MBTRAIN.DATAVREF start req} for 1 cycle.
    DATAVREF_LCL_WAIT_START_RESP= 3'd2,  // Wait for {MBTRAIN.DATAVREF start resp}.
    DATAVREF_LCL_SWEEP          = 3'd3,  // Assert sweep_en; wait for sweep_done.
    DATAVREF_LCL_APPLY_BEST     = 3'd4,  // 1-cycle pipeline stage
    DATAVREF_LCL_SEND_END_REQ   = 3'd5,  // TX {MBTRAIN.DATAVREF end req} for 1 cycle.
    DATAVREF_LCL_WAIT_END_RESP  = 3'd6,  // Wait for {MBTRAIN.DATAVREF end resp}.
    DATAVREF_LCL_TO_SPEEDIDLE   = 3'd7;  // Terminal: datavref_done=1; wait for en deassert.
    // DATAVREF_LCL_TO_TRAINERROR  = 4'd8;  // Terminal: trainerror_req=1; wait for en deassert.

    // =========================================================================
    // FSM Registers
    // =========================================================================
    reg [2:0] current_state, next_state;

    // =========================================================================
    // Registered best Vref codes per lane.
    // Captured when sweep_done is observed in DATAVREF_LOCAL_SWEEP.
    // =========================================================================
    reg [VW-1:0] best_code_r [0:15];

    // =========================================================================
    // sweep_en: asserted combinationally whenever FSM is in DATAVREF_LCL_SWEEP.
    // =========================================================================
    assign sweep_en = (current_state == DATAVREF_LCL_SWEEP);

    // =========================================================================
    // Sequential FSM: state register
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG_PROC
        if (!rst_n) begin
            current_state <= DATAVREF_LCL_IDLE;
        end
        else if (!soft_rst_n) begin
            current_state <= DATAVREF_LCL_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // Combinational Next-State Logic
    // =========================================================================
    always_comb begin : NEXT_STATE_PROC
        next_state = current_state; // Default: hold

        if (!datavref_en) begin
            next_state = DATAVREF_LCL_IDLE;
        end
        else begin
            case (current_state)

                // ---------------------------------------------------------
                // IDLE: Wait for datavref_en.
                // ---------------------------------------------------------
                DATAVREF_LCL_IDLE: begin
                    next_state = DATAVREF_LCL_SEND_START_REQ;
                end

                // ---------------------------------------------------------
                // SEND_START_REQ: tx_sb_msg_valid=1 for 1 cycle.
                // ---------------------------------------------------------
                DATAVREF_LCL_SEND_START_REQ: begin
                    next_state = DATAVREF_LCL_WAIT_START_RESP;
                end

                // ---------------------------------------------------------
                // WAIT_START_RESP: Wait for {MBTRAIN.DATAVREF start resp}.
                // ---------------------------------------------------------
                DATAVREF_LCL_WAIT_START_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATAVREF_start_resp) begin
                        next_state = DATAVREF_LCL_SWEEP;
                    end
                end

                // ---------------------------------------------------------
                // SWEEP: wait for sweep_done.
                // ---------------------------------------------------------
                DATAVREF_LCL_SWEEP: begin
                    next_state = sweep_done ? DATAVREF_LCL_APPLY_BEST : DATAVREF_LCL_SWEEP;
                end

                // ---------------------------------------------------------
                // APPLY_BEST (1-cycle pipeline stage).
                // ---------------------------------------------------------
                DATAVREF_LCL_APPLY_BEST: begin
                    next_state = DATAVREF_LCL_SEND_END_REQ;
                end

                // ---------------------------------------------------------
                // SEND_END_REQ: tx_sb_msg_valid=1 for 1 cycle.
                // ---------------------------------------------------------
                DATAVREF_LCL_SEND_END_REQ: begin
                    next_state = DATAVREF_LCL_WAIT_END_RESP;
                end

                // ---------------------------------------------------------
                // WAIT_END_RESP: Wait for {MBTRAIN.DATAVREF end resp}.
                // ---------------------------------------------------------
                DATAVREF_LCL_WAIT_END_RESP: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_DATAVREF_end_resp) begin
                        next_state = DATAVREF_LCL_TO_SPEEDIDLE;
                    end
                end

                // ---------------------------------------------------------
                // TO_SPEEDIDLE (Terminal): datavref_done=1.
                // ---------------------------------------------------------
                DATAVREF_LCL_TO_SPEEDIDLE: begin
                    next_state = DATAVREF_LCL_TO_SPEEDIDLE;
                end

                // ---------------------------------------------------------
                // TO_TRAINERROR (Terminal): trainerror_req=1.
                // ---------------------------------------------------------
                // DATAVREF_LCL_TO_TRAINERROR: begin
                //     next_state = DATAVREF_LCL_TO_TRAINERROR;
                // end

                default: begin
                    next_state = DATAVREF_LCL_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Sequential Block: best_code capture
    // =========================================================================
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
            if (current_state == DATAVREF_LCL_SWEEP && sweep_done) begin
                for (j = 0; j < 16; j = j + 1) begin
                    best_code_r[j] <= best_code[j][VW-1:0];
                end
            end
        end
    end

    // =========================================================================
    // Moore Machine Output Logic
    // =========================================================================
    always_comb begin : OUTPUT_COMB
        // --- Defaults: safe inactive values ---
        datavref_done    = 1'b0;
        // trainerror_req   = 1'b0;
        // update_lane_mask = 1'b0;

        tx_sb_msg_valid  = 1'b0;
        tx_sb_msg        = NOTHING;
        tx_msginfo       = 16'h0;
        tx_data_field    = 64'h0;

        // MB RX signals moved to wrapper as static assigns
        // (mb_rx_clk/data/val=datavref_en, mb_rx_trk=0)

        case (current_state)

            // ---------------------------------------------------------
            // IDLE: Watchdog off, RX disabled.
            // ---------------------------------------------------------
            DATAVREF_LCL_IDLE: begin
                // MB signals handled in wrapper
            end

            // ---------------------------------------------------------
            // SEND_START_REQ: Transmit {MBTRAIN.DATAVREF start req}.
            // ---------------------------------------------------------
            DATAVREF_LCL_SEND_START_REQ: begin
                tx_sb_msg_valid  = 1'b1;
                tx_sb_msg        = MBTRAIN_DATAVREF_start_req;
                tx_msginfo       = 16'h0;
                tx_data_field    = 64'h0;
                // update_lane_mask = 1'b1;
            end

            // ---------------------------------------------------------
            // WAIT_START_RESP: No TX.
            // ---------------------------------------------------------
            DATAVREF_LCL_WAIT_START_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            // ---------------------------------------------------------
            // SWEEP: wait for sweep_done.
            // ---------------------------------------------------------
            DATAVREF_LCL_SWEEP: begin
                // sweep_en driven combinationally.
            end

            // ---------------------------------------------------------
            // APPLY_BEST (1-cycle pipeline stage).
            // ---------------------------------------------------------
            DATAVREF_LCL_APPLY_BEST: begin
                // Register latching completed.
            end

            // ---------------------------------------------------------
            // SEND_END_REQ: Transmit {MBTRAIN.DATAVREF end req}.
            // ---------------------------------------------------------
            DATAVREF_LCL_SEND_END_REQ: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_DATAVREF_end_req;
                tx_msginfo      = 16'h0;
                tx_data_field   = 64'h0;
            end

            // ---------------------------------------------------------
            // WAIT_END_RESP: No TX.
            // ---------------------------------------------------------
            DATAVREF_LCL_WAIT_END_RESP: begin
                tx_sb_msg_valid = 1'b0;
            end

            // ---------------------------------------------------------
            // TO_SPEEDIDLE (Terminal): datavref_done=1.
            // ---------------------------------------------------------
            DATAVREF_LCL_TO_SPEEDIDLE: begin
                datavref_done    = 1'b1;
            end

            // ---------------------------------------------------------
            // TO_TRAINERROR (Terminal): trainerror_req=1.
            // ---------------------------------------------------------
            // DATAVREF_LCL_TO_TRAINERROR: begin
            //     datavref_done    = 1'b1;
            //     trainerror_req   = 1'b1;
            // end

            default: begin
                tx_sb_msg_valid = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // PHY Vref Control Output assignments (per-lane)
    // =========================================================================
    genvar l;
    generate
        for (l = 0; l < 16; l = l + 1) begin : VREF_OUT_GEN
            assign phy_rx_datavref_ctrl[l] =
                (current_state == DATAVREF_LCL_SWEEP) ?
                VW'(swept_code) :
                best_code_r[l];
        end
    endgenerate

endmodule


