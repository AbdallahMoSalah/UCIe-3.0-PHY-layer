//-----------------------------------------------------------------------------
// Module      : unit_linkreset_state_tb
// Description : Testbench for unit_linkreset_state module.
//               Covers transitions from LinkReset to Reset, LinkError, and Disable.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_linkreset_state_tb();

    // -------------------------------------------------------------------------
    // DUT Port Signals
    // -------------------------------------------------------------------------
    logic           lclk;
    logic           EN;
    logic           lp_linkerror;
    RDI_state       lp_state_req;
    msg_no_e        message_receive;

    RDI_state       next_state;
    msg_no_e        message_send;

    // -------------------------------------------------------------------------
    // Verification Counters
    // -------------------------------------------------------------------------
    integer error_count   = 0;
    integer correct_count = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    unit_linkreset_state uut (
        .lclk           (lclk),
        .EN             (EN),
        .lp_linkerror   (lp_linkerror),
        .lp_state_req   (lp_state_req),
        .message_receive(message_receive),
        .next_state     (next_state),
        .message_send   (message_send)
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
            EN              = 0;
            lp_linkerror    = 0;
            lp_state_req    = Nop;
            message_receive = NOP;
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
        $display("    Starting unit_linkreset_state Simulation    ");
        $display("=================================================");

        // ---------------------------------------------------------------------
        // Scenario 1: Initial Enable
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 1: Initial Enable ---");
        initialize_uut();
        check_condition((uut.cs == 3'd1), "DUT did not reach idle state after EN=1");

        // ---------------------------------------------------------------------
        // Scenario 2: Path to Reset
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 2: Path to Reset ---");
        lp_state_req = Active;
        #20;
        check_condition((uut.cs == 3'd2),        "DUT did not reach reset_st");
        check_condition((next_state == Reset),   "next_state not driven to Reset");
        
        EN = 0; #20; lp_state_req = Nop; EN = 1; #20; // Return to idle for next scenario

        // ---------------------------------------------------------------------
        // Scenario 3: Path to LinkError
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 3: Path to LinkError ---");
        lp_linkerror = 1;
        #20;
        check_condition((uut.cs == 3'd3),            "DUT did not reach linkerror_st");
        check_condition((next_state == LinkError),   "next_state not driven to LinkError");
        lp_linkerror = 0;
        
        EN = 0; #20; EN = 1; #20;

        // ---------------------------------------------------------------------
        // Scenario 4: Disable Flow (Adapter Initiated)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 4: Disable flow (Adapter initiated) ---");
        lp_state_req = Disabled;
        #10;
        check_condition((message_send == RDI_DISABLE_REQ), "Did not send RDI_DISABLE_REQ");
        lp_state_req = Nop;
        
        message_receive = RDI_DISABLE_RSP;
        #10;
        check_condition((uut.cs == 3'd6),              "DUT did not reach disabled_st");
        check_condition((next_state == Disabled),      "next_state not Disabled");
        message_receive = NOP;
        
        EN = 0; #20; EN = 1; #20;

        // ---------------------------------------------------------------------
        // Scenario 5: Disable Flow (Peer Initiated)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 5: Disable flow (Peer initiated) ---");
        message_receive = RDI_DISABLE_REQ;
        #10;
        check_condition((message_send == RDI_DISABLE_RSP), "Did not send RDI_DISABLE_RSP");
        #10;
        check_condition((uut.cs == 3'd6),                  "DUT did not reach disabled_st (Peer)");
        message_receive = NOP;

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
