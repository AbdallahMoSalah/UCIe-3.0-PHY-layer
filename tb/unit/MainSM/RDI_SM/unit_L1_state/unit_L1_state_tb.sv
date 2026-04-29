//-----------------------------------------------------------------------------
// Module      : unit_L1_state_tb
// Description : Testbench for unit_L1_state module.
//               Covers 8+ transitions from the L1 state machine diagram.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module unit_L1_state_tb();

    // -------------------------------------------------------------------------
    // DUT Port Signals
    // -------------------------------------------------------------------------
    logic           lclk;
    logic           EN;
    logic           lp_linkerror;
    RDI_state       lp_state_req;
    msg_no_e    message_receive;
    logic           Active_handshake_done;

    RDI_state       next_state;
    LTSM_state_e    state_req;
    logic           active_handshake_strt;
    msg_no_e        message_send;

    // -------------------------------------------------------------------------
    // Verification Counters
    // -------------------------------------------------------------------------
    integer error_count   = 0;
    integer correct_count = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    unit_L1_state uut (
        .lclk                 (lclk),
        .EN                   (EN),
        .lp_linkerror         (lp_linkerror),
        .lp_state_req         (lp_state_req),
        .message_receive      (message_receive),
        .Active_handshake_done(Active_handshake_done),
        .next_state           (next_state),
        .state_req            (state_req),
        .active_handshake_strt(active_handshake_strt),
        .message_send         (message_send)
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
    //   Enables the DUT and settles it in idle sub-state.
    // =========================================================================
    task initialize_uut;
        begin
            EN                    = 0;
            lp_linkerror          = 0;
            lp_state_req          = Nop;
            message_receive       = NOP;
            Active_handshake_done = 0;
            #20;
            EN = 1;
            #20;
        end
    endtask

    // =========================================================================
    // Task: deassert_en_and_verify_disabled
    // =========================================================================
    task deassert_en_and_verify_disabled(input string label);
        begin
            EN = 0;
            #20;
            check_condition((uut.cs == 4'd0), $sformatf("DUT did not return to state_disables after EN=0 (%s)", label));
        end
    endtask

    // =========================================================================
    // Main Simulation
    // =========================================================================
    initial begin
        lclk = 0;

        $display("=================================================");
        $display("       Starting unit_L1_state Simulation        ");
        $display("=================================================");

        // ---------------------------------------------------------------------
        // Scenario 1: Initial Enable
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 1: Initial Enable ---");
        initialize_uut();
        check_condition((uut.cs == 4'd1), "DUT did not reach idle state after EN=1");

        // ---------------------------------------------------------------------
        // Scenario 2: Active Re-entry (Adapter lp_state_req=Active)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 2: Active Re-entry (Adapter-initiated) ---");
        lp_state_req = Active;
        #10;
        check_condition((active_handshake_strt == 1'b1), "active_handshake_strt not pulsed");
        check_condition((state_req == ACTIVE),           "state_req not ACTIVE");
        check_condition((uut.cs == 4'd8),                "DUT did not reach training state");
        
        #10;
        lp_state_req = Nop;
        message_receive = RDI_ACTIVE_REQ; 
        #10;
        check_condition((uut.cs == 4'd9),                "DUT did not reach reset state (re-entry done)");
        check_condition((next_state == Active),          "next_state not Active");
        message_receive = NOP;
        
        deassert_en_and_verify_disabled("Active Re-entry Adapter");

        // ---------------------------------------------------------------------
        // Scenario 3: Active Re-entry (Peer RDI_ACTIVE_REQ)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 3: Active Re-entry (Peer-initiated) ---");
        initialize_uut();
        message_receive = RDI_ACTIVE_REQ;
        #10;
        check_condition((state_req == ACTIVE),           "state_req not ACTIVE on Peer re-entry");
        check_condition((uut.cs == 4'd9),                "DUT did not reach reset state");
        message_receive = NOP;
        
        deassert_en_and_verify_disabled("Active Re-entry Peer");

        // ---------------------------------------------------------------------
        // Scenario 4: LinkError (Local detect)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 4: LinkError (Local detect) ---");
        initialize_uut();
        lp_linkerror = 1;
        #10;
        check_condition((message_send == RDI_LINK_ERROR_REQ), "Did not send RDI_LINK_ERROR_REQ");
        lp_linkerror = 0;
        
        message_receive = RDI_LINK_ERROR_RSP;
        #10;
        #10;check_condition((uut.cs == 4'd11),             "DUT did not reach linkerror state");
        check_condition((next_state == LinkError),      "next_state not LinkError");
        message_receive = NOP;
        
        deassert_en_and_verify_disabled("LinkError Local");

        // ---------------------------------------------------------------------
        // Scenario 5: LinkError (Peer initiated)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 5: LinkError (Peer initiated) ---");
        initialize_uut();
        message_receive = RDI_LINK_ERROR_REQ;
        #10;
        check_condition((message_send == RDI_LINK_ERROR_RSP), "Did not send RDI_LINK_ERROR_RSP");
        #10;check_condition((uut.cs == 4'd11),                    "DUT did not reach linkerror state (Peer)");
        message_receive = NOP;
        
        deassert_en_and_verify_disabled("LinkError Peer");

        // ---------------------------------------------------------------------
        // Scenario 6: LinkReset (Adapter initiated)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 6: LinkReset (Adapter initiated) ---");
        initialize_uut();
        lp_state_req = LinkReset;
        #10;
        check_condition((message_send == RDI_LINK_RESET_REQ), "Did not send RDI_LINK_RESET_REQ");
        lp_state_req = Nop;
        
        message_receive = RDI_LINK_RESET_RSP;
        #10;
        #10;check_condition((uut.cs == 4'd10),               "DUT did not reach linkreset state");
        check_condition((next_state == LinkReset),        "next_state not LinkReset");
        message_receive = NOP;
        
        deassert_en_and_verify_disabled("LinkReset Local");

        // ---------------------------------------------------------------------
        // Scenario 7: LinkReset (Peer initiated)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 7: LinkReset (Peer initiated) ---");
        initialize_uut();
        message_receive = RDI_LINK_RESET_REQ;
        #10;
        check_condition((message_send == RDI_LINK_RESET_RSP), "Did not send RDI_LINK_RESET_RSP");
        #10;check_condition((uut.cs == 4'd10),                    "DUT did not reach linkreset state (Peer)");
        message_receive = NOP;
        
        deassert_en_and_verify_disabled("LinkReset Peer");

        // ---------------------------------------------------------------------
        // Scenario 8: Disable (Adapter initiated)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 8: Disable (Adapter initiated) ---");
        initialize_uut();
        lp_state_req = Disabled;
        #10;
        check_condition((message_send == RDI_DISABLE_REQ), "Did not send RDI_DISABLE_REQ");
        lp_state_req = Nop;
        
        message_receive = RDI_DISABLE_RSP;
        #10;
        #10;check_condition((uut.cs == 4'd12),             "DUT did not reach disabled state");
        check_condition((next_state == Disabled),      "next_state not Disabled");
        message_receive = NOP;
        
        deassert_en_and_verify_disabled("Disable Local");

        // ---------------------------------------------------------------------
        // Scenario 9: Disable (Peer initiated)
        // ---------------------------------------------------------------------
        $display("\n--- Scenario 9: Disable (Peer initiated) ---");
        initialize_uut();
        message_receive = RDI_DISABLE_REQ;
        #10;
        check_condition((message_send == RDI_DISABLE_RSP), "Did not send RDI_DISABLE_RSP");
        #10;check_condition((uut.cs == 4'd12),                 "DUT did not reach disabled state (Peer)");
        message_receive = NOP;
        
        deassert_en_and_verify_disabled("Disable Peer");

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
