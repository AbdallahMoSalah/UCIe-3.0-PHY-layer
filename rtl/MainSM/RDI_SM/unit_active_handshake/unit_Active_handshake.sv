import UCIe_pkg::*;

/**
 * Module: unit_active_handshake
 * Description: Implements the Active Handshake state machine for the UCIe RDI SM.
 * It manages the exchange of requests and responses, handling collision and
 * prioritization scenarios through the track of "flows" (FLOW_0, FLOW_1, FLOW_2).
 */
module unit_active_handshake (
    input  logic    rst_n,
    input  logic    lclk,                  // Local clock
    input  logic    pm_exit,
    input  msg_no_e message_receive,       // Received active request from peer
    input  logic    active_handshake_strt, // Signal to start the active handshake
    input  logic    inband_pres,           // In-band presence signal

    output msg_no_e active_message_send,   // Sent active request to peer
    output logic    active_handshake_done  // Indicator that handshake has completed
);

    // Main FSM states
    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        SEND_REQ  = 3'b001,
        CHECK_MSG = 3'b010,
        SEND_RESP = 3'b011,
        DONE      = 3'b100
    } state_t;

    // Track different message sequence flows during collisions/overlaps
    // FLOW_NONE: Default flow when inactive
    // FLOW_0: Default/Standard flow
    // FLOW_1: We received a request while waiting for our response
    // FLOW_2: We received a peer request before we were even ready to start
    typedef enum logic [1:0] {
        FLOW_NONE,
        FLOW_0,
        FLOW_1,
        FLOW_2
    } flow_t;

    state_t state;
    flow_t  flow;
    logic   req_r; // Latches peer requests that arrive during IDLE
    logic   rsp_r;

    // Main sequential process controlling state transitions, flow tracking,
    // request/response latching, and message transmissions.
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= IDLE;
            flow                <= FLOW_NONE;
            req_r               <= 1'b0;
            rsp_r               <= 1'b0;
            active_message_send <= NOP;
        end else begin
            // Latch incoming active request or response messages
            if (message_receive == RDI_ACTIVE_REQ) begin
                req_r <= 1'b1;
            end
            if (message_receive == RDI_ACTIVE_RSP) begin
                rsp_r <= 1'b1;
            end

            case (state)
                IDLE: begin
                    if (active_handshake_strt && (~req_r || pm_exit)) begin
                        state               <= SEND_REQ;
                        active_message_send <= RDI_ACTIVE_REQ;
                    end else if (active_handshake_strt && req_r && ~pm_exit) begin
                        state               <= SEND_RESP;
                        active_message_send <= RDI_ACTIVE_RSP;
                        flow                <= FLOW_1;
                    end
                end

                SEND_REQ: begin
                    active_message_send <= NOP;
                    state               <= CHECK_MSG;
                end

                CHECK_MSG: begin
                    // Condition: Peer response is received while not in overlap flow (FLOW_1).
                    // Flow: Belongs to FLOW_0.
                    if (rsp_r && flow != FLOW_1) begin
                        state <= CHECK_MSG;
                        flow  <= FLOW_0;
                        rsp_r <= 1'b0;
                    end
                    // Condition: Peer request is received during the standard flow.
                    // Flow: Belongs to FLOW_0.
                    else if (req_r && inband_pres && flow == FLOW_0) begin
                        state               <= SEND_RESP;
                        active_message_send <= RDI_ACTIVE_RSP;
                        req_r               <= 1'b0;
                    end
                    // Condition: Peer request is received during non-standard flow (collision/overlap).
                    // Flow: Belongs to FLOW_2.
                    else if (req_r && inband_pres && flow != FLOW_0) begin
                        state               <= SEND_RESP;
                        active_message_send <= RDI_ACTIVE_RSP;
                        flow                <= FLOW_2;
                        req_r               <= 1'b0;
                    end
                    // Condition: Peer response is received under FLOW_1.
                    // Flow: Belongs to FLOW_1.
                    else if (rsp_r && flow == FLOW_1) begin
                        state <= DONE;
                        rsp_r <= 1'b0;
                    end
                end

                SEND_RESP: begin
                    if (flow == FLOW_1) begin
                        state               <= SEND_REQ;
                        active_message_send <= RDI_ACTIVE_REQ;
                        req_r               <= 1'b0;
                    end else if (flow == FLOW_0) begin
                        state               <= DONE;
                        active_message_send <= NOP;
                    end else if (flow == FLOW_2 && rsp_r) begin
                        state               <= DONE;
                        active_message_send <= NOP;
                        rsp_r               <= 1'b0;
                    end else begin
                        active_message_send <= NOP;
                    end
                end

                // Clears all latches before returning to IDLE state
                DONE: begin
                    req_r               <= 1'b0;
                    rsp_r               <= 1'b0;
                    active_message_send <= NOP;
                    state               <= IDLE;
                    flow                <= FLOW_NONE;
                end

                default: begin
                    state               <= IDLE;
                    flow                <= FLOW_NONE;
                    req_r               <= 1'b0;
                    rsp_r               <= 1'b0;
                    active_message_send <= NOP;
                end
            endcase
        end
    end

    // Combinational assignments for output signals based entirely on current state
    assign active_handshake_done = (state == DONE);

endmodule
