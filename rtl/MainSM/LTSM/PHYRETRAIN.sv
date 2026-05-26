// UCIe 3.0 §4.5.3.7 PHYRETRAIN state.
//
// Pre-entry steps (RDI stall handshake, {LinkMgmt.RDI.Req.Retrain} exchange,
// pl_error for framing-error case) all happen *before* this state — in
// ACTIVE / LINKSPEED — and are not implemented here.
//
// Inside PHYRETRAIN:
//   1. Send {PHYRETRAIN.retrain start req} with local retrain encoding
//      (Table 4-11: 001=TXSELFCAL, 010=SPEEDIDLE, 100=REPAIR) in MsgInfo[2:0].
//   2. Receive partner's {PHYRETRAIN.retrain start req} carrying their encoding.
//   3. Resolve per Table 4-12 priority: SPEEDIDLE > REPAIR > TXSELFCAL.
//   4. Send {PHYRETRAIN.retrain start resp} with the resolved encoding.
//   5. Receive partner's {PHYRETRAIN.retrain start resp}.
//   6. Exit with resolved_retrain_enc valid; top hops to MBTRAIN and uses the
//      encoding to pick the entry substate (TXSELFCAL / SPEEDIDLE / REPAIR).
//
// Local encoding (per §4.5.3.7 Step 5) is sourced by the top from Runtime
// Link Test Control register; passed in as local_retrain_enc.
//
// Race handling: 4 parallel stickies (req_sent / req_rcvd / rsp_sent /
// rsp_rcvd) so messages may arrive in any order without deadlock; same
// shape as the SBINIT Step-8 fix.

module PHYRETRAIN
    import UCIe_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        phyretrain_enable,
    output logic        phyretrain_done,

    // Local retrain encoding (Table 4-11, one of 3'b001/3'b010/3'b100).
    input  logic [2:0]  local_retrain_enc,

    // Resolved encoding (valid while phyretrain_done is high).
    output logic [2:0]  resolved_retrain_enc,

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
        DONE_HOLD
    } pr_state_e;

    pr_state_e current_state, next_state;

    // ---------------- Stickies ----------------
    logic req_sent;
    logic req_rcvd;
    logic rsp_sent;
    logic rsp_rcvd;

    logic [2:0] partner_enc_q;     // partner's encoding captured from req.msginfo
    logic [2:0] resolved_enc_q;    // latched resolved encoding (drives output in DONE_HOLD)

    // Tx-side combinational drives (the state's "I am driving X this cycle").
    logic sending_req;
    logic sending_rsp;

    // ---------------- Sticky updates ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_sent        <= 1'b0;
            req_rcvd        <= 1'b0;
            rsp_sent        <= 1'b0;
            rsp_rcvd        <= 1'b0;
            partner_enc_q   <= 3'b000;
            resolved_enc_q  <= 3'b000;
        end else if (current_state == IDLE) begin
            req_sent        <= 1'b0;
            req_rcvd        <= 1'b0;
            rsp_sent        <= 1'b0;
            rsp_rcvd        <= 1'b0;
            partner_enc_q   <= 3'b000;
            resolved_enc_q  <= 3'b000;
        end else begin
            // TX acceptances
            if (sending_req && ltsm_rdy) req_sent <= 1'b1;
            if (sending_rsp && ltsm_rdy) rsp_sent <= 1'b1;

            // RX captures
            if (rx_sb_msg_valid) begin
                unique case (rx_sb_msg)
                    PHYRETRAIN_retrain_start_req : begin
                        if (!req_rcvd) partner_enc_q <= rx_msginfo[2:0];
                        req_rcvd <= 1'b1;
                    end
                    PHYRETRAIN_retrain_start_resp: begin
                        rsp_rcvd <= 1'b1;
                    end
                    default                       : ;
                endcase
            end

            // Latch the resolved encoding the cycle the partner's req lands;
            // expose it through DONE_HOLD.
            if (rx_sb_msg_valid && (rx_sb_msg == PHYRETRAIN_retrain_start_req) && !req_rcvd) begin
                resolved_enc_q <= resolve_enc(local_retrain_enc, rx_msginfo[2:0]);
            end
        end
    end

    // ---------------- Table 4-12 resolution ----------------
    //   priority: SPEEDIDLE (010) > REPAIR (100) > TXSELFCAL (001)
    function automatic logic [2:0] resolve_enc(input logic [2:0] a, input logic [2:0] b);
        if      (a == 3'b010 || b == 3'b010) return 3'b010; // SPEEDIDLE
        else if (a == 3'b100 || b == 3'b100) return 3'b100; // REPAIR
        else                                  return 3'b001; // TXSELFCAL
    endfunction

    // ---------------- State register ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end

    // ---------------- Next-state ----------------
    always_comb begin
        next_state = current_state;
        if (!phyretrain_enable) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE      : next_state = HANDSHAKE;
                HANDSHAKE : if (req_sent && req_rcvd && rsp_sent && rsp_rcvd)
                                next_state = DONE_HOLD;
                DONE_HOLD : ; // hold
                default   : next_state = IDLE;
            endcase
        end
    end

    // ---------------- TX driver ----------------
    //   priority while HANDSHAKE:
    //     1) drive our req until accepted
    //     2) once partner_req received, drive our resp (with resolved enc) until accepted
    always_comb begin
        tx_sb_msg_valid = 1'b0;
        tx_sb_msg       = msg_no_e'(NOTHING);
        tx_msginfo      = 16'h0000;
        sending_req     = 1'b0;
        sending_rsp     = 1'b0;

        if (current_state == HANDSHAKE) begin
            if (!req_sent) begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = PHYRETRAIN_retrain_start_req;
                tx_msginfo      = {13'd0, local_retrain_enc};
                sending_req     = 1'b1;
            end else if (req_rcvd && !rsp_sent) begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = PHYRETRAIN_retrain_start_resp;
                tx_msginfo      = {13'd0, resolved_enc_q};
                sending_rsp     = 1'b1;
            end
        end
    end

    // ---------------- Outputs ----------------
    assign phyretrain_done      = (current_state == DONE_HOLD);
    assign resolved_retrain_enc = resolved_enc_q;

endmodule
