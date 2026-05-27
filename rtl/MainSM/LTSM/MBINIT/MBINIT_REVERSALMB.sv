/*
{MBINIT.REVERSALMB result resp} *Data Field*
==================================================
The error condition for this flow is NOT observing 16 consecutive iterations of the 
expected pattern. The error threshold is always 0 for this test.

[63:0]: Compare Results of individual Data Lanes :-
- 0h: Fail (Errors > Max Error Threshold) 
- 1h: Pass (Errors <= Max Error Threshold)

    UCIe-S x16 {48'h0, RD_L[15], RD_L[14], …, RD_L[1], RD_L[0]}
    UCIe-S x8  {56'h0, RD_L[7], RD_L[6], …, RD_L[1], RD_L[0]}

    -/-/-/-/-/-/-/-/-/-/-/-//-/-/-/-/-/-/-/-/-/-/-/-/-/-/-//-/-/-/-/-//
    |     Interface with mainband         |
    |          NEW SIGNALS                |
    |  output logic mb_lane_reversal_req, |
    |  output logic reg_x8_mode_req,       |
    |  output logic clear_error_req,      |
    |-------------------------------------|
        
    -/-/-/-/-/-/-/-/-/-/-/-//-/-/-/-/-/-/-/-/-/-/-/-/-/-/-//-/-/-/-/-//

*/

import UCIe_pkg::*;

module MBINIT_REVERSALMB
#( parameter int CLK_FRQ_HZ = 800000000)
(
    input  logic clk, rst_n,

    input  logic mb_reversal_enable,

    output logic mb_reversal_done,
    output logic mb_reversal_error,

    input  logic mb_reversal_rx_valid,
    input  msg_no_e mb_reversal_rx_msg_id,
    input  logic [15:0] mb_reversal_rx_MsgInfo,
    input  logic [63:0] mb_reversal_rx_data_Field,

    output logic mb_reversal_tx_valid,
    output msg_no_e mb_reversal_tx_msg_id,
    output logic [15:0] mb_reversal_tx_MsgInfo,
    output logic [63:0] mb_reversal_tx_data_Field,

    input  logic reg_x8_mode_req,
    ////////////////////////////////////////////////////

    // PATTERN
    output logic  mb_tx_data_pattern_sel, // 1: per lane id pattern    0: lfsr pattern
    output logic  mb_rx_compare_setup, // 1: per lane comparison   0: aggregate comparison

    output logic mb_tx_data_pattern_en,
    output logic mb_rx_data_compare_en,

    input logic [15:0] mb_rx_perlane_status,
    input logic mb_tx_data_pattern_transmission_completed,

    //new signals to be added to the interface with MB team.
    output logic mb_lane_reversal_req,
    
    output logic clear_error_req,

    ////////////////////////////////////////////////////

    // FIFO ready
    input  logic ltsm_rdy,

    // Timer signals
    input  logic timeout_reversal_expired,
    output logic timeout_reversal_enable
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

    // S2 Error Reset (clear error)
    MB_S2_ERROR_RESET_REQ_SEND,
    MB_S2_ERROR_RESET_REQ_WAIT,
    MB_S2_ERROR_RESET_RSP_SEND,
    MB_S2_ERROR_RESET_RSP_WAIT,

    // S3 Pattern
    MB_S3_PATTERN_TRANSMISSION,

    // S4 Result Exchange
    MB_S4_RESULT_REQ_SEND,
    MB_S4_RESULT_REQ_WAIT,
    MB_S4_RESULT_RSP_SEND,
    MB_S4_RESULT_RSP_WAIT,

    // S5 Decision
    MB_S5_DECISION,

    // S6 Finalize
    MB_S6_FINALIZE_REQ_SEND,
    MB_S6_FINALIZE_REQ_WAIT,
    MB_S6_FINALIZE_RSP_SEND,
    MB_S6_FINALIZE_RSP_WAIT,

    MB_S7_REVERSAL_ERROR,
    MB_S8_REVERSAL_DONE
} state_e;

state_e current_state, next_state;

////////////////////////////////////////////////////////
// WIDTH (FROM NEGOTIATION)
////////////////////////////////////////////////////////

////////////////////////////////////////////////////////
// SUCCESS COUNT
////////////////////////////////////////////////////////
logic retry_done;
logic [15:0] partner_result; // latched in always_ff below
logic [4:0] success_count;

always_comb begin
    success_count = 0;

    if (reg_x8_mode_req)
        for (int i = 0; i < 8; i++) 
            success_count += partner_result[i]; 
    else 
        for (int i = 0; i < 16; i++) 
            success_count += partner_result[i];       
end

logic majority_success;
assign majority_success = reg_x8_mode_req ? (success_count >= 4 ) : (success_count >= 8 );

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_lane_reversal_req <= 1'b0;
    else if (current_state == MB_S5_DECISION && !majority_success && !retry_done) begin
        mb_lane_reversal_req <= 1'b1;
    end
    else if (mb_lane_reversal_req)
        mb_lane_reversal_req <= 1'b0;
end

////////////////////////////////////////////////////////
// DEFAULTS
////////////////////////////////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0;

////////////////////////////////////////////////////////
// RESULT
////////////////////////////////////////////////////////
logic [15:0] mb_rx_perlane_status_result;

logic [63:0] MB_local_result_exchange_data_Field;
always_comb begin
    if (reg_x8_mode_req)
        MB_local_result_exchange_data_Field = {56'h0, mb_rx_perlane_status_result[7:0]};
    else
        MB_local_result_exchange_data_Field = {48'h0, mb_rx_perlane_status_result[15:0]};
end

////////////////////////////////////////////////////////
// TIMEOUT
////////////////////////////////////////////////////////
logic timeout_error;
assign timeout_error = timeout_reversal_expired && !mb_reversal_done;
assign timeout_reversal_enable = mb_reversal_enable && !mb_reversal_done && !mb_reversal_error;

////////////////////////////////////////////////////////
// RETRY LOGIC
////////////////////////////////////////////////////////

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        retry_done <= 0;

    else if(current_state == MB_S5_DECISION && !majority_success && !retry_done)
        retry_done <= 1;

    else if(current_state == MB_S0_IDLE)
        retry_done <= 0;
end

logic retry_start;
assign retry_start = (current_state == MB_S5_DECISION) && (!majority_success) && (!retry_done);

////////////////////////////////////////////////////////
// HANDSHAKE FLAGS + DATA CAPTURE
////////////////////////////////////////////////////////
logic s1_req_rcvd;
logic s1_rsp_rcvd;
logic s2_req_rcvd;
logic s2_rsp_rcvd;
logic s4_req_rcvd;
logic s4_rsp_rcvd;
logic s6_req_rcvd;
logic s6_rsp_rcvd;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_req_rcvd    <= 1'b0;
        s1_rsp_rcvd    <= 1'b0;
        s2_req_rcvd    <= 1'b0;
        s2_rsp_rcvd    <= 1'b0;
        s4_req_rcvd    <= 1'b0;
        s4_rsp_rcvd    <= 1'b0;
        s6_req_rcvd    <= 1'b0;
        s6_rsp_rcvd    <= 1'b0;
        partner_result <= 16'h0;
        mb_rx_perlane_status_result <= 16'h0;
    end else if (current_state == MB_S0_IDLE) begin
        s1_req_rcvd    <= 1'b0;
        s1_rsp_rcvd    <= 1'b0;
        s2_req_rcvd    <= 1'b0;
        s2_rsp_rcvd    <= 1'b0;
        s4_req_rcvd    <= 1'b0;
        s4_rsp_rcvd    <= 1'b0;
        s6_req_rcvd    <= 1'b0;
        s6_rsp_rcvd    <= 1'b0;
        partner_result <= 16'h0;
        mb_rx_perlane_status_result <= 16'h0;
    end else if (retry_start) begin
        s2_req_rcvd    <= 1'b0;
        s2_rsp_rcvd    <= 1'b0;
        s4_req_rcvd    <= 1'b0;
        s4_rsp_rcvd    <= 1'b0;
        s6_req_rcvd    <= 1'b0;
        s6_rsp_rcvd    <= 1'b0;
        partner_result <= 16'h0;
    end else if (mb_reversal_rx_valid) begin
        case (mb_reversal_rx_msg_id)
            MBINIT_REVERSALMB_init_req : s1_req_rcvd <= 1'b1;
            MBINIT_REVERSALMB_init_resp: s1_rsp_rcvd <= 1'b1;

            MBINIT_REVERSALMB_clear_error_req : begin 
                s2_req_rcvd <= 1'b1;
                clear_error_req <= 1'b1;
            end
            MBINIT_REVERSALMB_clear_error_resp: s2_rsp_rcvd <= 1'b1;

            MBINIT_REVERSALMB_result_req      : begin 
                s4_req_rcvd <= 1'b1;
                mb_rx_perlane_status_result <= mb_rx_perlane_status;
            end
            MBINIT_REVERSALMB_result_resp     : begin
                s4_rsp_rcvd <= 1'b1;
                if (reg_x8_mode_req)
                    partner_result <= {8'b0, mb_reversal_rx_data_Field[7:0]};
                else
                    partner_result <= mb_reversal_rx_data_Field[15:0];
            end

            MBINIT_REVERSALMB_done_req        : s6_req_rcvd <= 1'b1;
            MBINIT_REVERSALMB_done_resp       : s6_rsp_rcvd <= 1'b1;
            default                           : clear_error_req <= 1'b0;
        endcase
    end
    else begin
        clear_error_req <= 1'b0;
    end
end

////////////////////////////////////////////////////////
// STATE REGISTER
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= MB_S0_IDLE;
    else
        current_state <= next_state;
end

////////////////////////////////////////////////////////
// NEXT STATE
////////////////////////////////////////////////////////
always_comb begin
    next_state = current_state;

    if(!mb_reversal_enable) begin
        next_state = MB_S0_IDLE;
    end
    else if (timeout_error) begin
        next_state = MB_S7_REVERSAL_ERROR;
    end
    else begin
        case (current_state)
            MB_S0_IDLE: begin
                if (mb_reversal_enable)
                    next_state = MB_S1_READY_REQ_SEND;
            end

            // S1 Readiness REQ
            MB_S1_READY_REQ_SEND: begin
                if (ltsm_rdy)       next_state = MB_S1_READY_REQ_WAIT;
            end
            MB_S1_READY_REQ_WAIT: begin
                if (s1_req_rcvd)    next_state = MB_S1_READY_RSP_SEND;
            end

            // S1 Readiness RSP
            MB_S1_READY_RSP_SEND: begin
                if (ltsm_rdy)       next_state = MB_S1_READY_RSP_WAIT;
            end
            MB_S1_READY_RSP_WAIT: begin
                if (s1_rsp_rcvd)    next_state = MB_S2_ERROR_RESET_REQ_SEND;
            end

            // S2 Error Reset REQ
            MB_S2_ERROR_RESET_REQ_SEND: begin
                if (ltsm_rdy)       next_state = MB_S2_ERROR_RESET_REQ_WAIT;
            end
            MB_S2_ERROR_RESET_REQ_WAIT: begin
                if (s2_req_rcvd)    next_state = MB_S2_ERROR_RESET_RSP_SEND;
            end

            // S2 Error Reset RSP
            MB_S2_ERROR_RESET_RSP_SEND: begin
                if (ltsm_rdy)       next_state = MB_S2_ERROR_RESET_RSP_WAIT;
            end
            MB_S2_ERROR_RESET_RSP_WAIT: begin
                if (s2_rsp_rcvd)    next_state = MB_S3_PATTERN_TRANSMISSION;
            end

            // S3 Pattern Transmission
            MB_S3_PATTERN_TRANSMISSION: begin
                if (mb_tx_data_pattern_transmission_completed)
                    next_state = MB_S4_RESULT_REQ_SEND;
            end

            // S4 Result REQ
            MB_S4_RESULT_REQ_SEND: begin
                if (ltsm_rdy)       next_state = MB_S4_RESULT_REQ_WAIT;
            end
            MB_S4_RESULT_REQ_WAIT: begin
                if (s4_req_rcvd)    next_state = MB_S4_RESULT_RSP_SEND;
            end

            // S4 Result RSP
            MB_S4_RESULT_RSP_SEND: begin
                if (ltsm_rdy)       next_state = MB_S4_RESULT_RSP_WAIT;
            end
            MB_S4_RESULT_RSP_WAIT: begin
                if (s4_rsp_rcvd)    next_state = MB_S5_DECISION;
            end

            // S5 Decision
            MB_S5_DECISION: begin
                if (majority_success)
                    next_state = MB_S6_FINALIZE_REQ_SEND;
                else if (!majority_success && !retry_done)
                    next_state = MB_S2_ERROR_RESET_REQ_SEND;
                else // !majority_success && retry_done
                    next_state = MB_S7_REVERSAL_ERROR;
            end

            // S6 Finalize REQ
            MB_S6_FINALIZE_REQ_SEND: begin
                if (ltsm_rdy)       next_state = MB_S6_FINALIZE_REQ_WAIT;
            end
            MB_S6_FINALIZE_REQ_WAIT: begin
                if (s6_req_rcvd)    next_state = MB_S6_FINALIZE_RSP_SEND;
            end

            // S6 Finalize RSP
            MB_S6_FINALIZE_RSP_SEND: begin
                if (ltsm_rdy)       next_state = MB_S6_FINALIZE_RSP_WAIT;
            end
            MB_S6_FINALIZE_RSP_WAIT: begin
                if (s6_rsp_rcvd)    next_state = MB_S8_REVERSAL_DONE;
            end

            MB_S7_REVERSAL_ERROR: begin
                // Stays here until mb_reversal_enable deasserts
            end

            MB_S8_REVERSAL_DONE: begin
                // Stays here until mb_reversal_enable deasserts
            end

            default: next_state = MB_S0_IDLE;
        endcase
    end
end

////////////////////////////////////////////////////////
// TX SB LOGIC
////////////////////////////////////////////////////////
always_comb begin
    mb_reversal_tx_valid      = 1'b0;
    mb_reversal_tx_msg_id     = msg_no_e'(NOTHING);
    mb_reversal_tx_MsgInfo    = MB_default_MSG_Info;
    mb_reversal_tx_data_Field = MB_default_data_Field;

    case (current_state)
        MB_S1_READY_REQ_SEND: begin
            mb_reversal_tx_valid  = 1'b1;
            mb_reversal_tx_msg_id = MBINIT_REVERSALMB_init_req;
        end

        MB_S1_READY_RSP_SEND: begin
            mb_reversal_tx_valid  = 1'b1;
            mb_reversal_tx_msg_id = MBINIT_REVERSALMB_init_resp;
        end

        MB_S2_ERROR_RESET_REQ_SEND: begin
            mb_reversal_tx_valid  = 1'b1;
            mb_reversal_tx_msg_id = MBINIT_REVERSALMB_clear_error_req;
        end

        MB_S2_ERROR_RESET_RSP_SEND: begin
            mb_reversal_tx_valid  = 1'b1;
            mb_reversal_tx_msg_id = MBINIT_REVERSALMB_clear_error_resp;
        end

        MB_S4_RESULT_REQ_SEND: begin
            mb_reversal_tx_valid  = 1'b1;
            mb_reversal_tx_msg_id = MBINIT_REVERSALMB_result_req;
        end

        MB_S4_RESULT_RSP_SEND: begin
            mb_reversal_tx_valid      = 1'b1;
            mb_reversal_tx_msg_id     = MBINIT_REVERSALMB_result_resp;
            mb_reversal_tx_data_Field = MB_local_result_exchange_data_Field;
        end

        MB_S6_FINALIZE_REQ_SEND: begin
            mb_reversal_tx_valid  = 1'b1;
            mb_reversal_tx_msg_id = MBINIT_REVERSALMB_done_req;
        end

        MB_S6_FINALIZE_RSP_SEND: begin
            mb_reversal_tx_valid  = 1'b1;
            mb_reversal_tx_msg_id = MBINIT_REVERSALMB_done_resp;
        end

        default: begin
            // Do nothing
        end
    endcase
end

////////////////////////////////////////////////////////
// PATTERN
////////////////////////////////////////////////////////
assign mb_tx_data_pattern_en   = (current_state == MB_S3_PATTERN_TRANSMISSION);

////////////////////////////////////////////////////////
// RX CLOCK EN
////////////////////////////////////////////////////////
always_comb begin

    mb_rx_data_compare_en = 0;
    case(current_state)

        MB_S1_READY_RSP_SEND,
        MB_S1_READY_RSP_WAIT,
        MB_S3_PATTERN_TRANSMISSION,
        MB_S4_RESULT_REQ_SEND,
        MB_S4_RESULT_REQ_WAIT: begin
            mb_rx_data_compare_en = 1;
        end
        default: begin
            mb_rx_data_compare_en = 0;
        end
    endcase
end


assign mb_tx_data_pattern_sel = 1'b1;  // 1'b1; per_lan_id_pattern
assign mb_rx_compare_setup    = 1'b1;  // per lane comparison

////////////////////////////////////////////////////////
// DONE
////////////////////////////////////////////////////////
always_comb begin
    mb_reversal_done = (current_state == MB_S8_REVERSAL_DONE);
end

////////////////////////////////////////////////////////
// ERROR
////////////////////////////////////////////////////////
always_comb begin
    mb_reversal_error = (current_state == MB_S7_REVERSAL_ERROR);
end

endmodule