// ====================================================================================================
// unit_REPAIR_local.sv — MBTRAIN.REPAIR LOCAL (Initiator) FSM
//
// ROLE (LOCAL = HANDSHAKE INITIATOR):
//   - Sends {init req}, waits {init resp}.
//   - Sends {apply degrade req} with our TX lane code in MsgInfo[2:0].
//   - Waits {apply degrade resp} (pure ACK — no data).
//   - Evaluates: if our TX code is feasible → send {end req}, wait {end resp} → TXSELFCAL.
//               if not feasible → TRAINERROR.
//   - Snoops incoming {apply degrade req} from the remote die ONLY to detect
//     "Degrade not possible" (3'b000), triggering TRAINERROR.
//
// OWNERSHIP:
//   LOCAL does NOT own any lane mask registers.
//   The PARTNER FSM (unit_REPAIR_partner) is the sole owner of both
//   mb_tx_data_lane_mask and mb_rx_data_lane_mask for our die.
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.REPAIR (Local — Initiator):
// +-------------------------------------------+-----------+------------------------------------------+
// | Message Name                              | Direction | MsgInfo & Data Field Details             |
// +-------------------------------------------+-----------+------------------------------------------+
// | {MBTRAIN.REPAIR init req}                 | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0              |
// | {MBTRAIN.REPAIR init resp}                | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0              |
// | {MBTRAIN.REPAIR apply degrade req}        | Out (TX)  | MsgInfo[2:0]: our TX lane code           |
// |                                           |           |   3'b000 = degrade not possible          |
// |                                           |           |   3'b001 = x8 low (lanes 0-7)            |
// |                                           |           |   3'b010 = x8 high (lanes 8-15)          |
// |                                           |           |   3'b011 = x16 full (lanes 0-15)         |
// |                                           |           |   3'b100 = x4 low (lanes 0-3)            |
// |                                           |           |   3'b101 = x4 mid-low (lanes 4-7)        |
// | {MBTRAIN.REPAIR apply degrade resp}       | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0 (pure ACK)  |
// | {MBTRAIN.REPAIR end req}                  | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0              |
// | {MBTRAIN.REPAIR end resp}                 | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0              |
// +-------------------------------------------+-----------+------------------------------------------+
// ====================================================================================================

module unit_REPAIR_local (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control Signals
        input  logic        repair_en,
        input  logic        is_ltsm_out_of_reset,
        input  logic        timeout_8ms_occured,
        output logic        repair_done,
        output logic        txselfcal_req,
        output logic        trainerror_req,

        // Width Degradation Input (our TX code, computed by unit_negotiated_lanes in the wrapper)
        input  logic [2:0]  degraded_tx_lane_map_code, // Our best TX degraded lane code
        input  logic        width_degrade_feasible,     // 1 = our TX code is valid (!= 3'b000)

        // Timer Control Signals
        output logic        timeout_timer_en,

        // MB TX/RX Lane Control
        output logic [1:0]  mb_tx_clk_lane_sel,
        output logic [1:0]  mb_tx_data_lane_sel,
        output logic [1:0]  mb_tx_val_lane_sel,
        output logic [1:0]  mb_tx_trk_lane_sel,
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_data_lane_sel,
        output logic        mb_rx_val_lane_sel,
        output logic        mb_rx_trk_lane_sel,

        // Sideband Control Signals
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg,
        input  logic [15:0] rx_msginfo,
        input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    // =========================================================================
    // State encoding
    // =========================================================================
    typedef enum logic [3:0] {
        REPAIR_LOCAL_IDLE          = 4'd0,
        REPAIR_LOCAL_SEND_INIT     = 4'd1,
        REPAIR_LOCAL_WAIT_INIT     = 4'd2,
        REPAIR_LOCAL_SEND_DEGRADE  = 4'd3,
        REPAIR_LOCAL_WAIT_DEGRADE  = 4'd4,
        REPAIR_LOCAL_EVAL          = 4'd5,
        REPAIR_LOCAL_SEND_END      = 4'd6,
        REPAIR_LOCAL_WAIT_END      = 4'd7,
        REPAIR_LOCAL_TO_TXSELFCAL  = 4'd8,
        REPAIR_LOCAL_TO_TRAINERROR = 4'd9
    } state_t;

    state_t current_state, next_state;

    // =========================================================================
    // Snoop register: capture the remote die's TX code from its {apply degrade req}.
    // This is used only for TRAINERROR detection (3'b000 = degrade not possible on remote die).
    // =========================================================================
    reg [2:0] partner_tx_code_r;

    // =========================================================================
    // FSM State Register
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG
        if (!rst_n) begin
            current_state    <= REPAIR_LOCAL_IDLE;
            partner_tx_code_r <= 3'b000;
        end else if (!is_ltsm_out_of_reset) begin
            current_state    <= REPAIR_LOCAL_IDLE;
            partner_tx_code_r <= 3'b000;
        end else begin
            current_state <= next_state;

            // Snoop: capture remote die's TX code whenever we see their {apply degrade req}
            // on the RX bus. This is Die B's LOCAL sending its TX code to Die A's PARTNER.
            // We capture it here only to check for 3'b000 = "Degrade not possible".
            if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_req) begin
                partner_tx_code_r <= rx_msginfo[2:0];
            end
        end
    end

    // =========================================================================
    // Next State Logic
    // =========================================================================
    always_comb begin : NEXT_STATE_LOGIC
        next_state = current_state;

        // TRAINERROR global overrides
        if (timeout_8ms_occured || (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req)) begin
            next_state = REPAIR_LOCAL_TO_TRAINERROR;
        end else begin
            case (current_state)
                REPAIR_LOCAL_IDLE: begin
                    if (repair_en) begin
                        next_state = REPAIR_LOCAL_SEND_INIT;
                    end
                end

                REPAIR_LOCAL_SEND_INIT: begin
                    next_state = REPAIR_LOCAL_WAIT_INIT;
                end

                REPAIR_LOCAL_WAIT_INIT: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_init_resp) begin
                        next_state = REPAIR_LOCAL_SEND_DEGRADE;
                    end
                end

                REPAIR_LOCAL_SEND_DEGRADE: begin
                    next_state = REPAIR_LOCAL_WAIT_DEGRADE;
                end

                REPAIR_LOCAL_WAIT_DEGRADE: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_resp) begin
                        next_state = REPAIR_LOCAL_EVAL;
                    end
                end

                REPAIR_LOCAL_EVAL: begin
                    // TRAINERROR if our TX code is 3'b000 OR if the remote die sent 3'b000.
                    // partner_tx_code_r was captured (snooped) when we saw their req on the bus.
                    if (!width_degrade_feasible || (partner_tx_code_r == 3'b000)) begin
                        next_state = REPAIR_LOCAL_TO_TRAINERROR;
                    end else begin
                        next_state = REPAIR_LOCAL_SEND_END;
                    end
                end

                REPAIR_LOCAL_SEND_END: begin
                    next_state = REPAIR_LOCAL_WAIT_END;
                end

                REPAIR_LOCAL_WAIT_END: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_end_resp) begin
                        next_state = REPAIR_LOCAL_TO_TXSELFCAL;
                    end
                end

                REPAIR_LOCAL_TO_TXSELFCAL: begin
                    if (!repair_en) begin
                        next_state = REPAIR_LOCAL_IDLE;
                    end
                end

                REPAIR_LOCAL_TO_TRAINERROR: begin
                    if (!repair_en) begin
                        next_state = REPAIR_LOCAL_IDLE;
                    end
                end

                default: next_state = REPAIR_LOCAL_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Output Logic
    // =========================================================================
    always_comb begin : OUTPUT_LOGIC
        // Defaults
        repair_done         = 1'b0;
        txselfcal_req       = 1'b0;
        trainerror_req      = 1'b0;
        timeout_timer_en    = 1'b1;

        // Mainband defaults during REPAIR (spec §4.5.3.4.13):
        //   Track, Data, Valid TX held low (2'b00).
        //   Clock TX held differential/simultaneous low (2'b01).
        //   Clock RX enabled (1'b1), other RX disabled (1'b0).
        mb_tx_clk_lane_sel  = 2'b01;
        mb_tx_data_lane_sel = 2'b00;
        mb_tx_val_lane_sel  = 2'b00;
        mb_tx_trk_lane_sel  = 2'b00;
        mb_rx_clk_lane_sel  = 1'b1;
        mb_rx_data_lane_sel = 1'b0;
        mb_rx_val_lane_sel  = 1'b0;
        mb_rx_trk_lane_sel  = 1'b0;

        tx_sb_msg_valid     = 1'b0;
        tx_sb_msg           = NOTHING;
        tx_msginfo          = 16'h0;
        tx_data_field       = 64'h0;

        case (current_state)
            REPAIR_LOCAL_IDLE: begin
                timeout_timer_en    = 1'b0;
                mb_tx_clk_lane_sel  = 2'b00;
                mb_tx_data_lane_sel = 2'b00;
                mb_tx_val_lane_sel  = 2'b00;
                mb_tx_trk_lane_sel  = 2'b00;
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
                mb_rx_trk_lane_sel  = 1'b0;
            end

            REPAIR_LOCAL_SEND_INIT: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_init_req;
            end

            REPAIR_LOCAL_WAIT_INIT: begin
                // Waiting for {MBTRAIN.REPAIR init resp}
            end

            REPAIR_LOCAL_SEND_DEGRADE: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_apply_degrade_req;
                // MsgInfo[2:0] carries our TX lane code.
                // If width_degrade_feasible=0, degraded_tx_lane_map_code=3'b000 (degrade not possible).
                tx_msginfo      = {13'h0, degraded_tx_lane_map_code};
            end

            REPAIR_LOCAL_WAIT_DEGRADE: begin
                // Waiting for {MBTRAIN.REPAIR apply degrade resp} (pure ACK — no data)
            end

            REPAIR_LOCAL_EVAL: begin
                // Single-cycle evaluation state — no SB activity.
            end

            REPAIR_LOCAL_SEND_END: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_end_req;
            end

            REPAIR_LOCAL_WAIT_END: begin
                // Waiting for {MBTRAIN.REPAIR end resp}
            end

            REPAIR_LOCAL_TO_TXSELFCAL: begin
                repair_done      = 1'b1;
                txselfcal_req    = 1'b1;
                timeout_timer_en = 1'b0;
            end

            REPAIR_LOCAL_TO_TRAINERROR: begin
                repair_done      = 1'b1;
                trainerror_req   = 1'b1;
                timeout_timer_en = 1'b0;
            end

            default: begin
                // Safe defaults already assigned above
            end
        endcase
    end

endmodule
