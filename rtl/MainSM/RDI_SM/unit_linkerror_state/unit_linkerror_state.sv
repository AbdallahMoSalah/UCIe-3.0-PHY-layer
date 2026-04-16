//-----------------------------------------------------------------------------
// Module      : unit_linkerror_state
// Description : LinkError State Machine for RDI (Raw Data Interface) in UCIe PHY.
//               This module manages the transition from the LinkError state 
//               back to Reset, triggered after a 16ms wait time and 
//               adapter-side ready signals.
// 
// Ports:
//   EN           - Input: Enable from top-level RDI SM
//   lp_linkerror - Input: Link error flag from Adapter
//   time_16ms    - Input: Signal indicating 16ms wait time has elapsed
//   lp_state_req - Input: Requested RDI state from Adapter
//   next_state   - Output: Next RDI state to top-level SM
//-----------------------------------------------------------------------------
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_linkerror_state (
    input  logic           lclk,                    // Local clock
    input  logic           EN,                      // Enable from top-level RDI SM
    input  logic           lp_linkerror,            // Link error flag from Adapter
    input  logic           time_16ms,               // 16ms timer elapsed signal
    input  RDI_state       lp_state_req,            // Requested RDI state from Adapter

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

    le_sub_state cs = state_disable; // Initialize for simulation stability

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
                next_state <= Nop;
            end

            // -----------------------------------------------------------------
            // IDLE: Monitoring transition condition: (time > 16ms && !error && Active req)
            // -----------------------------------------------------------------
            idle: begin
                if (EN == 1'b0) begin
                    cs <= state_disable;
                end else if (!lp_linkerror && (lp_state_req == Active) && time_16ms) begin
                    cs <= reset_st;
                end
            end

            // -----------------------------------------------------------------
            // RESET_ST: Terminal sub-state driving the SM exit to Reset
            // -----------------------------------------------------------------
            reset_st: begin
                next_state <= Reset;
                if (!EN) begin
                    cs <= state_disable;
                end
            end

            default: cs <= state_disable;

        endcase
    end

endmodule
