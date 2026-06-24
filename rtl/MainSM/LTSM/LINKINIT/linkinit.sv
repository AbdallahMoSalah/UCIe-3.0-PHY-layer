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
    input Linkinit_enable,               // Enable signal to start initialization

    output logic linkinit_done,          // Asserted when link is successfully active
    output logic linkinit_error          // Asserted when an error or timeout occurs
);
    // NOTE: the 8 ms state watchdog is owned by the ltsm_controller (shared
    // timer, enabled while in LINKINIT). This block no longer drives its own
    // timeout counter — the controller handles the timeout / TRAINERROR path.

// State definitions
typedef enum logic [1:0] {
    idle                = 2'b00,
    wait_for_rdi_active = 2'b01,
    done                = 2'b10
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
    linkinit_error = 1'b0;

    if (~Linkinit_enable)
        ns = idle;
    else begin
        case (cs)
            // IDLE: Waiting for the enable signal to start initialization
            idle: begin
                ns = wait_for_rdi_active;
            end
            // WAIT_FOR_RDI_ACTIVE: Monitoring RDI status (8 ms timeout owned by
            // the ltsm_controller now)
            wait_for_rdi_active: begin
                // Success: RDI reports Active state
                if (rdi_state_sts == Active) begin
                    ns            = done;
                    linkinit_done = 1'b1;
                end
                // NOTE: previously a high start_ucie_link_training here forced
                // link_error.  With "Start UCIe Link Training" now sourced from the
                // Reg_File (UCIe Link Control[10]), that bit is held high for the
                // whole training window and only auto-clears at completion, so it is
                // legitimately still asserted while LINKINIT waits for RDI Active.
                // Treating it as a re-train/error trigger here deadlocks bring-up,
                // so the abort path is removed; the 8 ms watchdog in the
                // ltsm_controller still covers a genuinely stuck LINKINIT.
            end

            // DONE: Link is successfully active and the signal will de-assert
            done: begin
                linkinit_done = 1'b1;
            end

            // Default case for safety
            default: ns = idle;
        endcase
    end
end

endmodule
