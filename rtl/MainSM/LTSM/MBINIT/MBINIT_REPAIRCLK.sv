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

    output logic timeout_error,

    output logic [2:0] mb_tx_pattern_setup ,
    output logic [1:0] mb_tx_clk_pattern_sel,
    output logic [1:0] mb_rx_compare_setup,

    output logic mb_tx_pattern_en,
    output logic mb_rx_compare_en,

    input logic rtrk_pass,
    input logic rckn_pass,
    input logic rckp_pass,

    input logic mb_rx_compare_done
);

////////////////////////////////////////////////////////
// STATES
////////////////////////////////////////////////////////
typedef enum logic [3:0] { 
    MB_S0_IDLE,
    MB_S1_READINESS_HANDSHAKE_REQ,
    MB_S1_READINESS_HANDSHAKE_RSP,
    MB_S2_PATTERN_TRANSMISSION,
    MB_S3_RESULT_EXCHANGE_REQ,
    MB_S3_RESULT_EXCHANGE_RSP,
    MB_S4_FINALIZE_HANDSHAKE_REQ,
    MB_S4_FINALIZE_HANDSHAKE_RSP
} mb_repairclk_state_e;

mb_repairclk_state_e current_state, next_state;

////////////////////////////////////////////////////////
// DEFAULTS
////////////////////////////////////////////////////////
localparam logic [15:0] MB_default_MSG_Info = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0;

assign mb_tx_pattern_setup   = 3'b100;
assign mb_tx_clk_pattern_sel = 2'b10;
assign mb_rx_compare_setup   = 2'b11;

logic [2:0] repairclk_result_local;
assign repairclk_result_local = {rtrk_pass, rckn_pass, rckp_pass};

logic [15:0] MB_repairclk_result_MSG_Info;
assign MB_repairclk_result_MSG_Info = {13'b0, repairclk_result_local};

////////////////////////////////////////////////////////
// TIMEOUT
////////////////////////////////////////////////////////
logic timer_enable;
logic timeout_expired;

assign timer_enable = mb_repairclk_enable && !mb_repairclk_done && !mb_repairclk_error;

timeout_counter #(
    .CLK_FRQ_HZ(CLK_FRQ_HZ),
    .TIME_OUT(8)
) u_timeout (
    .clk(clk),
    .timeout_rst_n(rst_n),
    .enable_timeout(timer_enable),
    .timeout_expired(timeout_expired)
);

assign timeout_error = timeout_expired && !mb_repairclk_done;

////////////////////////////////////////////////////////
// HANDSHAKE FLAGS
////////////////////////////////////////////////////////
logic s1_req_sent, s1_req_rcvd;
logic s1_rsp_sent, s1_rsp_rcvd;
logic s3_req_sent, s3_req_rcvd;
logic s3_rsp_sent, s3_rsp_rcvd;
logic s4_req_sent, s4_req_rcvd;
logic s4_rsp_sent, s4_rsp_rcvd;

////////////////////////////////////////////////////////
// RX FLAGS
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        s1_req_rcvd <= 0; s1_rsp_rcvd <= 0;
        s3_req_rcvd <= 0; s3_rsp_rcvd <= 0;
        s4_req_rcvd <= 0; s4_rsp_rcvd <= 0;
    end
    else begin
        if(mb_repairclk_rx_valid) begin

            case(current_state)

            MB_S1_READINESS_HANDSHAKE_REQ:
                if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_init_req)
                    s1_req_rcvd <= 1;

            MB_S1_READINESS_HANDSHAKE_RSP:
                if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_init_resp)
                    s1_rsp_rcvd <= 1;

            MB_S3_RESULT_EXCHANGE_REQ:
                if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_result_req)
                    s3_req_rcvd <= 1;

            MB_S3_RESULT_EXCHANGE_RSP:
                if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_result_resp)
                    s3_rsp_rcvd <= 1;

            MB_S4_FINALIZE_HANDSHAKE_REQ:
                if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_done_req)
                    s4_req_rcvd <= 1;

            MB_S4_FINALIZE_HANDSHAKE_RSP:
                if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_done_resp)
                    s4_rsp_rcvd <= 1;

            endcase
        end
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

    if(timeout_error)
        next_state = MB_S0_IDLE;

    case(current_state)

    MB_S0_IDLE:
        if(mb_repairclk_enable && !mb_repairclk_done && !mb_repairclk_error)
            next_state = MB_S1_READINESS_HANDSHAKE_REQ;

    MB_S1_READINESS_HANDSHAKE_REQ:
        if(s1_req_sent && s1_req_rcvd)
            next_state = MB_S1_READINESS_HANDSHAKE_RSP;

    MB_S1_READINESS_HANDSHAKE_RSP:
        if(s1_rsp_sent && s1_rsp_rcvd)
            next_state = MB_S2_PATTERN_TRANSMISSION;

    MB_S2_PATTERN_TRANSMISSION:
        if(mb_rx_compare_done)
            next_state = MB_S3_RESULT_EXCHANGE_REQ;

    MB_S3_RESULT_EXCHANGE_REQ:
        if(s3_req_sent && s3_req_rcvd)
            next_state = MB_S3_RESULT_EXCHANGE_RSP;

    MB_S3_RESULT_EXCHANGE_RSP:
        if(s3_rsp_sent && s3_rsp_rcvd)
            next_state = MB_S4_FINALIZE_HANDSHAKE_REQ;

    MB_S4_FINALIZE_HANDSHAKE_REQ:
        if(s4_req_sent && s4_req_rcvd)
            next_state = MB_S4_FINALIZE_HANDSHAKE_RSP;

    MB_S4_FINALIZE_HANDSHAKE_RSP:
        if(s4_rsp_sent && s4_rsp_rcvd)
            next_state = MB_S0_IDLE;

    endcase
end

////////////////////////////////////////////////////////
// TX LOGIC
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin

        mb_repairclk_tx_valid <= 0;
        mb_repairclk_tx_msg_id <= msg_no_e'(0);
        mb_repairclk_tx_MsgInfo <= 0;
        mb_repairclk_tx_data_Field <= 0;

        s1_req_sent <= 0; s1_rsp_sent <= 0;
        s3_req_sent <= 0; s3_rsp_sent <= 0;
        s4_req_sent <= 0; s4_rsp_sent <= 0;
    end
    else if(mb_repairclk_enable && !mb_repairclk_done) begin
        mb_repairclk_tx_valid <= 0;
        mb_repairclk_tx_data_Field <= 0;
        
        case(current_state)

        MB_S1_READINESS_HANDSHAKE_REQ:
            if(!s1_req_sent) begin
                mb_repairclk_tx_valid <= 1;
                mb_repairclk_tx_msg_id <= MBINIT_REPAIRCLK_init_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                mb_repairclk_tx_data_Field = MB_default_data_Field;
                s1_req_sent <= 1;
            end

        MB_S1_READINESS_HANDSHAKE_RSP:
            if(!s1_rsp_sent) begin
                mb_repairclk_tx_valid <= 1;
                mb_repairclk_tx_msg_id <= MBINIT_REPAIRCLK_init_resp;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                mb_repairclk_tx_data_Field = MB_default_data_Field;
                s1_rsp_sent <= 1;
            end

        MB_S3_RESULT_EXCHANGE_REQ:
            if(!s3_req_sent) begin
                mb_repairclk_tx_valid <= 1;
                mb_repairclk_tx_msg_id <= MBINIT_REPAIRCLK_result_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                mb_repairclk_tx_data_Field = MB_default_data_Field;
                s3_req_sent <= 1;
            end

        MB_S3_RESULT_EXCHANGE_RSP:
            if(!s3_rsp_sent) begin
                mb_repairclk_tx_valid <= 1;
                mb_repairclk_tx_msg_id <= MBINIT_REPAIRCLK_result_resp;
                mb_repairclk_tx_MsgInfo <= MB_repairclk_result_MSG_Info;
                mb_repairclk_tx_data_Field = MB_default_data_Field;
                s3_rsp_sent <= 1;
            end

        MB_S4_FINALIZE_HANDSHAKE_REQ:
            if(!s4_req_sent) begin
                mb_repairclk_tx_valid <= 1;
                mb_repairclk_tx_msg_id <= MBINIT_REPAIRCLK_done_req;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                mb_repairclk_tx_data_Field = MB_default_data_Field;
                s4_req_sent <= 1;
            end

        MB_S4_FINALIZE_HANDSHAKE_RSP:
            if(!s4_rsp_sent) begin
                mb_repairclk_tx_valid <= 1;
                mb_repairclk_tx_msg_id <= MBINIT_REPAIRCLK_done_resp;
                mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                mb_repairclk_tx_data_Field = MB_default_data_Field;
                s4_rsp_sent <= 1;
            end

        endcase
    end
end

////////////////////////////////////////////////////////
// PATTERN
////////////////////////////////////////////////////////
assign mb_tx_pattern_en = (current_state == MB_S2_PATTERN_TRANSMISSION && !mb_repairclk_done);
assign mb_rx_compare_en = (current_state == MB_S2_PATTERN_TRANSMISSION && !mb_repairclk_done);

////////////////////////////////////////////////////////
// DONE
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_repairclk_done <= 0;
    else if(current_state == MB_S4_FINALIZE_HANDSHAKE_RSP &&
            s4_rsp_sent && s4_rsp_rcvd)
        mb_repairclk_done <= 1;
end

////////////////////////////////////////////////////////
// ERROR LOGIC
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        mb_repairclk_error <= 0;

    else if(timeout_error)
        mb_repairclk_error <= 1;

    else if(mb_repairclk_rx_valid) begin

        case(current_state)

        MB_S1_READINESS_HANDSHAKE_REQ,
        MB_S1_READINESS_HANDSHAKE_RSP:
            if(!(mb_repairclk_rx_msg_id inside {
                MBINIT_REPAIRCLK_init_req,
                MBINIT_REPAIRCLK_init_resp
            }))
                mb_repairclk_error <= 1;

        MB_S3_RESULT_EXCHANGE_REQ,
        MB_S3_RESULT_EXCHANGE_RSP:
            if(!(mb_repairclk_rx_msg_id inside {
                MBINIT_REPAIRCLK_result_req,
                MBINIT_REPAIRCLK_result_resp
            }))
                mb_repairclk_error <= 1;

        MB_S4_FINALIZE_HANDSHAKE_REQ,
        MB_S4_FINALIZE_HANDSHAKE_RSP:
            if(!(mb_repairclk_rx_msg_id inside {
                MBINIT_REPAIRCLK_done_req,
                MBINIT_REPAIRCLK_done_resp
            }))
                mb_repairclk_error <= 1;

        endcase
    end
    else if (!(rtrk_pass && rckn_pass && rckp_pass)) 
        mb_repairclk_error <= 1;
        
end

endmodule