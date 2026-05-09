import UCIe_pkg::*;

module MBINIT_REPAIRCLK_NEW
#( parameter int CLK_FRQ_HZ = 800000000)
(
    input  logic clk, rst_n,

    input  logic mb_repairclk_enable,

    output logic mb_repairclk_done,
    output logic mb_repairclk_error,

    input  logic mb_repairclk_rx_valid,
    input  msg_no_e mb_repairclk_rx_msg_id,
    input  logic [15:0] mb_repairclk_rx_MsgInfo,
    input  logic [63:0] mb_repairclk_rx_data_Field,

    output logic mb_repairclk_tx_valid,
    output msg_no_e mb_repairclk_tx_msg_id,
    output logic [15:0] mb_repairclk_tx_MsgInfo,
    output logic [63:0] mb_repairclk_tx_data_Field,

    // output logic [2:0] mb_tx_pattern_setup ,
    // output logic [1:0] mb_tx_clk_pattern_sel,
    // output logic [1:0] mb_rx_compare_setup,

    output logic mb_tx_pattern_clk_en,
    output logic mb_rx_compare_clk_en,

    input logic rtrk_pass,
    input logic rckn_pass,
    input logic rckp_pass,

    input logic mb_tx_clk_pattern_transmission_completed,

    // FIFO ready
    input  logic ltsm_rdy,

    //Timer signals
    input logic timeout_repairclk_expired,
    output logic timeout_repairclk_enable
);

////////////////////////////////////////////////////////
// STATES
////////////////////////////////////////////////////////
typedef enum logic [4:0] {
    MB_S0_IDLE,
    // S1 Readiness (split)
    MB_S1_READY_REQ_SEND,   // drive init_req until ltsm_rdy=1
    MB_S1_READY_REQ_WAIT,   // wait for partner init_req
    MB_S1_READY_RSP_SEND,   // drive init_resp until ltsm_rdy=1
    MB_S1_READY_RSP_WAIT,   // wait for partner init_resp
    // S2 Pattern
    MB_S2_PATTERN_TRANSMISSION,
    // S3 Result Exchange (split)
    MB_S3_RESULT_REQ_SEND,  // drive result_req until ltsm_rdy=1
    MB_S3_RESULT_REQ_WAIT,  // wait for partner result_req
    MB_S3_RESULT_RSP_SEND,  // drive result_resp until ltsm_rdy=1
    MB_S3_RESULT_RSP_WAIT,  // wait for partner result_resp
    // S4 Error Check
    MB_S4_ERROR_CHECK,
    // S5 Finalize (split)
    MB_S5_FINALIZE_REQ_SEND,
    MB_S5_FINALIZE_REQ_WAIT,
    MB_S5_FINALIZE_RSP_SEND,
    MB_S5_FINALIZE_RSP_WAIT,

    MB_S6_REPAIRCLK_ERROR,
    MB_S7_REPAIRCLK_DONE

} mb_repairclk_state_e;

mb_repairclk_state_e current_state, next_state;

////////////////////////////////////////////////////////
// DEFAULTS
////////////////////////////////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0;

// assign mb_tx_pattern_setup   = 3'b100;
// assign mb_tx_clk_pattern_sel = 2'b10;
// assign mb_rx_compare_setup   = 2'b11;

logic [2:0] repairclk_result_local;
assign repairclk_result_local = {rtrk_pass, rckn_pass, rckp_pass};
logic [15:0] MB_repairclk_result_MSG_Info;
assign MB_repairclk_result_MSG_Info = {13'b0, repairclk_result_local};


logic [2:0] partner_compare_result; // latched in s3_rsp_rcvd ff below

logic error_detect;
assign error_detect = !(&partner_compare_result);


////////////////////////////////////////////////////////
// TIMEOUT
////////////////////////////////////////////////////////
logic timeout_error;
assign timeout_error = timeout_repairclk_expired && !mb_repairclk_done;
assign timeout_repairclk_enable = mb_repairclk_enable && !mb_repairclk_done && !mb_repairclk_error;

////////////////////////////////////////////////////////
// HANDSHAKE FLAGS
////////////////////////////////////////////////////////
logic s1_req_sent, s1_req_rcvd;
logic s1_rsp_sent, s1_rsp_rcvd;
logic s3_req_sent, s3_req_rcvd;
logic s3_rsp_sent, s3_rsp_rcvd;
logic s4_req_sent, s4_req_rcvd;
logic s4_rsp_sent, s4_rsp_rcvd;

// Entry flip-flops removed - _SEND states handle first-cycle TX.
////////////////////////////////////////////////////////
// RX FLAGS (SBINITNEW style: set any cycle msg arrives, clear outside _WAIT)
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) s1_req_rcvd <= 0;
    else if(mb_repairclk_rx_valid && mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_init_req) s1_req_rcvd <= 1;
    else if(current_state != MB_S1_READY_REQ_WAIT) s1_req_rcvd <= 0;
end
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) s1_rsp_rcvd <= 0;
    else if(mb_repairclk_rx_valid && mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_init_resp) s1_rsp_rcvd <= 1;
    else if(current_state != MB_S1_READY_RSP_WAIT) s1_rsp_rcvd <= 0;
end
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) s3_req_rcvd <= 0;
    else if(mb_repairclk_rx_valid && mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_result_req) s3_req_rcvd <= 1;
    else if(current_state != MB_S3_RESULT_REQ_WAIT) s3_req_rcvd <= 0;
end
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) s3_rsp_rcvd <= 0;
    else if(mb_repairclk_rx_valid && mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_result_resp) begin
        s3_rsp_rcvd <= 1;
        partner_compare_result <= mb_repairclk_rx_data_Field[2:0];
    end
    else if(current_state != MB_S3_RESULT_RSP_WAIT) s3_rsp_rcvd <= 0;
end
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) s4_req_rcvd <= 0;
    else if(mb_repairclk_rx_valid && mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_done_req) s4_req_rcvd <= 1;
    else if(current_state != MB_S5_FINALIZE_REQ_WAIT) s4_req_rcvd <= 0;
end
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) s4_rsp_rcvd <= 0;
    else if(mb_repairclk_rx_valid && mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_done_resp) s4_rsp_rcvd <= 1;
    else if(current_state != MB_S5_FINALIZE_RSP_WAIT) s4_rsp_rcvd <= 0;
end

////////////////////////////////////////////////////////
// STATE REGISTER
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        current_state <= MB_S0_IDLE;
    end
    else begin
        current_state <= next_state;
    end
end
////////////////////////////////////////////////////////
// NEXT STATE
////////////////////////////////////////////////////////
always_comb begin
    next_state = current_state;

    case(current_state)
        MB_S0_IDLE: begin
            if(mb_repairclk_enable)
                next_state = MB_S1_READY_REQ_SEND;
        end
        // S1 Readiness REQ
        MB_S1_READY_REQ_SEND: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(ltsm_rdy)           next_state = MB_S1_READY_REQ_WAIT;
        end
        MB_S1_READY_REQ_WAIT: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(s1_req_rcvd)        next_state = MB_S1_READY_RSP_SEND;
        end
        // S1 Readiness RSP
        MB_S1_READY_RSP_SEND: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(ltsm_rdy)           next_state = MB_S1_READY_RSP_WAIT;
        end
        MB_S1_READY_RSP_WAIT: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(s1_rsp_rcvd)        next_state = MB_S2_PATTERN_TRANSMISSION;
        end
        // S2 Pattern
        MB_S2_PATTERN_TRANSMISSION: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(mb_tx_clk_pattern_transmission_completed) next_state = MB_S3_RESULT_REQ_SEND;
        end
        // S3 Result REQ
        MB_S3_RESULT_REQ_SEND: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(ltsm_rdy)           next_state = MB_S3_RESULT_REQ_WAIT;
        end
        MB_S3_RESULT_REQ_WAIT: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(s3_req_rcvd)        next_state = MB_S3_RESULT_RSP_SEND;
        end
        // S3 Result RSP
        MB_S3_RESULT_RSP_SEND: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(ltsm_rdy)           next_state = MB_S3_RESULT_RSP_WAIT;
        end
        MB_S3_RESULT_RSP_WAIT: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(s3_rsp_rcvd)        next_state = MB_S4_ERROR_CHECK;
        end
        // S4 Error Check
        MB_S4_ERROR_CHECK: begin
            if(!mb_repairclk_enable)              next_state = MB_S0_IDLE;
            else if(error_detect || timeout_error) next_state = MB_S6_REPAIRCLK_ERROR;
            else                                   next_state = MB_S5_FINALIZE_REQ_SEND;
        end
        // S5 Finalize REQ
        MB_S5_FINALIZE_REQ_SEND: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(ltsm_rdy)           next_state = MB_S5_FINALIZE_REQ_WAIT;
        end
        MB_S5_FINALIZE_REQ_WAIT: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(s4_req_rcvd)        next_state = MB_S5_FINALIZE_RSP_SEND;
        end
        // S5 Finalize RSP
        MB_S5_FINALIZE_RSP_SEND: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(ltsm_rdy)           next_state = MB_S5_FINALIZE_RSP_WAIT;
        end
        MB_S5_FINALIZE_RSP_WAIT: begin
            if(!mb_repairclk_enable)    next_state = MB_S0_IDLE;
            else if(timeout_error)      next_state = MB_S6_REPAIRCLK_ERROR;
            else if(s4_rsp_rcvd)        next_state = MB_S7_REPAIRCLK_DONE;
        end
        MB_S6_REPAIRCLK_ERROR: begin
            if(!mb_repairclk_enable) next_state = MB_S0_IDLE;
        end
        MB_S7_REPAIRCLK_DONE: begin
            if(!mb_repairclk_enable) next_state = MB_S0_IDLE;
        end
        default: next_state = MB_S0_IDLE;
    endcase
end

////////////////////////////////////////////////////////
// TX SB LOGIC
////////////////////////////////////////////////////////
always_comb begin

        mb_repairclk_tx_valid = 0;
        mb_repairclk_tx_msg_id = msg_no_e'(0);
        mb_repairclk_tx_MsgInfo = 0;
        mb_repairclk_tx_data_Field = 0;

        case(current_state)
            MB_S1_READY_REQ_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_init_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S1_READY_REQ_WAIT: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0; mb_repairclk_tx_data_Field = 0;
            end
            MB_S1_READY_RSP_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_init_resp;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S1_READY_RSP_WAIT: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0; mb_repairclk_tx_data_Field = 0;
            end
            MB_S2_PATTERN_TRANSMISSION: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0; mb_repairclk_tx_data_Field = 0;
            end
            MB_S3_RESULT_REQ_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_result_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;    
            end
            MB_S3_RESULT_REQ_WAIT: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0; mb_repairclk_tx_data_Field = 0; 
            end
            MB_S3_RESULT_RSP_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_result_resp;
                mb_repairclk_tx_MsgInfo = MB_repairclk_result_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S3_RESULT_RSP_WAIT: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0; mb_repairclk_tx_data_Field = 0;
            end
            MB_S5_FINALIZE_REQ_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_done_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S5_FINALIZE_REQ_WAIT: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0; mb_repairclk_tx_data_Field = 0;
            end
            MB_S5_FINALIZE_RSP_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_done_resp;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S5_FINALIZE_RSP_WAIT: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0; mb_repairclk_tx_data_Field = 0;
            end
            default: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0; mb_repairclk_tx_data_Field = 0;
            end
        endcase
end

////////////////////////////////////////////////////////
// RX CLOCK EN
////////////////////////////////////////////////////////
always_comb begin

    mb_rx_compare_clk_en = 0;
    case(current_state)

        MB_S1_READY_RSP_SEND,
        MB_S1_READY_RSP_WAIT,
        MB_S2_PATTERN_TRANSMISSION,
        MB_S3_RESULT_REQ_SEND,
        MB_S3_RESULT_REQ_WAIT,
        MB_S3_RESULT_RSP_SEND: begin
            mb_rx_compare_clk_en = 1;
        end
        default: begin
            mb_rx_compare_clk_en = 0;
        end
    endcase
end

////////////////////////////////////////////////////////
// TX PATTERN CLK EN
////////////////////////////////////////////////////////
always_comb begin

    mb_tx_pattern_clk_en = 0;
    case(current_state)
        MB_S2_PATTERN_TRANSMISSION: begin
            mb_tx_pattern_clk_en = 1;
        end
        default: begin
            mb_tx_pattern_clk_en = 0;
        end
    endcase
end

////////////////////////////////////////////////////////
// DONE
////////////////////////////////////////////////////////
always_comb begin
    mb_repairclk_done = (current_state == MB_S7_REPAIRCLK_DONE);
end

////////////////////////////////////////////////////////
// ERROR LOGIC
////////////////////////////////////////////////////////
always_comb begin
    mb_repairclk_error = (current_state == MB_S6_REPAIRCLK_ERROR);
end

endmodule