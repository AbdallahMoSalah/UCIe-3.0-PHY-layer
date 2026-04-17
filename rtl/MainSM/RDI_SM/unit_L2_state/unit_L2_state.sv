//-----------------------------------------------------------------------------
// Module      : unit_L2_state
// Description : L2 State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages all sub-state transitions while the RDI main
//               state machine is in the L2 state. It handles Active re-entry
//               handshakes, LinkError, LinkReset, and Disable escapes.
// 
// Ports:
//   Active_handshake_done - Input: completion from sub-handshake SM
//   EN                    - Input: enable from top-level RDI SM
//   lp_state_req [3:0]    - Input: requested RDI state from Adapter
//   message_receive [3:0] - Input: received RDI message from peer
//   lp_linkerror          - Input: link error flag from Adapter
//   next_state [3:0]      - Output: next main RDI state to top-level SM
//   active_handshake_strt - Output: start signal for Active handshake sub-SM
//   message_send [3:0]    - Output: RDI message to send to peer
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module unit_L2_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter
    input  msg_no_e        message_receive,          // Received message from peer
    input  logic           Active_handshake_done,   // Active handshake sub-SM done flag

    output RDI_state       next_state,              // Next RDI main state on exit
    output logic           active_handshake_strt,   // Start strobe for Active handshake sub-SM
    output msg_no_e        message_send              // RDI message to send to peer
);

    // -------------------------------------------------------------------------
    // Sub-state enumeration
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        state_disables,   // 0: Inactive/Power-down context
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
    } l2_sub_state;

    l2_sub_state cs = state_disables; // Initial assignment for simulation stability

    // -------------------------------------------------------------------------
    // Sequential State-Machine logic
    // -------------------------------------------------------------------------
    always @(posedge lclk) begin
        case (cs)

            // -----------------------------------------------------------------
            // STATE_DISABLES: Initial entry or reset via EN=0
            // -----------------------------------------------------------------
            state_disables: begin
                if (EN) begin
                    cs <= idle;
                end
                // Clear outputs on disable
                active_handshake_strt <= 1'b0;
                message_send          <= NOP;
                next_state            <= Nop;
            end

            // -----------------------------------------------------------------
            // IDLE: Decision node for all escape and re-entry paths
            // -----------------------------------------------------------------
            idle: begin
                // 1. LinkReset Escape (Peer initiated)
                if (message_receive == RDI_LINK_RESET_REQ) begin
                    cs           <= lr_send_resp;
                    message_send <= RDI_LINK_RESET_RSP;

                // 2. LinkReset Escape (Adapter initiated)
                end else if (lp_state_req == LinkReset) begin
                    cs           <= lr_send_req;
                    message_send <= RDI_LINK_RESET_REQ;

                // 3. LinkError Escape (Peer initiated)
                end else if (message_receive == RDI_LINK_ERROR_REQ) begin
                    cs           <= le_send_resp;
                    message_send <= RDI_LINK_ERROR_RSP;

                // 4. LinkError Escape (Adapter initiated)
                end else if (lp_linkerror) begin
                    cs           <= le_send_req;
                    message_send <= RDI_LINK_ERROR_REQ;

                // 5. Disable Escape (Adapter initiated)
                end else if (lp_state_req == Disabled) begin
                    cs           <= d_send_req;
                    message_send <= RDI_DISABLE_REQ;

                // 6. Disable Escape (Peer initiated)
                end else if (message_receive == RDI_DISABLE_REQ) begin
                    cs           <= d_send_resp;
                    message_send <= RDI_DISABLE_RSP;

                // 7. Active Re-entry (Adapter initiated)
                end else if (lp_state_req == Active) begin
                    cs                    <= training;
                    active_handshake_strt <= 1'b1;

                // 8. Active Re-entry (Peer initiated)
                end else if (message_receive == RDI_ACTIVE_REQ) begin
                    cs        <= reset;
                end
            end

            // -----------------------------------------------------------------
            // Handshake and Transient states
            // -----------------------------------------------------------------
            
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
                active_handshake_strt <= 1'b0; // Pulse start
                if (message_receive == RDI_ACTIVE_REQ) begin
                    cs         <= reset;
                    next_state <= Active;
                end
                // Optionally handle Active_handshake_done here if needed by protocol
            end

            // -----------------------------------------------------------------
            // Terminal / Stable states: Remain until EN=0
            // -----------------------------------------------------------------
            reset, linkreset, linkerror, disabled: begin
                if (~EN) begin
                    cs <= state_disables;
                end
            end

            default: cs <= state_disables;
        endcase
    end

endmodule
