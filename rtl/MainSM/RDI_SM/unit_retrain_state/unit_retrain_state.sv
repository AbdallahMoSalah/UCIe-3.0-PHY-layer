//-----------------------------------------------------------------------------
// Module      : unit_retrain_state
// Description : Retrain State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages all sub-state transitions while the RDI main
//               state machine is in the Retrain state.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module unit_retrain_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter
    input  msg_no_e        message_receive,         // Received message from peer
    input  logic           Active_handshake_done,   // Active handshake sub-SM done flag
    input  LTSM_state_e    state_sts,               // Current LTSM stable state (top-level SM)
    input  logic           rst_n,                   // Asynchronous active-low reset
    input  logic           pm_exit,                 // pm exit

    output RDI_state       next_state,              // Next RDI main state on exit
    output logic           Active_handshake_strt,   // Start strobe for Active handshake sub-SM
    output msg_no_e        message_send             // RDI message to send to peer
);

    // -------------------------------------------------------------------------
    // Sub-state enumeration
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        state_disabled,   // Inactive; waiting for EN to go high
        idle,             // Retrain active; scanning inputs for exit triggers
        lr_req_send,      // LinkReset handshake: sending REQ to peer
        lr_resp_send,     // LinkReset handshake: sending RSP to peer
        d_req_send,       // Disable handshake: sending REQ to peer
        d_resp_send,      // Disable handshake: sending RSP to peer
        active_hs,        // Active re-entry: Active handshake sub-SM running
        nop_rcvd,         // NOP received during LINKINIT; waiting for lp_state_req=Active
        active,           // Active handshake done; wait for EN=0
        linkreset,        // Settled into LinkReset; wait for EN=0
        disabled          // Settled into Disabled; wait for EN=0
    } retrain_sub_state;

    retrain_sub_state cs; 

    // -------------------------------------------------------------------------
    // Sequential state-machine
    // -------------------------------------------------------------------------
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= state_disabled;
            next_state <= Nop;
            Active_handshake_strt <= 1'b0;
            message_send <= NOP;
        end else if (!EN) begin
            cs <= state_disabled;
            next_state <= Nop;
            Active_handshake_strt <= 1'b0;
            message_send <= NOP;
        end else begin
            case (cs)
                // -------------------------------------------------------------
                // STATE_DISABLED
                // -------------------------------------------------------------
                state_disabled: begin
                    if (EN) begin
                        cs         <= idle;
                        next_state <= Retrain;   
                    end
                end

                // -------------------------------------------------------------
                // IDLE
                // -------------------------------------------------------------
                idle: begin
                    if (message_receive == RDI_LINK_RESET_REQ) begin
                        cs           <= lr_resp_send;
                        message_send <= RDI_LINK_RESET_RSP;
                    end else if (lp_state_req == LinkReset) begin
                        cs           <= lr_req_send;
                        message_send <= RDI_LINK_RESET_REQ;
                    end else if (message_receive == RDI_DISABLE_REQ) begin
                        cs           <= d_resp_send;
                        message_send <= RDI_DISABLE_RSP;
                    end else if (lp_state_req == Disabled) begin
                        cs           <= d_req_send;
                        message_send <= RDI_DISABLE_REQ;
                    end else if (Active_handshake_done) begin
                        cs         <= active;
                        next_state <= Active;
                    end else if (state_sts == LINKINIT && lp_state_req == Nop) begin
                        cs <= nop_rcvd;
                    end else if (lp_state_req == Active) begin
                        cs                    <= active_hs;
                        Active_handshake_strt <= 1'b1;
                    end
                end

                lr_req_send: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_RESET_RSP) begin
                        cs         <= linkreset;
                        next_state <= LinkReset;
                    end
                end

                lr_resp_send: begin
                    message_send <= NOP;
                    cs           <= linkreset;
                    next_state   <= LinkReset;
                end

                d_req_send: begin
                    message_send <= NOP;
                    if (message_receive == RDI_DISABLE_RSP) begin
                        cs         <= disabled;
                        next_state <= Disabled;
                    end
                end

                d_resp_send: begin
                    message_send <= NOP;
                    cs           <= disabled;
                    next_state   <= Disabled;
                end

                active_hs: begin
                    if (Active_handshake_done) begin
                        Active_handshake_strt <= 1'b0;  
                        cs         <= active;
                        next_state <= Active;
                    end
                end
    
                nop_rcvd: begin
                    if (lp_state_req == Active) begin
                        cs         <= active_hs;
                        Active_handshake_strt <= 1'b1;
                    end
                end

                active, linkreset, disabled: begin
                    // Transition handled by EN de-assertion logic
                end

                default: cs <= state_disabled;
            endcase
        end
    end
endmodule
