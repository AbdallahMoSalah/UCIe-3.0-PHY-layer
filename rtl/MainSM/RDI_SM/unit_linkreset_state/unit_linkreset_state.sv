//-----------------------------------------------------------------------------
// Module      : unit_linkreset_state
// Description : LinkReset State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages transitions out of the LinkReset state 
//               towards either Reset, LinkError, or Disabled.
// 
// Ports:
//   EN           - Input: Enable from top-level RDI SM
//   lp_linkerror - Input: Link error flag from Adapter
//   lp_state_req - Input: Requested RDI state from Adapter
//   massage_receive - Input: Received RDI message from peer
//   next_state   - Output: Next RDI state to top-level SM
//   massage_send    - Output: RDI message to send to peer
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_linkreset_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter
    input  msg_no_e        massage_receive,         // Received message from peer

    output RDI_state       next_state,              // Next RDI main state on exit
    output msg_no_e        massage_send             // RDI message to send to peer
);

    // -------------------------------------------------------------------------
    // Sub-state enumeration
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        state_disable,   // 0: Initial/Inactive state
        idle,            // 1: Waiting for exit triggers
        reset_st,        // 2: Exit triggered towards Reset (on lp_state_req=Active)
        linkerror_st,    // 3: Exit triggered towards LinkError
        d_send_req,      // 4: Disable flow (adapter-initiated)
        d_send_resp,     // 5: Disable flow (peer-initiated)
        disabled_st      // 6: Stable Disabled state
    } lr_sub_state;

    lr_sub_state cs = state_disable; // Initialize for simulation stability

    // -------------------------------------------------------------------------
    // Sequential State-Machine logic
    // -------------------------------------------------------------------------
    always @(posedge lclk) begin
        case (cs)

            // -----------------------------------------------------------------
            // STATE_DISABLE: Waiting for top-level SM to grant context
            // -----------------------------------------------------------------
            state_disable: begin
                if (EN) begin
                    cs <= idle;
                end
                next_state   <= Nop;
                massage_send <= NOP;
            end

            // -----------------------------------------------------------------
            // IDLE: Monitoring transition conditions
            // -----------------------------------------------------------------
            idle: begin
                if (!EN) begin
                    cs <= state_disable;
                end 
                // 1. Path to Reset (Adapter requests Active re-entry)
                else if (lp_state_req == Active) begin
                    cs <= reset_st;
                end 
                // 2. Path to LinkError
                else if (lp_linkerror) begin
                    cs <= linkerror_st;
                end 
                // 3. Disable flow (Adapter initiated)
                else if (lp_state_req == Disabled) begin
                    cs           <= d_send_req;
                    massage_send <= RDI_DISABLE_REQ;
                end 
                // 4. Disable flow (Peer initiated)
                else if (massage_receive == RDI_DISABLE_REQ) begin
                    cs           <= d_send_resp;
                    massage_send <= RDI_DISABLE_RSP;
                end
            end

            // -----------------------------------------------------------------
            // RESET_ST: Exit path to Reset (or Active top-level)
            // -----------------------------------------------------------------
            reset_st: begin
                next_state <= Reset;
                if (!EN) begin
                    cs <= state_disable;
                end
            end

            // -----------------------------------------------------------------
            // LINKERROR_ST: Exit path to LinkError
            // -----------------------------------------------------------------
            linkerror_st: begin
                next_state <= LinkError;
                if (!EN) begin
                    cs <= state_disable;
                end
            end

            // -----------------------------------------------------------------
            // D_SEND_REQ: Local initiated disable handshake
            // -----------------------------------------------------------------
            d_send_req: begin
                massage_send <= NOP;
                if (massage_receive == RDI_DISABLE_RSP) begin
                    cs         <= disabled_st;
                    next_state <= Disabled;
                end
            end

            // -----------------------------------------------------------------
            // D_SEND_RESP: Peer initiated disable handshake
            // -----------------------------------------------------------------
            d_send_resp: begin
                massage_send <= NOP;
                cs           <= disabled_st;
                next_state   <= Disabled;
            end

            // -----------------------------------------------------------------
            // DISABLED_ST: Stable state until EN=0
            // -----------------------------------------------------------------
            disabled_st: begin
                if (!EN) begin
                    cs <= state_disable;
                end
            end

            default: cs <= state_disable;

        endcase
    end

endmodule
