//-----------------------------------------------------------------------------
// Module      : unit_disabled_state_tb
// Description : Testbench for unit_disabled_state module.
//               Covers transitions from Disabled to Reset and LinkError.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_disabled_state_tb();

    // -------------------------------------------------------------------------
    // DUT Port Signals
    // -------------------------------------------------------------------------
    logic           lclk;
    logic           EN;
    logic           lp_linkerror;
    RDI_state       lp_state_req;

    RDI_state       next_state;

    // -------------------------------------------------------------------------
    // Verification Counters
    // -------------------------------------------------------------------------
    integer error_count   = 0;
    integer correct_count = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    unit_disabled_state uut (
        .lclk        (lclk),
        .EN          (EN),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .next_state  (next_state)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (10 ns period)
    // -------------------------------------------------------------------------
    always #5 lclk = ~lclk;

    // =========================================================================
    // Task: check_condition
    // =========================================================================
    task check_condition(input logic condition, input string err_msg);
        begin
            if (!condition) begin
                $display("[%0t] FAILED: %s", $time, err_msg);
                error_count = error_count + 1;
            end else begin
                correct_count = correct_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Task: initialize_uut
    // =========================================================================
    task initialize_uut;
        begin
            EN           = 0;
            lp_linkerror = 0;
            lp_state_req = Nop;
            #20;
            EN = 1;
            #20;
        end
    endtask

    // =========================================================================
    // Main Simulation
    // =========================================================================
    initial begin
        lclk = 0;

        $display("=================================================");
        $display("     Starting unit_disabled_state Simulation    ");
        $display("=================================================");

        // ---------------------------------------------------------------------
        // Scenario 1: Initial Enable
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 1: Initial Enable ---");
        initialize_uut();
        check_condition((uut.cs == 2'd1), "DUT did not reach idle state after EN=1");

        // ---------------------------------------------------------------------
        // Scenario 2: Path to Reset
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 2: Path to Reset ---");
        lp_state_req = Active;
        #20;
        check_condition((uut.cs == 2'd2),        "DUT did not reach reset_st");
        check_condition((next_state == Reset),   "next_state not driven to Reset");
        
        EN = 0; #20; EN = 1; #20; // Return to idle for next scenario

        // ---------------------------------------------------------------------
        // Scenario 3: Path to LinkError
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 3: Path to LinkError ---");
        lp_linkerror = 1;
        #20;
        check_condition((uut.cs == 2'd3),            "DUT did not reach linkerror_st");
        check_condition((next_state == LinkError),   "next_state not driven to LinkError");
        lp_linkerror = 0;

        // ---------------------------------------------------------------------
        // Scenario 4: Disable flow
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 4: Disable flow ---");
        EN = 0;
        #20;
        check_condition((uut.cs == 2'd0),        "DUT did not return to state_disabled after EN=0");
        check_condition((next_state == Nop),     "next_state not Nop after disabling");

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n=================================================");
        $display("   Simulation Completed.");
        $display("   Correct asserts : %0d", correct_count);
        $display("   Error asserts   : %0d", error_count);
        $display("=================================================");

        if (error_count == 0)
            $display("   >>> ALL TESTS PASSED <<<");
        else
            $display("   >>> SOME TESTS FAILED <<<");

        #50;
        $finish;
    end

endmodule
