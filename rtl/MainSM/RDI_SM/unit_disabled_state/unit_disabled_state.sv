//-----------------------------------------------------------------------------
// Module      : unit_disabled_state
// Description : Disabled State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages transitions out of the Disabled state 
//               towards either Reset or LinkError based on adapter requests 
//               or detected link errors.
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_disabled_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter
    input  logic           rst_n,                   // Asynchronous active-low reset

    output RDI_state       next_state               // Next RDI main state on exit
);

    // -------------------------------------------------------------------------
    // Sub-state enumeration
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        state_disabled, // 0: Initial/Inactive state
        idle,           // 1: Waiting for exit triggers (Active req or LinkError)
        reset_st,       // 2: Exit triggered towards Reset
        linkerror_st    // 3: Exit triggered towards LinkError
    } d_sub_state;

    d_sub_state cs; 

    // -------------------------------------------------------------------------
    // Sequential State-Machine logic
    // -------------------------------------------------------------------------
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= state_disabled;
            next_state <= Nop;
        end else if (!EN) begin
            cs <= state_disabled;
            next_state <= Nop;
        end else begin
            case (cs)
            state_disabled: begin
                if (EN) begin
                    cs <= idle;
                end
                next_state <= Nop;
            end

            idle: begin
                if (lp_state_req == Active) begin
                    cs <= reset_st;
                end else if (lp_linkerror) begin
                    cs <= linkerror_st;
                end
            end

            reset_st: begin
                next_state <= Reset;
            end

            linkerror_st: begin
                next_state <= LinkError;
            end

            default: cs <= state_disabled;

        endcase
    end
    end
endmodule
