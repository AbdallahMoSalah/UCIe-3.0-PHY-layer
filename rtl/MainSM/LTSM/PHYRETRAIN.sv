// =============================================================================
// PHYRETRAIN — UCIe 3.0 §4.5.3.7
// =============================================================================
// Performs the PHY retrain sideband handshake and resolves the retrain
// encoding that selects the MBTRAIN re-entry sub-state.
//
// Retrain encoding is determined by:
//   busy_bit_PHY_RETRAIN, rt_apply_module_0_lane_repair_ctrl_out,
//   mbinit_tx_data_lane_mask (current lane mask), and is_x8.
//
//   busy_bit=0                                       → TXSELFCAL
//   busy_bit=1, rt_apply=0                           → TXSELFCAL
//   busy_bit=1, rt_apply=1, degradation possible     → REPAIR
//   busy_bit=1, rt_apply=1, degradation not possible → SPEEDIDLE
//
// Handshake sequence (§4.5.3.7 / Tables 4-10 to 4-12):
//   PR_REQ_SEND  – drive retrain_start_req until SB FIFO accepts (ltsm_rdy)
//   PR_REQ_WAIT  – wait for partner retrain_start_req; latch partner encoding;
//                  compute resolved encoding via Table 4-12
//   PR_RSP_SEND  – drive retrain_start_resp (resolved enc) until accepted
//   PR_RSP_WAIT  – wait for partner retrain_start_resp
//   PR_DONE      – assert phyretrain_done; hold until enable deasserts
//   PR_ERROR     – global_error received; hold until enable deasserts
//
// resolved_retrain_enc (§4.5.3.7):
//   3'b001 → MBTRAIN.TXSELFCAL   3'b100 → MBTRAIN.REPAIR   3'b010 → MBTRAIN.SPEEDIDLE
// =============================================================================

module PHYRETRAIN
    import UCIe_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // LTSM control
    input  logic        phyretrain_enable,
    output logic        phyretrain_done,
    output logic        phyretrain_error,

    // Runtime Link Test Control fields (latched at PHYRETRAIN entry)
    input  logic        rt_apply_module_0_lane_repair_ctrl_out,
    input  logic [6:0]  module_0_lane_repair_id_ctrl_out,
    // Busy status — set when a runtime link test is in progress
    input  logic        busy_bit_PHY_RETRAIN,
    // Standard Package logical lane-map code (Table 4-9) — the width the last
    // degrade settled at. For standard package, "repairable" (Table 4-11) means
    // this width can be degraded one more step.
    input  logic [2:0]  mbinit_tx_data_lane_mask,
    // x8 mode strap — affects which lane-map codes are considered repairable
    input  logic        is_x8,

    // 8 ms watchdog expired (same role as global_error in MBINIT substates)
    input  logic        global_error,

    // Resolved encoding — persistent output valid through PR_DONE
    // (same value as tx_msginfo[2:0] during PR_RSP_SEND, but held for LTSM use)
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


    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        PR_IDLE,
        PR_REQ_SEND,   // drive retrain_start_req; exit when ltsm_rdy accepts
        PR_REQ_WAIT,   // wait for partner retrain_start_req
        PR_RSP_SEND,   // drive retrain_start_resp; exit when ltsm_rdy accepts
        PR_RSP_WAIT,   // wait for partner retrain_start_resp
        PR_DONE,
        PR_ERROR
    } pr_state_e;

    pr_state_e current_state, next_state;

    // -------------------------------------------------------------------------
    // Local retrain encoding — Table 4-10 / 4-11 (§4.5.3.7)
    //
    // Per §4.5.3.7.1-.4 step 5/1, the encoding reflects the Runtime Link Test
    // CONTROL register (except the Start bit) gated by the Busy status bit. The
    // rule is identical for every entry path (Adapter, PHY framing error, Remote
    // die, LINKSPEED), so PHYRETRAIN never needs to know which trigger fired.
    //
    //   Busy=0                                    → TXSELFCAL  (no active test)
    //   Busy=1, Apply Lane Repair=0               → TXSELFCAL  (No Repair)
    //   Busy=1, Apply Lane Repair=1, repairable   → REPAIR
    //   Busy=1, Apply Lane Repair=1, unrepairable → SPEEDIDLE
    // -------------------------------------------------------------------------
    logic [2:0] local_retrain_enc;
    logic       repair_possible;

    // Standard package "repairable" (Table 4-11) = current width can be degraded
    // one more step (Table 4-9).
    //   is_x8=0 (x16 package): x16 (011) → x8 and lower-x8 (001) → x4 qualify.
    //   is_x8=1 (x8  package): x8  (011) → x4 qualifies; everything else is
    //                           already at the floor or has no map.
    assign repair_possible = is_x8 ? ((mbinit_tx_data_lane_mask == 3'b011)   //  mask 16& x8
                                   || (mbinit_tx_data_lane_mask == 3'b001))  // mask → 8
                                   : ((mbinit_tx_data_lane_mask == 3'b011)); // mask 16 → x16 

    always_comb begin
        if (!busy_bit_PHY_RETRAIN)
            local_retrain_enc = 3'b001;             // TXSELFCAL: link not under test
        else if (!rt_apply_module_0_lane_repair_ctrl_out)
            local_retrain_enc = 3'b001;             // TXSELFCAL: busy, No Repair
        else if (repair_possible)
            local_retrain_enc = 3'b100;             // REPAIR: lane errors, can degrade width
        else
            local_retrain_enc = 3'b010;             // SPEEDIDLE: lane errors, unrepairable
    end

    // -------------------------------------------------------------------------
    // RX capture flags — per-state self-clearing (MBINIT_CAL pattern)
    // -------------------------------------------------------------------------
    logic req_rcvd;
    logic rsp_rcvd;

    logic [2:0] partner_enc_q;
    logic [2:0] resolved_enc_q;
    logic [2:0] partner_rsp_enc_q;  // encoding carried in partner's resp, checked on arrival

    // req_rcvd: sticky through the entire REQ phase so an early partner req
    // received while DUT is still in PR_REQ_SEND (under backpressure) is not
    // lost before the FSM reaches PR_REQ_WAIT.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_rcvd       <= 1'b0;
            partner_enc_q  <= 3'b000;
            resolved_enc_q <= 3'b000;
        end
        else if (rx_sb_msg_valid && rx_sb_msg == PHYRETRAIN_retrain_start_req) begin
            req_rcvd       <= 1'b1;
            partner_enc_q  <= rx_msginfo[2:0];
            resolved_enc_q <= resolve_enc(local_retrain_enc, rx_msginfo[2:0]);
        end
        else if (current_state != PR_REQ_SEND && current_state != PR_REQ_WAIT)
            req_rcvd <= 1'b0;
        else if (current_state == PR_IDLE) begin
            resolved_enc_q <= 3'b000;
            req_rcvd       <= 1'b0;
            partner_enc_q  <= 3'b000;
        end
    end

    // rsp_rcvd: set when partner resp arrives (only after req stage);
    //           clears when leaving PR_RSP_WAIT
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_rcvd          <= 1'b0;
            partner_rsp_enc_q <= 3'b000;
        end
        else if (rx_sb_msg_valid && rx_sb_msg == PHYRETRAIN_retrain_start_resp
                 && current_state > PR_REQ_SEND) begin
            rsp_rcvd          <= 1'b1;
            partner_rsp_enc_q <= rx_msginfo[2:0];
        end
        else if (current_state != PR_RSP_WAIT )
            rsp_rcvd <= 1'b0;
        else if (current_state == PR_IDLE) begin
            partner_rsp_enc_q <= 3'b000;
            rsp_rcvd          <= 1'b0;
        end
    end


    // -------------------------------------------------------------------------
    // Table 4-12: encoding resolution
    //   priority: SPEEDIDLE (010) > REPAIR (100) > TXSELFCAL (001)
    // -------------------------------------------------------------------------
    function automatic logic [2:0] resolve_enc(
        input logic [2:0] a,
        input logic [2:0] b
    );
        if      (a == 3'b010 || b == 3'b010) return 3'b010;  // SPEEDIDLE
        else if (a == 3'b100 || b == 3'b100) return 3'b100;  // REPAIR
        else                                  return 3'b001;  // TXSELFCAL
    endfunction

    // -------------------------------------------------------------------------
    // State register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= PR_IDLE;
        else        current_state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Next-state logic
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = current_state;

        if (!phyretrain_enable) begin
            next_state = PR_IDLE;
        end else if (global_error && current_state != PR_DONE) begin
            next_state = PR_ERROR;
        end else begin
            case (current_state)
                PR_IDLE:     next_state = PR_REQ_SEND;

                PR_REQ_SEND: if (ltsm_rdy)  next_state = PR_REQ_WAIT;

                PR_REQ_WAIT: if (req_rcvd)  next_state = PR_RSP_SEND;

                PR_RSP_SEND: if (ltsm_rdy)  next_state = PR_RSP_WAIT;

                PR_RSP_WAIT: if (rsp_rcvd) begin
                    if (partner_rsp_enc_q != resolved_enc_q)
                        next_state = PR_ERROR;     // encoding mismatch → protocol error
                    else
                        next_state = PR_DONE;
                end

                PR_DONE:  ;  // hold until phyretrain_enable deasserts
                PR_ERROR: ;  // hold until phyretrain_enable deasserts

                default: next_state = PR_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // TX output — combinational, driven only in SEND states
    // -------------------------------------------------------------------------
    always_comb begin
        tx_sb_msg_valid = 1'b0;
        tx_sb_msg       = msg_no_e'(NOTHING);
        tx_msginfo      = 16'h0000;

        case (current_state)
            PR_REQ_SEND: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = PHYRETRAIN_retrain_start_req;
                tx_msginfo      = {13'd0, local_retrain_enc};
            end
            PR_RSP_SEND: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = PHYRETRAIN_retrain_start_resp;
                tx_msginfo      = {13'd0, resolved_enc_q};
            end
            default: ;
        endcase
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    assign phyretrain_done      = (current_state == PR_DONE);
    assign phyretrain_error     = (current_state == PR_ERROR);
    assign resolved_retrain_enc = resolved_enc_q;

    // -------------------------------------------------------------------------
    // SVA Assertions
    // -------------------------------------------------------------------------
`ifdef SIMULATION
    // 1. No resp sent before partner req received
    property p_resp_after_req_rcvd;
        @(posedge clk) disable iff (!rst_n)
        (tx_sb_msg_valid && tx_sb_msg == PHYRETRAIN_retrain_start_resp)
        |-> (partner_enc_q != 3'b000 || resolved_enc_q != 3'b000);
    endproperty
    assert_resp_after_req_rcvd: assert property (p_resp_after_req_rcvd);

    // 2. TX message stable while waiting for ltsm_rdy
    property p_tx_stable_until_rdy;
        @(posedge clk) disable iff (!rst_n || !phyretrain_enable)
        (tx_sb_msg_valid && !ltsm_rdy) |->
        ##1 (tx_sb_msg_valid && $stable(tx_sb_msg) && $stable(tx_msginfo));
    endproperty
    assert_tx_stable_until_rdy: assert property (p_tx_stable_until_rdy);

    // 3. Done and Error mutually exclusive
    assert_done_error_mutex: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(phyretrain_done && (current_state == PR_ERROR))
    );

    // 4. State coverage
    cover_idle:     cover property (@(posedge clk) disable iff (!rst_n) current_state == PR_IDLE);
    cover_req_send: cover property (@(posedge clk) disable iff (!rst_n) current_state == PR_REQ_SEND);
    cover_req_wait: cover property (@(posedge clk) disable iff (!rst_n) current_state == PR_REQ_WAIT);
    cover_rsp_send: cover property (@(posedge clk) disable iff (!rst_n) current_state == PR_RSP_SEND);
    cover_rsp_wait: cover property (@(posedge clk) disable iff (!rst_n) current_state == PR_RSP_WAIT);
    cover_done:     cover property (@(posedge clk) disable iff (!rst_n) current_state == PR_DONE);
    cover_error:    cover property (@(posedge clk) disable iff (!rst_n) current_state == PR_ERROR);
`endif

endmodule
