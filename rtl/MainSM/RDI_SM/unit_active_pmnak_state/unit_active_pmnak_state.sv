//-----------------------------------------------------------------------------
// Module      : unit_active_pmnak_state
// Description : Active PM NAK State Machine for RDI
//               Handles active pipeline stalling, messaging (send/receive), and 
//               main state transitions for LinkError, Disabled, Retrain, LinkReset.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_active_pmnak_state(
    input logic lclk,                   // Local clock
    input logic rst_n,                  // Asynchronous active-low reset
    input logic lp_linkerror,           // Link error indicator from Adapter
    input RDI_state lp_state_req,       // Requested state from Adapter
    input msg_no_e message_receive,     // Received message from the other interface
    input logic stall_done,             // Indicator that the stall handshake is complete
    input logic EN,                     // Enable signal for the state machine
    
    output logic stall_req,             // Request to stall the interface pipeline
    output msg_no_e message_send,       // Message to send to the other interface
    output RDI_state next_state         // Next main state to transition to
);

    // active_pmnak_state enumeration declaring main operational statuses
    typedef enum logic [4:0] { 
        state_disabled,   // Inactive module state
        idle,             // Awaiting new incoming requests or messages
        stall_handshake,  // Coordinating with pipeline stall request logic
        le_send_req,      // Link Error handshake: Sending request
        le_send_resp,     // Link Error handshake: Sending response
        active,           // Loopback / confirm active state
        d_send_req,       // Disable handshake: Sending request
        d_send_resp,      // Disable handshake: Sending response
        rt_send_req,      // Retrain handshake: Sending request
        rt_send_resp,     // Retrain handshake: Sending response
        lr_send_req,      // Link Reset handshake: Sending request
        lr_send_resp,     // Link Reset handshake: Sending response
        linkerror,        // Settled into LinkError
        disabled,         // Settled into Disabled
        retrain,          // Settled into Retrain
        linkreset         // Settled into LinkReset
    } active_pmnak_state;

    // flow_state enumeration to preserve intent across the 'stall_handshake' delay
    typedef enum logic [2:0] { 
        flow0, // Preserves the intent to send Disable Response
        flow1, // Preserves the intent to send Disable Request
        flow2, // Preserves the intent to send Retrain Response
        flow3, // Preserves the intent to send Retrain Request
        flow4, // Preserves the intent to send Link Reset Request
        flow5  // Preserves the intent to send Link Reset Response
    } flow_state;

    // Internal state variables 
    active_pmnak_state cs;
    flow_state flow;

    // Sequential logic for state machine transitions
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= state_disabled;
            flow <= flow0;
            next_state <= Nop;
            stall_req <= 1'b0;
            message_send <= NOP;
        end else begin
            case(cs)
                // --- STATE_DISABLED ---
                // Remains here while disabled. Re-enters 'idle' when EN goes high.
                state_disabled: begin
                    if (EN) begin
                        cs <= idle;
                        next_state <= Active;
                    end
                end

                // --- IDLE ---
                // Scans inputs sequentially. Processes adapter requests or peer messages
                // and sets branching flags accordingly.
                idle: begin
                    if (message_receive == RDI_LINK_ERROR_REQ) begin
                        cs <= le_send_resp;
                        message_send <= RDI_LINK_ERROR_RSP;
                    end else if (lp_linkerror) begin
                        cs <= le_send_req;
                        message_send <= RDI_LINK_ERROR_REQ;
                    end else if (lp_state_req == Active) begin
                        cs <= active;
                        next_state <= Active;
                    end else if (message_receive == RDI_DISABLE_REQ) begin
                        cs <= stall_handshake;
                        flow <= flow0;
                        stall_req <= 1'b1;
                    end else if (lp_state_req == Disabled) begin
                        cs <= stall_handshake;
                        flow <= flow1;
                        stall_req <= 1'b1;
                    end else if (message_receive == RDI_RETRAIN_REQ) begin
                        cs <= stall_handshake;
                        flow <= flow2;
                        stall_req <= 1'b1;
                    end else if (lp_state_req == Retrain) begin
                        cs <= stall_handshake;
                        flow <= flow3;
                        stall_req <= 1'b1;
                    end else if (lp_state_req == LinkReset) begin
                        cs <= stall_handshake;
                        flow <= flow4;
                        stall_req <= 1'b1;
                    end else if (message_receive == RDI_LINK_RESET_REQ) begin
                        cs <= stall_handshake;
                        flow <= flow5;
                        stall_req <= 1'b1;
                    end
                end

                // --- STALL HANDSHAKE ---
                // Blocks until stall_done is asserted, effectively freezing transitions 
                // while the pipeline clears out. Then branches utilizing 'flow_state'.
                stall_handshake: begin
                    stall_req <= 1'b0; // De-assert stall constraint bit for edge detection parity
                    if (stall_done) begin
                        case(flow)
                            flow0: begin
                                message_send <= RDI_DISABLE_RSP;
                                cs <= d_send_resp;
                            end
                            flow1: begin
                                message_send <= RDI_DISABLE_REQ;
                                cs <= d_send_req;
                            end
                            flow2: begin
                                message_send <= RDI_RETRAIN_RSP;
                                cs <= rt_send_resp;
                            end
                            flow3: begin
                                message_send <= RDI_RETRAIN_REQ;
                                cs <= rt_send_req;
                            end
                            flow4: begin
                                message_send <= RDI_LINK_RESET_REQ;
                                cs <= lr_send_req;
                            end
                            flow5: begin
                                message_send <= RDI_LINK_RESET_RSP;
                                cs <= lr_send_resp;
                            end
                        endcase
                    end
                end

                // --- LINK ERROR HANDSHAKE ---
                // Waiting for peer's response to our link error request
                le_send_req: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_ERROR_RSP) begin
                        cs <= linkerror;
                        next_state <= LinkError;
                    end
                end

                // After sending link error response, immediately settle into linkerror state
                le_send_resp: begin
                    message_send <= NOP;
                    cs <= linkerror;
                    next_state <= LinkError;
                end
                
                // End state for LinkError, waits for global state drop (EN=0) to recover
                linkerror: begin
                    if (~EN) begin
                        cs <= state_disabled;
                        next_state <= Nop;
                    end
                end

                // --- ACTIVE LOOPBACK STATE ---
                // Confirmed adapter's state_req == Active, remains until EN drops
                active: begin
                    if (~EN) begin
                        cs <= state_disabled;
                        next_state <= Nop;
                    end
                end

                // --- DISABLE HANDSHAKE ---
                // Waiting for peer's response to our disable request
                d_send_req: begin
                    message_send <= NOP;
                    if (message_receive == RDI_DISABLE_RSP) begin
                        cs <= disabled;
                        next_state <= Disabled;
                    end
                end

                // After sending disable response, immediately settle into disabled state
                d_send_resp: begin
                    message_send <= NOP;
                    cs <= disabled;
                    next_state <= Disabled;
                end

                // End state for Disabled, waits for global state drop (EN=0) to recover
                disabled: begin
                    if (~EN) begin
                        cs <= state_disabled;
                        next_state <= Nop;
                    end
                end

                // --- RETRAIN HANDSHAKE ---
                // Waiting for peer's response to our retrain request
                rt_send_req: begin
                    message_send <= NOP;
                    if (message_receive == RDI_RETRAIN_RSP) begin
                        cs <= retrain;
                        next_state <= Retrain;
                    end
                end

                // After sending retrain response, immediately settle into retrain state
                rt_send_resp: begin
                    message_send <= NOP;
                    cs <= retrain;
                    next_state <= Retrain;
                end

                // End state for Retrain, waits for global state drop (EN=0) to recover
                retrain: begin
                    if (~EN) begin
                        cs <= state_disabled;
                        next_state <= Nop;
                    end
                end

                // --- LINK RESET HANDSHAKE ---
                // Waiting for peer's response to our link reset request
                lr_send_req: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_RESET_RSP) begin
                        cs <= linkreset;
                        next_state <= LinkReset;
                    end
                end

                // After sending link reset response, immediately settle into linkreset state
                lr_send_resp: begin
                    message_send <= NOP;
                    cs <= linkreset;
                    next_state <= LinkReset;
                end

                // End state for Link Reset, waits for global state drop (EN=0) to recover
                linkreset: begin
                    if (~EN) begin
                        cs <= state_disabled;
                        next_state <= Nop;
                    end
                end

            endcase
        end
    end
endmodule