/**
 * Module: unit_active_handshake
 * Description: Implements the Active Handshake state machine for the UCIe RDI SM.
 * It manages the exchange of requests and responses, handling collision and
 * prioritization scenarios through the track of "flows" (flow0, flow1, flow2).
 */
 import UCIe_pkg::*;
module unit_active_handshake (
    input  logic lclk,                  // Local clock
    input  logic pm_exit,
    input  msg_no_e message_receive,          // Received active request from peer
    input  logic Active_handshake_strt, // Signal to start the active handshake
    input logic inband_pres,            // In-band presence signal

    output msg_no_e Active_message_send,          // Sent active request to peer
    output logic Active_handshake_done  // Indicator that handshake has completed
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
    // flow0: Default/Standard flow
    // flow1: We received a request while waiting for our response
    // flow2: We received a peer request before we were even ready to start
    typedef enum logic [1:0] {
        none,
        flow0, 
        flow1,
        flow2
    } flow_t;

    state_t state = IDLE;
    flow_t  flow  = none;
    logic   req_r = 1'b0; // Latches peer requests that arrive during IDLE
    logic rsp_r=1'b0;
    always @(posedge lclk) begin
        // Latch incoming request
        if (message_receive == RDI_ACTIVE_REQ) begin
            req_r <= 1'b1;
        end
        if (message_receive == RDI_ACTIVE_RSP) begin
            rsp_r <= 1'b1;
        end
    end
    always @(posedge lclk) begin
        case (state)
            IDLE: begin
               if (Active_handshake_strt && (~req_r || pm_exit)) begin
                state <=SEND_REQ;
                Active_message_send <= RDI_ACTIVE_REQ;
               end
               else if (Active_handshake_strt && req_r && ~pm_exit) begin
                    state <= SEND_RESP;
                    Active_message_send <= RDI_ACTIVE_RSP;
                    flow  <= flow1;
               end
            end

            SEND_REQ: begin
                Active_message_send <= NOP;
                state <= CHECK_MSG;
            end

            CHECK_MSG: begin
                if (rsp_r && flow != flow1) begin
                    state <=  CHECK_MSG;
                    flow <= flow0;
                    rsp_r<=0;
                end 
                else if (req_r && inband_pres && flow == flow0) begin
                    state <= SEND_RESP;
                    Active_message_send <= RDI_ACTIVE_RSP;
                    req_r<=0;
                end
                else if (req_r && inband_pres && flow != flow0) begin
                    state <= SEND_RESP;
                    Active_message_send <= RDI_ACTIVE_RSP;
                    flow <= flow2;
                    req_r<=0;
                end
                else if (rsp_r && flow == flow1) begin
                    state <=  DONE;
                    rsp_r<=0;
                end
            end

            SEND_RESP: begin
                Active_message_send <= NOP;
                if (flow == flow1) begin
                    state <=  SEND_REQ;
                    Active_message_send <= RDI_ACTIVE_REQ;
                    req_r<=0;
                end
                else if (flow == flow0) begin
                    state <=  DONE;
                end
                else if (flow == flow2 && rsp_r) begin
                    state <=  DONE;
                    rsp_r<=0;
                end
            end

            DONE: begin
                req_r<=1'b0;
                rsp_r<=1'b0;
                Active_message_send <= NOP;
                state <= IDLE;
                flow <= none;
            end

            default: begin
               state <= IDLE;
               flow <= none;
               req_r<=1'b0;
               rsp_r<=1'b0;
            end
        endcase
    end

    // Combinational assignments for output signals based entirely on current state
    assign Active_handshake_done = (state == DONE);

endmodule