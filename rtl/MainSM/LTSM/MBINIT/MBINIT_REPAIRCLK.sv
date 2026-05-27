import UCIe_pkg::*;

module MBINIT_REPAIRCLK
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
// HANDSHAKE FLAGS + DATA CAPTURE
////////////////////////////////////////////////////////
// When mb_repairclk_rx_valid is high, a case on mb_repairclk_rx_msg_id:
//   • sets the matching flag
//   • captures payload / local results into the corresponding register (begin..end)
// All flags are cleared together on reset or when the FSM returns to IDLE.
////////////////////////////////////////////////////////
logic s1_req_rcvd;
logic s1_rsp_rcvd;
logic s3_req_rcvd;
logic s3_rsp_rcvd;
logic s4_req_rcvd;
logic s4_rsp_rcvd;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_req_rcvd            <= 1'b0;
        s1_rsp_rcvd            <= 1'b0;
        s3_req_rcvd            <= 1'b0;
        s3_rsp_rcvd            <= 1'b0;
        s4_req_rcvd            <= 1'b0;
        s4_rsp_rcvd            <= 1'b0;
        repairclk_result_local <= 3'b000;
        partner_compare_result <= 3'b111;
    end else if (current_state == MB_S0_IDLE) begin
        s1_req_rcvd            <= 1'b0;
        s1_rsp_rcvd            <= 1'b0;
        s3_req_rcvd            <= 1'b0;
        s3_rsp_rcvd            <= 1'b0;
        s4_req_rcvd            <= 1'b0;
        s4_rsp_rcvd            <= 1'b0;
        repairclk_result_local <= 3'b000;
        partner_compare_result <= 3'b111;
    end else if (mb_repairclk_rx_valid) begin
        case (mb_repairclk_rx_msg_id)
            MBINIT_REPAIRCLK_init_req    : s1_req_rcvd <= 1'b1;
            MBINIT_REPAIRCLK_init_resp   : s1_rsp_rcvd <= 1'b1;
            MBINIT_REPAIRCLK_result_req  : begin
                s3_req_rcvd            <= 1'b1;
                repairclk_result_local <= {rtrk_pass, rckn_pass, rckp_pass};
            end
            MBINIT_REPAIRCLK_result_resp : begin
                s3_rsp_rcvd            <= 1'b1;
                partner_compare_result <= mb_repairclk_rx_MsgInfo[2:0];
            end
            MBINIT_REPAIRCLK_done_req    : s4_req_rcvd <= 1'b1;
            MBINIT_REPAIRCLK_done_resp   : s4_rsp_rcvd <= 1'b1;
            default                      : ; // ignore unrelated messages
        endcase
    end
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

    if(!mb_repairclk_enable) begin
        next_state = MB_S0_IDLE;
    end
    else if(timeout_error) begin
        next_state = MB_S6_REPAIRCLK_ERROR;
    end
    else begin
        case(current_state)
            MB_S0_IDLE: begin
                if(mb_repairclk_enable)
                    next_state = MB_S1_READY_REQ_SEND;
            end
            // S1 Readiness REQ
            MB_S1_READY_REQ_SEND: begin
                if(ltsm_rdy)           next_state = MB_S1_READY_REQ_WAIT;
            end
            MB_S1_READY_REQ_WAIT: begin
                if(s1_req_rcvd)        next_state = MB_S1_READY_RSP_SEND;
            end
            // S1 Readiness RSP
            MB_S1_READY_RSP_SEND: begin
                if(ltsm_rdy)           next_state = MB_S1_READY_RSP_WAIT;
            end
            MB_S1_READY_RSP_WAIT: begin
                if(s1_rsp_rcvd)        next_state = MB_S2_PATTERN_TRANSMISSION;
            end
            // S2 Pattern
            MB_S2_PATTERN_TRANSMISSION: begin
                if(mb_tx_clk_pattern_transmission_completed) next_state = MB_S3_RESULT_REQ_SEND;
            end
            // S3 Result REQ
            MB_S3_RESULT_REQ_SEND: begin
                if(ltsm_rdy)           next_state = MB_S3_RESULT_REQ_WAIT;
            end
            MB_S3_RESULT_REQ_WAIT: begin
                if(s3_req_rcvd)        next_state = MB_S3_RESULT_RSP_SEND;
            end
            // S3 Result RSP
            MB_S3_RESULT_RSP_SEND: begin
                if(ltsm_rdy)           next_state = MB_S3_RESULT_RSP_WAIT;
            end
            MB_S3_RESULT_RSP_WAIT: begin
                if(s3_rsp_rcvd)        next_state = MB_S4_ERROR_CHECK;
            end
            // S4 Error Check
            MB_S4_ERROR_CHECK: begin
                if(error_detect) next_state = MB_S6_REPAIRCLK_ERROR;
                else             next_state = MB_S5_FINALIZE_REQ_SEND;
            end
            // S5 Finalize REQ
            MB_S5_FINALIZE_REQ_SEND: begin
                if(ltsm_rdy)           next_state = MB_S5_FINALIZE_REQ_WAIT;
            end
            MB_S5_FINALIZE_REQ_WAIT: begin
                if(s4_req_rcvd)        next_state = MB_S5_FINALIZE_RSP_SEND;
            end
            // S5 Finalize RSP
            MB_S5_FINALIZE_RSP_SEND: begin
                if(ltsm_rdy)           next_state = MB_S5_FINALIZE_RSP_WAIT;
            end
            MB_S5_FINALIZE_RSP_WAIT: begin
                if(s4_rsp_rcvd)        next_state = MB_S7_REPAIRCLK_DONE;
            end
            MB_S6_REPAIRCLK_ERROR: begin
                // Stays here until mb_repairclk_enable deasserts
            end
            MB_S7_REPAIRCLK_DONE: begin
                // Stays here until mb_repairclk_enable deasserts
            end
            default: begin
                next_state = MB_S0_IDLE;
            end
        endcase
    end
    
end

////////////////////////////////////////////////////////
// TX SB LOGIC
////////////////////////////////////////////////////////
always_comb begin

        mb_repairclk_tx_valid = 0;
        mb_repairclk_tx_msg_id = msg_no_e'(NOTHING);
        mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
        mb_repairclk_tx_data_Field = MB_default_data_Field;

        case(current_state)
            MB_S1_READY_REQ_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_init_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S1_READY_RSP_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_init_resp;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S3_RESULT_REQ_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_result_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;    
            end
            MB_S3_RESULT_RSP_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_result_resp;
                mb_repairclk_tx_MsgInfo = MB_repairclk_result_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S5_FINALIZE_REQ_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_done_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S5_FINALIZE_RSP_SEND: begin
                mb_repairclk_tx_valid = 1; mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_done_resp;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info; mb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            default: begin
                mb_repairclk_tx_valid = 0; mb_repairclk_tx_msg_id = msg_no_e'(NOTHING);
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
        MB_S3_RESULT_REQ_WAIT: begin
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