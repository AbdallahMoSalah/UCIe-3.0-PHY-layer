module MBINIT_REPAIRCLK
import UCIe_pkg::*;
(
    input  logic clk, rst_n,

    input  logic mb_repairclk_enable,

    output logic mb_repairclk_done,
    output logic mb_repairclk_error,

    // sb interface for messages
    input  logic sb_repairclk_rx_valid,
    input  msg_no_e sb_repairclk_rx_msg_id,
    input  logic [2:0] sb_repairclk_rx_MsgInfo,

    output logic sb_repairclk_tx_valid,
    output msg_no_e sb_repairclk_tx_msg_id,
    output logic [15:0] sb_repairclk_tx_MsgInfo,
    output logic [63:0] sb_repairclk_tx_data_Field,

    output logic       mb_tx_pattern_en      , // 1: Send pattern immediately, 0: Don't send pattern.
    output logic [2:0] mb_tx_pattern_setup   , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    
    output logic       mb_rx_compare_en            , // 1: Enable the Rx comparison circuit, 0: Disable.
    output logic [1:0] mb_rx_compare_setup   , // 00b: Per-Lane, 01b: Aggregate, 10b: Valid Lane, 11b: Clock Lane Comparison.

    input logic rtrk_pass,
    input logic rckn_pass,
    input logic rckp_pass,

    input logic mb_tx_pattern_count_done,

    // FIFO ready
    input  logic sb_ltsm_rdy,

    // Timer / Global Error signals
    input  logic global_error
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

logic [2:0] repairclk_result_local;
logic [15:0] MB_repairclk_result_MSG_Info;
assign MB_repairclk_result_MSG_Info = {13'b0, repairclk_result_local};


logic [2:0] partner_compare_result; // latched in s3_rsp_rcvd ff below

logic error_detect;
assign error_detect = !(&partner_compare_result);


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
    end else if (sb_repairclk_rx_valid) begin
        case (sb_repairclk_rx_msg_id)
            MBINIT_REPAIRCLK_init_req    : begin
                s1_req_rcvd <= 1'b1;
            end
            MBINIT_REPAIRCLK_init_resp   : begin
                if (current_state > MB_S1_READY_REQ_SEND) begin
                    s1_rsp_rcvd <= 1'b1;
                end
            end
            MBINIT_REPAIRCLK_result_req  : begin
                if (current_state > MB_S1_READY_RSP_SEND && s1_rsp_rcvd) begin
                    s3_req_rcvd            <= 1'b1;
                    repairclk_result_local <= {rtrk_pass, rckn_pass, rckp_pass};
                end
            end
            MBINIT_REPAIRCLK_result_resp : begin
                if (current_state > MB_S3_RESULT_REQ_SEND) begin
                    s3_rsp_rcvd            <= 1'b1;
                    partner_compare_result <= sb_repairclk_rx_MsgInfo[2:0];
                end
            end
            MBINIT_REPAIRCLK_done_req    : begin
                if (current_state > MB_S3_RESULT_RSP_SEND && s3_rsp_rcvd) begin
                    s4_req_rcvd <= 1'b1;
                end
            end
            MBINIT_REPAIRCLK_done_resp   : begin
                if (current_state > MB_S5_FINALIZE_REQ_SEND) begin
                    s4_rsp_rcvd <= 1'b1;
                end
            end
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
    else if(global_error && !mb_repairclk_done) begin
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
                if(sb_ltsm_rdy)           next_state = MB_S1_READY_REQ_WAIT;
            end
            MB_S1_READY_REQ_WAIT: begin
                if(s1_req_rcvd)        next_state = MB_S1_READY_RSP_SEND;
            end
            // S1 Readiness RSP
            MB_S1_READY_RSP_SEND: begin
                if(sb_ltsm_rdy)           next_state = MB_S1_READY_RSP_WAIT;
            end
            MB_S1_READY_RSP_WAIT: begin
                if(s1_rsp_rcvd)        next_state = MB_S2_PATTERN_TRANSMISSION;
            end
            // S2 Pattern
            MB_S2_PATTERN_TRANSMISSION: begin
                if(mb_tx_pattern_count_done) next_state = MB_S3_RESULT_REQ_SEND;
            end
            // S3 Result REQ
            MB_S3_RESULT_REQ_SEND: begin
                if(sb_ltsm_rdy)           next_state = MB_S3_RESULT_REQ_WAIT;
            end
            MB_S3_RESULT_REQ_WAIT: begin
                if(s3_req_rcvd)        next_state = MB_S3_RESULT_RSP_SEND;
            end
            // S3 Result RSP
            MB_S3_RESULT_RSP_SEND: begin
                if(sb_ltsm_rdy)           next_state = MB_S3_RESULT_RSP_WAIT;
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
                if(sb_ltsm_rdy)           next_state = MB_S5_FINALIZE_REQ_WAIT;
            end
            MB_S5_FINALIZE_REQ_WAIT: begin
                if(s4_req_rcvd)        next_state = MB_S5_FINALIZE_RSP_SEND;
            end
            // S5 Finalize RSP
            MB_S5_FINALIZE_RSP_SEND: begin
                if(sb_ltsm_rdy)           next_state = MB_S5_FINALIZE_RSP_WAIT;
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

        sb_repairclk_tx_valid = 0;
        sb_repairclk_tx_msg_id = msg_no_e'(NOTHING);
        sb_repairclk_tx_MsgInfo = MB_default_MSG_Info;
        sb_repairclk_tx_data_Field = MB_default_data_Field;

        case(current_state)
            MB_S1_READY_REQ_SEND: begin
                sb_repairclk_tx_valid = 1; sb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_init_req;
                sb_repairclk_tx_MsgInfo = MB_default_MSG_Info; sb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S1_READY_RSP_SEND: begin
                sb_repairclk_tx_valid = 1; sb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_init_resp;
                sb_repairclk_tx_MsgInfo = MB_default_MSG_Info; sb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S3_RESULT_REQ_SEND: begin
                sb_repairclk_tx_valid = 1; sb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_result_req;
                sb_repairclk_tx_MsgInfo = MB_default_MSG_Info; sb_repairclk_tx_data_Field = MB_default_data_Field;    
            end
            MB_S3_RESULT_RSP_SEND: begin
                sb_repairclk_tx_valid = 1; sb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_result_resp;
                sb_repairclk_tx_MsgInfo = MB_repairclk_result_MSG_Info; sb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S5_FINALIZE_REQ_SEND: begin
                sb_repairclk_tx_valid = 1; sb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_done_req;
                sb_repairclk_tx_MsgInfo = MB_default_MSG_Info; sb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            MB_S5_FINALIZE_RSP_SEND: begin
                sb_repairclk_tx_valid = 1; sb_repairclk_tx_msg_id = MBINIT_REPAIRCLK_done_resp;
                sb_repairclk_tx_MsgInfo = MB_default_MSG_Info; sb_repairclk_tx_data_Field = MB_default_data_Field;
            end
            default: begin
                sb_repairclk_tx_valid = 0; sb_repairclk_tx_msg_id = msg_no_e'(NOTHING);
                sb_repairclk_tx_MsgInfo = 0; sb_repairclk_tx_data_Field = 0;
            end
        endcase
end

////////////////////////////////////////////////////////
// RX CLOCK EN
////////////////////////////////////////////////////////
always_comb begin

    mb_rx_compare_en = 1'b0;
    mb_rx_compare_setup = 2'b11;
    case(current_state)

        MB_S1_READY_RSP_SEND,
        MB_S1_READY_RSP_WAIT,
        MB_S2_PATTERN_TRANSMISSION,
        MB_S3_RESULT_REQ_SEND,
        MB_S3_RESULT_REQ_WAIT: begin
            mb_rx_compare_en = 1'b1;
        end
        default: begin
            mb_rx_compare_en = 1'b0;
        end
    endcase
end

////////////////////////////////////////////////////////
// TX PATTERN CLK EN
////////////////////////////////////////////////////////
always_comb begin

    mb_tx_pattern_en = 0;
    mb_tx_pattern_setup = 3'b100;
    case(current_state)
        MB_S2_PATTERN_TRANSMISSION: begin
            mb_tx_pattern_en = 1;
        end
        default: begin
            mb_tx_pattern_en = 0;
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

////////////////////////////////////////////////////////
// SYSTEMVERILOG ASSERTIONS (SVA) FOR REPAIRCLK
////////////////////////////////////////////////////////
`ifdef SIMULATION
    // 1. Handshake Integrity: No init_resp sent without init_req received first
    property p_tx_start_resp_after_req;
        @(posedge clk) disable iff (!rst_n)
        (sb_repairclk_tx_valid && sb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_init_resp) |-> s1_req_rcvd;
    endproperty
    assert_tx_start_resp_after_req: assert property(p_tx_start_resp_after_req);

    // 2. Handshake Integrity: No result_resp sent without result_req received first
    property p_tx_degrade_resp_after_req;
        @(posedge clk) disable iff (!rst_n)
        (sb_repairclk_tx_valid && sb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_result_resp) |-> s3_req_rcvd;
    endproperty
    assert_tx_degrade_resp_after_req: assert property(p_tx_degrade_resp_after_req);

    // 3. Handshake Integrity: No done_resp sent without done_req received first
    property p_tx_end_resp_after_req;
        @(posedge clk) disable iff (!rst_n)
        (sb_repairclk_tx_valid && sb_repairclk_tx_msg_id == MBINIT_REPAIRCLK_done_resp) |-> s4_req_rcvd;
    endproperty
    assert_tx_end_resp_after_req: assert property(p_tx_end_resp_after_req);

    // 4. Bounded Liveness: init_req must eventually be answered or enter S6 error
    property p_start_req_leads_to_resp_or_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S1_READY_REQ_WAIT) |-> (##[1:2000] (s1_rsp_rcvd || current_state == MB_S6_REPAIRCLK_ERROR));
    endproperty
    assert_start_req_leads_to_resp_or_error: assert property(p_start_req_leads_to_resp_or_error);

    // 5. Bounded Liveness: result_req must eventually be answered or enter S6 error
    property p_degrade_req_leads_to_resp_or_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S3_RESULT_RSP_WAIT) |-> (##[1:2000] (s3_rsp_rcvd || current_state == MB_S6_REPAIRCLK_ERROR));
    endproperty
    assert_degrade_req_leads_to_resp_or_error: assert property(p_degrade_req_leads_to_resp_or_error);

    // 6. Bounded Liveness: done_req must eventually be answered or enter S6 error
    property p_end_req_leads_to_resp_or_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S5_FINALIZE_RSP_WAIT) |-> (##[1:2000] (s4_rsp_rcvd || current_state == MB_S6_REPAIRCLK_ERROR));
    endproperty
    assert_end_req_leads_to_resp_or_error: assert property(p_end_req_leads_to_resp_or_error);

    // 7. Protocol Rule: Sideband TX stability until sb_ltsm_rdy asserts
    property p_tx_stability_until_rdy;
        @(posedge clk) disable iff (!rst_n || !mb_repairclk_enable)
        (sb_repairclk_tx_valid && !sb_ltsm_rdy) |-> 
        ##1 (sb_repairclk_tx_valid && 
             $stable(sb_repairclk_tx_msg_id) && 
             $stable(sb_repairclk_tx_MsgInfo) && 
             $stable(sb_repairclk_tx_data_Field));
    endproperty
    assert_tx_stability_until_rdy: assert property(p_tx_stability_until_rdy);

    // 8. Error Check: Error states raise error flag
    property p_error_condition_raises_error;
        @(posedge clk) disable iff (!rst_n)
        (global_error && mb_repairclk_enable) ||
        (current_state == MB_S4_ERROR_CHECK && error_detect)
        |-> ##[1:5] (current_state == MB_S6_REPAIRCLK_ERROR && mb_repairclk_error == 1'b1);
    endproperty
    assert_error_condition_raises_error: assert property(p_error_condition_raises_error);

    // 9. Success Check: Done state asserts done flag
    property p_success_path_leads_to_done;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S5_FINALIZE_RSP_WAIT && s4_rsp_rcvd && !global_error)
        |-> ##[1:5] (current_state == MB_S7_REPAIRCLK_DONE && mb_repairclk_done == 1'b1);
    endproperty
    assert_success_path_leads_to_done: assert property(p_success_path_leads_to_done);

    // 10. Safety Check: Done and Error are mutually exclusive
    assert_never_done_and_error: assert property (
        @(posedge clk) disable iff (!rst_n) 
        !(mb_repairclk_done && mb_repairclk_error)
    );

    // 11. FSM State Coverage Checks
    cover_state_idle:         cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S0_IDLE);
    cover_state_s1_req_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_READY_REQ_SEND);
    cover_state_s1_req_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_READY_REQ_WAIT);
    cover_state_s1_rsp_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_READY_RSP_SEND);
    cover_state_s1_rsp_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S1_READY_RSP_WAIT);
    cover_state_s2_pattern:   cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S2_PATTERN_TRANSMISSION);
    cover_state_s3_req_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_RESULT_REQ_SEND);
    cover_state_s3_req_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_RESULT_REQ_WAIT);
    cover_state_s3_rsp_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_RESULT_RSP_SEND);
    cover_state_s3_rsp_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S3_RESULT_RSP_WAIT);
    cover_state_s4_verify:    cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S4_ERROR_CHECK);
    cover_state_s5_req_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_FINALIZE_REQ_SEND);
    cover_state_s5_req_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_FINALIZE_REQ_WAIT);
    cover_state_s5_rsp_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_FINALIZE_RSP_SEND);
    cover_state_s5_rsp_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_FINALIZE_RSP_WAIT);
    cover_state_s6_error:     cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S6_REPAIRCLK_ERROR);
    cover_state_s7_done:      cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S7_REPAIRCLK_DONE);
`endif

endmodule
