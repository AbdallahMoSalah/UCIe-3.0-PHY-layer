//-----------------------------------------------------------------------------
// Module      : message_timeout_handler
// Description : Combined 8 ms sideband-message timeout watcher + Link-Error
//               handshake engine for the RDI state machine (UCIe 3.0, §10, p.124:
//               "Physical Layer sideband handshakes for RDI state transitions with
//               remote Link partner also timeout after 8 ms").
//
//               The block has three error sources, all funnelled into a single
//               `error` line to the main controller:
//                 1. TIMEOUT  : an outgoing sideband request (*_REQ on the message
//                               MUX output) is not answered by a matching *_RSP
//                               within 8 ms.                          (initiator)
//                 2. LP_LINKERROR : the Adapter raises lp_linkerror. (initiator)
//                 3. PEER_REQ : the remote partner sends RDI_LINK_ERROR_REQ.
//                                                                     (responder)
//
//               Handshake protocol with the main controller:
//                 - block asserts `error`
//                 - controller replies with `start_linkerror_handshake` and flips
//                   the message MUX to this block (le_mux_sel, driven by ctrl)
//                 - on start: initiator sends RDI_LINK_ERROR_REQ and restarts the
//                   8 ms timer; responder sends RDI_LINK_ERROR_RSP (no timer)
//                 - block asserts `handshake_done` on RDI_LINK_ERROR_RSP receipt,
//                   or (initiator only) on a second 8 ms timeout
//                 - controller then disables all states and enables LinkError
//
//               Collision rule: if a peer RDI_LINK_ERROR_REQ and an initiator
//               trigger occur together, the responder role wins.
//-----------------------------------------------------------------------------
import UCIe_pkg::*;

module message_timeout_handler #(
    // 8 ms residency at the default 2 GHz lclk = 16,000,000 cycles.
    // Overridable so testbenches can shorten the timeout.
    parameter int TIMEOUT_CYCLES = 16_000_000
) (
    input  logic    lclk,
    input  logic    rst_n,

    // Monitor taps
    input  msg_no_e message_send,               // MUX output: actual outgoing SB message
    input  msg_no_e message_receive,            // incoming SB message
    input  logic    lp_linkerror,               // Adapter-initiated link error
    input  logic    monitor_en,                 // gate: high except while RDI is in LinkError

    // Controller handshake
    input  logic    start_linkerror_handshake,  // from controller
    output logic    error,                      // to controller
    output logic    handshake_done,             // to controller
    output logic    sb_msg_timeout,

    // Message driven onto the MUX while the block owns it (le_mux_sel from ctrl)
    output msg_no_e le_message_send
);

    // -------------------------------------------------------------------------
    // Message classification helpers
    // -------------------------------------------------------------------------
    function automatic logic is_req(input msg_no_e m);
        is_req = (m == RDI_LINK_ERROR_REQ) || (m == RDI_DISABLE_REQ)    ||
                 (m == RDI_LINK_RESET_REQ) || (m == RDI_RETRAIN_REQ)    ||
                 (m == RDI_L1_REQ)         || (m == RDI_L2_REQ)         ||
                 (m == RDI_ACTIVE_REQ);
    endfunction

    function automatic logic is_rsp(input msg_no_e m);
        is_rsp = (m == RDI_LINK_ERROR_RSP) || (m == RDI_DISABLE_RSP)    ||
                 (m == RDI_LINK_RESET_RSP) || (m == RDI_RETRAIN_RSP)    ||
                 (m == RDI_L1_RSP)         || (m == RDI_L2_RSP)         ||
                 (m == RDI_ACTIVE_RSP)     || (m == RDI_PMNAK_RSP);
    endfunction

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] { MONITOR, ERR_WAIT, LE_REQ_WAIT, DONE } state_t;
    state_t state;

    // Latched role at the moment `error` is raised.
    typedef enum logic { INITIATOR, RESPONDER } role_t;
    role_t role;

    // 8 ms timer
    logic [31:0] cnt;
    logic        timer_active;
    msg_no_e     msg_send_prev;

    // A new, distinct outgoing request was issued this cycle (edge-detected so a
    // request held across several cycles only (re)arms the timer once).
    wire req_event = is_req(message_send) && (message_send != msg_send_prev);
    // Timer has expired while running.
    assign sb_msg_timeout   = timer_active && (cnt == 0);

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= MONITOR;
            role            <= INITIATOR;
            cnt             <= TIMEOUT_CYCLES;
            timer_active    <= 1'b0;
            msg_send_prev   <= NOP;
            le_message_send <= NOP;
        end else begin
            msg_send_prev <= message_send;

            case (state)
                // -------------------------------------------------------------
                // MONITOR: watch outgoing *_REQ vs incoming *_RSP and detect the
                // three error sources.
                // -------------------------------------------------------------
                MONITOR: begin
                    le_message_send <= NOP;

                    // --- timer bookkeeping (initiator monitoring) ---
                    if (!monitor_en) begin
                        timer_active <= 1'b0;
                        cnt          <= TIMEOUT_CYCLES;
                    end else if (is_rsp(message_receive)) begin
                        // Outstanding handshake answered -> disarm.
                        timer_active <= 1'b0;
                        cnt          <= TIMEOUT_CYCLES;
                    end else if (req_event) begin
                        // New request issued -> (re)arm.
                        timer_active <= 1'b1;
                        cnt          <= TIMEOUT_CYCLES;
                    end else if (timer_active && cnt != 0) begin
                        cnt <= cnt - 1;
                    end

                    // --- error-source detection (responder wins collisions) ---
                    if (monitor_en) begin
                        if (message_receive == RDI_LINK_ERROR_REQ) begin
                            role         <= RESPONDER;
                            state        <= ERR_WAIT;
                            timer_active <= 1'b0;
                            cnt          <= TIMEOUT_CYCLES;
                        end else if (sb_msg_timeout || lp_linkerror) begin
                            role         <= INITIATOR;
                            state        <= ERR_WAIT;
                            timer_active <= 1'b0;
                            cnt          <= TIMEOUT_CYCLES;
                        end
                    end
                end

                // -------------------------------------------------------------
                // ERR_WAIT: hold `error`, wait for the controller to start the
                // link-error handshake and hand the MUX over.
                // -------------------------------------------------------------
                ERR_WAIT: begin
                    if (start_linkerror_handshake) begin
                        if (role == RESPONDER) begin
                            le_message_send <= RDI_LINK_ERROR_RSP;
                            state           <= DONE;            // no timer
                        end else begin
                            le_message_send <= RDI_LINK_ERROR_REQ;
                            timer_active    <= 1'b1;            // restart 8 ms timer
                            cnt             <= TIMEOUT_CYCLES;
                            state           <= LE_REQ_WAIT;
                        end
                    end
                end

                // -------------------------------------------------------------
                // LE_REQ_WAIT (initiator): wait for RDI_LINK_ERROR_RSP or a second
                // 8 ms timeout, then declare the handshake done either way.
                // -------------------------------------------------------------
                LE_REQ_WAIT: begin
                    le_message_send <= NOP;                    // REQ was a 1-cycle pulse
                    if (message_receive == RDI_LINK_ERROR_RSP) begin
                        timer_active <= 1'b0;
                        cnt          <= TIMEOUT_CYCLES;
                        state        <= DONE;
                    end else if (sb_msg_timeout) begin
                        timer_active <= 1'b0;
                        cnt          <= TIMEOUT_CYCLES;
                        state        <= DONE;
                    end else if (timer_active && cnt != 0) begin
                        cnt <= cnt - 1;
                    end
                end

                // -------------------------------------------------------------
                // DONE: hold `handshake_done` until the controller drops
                // start_linkerror_handshake, then return to monitoring.
                // -------------------------------------------------------------
                DONE: begin
                    le_message_send <= NOP;
                    if (!start_linkerror_handshake) begin
                        state <= MONITOR;
                    end
                end

                default: state <= MONITOR;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Combinational status outputs
    // -------------------------------------------------------------------------
    assign error          = (state == ERR_WAIT);
    assign handshake_done = (state == DONE);

endmodule
