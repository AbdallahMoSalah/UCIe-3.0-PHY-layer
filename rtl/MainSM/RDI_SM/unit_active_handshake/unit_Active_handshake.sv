/**
 * Module: unit_active_handshake
 * Description: Implements the Active Handshake state machine for the UCIe RDI SM.
 * It manages the exchange of requests and responses, handling collision and
 * prioritization scenarios through the track of "flows" (flow0, flow1, flow2).
 */
module unit_active_handshake (
    input  logic lclk,                  // Local clock
    input  logic Active_resp_r,         // Received active response from peer
    input  logic Active_req_r,          // Received active request from peer
    input  logic Active_handshake_strt, // Signal to start the active handshake
    output logic Active_resp_s,         // Sent active response to peer
    output logic Active_req_s,          // Sent active request to peer
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
    
    always @(posedge lclk) begin
        // Latch incoming request
        if (Active_req_r) begin
            req_r <= 1'b1;
        end
    end
    always @(posedge lclk) begin
        case (state)
            IDLE: begin
                if (Active_handshake_strt) begin
                    if (~req_r) begin
                        // Normal start: send our request
                        state <= SEND_REQ;
                    end else begin
                        // Peer beat us to the punch: prioritize sending response
                        state <= SEND_RESP;
                        flow  <= flow2;
                        req_r <= 1'b0;
                    end
                end
            end

            SEND_REQ: begin
                // Automatically proceed to wait for messages after sending req
                state <= CHECK_MSG;
            end

            CHECK_MSG: begin
                // Wait to receive the peer's response or a conflicting request

                if (Active_resp_r && (flow != flow1) && (flow != flow2)) begin
                    // Got peer's req; keep waiting for their resp, update flow
                    state <= CHECK_MSG;
                    flow  <= flow0;
                end

                if (Active_resp_r && (flow == flow2)) begin
                    // Received response in flow2 scenario -> we are done
                    state <= DONE;
                end

                if (Active_resp_r && (flow == flow1)) begin
                    // Received request while in flow1 -> done
                    state <= DONE;
                end

                if (req_r && (flow != flow0)) begin
                    // Conflicting req received -> need to send response
                    state <= SEND_RESP;
                    flow  <= flow1;
                    req_r <= 1'b0;
                end

                if (req_r && (flow == flow0)) begin
                    // Received request in default flow -> need to send response
                    state <= SEND_RESP;
                    req_r <= 1'b0;
                end
            end

            SEND_RESP: begin
                // After sending our response, determine next step based on flow history
                if (flow == flow0) begin
                    state <= DONE;
                end

                if (flow == flow1) begin
                    state <= CHECK_MSG;
                end

                if (flow == flow2) begin
                    // Received our response while finishing flow2 resolution -> send our req
                    state <= SEND_REQ;
                end
            end

            DONE: begin
                // Transition gracefully back to IDLE
                state <= IDLE;
                flow  <= none;
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end

    // Combinational assignments for output signals based entirely on current state
    assign Active_handshake_done = (state == DONE);
    assign Active_req_s          = (state == SEND_REQ);
    assign Active_resp_s         = (state == SEND_RESP);

endmodule