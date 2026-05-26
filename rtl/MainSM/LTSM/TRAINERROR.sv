// UCIe 3.0 §4.5.3.8 TRAINERROR state.
//
// Transitional state that brings the LTSM back to RESET on fatal / non-fatal
// events.  MB Tx tri-stated / Rx may be disabled — hard-wired by top, not
// here.
//
// Behavior:
//   1. If skip_handshake is set on entry (we came from SBINIT or SB is not
//      yet Active), the SB handshake is bypassed.  Otherwise perform the
//      TRAINERROR Entry handshake:
//        - is_initiator=1: send {TRAINERROR_Entry_req}, wait for
//          {TRAINERROR_Entry_resp}.
//        - any received {TRAINERROR_Entry_req} must be answered with
//          {TRAINERROR_Entry_resp} (symmetric path).
//        - 8 ms watchdog: if it expires before the handshake completes,
//          advance regardless (spec: "If no response is received for 8 ms,
//          the LTSM transitions to TRAINERROR").
//   2. While RDI is in LinkError (rdi_link_error=1) stay in TRAINERROR
//      (per §4.5.3.8 error-escalation rule); advance only when it clears.
//   3. Assert trainerror_done in DONE_HOLD and hold until trainerror_enable
//      drops (top tears us down and goes to RESET).
//
// "Any in-progress sideband packets must finish before entering RESET" is
// the top controller's concern — it should only drop trainerror_enable when
// SB Tx is idle.
//
// Race handling: 4 parallel stickies (req/rsp x sent/rcvd) — same shape as
// PHYRETRAIN / SBINIT Step 8.

module TRAINERROR
    import UCIe_pkg::*;
#(
    parameter int CLK_FRQ_HZ = 800000000
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        trainerror_enable,
    input  logic        is_initiator,     // 1 = we send Entry_req; 0 = passive receiver
    input  logic        skip_handshake,   // 1 = bypass SB exchange (from SBINIT / SB not Active)
    input  logic        rdi_link_error,   // 1 = RDI in LinkError -> hold here

    output logic        trainerror_done,

    // SB TX
    output logic        tx_sb_msg_valid,
    output msg_no_e     tx_sb_msg,
    output logic [15:0] tx_msginfo,
    input  logic        ltsm_rdy,

    // SB RX
    input  logic        rx_sb_msg_valid,
    input  msg_no_e     rx_sb_msg,
    input  logic [15:0] rx_msginfo
);

    // ---------------- FSM ----------------
    typedef enum logic [1:0] {
        IDLE,
        HANDSHAKE,
        LINKERROR_GATE,
        DONE_HOLD
    } te_state_e;

    te_state_e current_state, next_state;

    // ---------------- Stickies ----------------
    logic req_sent;
    logic req_rcvd;
    logic rsp_sent;
    logic rsp_rcvd;

    logic sending_req;   // combinational: driving Entry_req this cycle
    logic sending_rsp;   // combinational: driving Entry_resp this cycle

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_sent <= 1'b0;
            req_rcvd <= 1'b0;
            rsp_sent <= 1'b0;
            rsp_rcvd <= 1'b0;
        end else if (current_state == IDLE) begin
            req_sent <= 1'b0;
            req_rcvd <= 1'b0;
            rsp_sent <= 1'b0;
            rsp_rcvd <= 1'b0;
        end else begin
            if (sending_req && ltsm_rdy) req_sent <= 1'b1;
            if (sending_rsp && ltsm_rdy) rsp_sent <= 1'b1;
            if (rx_sb_msg_valid) begin
                unique case (rx_sb_msg)
                    TRAINERROR_Entry_req : req_rcvd <= 1'b1;
                    TRAINERROR_Entry_resp: rsp_rcvd <= 1'b1;
                    default              : ;
                endcase
            end
        end
    end

    // ---------------- Handshake completion ----------------
    // Initiator path: must have sent req and received rsp.  If a partner
    // req came in concurrently, must also have sent rsp.
    // Receiver path : must have received a partner req and sent our rsp.
    // (No partner traffic at all -> only the 8 ms timeout in the FSM
    // releases us; handshake_complete stays low until then.)
    logic init_done;
    logic recv_done;
    logic handshake_complete;
    assign init_done          = is_initiator && req_sent && rsp_rcvd && (!req_rcvd || rsp_sent);
    assign recv_done          = !is_initiator && req_rcvd && rsp_sent;
    assign handshake_complete = init_done || recv_done;

    // ---------------- 8 ms watchdog ----------------
    logic timer_enable;
    logic timer_expired;
    timeout_counter #(
        .CLK_FRQ_HZ(CLK_FRQ_HZ),
        .TIME_OUT  (8)
    ) handshake_timer (
        .clk            (clk),
        .timeout_rst_n  (rst_n),
        .enable_timeout (timer_enable),
        .timeout_expired(timer_expired)
    );
    assign timer_enable = (current_state == HANDSHAKE);

    // ---------------- State register ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end

    // ---------------- Next-state ----------------
    always_comb begin
        next_state = current_state;
        if (!trainerror_enable) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE          : next_state = skip_handshake ? LINKERROR_GATE : HANDSHAKE;
                HANDSHAKE     : if (handshake_complete || timer_expired)
                                    next_state = LINKERROR_GATE;
                LINKERROR_GATE: if (!rdi_link_error)
                                    next_state = DONE_HOLD;
                DONE_HOLD     : ;
                default       : next_state = IDLE;
            endcase
        end
    end

    // ---------------- Tx driver ----------------
    always_comb begin
        tx_sb_msg_valid = 1'b0;
        tx_sb_msg       = msg_no_e'(NOTHING);
        tx_msginfo      = 16'h0000;
        sending_req     = 1'b0;
        sending_rsp     = 1'b0;

        if (current_state == HANDSHAKE) begin
            if (is_initiator && !req_sent) begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = TRAINERROR_Entry_req;
                sending_req     = 1'b1;
            end else if (req_rcvd && !rsp_sent) begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = TRAINERROR_Entry_resp;
                sending_rsp     = 1'b1;
            end
        end
    end

    assign trainerror_done = (current_state == DONE_HOLD);

endmodule
