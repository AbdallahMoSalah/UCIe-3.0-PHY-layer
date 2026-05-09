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

    output logic mb_tx_pattern_val_en,
    output logic mb_rx_compare_val_en,

    input logic RVLD_L_pass,

    input logic mb_tx_val_pattern_transmission_completed,

    // FIFO ready (write-side handshake)
    input  logic ltsm_rdy,

    // timer interface
    output logic timer_enable,
    input  logic timeout_expired
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

logic [15:0] MB_repairval_result_MSG_Info;
assign MB_repairval_result_MSG_Info = {15'b0, RVLD_L_pass};

////////////////////////////////////////////////////////
// TIMEOUT
////////////////////////////////////////////////////////
logic timeout_error;
assign timer_enable  = mb_repairval_enable && !mb_repairval_done && !mb_repairval_error;
assign timeout_error = timeout_expired     && !mb_repairval_done;

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

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_req_rcvd <= 1'b0;
        s1_rsp_rcvd <= 1'b0;
        s3_req_rcvd <= 1'b0;
        s3_rsp_rcvd <= 1'b0;
        s4_req_rcvd <= 1'b0;
        s4_rsp_rcvd <= 1'b0;
    end else if (current_state == MB_S0_IDLE) begin
        s1_req_rcvd <= 1'b0;
        s1_rsp_rcvd <= 1'b0;
        s3_req_rcvd <= 1'b0;
        s3_rsp_rcvd <= 1'b0;
        s4_req_rcvd <= 1'b0;
        s4_rsp_rcvd <= 1'b0;
    end else if (mb_repairval_rx_valid) begin
        case (mb_repairval_rx_msg_id)
            MBINIT_REPAIRVAL_init_req   : s1_req_rcvd <= 1'b1;
            MBINIT_REPAIRVAL_init_resp  : s1_rsp_rcvd <= 1'b1;
            MBINIT_REPAIRVAL_result_req : s3_req_rcvd <= 1'b1;
            MBINIT_REPAIRVAL_result_resp: s3_rsp_rcvd <= 1'b1;
            MBINIT_REPAIRVAL_done_req   : s4_req_rcvd <= 1'b1;
            MBINIT_REPAIRVAL_done_resp  : s4_rsp_rcvd <= 1'b1;
            default                     : ; // ignore unrelated messages
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
    else if (timeout_error) begin
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
                if (mb_tx_val_pattern_transmission_completed)
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
                if (s3_rsp_rcvd) begin
                    if (!RVLD_L_pass) next_state = MB_S5_ERROR;
                    else              next_state = MB_S4_FINALIZE_REQ_SEND;
                end
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
            mb_repairval_tx_valid      = 1'b0;
            mb_repairval_tx_msg_id     = msg_no_e'(NOTHING);
            mb_repairval_tx_MsgInfo    = MB_default_MSG_Info;
            mb_repairval_tx_data_Field = MB_default_data_Field;
        end
    endcase
end

////////////////////////////////////////////////////////
// PATTERN ENABLES
////////////////////////////////////////////////////////
always_comb begin
    mb_tx_pattern_val_en = 1'b0;
    mb_rx_compare_val_en = 1'b0;
    case (current_state)
        MB_S2_PATTERN_TRANSMISSION: begin
            mb_tx_pattern_val_en = 1'b1;
            mb_rx_compare_val_en = 1'b1;
        end
        MB_S3_RESULT_REQ_SEND,
        MB_S3_RESULT_REQ_WAIT: begin
            mb_rx_compare_val_en = 1'b1;
        end
        default: begin
            mb_tx_pattern_val_en = 1'b0;
            mb_rx_compare_val_en = 1'b0;
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

endmodule