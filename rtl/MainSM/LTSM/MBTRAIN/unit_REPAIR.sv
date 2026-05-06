// =============================================================================
// Module  : unit_REPAIR
// Purpose : MBTRAIN.REPAIR sub-state FSM.
//           Handles width degradation for Standard Packages (x16 and x8)
//           after a LINKSPEED failure.
//
// UCIe 3.0 Spec Reference: Section 4.5.3.4.13 – MBTRAIN.REPAIR
// =============================================================================
module unit_REPAIR (
        internal_ltsm_if.repair_mp rp_if
    );
    import UCIe_pkg::*;

    // =========================================================================
    // State encoding
    // =========================================================================
    localparam REPAIR_IDLE         = 4'd0; // S0
    localparam REPAIR_INIT_REQ     = 4'd1; // S1
    localparam REPAIR_INIT_RESP    = 4'd2; // S2
    localparam REPAIR_DEGRADE_REQ  = 4'd3; // S3
    localparam REPAIR_DEGRADE_RESP = 4'd4; // S4
    localparam REPAIR_EVAL_RESULT  = 4'd5; // S5
    localparam REPAIR_END_REQ      = 4'd6; // S6
    localparam REPAIR_END_RESP     = 4'd7; // S7
    localparam TO_TXSELFCAL        = 4'd8; // S8
    localparam TO_TRAINERROR       = 4'd9; // S9

    reg [3:0] current_state, next_state;

    wire is_sb_data_valid = (current_state == next_state);

    // =========================================================================
    // Active Lanes Calculation
    // =========================================================================
    // MB Lane Control
    // Here is the encoding of "local_tx_lane_map_code" OR "local_rx_lane_map_code" by 3 bits:
    // 000b:  None (Degrade not possible)
    // 001b: Logical Lanes 0 to 7
    // 010b: Logical Lanes 8 to 15
    // 011b: Logical Lanes 0 to 15
    // 100b: Logical Lanes 0 to 3
    // 101b: Logical Lanes 4 to 7

    logic [2:0] local_tx_lane_map_code; // We assign to this signal: the sucessful lanes encoding of our MB Tx Lanes (linkspeed_success_lanes)
    logic [2:0] local_rx_lane_map_code; // We assign to this signal: the sucessful lanes encoding of our MB Rx Lanes (mb_rx_data_lane_mask)

    // We have to register the signal 'mb_tx_data_lane_mask'.
    // Because it's used in external modules.
    // and it changes only at the end of the REPAIR_EVAL_RESULT state.
    always_ff @(posedge rp_if.lclk or negedge rp_if.rst_n) begin
        if (!rp_if.rst_n) begin
            rp_if.mb_tx_data_lane_mask <= 3'b0; // to update the used lanes mask for MB Transmitter side. (on our Die)
            rp_if.mb_rx_data_lane_mask <= 3'b0; // to update the used lanes mask for MB Receiver    side. (on our Die)
        end
        // This signal be triggered in the begining of the MBTRAIN state. We get signal form ths substate MBTRAIN.VALVREF
        else if (rp_if.update_lane_mask) begin
            rp_if.mb_tx_data_lane_mask <= rp_if.mbinit_tx_data_lane_mask; // to update the used lanes mask for MB Transmitter side. (on our Die)
            rp_if.mb_rx_data_lane_mask <= rp_if.mbinit_rx_data_lane_mask; // to update the used lanes mask for MB Receiver    side. (on our Die)
        end
        // At the end of the REPAIR substate, we update the value of "mb_(rx/tx)_data_lane_mask" to take the value of "local_(rx/tx)_lane_map_code".
        else if (current_state == REPAIR_EVAL_RESULT) begin
            rp_if.mb_tx_data_lane_mask <= local_tx_lane_map_code; // to update the used lanes mask for MB Transmitter side. (on our Die)
            rp_if.mb_rx_data_lane_mask <= local_rx_lane_map_code; // to update the used lanes mask for MB Receiver    side. (on our Die)
        end
    end

    // =========================================================================
    // State encoding
    // =========================================================================
    always_comb begin
        // If the current opretional width before degrade was x16:
        if ((rp_if.rf_cap_SPMW == 1'b0 && rp_if.rf_ctrl_target_link_width == 4'h2) && rp_if.param_UCIe_S_x8 == 1'b0) begin
            // x16 standard package module
            if (rp_if.linkspeed_success_lanes == 16'hFFFF)
                local_tx_lane_map_code = 3'b011; // Logical Lanes 0 to 15
            else if (rp_if.linkspeed_success_lanes[7:0] == 8'hFF)
                local_tx_lane_map_code = 3'b001; // Logical Lanes 0 to 7
            else if (rp_if.linkspeed_success_lanes[15:8] == 8'hFF)
                local_tx_lane_map_code = 3'b010; // Logical Lanes 8 to 15
            else
                local_tx_lane_map_code = 3'b000; // default (degrade not possible)

            // If the current opretional width before degrade was x8:
        end else if (rp_if.rf_ctrl_target_link_width == 4'h1) begin
            // x8 standard package module OR x8 Mode
            if (rp_if.linkspeed_success_lanes[7:0] == 8'hFF)
                local_tx_lane_map_code = 3'b001; // Logical Lanes 0 to 7
            else if (rp_if.linkspeed_success_lanes[3:0] == 4'hF)
                local_tx_lane_map_code = 3'b100; // Logical Lanes 0 to 3
            else if (rp_if.linkspeed_success_lanes[7:4] == 4'hF)
                local_tx_lane_map_code = 3'b101; // Logical Lanes 4 to 7
            else
                local_tx_lane_map_code = 3'b000; // default (degrade not possible)
        end
        else begin
            local_tx_lane_map_code = 3'b000;
        end
    end

    // =========================================================================
    // Sequential: current state register
    // =========================================================================
    always @(posedge rp_if.lclk or negedge rp_if.rst_n) begin
        if (!rp_if.rst_n) begin
            current_state  <= REPAIR_IDLE;
        end else begin
            current_state  <= next_state;
        end
    end

    // =========================================================================
    // Combinational: next-state logic
    // =========================================================================
    always_comb begin
        if (rp_if.timeout_8ms_occured |
                (rp_if.rx_sb_msg == TRAINERROR_Entry_req && rp_if.rx_sb_msg_valid)) begin
            next_state = TO_TRAINERROR;
        end else begin
            case (current_state)
                REPAIR_IDLE: begin
                    next_state = rp_if.repair_en ? REPAIR_INIT_REQ : REPAIR_IDLE;
                end

                REPAIR_INIT_REQ: begin
                    next_state = (rp_if.rx_sb_msg_valid && rp_if.rx_sb_msg == MBTRAIN_REPAIR_init_req) ? REPAIR_INIT_RESP : REPAIR_INIT_REQ;
                end

                REPAIR_INIT_RESP: begin
                    next_state = (rp_if.rx_sb_msg_valid && rp_if.rx_sb_msg == MBTRAIN_REPAIR_init_resp) ? REPAIR_DEGRADE_REQ : REPAIR_INIT_RESP;
                end

                REPAIR_DEGRADE_REQ: begin
                    next_state = (rp_if.rx_sb_msg_valid && rp_if.rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_req) ? REPAIR_EVAL_RESULT : REPAIR_DEGRADE_REQ;
                end

                REPAIR_EVAL_RESULT: begin
                    // Wait one cycle to evaluate the degraded map code
                    if (local_tx_lane_map_code != 3'b000)
                        next_state = REPAIR_DEGRADE_RESP;
                    else
                        next_state = TO_TRAINERROR;
                end

                REPAIR_DEGRADE_RESP: begin
                    next_state = (rp_if.rx_sb_msg_valid && rp_if.rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_resp) ? REPAIR_END_REQ : REPAIR_DEGRADE_RESP;
                end

                REPAIR_END_REQ: begin
                    next_state = (rp_if.rx_sb_msg_valid && rp_if.rx_sb_msg == MBTRAIN_REPAIR_end_req) ? REPAIR_END_RESP : REPAIR_END_REQ;
                end

                REPAIR_END_RESP: begin
                    next_state = (rp_if.rx_sb_msg_valid && rp_if.rx_sb_msg == MBTRAIN_REPAIR_end_resp) ? TO_TXSELFCAL : REPAIR_END_RESP;
                end

                TO_TXSELFCAL, TO_TRAINERROR: begin
                    next_state = rp_if.repair_en ? current_state : REPAIR_IDLE;
                end

                default: next_state = rp_if.repair_en ? TO_TRAINERROR : REPAIR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Combinational: output logic
    // =========================================================================
    always_comb begin
        // ======================= //
        // LTSM general signals.   //
        // ======================= //
        rp_if.repair_done            = 1'b0;
        rp_if.txselfcal_req          = 1'b0;
        rp_if.trainerror_req         = 1'b0;
        rp_if.timeout_timer_en       = 1'b1;

        // ======================= //
        // MB signals.             //
        // ======================= //
        rp_if.mb_tx_clk_lane_sel  = 2'b01; // Clock Diff Low / Simultaneous Low
        rp_if.mb_tx_data_lane_sel = 2'b00; // Data Low
        rp_if.mb_tx_val_lane_sel  = 2'b00; // Valid Low
        rp_if.mb_tx_trk_lane_sel  = 2'b00; // Track Low
        rp_if.mb_rx_clk_lane_sel  = 1'b1 ;
        rp_if.mb_rx_data_lane_sel = 1'b0 ;
        rp_if.mb_rx_val_lane_sel  = 1'b0 ;
        rp_if.mb_rx_trk_lane_sel  = 1'b0 ;

        // ======================= //
        // SB signals.             //
        // ======================= //
        rp_if.tx_sb_msg_valid = 1'b0;
        rp_if.tx_sb_msg       = NOTHING;
        rp_if.tx_msginfo      = 16'h0;
        rp_if.tx_data_field   = 64'h0;

        case (current_state)
            REPAIR_IDLE: begin
                rp_if.timeout_timer_en = 1'b0;
            end

            REPAIR_INIT_REQ: begin
                rp_if.tx_sb_msg_valid = is_sb_data_valid;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_init_req;
            end

            REPAIR_INIT_RESP: begin
                rp_if.tx_sb_msg_valid = is_sb_data_valid;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_init_resp;
            end

            REPAIR_DEGRADE_REQ: begin
                rp_if.tx_sb_msg_valid = is_sb_data_valid;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_apply_degrade_req;
                rp_if.tx_msginfo      = {13'h0, local_tx_lane_map_code};
            end

            REPAIR_DEGRADE_RESP: begin
                rp_if.tx_sb_msg_valid = is_sb_data_valid;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_apply_degrade_resp;
            end

            REPAIR_EVAL_RESULT: begin
                // Tri-state Tx lanes and Disable Rx lanes that are not part of the negotiated map.
                // However, this is just a single cycle, actual disabling will be handled by the mapper.
            end

            REPAIR_END_REQ: begin
                rp_if.tx_sb_msg_valid = is_sb_data_valid;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_end_req;
            end

            REPAIR_END_RESP: begin
                rp_if.tx_sb_msg_valid = is_sb_data_valid;
                rp_if.tx_sb_msg       = MBTRAIN_REPAIR_end_resp;
            end

            TO_TXSELFCAL: begin
                rp_if.repair_done      = 1'b1;
                rp_if.txselfcal_req    = 1'b1;
                rp_if.timeout_timer_en = 1'b0;
            end

            TO_TRAINERROR: begin
                rp_if.trainerror_req   = 1'b1;
                rp_if.repair_done      = 1'b1;
                rp_if.timeout_timer_en = 1'b0;
            end

            default: begin end
        endcase
    end

    always_ff @(posedge rp_if.lclk or negedge rp_if.rst_n) begin
        if (!rp_if.rst_n) begin
            local_rx_lane_map_code <= 3'b000;
        end
        else if (current_state == REPAIR_INIT_RESP) begin
            local_rx_lane_map_code <= 3'b000;
        end
        else if (current_state == REPAIR_DEGRADE_REQ && (rp_if.rx_sb_msg_valid && rp_if.rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_req)) begin
            local_rx_lane_map_code <= rp_if.rx_msginfo[2:0];
        end
    end
endmodule
