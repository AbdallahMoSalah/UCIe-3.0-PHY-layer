//-----------------------------------------------------------------------------
// Module      : unit_disabled_state
// Description : Disabled State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages transitions out of the Disabled state 
//               towards either Reset or LinkError based on adapter requests 
//               or detected link errors.
// 
// Ports:
//   EN           - Input: Enable from top-level RDI SM
//   lp_linkerror - Input: Link error flag from Adapter
//   lp_state_req - Input: Requested RDI state from Adapter
//   next_state   - Output: Next RDI state to top-level SM
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_disabled_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter

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

    d_sub_state cs = state_disabled; // Initialize for simulation stability

    // -------------------------------------------------------------------------
    // Sequential State-Machine logic
    // -------------------------------------------------------------------------
    always @(posedge lclk) begin
        case (cs)

            // -----------------------------------------------------------------
            // STATE_DISABLED: Waiting for top-level SM to grant context
            // -----------------------------------------------------------------
            state_disabled: begin
                if (EN) begin
                    cs <= idle;
                end
                next_state <= Nop;
            end

            // -----------------------------------------------------------------
            // IDLE: Monitoring transition conditions
            // -----------------------------------------------------------------
            idle: begin
                if (!EN) begin
                    cs <= state_disabled;
                end else if (lp_state_req == Active) begin
                    cs <= reset_st;
                end else if (lp_linkerror) begin
                    cs <= linkerror_st;
                end
            end

            // -----------------------------------------------------------------
            // RESET_ST: Exit path to Reset
            // -----------------------------------------------------------------
            reset_st: begin
                next_state <= Reset;
                if (!EN) begin
                    cs <= state_disabled;
                end
            end

            // -----------------------------------------------------------------
            // LINKERROR_ST: Exit path to LinkError
            // -----------------------------------------------------------------
            linkerror_st: begin
                next_state <= LinkError;
                if (!EN) begin
                    cs <= state_disabled;
                end
            end

            default: cs <= state_disabled;

        endcase
    end

endmodule
