//-----------------------------------------------------------------------------
// Module      : unit_linkerror_state
// Description : LinkError State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages the transition from the LinkError state 
//               back to Reset.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_linkerror_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  logic           time_16ms,               // 16ms timer elapsed signal
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter
    input  logic           rst_n,                   // Asynchronous active-low reset
    
    output logic           start_timer_16ms,        // Start 16ms timer
    output RDI_state       next_state               // Next RDI main state on exit
);

    // -------------------------------------------------------------------------
    // Sub-state enumeration
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        state_disable,  // 0: Initial/Inactive state
        idle,           // 1: Waiting for exit conditions (lp_linkerror=0, etc)
        reset_st        // 2: Exit triggered; driving next_state=Reset
    } le_sub_state;

    le_sub_state cs; 

    // -------------------------------------------------------------------------
    // Sequential State-Machine logic
    // -------------------------------------------------------------------------
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= state_disable;
            start_timer_16ms <= 1'b0;
            next_state <= Nop;
        end else if (!EN) begin
            cs <= state_disable;
            start_timer_16ms <= 1'b0;
            next_state <= Nop;
        end else begin
            case (cs)
            state_disable: begin
                start_timer_16ms <= 1'b0;
                if (EN) begin
                    cs <= idle;
                    start_timer_16ms <= 1'b1;
                end
                next_state <= Nop;
            end

            idle: begin
                start_timer_16ms <= 1'b1;
                if (!lp_linkerror && (lp_state_req == Active) && time_16ms) begin
                    cs <= reset_st;
                    next_state <= Reset;
                end
            end

            reset_st: begin
                next_state <= Nop;
            end

            default: cs <= state_disable;

        endcase
    end
    end
endmodule
