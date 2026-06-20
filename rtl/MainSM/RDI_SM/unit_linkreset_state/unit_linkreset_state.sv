//-----------------------------------------------------------------------------
// Module      : unit_linkreset_state
// Description : LinkReset State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages transitions out of the LinkReset state 
//               towards either Reset, LinkError, or Disabled.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_linkreset_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter
    input  msg_no_e        message_receive,         // Received message from peer
    input  logic           rst_n,                   // Asynchronous active-low reset

    output RDI_state       next_state,              // Next RDI main state on exit
    output msg_no_e        message_send             // RDI message to send to peer
);

    // -------------------------------------------------------------------------
    // Sub-state enumeration
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        state_disable,   // 0: Initial/Inactive state
        idle,            // 1: Waiting for exit triggers
        reset_st,        // 2: Exit triggered towards Reset (on lp_state_req=Active)
        d_send_req,      // 4: Disable flow (adapter-initiated)
        d_send_resp,     // 5: Disable flow (peer-initiated)
        disabled_st      // 6: Stable Disabled state
    } lr_sub_state;

    lr_sub_state cs; 

    // -------------------------------------------------------------------------
    // Sequential State-Machine logic
    // -------------------------------------------------------------------------
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= state_disable;
            next_state <= Nop;
            message_send <= NOP;
        end else if (!EN) begin
            cs <= state_disable;
            next_state <= Nop;
            message_send <= NOP;
        end else begin
            case (cs)
            state_disable: begin
                if (EN) begin
                    cs <= idle;
                end
                next_state   <= Nop;
                message_send <= NOP;
            end

            idle: begin
                if (lp_state_req == Active) begin
                    cs <= reset_st;
                end
                else if (lp_state_req == Disabled) begin
                    cs           <= d_send_req;
                    message_send <= RDI_DISABLE_REQ;
                end 
                else if (message_receive == RDI_DISABLE_REQ) begin
                    cs           <= d_send_resp;
                    message_send <= RDI_DISABLE_RSP;
                end
            end

            reset_st: begin
                next_state <= Reset;
            end

            d_send_req: begin
                message_send <= NOP;
                if (message_receive == RDI_DISABLE_RSP) begin
                    cs         <= disabled_st;
                    next_state <= Disabled;
                end
            end

            d_send_resp: begin
                message_send <= NOP;
                cs           <= disabled_st;
                next_state   <= Disabled;
            end

            disabled_st: begin
                // Transition handled by EN de-assertion logic
            end

            default: cs <= state_disable;

        endcase
    end
    end
endmodule
