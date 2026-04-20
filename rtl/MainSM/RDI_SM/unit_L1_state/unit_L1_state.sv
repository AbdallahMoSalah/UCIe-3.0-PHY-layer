//-----------------------------------------------------------------------------
// Module      : unit_L1_state
// Description : L1 State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages all sub-state transitions while the RDI main
//               state machine is in the L1 (low power) state.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module unit_L1_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter
    input  msg_no_e        message_receive,          // Received message from peer
    input  logic           Active_handshake_done,   // Active handshake sub-SM done flag
    input  logic           rst_n,                   // Asynchronous active-low reset

    output RDI_state       next_state,              // Next RDI main state on exit
    output logic           active_handshake_strt,   // Start strobe for Active handshake sub-SM
    output msg_no_e        message_send              // RDI message to send to peer
);

    // -------------------------------------------------------------------------
    // Sub-state enumeration
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        state_disables,   // 0: Initial/Inactive entry via EN=0 or reset
        idle,             // 1: Scanning for exit triggers
        lr_send_resp,     // 2: LinkReset flow (peer-initiated)
        lr_send_req,      // 3: LinkReset flow (adapter-initiated)
        le_send_resp,     // 4: LinkError flow (peer-initiated)
        le_send_req,      // 5: LinkError flow (local detect)
        d_send_req,       // 6: Disable flow (adapter-initiated)
        d_send_resp,      // 7: Disable flow (peer-initiated)
        training,         // 8: Active re-entry: waiting for Peer REQ or Done
        reset,            // 9: Active re-entry: finalized, waiting for EN=0
        linkreset,        // 10: Stable LinkReset state, waiting for EN=0
        linkerror,        // 11: Stable LinkError state, waiting for EN=0
        disabled          // 12: Stable Disabled state, waiting for EN=0
    } l1_sub_state;

    l1_sub_state cs; 

    // -------------------------------------------------------------------------
    // Sequential State-Machine logic
    // -------------------------------------------------------------------------
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= state_disables;
            active_handshake_strt <= 1'b0;
            message_send <= NOP;
            next_state <= Nop;
        end else if (!EN) begin
            cs <= state_disables;
            active_handshake_strt <= 1'b0;
            message_send <= NOP;
            next_state <= Nop;
        end else begin
            case (cs)
            state_disables: begin
                if (EN) begin
                    cs <= idle;
                end
            end

            idle: begin
                if (message_receive == RDI_LINK_RESET_REQ) begin
                    cs           <= lr_send_resp;
                    message_send <= RDI_LINK_RESET_RSP;
                end else if (lp_state_req == LinkReset) begin
                    cs           <= lr_send_req;
                    message_send <= RDI_LINK_RESET_REQ;
                end else if (message_receive == RDI_LINK_ERROR_REQ) begin
                    cs           <= le_send_resp;
                    message_send <= RDI_LINK_ERROR_RSP;
                end else if (lp_linkerror) begin
                    cs           <= le_send_req;
                    message_send <= RDI_LINK_ERROR_REQ;
                end else if (lp_state_req == Disabled) begin
                    cs           <= d_send_req;
                    message_send <= RDI_DISABLE_REQ;
                end else if (message_receive == RDI_DISABLE_REQ) begin
                    cs           <= d_send_resp;
                    message_send <= RDI_DISABLE_RSP;
                end else if (lp_state_req == Active) begin
                    cs                    <= training;
                    active_handshake_strt <= 1'b1;
                end else if (message_receive == RDI_ACTIVE_REQ) begin
                    cs        <= reset;
                end
            end

            lr_send_req: begin
                message_send <= NOP;
                if (message_receive == RDI_LINK_RESET_RSP) begin
                    cs         <= linkreset;
                    next_state <= LinkReset;
                end
            end

            lr_send_resp: begin
                message_send <= NOP;
                cs           <= linkreset;
                next_state   <= LinkReset;
            end

            le_send_req: begin
                message_send <= NOP;
                if (message_receive == RDI_LINK_ERROR_RSP)begin
                    cs         <= linkerror;
                    next_state <= LinkError;
                end
            end

            le_send_resp: begin
                message_send <= NOP;
                cs           <= linkerror;
                next_state   <= LinkError;
            end

            d_send_req: begin
                message_send <= NOP;
                if (message_receive == RDI_DISABLE_RSP) begin
                    cs         <= disabled;
                    next_state <= Disabled;
                end
            end

            d_send_resp: begin
                message_send <= NOP;
                cs           <= disabled;
                next_state   <= Disabled;
            end

            training: begin
                active_handshake_strt <= 1'b0; 
                if (message_receive == RDI_ACTIVE_REQ) begin
                    cs         <= reset;
                    next_state <= Active;
                end
            end

            reset, linkreset, linkerror, disabled: begin
                // Transition handled by EN de-assertion logic
            end

            default: cs <= state_disables;
            endcase
        end
    end
endmodule
