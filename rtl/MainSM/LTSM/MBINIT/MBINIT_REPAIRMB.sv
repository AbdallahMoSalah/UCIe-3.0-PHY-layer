/*
==================================================
UCIe 3.0 PHY Layer - MBINIT_REPAIRMB
==================================================
This module implements the Mainband Lane Repair (REPAIRMB) substate
of Mainband Initialization, completely refactored to match the robust,
split-state FSM style of MBINIT_REVERSALMB.

It replaces the old d2c_test_if interface with discrete ports,
externalizes the watchdog timer, implements ltsm_rdy handshaking,
and utilizes sticky flags to latch partner messages.
*/

import UCIe_pkg::*;

module MBINIT_REPAIRMB
#( parameter int CLK_FRQ_HZ = 800000000 )
(
    input  logic clk, rst_n,

    input  logic reg_x8_mode_req,
    input  logic SPMW,
    input  logic mb_repairmb_enable,

    output logic mb_repairmb_done,
    output logic mb_repairmb_error,

    // RX Sideband Interface
    input  logic            mb_repairmb_rx_valid,
    input  msg_no_e         mb_repairmb_rx_msg_id,
    input  logic    [15:0]  mb_repairmb_rx_MsgInfo,
    input  logic    [63:0]  mb_repairmb_rx_data_Field,

    // TX Sideband Interface
    output logic            mb_repairmb_tx_valid,
    output msg_no_e         mb_repairmb_tx_msg_id,
    output logic    [15:0]  mb_repairmb_tx_MsgInfo,
    output logic    [63:0]  mb_repairmb_tx_data_Field,

    // Timer Interface (Externalized)
    input  logic            timeout_repair_expired,
    output logic            timeout_repair_enable,

    // FIFO handshake
    input  logic            ltsm_rdy,

    // Pattern Generator & Comparator Interface
    output logic            mb_tx_data_pattern_sel, // 1: per lane id, 0: lfsr
    output logic            mb_rx_compare_setup,   // 1: per lane, 0: aggregate
    output logic            mb_tx_data_pattern_en,
    output logic            mb_rx_data_compare_en,
    input  logic    [15:0]  mb_rx_perlane_status,
    input  logic            mb_tx_data_pattern_transmission_completed,

    // Clear Error request to comparator
    output logic            clear_error_req

);

    ////////////////////////////////////////////////////////
    // STATES
    ////////////////////////////////////////////////////////
    typedef enum logic [4:0] {
        MB_S0_IDLE,

        // S1 Readiness
        MB_S1_READY_REQ_SEND,
        MB_S1_READY_REQ_WAIT,
        MB_S1_READY_RSP_SEND,
        MB_S1_READY_RSP_WAIT,

        // S2 Point Test
        MB_S2_D2C_POINT_TEST,

        // S3 Degrade Resolution
        MB_S3_DEGRADE_REQ_SEND,
        MB_S3_DEGRADE_REQ_WAIT,
        MB_S3_DEGRADE_RSP_SEND,
        MB_S3_DEGRADE_RSP_WAIT,

        // S4 Degrade Verification
        MB_S4_DEGRADE_VERIFICATION,

        // S5 Finalize
        MB_S5_FINALIZE_REQ_SEND,
        MB_S5_FINALIZE_REQ_WAIT,
        MB_S5_FINALIZE_RSP_SEND,
        MB_S5_FINALIZE_RSP_WAIT,

        MB_S6_REPAIR_ERROR,
        MB_S7_REPAIR_DONE
    } state_e;

    state_e current_state, next_state;

    ////////////////////////////////////////////////////////
    // CONSTANTS & DEFAULTS
    ////////////////////////////////////////////////////////
    localparam logic [15:0] MB_default_MSG_Info   = 16'h0000;
    localparam logic [63:0] MB_default_data_Field = 64'h0;

    ////////////////////////////////////////////////////////
    // DEGRADATION LOGIC & LANE MAPS
    ////////////////////////////////////////////////////////
    logic [2:0]  local_lane_map;
    logic [2:0]  partner_lane_map;
    logic [2:0]  final_lane_map;
    logic [2:0]  final_lane_map_r;
    logic [2:0]  prev_lane_map;
    logic        degrade_not_possible;
    logic        degrade_not_possible_r;
    logic        width_changed_r;

    logic [15:0] mb_rx_perlane_result;
    logic        allow_x4_mode;

    assign allow_x4_mode = reg_x8_mode_req || SPMW;

    // Local Degrade Map calculation based on per-lane error results
    always_comb begin
        // default - all lanes good (x16 mode)
        local_lane_map = 3'b011; 

        if (mb_rx_perlane_result == 16'hFFFF) begin
            local_lane_map = 3'b000; // degrade not possible
        end
        else if (mb_rx_perlane_result == 16'h0000) begin
            local_lane_map = 3'b011; // x16 full width
        end
        else if (mb_rx_perlane_result == 16'hFF00) begin
            local_lane_map = 3'b001; // lower x8 operational
        end
        else if (mb_rx_perlane_result == 16'h00FF) begin
            local_lane_map = 3'b010; // upper x8 operational
        end
        else if (allow_x4_mode) begin
            if (mb_rx_perlane_result == 16'hFFF0) begin
                local_lane_map = 3'b100; // lanes 0-3 operational
            end
            else if (mb_rx_perlane_result == 16'hFF0F) begin
                local_lane_map = 3'b101; // lanes 4-7 operational
            end
            else begin
                local_lane_map = 3'b000; // other errors -> fail
            end
        end
        else begin
            local_lane_map = 3'b000; // other errors -> fail
        end
    end

    // Agreement Resolution Logic (Combines local and partner capabilities)
    always_comb begin
        degrade_not_possible = 1'b0;
        final_lane_map = 3'b000;

        if (local_lane_map == 3'b000 || partner_lane_map == 3'b000) begin
            final_lane_map = 3'b000;
            degrade_not_possible = 1'b1;
        end
        else if (local_lane_map == 3'b011 && partner_lane_map == 3'b011) begin
            final_lane_map = 3'b011; // remain at x16
        end
        else if ((local_lane_map inside {3'b011, 3'b001}) && (partner_lane_map inside {3'b011, 3'b001})) begin
            final_lane_map = 3'b001; // Lower x8
        end
        else if ((local_lane_map inside {3'b011, 3'b010}) && (partner_lane_map inside {3'b011, 3'b010})) begin
            final_lane_map = 3'b010; // Upper x8
        end
        else if (allow_x4_mode) begin
            if ((local_lane_map inside {3'b011, 3'b001, 3'b100}) && (partner_lane_map inside {3'b011, 3'b001, 3'b100})) begin
                final_lane_map = 3'b100; // lanes 0-3
            end
            else if ((local_lane_map inside {3'b011, 3'b001, 3'b101}) && (partner_lane_map inside {3'b011, 3'b001, 3'b101})) begin
                final_lane_map = 3'b101; // lanes 4-7
            end
            else begin
                final_lane_map = 3'b000;
                degrade_not_possible = 1'b1;
            end
        end
        else begin
            final_lane_map = 3'b000;
            degrade_not_possible = 1'b1;
        end
    end

    ////////////////////////////////////////////////////////
    // RETRY & TIMER CONTROLS
    ////////////////////////////////////////////////////////
    logic retry_done;
    logic retry_start;

    assign retry_start = (current_state == MB_S4_DEGRADE_VERIFICATION) && width_changed_r && !degrade_not_possible_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retry_done <= 1'b0;
        end
        else if (retry_start) begin
            retry_done <= 1'b1;
        end
        else if (current_state == MB_S0_IDLE) begin
            retry_done <= 1'b0;
        end
    end

    // Watchdog Timer Enable
    assign timeout_repair_enable = mb_repairmb_enable && !mb_repairmb_done && !mb_repairmb_error;
    
    logic timeout_error;
    assign timeout_error = timeout_repair_expired && !mb_repairmb_done;

    ////////////////////////////////////////////////////////
    // STICKY HANDSHAKE FLAGS & CAPTURES
    ////////////////////////////////////////////////////////
    logic s1_req_rcvd;
    logic s1_rsp_rcvd;
    logic s3_req_rcvd;
    logic s3_rsp_rcvd;
    logic s5_req_rcvd;
    logic s5_rsp_rcvd;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_req_rcvd          <= 1'b0;
            s1_rsp_rcvd          <= 1'b0;
            s3_req_rcvd          <= 1'b0;
            s3_rsp_rcvd          <= 1'b0;
            s5_req_rcvd          <= 1'b0;
            s5_rsp_rcvd          <= 1'b0;
            partner_lane_map     <= 3'b000;
            mb_rx_perlane_result <= 16'h0;
        end
        else if (current_state == MB_S0_IDLE) begin
            s1_req_rcvd          <= 1'b0;
            s1_rsp_rcvd          <= 1'b0;
            s3_req_rcvd          <= 1'b0;
            s3_rsp_rcvd          <= 1'b0;
            s5_req_rcvd          <= 1'b0;
            s5_rsp_rcvd          <= 1'b0;
            partner_lane_map     <= 3'b000;
            mb_rx_perlane_result <= 16'h0;
        end
        else if (retry_start) begin
            // Clear S3 & S5 handshakes on retry, but keep S1
            s3_req_rcvd          <= 1'b0;
            s3_rsp_rcvd          <= 1'b0;
            s5_req_rcvd          <= 1'b0;
            s5_rsp_rcvd          <= 1'b0;
            partner_lane_map     <= 3'b000;
            mb_rx_perlane_result <= 16'h0;
        end
        else begin
            // Latch per-lane status when the point test completes
            if (current_state == MB_S2_D2C_POINT_TEST && mb_tx_data_pattern_transmission_completed) begin
                mb_rx_perlane_result <= mb_rx_perlane_status;
            end

            // Capture partner sideband messages
            if (mb_repairmb_rx_valid) begin
                case (mb_repairmb_rx_msg_id)
                    MBINIT_REPAIRMB_start_req: begin
                        s1_req_rcvd <= 1'b1;
                    end
                    MBINIT_REPAIRMB_start_resp: begin
                        s1_rsp_rcvd <= 1'b1;
                    end
                    MBINIT_REPAIRMB_apply_degrade_req: begin
                        s3_req_rcvd      <= 1'b1;
                        partner_lane_map <= mb_repairmb_rx_MsgInfo[2:0];
                    end
                    MBINIT_REPAIRMB_apply_degrade_resp: begin
                        s3_rsp_rcvd <= 1'b1;
                    end
                    MBINIT_REPAIRMB_end_req: begin
                        s5_req_rcvd <= 1'b1;
                    end
                    MBINIT_REPAIRMB_end_resp: begin
                        s5_rsp_rcvd <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // Track width changes & decision registrations
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            final_lane_map_r       <= 3'b011;
            degrade_not_possible_r <= 1'b0;
            width_changed_r        <= 1'b0;
        end
        else if (current_state == MB_S0_IDLE) begin
            final_lane_map_r       <= reg_x8_mode_req ? 3'b001 : 3'b011;
            degrade_not_possible_r <= 1'b0;
            width_changed_r        <= 1'b0;
        end
        else if (current_state == MB_S3_DEGRADE_RSP_WAIT && s3_rsp_rcvd) begin
            final_lane_map_r       <= final_lane_map;
            degrade_not_possible_r <= degrade_not_possible;
            width_changed_r        <= (final_lane_map != prev_lane_map);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_lane_map <= 3'b011;
        end
        else if (current_state == MB_S0_IDLE) begin
            prev_lane_map <= reg_x8_mode_req ? 3'b001 : 3'b011;
        end
        else if (current_state == MB_S4_DEGRADE_VERIFICATION) begin
            prev_lane_map <= final_lane_map_r;
        end
    end

    ////////////////////////////////////////////////////////
    // STATE REGISTER
    ////////////////////////////////////////////////////////
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= MB_S0_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    ////////////////////////////////////////////////////////
    // NEXT STATE LOGIC
    ////////////////////////////////////////////////////////
    always_comb begin
        next_state = current_state;

        if (!mb_repairmb_enable) begin
            next_state = MB_S0_IDLE;
        end
        else if (timeout_error) begin
            next_state = MB_S6_REPAIR_ERROR;
        end
        else begin
            case (current_state)
                MB_S0_IDLE: begin
                    if (mb_repairmb_enable)
                        next_state = MB_S1_READY_REQ_SEND;
                end

                // ── S1 Readiness REQ ──
                MB_S1_READY_REQ_SEND: begin
                    if (ltsm_rdy)       next_state = MB_S1_READY_REQ_WAIT;
                end
                MB_S1_READY_REQ_WAIT: begin
                    if (s1_req_rcvd)    next_state = MB_S1_READY_RSP_SEND;
                end

                // ── S1 Readiness RSP ──
                MB_S1_READY_RSP_SEND: begin
                    if (ltsm_rdy)       next_state = MB_S1_READY_RSP_WAIT;
                end
                MB_S1_READY_RSP_WAIT: begin
                    if (s1_rsp_rcvd)    next_state = MB_S2_D2C_POINT_TEST;
                end

                // ── S2 Point Test ──
                MB_S2_D2C_POINT_TEST: begin
                    if (mb_tx_data_pattern_transmission_completed)
                        next_state = MB_S3_DEGRADE_REQ_SEND;
                end

                // ── S3 Degrade REQ ──
                MB_S3_DEGRADE_REQ_SEND: begin
                    if (ltsm_rdy)       next_state = MB_S3_DEGRADE_REQ_WAIT;
                end
                MB_S3_DEGRADE_REQ_WAIT: begin
                    if (s3_req_rcvd)    next_state = MB_S3_DEGRADE_RSP_SEND;
                end

                // ── S3 Degrade RSP ──
                MB_S3_DEGRADE_RSP_SEND: begin
                    if (ltsm_rdy)       next_state = MB_S3_DEGRADE_RSP_WAIT;
                end
                MB_S3_DEGRADE_RSP_WAIT: begin
                    if (s3_rsp_rcvd)    next_state = MB_S4_DEGRADE_VERIFICATION;
                end

                // ── S4 Verification ──
                MB_S4_DEGRADE_VERIFICATION: begin
                    if (degrade_not_possible_r) begin
                        next_state = MB_S6_REPAIR_ERROR;
                    end
                    else if (width_changed_r) begin
                        if (!retry_done)
                            next_state = MB_S2_D2C_POINT_TEST; // Retry
                        else
                            next_state = MB_S6_REPAIR_ERROR; // Double fail
                    end
                    else begin
                        next_state = MB_S5_FINALIZE_REQ_SEND;
                    end
                end

                // ── S5 Finalize REQ ──
                MB_S5_FINALIZE_REQ_SEND: begin
                    if (ltsm_rdy)       next_state = MB_S5_FINALIZE_REQ_WAIT;
                end
                MB_S5_FINALIZE_REQ_WAIT: begin
                    if (s5_req_rcvd)    next_state = MB_S5_FINALIZE_RSP_SEND;
                end

                // ── S5 Finalize RSP ──
                MB_S5_FINALIZE_RSP_SEND: begin
                    if (ltsm_rdy)       next_state = MB_S5_FINALIZE_RSP_WAIT;
                end
                MB_S5_FINALIZE_RSP_WAIT: begin
                    if (s5_rsp_rcvd)    next_state = MB_S7_REPAIR_DONE;
                end

                MB_S6_REPAIR_ERROR: begin
                    // Stays here until mb_repairmb_enable deasserts
                end

                MB_S7_REPAIR_DONE: begin
                    // Stays here until mb_repairmb_enable deasserts
                end

                default: next_state = MB_S0_IDLE;
            endcase
        end
    end

    ////////////////////////////////////////////////////////
    // TX SIDEBAND MESSAGE CONTROLS
    ////////////////////////////////////////////////////////
    always_comb begin
        mb_repairmb_tx_valid      = 1'b0;
        mb_repairmb_tx_msg_id     = msg_no_e'(NOTHING);
        mb_repairmb_tx_MsgInfo    = MB_default_MSG_Info;
        mb_repairmb_tx_data_Field = MB_default_data_Field;

        case (current_state)
            MB_S1_READY_REQ_SEND: begin
                mb_repairmb_tx_valid  = 1'b1;
                mb_repairmb_tx_msg_id = MBINIT_REPAIRMB_start_req;
            end

            MB_S1_READY_RSP_SEND: begin
                mb_repairmb_tx_valid  = 1'b1;
                mb_repairmb_tx_msg_id = MBINIT_REPAIRMB_start_resp;
            end

            MB_S3_DEGRADE_REQ_SEND: begin
                mb_repairmb_tx_valid   = 1'b1;
                mb_repairmb_tx_msg_id  = MBINIT_REPAIRMB_apply_degrade_req;
                mb_repairmb_tx_MsgInfo = {13'b0, local_lane_map};
            end

            MB_S3_DEGRADE_RSP_SEND: begin
                mb_repairmb_tx_valid   = 1'b1;
                mb_repairmb_tx_msg_id  = MBINIT_REPAIRMB_apply_degrade_resp;
                mb_repairmb_tx_MsgInfo = {13'b0, final_lane_map_r};
            end

            MB_S5_FINALIZE_REQ_SEND: begin
                mb_repairmb_tx_valid  = 1'b1;
                mb_repairmb_tx_msg_id = MBINIT_REPAIRMB_end_req;
            end

            MB_S5_FINALIZE_RSP_SEND: begin
                mb_repairmb_tx_valid  = 1'b1;
                mb_repairmb_tx_msg_id = MBINIT_REPAIRMB_end_resp;
            end

            default: ;
        endcase
    end

    ////////////////////////////////////////////////////////
    // PATTERN ENGINE CONTROLS
    ////////////////////////////////////////////////////////
    assign mb_tx_data_pattern_sel = 1'b1; // per-lane ID pattern
    assign mb_rx_compare_setup    = 1'b1; // per-lane comparison

    assign mb_tx_data_pattern_en  = (current_state == MB_S2_D2C_POINT_TEST);

    // RX compare enable timing logic
    always_comb begin
        mb_rx_data_compare_en = 1'b0;
        case (current_state)
            MB_S1_READY_RSP_SEND,
            MB_S1_READY_RSP_WAIT,
            MB_S2_D2C_POINT_TEST,
            MB_S3_DEGRADE_REQ_SEND,
            MB_S3_DEGRADE_REQ_WAIT: begin
                mb_rx_data_compare_en = 1'b1;
            end
            default: begin
                mb_rx_data_compare_en = 1'b0;
            end
        endcase
    end

    // Clear Error to RX comparator
    always_comb begin
        clear_error_req = 1'b0;
        if (current_state == MB_S0_IDLE) begin
            clear_error_req = 1'b1;
        end
        else if (retry_start) begin
            clear_error_req = 1'b1;
        end
    end

    ////////////////////////////////////////////////////////
    // OUTPUT SUCCESS/DONE/ERROR ASSIGNMENTS
    ////////////////////////////////////////////////////////
    always_comb begin
        mb_repairmb_done  = (current_state == MB_S7_REPAIR_DONE);
        mb_repairmb_error = (current_state == MB_S6_REPAIR_ERROR);
    end

    ////////////////////////////////////////////////////////
    // DEBUG DISPLAY
    ////////////////////////////////////////////////////////
    always @(posedge clk) begin
        if (current_state == MB_S4_DEGRADE_VERIFICATION) begin
            $display("DUT DEBUG: current_state=S4, width_changed_r=%b, degrade_not_possible_r=%b, retry_start=%b, retry_done=%b, prev_lane_map=%b, final_lane_map_r=%b",
                width_changed_r, degrade_not_possible_r, retry_start, retry_done, prev_lane_map, final_lane_map_r);
        end
    end

endmodule