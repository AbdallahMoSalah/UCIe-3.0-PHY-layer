//-----------------------------------------------------------------------------
// Module      : unit_retrain_state_tb
// Description : Testbench for the unit_retrain_state logic.
//               Covers all sub-state transitions:
//                 - Enable sequencing
//                 - Normal exit via Active handshake
//                 - LinkError escape (local adapter + peer-initiated)
//                 - LinkReset escape (local adapter + peer-initiated)
//                 - Disable escape (local adapter + peer-initiated)
//                 - EN de-assertion and re-entry after every terminal state
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
import RDI_SM_pkg::*;
import UCIe_pkg::*;
import LTSM_state_pkg::*;

module unit_retrain_state_tb();

    // -------------------------------------------------------------------------
    // DUT Port Signals
    // -------------------------------------------------------------------------
    logic           lclk;
    logic           EN;
    logic           lp_linkerror;
    RDI_state       lp_state_req;
    msg_no_e        message_receive;
    logic       Active_handshake_done;
    LTSM_state_e    state_sts;

    LTSM_state_e    state_req;
    RDI_state       next_state;
    logic           Active_handshake_strt;
    msg_no_e        message_send;

    // -------------------------------------------------------------------------
    // Verification Counters
    // -------------------------------------------------------------------------
    integer error_count   = 0;
    integer correct_count = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    unit_retrain_state uut (
        .lclk                 (lclk),
        .EN                   (EN),
        .lp_linkerror         (lp_linkerror),
        .lp_state_req         (lp_state_req),
        .message_receive      (message_receive),
        .Active_handshake_done(Active_handshake_done),
        .state_sts            (state_sts),
        .state_req            (state_req),
        .next_state           (next_state),
        .Active_handshake_strt (Active_handshake_strt),
        .message_send         (message_send)
    );

    // -------------------------------------------------------------------------
    // Clock Generation  (10 ns period)
    // -------------------------------------------------------------------------
    always #5 lclk = ~lclk;

    // =========================================================================
    // Task : check_condition
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
    // Task : initialize_uut
    //   Leaves DUT in idle sub-state.
    // =========================================================================
    task initialize_uut;
        begin
            EN                    = 0;
            lp_linkerror          = 0;
            lp_state_req          = Nop;
            message_receive       = NOP;
            Active_handshake_done = 0;
            state_sts             = PHYRETRAIN;
            #20;
            EN = 1;     // Grant Retrain context to DUT
            #20;        // Allow DUT to settle to idle
        end
    endtask

    // =========================================================================
    // Task : deassert_en_and_wait
    //   Simulates the top-level SM releasing EN once a terminal state is reached.
    //   Returns DUT to state_disabled, ready for a fresh initialize_uut.
    // =========================================================================
    task deassert_en_and_wait;
        begin
            EN = 0;
            #20;
        end
    endtask

    // =========================================================================
    // Main Simulation
    // =========================================================================
    initial begin
        lclk = 0;

        $display("=================================================");
        $display("     Starting unit_retrain_state Simulation     ");
        $display("=================================================");

        // =====================================================================
        // Scenario 1: Enable → idle
        // Expected: After EN raised, DUT reaches idle.
        //           next_state should be Retrain (advertised to top-level SM).
        // =====================================================================
        $display("\n--- Scenario 1: Enable → idle ---");
        initialize_uut();
        check_condition((uut.cs == 4'd1),      "DUT did not reach idle sub-state after enable");
        check_condition((next_state == Retrain), "next_state not driven to Retrain after enable");

        // =====================================================================
        // Scenario 2: Normal exit via Active handshake (Active_handshake_done)
        // Expected: DUT pulses Active_handshake_strt, waits for done, then sets
        //           next_state = Active and moves to active state.
        // =====================================================================
        $display("\n--- Scenario 2: Normal exit via Active handshake ---");
        // To trigger active_hs, we need state_sts == LINKINIT and lp_state_req == Active
        // And we need to be in idle. initialize_uut puts us in idle.
        state_sts = LINKINIT;
        lp_state_req = Active;
        #20;
        check_condition((uut.cs == 4'd8),          "DUT did not reach active_hs state");
        check_condition((Active_handshake_strt == 1'b1), "Active_handshake_strt not pulsed");
        
        #10;
        Active_handshake_done = 1;                 // Sub-SM signals done
        #10;
        check_condition((next_state == Active),    "next_state not Active after handshake done");
        check_condition((state_req == ACTIVE),     "state_req not ACTIVE after handshake done");
        check_condition((uut.cs == 4'd10),         "DUT did not reach terminal active sub-state");
        Active_handshake_done = 0;

        // Stay in active until EN drops
        deassert_en_and_wait();
        check_condition((uut.cs == 4'd0),          "DUT did not return to state_disabled after EN=0");

        // =====================================================================
        // Scenario 3: LinkError escape – local adapter (lp_linkerror)
        // Expected: DUT sends RDI_LINK_ERROR_REQ, waits for RSP, then
        //           sets next_state = LinkError.
        // =====================================================================
        $display("\n--- Scenario 3: LinkError escape (local lp_linkerror) ---");
        initialize_uut();
        lp_linkerror = 1;
        #10;
        lp_linkerror = 0;
        check_condition((message_send == RDI_LINK_ERROR_REQ), "Did not send RDI_LINK_ERROR_REQ");

        message_receive = RDI_LINK_ERROR_RSP;
        #10;
        message_receive = NOP;
        #10;
        check_condition((next_state == LinkError), "next_state not LinkError after local LE flow");
        check_condition((uut.cs == 4'd11),         "DUT did not reach linkerror sub-state");

        deassert_en_and_wait();
        check_condition((uut.cs == 4'd0),          "DUT did not return to state_disabled after EN=0 (LE local)");

        // =====================================================================
        // Scenario 4: LinkError escape – peer initiates (RDI_LINK_ERROR_REQ received)
        // Expected: DUT immediately sends RDI_LINK_ERROR_RSP and settles into linkerror.
        // =====================================================================
        $display("\n--- Scenario 4: LinkError escape (peer RDI_LINK_ERROR_REQ) ---");
        initialize_uut();
        message_receive = RDI_LINK_ERROR_REQ;
        #10;
        message_receive = NOP;
        check_condition((message_send == RDI_LINK_ERROR_RSP), "Did not send RDI_LINK_ERROR_RSP to peer");
        #10;
        check_condition((next_state == LinkError), "next_state not LinkError after peer LE flow");
        check_condition((uut.cs == 4'd11),         "DUT did not reach linkerror sub-state (peer)");

        deassert_en_and_wait();
        check_condition((uut.cs == 4'd0),          "DUT did not return to state_disabled after EN=0 (LE peer)");

        // =====================================================================
        // Scenario 5: LinkReset escape – local adapter (lp_state_req == LinkReset)
        // Expected: DUT sends RDI_LINK_RESET_REQ, waits for RSP, sets next_state = LinkReset.
        // =====================================================================
        $display("\n--- Scenario 5: LinkReset escape (local lp_state_req) ---");
        initialize_uut();
        lp_state_req = LinkReset;
        #10;
        lp_state_req = Nop;
        check_condition((message_send == RDI_LINK_RESET_REQ), "Did not send RDI_LINK_RESET_REQ");

        message_receive = RDI_LINK_RESET_RSP;
        #10;
        message_receive = NOP;
        #10;
        check_condition((next_state == LinkReset), "next_state not LinkReset after local LR flow");
        check_condition((uut.cs == 4'd12),         "DUT did not reach linkreset sub-state");

        deassert_en_and_wait();
        check_condition((uut.cs == 4'd0),           "DUT did not return to state_disabled after EN=0 (LR local)");

        // =====================================================================
        // Scenario 6: LinkReset escape – peer initiates (RDI_LINK_RESET_REQ received)
        // Expected: DUT immediately sends RDI_LINK_RESET_RSP and settles into linkreset.
        // =====================================================================
        $display("\n--- Scenario 6: LinkReset escape (peer RDI_LINK_RESET_REQ) ---");
        initialize_uut();
        message_receive = RDI_LINK_RESET_REQ;
        #10;
        message_receive = NOP;
        check_condition((message_send == RDI_LINK_RESET_RSP), "Did not send RDI_LINK_RESET_RSP to peer");
        #10;
        check_condition((next_state == LinkReset), "next_state not LinkReset after peer LR flow");
        check_condition((uut.cs == 4'd12),         "DUT did not reach linkreset sub-state (peer)");

        deassert_en_and_wait();
        check_condition((uut.cs == 4'd0),           "DUT did not return to state_disabled after EN=0 (LR peer)");

        // =====================================================================
        // Scenario 7: Disable escape – local adapter (lp_state_req == Disabled)
        // Expected: DUT sends RDI_DISABLE_REQ, waits for RSP, sets next_state = Disabled.
        // =====================================================================
        $display("\n--- Scenario 7: Disable escape (local lp_state_req) ---");
        initialize_uut();
        lp_state_req = Disabled;
        #10;
        lp_state_req = Nop;
        check_condition((message_send == RDI_DISABLE_REQ), "Did not send RDI_DISABLE_REQ");

        message_receive = RDI_DISABLE_RSP;
        #10;
        message_receive = NOP;
        #10;
        check_condition((next_state == Disabled), "next_state not Disabled after local Disable flow");
        check_condition((uut.cs == 4'd13),         "DUT did not reach disabled sub-state");

        deassert_en_and_wait();
        check_condition((uut.cs == 4'd0),          "DUT did not return to state_disabled after EN=0 (Dis local)");

        // =====================================================================
        // Scenario 8: Disable escape – peer initiates (RDI_DISABLE_REQ received)
        // Expected: DUT immediately sends RDI_DISABLE_RSP and settles into disabled.
        // =====================================================================
        $display("\n--- Scenario 8: Disable escape (peer RDI_DISABLE_REQ) ---");
        initialize_uut();
        message_receive = RDI_DISABLE_REQ;
        #10;
        message_receive = NOP;
        check_condition((message_send == RDI_DISABLE_RSP), "Did not send RDI_DISABLE_RSP to peer");
        #10;
        check_condition((next_state == Disabled), "next_state not Disabled after peer Disable flow");
        check_condition((uut.cs == 4'd13),         "DUT did not reach disabled sub-state (peer)");

        deassert_en_and_wait();
        check_condition((uut.cs == 4'd0),          "DUT did not return to state_disabled after EN=0 (Dis peer)");

        // =====================================================================
        // Summary
        // =====================================================================
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
        $stop;
    end

endmodule
