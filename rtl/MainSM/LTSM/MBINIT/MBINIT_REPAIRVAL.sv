import UCIe_pkg::*;

module MBINIT_REPAIRVAL
#( parameter int CLK_FRQ_HZ = 800000000)
(
    input  logic clk, rst_n,

    input  logic mb_repairval_enable,

    output logic mb_repairval_done,
    output logic mb_repairval_error,

    input  logic mb_repairval_rx_valid,
    input  msg_no_e mb_repairval_rx_msg_id,
    input  logic [15:0] mb_repairval_rx_MsgInfo,
    input  logic [63:0] mb_repairval_rx_data_Field,

    output logic mb_repairval_tx_valid,
    output msg_no_e mb_repairval_tx_msg_id,
    output logic [15:0] mb_repairval_tx_MsgInfo,
    output logic [63:0] mb_repairval_tx_data_Field,

    output logic       mb_tx_pattern_en      , // 1: Send pattern immediately, 0: Don't send pattern.
    output logic [2:0] mb_tx_pattern_setup   , // 001b: Data Pattern, 010b: Valid Pattern, 100b: Clock Pattern.
    output logic       mb_tx_val_pattern_sel , // 0: VALTRAIN pattern, 1: Held Low.
    
    output logic       mb_rx_compare_en      , // 1: Enable the Rx comparison circuit, 0: Disable.
    output logic [1:0] mb_rx_compare_setup   , // 00b: Per-Lane, 01b: Aggregate, 10b: Valid Lane, 11b: Clock Pattern.

    input logic mb_rx_val_pass,
    input logic mb_tx_pattern_count_done,

    // FIFO ready (write-side handshake)
    input  logic ltsm_rdy,

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

    // S4 Finalize (split)
    MB_S4_FINALIZE_REQ_SEND,
    MB_S4_FINALIZE_REQ_WAIT,

    MB_S4_FINALIZE_RSP_SEND,
    MB_S4_FINALIZE_RSP_WAIT,

    MB_S5_ERROR,
    MB_S6_DONE

} mb_repairval_state_e;

mb_repairval_state_e current_state, next_state;

////////////////////////////////////////////////////////
// DEFAULTS
////////////////////////////////////////////////////////
localparam logic [15:0] MB_default_MSG_Info   = 16'h0000;
localparam logic [63:0] MB_default_data_Field = 64'h0;

//

////////////////////////////////////////////////////////
// HANDSHAKE FLAGS + DATA CAPTURE
////////////////////////////////////////////////////////
// When mb_repairval_rx_valid is high, a case on mb_repairval_rx_msg_id:
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

logic repairval_result_local; // our local repair result (latched when partner result_req arrives)
logic partner_result;         // partner's repair result (from rx MsgInfo[0] on result_resp)

logic error_detect;
assign error_detect = !partner_result; // pass = 1, fail = 0


logic [15:0] MB_repairval_result_MSG_Info;
assign MB_repairval_result_MSG_Info = {15'b0, repairval_result_local};

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_req_rcvd          <= 1'b0;
        s1_rsp_rcvd          <= 1'b0;
        s3_req_rcvd          <= 1'b0;
        s3_rsp_rcvd          <= 1'b0;
        s4_req_rcvd          <= 1'b0;
        s4_rsp_rcvd          <= 1'b0;
        repairval_result_local <= 1'b0;
        partner_result         <= 1'b1; // default: assume pass
    end else if (current_state == MB_S0_IDLE) begin
        s1_req_rcvd          <= 1'b0;
        s1_rsp_rcvd          <= 1'b0;
        s3_req_rcvd          <= 1'b0;
        s3_rsp_rcvd          <= 1'b0;
        s4_req_rcvd          <= 1'b0;
        s4_rsp_rcvd          <= 1'b0;
        repairval_result_local <= 1'b0;
        partner_result         <= 1'b1;
    end else if (mb_repairval_rx_valid) begin
        case (mb_repairval_rx_msg_id)
            MBINIT_REPAIRVAL_init_req    : s1_req_rcvd <= 1'b1;
            MBINIT_REPAIRVAL_init_resp   : s1_rsp_rcvd <= 1'b1;
            MBINIT_REPAIRVAL_result_req  : begin
                s3_req_rcvd            <= 1'b1;
                repairval_result_local <= mb_rx_val_pass; // latch our local result
            end
            MBINIT_REPAIRVAL_result_resp : begin
                s3_rsp_rcvd    <= 1'b1;
                partner_result <= mb_repairval_rx_MsgInfo[0]; // partner's pass/fail bit
            end
            MBINIT_REPAIRVAL_done_req    : s4_req_rcvd <= 1'b1;
            MBINIT_REPAIRVAL_done_resp   : s4_rsp_rcvd <= 1'b1;
            default                      : ; // ignore unrelated messages
        endcase
    end
end

////////////////////////////////////////////////////////
// STATE REGISTER
////////////////////////////////////////////////////////
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_state <= MB_S0_IDLE;
    else
        current_state <= next_state;
end

////////////////////////////////////////////////////////
// NEXT STATE
////////////////////////////////////////////////////////
always_comb begin
    next_state = current_state;

    if (!mb_repairval_enable) begin
        next_state = MB_S0_IDLE;
    end
    else if (global_error && !mb_repairval_done) begin
        next_state = MB_S5_ERROR;
    end
    else begin
        case (current_state)

            MB_S0_IDLE: begin
                if (mb_repairval_enable)
                    next_state = MB_S1_READY_REQ_SEND;
            end

            // ── S1 Readiness REQ ──────────────────────────────────────────────
            MB_S1_READY_REQ_SEND: begin
                if (ltsm_rdy)       next_state = MB_S1_READY_REQ_WAIT;
            end
            MB_S1_READY_REQ_WAIT: begin
                if (s1_req_rcvd)    next_state = MB_S1_READY_RSP_SEND;
            end

            // ── S1 Readiness RSP ──────────────────────────────────────────────
            MB_S1_READY_RSP_SEND: begin
                if (ltsm_rdy)       next_state = MB_S1_READY_RSP_WAIT;
            end
            MB_S1_READY_RSP_WAIT: begin
                if (s1_rsp_rcvd)    next_state = MB_S2_PATTERN_TRANSMISSION;
            end

            // ── S2 Pattern ────────────────────────────────────────────────────
            MB_S2_PATTERN_TRANSMISSION: begin
                if (mb_tx_pattern_count_done)
                    next_state = MB_S3_RESULT_REQ_SEND;
            end

            // ── S3 Result REQ ─────────────────────────────────────────────────
            MB_S3_RESULT_REQ_SEND: begin
                if (ltsm_rdy)       next_state = MB_S3_RESULT_REQ_WAIT;
            end
            MB_S3_RESULT_REQ_WAIT: begin
                if (s3_req_rcvd)    next_state = MB_S3_RESULT_RSP_SEND;
            end

            // ── S3 Result RSP ─────────────────────────────────────────────────
            MB_S3_RESULT_RSP_SEND: begin
                if (ltsm_rdy)       next_state = MB_S3_RESULT_RSP_WAIT;
            end
            MB_S3_RESULT_RSP_WAIT: begin
                if (s3_rsp_rcvd)    next_state = MB_S4_ERROR_CHECK;
            end

            // ── S4 Error Check ────────────────────────────────────────────────
            MB_S4_ERROR_CHECK: begin
                if (error_detect) next_state = MB_S5_ERROR;
                else              next_state = MB_S4_FINALIZE_REQ_SEND;
            end

            // ── S4 Finalize REQ ───────────────────────────────────────────────
            MB_S4_FINALIZE_REQ_SEND: begin
                if (ltsm_rdy)       next_state = MB_S4_FINALIZE_REQ_WAIT;
            end
            MB_S4_FINALIZE_REQ_WAIT: begin
                if (s4_req_rcvd)    next_state = MB_S4_FINALIZE_RSP_SEND;
            end

            // ── S4 Finalize RSP ───────────────────────────────────────────────
            MB_S4_FINALIZE_RSP_SEND: begin
                if (ltsm_rdy)       next_state = MB_S4_FINALIZE_RSP_WAIT;
            end
            MB_S4_FINALIZE_RSP_WAIT: begin
                if (s4_rsp_rcvd)    next_state = MB_S6_DONE;
            end

            MB_S5_ERROR: begin
            end

            MB_S6_DONE: begin
            end

            default: next_state = MB_S0_IDLE;
        endcase
    end
end

////////////////////////////////////////////////////////
// TX SB LOGIC (combinational – _SEND states drive the message)
////////////////////////////////////////////////////////
always_comb begin
    mb_repairval_tx_valid      = 1'b0;
    mb_repairval_tx_msg_id     = msg_no_e'(NOTHING);
    mb_repairval_tx_MsgInfo    = MB_default_MSG_Info;
    mb_repairval_tx_data_Field = MB_default_data_Field;

    case (current_state)

        MB_S1_READY_REQ_SEND: begin
            mb_repairval_tx_valid  = 1'b1;
            mb_repairval_tx_msg_id = MBINIT_REPAIRVAL_init_req;
        end

        MB_S1_READY_RSP_SEND: begin
            mb_repairval_tx_valid  = 1'b1;
            mb_repairval_tx_msg_id = MBINIT_REPAIRVAL_init_resp;
        end

        MB_S3_RESULT_REQ_SEND: begin
            mb_repairval_tx_valid  = 1'b1;
            mb_repairval_tx_msg_id = MBINIT_REPAIRVAL_result_req;
        end

        MB_S3_RESULT_RSP_SEND: begin
            mb_repairval_tx_valid   = 1'b1;
            mb_repairval_tx_msg_id  = MBINIT_REPAIRVAL_result_resp;
            mb_repairval_tx_MsgInfo = MB_repairval_result_MSG_Info;
        end

        MB_S4_FINALIZE_REQ_SEND: begin
            mb_repairval_tx_valid  = 1'b1;
            mb_repairval_tx_msg_id = MBINIT_REPAIRVAL_done_req;
        end

        MB_S4_FINALIZE_RSP_SEND: begin
            mb_repairval_tx_valid  = 1'b1;
            mb_repairval_tx_msg_id = MBINIT_REPAIRVAL_done_resp;
        end

        default: begin
            // Do nothing
        end
    endcase
end

////////////////////////////////////////////////////////
// PATTERN ENABLES
////////////////////////////////////////////////////////
always_comb begin
    mb_tx_pattern_en = 1'b0;
    mb_rx_compare_en = 1'b0;
    mb_tx_pattern_setup = 3'b010;
    mb_tx_val_pattern_sel = 1'b0;
    
    mb_rx_compare_setup = 2'b10;
    case (current_state)
        MB_S2_PATTERN_TRANSMISSION: begin
            mb_tx_pattern_en = 1'b1;
            mb_rx_compare_en = 1'b1;
        end
        MB_S3_RESULT_REQ_SEND,
        MB_S3_RESULT_REQ_WAIT: begin
            mb_rx_compare_en = 1'b1;
        end
        default: begin
            mb_tx_pattern_en = 1'b0;
            mb_rx_compare_en = 1'b0;
        end
    endcase
end

////////////////////////////////////////////////////////
// DONE
////////////////////////////////////////////////////////
always_comb begin
    mb_repairval_done = (current_state == MB_S6_DONE);
end

////////////////////////////////////////////////////////
// ERROR LOGIC
////////////////////////////////////////////////////////
always_comb begin
    mb_repairval_error = (current_state == MB_S5_ERROR);
end

////////////////////////////////////////////////////////
// SYSTEMVERILOG ASSERTIONS (SVA) FOR REPAIRVAL
////////////////////////////////////////////////////////
`ifdef SIMULATION
    // 1. Handshake Integrity: No init_resp sent without init_req received first
    property p_tx_start_resp_after_req;
        @(posedge clk) disable iff (!rst_n)
        (mb_repairval_tx_valid && mb_repairval_tx_msg_id == MBINIT_REPAIRVAL_init_resp) |-> s1_req_rcvd;
    endproperty
    assert_tx_start_resp_after_req: assert property(p_tx_start_resp_after_req);

    // 2. Handshake Integrity: No result_resp sent without result_req received first
    property p_tx_degrade_resp_after_req;
        @(posedge clk) disable iff (!rst_n)
        (mb_repairval_tx_valid && mb_repairval_tx_msg_id == MBINIT_REPAIRVAL_result_resp) |-> s3_req_rcvd;
    endproperty
    assert_tx_degrade_resp_after_req: assert property(p_tx_degrade_resp_after_req);

    // 3. Handshake Integrity: No done_resp sent without done_req received first
    property p_tx_end_resp_after_req;
        @(posedge clk) disable iff (!rst_n)
        (mb_repairval_tx_valid && mb_repairval_tx_msg_id == MBINIT_REPAIRVAL_done_resp) |-> s4_req_rcvd;
    endproperty
    assert_tx_end_resp_after_req: assert property(p_tx_end_resp_after_req);

    // 4. Bounded Liveness: init_req must eventually be answered or enter S5 error
    property p_start_req_leads_to_resp_or_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S1_READY_REQ_WAIT) |-> (##[1:2000] (s1_rsp_rcvd || current_state == MB_S5_ERROR));
    endproperty
    assert_start_req_leads_to_resp_or_error: assert property(p_start_req_leads_to_resp_or_error);

    // 5. Bounded Liveness: result_req must eventually be answered or enter S5 error
    property p_degrade_req_leads_to_resp_or_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S3_RESULT_RSP_WAIT) |-> (##[1:2000] (s3_rsp_rcvd || current_state == MB_S5_ERROR));
    endproperty
    assert_degrade_req_leads_to_resp_or_error: assert property(p_degrade_req_leads_to_resp_or_error);

    // 6. Bounded Liveness: done_req must eventually be answered or enter S5 error
    property p_end_req_leads_to_resp_or_error;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S4_FINALIZE_RSP_WAIT) |-> (##[1:2000] (s4_rsp_rcvd || current_state == MB_S5_ERROR));
    endproperty
    assert_end_req_leads_to_resp_or_error: assert property(p_end_req_leads_to_resp_or_error);

    // 7. Protocol Rule: Sideband TX stability until ltsm_rdy asserts
    property p_tx_stability_until_rdy;
        @(posedge clk) disable iff (!rst_n || !mb_repairval_enable)
        (mb_repairval_tx_valid && !ltsm_rdy) |-> 
        ##1 (mb_repairval_tx_valid && 
             $stable(mb_repairval_tx_msg_id) && 
             $stable(mb_repairval_tx_MsgInfo) && 
             $stable(mb_repairval_tx_data_Field));
    endproperty
    assert_tx_stability_until_rdy: assert property(p_tx_stability_until_rdy);

    // 8. Error Check: Error states raise error flag
    property p_error_condition_raises_error;
        @(posedge clk) disable iff (!rst_n)
        (global_error && mb_repairval_enable) ||
        (current_state == MB_S4_ERROR_CHECK && error_detect)
        |-> ##[1:5] (current_state == MB_S5_ERROR && mb_repairval_error == 1'b1);
    endproperty
    assert_error_condition_raises_error: assert property(p_error_condition_raises_error);

    // 9. Success Check: Done state asserts done flag
    property p_success_path_leads_to_done;
        @(posedge clk) disable iff (!rst_n)
        (current_state == MB_S4_FINALIZE_RSP_WAIT && s4_rsp_rcvd && !global_error)
        |-> ##[1:5] (current_state == MB_S6_DONE && mb_repairval_done == 1'b1);
    endproperty
    assert_success_path_leads_to_done: assert property(p_success_path_leads_to_done);

    // 10. Safety Check: Done and Error are mutually exclusive
    assert_never_done_and_error: assert property (
        @(posedge clk) disable iff (!rst_n) 
        !(mb_repairval_done && mb_repairval_error)
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
    cover_state_s4_req_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S4_FINALIZE_REQ_SEND);
    cover_state_s4_req_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S4_FINALIZE_REQ_WAIT);
    cover_state_s4_rsp_send:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S4_FINALIZE_RSP_SEND);
    cover_state_s4_rsp_wait:  cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S4_FINALIZE_RSP_WAIT);
    cover_state_s5_error:     cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S5_ERROR);
    cover_state_s6_done:      cover property (@(posedge clk) disable iff (!rst_n) current_state == MB_S6_DONE);
`endif

endmodule