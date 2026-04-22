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

    output logic timeout_error,
    ////////////////////////////////////////////////////

    // PATTERN
    output logic [2:0] mb_tx_pattern_setup,
    output logic [1:0] mb_tx_data_pattern_sel,
    output logic [1:0] mb_rx_compare_setup,

    output logic mb_tx_pattern_en,
    output logic mb_rx_compare_en,

    input logic [15:0] mb_rx_perlane_err,
    input logic mb_rx_compare_done,
    ////////////////////////////////////////////////////

    // PHY CONTROL
    output logic mb_tx_valid_status,
    output logic mb_tx_track_status,
    output logic mb_tx_clk_status,
    output logic mb_tx_data_status,

    output logic mb_rx_valid_status,
    output logic mb_rx_track_status,
    output logic mb_rx_clk_status,
    output logic mb_rx_data_status
);

////////////////////////////////////////////////////////
// STATES
////////////////////////////////////////////////////////
typedef enum logic [3:0] { 
    MB_S0_IDLE,

    MB_S1_READINESS_HANDSHAKE_REQ,
    MB_S1_READINESS_HANDSHAKE_RSP,

    MB_S2_ERROR_RESET_REQ,
    MB_S2_ERROR_RESET_RSP,

    MB_S3_PATTERN_TRANSMISSION,

    MB_S4_RESULT_EXCHANGE_REQ,
    MB_S4_RESULT_EXCHANGE_RSP,

    MB_S5_DECISION,

    MB_S6_FINALIZE_HANDSHAKE_REQ,
    MB_S6_FINALIZE_HANDSHAKE_RSP
} state_e;

state_e current_state, next_state;

////////////////////////////////////////////////////////
// Reset flags when there is a retry
////////////////////////////////////////////////////////
/*logic s2_entry;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        s2_entry <= 0;
    else
        s2_entry <= (current_state != MB_S2_ERROR_RESET_REQ) && (next_state == MB_S2_ERROR_RESET_REQ);
end
*/

logic s2_entry;
assign s2_entry = (next_state == MB_S2_ERROR_RESET_REQ) && (current_state != MB_S2_ERROR_RESET_REQ);

////////////////////////////////////////////////////////
// DEFAULTS
////////////////////////////////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0;

////////////////////////////////////////////////////////
// RESULT
////////////////////////////////////////////////////////
logic [15:0] mb_rx_perlane_result;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_rx_perlane_result <= 16'h0;
    else if(s2_entry)
        mb_rx_perlane_result <= 16'h0;
    else
        mb_rx_perlane_result <= mb_rx_perlane_err;
end

logic [63:0] MB_local_result_exchange_data_Field;
assign MB_local_result_exchange_data_Field = {48'h0, mb_rx_perlane_result};
////////////////////////////////////////////////////////
// MAJORITY LOGIC
////////////////////////////////////////////////////////
parameter int NUM_LANES = 16;

logic [NUM_LANES-1:0] partner_result;
logic [$clog2(NUM_LANES+1)-1:0] success_count;
logic majority_success;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        partner_result <= 0;

    else if(s2_entry)
        partner_result <= 0;

    else if(current_state == MB_S4_RESULT_EXCHANGE_RSP &&
            mb_reversal_rx_valid &&
            mb_reversal_rx_msg_id == MBINIT_REVERSALMB_result_resp)
        partner_result <= mb_reversal_rx_data_Field[15:0];
end

always_comb begin
    success_count = 0;
    for (int i = 0; i < NUM_LANES; i++) begin
        success_count += partner_result[i];
    end
end

assign majority_success = (success_count > (NUM_LANES/2));
////////////////////////////////////////////////////////
// TIMEOUT
////////////////////////////////////////////////////////
logic timer_enable;
logic timeout_expired;

assign timer_enable = mb_reversal_enable && !mb_reversal_done && !mb_reversal_error;

timeout_counter #(
    .CLK_FRQ_HZ(CLK_FRQ_HZ),
    .TIME_OUT(8)
) u_timeout (
    .clk(clk),
    .timeout_rst_n(rst_n),
    .enable_timeout(timer_enable),
    .timeout_expired(timeout_expired)
);

assign timeout_error = timeout_expired && !mb_reversal_done;

////////////////////////////////////////////////////////
// RX FLAGS
////////////////////////////////////////////////////////

// To Reset the flages when there is a retry.
logic retry_done;
/*logic retry_pulse;

assign retry_pulse =
    (current_state == MB_S5_DECISION) &&
    (!majority_success);
*/
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        retry_done <= 0;

    else if(current_state == MB_S5_DECISION && !majority_success && !retry_done)
        retry_done <= 1;

    else if(s2_entry)
        retry_done <= retry_done;

    else if(current_state == MB_S0_IDLE)
        retry_done <= 0;
end
////////////////////////////////////////////////////


logic retry_start;

assign retry_start =
    (current_state == MB_S5_DECISION) &&
    (!majority_success) &&
    (!retry_done);
    
//HANDSHAKE FLAGS
logic s1_req_sent, s1_req_rcvd;
logic s1_rsp_sent, s1_rsp_rcvd;

logic s2_req_sent, s2_req_rcvd;
logic s2_rsp_sent, s2_rsp_rcvd;

logic s4_req_sent, s4_req_rcvd;
logic s4_rsp_sent, s4_rsp_rcvd;

logic s6_req_sent, s6_req_rcvd;
logic s6_rsp_sent, s6_rsp_rcvd;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || retry_start) begin
        s1_req_rcvd <= 0; s1_rsp_rcvd <= 0;
        s2_req_rcvd <= 0; s2_rsp_rcvd <= 0;
        s4_req_rcvd <= 0; s4_rsp_rcvd <= 0;
        s6_req_rcvd <= 0; s6_rsp_rcvd <= 0;
    end
    else if(mb_reversal_rx_valid) begin

        case(mb_reversal_rx_msg_id)

        MBINIT_REVERSALMB_init_req:       s1_req_rcvd <= 1;
        MBINIT_REVERSALMB_init_resp:      s1_rsp_rcvd <= 1;

        MBINIT_REVERSALMB_clear_error_req:  s2_req_rcvd <= 1;
        MBINIT_REVERSALMB_clear_error_resp: s2_rsp_rcvd <= 1;

        MBINIT_REVERSALMB_result_req:     s4_req_rcvd <= 1;
        MBINIT_REVERSALMB_result_resp:    s4_rsp_rcvd <= 1;

        MBINIT_REVERSALMB_done_req:       s6_req_rcvd <= 1;
        MBINIT_REVERSALMB_done_resp:      s6_rsp_rcvd <= 1;

        endcase
    end
end

////////////////////////////////////////////////////////
// STATE REG
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

    if(mb_reversal_error || timeout_error)
        next_state = MB_S0_IDLE;
    else
        case(current_state)

    MB_S0_IDLE:
        if(mb_reversal_enable && !mb_reversal_done && !mb_reversal_error)
            next_state = MB_S1_READINESS_HANDSHAKE_REQ;

    MB_S1_READINESS_HANDSHAKE_REQ:
        if(s1_req_sent && s1_req_rcvd)
            next_state = MB_S1_READINESS_HANDSHAKE_RSP;

    MB_S1_READINESS_HANDSHAKE_RSP:
        if(s1_rsp_sent && s1_rsp_rcvd)
            next_state = MB_S2_ERROR_RESET_REQ;

    MB_S2_ERROR_RESET_REQ:
        if(s2_req_sent && s2_req_rcvd)
            next_state = MB_S2_ERROR_RESET_RSP;
        else
            next_state = MB_S2_ERROR_RESET_REQ;

    MB_S2_ERROR_RESET_RSP:
        if(s2_rsp_sent && s2_rsp_rcvd)
            next_state = MB_S3_PATTERN_TRANSMISSION;

    MB_S3_PATTERN_TRANSMISSION:
        if(mb_rx_compare_done)
            next_state = MB_S4_RESULT_EXCHANGE_REQ;

    MB_S4_RESULT_EXCHANGE_REQ:
        if(s4_req_sent && s4_req_rcvd)
            next_state = MB_S4_RESULT_EXCHANGE_RSP;

    MB_S4_RESULT_EXCHANGE_RSP:
        if(s4_rsp_sent && s4_rsp_rcvd)
            next_state = MB_S5_DECISION;

    MB_S5_DECISION:
        if(majority_success)
            next_state = MB_S6_FINALIZE_HANDSHAKE_REQ;
        else if(!majority_success && !retry_done)
            next_state = MB_S2_ERROR_RESET_REQ;
        else if(!majority_success && retry_done)
            next_state = MB_S0_IDLE;

    MB_S6_FINALIZE_HANDSHAKE_REQ:
        if(s6_req_sent && s6_req_rcvd)
            next_state = MB_S6_FINALIZE_HANDSHAKE_RSP;

    MB_S6_FINALIZE_HANDSHAKE_RSP:
        if(s6_rsp_sent && s6_rsp_rcvd)
            next_state = MB_S0_IDLE;

    default: next_state = MB_S0_IDLE;
    endcase
end

////////////////////////////////////////////////////////
// RESET TX FLAGS ON S2 ENTRY (FIX BUG)
////////////////////////////////////////////////////////


always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n || retry_start) begin
        s1_req_sent <= 0; s1_rsp_sent <= 0;
        s2_req_sent <= 0; s2_rsp_sent <= 0;
        s4_req_sent <= 0; s4_rsp_sent <= 0;
        s6_req_sent <= 0; s6_rsp_sent <= 0;
    end
end

////////////////////////////////////////////////////////
// TX LOGIC
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mb_reversal_tx_valid <= 0;
    end
    else begin
        mb_reversal_tx_valid <= 0;

        case(current_state)

        //////////////////////////////////////////////////
        // S1
        //////////////////////////////////////////////////
        MB_S1_READINESS_HANDSHAKE_REQ:
            if(!s1_req_sent) begin
                mb_reversal_tx_valid <= 1;
                mb_reversal_tx_msg_id <= MBINIT_REVERSALMB_init_req;
                mb_reversal_tx_MsgInfo <= MB_default_MSG_Info;
                mb_reversal_tx_data_Field <= MB_default_data_Field;
                s1_req_sent <= 1;
            end

        MB_S1_READINESS_HANDSHAKE_RSP:
            if(!s1_rsp_sent && s1_req_rcvd)begin
                mb_reversal_tx_valid <= 1;
                mb_reversal_tx_msg_id <= MBINIT_REVERSALMB_init_resp;
                mb_reversal_tx_MsgInfo <= MB_default_MSG_Info;
                mb_reversal_tx_data_Field <= MB_default_data_Field;
                s1_rsp_sent <= 1;
            end

        //////////////////////////////////////////////////
        // S2 (FIXED)
        //////////////////////////////////////////////////
        MB_S2_ERROR_RESET_REQ:
            if(!s2_req_sent) begin
                mb_reversal_tx_valid <= 1;
                mb_reversal_tx_msg_id <= MBINIT_REVERSALMB_clear_error_req;
                mb_reversal_tx_MsgInfo <= MB_default_MSG_Info;
                mb_reversal_tx_data_Field <= MB_default_data_Field;
                s2_req_sent <= 1;
            end

        MB_S2_ERROR_RESET_RSP:
            if(!s2_rsp_sent && s2_req_rcvd)begin
                mb_reversal_tx_valid <= 1;
                mb_reversal_tx_msg_id <= MBINIT_REVERSALMB_clear_error_resp;
                mb_reversal_tx_MsgInfo <= MB_default_MSG_Info;
                mb_reversal_tx_data_Field <= MB_default_data_Field;
                s2_rsp_sent <= 1;
            end

        //////////////////////////////////////////////////
        // S4
        //////////////////////////////////////////////////
        MB_S4_RESULT_EXCHANGE_REQ:
            if(!s4_req_sent) begin
                mb_reversal_tx_valid <= 1;
                mb_reversal_tx_msg_id <= MBINIT_REVERSALMB_result_req;
                mb_reversal_tx_MsgInfo <= MB_default_MSG_Info;
                mb_reversal_tx_data_Field <= MB_default_data_Field;
                s4_req_sent <= 1;
            end

        MB_S4_RESULT_EXCHANGE_RSP:
            if(!s4_rsp_sent && s4_req_rcvd)begin
                mb_reversal_tx_valid <= 1;
                mb_reversal_tx_msg_id <= MBINIT_REVERSALMB_result_resp;
                mb_reversal_tx_MsgInfo <= MB_default_MSG_Info;
                mb_reversal_tx_data_Field <= MB_local_result_exchange_data_Field;
                s4_rsp_sent <= 1;
            end

        //////////////////////////////////////////////////
        // S6
        //////////////////////////////////////////////////
        MB_S6_FINALIZE_HANDSHAKE_REQ:
            if(!s6_req_sent) begin
                mb_reversal_tx_valid <= 1;
                mb_reversal_tx_msg_id <= MBINIT_REVERSALMB_done_req;
                mb_reversal_tx_MsgInfo <= MB_default_MSG_Info;
                mb_reversal_tx_data_Field <= MB_default_data_Field;
                s6_req_sent <= 1;
            end

        MB_S6_FINALIZE_HANDSHAKE_RSP:
            if(!s6_rsp_sent && s6_req_rcvd)begin
                mb_reversal_tx_valid <= 1;
                mb_reversal_tx_msg_id <= MBINIT_REVERSALMB_done_resp;
                mb_reversal_tx_MsgInfo <= MB_default_MSG_Info;
                mb_reversal_tx_data_Field <= MB_default_data_Field;
                s6_rsp_sent <= 1;
            end

        endcase
    end
end

////////////////////////////////////////////////////////
// PATTERN
////////////////////////////////////////////////////////
assign mb_tx_pattern_en   = (current_state == MB_S3_PATTERN_TRANSMISSION);
assign mb_rx_compare_en   = (current_state == MB_S3_PATTERN_TRANSMISSION);

assign mb_tx_pattern_setup    = 3'b001;
assign mb_tx_data_pattern_sel = 2'b01;
assign mb_rx_compare_setup    = 2'b00;

////////////////////////////////////////////////////////
// PHY CONTROL
////////////////////////////////////////////////////////
always_comb begin
    mb_tx_valid_status = 0;
    mb_tx_track_status = 0;
    mb_tx_clk_status   = 0;
    mb_tx_data_status  = 0;

    mb_rx_valid_status = 0;
    mb_rx_track_status = 0;
    mb_rx_clk_status   = 0;
    mb_rx_data_status  = 0;

    if(current_state == MB_S3_PATTERN_TRANSMISSION) begin
        mb_rx_valid_status = 1;
        mb_rx_track_status = 1;
        mb_rx_clk_status   = 1;
        mb_rx_data_status  = 1;
    end
end

////////////////////////////////////////////////////////
// DONE
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_reversal_done <= 0;
    else if(current_state == MB_S6_FINALIZE_HANDSHAKE_RSP &&
            s6_rsp_sent && s6_rsp_rcvd)
        mb_reversal_done <= 1;
end

////////////////////////////////////////////////////////
// ERROR
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_reversal_error <= 0;

    else if(!mb_reversal_enable)
        mb_reversal_error <= 0;

    else if(timeout_error)
        mb_reversal_error <= 1;

    else if(current_state == MB_S5_DECISION && !majority_success && retry_done)
        mb_reversal_error <= 1;

    else if(mb_reversal_rx_valid) begin
        case(current_state)

        MB_S1_READINESS_HANDSHAKE_REQ,
        MB_S1_READINESS_HANDSHAKE_RSP:
            if(!(mb_reversal_rx_msg_id inside {
                MBINIT_REVERSALMB_init_req,
                MBINIT_REVERSALMB_init_resp
            }))
                mb_reversal_error <= 1;
        
        MB_S2_ERROR_RESET_REQ,
        MB_S2_ERROR_RESET_RSP:
            if(!(mb_reversal_rx_msg_id inside {
                MBINIT_REVERSALMB_clear_error_req,
                MBINIT_REVERSALMB_clear_error_resp
            }))
                mb_reversal_error <= 1;

        MB_S4_RESULT_EXCHANGE_REQ,
        MB_S4_RESULT_EXCHANGE_RSP:
            if(!(mb_reversal_rx_msg_id inside {
                MBINIT_REVERSALMB_result_req,
                MBINIT_REVERSALMB_result_resp
            }))
                mb_reversal_error <= 1;

        MB_S6_FINALIZE_HANDSHAKE_REQ,
        MB_S6_FINALIZE_HANDSHAKE_RSP:
            if(!(mb_reversal_rx_msg_id inside {
                MBINIT_REVERSALMB_done_req,
                MBINIT_REVERSALMB_done_resp
            }))
                mb_reversal_error <= 1;

        endcase
    end

end

endmodule