//-----------------------------------------------------------------------------
// Module      : unit_retrain_state
// Description : Retrain State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages all sub-state transitions while the RDI main
//               state machine is in the Retrain state. It coordinates the
//               Active re-entry handshake, handles escapes to LinkError, Disabled,
//               and LinkReset, and drives state_req / next_state outputs back to
//               the top-level RDI SM dispatcher.
//
// Inputs  : EN                    - Enable from top-level SM (de-asserted on exit)
//           lp_linkerror          - Link error indicator from Adapter
//           lp_state_req  [3:0]   - Requested RDI state from Adapter
//           message_receive[3:0]  - Received RDI message from peer interface
//           Active_handshake_done - Completion flag from Active-handshake sub-SM
//           state_sta      [3:0]  - Current LTSM stable state from top-level SM
//           pm_exit               - Power-management exit flag from top-level SM
//
//           next_state      [3:0] - Next main RDI state on transition
//           Active_handshake_strt - Start strobe for Active handshake sub-SM
//           message_send    [3:0] - RDI message to send to peer interface
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module unit_retrain_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter
    input  msg_no_e        message_receive,          // Received message from peer
    input  logic           Active_handshake_done,   // Active handshake sub-SM done flag
    input  LTSM_state_e    state_sts,               // Current LTSM stable state (top-level SM)

    output RDI_state       next_state,              // Next RDI main state on exit
    output logic           Active_handshake_strt,   // Start strobe for Active handshake sub-SM
    output msg_no_e        message_send              // RDI message to send to peer
);

    // -------------------------------------------------------------------------
    // Sub-state enumeration
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        state_disabled,   // Inactive; waiting for EN to go high
        idle,             // Retrain active; scanning inputs for exit triggers
        le_req_send,      // LinkError handshake: sending REQ to peer
        le_resp_send,     // LinkError handshake: sending RSP to peer
        lr_req_send,      // LinkReset handshake: sending REQ to peer
        lr_resp_send,     // LinkReset handshake: sending RSP to peer
        d_req_send,       // Disable handshake: sending REQ to peer
        d_resp_send,      // Disable handshake: sending RSP to peer
        active_hs,        // Active re-entry: Active handshake sub-SM running
        nop_rcvd,         // NOP received during LINKINIT; waiting for lp_state_req=Active
        active,           // Active handshake done; wait for EN=0
        linkerror,        // Settled into LinkError; wait for EN=0
        linkreset,        // Settled into LinkReset; wait for EN=0
        disabled          // Settled into Disabled; wait for EN=0
    } retrain_sub_state;

    retrain_sub_state cs = state_disabled; // Initialize for simulation stability

    // -------------------------------------------------------------------------
    // Sequential state-machine
    // -------------------------------------------------------------------------
    always @(posedge lclk) begin
            case (cs)

                // -------------------------------------------------------------
                // STATE_DISABLED
                // Inactive while the top-level SM has not granted Retrain context.
                // Re-enters 'idle' the moment EN is asserted.
                // -------------------------------------------------------------
                state_disabled: begin
                    if (EN) begin
                        cs         <= idle;
                        next_state <= Retrain;   // Advertise Retrain to top-level SM
                    end
                end

                // -------------------------------------------------------------
                // IDLE
                // Main decision hub while the link is retraining.
                // Priority order:
                //   1. LinkError    (lp_linkerror or peer REQ)
                //   2. LinkReset    (peer REQ or lp_state_req)
                //   3. Disable      (peer REQ or lp_state_req)
                //   4. Active done  (Active_handshake_done asserted)
                //   5. NOP received (state_sta==LINKINIT && lp_state_req==Nop)
                //   6. PM exit      (lp_state_req==Active && state_sta==LINKINIT && pm_exit)
                // -------------------------------------------------------------
                idle: begin
                    // ---- LinkError escape (local adapter detects error) ----
                    if (lp_linkerror) begin
                        cs           <= le_req_send;
                        message_send <= RDI_LINK_ERROR_REQ;

                    // ---- LinkError escape (peer sends REQ) ----
                    end else if (message_receive == RDI_LINK_ERROR_REQ) begin
                        cs           <= le_resp_send;
                        message_send <= RDI_LINK_ERROR_RSP;

                    // ---- LinkReset escape: peer initiates ----
                    end else if (message_receive == RDI_LINK_RESET_REQ) begin
                        cs           <= lr_resp_send;
                        message_send <= RDI_LINK_RESET_RSP;

                    // ---- LinkReset escape: local adapter requests ----
                    end else if (lp_state_req == LinkReset) begin
                        cs           <= lr_req_send;
                        message_send <= RDI_LINK_RESET_REQ;

                    // ---- Disable escape: peer initiates ----
                    end else if (message_receive == RDI_DISABLE_REQ) begin
                        cs           <= d_resp_send;
                        message_send <= RDI_DISABLE_RSP;

                    // ---- Disable escape: local adapter requests ----
                    end else if (lp_state_req == Disabled) begin
                        cs           <= d_req_send;
                        message_send <= RDI_DISABLE_REQ;

                    // ---- Active handshake already done ----
                    end else if (Active_handshake_done) begin
                        cs         <= active;
                        next_state <= Active;

                    // ---- NOP received during LINKINIT: wait for adapter to confirm Active ----
                    end else if (state_sts == LINKINIT && lp_state_req == Nop) begin
                        cs <= nop_rcvd;

                    // ---- PM exit: adapter requests Active while LTSM is in LINKINIT ----
                    end else if (lp_state_req == Active && state_sts == LINKINIT) begin
                        cs                    <= active_hs;
                        Active_handshake_strt <= 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // LE_REQ_SEND
                // We sent RDI_LINK_ERROR_REQ; wait for peer's RSP.
                // -------------------------------------------------------------
                le_req_send: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_ERROR_RSP) begin
                        cs         <= linkerror;
                        next_state <= LinkError;
                    end
                end

                // -------------------------------------------------------------
                // LE_RESP_SEND
                // We sent RDI_LINK_ERROR_RSP; immediately settle into linkerror.
                // -------------------------------------------------------------
                le_resp_send: begin
                    message_send <= NOP;
                    cs           <= linkerror;
                    next_state   <= LinkError;
                end

                // -------------------------------------------------------------
                // LR_REQ_SEND
                // We sent RDI_LINK_RESET_REQ; wait for peer's RSP.
                // -------------------------------------------------------------
                lr_req_send: begin
                    message_send <= NOP;
                    if (message_receive == RDI_LINK_RESET_RSP) begin
                        cs         <= linkreset;
                        next_state <= LinkReset;
                    end
                end

                // -------------------------------------------------------------
                // LR_RESP_SEND
                // We sent RDI_LINK_RESET_RSP; immediately settle into linkreset.
                // -------------------------------------------------------------
                lr_resp_send: begin
                    message_send <= NOP;
                    cs           <= linkreset;
                    next_state   <= LinkReset;
                end

                // -------------------------------------------------------------
                // D_REQ_SEND
                // We sent RDI_DISABLE_REQ; wait for peer's RSP.
                // -------------------------------------------------------------
                d_req_send: begin
                    message_send <= NOP;
                    if (message_receive == RDI_DISABLE_RSP) begin
                        cs         <= disabled;
                        next_state <= Disabled;
                    end
                end

                // -------------------------------------------------------------
                // D_RESP_SEND
                // We sent RDI_DISABLE_RSP; immediately settle into disabled.
                // -------------------------------------------------------------
                d_resp_send: begin
                    message_send <= NOP;
                    cs           <= disabled;
                    next_state   <= Disabled;
                end

                // -------------------------------------------------------------
                // ACTIVE_HS
                // Active handshake sub-SM is running; wait for completion.
                // On completion, drive next_state = Active and move to active
                // to let the top-level SM take over.
                // -------------------------------------------------------------
                active_hs: begin
                    if (Active_handshake_done) begin
                        Active_handshake_strt <= 1'b0;  // Pulse; sub-SM latches the enable
                        cs         <= active;
                        next_state <= Active;
                    end
                end
    
                // -------------------------------------------------------------
                // NOP_RCVD
                // NOP received in LINKINIT; wait for adapter to request Active.
                // -------------------------------------------------------------
                nop_rcvd: begin
                    if (lp_state_req == Active) begin
                        cs         <= active_hs;
                        Active_handshake_strt <= 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // ACTIVE
                // Active handshake completed successfully. Remain here until
                // the top-level SM de-asserts EN to reclaim control.
                // -------------------------------------------------------------
                active: begin
                    if (~EN) begin
                        cs         <= state_disabled;
                        next_state <= Nop;
                    end
                end

                // -------------------------------------------------------------
                // LINKERROR
                // Settled into LinkError sub-state. Wait for EN de-assertion.
                // -------------------------------------------------------------
                linkerror: begin
                    if (~EN) begin
                        cs         <= state_disabled;
                        next_state <= Nop;
                    end
                end

                // -------------------------------------------------------------
                // LINKRESET
                // Settled into LinkReset sub-state. Wait for EN de-assertion.
                // -------------------------------------------------------------
                linkreset: begin
                    if (~EN) begin
                        cs         <= state_disabled;
                        next_state <= Nop;
                    end
                end

                // -------------------------------------------------------------
                // DISABLED
                // Settled into Disabled sub-state. Wait for EN de-assertion.
                // -------------------------------------------------------------
                disabled: begin
                    if (~EN) begin
                        cs         <= state_disabled;
                        next_state <= Nop;
                    end
                end

            endcase
        end
endmodule
