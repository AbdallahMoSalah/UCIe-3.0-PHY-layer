//-----------------------------------------------------------------------------
// Module      : unit_active_state
// Description : Active State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages state transitions and message exchanges 
//               when the link is in the Active state. It handles operations like
//               Retrain, LinkReset, Disable, L1, L2, and Link Errors.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

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
    input LTSM_state_e state_sts,
    
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
            cs <= disable_state;
            flow <= flow0;
            next_state <= Nop;
            stall_req <= 1'b0;
            message_send <= NOP;
            start_1us_timer <= 1'b0;
        end else if (!EN) begin
            cs <= disable_state;
            next_state <= Nop;
            stall_req <= 1'b0;
            message_send <= NOP;
            start_1us_timer <= 1'b0;
        end else begin
            case(cs)
                // --- IDLE STATE ---
                idle: begin
                    if (message_receive== RDI_LINK_ERROR_REQ)begin
                        cs<=le_send_resp; 
                        message_send<=RDI_LINK_ERROR_RSP;
                    end 
                    else if (lp_linkerror)begin
                        cs<=le_send_req; 
                        message_send<=RDI_LINK_ERROR_REQ;
                    end 
                    else if (lp_state_req==Retrain || pl_error || state_sts==PHYRETRAIN)begin
                        flow<=flow0;
                        cs<=stall_handshake;
                        stall_req<=1'b1;
                    end
                    else if (message_receive==RDI_RETRAIN_REQ)begin
                        cs<=stall_handshake;
                        flow<=flow1;
                        stall_req<=1'b1;
                    end
                    else if (lp_state_req==LinkReset)begin
                        cs <=stall_handshake;
                        flow<=flow2;
                        stall_req<=1'b1;
                    end 
                    else if (message_receive==RDI_LINK_RESET_REQ)begin
                        cs <=stall_handshake;
                        flow<=flow3;
                        stall_req<=1'b1;
                    end 
                    else if (lp_state_req==Disabled)begin
                        cs <=stall_handshake;
                        flow<=flow4;
                        stall_req<=1'b1;
                    end 
                    else if (message_receive==RDI_DISABLE_REQ)begin
                        cs <=stall_handshake;
                        flow<=flow5;
                        stall_req<=1'b1;
                    end 
                    else if (lp_state_req==L_1)begin
                        cs <=stall_handshake;
                        flow<=flow6;
                        stall_req<=1'b1;
                    end 
                    else if (message_receive==RDI_L1_REQ)begin
                        cs <=Wait;
                        start_1us_timer<=1'b1;
                        flow<=flow7;
                    end 
                    else if (lp_state_req==L_2)begin
                        cs <=stall_handshake;
                        flow<=flow9;
                        stall_req<=1'b1;
                    end 
                    else if (message_receive==RDI_L2_REQ)begin
                        cs <=Wait;
                        start_1us_timer<=1'b1;
                        flow<=flow8;
                    end 
                end

                stall_handshake: begin
                    stall_req<=1'b0;
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

                Wait: begin

                    if ((lp_state_req==L_1) || (lp_state_req==L_2))begin
                        cs<=stall_handshake;
                        stall_req<=1'b1;
                        start_1us_timer<=1'b0;
                    end 
                    else if (timeout_1us) begin
                        cs<=send_pmnak_resp;
                        message_send<=RDI_PMNAK_RSP;
                        start_1us_timer<=1'b0;
                    end
                end

                send_pmnak_resp: begin
                    cs<=idle;
                    message_send<=NOP;
                end

                le_send_req: begin
                    message_send<=NOP;
                    if (message_receive==RDI_LINK_ERROR_RSP)begin
                        cs<=linkerror;
                        next_state<=LinkError;
                    end
                end
                
                le_send_resp: begin
                    message_send<=NOP;
                    cs<=linkerror;
                    next_state<=LinkError;
                end
                
                linkerror: begin
                    // Transition handled by EN de-assertion logic
                end

                rt_send_req: begin
                    message_send<=NOP;
                    if (message_receive==RDI_RETRAIN_RSP)begin
                        cs<=retrain;
                        next_state<=Retrain;
                    end
                end
                
                rt_send_resp: begin
                    message_send<=NOP;
                    cs<=retrain;
                    next_state<=Retrain;
                end
                
                retrain: begin
                    // Transition handled by EN de-assertion logic
                end

                lr_send_req: begin
                    message_send<=NOP;
                    if (message_receive==RDI_LINK_RESET_RSP)begin
                        cs<=linkreset;
                        next_state<=LinkReset;
                    end
                end
                
                lr_send_resp: begin
                    message_send<=NOP;
                    cs<=linkreset;
                    next_state<=LinkReset;
                end
                
                linkreset: begin
                    // Transition handled by EN de-assertion logic
                end

                d_send_req: begin
                    message_send<=NOP;
                    if (message_receive==RDI_DISABLE_RSP)begin
                        cs<=disabled;
                        next_state<=Disabled;
                    end
                end
                
                d_send_resp: begin
                    message_send<=NOP;
                    cs<=disabled;
                    next_state<=Disabled;
                end
                
                disabled: begin
                    // Transition handled by EN de-assertion logic
                end

                l1_send_req: begin
                    message_send<=NOP;
                    if ((message_receive==RDI_L1_REQ)&&(flow==flow6))begin
                        cs<=l1_receive_resp;
                    end
                    if (message_receive==RDI_PMNAK_RSP)begin
                        cs<=active_pmnak;
                        next_state<=Active_PMNAK;
                    end
                    if (flow==flow7)begin
                        message_send<=RDI_L1_RSP;
                        cs<=l1_send_resp;
                    end
                end
                
                l1_receive_resp: begin
                    if ((message_receive==RDI_L1_RSP)&&(flow==flow6))begin
                        cs<=l1_send_resp;
                        message_send<=RDI_L1_RSP;
                    end
                    if ((message_receive==RDI_L1_RSP)&&(flow==flow7))begin 
                        cs<=l1;
                        next_state<=L_1;
                    end
                end
                
                l1_send_resp: begin
                    message_send<=NOP;
                    if (flow==flow6)begin
                    cs<=l1;
                    next_state<=L_1;
                    end
                    if (flow==flow7)begin
                        cs<=l1_receive_resp;
                    end
                end
                
                l1: begin
                    // Transition handled by EN de-assertion logic
                end

                l2_send_req: begin
                    message_send<=NOP;
                    if ((message_receive==RDI_L2_REQ)&&(flow==flow9))begin
                        cs<=l2_receive_resp;
                    end
                    if (message_receive==RDI_PMNAK_RSP)begin
                        cs<=active_pmnak;
                        next_state<=Active_PMNAK;
                    end
                    if (flow==flow8)begin
                        message_send<=RDI_L2_RSP;
                        cs<=l2_send_resp;
                    end
                end
                
                l2_receive_resp: begin
                    if ((message_receive==RDI_L2_RSP)&&(flow==flow9))begin
                        cs<=l2_send_resp;
                        message_send<=RDI_L2_RSP;
                    end
                    if ((message_receive==RDI_L2_RSP)&&(flow==flow8))begin 
                        cs<=l2;
                        next_state<=L_2;
                    end
                end
                
                l2_send_resp: begin
                    message_send<=NOP;
                    if (flow==flow9)begin
                    cs<=l2;
                    next_state<=L_2;
                    end
                    if (flow==flow8)begin
                        cs<=l2_receive_resp;
                    end
                end
                
                l2: begin
                    // Transition handled by EN de-assertion logic
                end

                active_pmnak: begin
                    // Transition handled by EN de-assertion logic
                end

                disable_state: begin
                    if (EN) begin
                        cs<=idle;
                        next_state<=Active;
                    end
                end
            endcase
        end
    end
endmodule