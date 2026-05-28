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

    input  logic [3:0] Link_Width_enable_status,
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


    // d2cptest interface
    output logic            tx_pt_en,
    output logic [2:0]      d2c_pattern_setup,// 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    output logic [1:0]      d2c_data_pattern_sel, // Data pattern used during training: 0h: LFSR, 1: ID, or all 0.
    output logic            d2c_pattern_mode,// 0: Continuous Pattern Mode, 1: Burst Pattern Mode. 
    output logic [1:0]      d2c_compare_setup, // 0: Aggregate, 1: Per-Lane, 2: Valid Lane, 3: Clock Lane Comparison.

    input logic [15:0] d2c_perlane_pass, // The Per-Lane Errors (Each bit represents one pass Data Lane).

    input logic test_d2c_done,

    // Clear Error request to comparator
    output logic            clear_error_req,

    // Output lane maps
    output logic [2:0]      mbinit_rx_data_lane_mask,
    output logic [2:0]      mbinit_tx_data_lane_mask
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
        MB_S7_REPAIR_DONE,
        MB_S8_ALIGN_CHECK
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
    logic [2:0]  prev_partner_lane_map;
    logic [2:0]  prev_lane_map;
    logic        degrade_not_possible;
    logic        degrade_not_possible_r;
    logic        width_changed_r;
    logic        retry_done;
    logic        retry_start;

    logic        s1_req_rcvd;
    logic        s1_rsp_rcvd;
    logic        s3_req_rcvd;
    logic        s3_rsp_rcvd;
    logic        s5_req_rcvd;
    logic        s5_rsp_rcvd;
    logic        s5_degrade_rsp_pending;

    logic [15:0] mb_rx_perlane_result;
    logic        allow_x4_mode;

    logic reg_x8_mode_req;
    assign reg_x8_mode_req = (Link_Width_enable_status == 4'h1);

    assign allow_x4_mode = reg_x8_mode_req || SPMW;

    logic [2:0] mbinit_rx_data_lane_mask_r;
    logic [2:0] mbinit_tx_data_lane_mask_r;

    logic        local_lower_x4_pass;
    logic        local_upper_x4_pass;

    // Helper functions for width alignment
    function automatic int get_width(logic [2:0] map);
        case (map)
            3'b011:  return 16;
            3'b001:  return 8;
            3'b010:  return 8;
            3'b100:  return 4;
            3'b101:  return 4;
            default: return 0;
        endcase
    endfunction

    function automatic logic [2:0] degrade_map_to_width(logic [2:0] orig_map, int target_w, logic lower_x4, logic upper_x4);
        int orig_w;
        orig_w = get_width(orig_map);
        if (orig_w <= target_w) return orig_map;
        
        case (target_w)
            8: begin
                if (orig_map == 3'b011) return 3'b001; // Degrade x16 to lower x8
                else return orig_map;
            end
            4: begin
                if (orig_map == 3'b011 || orig_map == 3'b001) begin
                    if (lower_x4) return 3'b100;
                    else if (upper_x4) return 3'b101;
                    else return 3'b000;
                end
                else if (orig_map == 3'b010) begin
                    if (upper_x4) return 3'b101;
                    else if (lower_x4) return 3'b100;
                    else return 3'b000;
                end
                else return 3'b000;
            end
            default: return orig_map;
        endcase
    endfunction

    logic [2:0] aligned_tx;
    logic [2:0] aligned_rx;

    always_comb begin
        int tx_w, rx_w, min_w;
        tx_w = get_width(mbinit_tx_data_lane_mask_r);
        rx_w = get_width(mbinit_rx_data_lane_mask_r);
        min_w = (tx_w < rx_w) ? tx_w : rx_w;

        aligned_tx = degrade_map_to_width(mbinit_tx_data_lane_mask_r, min_w, local_lower_x4_pass, local_upper_x4_pass);
        aligned_rx = degrade_map_to_width(mbinit_rx_data_lane_mask_r, min_w, local_lower_x4_pass, local_upper_x4_pass);
    end

    assign mbinit_rx_data_lane_mask = mbinit_rx_data_lane_mask_r;
    assign mbinit_tx_data_lane_mask = mbinit_tx_data_lane_mask_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mbinit_rx_data_lane_mask_r <= 3'b011;
            mbinit_tx_data_lane_mask_r <= 3'b011;
        end
        else if (current_state == MB_S0_IDLE) begin
            mbinit_rx_data_lane_mask_r <= 3'b011;
            mbinit_tx_data_lane_mask_r <= 3'b011;
        end
        else begin
            if (current_state == MB_S3_DEGRADE_REQ_SEND) begin
                mbinit_tx_data_lane_mask_r <= local_lane_map;
            end
            if (mb_repairmb_rx_valid && (mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_apply_degrade_req)) begin
                mbinit_rx_data_lane_mask_r <= mb_repairmb_rx_MsgInfo[2:0];
            end

            if (current_state == MB_S8_ALIGN_CHECK) begin
                if (aligned_tx == 3'b000 || aligned_rx == 3'b000) begin
                    mbinit_rx_data_lane_mask_r <= 3'b000;
                    mbinit_tx_data_lane_mask_r <= 3'b000;
                end
                else begin
                    mbinit_rx_data_lane_mask_r <= aligned_rx;
                    mbinit_tx_data_lane_mask_r <= aligned_tx;
                end
            end
        end
    end

    // Local Degrade Map calculation based on per-lane error results
    // d2c_perlane_pass bit is 1 for pass and 0 for fail
    logic [2:0] raw_local_map;
    always_comb begin
        raw_local_map = 3'b000; // default to fail

        // Priority Encoder logic:
        // 1. x16 full width: if negotiated x16 and all lanes pass
        if (!allow_x4_mode && (mb_rx_perlane_result == 16'hFFFF)) begin
            raw_local_map = 3'b011; // x16 full width (all lanes pass)
        end
        // 2. lower x8 operational: if lanes 0-7 pass
        else if (mb_rx_perlane_result[7:0] == 8'hFF) begin
            raw_local_map = 3'b001; // lower x8 operational (Lanes 0-7 PASS)
        end
        // 3. upper x8 operational: if lanes 8-15 pass
        else if (mb_rx_perlane_result[15:8] == 8'hFF) begin
            raw_local_map = 3'b010; // upper x8 operational (Lanes 8-15 PASS)
        end
        // 4. lanes 0-3 operational (under x4 mode allow)
        else if (allow_x4_mode && (mb_rx_perlane_result[3:0] == 4'hF)) begin
            raw_local_map = 3'b100; // lanes 0-3 operational (Lanes 0-3 PASS)
        end
        // 5. lanes 4-7 operational (under x4 mode allow)
        else if (allow_x4_mode && (mb_rx_perlane_result[7:4] == 4'hF)) begin
            raw_local_map = 3'b101; // lanes 4-7 operational (Lanes 4-7 PASS)
        end
    end

    always_comb begin
        if (retry_done) begin
            local_lane_map = prev_lane_map;
        end
        else begin
            if (current_state >= MB_S3_DEGRADE_RSP_WAIT) begin
                int local_w, partner_w, min_w;
                local_w   = get_width(raw_local_map);
                partner_w = get_width(partner_lane_map);
                min_w     = (local_w < partner_w) ? local_w : partner_w;

                local_lane_map = degrade_map_to_width(raw_local_map, min_w, local_lower_x4_pass, local_upper_x4_pass);
            end
            else begin
                local_lane_map = raw_local_map;
            end
        end
    end

    // Agreement Resolution Logic (Asymmetric Link Support)
    // The Tx on each Die is configured according to local_lane_map,
    // and the Rx is configured according to partner_lane_map.
    logic [15:0] partner_mask;
    always_comb begin
        case (partner_lane_map)
            3'b011:  partner_mask = 16'hFFFF;
            3'b001:  partner_mask = 16'h00FF;
            3'b010:  partner_mask = 16'hFF00;
            3'b100:  partner_mask = 16'h000F;
            3'b101:  partner_mask = 16'h00F0;
            default: partner_mask = 16'h0000;
        endcase
    end

    logic [2:0] expected_partner_lane_map;
    always_comb begin
        if (retry_done) begin
            int partner_w;
            partner_w = get_width(partner_lane_map);
            expected_partner_lane_map = degrade_map_to_width(prev_partner_lane_map, partner_w, local_lower_x4_pass, local_upper_x4_pass);
        end
        else begin
            expected_partner_lane_map = prev_partner_lane_map;
        end
    end

    logic retry_rx_pass;
    assign retry_rx_pass = ((mb_rx_perlane_result & partner_mask) == partner_mask);

    assign degrade_not_possible = (local_lane_map == 3'b000) ||
                                  (partner_lane_map == 3'b000) ||
                                  (retry_done && !retry_rx_pass) ||
                                  (retry_done && (partner_lane_map != expected_partner_lane_map));

    ////////////////////////////////////////////////////////
    // RETRY & TIMER CONTROLS
    ////////////////////////////////////////////////////////

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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_req_rcvd           <= 1'b0;
            s1_rsp_rcvd           <= 1'b0;
            s3_req_rcvd           <= 1'b0;
            s3_rsp_rcvd           <= 1'b0;
            s5_req_rcvd           <= 1'b0;
            s5_rsp_rcvd           <= 1'b0;
            partner_lane_map      <= 3'b000;
            prev_partner_lane_map <= 3'b000;
            mb_rx_perlane_result  <= 16'h0;
            local_lower_x4_pass   <= 1'b0;
            local_upper_x4_pass   <= 1'b0;
        end
        else if (current_state == MB_S0_IDLE) begin
            s1_req_rcvd           <= 1'b0;
            s1_rsp_rcvd           <= 1'b0;
            s3_req_rcvd           <= 1'b0;
            s3_rsp_rcvd           <= 1'b0;
            s5_req_rcvd           <= 1'b0;
            s5_rsp_rcvd           <= 1'b0;
            partner_lane_map      <= allow_x4_mode ? 3'b001 : 3'b011;
            prev_partner_lane_map <= 3'b000;
            mb_rx_perlane_result  <= 16'h0;
            local_lower_x4_pass   <= 1'b0;
            local_upper_x4_pass   <= 1'b0;
        end
        else if (retry_start) begin
            // Clear S3 & S5 handshakes on retry, but keep S1 and partner_lane_map
            s3_req_rcvd          <= 1'b0;
            s3_rsp_rcvd          <= 1'b0;
            s5_req_rcvd          <= 1'b0;
            s5_rsp_rcvd          <= 1'b0;
            mb_rx_perlane_result <= 16'h0;
        end
        else begin
            // Latch per-lane status when the point test completes
            if (current_state == MB_S2_D2C_POINT_TEST && test_d2c_done) begin
                mb_rx_perlane_result <= d2c_perlane_pass;
                local_lower_x4_pass   <= (d2c_perlane_pass[3:0] == 4'hF);
                local_upper_x4_pass   <= (d2c_perlane_pass[7:4] == 4'hF);
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

            if (current_state == MB_S3_DEGRADE_RSP_WAIT && s3_rsp_rcvd && !retry_done) begin
                prev_partner_lane_map <= partner_lane_map;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s5_degrade_rsp_pending <= 1'b0;
        end
        else if (current_state == MB_S0_IDLE) begin
            s5_degrade_rsp_pending <= 1'b0;
        end
        else begin
            if (current_state == MB_S5_FINALIZE_REQ_WAIT && 
                mb_repairmb_rx_valid && (mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_apply_degrade_req)) begin
                s5_degrade_rsp_pending <= 1'b1;
            end
            else if (current_state == MB_S3_DEGRADE_RSP_SEND && ltsm_rdy) begin
                s5_degrade_rsp_pending <= 1'b0;
            end
        end
    end

    // Track width changes & decision registrations
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            degrade_not_possible_r <= 1'b0;
            width_changed_r        <= 1'b0;
        end
        else if (current_state == MB_S0_IDLE) begin
            degrade_not_possible_r <= 1'b0;
            width_changed_r        <= 1'b0;
        end
        else if (current_state == MB_S3_DEGRADE_RSP_WAIT && s3_rsp_rcvd) begin
            degrade_not_possible_r <= degrade_not_possible;
            width_changed_r        <= (local_lane_map != prev_lane_map);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_lane_map <= 3'b011;
        end
        else if (current_state == MB_S0_IDLE) begin
            prev_lane_map <= 3'b011;
        end
        else if (current_state == MB_S4_DEGRADE_VERIFICATION) begin
            prev_lane_map <= local_lane_map;
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
                    if (test_d2c_done)
                        next_state = MB_S3_DEGRADE_REQ_SEND;
                end

                // ── S3 Degrade REQ ──
                MB_S3_DEGRADE_REQ_SEND: begin
                    if (ltsm_rdy)       next_state = MB_S3_DEGRADE_REQ_WAIT;
                end
                MB_S3_DEGRADE_REQ_WAIT: begin
                    if (s3_req_rcvd)
                        next_state = MB_S3_DEGRADE_RSP_SEND;
                    else if (s3_rsp_rcvd)
                        next_state = MB_S3_DEGRADE_RSP_WAIT;
                end

                // ── S3 Degrade RSP ──
                MB_S3_DEGRADE_RSP_SEND: begin
                    if (ltsm_rdy) begin
                        if (s5_degrade_rsp_pending)
                            next_state = MB_S5_FINALIZE_REQ_WAIT;
                        else
                            next_state = MB_S3_DEGRADE_RSP_WAIT;
                    end
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
                    if (mb_repairmb_rx_valid && (mb_repairmb_rx_msg_id == MBINIT_REPAIRMB_apply_degrade_req))
                        next_state = MB_S3_DEGRADE_RSP_SEND;
                    else if (s5_req_rcvd)
                        next_state = MB_S5_FINALIZE_RSP_SEND;
                end

                // ── S5 Finalize RSP ──
                MB_S5_FINALIZE_RSP_SEND: begin
                    if (ltsm_rdy)       next_state = MB_S5_FINALIZE_RSP_WAIT;
                end
                MB_S5_FINALIZE_RSP_WAIT: begin
                    if (s5_rsp_rcvd)    next_state = MB_S8_ALIGN_CHECK;
                end

                MB_S8_ALIGN_CHECK: begin
                    if (aligned_tx == 3'b000 || aligned_rx == 3'b000) begin
                        next_state = MB_S6_REPAIR_ERROR;
                    end
                    else begin
                        next_state = MB_S7_REPAIR_DONE;
                    end
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
                mb_repairmb_tx_valid  = 1'b1;
                mb_repairmb_tx_msg_id = MBINIT_REPAIRMB_apply_degrade_resp;
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
    
    

    assign d2c_pattern_setup = 3'b001; // Data pattern
    assign d2c_pattern_mode = 1'b0; // Continuous Pattern Mode
    assign d2c_data_pattern_sel = 2'b01; // per-lane ID pattern


    assign d2c_compare_setup    = 2'b01; // per-lane comparison
    assign tx_pt_en  = (current_state == MB_S2_D2C_POINT_TEST);

    // RX compare enable timing logic (No longer needed since mb_rx_data_compare_en port is removed)

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
    // DEBUG DISPLAY & SYSTEMVERILOG ASSERTIONS
    ////////////////////////////////////////////////////////
    `ifdef SIMULATION
        always @(posedge clk) begin
            if (current_state == MB_S4_DEGRADE_VERIFICATION) begin
                $display("DUT DEBUG: current_state=S4, width_changed_r=%b, degrade_not_possible_r=%b, retry_start=%b, retry_done=%b, prev_lane_map=%b, local_lane_map=%b",
                    width_changed_r, degrade_not_possible_r, retry_start, retry_done, prev_lane_map, local_lane_map);
            end
        end

        // ========================================================
        // SYSTEMVERILOG ASSERTIONS (SVA) FOR REPAIRMB ROBUSTNESS
        // ========================================================

        // 1. Handshake Integrity: No start_resp sent without start_req received first
        property p_tx_start_resp_after_req;
            @(posedge clk) disable iff (!rst_n)
            (mb_repairmb_tx_valid && mb_repairmb_tx_msg_id == MBINIT_REPAIRMB_start_resp) |-> s1_req_rcvd;
        endproperty
        assert_tx_start_resp_after_req: assert property(p_tx_start_resp_after_req);

        // 2. Handshake Integrity: No apply_degrade_resp sent without apply_degrade_req received first
        property p_tx_degrade_resp_after_req;
            @(posedge clk) disable iff (!rst_n)
            (mb_repairmb_tx_valid && mb_repairmb_tx_msg_id == MBINIT_REPAIRMB_apply_degrade_resp) |-> (s3_req_rcvd || s5_degrade_rsp_pending);
        endproperty
        assert_tx_degrade_resp_after_req: assert property(p_tx_degrade_resp_after_req);

        // 3. Handshake Integrity: No end_resp sent without end_req received first
        property p_tx_end_resp_after_req;
            @(posedge clk) disable iff (!rst_n)
            (mb_repairmb_tx_valid && mb_repairmb_tx_msg_id == MBINIT_REPAIRMB_end_resp) |-> s5_req_rcvd;
        endproperty
        assert_tx_end_resp_after_req: assert property(p_tx_end_resp_after_req);

        // 4. Bounded Liveness: start_req must eventually be answered or enter S6 error
        property p_start_req_leads_to_resp_or_error;
            @(posedge clk) disable iff (!rst_n)
            (current_state == MB_S1_READY_REQ_WAIT) |-> (##[1:2000] (s1_rsp_rcvd || current_state == MB_S6_REPAIR_ERROR));
        endproperty
        assert_start_req_leads_to_resp_or_error: assert property(p_start_req_leads_to_resp_or_error);

        // 5. Bounded Liveness: apply_degrade_req must eventually be answered or enter S6 error
        property p_degrade_req_leads_to_resp_or_error;
            @(posedge clk) disable iff (!rst_n)
            (current_state == MB_S3_DEGRADE_RSP_WAIT) |-> (##[1:2000] (s3_rsp_rcvd || current_state == MB_S6_REPAIR_ERROR));
        endproperty
        assert_degrade_req_leads_to_resp_or_error: assert property(p_degrade_req_leads_to_resp_or_error);

        // 6. Bounded Liveness: end_req must eventually be answered or enter S6 error
        property p_end_req_leads_to_resp_or_error;
            @(posedge clk) disable iff (!rst_n)
            (current_state == MB_S5_FINALIZE_RSP_WAIT) |-> (##[1:2000] (s5_rsp_rcvd || current_state == MB_S6_REPAIR_ERROR));
        endproperty
        assert_end_req_leads_to_resp_or_error: assert property(p_end_req_leads_to_resp_or_error);

        // 7. Initial Check: First point test must check all 16 lanes (force x16 mask regardless of allow_x4_mode)
        property p_first_test_uses_x16;
            @(posedge clk) disable iff (!rst_n)
            (current_state == MB_S2_D2C_POINT_TEST && !retry_done) |-> 
            (mbinit_rx_data_lane_mask == 3'b011 && mbinit_tx_data_lane_mask == 3'b011);
        endproperty
        assert_first_test_uses_x16: assert property(p_first_test_uses_x16);

        // 8. Protocol Rule: Sideband TX stability until ltsm_rdy asserts
        property p_tx_stability_until_rdy;
            @(posedge clk) disable iff (!rst_n || !mb_repairmb_enable)
            (mb_repairmb_tx_valid && !ltsm_rdy) |-> 
            ##1 (mb_repairmb_tx_valid && 
                 $stable(mb_repairmb_tx_msg_id) && 
                 $stable(mb_repairmb_tx_MsgInfo) && 
                 $stable(mb_repairmb_tx_data_Field));
        endproperty
        assert_tx_stability_until_rdy: assert property(p_tx_stability_until_rdy);

        // 9. Error Check: Error states raise error flag
        property p_error_condition_raises_error;
            @(posedge clk) disable iff (!rst_n)
            (timeout_repair_expired && mb_repairmb_enable) ||
            (current_state == MB_S4_DEGRADE_VERIFICATION && degrade_not_possible_r) ||
            (current_state == MB_S4_DEGRADE_VERIFICATION && width_changed_r && retry_done)
            |-> ##[1:5] (current_state == MB_S6_REPAIR_ERROR && mb_repairmb_error == 1'b1);
        endproperty
        assert_error_condition_raises_error: assert property(p_error_condition_raises_error);

        // 10. Success Check: Done state asserts done flag
        property p_success_path_leads_to_done;
            @(posedge clk) disable iff (!rst_n)
            (current_state == MB_S5_FINALIZE_RSP_WAIT && s5_rsp_rcvd && !timeout_repair_expired)
            |-> ##[1:5] (current_state == MB_S7_REPAIR_DONE && mb_repairmb_done == 1'b1);
        endproperty
        assert_success_path_leads_to_done: assert property(p_success_path_leads_to_done);

        // 11. Safety Check: Done and Error are mutually exclusive
        assert_never_done_and_error: assert property (
            @(posedge clk) disable iff (!rst_n) 
            !(mb_repairmb_done && mb_repairmb_error)
        );

        // 12. Safety Check: retry_done is sticky until return to S0 IDLE
        property p_retry_done_sticky;
            @(posedge clk) disable iff (!rst_n)
            (retry_done) |-> (retry_done) until (current_state == MB_S0_IDLE);
        endproperty
        assert_retry_done_sticky: assert property(p_retry_done_sticky);

        // 13. State Coverage Checks
        cover_state_idle:         cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S0_IDLE);
        cover_state_s1_req_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_READY_REQ_SEND);
        cover_state_s1_req_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_READY_REQ_WAIT);
        cover_state_s1_rsp_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_READY_RSP_SEND);
        cover_state_s1_rsp_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_READY_RSP_WAIT);
        cover_state_s2_point_test:cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S2_D2C_POINT_TEST);
        cover_state_s3_req_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_DEGRADE_REQ_SEND);
        cover_state_s3_req_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_DEGRADE_REQ_WAIT);
        cover_state_s3_rsp_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_DEGRADE_RSP_SEND);
        cover_state_s3_rsp_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_DEGRADE_RSP_WAIT);
        cover_state_s4_verify:    cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S4_DEGRADE_VERIFICATION);
        cover_state_s5_req_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_FINALIZE_REQ_SEND);
        cover_state_s5_req_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_FINALIZE_REQ_WAIT);
        cover_state_s5_rsp_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_FINALIZE_RSP_SEND);
        cover_state_s5_rsp_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_FINALIZE_RSP_WAIT);
        cover_state_s6_error:     cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S6_REPAIR_ERROR);
        cover_state_s7_done:      cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S7_REPAIR_DONE);
    `endif

endmodule