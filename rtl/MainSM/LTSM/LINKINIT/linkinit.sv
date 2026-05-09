//==============================================================================
// Module: linkinit
// Description: Implements the Link Initialization State Machine (LTSM) for UCIe.
//              Handles the transition from idle to active state via RDI status,
//              with timeout and error handling.
//==============================================================================
import RDI_SM_pkg::*;

module linkinit(
    input logic clk,
    input logic rst_n,
    input RDI_state rdi_state_sts,      // Status from RDI State Machine
    input timeout_expired,               // Signal indicating timer has reached limit
    input Linkinit_enable,               // Enable signal to start initialization
    input start_ucie_link_training,      // Trigger for link training (error condition here)

    output logic linkinit_done,          // Asserted when link is successfully active
    output logic timeout_rst_n,          // Reset signal for the external timeout counter
    output logic enable_timeout,         // Enable signal for the external timeout counter
    output logic linkinit_error          // Asserted when an error or timeout occurs
);

// State definitions
typedef enum logic [2:0] {
    idle                = 3'b000,
    wait_for_rdi_active = 3'b001,
    link_error          = 3'b010
} linkinit_state_t;

linkinit_state_t cs, ns; // Current state and Next state

//------------------------------------------------------------------------------
// Sequential Block: State Register
//------------------------------------------------------------------------------
always @(posedge clk, negedge rst_n) begin
    if (!rst_n)
        cs <= idle;
    else
        cs <= ns;
end

//------------------------------------------------------------------------------
// Combinational Block: Next State and Output Logic
//------------------------------------------------------------------------------
always @(*) begin
    // Default values to prevent unintended latches during synthesis
    ns             = cs;
    linkinit_done  = 1'b0;
    timeout_rst_n  = 1'b1; // Reset is active low, default to inactive
    enable_timeout = 1'b0;
    linkinit_error = 1'b0;

    case (cs)
        // IDLE: Waiting for the enable signal to start initialization
        idle: begin
            if (Linkinit_enable) begin
                ns             = wait_for_rdi_active;
                timeout_rst_n  = 1'b0; // Pulse reset to clear external timer
                enable_timeout = 1'b1;
            end
        end

        // WAIT_FOR_RDI_ACTIVE: Monitoring RDI status and timeout conditions
        wait_for_rdi_active: begin
            enable_timeout = 1'b1;
            
            // Success: RDI reports Active state
            if (rdi_state_sts == Active) begin 
                ns            = idle;
                linkinit_done = 1'b1;
            end
            // Failure: Timeout reached or external training trigger detected
            else if (timeout_expired || start_ucie_link_training) begin
                ns             = link_error;
                linkinit_error = 1'b1;
            end
        end

        // LINK_ERROR: Error state, stays here until enable is de-asserted
        link_error: begin
            linkinit_error = 1'b1;
            if (~Linkinit_enable)
                ns = idle;
        end

        // Default case for safety
        default: ns = idle;
    endcase
end

endmodule