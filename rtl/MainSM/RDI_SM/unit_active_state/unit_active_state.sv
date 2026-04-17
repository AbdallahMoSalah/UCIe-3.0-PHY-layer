//-----------------------------------------------------------------------------
// Module      : unit_active_state
// Description : Active State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages state transitions and message exchanges 
//               when the link is in the Active state. It handles operations like
//               Retrain, LinkReset, Disable, L1, L2, and Link Errors.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_active_state(
    input logic lclk,                   // Local clock
    input logic lp_linkerror,           // Link error indicator from Adapter
    input msg_no_e message_receive,     // Received message from the other interface
    input logic stall_done,             // Indicator that the stall handshake is complete
    input logic EN,                     // Enable signal for the active state machine
    input RDI_state lp_state_req,       // Requested state from Adapter
    input logic rst_n,                  // Asynchronous active-low reset
    input logic timeout_1us,            // 1us timeout for L1/L2 entry
    input logic pl_error,

    output RDI_state next_state,        // Next main state to transition to
    output logic stall_req,             // Request to stall the interface pipeline
    output logic start_1us_timer,       // Start 1us timer for L1/L2 entry
    output msg_no_e message_send        // Message to send to the other interface
);

    // Sub-states of the Active State Machine
    typedef enum logic [4:0] { idle,
                        le_send_resp,
                        le_send_req,
                        stall_handshake,
                        rt_send_req,
                        rt_send_resp,
                        lr_send_req,
                        lr_send_resp,
                        d_send_req,
                        d_send_resp,
                        l1_send_req,
                        l2_send_req,
                        l1_receive_resp,
                        l2_receive_resp,
                        l1_send_resp,
                        l2_send_resp,
                        l1,
                        l2,
                        linkerror,
                        retrain,
                        linkreset,
                        disabled,
                        Wait,
                        send_pmnak_resp,
                        active_pmnak,
                        disable_state} active_state;

    // Flow states to keep track of the current ongoing protocol handshake scenario
    typedef enum logic [4:0] { flow0, // Retrain Req flow
                         flow1, // Retrain Rsp flow
                         flow2, // Link Reset Req flow
                         flow3, // Link Reset Rsp flow
                         flow4, // Disable Req flow
                         flow5, // Disable Rsp flow
                         flow6, // L1 Req from LP flow
                         flow7, // L1 Req from Adapter flow
                         flow8, // L2 Req from Adapter flow
                         flow9  // L2 Req from LP flow
                       } flow_state;

    // State registers initialization
    active_state cs;
    flow_state flow;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= idle;
            flow <= flow0;
            next_state <= Nop;
            stall_req <= 1'b0;
            message_send <= NOP;
            start_1us_timer <= 1'b0;
        end else begin
            case(cs)
                // --- IDLE STATE ---
                // Wait for state change requests or incoming messages
                // This state handles the primary evaluations of requests
                idle: begin
                    // Check if Link Error request message received from peer
                    if (message_receive== RDI_LINK_ERROR_REQ)begin
                        cs<=le_send_resp; 
                        message_send<=RDI_LINK_ERROR_RSP;
                    end 
                    // Check if Link Error flagged by local Adapter
                    else if (lp_linkerror)begin
                        cs<=le_send_req; 
                        message_send<=RDI_LINK_ERROR_REQ;
                    end 
                    // Check if Adapter requested Retrain state
                    else if (lp_state_req==Retrain || pl_error)begin
                        flow<=flow0;
                        cs<=stall_handshake;
                        stall_req<=1'b1;
                    end
                    // Check if Retrain request message received from peer
                    else if (message_receive==RDI_RETRAIN_REQ)begin
                        cs<=stall_handshake;
                        flow<=flow1;
                        stall_req<=1'b1;
                    end
                    // Check if Adapter requested LinkReset state
                    else if (lp_state_req==LinkReset)begin
                        cs <=stall_handshake;
                        flow<=flow2;
                        stall_req<=1'b1;
                    end 
                    // Check if LinkReset request message received from peer
                    else if (message_receive==RDI_LINK_RESET_REQ)begin
                        cs <=stall_handshake;
                        flow<=flow3;
                        stall_req<=1'b1;
                    end 
                    // Check if Adapter requested Disable state
                    else if (lp_state_req==Disabled)begin
                        cs <=stall_handshake;
                        flow<=flow4;
                        stall_req<=1'b1;
                    end 
                    // Check if Disable request message received from peer
                    else if (message_receive==RDI_DISABLE_REQ)begin
                        cs <=stall_handshake;
                        flow<=flow5;
                        stall_req<=1'b1;
                    end 
                    // Check if Adapter requested L1 power state
                    else if (lp_state_req==L1)begin
                        cs <=stall_handshake;
                        flow<=flow6;
                        stall_req<=1'b1;
                    end 
                    // Check if L1 power request message received from peer
                    else if (message_receive==RDI_L1_REQ)begin
                        cs <=Wait;
                        start_1us_timer<=1'b1;
                        flow<=flow7;
                    end 
                    // Check if Adapter requested L2 power state
                    else if (lp_state_req==L2)begin
                        cs <=stall_handshake;
                        flow<=flow9;
                        stall_req<=1'b1;
                    end 
                    // Check if L2 power request message received from peer
                    else if (message_receive==RDI_L2_REQ)begin
                        cs <=Wait;
                        start_1us_timer<=1'b1;
                        flow<=flow8;
                    end 

                end

                // --- STALL HANDSHAKE ---
                // Ensures pipeline/traffic stall before entering new state message exchanges
                // Branches to the appropriate send_req or send_rsp state based on the current flow
                stall_handshake: begin
                    stall_req<=1'b0;
                    // Proceed only when stall is confirmed complete
                    if (stall_done)begin
                        case(flow)
                            flow0: begin
                                message_send<=RDI_RETRAIN_REQ;
                                cs<=rt_send_req;
                            end
                            flow1: begin
                                message_send<=RDI_RETRAIN_RSP;
                                cs<=rt_send_resp;
                            end
                            flow2: begin
                                message_send<=RDI_LINK_RESET_REQ;
                                cs<=lr_send_req;      
                            end
                            flow3: begin
                                message_send<=RDI_LINK_RESET_RSP;
                                cs<=lr_send_resp;
                            end
                            flow4: begin
                                message_send<=RDI_DISABLE_REQ;
                                cs<=d_send_req;
                            end
                            flow5: begin
                                message_send<=RDI_DISABLE_RSP;
                                cs<=d_send_resp;
                            end
                            flow6: begin
                                message_send<=RDI_L1_REQ;
                                cs<=l1_send_req;
                            end
                            flow7: begin
                                message_send<=RDI_L1_REQ;
                                cs<=l1_send_req;
                            end
                            flow8: begin
                                message_send<=RDI_L2_REQ;
                                cs<=l2_send_req;
                            end
                            flow9: begin
                                message_send<=RDI_L2_REQ;
                                cs<=l2_send_req;
                            end
                        endcase
                    end
                end

                // --- WAIT STATE ---
                // Temporary wait state for L1/L2 requests, expects condition met or stall trigger
                Wait: begin
                    start_1us_timer<=1'b0;
                    // Check if Adapter confirmed L1 or L2 state request
                    if ((lp_state_req==L1) || (lp_state_req==L2))begin
                        cs<=stall_handshake;
                        stall_req<=1'b1;
                    end 
                    // Else if 1us timeout happens, trigger PM NAK response
                    else if (timeout_1us) begin
                        cs<=send_pmnak_resp;
                        message_send<=RDI_PMNAK_RSP;
                    end
                end

                // --- PM NAK TIMEOUT RESPONSE ---
                // Issues a PM NAK response and returns to idle when a timeout occurs
                send_pmnak_resp: begin
                    cs<=idle;
                    message_send<=NOP;
                end


                // --- LINK ERROR HANDSHAKE ---
                // Wait for Link Error Response after sending a Link Error Request
                le_send_req: begin
                    message_send<=NOP;
                    // Check if peer responded to Link Error Request
                    if (message_receive==RDI_LINK_ERROR_RSP)begin
                        cs<=linkerror;
                        next_state<=LinkError;
                    end
                end
                
                // Transition to the linkerror state after sending a Link Error Response
                le_send_resp: begin
                    message_send<=NOP;
                    cs<=linkerror;
                    next_state<=LinkError;
                end
                
                // Stable Link Error state. Exits to disable_state when EN drops
                linkerror: begin
                    // Check if SM enable is deasserted to disable module
                    if (~EN) begin
                        cs<=disable_state;
                        next_state<=Nop;
                    end
                end


                // --- RETRAIN HANDSHAKE ---
                // Wait for Retrain Response after sending a Retrain Request
                rt_send_req: begin
                    message_send<=NOP;
                    // Check if peer responded to Retrain Request
                    if (message_receive==RDI_RETRAIN_RSP)begin
                        cs<=retrain;
                        next_state<=Retrain;
                    end
                end
                
                // Transition to the retrain state after sending a Retrain Response
                rt_send_resp: begin
                    message_send<=NOP;
                    cs<=retrain;
                    next_state<=Retrain;
                end
                
                // Stable Retrain state. Exits to disable_state when EN drops
                retrain: begin
                    // Check if SM enable is deasserted to disable module
                    if (~EN) begin
                        cs<=disable_state;
                        next_state<=Nop;
                    end
                end


                // --- LINK RESET HANDSHAKE ---
                // Wait for Link Reset Response after sending a Link Reset Request
                lr_send_req: begin
                    message_send<=NOP;
                    // Check if peer responded to Link Reset Request
                    if (message_receive==RDI_LINK_RESET_RSP)begin
                        cs<=linkreset;
                        next_state<=LinkReset;
                    end
                end
                
                // Transition to the linkreset state after sending a Link Reset Response
                lr_send_resp: begin
                    message_send<=NOP;
                    cs<=linkreset;
                    next_state<=LinkReset;
                end
                
                // Stable Link Reset state. Exits to disable_state when EN drops
                linkreset: begin
                    // Check if SM enable is deasserted to disable module
                    if (~EN) begin
                        cs<=disable_state;
                        next_state<=Nop;
                    end
                end


                // --- DISABLE HANDSHAKE ---
                // Wait for Disable Response after sending a Disable Request
                d_send_req: begin
                    message_send<=NOP;
                    // Check if peer responded to Disable Request
                    if (message_receive==RDI_DISABLE_RSP)begin
                        cs<=disabled;
                        next_state<=Disabled;
                    end
                end
                
                // Transition to disabled state after sending a Disable Response
                d_send_resp: begin
                    message_send<=NOP;
                    cs<=disabled;
                    next_state<=Disabled;
                end
                
                // Stable Disabled state. Exits to disable_state when EN drops
                disabled: begin
                    // Check if SM enable is deasserted to disable module
                    if (~EN) begin
                        cs<=disable_state;
                        next_state<=Nop;
                    end
                end


                // --- L1 ENTRY HANDSHAKE ---
                // Handle L1 Request phase: wait for L1 Req or PM NAK responses, or send L1 Rsp based on flow
                l1_send_req: begin
                    message_send<=NOP;
                    // Check if L1 Request was received while initiating L1 from adapter side
                    if ((message_receive==RDI_L1_REQ)&&(flow==flow6))begin
                        cs<=l1_receive_resp;
                    end
                    // Check if PM NAK response was received, meaning entry is aborted
                    if (message_receive==RDI_PMNAK_RSP)begin
                        cs<=active_pmnak;
                        next_state<=Active_PMNAK;
                    end
                    // Check if we are responding to a received L1 Request
                    if (flow==flow7)begin
                        message_send<=RDI_L1_RSP;
                        cs<=l1_send_resp;
                    end
                end
                
                // Wait for L1 Response or finalize L1 transition depending on flow source
                l1_receive_resp: begin
                    // Check if L1 Response was received for adapter-initiated L1
                    if ((message_receive==RDI_L1_RSP)&&(flow==flow6))begin
                        cs<=l1_send_resp;
                        message_send<=RDI_L1_RSP;
                    end
                    // Check if L1 Response was received for peer-initiated L1
                    if ((message_receive==RDI_L1_RSP)&&(flow==flow7))begin 
                        cs<=l1;
                        next_state<=L1;
                    end
                end
                
                // Transition to main L1 state depending on the flow completion
                l1_send_resp: begin
                    message_send<=NOP;
                    // If Adapter initiated, transition directly to L1 
                    if (flow==flow6)begin
                    cs<=l1;
                    next_state<=L1;
                    end
                    // If peer initiated, transition to wait for final reception response
                    if (flow==flow7)begin
                        cs<=l1_receive_resp;
                    end
                end
                
                // Stable L1 state. Exits to disable_state when EN drops
                l1: begin
                    // Check if SM enable is deasserted to exit L1 mode
                    if (~EN) begin
                        cs<=disable_state;
                        next_state<=Nop;
                    end
                end


                // --- L2 ENTRY HANDSHAKE ---
                // Handle L2 Request phase: wait for L2 Req or PM NAK responses, or send L2 Rsp based on flow
                l2_send_req: begin
                    message_send<=NOP;
                    // Check if L2 Request was received while initiating L2 from adapter side
                    if ((message_receive==RDI_L2_REQ)&&(flow==flow9))begin
                        cs<=l2_receive_resp;
                    end
                    // Check if PM NAK response was received, meaning entry is aborted
                    if (message_receive==RDI_PMNAK_RSP)begin
                        cs<=active_pmnak;
                        next_state<=Active_PMNAK;
                    end
                    // Check if we are responding to a received L2 Request
                    if (flow==flow8)begin
                        message_send<=RDI_L2_RSP;
                        cs<=l2_send_resp;
                    end
                end
                
                // Wait for L2 Response or finalize L2 transition depending on flow source
                l2_receive_resp: begin
                    // Check if L2 Response was received for adapter-initiated L2
                    if ((message_receive==RDI_L2_RSP)&&(flow==flow9))begin
                        cs<=l2_send_resp;
                        message_send<=RDI_L2_RSP;
                    end
                    // Check if L2 Response was received for peer-initiated L2
                    if ((message_receive==RDI_L2_RSP)&&(flow==flow8))begin 
                        cs<=l2;
                        next_state<=L2;
                    end
                end
                
                // Transition to main L2 state depending on the flow completion
                l2_send_resp: begin
                    message_send<=NOP;
                    // If Adapter initiated, transition directly to L2 
                    if (flow==flow9)begin
                    cs<=l2;
                    next_state<=L2;
                    end
                    // If peer initiated, transition to wait for final reception response
                    if (flow==flow8)begin
                        cs<=l2_receive_resp;
                    end
                end
                
                // Stable L2 state. Exits to disable_state when EN drops
                l2: begin
                    // Check if SM enable is deasserted to exit L2 mode
                    if (~EN) begin
                        cs<=disable_state;
                        next_state<=Nop;
                    end
                end

                // --- ACTIVE PM NAK ---
                // Exits Active PMNAK handling back to disable_state when EN drops
                active_pmnak: begin
                    // Wait until disabled to clear NAK state
                    if (~EN) begin
                        cs<=disable_state;
                        next_state<=Nop;
                    end
                end

                // --- RETURN TO ACTIVE / DISABLE STATE WAIT ---
                // Temporary recovery state. Transitions back to idle when re-enabled (EN)
                disable_state: begin
                    // Re-enter idle loop when SM is re-enabled
                    if (EN) begin
                        cs<=idle;
                        next_state<=Active;
                    end
                end
            endcase
        end
    end
    endmodule