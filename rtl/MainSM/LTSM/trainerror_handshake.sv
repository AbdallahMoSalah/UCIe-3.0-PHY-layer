// =============================================================================
// TRAINERROR_HANDSHAKE — UCIe 3.0 §4.5.3.8
// =============================================================================
// Performs the TRAINERROR entry sideband handshake.
//
// 2-Way Handshake logic:
//   - Starts in `TE_IDLE` until `en` (enable) is asserted (post-RESET/SBINIT).
//   - Transitions to `TE_WAIT_TRIGGER` once `en` is asserted, waiting for trigger.
//   - If triggered locally (`local_error_trigger`): we are the Initiator.
//     * Transitions to `TE_REQ_SEND`, drives `TRAINERROR_Entry_req` until accepted.
//     * Transitions to `TE_RSP_WAIT`, waits for `TRAINERROR_Entry_resp` from partner.
//   - If triggered by partner request (`rx_req_detected`): we are the Responder.
//     * Transitions to `TE_RSP_SEND`, drives `TRAINERROR_Entry_resp` until accepted.
//   - Transition to `TE_DONE` on completion of either path.
//   - If `global_error` (timeout) is asserted while active, transition to `TE_DONE`.
//   - Once in `TE_DONE`, remains there until `en` goes low, transitioning back
//     to `TE_IDLE`.
// =============================================================================

module trainerror_handshake
    import UCIe_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Control
    input  logic        en,
    input  logic        local_error_trigger,
    output logic        done,

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
    // FSM States
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        TE_IDLE,
        TE_WAIT_TRIGGER,
        TE_REQ_SEND,
        TE_RSP_WAIT,
        TE_RSP_SEND,
        TE_DONE
    } te_state_e;

    te_state_e current_state, next_state;

    // -------------------------------------------------------------------------
    // Rx Capture Signals
    // -------------------------------------------------------------------------
    logic rx_req_detected;
    assign rx_req_detected = rx_sb_msg_valid && (rx_sb_msg == TRAINERROR_Entry_req);

    logic rx_resp_detected;
    assign rx_resp_detected = rx_sb_msg_valid && (rx_sb_msg == TRAINERROR_Entry_resp);

    // Sticky flag to track partner's response arrival (to prevent missing fast response)
    logic partner_resp_received;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partner_resp_received <= 1'b0;
        end else if (current_state == TE_IDLE || current_state == TE_WAIT_TRIGGER) begin
            partner_resp_received <= 1'b0;
        end else if (rx_resp_detected) begin
            partner_resp_received <= 1'b1;
        end else if (current_state == TE_DONE) begin
            partner_resp_received <= 1'b0;
        end
    end

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= TE_IDLE;
        else        current_state <= next_state;
    end

    // Next-state logic
    always_comb begin
        next_state = current_state;

        if (!en) begin
            next_state = TE_DONE;
        end else begin
            case (current_state)
                TE_IDLE: begin
                    next_state = TE_WAIT_TRIGGER;
                end

                TE_WAIT_TRIGGER: begin
                    if (local_error_trigger)
                        next_state = TE_REQ_SEND;
                    else if (rx_req_detected)
                        next_state = TE_RSP_SEND;
                end

                TE_REQ_SEND: begin
                    if (ltsm_rdy) begin
                        next_state = TE_RSP_WAIT;
                    end
                end

                TE_RSP_WAIT: begin
                    if (partner_resp_received || rx_resp_detected)
                        next_state = TE_DONE;
                end

                TE_RSP_SEND: begin
                    if (ltsm_rdy) begin
                        next_state = TE_DONE;
                    end
                end

                TE_DONE: begin
                    // stay in TE_DONE until en goes low
                end

                default: next_state = TE_IDLE;
            endcase
        end
    end

    // TX output — combinational, driven only in SEND states
    always_comb begin
        tx_sb_msg_valid = 1'b0;
        tx_sb_msg       = msg_no_e'(NOTHING);
        tx_msginfo      = 16'h0000;

        case (current_state)
            TE_REQ_SEND: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = TRAINERROR_Entry_req;
            end
            TE_RSP_SEND: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = TRAINERROR_Entry_resp;
            end
            default: ;
        endcase
    end

    // Outputs
    assign done = (current_state == TE_DONE);

    // -------------------------------------------------------------------------
    // SVA Assertions
    // -------------------------------------------------------------------------
`ifdef SIMULATION
    // 1. Done and tx_sb_msg_valid mutually exclusive
    assert_done_and_tx_mutex: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(done && tx_sb_msg_valid)
    );

    // 2. TX message stable while waiting for ltsm_rdy
    property p_tx_stable_until_rdy;
        @(posedge clk) disable iff (!rst_n || (current_state == TE_IDLE) || (current_state == TE_WAIT_TRIGGER))
        (tx_sb_msg_valid && !ltsm_rdy) |->
        ##1 (tx_sb_msg_valid && $stable(tx_sb_msg) && $stable(tx_msginfo));
    endproperty
    assert_tx_stable_until_rdy: assert property (p_tx_stable_until_rdy);

    // 3. Global error triggers immediate entry to done
    property p_global_error_to_done;
        @(posedge clk) disable iff (!rst_n)
        (global_error && current_state != TE_DONE && current_state != TE_IDLE) |=> done;
    endproperty
    assert_global_error_to_done: assert property (p_global_error_to_done);
`endif

endmodule
