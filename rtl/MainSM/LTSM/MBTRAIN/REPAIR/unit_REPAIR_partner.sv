// ====================================================================================================
// unit_REPAIR_partner.sv — MBTRAIN.REPAIR PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled REPAIR substate.
// The Partner FSM:
//   - Responds to width degradation handshake from remote Local FSM.
//   - Receives the partner's Transmitter map code and registers it as our mb_rx_data_lane_mask.
//
// ====================================================================================================

module unit_REPAIR_partner (
    // Clock and Reset Signals
    input  logic        lclk,
    input  logic        rst_n,

    // LTSM Control Signals
    input  logic        repair_en,
    input  logic        is_ltsm_out_of_reset,
    input  logic        timeout_8ms_occured,
    output logic        repair_done,
    output logic        trainerror_req,

    // Rx lane map masks
    output logic [2:0]  mb_rx_data_lane_mask,
    input  logic [2:0]  mbinit_rx_data_lane_mask,
    input  logic        update_lane_mask,

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

    // State encoding
    typedef enum logic [3:0] {
        REPAIR_PTN_IDLE         = 4'd0,
        REPAIR_PTN_WAIT_INIT    = 4'd1,
        REPAIR_PTN_SEND_INIT    = 4'd2,
        REPAIR_PTN_WAIT_DEGRADE = 4'd3,
        REPAIR_PTN_SEND_DEGRADE = 4'd4,
        REPAIR_PTN_WAIT_END     = 4'd5,
        REPAIR_PTN_SEND_END     = 4'd6,
        REPAIR_PTN_DONE         = 4'd7,
        REPAIR_PTN_TO_TE        = 4'd8
    } state_t;

    state_t current_state, next_state;

    // Registers
    reg [2:0] mb_rx_data_lane_mask_r;

    assign mb_rx_data_lane_mask = mb_rx_data_lane_mask_r;

    // FSM State Register
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG
        if (!rst_n) begin
            current_state        <= REPAIR_PTN_IDLE;
            mb_rx_data_lane_mask_r <= 3'b000;
        end else if (!is_ltsm_out_of_reset) begin
            current_state        <= REPAIR_PTN_IDLE;
            mb_rx_data_lane_mask_r <= 3'b000;
        end else begin
            current_state <= next_state;

            // Lane map register update
            if (update_lane_mask) begin
                mb_rx_data_lane_mask_r <= mbinit_rx_data_lane_mask;
            end else if (current_state == REPAIR_PTN_WAIT_DEGRADE && rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_req) begin
                mb_rx_data_lane_mask_r <= rx_msginfo[2:0];
            end
        end
    end

    // Next State Logic
    always_comb begin : NEXT_STATE_LOGIC
        next_state = current_state;

        // TRAINERROR overrides
        if (timeout_8ms_occured || (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req)) begin
            next_state = REPAIR_PTN_TO_TE;
        end else begin
            case (current_state)
                REPAIR_PTN_IDLE: begin
                    if (repair_en) begin
                        next_state = REPAIR_PTN_WAIT_INIT;
                    end
                end

                REPAIR_PTN_WAIT_INIT: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_init_req) begin
                        next_state = REPAIR_PTN_SEND_INIT;
                    end
                end

                REPAIR_PTN_SEND_INIT: begin
                    next_state = REPAIR_PTN_WAIT_DEGRADE;
                end

                REPAIR_PTN_WAIT_DEGRADE: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_req) begin
                        next_state = REPAIR_PTN_SEND_DEGRADE;
                    end
                end

                REPAIR_PTN_SEND_DEGRADE: begin
                    next_state = REPAIR_PTN_WAIT_END;
                end

                REPAIR_PTN_WAIT_END: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_end_req) begin
                        next_state = REPAIR_PTN_SEND_END;
                    end
                end

                REPAIR_PTN_SEND_END: begin
                    next_state = REPAIR_PTN_DONE;
                end

                REPAIR_PTN_DONE: begin
                    if (!repair_en) begin
                        next_state = REPAIR_PTN_IDLE;
                    end
                end

                REPAIR_PTN_TO_TE: begin
                    if (!repair_en) begin
                        next_state = REPAIR_PTN_IDLE;
                    end
                end

                default: next_state = REPAIR_PTN_IDLE;
            endcase
        end
    end

    // Output Logic
    always_comb begin : OUTPUT_LOGIC
        // Default outputs
        repair_done         = 1'b0;
        trainerror_req      = 1'b0;
        timeout_timer_en    = 1'b1;

        // Mainband Defaults during REPAIR: Clock Transmitter held differential/simultaneous low (2'b01), other TX low (2'b00)
        // Clock Receiver enabled (1'b1), other RX disabled (1'b0)
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
            REPAIR_PTN_IDLE: begin
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

            REPAIR_PTN_WAIT_INIT: begin
                // Waiting
            end

            REPAIR_PTN_SEND_INIT: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_init_resp;
            end

            REPAIR_PTN_WAIT_DEGRADE: begin
                // Waiting
            end

            REPAIR_PTN_SEND_DEGRADE: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_apply_degrade_resp;
            end

            REPAIR_PTN_WAIT_END: begin
                // Waiting
            end

            REPAIR_PTN_SEND_END: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_end_resp;
            end

            REPAIR_PTN_DONE: begin
                repair_done      = 1'b1;
                timeout_timer_en = 1'b0;
            end

            REPAIR_PTN_TO_TE: begin
                repair_done      = 1'b1;
                trainerror_req   = 1'b1;
                timeout_timer_en = 1'b0;
            end
        endcase
    end

endmodule
