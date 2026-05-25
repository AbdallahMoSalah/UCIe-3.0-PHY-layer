//-----------------------------------------------------------------------------
// Module      : unit_active_pmnak_state
// Description : Active PM NAK State Machine for RDI
//               Handles active pipeline stalling, messaging (send/receive), and 
//               main state transitions for LinkError, Disabled, Retrain, LinkReset.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_active_pmnak_state (
    input  logic    lclk,            // Local clock
    input  logic    rst_n,           // Asynchronous active-low reset
    input  logic    lp_linkerror,    // Link error indicator from Adapter
    input  RDI_state lp_state_req,   // Requested state from Adapter
    input  msg_no_e message_receive, // Received message from the other interface
    input  logic    stall_done,      // Indicator that the stall handshake is complete
    input  logic    en,              // Enable signal for the state machine
    
    output logic    stall_req,       // Request to stall the interface pipeline
    output msg_no_e message_send,    // Message to send to the other interface
    output RDI_state next_state      // Next main state to transition to (registered output)
);

    // active_pmnak_state enumeration declaring main operational statuses.
    // One-hot encoding is selected here because high-speed interfaces like UCIe benefit
    // from one-hot state machines on both FPGA and ASIC targets. In FPGAs, register
    // resources are abundant, and one-hot encoding reduces next-state combinational logic
    // depth, helping to achieve timing closure at high clock frequencies.
    typedef enum logic [15:0] { 
        STATE_DISABLED  = 16'h0001,   // Inactive module state
        IDLE            = 16'h0002,   // Awaiting new incoming requests or messages
        STALL_HANDSHAKE = 16'h0004,   // Coordinating with pipeline stall request logic
        LE_SEND_REQ     = 16'h0008,   // Link Error handshake: Sending request
        LE_SEND_RESP    = 16'h0010,   // Link Error handshake: Sending response
        ACTIVE          = 16'h0020,   // Loopback / confirm active state
        D_SEND_REQ      = 16'h0040,   // Disable handshake: Sending request
        D_SEND_RESP     = 16'h0080,   // Disable handshake: Sending response
        RT_SEND_REQ     = 16'h0100,   // Retrain handshake: Sending request
        RT_SEND_RESP    = 16'h0200,   // Retrain handshake: Sending response
        LR_SEND_REQ     = 16'h0400,   // Link Reset handshake: Sending request
        LR_SEND_RESP    = 16'h0800,   // Link Reset handshake: Sending response
        LINK_ERROR      = 16'h1000,   // Settled into LinkError
        DISABLED        = 16'h2000,   // Settled into Disabled
        RETRAIN         = 16'h4000,   // Settled into Retrain
        LINK_RESET      = 16'h8000    // Settled into LinkReset
    } active_pmnak_state;

    // flow_state enumeration to preserve intent across the 'stall_handshake' delay
    typedef enum logic [2:0] { 
        FLOW_DISABLE_RSP,
        FLOW_DISABLE_REQ,
        FLOW_RETRAIN_RSP,
        FLOW_RETRAIN_REQ,
        FLOW_LINK_RESET_REQ,
        FLOW_LINK_RESET_RSP
    } flow_state;

    // Internal state variables 
    active_pmnak_state current_state;
    flow_state         flow;

    // Sequential logic for state machine transitions
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_DISABLED;
            flow          <= FLOW_DISABLE_RSP;
            next_state    <= Nop;
            stall_req     <= 1'b0;
            message_send  <= NOP;
        end else if (!en) begin
            current_state <= STATE_DISABLED;
            flow          <= FLOW_DISABLE_RSP;
            next_state    <= Nop;
            stall_req     <= 1'b0;
            message_send  <= NOP;
        end else begin
            case (current_state)
                // --- STATE_DISABLED ---
                STATE_DISABLED: begin
                    current_state <= IDLE;
                    next_state    <= Active;
                end

                // --- IDLE ---
                IDLE: begin
                    if (message_receive == RDI_LINK_ERROR_REQ) begin
                        current_state <= LE_SEND_RESP;
                        message_send  <= RDI_LINK_ERROR_RSP;
                    end else if (lp_linkerror) begin
                        current_state <= LE_SEND_REQ;
                        message_send  <= RDI_LINK_ERROR_REQ;
                    end else if (lp_state_req == Active) begin
                        current_state <= ACTIVE;
                        next_state    <= Active;
                    end else if (message_receive == RDI_DISABLE_REQ) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_DISABLE_RSP;
                        stall_req     <= 1'b1;
                    end else if (lp_state_req == Disabled) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_DISABLE_REQ;
                        stall_req     <= 1'b1;
                    end else if (message_receive == RDI_RETRAIN_REQ) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_RETRAIN_RSP;
                        stall_req     <= 1'b1;
                    end else if (lp_state_req == Retrain) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_RETRAIN_REQ;
                        stall_req     <= 1'b1;
                    end else if (lp_state_req == LinkReset) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_LINK_RESET_REQ;
                        stall_req     <= 1'b1;
                    end else if (message_receive == RDI_LINK_RESET_REQ) begin
                        current_state <= STALL_HANDSHAKE;
                        flow          <= FLOW_LINK_RESET_RSP;
                        stall_req     <= 1'b1;
                    end
                end

                // --- STALL HANDSHAKE ---
                STALL_HANDSHAKE: begin
                    // De-assert stall_req to create a single-cycle pulse since it was asserted in IDLE
                    stall_req <= 1'b0; 
                    if (stall_done) begin
                        case (flow)
                            FLOW_DISABLE_RSP: begin
                                message_send  <= RDI_DISABLE_RSP;
                                current_state <= D_SEND_RESP;
                            end
                            FLOW_DISABLE_REQ: begin
                                message_send  <= RDI_DISABLE_REQ;
                                current_state <= D_SEND_REQ;
                            end
                            FLOW_RETRAIN_RSP: begin
                                message_send  <= RDI_RETRAIN_RSP;
                                current_state <= RT_SEND_RESP;
                            end
                            FLOW_RETRAIN_REQ: begin
                                message_send  <= RDI_RETRAIN_REQ;
                                current_state <= RT_SEND_REQ;
                            end
                            FLOW_LINK_RESET_REQ: begin
                                message_send  <= RDI_LINK_RESET_REQ;
                                current_state <= LR_SEND_REQ;
                            end
                            FLOW_LINK_RESET_RSP: begin
                                message_send  <= RDI_LINK_RESET_RSP;
                                current_state <= LR_SEND_RESP;
                            end
                            default: begin
                                message_send  <= NOP;
                                current_state <= STALL_HANDSHAKE;
                            end
                        endcase
                    end
                end

                // --- LINK ERROR HANDSHAKE ---
                LE_SEND_REQ: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_ERROR_RSP) begin
                        current_state <= LINK_ERROR;
                        next_state    <= LinkError;
                    end
                end

                LE_SEND_RESP: begin
                    message_send  <= NOP;
                    current_state <= LINK_ERROR;
                    next_state    <= LinkError;
                end
                
                D_SEND_REQ: begin
                    message_send <= NOP;
                    if (message_receive == RDI_DISABLE_RSP) begin
                        current_state <= DISABLED;
                        next_state    <= Disabled;
                    end
                end

                D_SEND_RESP: begin
                    message_send  <= NOP;
                    current_state <= DISABLED;
                    next_state    <= Disabled;
                end

                RT_SEND_REQ: begin
                    message_send <= NOP;
                    if (message_receive == RDI_RETRAIN_RSP) begin
                        current_state <= RETRAIN;
                        next_state    <= Retrain;
                    end
                end

                RT_SEND_RESP: begin
                    message_send  <= NOP;
                    current_state <= RETRAIN;
                    next_state    <= Retrain;
                end

                LR_SEND_REQ: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_RESET_RSP) begin
                        current_state <= LINK_RESET;
                        next_state    <= LinkReset;
                    end
                end

                LR_SEND_RESP: begin
                    message_send  <= NOP;
                    current_state <= LINK_RESET;
                    next_state    <= LinkReset;
                end

                // ==========================================
                // Settled Terminal States
                // ==========================================
                LINK_ERROR: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                    flow <= FLOW_DISABLE_RSP;
                end

                ACTIVE: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                    flow <= FLOW_DISABLE_RSP;
                end

                DISABLED: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                    flow <= FLOW_DISABLE_RSP;
                end

                RETRAIN: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                    flow <= FLOW_DISABLE_RSP;
                end

                LINK_RESET: begin
                    // When en is de-asserted, the outer always block resets current_state to STATE_DISABLED
                    flow <= FLOW_DISABLE_RSP;
                end

                default: begin
                    current_state <= STATE_DISABLED;
                    next_state    <= Nop;
                    stall_req     <= 1'b0;
                    message_send  <= NOP;
                end
            endcase
        end
    end
endmodule