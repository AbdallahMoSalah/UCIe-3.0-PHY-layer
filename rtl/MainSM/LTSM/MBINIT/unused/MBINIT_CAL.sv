import UCIe_pkg::*;
module MBINIT_CAL 
#(parameter int CLK_FRQ_HZ = 800000000)
(
    input  logic clk, rst_n,

    // from LTSM
    input  logic mb_cal_enable,

    // to LTSM
    output logic mb_cal_done,
    output logic mb_cal_error,

    // RX from partner
    input  logic mb_cal_rx_valid,
    input  msg_no_e mb_cal_rx_msg_id,
    input  logic [15:0] mb_cal_rx_MsgInfo,
    input  logic [63:0] mb_cal_rx_data_Field,

    // TX to partner
    output logic mb_cal_tx_valid,
    output msg_no_e mb_cal_tx_msg_id,
    output logic [15:0] mb_cal_tx_MsgInfo,
    output logic [63:0] mb_cal_tx_data_Field,

    output logic timeout_error

);
////////////////////////////////////////////////////////
////////////////////// STATES //////////////////////////
////////////////////////////////////////////////////////
typedef enum logic [1:0] { 
    MB_S0_IDLE,

    MB_S1_HANDSHAKE_REQ,
    MB_S1_HANDSHAKE_RSP

 } mb_cal_state_e;
mb_cal_state_e current_state , next_state ;

////////////////////////////////////////////////////////
///////////////////// calETERS ///////////////////////
//Handshakes message IDs.///////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0000000000000000;

////////////////////////////////////////////////////////
/////////////////// TIMEOUT TIMER //////////////////////
////////////////////////////////////////////////////////
logic mb_cal_timer_enable;  // to reset and enable the timeout timer.
assign mb_cal_timer_enable = mb_cal_enable && !mb_cal_done && !mb_cal_error;
logic mb_cal_timeout_expired ;
timeout_counter #(
    .CLK_FRQ_HZ(CLK_FRQ_HZ),
    .TIME_OUT(8)
) mb_cal_timeout_timer (
    .clk(clk),
    .timeout_rst_n(rst_n),
    .enable_timeout(mb_cal_timer_enable),
    .timeout_expired(mb_cal_timeout_expired)
);
assign timeout_error = mb_cal_timeout_expired && !mb_cal_done;

////////////////////////////////////////////////////////
//////////////// Entry Detection logic /////////////////
////////////////////////////////////////////////////////
logic s1_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        s1_entry <= 0;
    else
        s1_entry <= (current_state != MB_S1_HANDSHAKE_REQ) && (next_state == MB_S1_HANDSHAKE_REQ);
end

////////////////////////////////////////////////////////
////////////////// HANDSHAKE FLAGS /////////////////////
////////////////////////////////////////////////////////
logic cal_req_rcvd;
logic cal_rsp_rcvd;
//-----------------------------------------------------
// CAL REQ received
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
if(!rst_n)
    cal_req_rcvd <= 0;
else if(current_state == MB_S1_HANDSHAKE_REQ && mb_cal_rx_valid && mb_cal_rx_msg_id == MBINIT_CAL_Done_req)
    cal_req_rcvd <= 1;
else if(current_state != MB_S1_HANDSHAKE_REQ)
    cal_req_rcvd <= 0;
end
//-----------------------------------------------------
// CAL RSP received
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
if(!rst_n)
    cal_rsp_rcvd <= 0;
else if(current_state == MB_S1_HANDSHAKE_RSP && mb_cal_rx_valid && mb_cal_rx_msg_id == MBINIT_CAL_Done_resp)
    cal_rsp_rcvd <= 1;
else if(current_state != MB_S1_HANDSHAKE_RSP)
    cal_rsp_rcvd <= 0;
end

////////////////////////////////////////////////////////
////////////////// STATE REGISTER //////////////////////
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= MB_S0_IDLE;
    else
        current_state <= next_state;
end

////////////////////////////////////////////////////////
////////////////// NEXT STATE LOGIC ////////////////////
////////////////////////////////////////////////////////
always_comb begin 
    next_state = current_state;
    if(timeout_error)
    next_state = MB_S0_IDLE;

    case(current_state)
    MB_S0_IDLE: begin
        if(mb_cal_enable && !mb_cal_done )
        next_state = MB_S1_HANDSHAKE_REQ;
    end
        ///////////////////////////////////////////////
    MB_S1_HANDSHAKE_REQ: begin
        if(mb_cal_error || !mb_cal_enable)
        next_state = MB_S0_IDLE;
        else if(cal_req_rcvd && !cal_rsp_rcvd)
        next_state = MB_S1_HANDSHAKE_RSP;
    end
        ///////////////////////////////////////////////
    MB_S1_HANDSHAKE_RSP: begin
        if(mb_cal_error || !mb_cal_enable)
        next_state = MB_S0_IDLE;
        else if(cal_rsp_rcvd)
        next_state = MB_S0_IDLE;
        end

    endcase        
end

////////////////////////////////////////////////////////
/////////////// OUTPUT LOGIC ///////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    // Default outputs.
    mb_cal_tx_valid       = 1'b0;
    mb_cal_tx_msg_id      = msg_no_e'(8'h00);
    mb_cal_tx_MsgInfo     = MB_default_MSG_Info;
    mb_cal_tx_data_Field  = MB_default_data_Field;
    if(mb_cal_enable) begin
    case(current_state)

        MB_S1_HANDSHAKE_REQ: begin
            if(s1_entry) begin
            mb_cal_tx_valid       = 1'b1;
            mb_cal_tx_msg_id      = MBINIT_CAL_Done_req;
            mb_cal_tx_MsgInfo     = MB_default_MSG_Info;
            mb_cal_tx_data_Field  = MB_default_data_Field;    
        end
            end
        MB_S1_HANDSHAKE_RSP: begin
            mb_cal_tx_valid       = 1'b1;
            mb_cal_tx_msg_id      = MBINIT_CAL_Done_resp;
            mb_cal_tx_MsgInfo     = MB_default_MSG_Info;
            mb_cal_tx_data_Field  = MB_default_data_Field;    
        end
    endcase
    end
end

////////////////////////////////////////////////////////
/////////////// DONE LOGIC //////////////////////////////
////////////////////////////////////////////////////////
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n)
        mb_cal_done <= 0;
    else if(current_state == MB_S1_HANDSHAKE_RSP && cal_rsp_rcvd )        
        mb_cal_done <= 1;
    //else if(current_state == MB_S0_IDLE)
    //mb_cal_done <= 0;
end

////////////////////////////////////////////////////////
/////////////// ERROR LOGIC ////////////////////////////
////////////////////////////////////////////////////////
always_ff @( posedge clk , negedge rst_n ) begin
    if(!rst_n)
    mb_cal_error <= 0;

    else if(timeout_error)
    mb_cal_error <= 1;
    //S1 error: only flag wrong msg after handshake has started (guard prevents stale PARAM msgs triggering error).
    else if(mb_cal_rx_valid && current_state == MB_S1_HANDSHAKE_REQ && cal_req_rcvd && mb_cal_rx_msg_id != MBINIT_CAL_Done_req)
    mb_cal_error <= 1;
    else if(mb_cal_rx_valid && current_state == MB_S1_HANDSHAKE_RSP && mb_cal_rx_msg_id != MBINIT_CAL_Done_resp)
    mb_cal_error <= 1;
end


endmodule