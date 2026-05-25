import UCIe_pkg::*;

module MBINIT_CAL_NEW 
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

    // FIFO ready
    input  logic ltsm_rdy,

    // Timer signals
    output logic timeout_cal_enable,
    input  logic timeout_cal_expired

);

////////////////////////////////////////////////////////
////////////////////// STATES //////////////////////////
////////////////////////////////////////////////////////
typedef enum logic [2:0] { 
    MB_S0_IDLE,

    MB_S1_CAL_REQ_SEND,     // drive CAL_Done_req until ltsm_rdy=1
    MB_S1_CAL_REQ_WAIT,     // wait for partner's CAL_Done_req

    MB_S1_CAL_RSP_SEND,     // drive CAL_Done_resp until ltsm_rdy=1
    MB_S1_CAL_RSP_WAIT,     // wait for partner's CAL_Done_resp

    MB_S2_DONE,
    MB_S3_ERROR

 } mb_cal_state_e;
mb_cal_state_e current_state , next_state ;

////////////////////////////////////////////////////////
///////////////////// PARAMETERS ///////////////////////
////////////////////////////////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0000000000000000;

////////////////////////////////////////////////////////
/////////////////// TIMEOUT TIMER //////////////////////
////////////////////////////////////////////////////////
logic timeout_error;
assign timeout_error = timeout_cal_expired && !mb_cal_done;
assign timeout_cal_enable = mb_cal_enable && !mb_cal_done && !mb_cal_error;

////////////////////////////////////////////////////////
//////////////// HANDSHAKE FLAGS /////////////////////
////////////////////////////////////////////////////////
logic cal_req_rcvd;
logic cal_rsp_rcvd;

//-----------------------------------------------------
// CAL REQ received (clears outside MB_S1_CAL_REQ_WAIT)
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        cal_req_rcvd <= 0;
    else if(mb_cal_rx_valid && mb_cal_rx_msg_id == MBINIT_CAL_Done_req)
        cal_req_rcvd <= 1;
    else if(current_state != MB_S1_CAL_REQ_WAIT)
        cal_req_rcvd <= 0;
end

//-----------------------------------------------------
// CAL RSP received (clears outside MB_S1_CAL_RSP_WAIT)
//-----------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        cal_rsp_rcvd <= 0;
    else if(mb_cal_rx_valid && mb_cal_rx_msg_id == MBINIT_CAL_Done_resp)
        cal_rsp_rcvd <= 1;
    else if(current_state != MB_S1_CAL_RSP_WAIT)
        cal_rsp_rcvd <= 0;
end

////////////////////////////////////////////////////////
//////////////// STATE REGISTER //////////////////////
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

    if(!mb_cal_enable) begin
        next_state = MB_S0_IDLE;
    end else if(timeout_error) begin
        next_state = MB_S3_ERROR;
    end else begin
        
        case(current_state)
            MB_S0_IDLE: begin
                if(mb_cal_enable)
                    next_state = MB_S1_CAL_REQ_SEND;
            end

            // -- S1 CAL Request --
            MB_S1_CAL_REQ_SEND: begin
                if(ltsm_rdy)           next_state = MB_S1_CAL_REQ_WAIT;
            end

            MB_S1_CAL_REQ_WAIT: begin
                if(cal_req_rcvd)       next_state = MB_S1_CAL_RSP_SEND;
            end

            // -- S1 CAL Response --
            MB_S1_CAL_RSP_SEND: begin
                if(ltsm_rdy)           next_state = MB_S1_CAL_RSP_WAIT;
            end

            MB_S1_CAL_RSP_WAIT: begin
                if(cal_rsp_rcvd)       next_state = MB_S2_DONE;
            end

            MB_S2_DONE: begin
                // Stays here until mb_cal_enable deasserts
            end

            MB_S3_ERROR: begin
                // Stays here until mb_cal_enable deasserts
            end

            default: next_state = MB_S0_IDLE;
        endcase        
    end
end

////////////////////////////////////////////////////////
/////////////// OUTPUT LOGIC ///////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    // Default outputs.
    mb_cal_tx_valid       = 1'b0;
    mb_cal_tx_msg_id      = msg_no_e'(NOTHING);
    mb_cal_tx_MsgInfo     = MB_default_MSG_Info;
    mb_cal_tx_data_Field  = MB_default_data_Field;

    case(current_state)
        MB_S1_CAL_REQ_SEND: begin
            mb_cal_tx_valid       = 1'b1;
            mb_cal_tx_msg_id      = MBINIT_CAL_Done_req;
            mb_cal_tx_MsgInfo     = MB_default_MSG_Info;
            mb_cal_tx_data_Field  = MB_default_data_Field;    
        end

        MB_S1_CAL_RSP_SEND: begin
            mb_cal_tx_valid       = 1'b1;
            mb_cal_tx_msg_id      = MBINIT_CAL_Done_resp;
            mb_cal_tx_MsgInfo     = MB_default_MSG_Info;
            mb_cal_tx_data_Field  = MB_default_data_Field;    
        end

        default: ; // Use defaults
    endcase
end

////////////////////////////////////////////////////////
/////////////// DONE LOGIC //////////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    mb_cal_done = (current_state == MB_S2_DONE);
end

////////////////////////////////////////////////////////
/////////////// ERROR LOGIC ////////////////////////////
////////////////////////////////////////////////////////
always_comb begin
    mb_cal_error = (current_state == MB_S3_ERROR);
end

endmodule
