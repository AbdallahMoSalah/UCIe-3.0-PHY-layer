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

    //Timer signals
    input logic timeout_repairclk_expired,
    output logic timeout_repairclk_enable
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

    MB_S4_ERROR_CHECK,

    MB_S5_FINALIZE_HANDSHAKE_REQ,
    MB_S5_FINALIZE_HANDSHAKE_RSP,

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


logic [2:0] partner_compare_result;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        partner_compare_result <= 3'b111;
    end
    else if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_result_resp && mb_repairclk_rx_valid) begin
        partner_compare_result <= mb_repairclk_rx_data_Field[2:0];
    end
end

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

////////////////////////////////////////////////////////
//////////////// Entry Detection logic /////////////////
////////////////////////////////////////////////////////
logic s1_req_entry;
logic s1_resp_entry;
logic s3_req_entry;
logic s3_resp_entry;
logic s4_req_entry;
logic s4_resp_entry;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        s1_req_entry  <= 0;
        s1_resp_entry <= 0;
        s3_req_entry  <= 0;
        s3_resp_entry <= 0;
        s4_req_entry  <= 0;
        s4_resp_entry <= 0;
    end

    else begin
        s1_req_entry  <= (current_state != MB_S1_READINESS_HANDSHAKE_REQ)   && (next_state == MB_S1_READINESS_HANDSHAKE_REQ);
        s1_resp_entry <= (current_state != MB_S1_READINESS_HANDSHAKE_RSP)   && (next_state == MB_S1_READINESS_HANDSHAKE_RSP);
        s3_req_entry  <= (current_state != MB_S3_RESULT_EXCHANGE_REQ) && (next_state == MB_S3_RESULT_EXCHANGE_REQ);
        s3_resp_entry <= (current_state != MB_S3_RESULT_EXCHANGE_RSP) && (next_state == MB_S3_RESULT_EXCHANGE_RSP);
        s4_req_entry  <= (current_state != MB_S4_FINALIZE_HANDSHAKE_REQ) && (next_state == MB_S4_FINALIZE_HANDSHAKE_REQ);
        s4_resp_entry <= (current_state != MB_S4_FINALIZE_HANDSHAKE_RSP) && (next_state == MB_S4_FINALIZE_HANDSHAKE_RSP);
    end
end
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

            if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_init_req) begin
                s1_req_rcvd <= 1;
            end
            else if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_init_resp) begin
                s1_rsp_rcvd <= 1;
            end
            else if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_result_req) begin
                s3_req_rcvd <= 1;
            end

            else if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_result_resp) begin
                s3_rsp_rcvd <= 1;
            end
            else if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_done_req) begin
                s4_req_rcvd <= 1;
            end

            else if(mb_repairclk_rx_msg_id == MBINIT_REPAIRCLK_done_resp) begin
                s4_rsp_rcvd <= 1;
            end
        end
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

    case(current_state)

        MB_S0_IDLE: begin
            if(mb_repairclk_enable && !mb_repairclk_done)
                next_state = MB_S1_READINESS_HANDSHAKE_REQ;
        end

        MB_S1_READINESS_HANDSHAKE_REQ: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE
            end
            else if(timeout_error) begin
                next_state = MB_S6_REPAIRCLK_ERROR
            end
            else if(s1_req_rcvd) begin
                next_state = MB_S1_READINESS_HANDSHAKE_RSP;
            end
            else begin
                next_state = MB_S1_READINESS_HANDSHAKE_REQ;
            end
        end


        MB_S1_READINESS_HANDSHAKE_RSP: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE
            end
            else if(timeout_error) begin
                next_state = MB_S6_REPAIRCLK_ERROR
            end
            else if(s1_rsp_rcvd) begin
                next_state = MB_S2_PATTERN_TRANSMISSION;
            end
            else begin
                next_state = MB_S1_READINESS_HANDSHAKE_RSP;
            end
        end

        MB_S2_PATTERN_TRANSMISSION: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE
            end
            else if(timeout_error) begin
                next_state = MB_S6_REPAIRCLK_ERROR
            end
            else if(mb_tx_clk_pattern_transmission_completed) begin
                next_state = MB_S3_RESULT_EXCHANGE_REQ;
            end
            else begin
                next_state = MB_S2_PATTERN_TRANSMISSION;
            end
        end

        MB_S3_RESULT_EXCHANGE_REQ: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE
            end
            else if(timeout_error) begin
                next_state = MB_S6_REPAIRCLK_ERROR
            end
            else if(s3_req_rcvd) begin
                next_state = MB_S3_RESULT_EXCHANGE_RSP;
            end
            else begin
                next_state = MB_S3_RESULT_EXCHANGE_REQ;
            end
        end
        
        MB_S3_RESULT_EXCHANGE_RSP: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE
            end
            else if(timeout_error) begin
                next_state = MB_S6_REPAIRCLK_ERROR
            end
            else if(s3_rsp_rcvd) begin
                next_state = MB_S4_ERROR_CHECK;
            end
            else begin
                next_state = MB_S3_RESULT_EXCHANGE_RSP;
            end
        end

        MB_S4_ERROR_CHECK: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE
            end
            else if(error_detect || timeout_error) begin
                next_state = MB_S6_REPAIRCLK_ERROR
            end
            else begin
                next_state = MB_S5_FINALIZE_HANDSHAKE_REQ;
            end
        end

        MB_S5_FINALIZE_HANDSHAKE_REQ: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE
            end
            else if(timeout_error) begin
                next_state = MB_S6_REPAIRCLK_ERROR
            end
            else if(s4_req_rcvd) begin
                next_state = MB_S5_FINALIZE_HANDSHAKE_RSP;
            end
            else begin
                next_state = MB_S5_FINALIZE_HANDSHAKE_REQ;
            end
        end

        MB_S5_FINALIZE_HANDSHAKE_RSP: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE
            end
            else if(timeout_error) begin
                next_state = MB_S6_REPAIRCLK_ERROR
            end
            else if(s4_rsp_rcvd) begin
                next_state = MB_S7_REPAIRCLK_DONE;
            end
            else begin
                next_state = MB_S5_FINALIZE_HANDSHAKE_RSP;
            end
        end

        MB_S6_REPAIRCLK_ERROR: begin
            if(!mb_repairclk_enable) begin
                next_state = MB_S0_IDLE;
            end
            else begin
                next_state = MB_S6_REPAIRCLK_ERROR;
            end
        end

        MB_S7_REPAIRCLK_DONE: begin
            if(mb_repairclk_enable) begin
                next_state = MB_S0_IDLE;
            end
            else begin
                next_state = MB_S7_REPAIRCLK_DONE;
            end
        end

        default: begin
            next_state = MB_S0_IDLE;
        end
    endcase
end

////////////////////////////////////////////////////////
// TX LOGIC
////////////////////////////////////////////////////////
always_comb begin

        mb_repairclk_tx_valid = 0;
        mb_repairclk_tx_msg_id = msg_no_e'(0);
        mb_repairclk_tx_MsgInfo = 0;
        mb_repairclk_tx_data_Field = 0;

        case(current_state)

            MB_S1_READINESS_HANDSHAKE_REQ: begin
                if(s1_req_entry) begin
                    mb_repairclk_tx_valid = 1;
                    mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_init_req;
                    mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                    mb_repairclk_tx_data_Field = MB_default_data_Field;
                end
                else begin
                    mb_repairclk_tx_valid = 0;
                    mb_repairclk_tx_msg_id = msg_no_e'(0);
                    mb_repairclk_tx_MsgInfo = 0;
                    mb_repairclk_tx_data_Field = 0;
                end
            end

            MB_S1_READINESS_HANDSHAKE_RSP: begin
                if(s1_resp_entry) begin
                    mb_repairclk_tx_valid = 1;
                    mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_init_resp;
                    mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                    mb_repairclk_tx_data_Field = MB_default_data_Field;
                end
                else begin
                    mb_repairclk_tx_valid = 0;
                    mb_repairclk_tx_msg_id = msg_no_e'(0);
                    mb_repairclk_tx_MsgInfo = 0;
                    mb_repairclk_tx_data_Field = 0;
                end
            end

            MB_S3_RESULT_EXCHANGE_REQ: begin
                if(s3_req_entry) begin
                    mb_repairclk_tx_valid = 1;
                    mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_result_req;
                    mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                    mb_repairclk_tx_data_Field = MB_default_data_Field;
                end
                else begin
                    mb_repairclk_tx_valid = 0;
                    mb_repairclk_tx_msg_id = msg_no_e'(0);
                    mb_repairclk_tx_MsgInfo = 0;
                    mb_repairclk_tx_data_Field = 0;
                end
            end

            MB_S3_RESULT_EXCHANGE_RSP: begin
                if(s3_resp_entry) begin
                    mb_repairclk_tx_valid = 1;
                    mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_result_resp;
                    mb_repairclk_tx_MsgInfo = MB_repairclk_result_MSG_Info;
                    mb_repairclk_tx_data_Field = MB_default_data_Field;
                    
                end
                else begin
                    mb_repairclk_tx_valid = 0;
                    mb_repairclk_tx_msg_id = msg_no_e'(0);
                    mb_repairclk_tx_MsgInfo = 0;
                    mb_repairclk_tx_data_Field = 0;
                end
            end

            MB_S4_FINALIZE_HANDSHAKE_REQ: begin
                if(s4_req_entry) begin
                    mb_repairclk_tx_valid = 1;
                    mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_done_req;
                    mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                    mb_repairclk_tx_data_Field = MB_default_data_Field;
                end
                else begin
                    mb_repairclk_tx_valid = 0;
                    mb_repairclk_tx_msg_id = msg_no_e'(0);
                    mb_repairclk_tx_MsgInfo = 0;
                    mb_repairclk_tx_data_Field = 0;
                end
            end

            MB_S4_FINALIZE_HANDSHAKE_RSP: begin
                if(s4_resp_entry) begin
                    mb_repairclk_tx_valid = 1;
                    mb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_done_resp;
                    mb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
                    mb_repairclk_tx_data_Field = MB_default_data_Field;
                end
                else begin
                    mb_repairclk_tx_valid = 0;
                    mb_repairclk_tx_msg_id = msg_no_e'(0);
                    mb_repairclk_tx_MsgInfo = 0;
                    mb_repairclk_tx_data_Field = 0;
                end
            end

            default: begin
                mb_repairclk_tx_valid = 0;
                mb_repairclk_tx_msg_id = msg_no_e'(0);
                mb_repairclk_tx_MsgInfo = 0;
                mb_repairclk_tx_data_Field = 0;
            end
        endcase
    end

////////////////////////////////////////////////////////
// PATTERN
////////////////////////////////////////////////////////
assign mb_tx_pattern_clk_en = ((current_state == MB_S2_PATTERN_TRANSMISSION) && (!mb_repairclk_done));
assign mb_rx_compare_en     = ((current_state == MB_S1_READINESS_HANDSHAKE_RSP ) ||  (current_state == MB_S2_PATTERN_TRANSMISSION) && (!mb_repairclk_done));

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