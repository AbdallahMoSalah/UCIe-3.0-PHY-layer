//-----------------------------------------------------------------------------
// Module      : unit_active_pmnak_state_tb
// Description : Testbench for the unit_active_pmnak_state logic.
//               Covers all scenarios from idle, keeping track of 
//               error and correct check counts.
//-----------------------------------------------------------------------------
`timescale 1ns/1ps
import RDI_SM_pkg::*;
import UCIe_pkg::*;

module unit_active_pmnak_state_tb();

    // Testbench Inputs
    logic lclk;
    logic rst_n;
    logic lp_linkerror;
    RDI_state lp_state_req;
    msg_no_e message_receive;
    logic stall_done;
    logic en;

    // Testbench Outputs
    logic stall_req;
    msg_no_e message_send;
    RDI_state next_state;

    // Verification counters
    integer error_count = 0;
    integer correct_count = 0;

    // Instantiate the Unit Under Test (UUT)
    unit_active_pmnak_state uut (
        .lclk(lclk),
        .rst_n(rst_n),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .stall_done(stall_done),
        .en(en),
        .stall_req(stall_req),
        .message_send(message_send),
        .next_state(next_state)
    );

    // Clock generation (10ns period)
    always #5 lclk = ~lclk;

    // -------------------------------------------------------------
    // Task: Check condition
    // -------------------------------------------------------------
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

    // -------------------------------------------------------------
    // Task: Reset UUT
    // -------------------------------------------------------------
    task reset_uut;
        begin
            rst_n = 0;
            en = 0;
            lp_linkerror = 0;
            lp_state_req = Nop;
            message_receive = NOP;
            stall_done = 0;
            #20;
            rst_n = 1;
            en = 1; 
            #30; 
        end
    endtask

    // -------------------------------------------------------------
    // Task: Process Stall Handshake
    // -------------------------------------------------------------
    task complete_stall;
        begin
            wait(stall_req == 1);
            #10;
            stall_done = 1;
            wait(stall_req == 0);
            #10; 
            stall_done = 0;
        end
    endtask

    // -------------------------------------------------------------
    // Main Simulation Block
    // -------------------------------------------------------------
    initial begin
        // Init clock
        lclk = 0;
        
        $display("=================================================");
        $display("   Starting unit_active_pmnak_state Simulation   ");
        $display("=================================================");
        
        // --- Scenario 1: Basic Reset and Enable ---
        $display("\n--- Scenario 1: Reset and transition to Idle ---");
        reset_uut();
        check_condition((uut.current_state.name() == "IDLE"), "Did not reach IDLE state.");
        
        // --- Scenario 2: message_receive == RDI_LINK_ERROR_REQ ---
        $display("\n--- Scenario 2: Peer RDI_LINK_ERROR_REQ ---");
        message_receive = RDI_LINK_ERROR_REQ;
        #10;
        message_receive = NOP;
        check_condition((message_send == RDI_LINK_ERROR_RSP), "Did not send RDI_LINK_ERROR_RSP");
        #10;
        check_condition((next_state == LinkError), "Did not reach LinkError next_state");

        // --- Scenario 3: lp_linkerror == 1 ---
        $display("\n--- Scenario 3: Adapter lp_linkerror ---");
        reset_uut();
        lp_linkerror = 1;
        #10;
        lp_linkerror = 0;
        check_condition((message_send == RDI_LINK_ERROR_REQ), "Did not send RDI_LINK_ERROR_REQ");
        message_receive = RDI_LINK_ERROR_RSP;
        #10;
        message_receive = NOP;
        check_condition((next_state == LinkError), "Did not reach LinkError next_state");

        // --- Scenario 4: lp_state_req == Active ---
        $display("\n--- Scenario 4: Adapter requests Active ---");
        reset_uut();
        lp_state_req = Active;
        #10;
        lp_state_req = Nop;
        check_condition((next_state == Active), "Did not transition to Active state properly");

        // --- Scenario 5: message_receive == RDI_DISABLE_REQ ---
        $display("\n--- Scenario 5: Peer sends RDI_DISABLE_REQ ---");
        reset_uut();
        message_receive = RDI_DISABLE_REQ;
        #10;
        message_receive = NOP;
        complete_stall();
        check_condition((message_send == RDI_DISABLE_RSP), "Did not send RDI_DISABLE_RSP");
        #10;
        check_condition((next_state == Disabled), "Did not reach Disabled next_state");
        #10;
        // --- Scenario 6: lp_state_req == Disabled ---
        $display("\n--- Scenario 6: Adapter requests Disabled ---");
        reset_uut();
        lp_state_req = Disabled;
        #10;
        lp_state_req = Nop;
        complete_stall();
        check_condition((message_send == RDI_DISABLE_REQ), "Did not send RDI_DISABLE_REQ");
        message_receive = RDI_DISABLE_RSP;
        #10;
        message_receive = NOP;
        check_condition((next_state == Disabled), "Did not reach Disabled next_state");

        // --- Scenario 7: message_receive == RDI_RETRAIN_REQ ---
        $display("\n--- Scenario 7: Peer sends RDI_RETRAIN_REQ ---");
        reset_uut();
        message_receive = RDI_RETRAIN_REQ;
        #10;
        message_receive = NOP;
        complete_stall();
        check_condition((message_send == RDI_RETRAIN_RSP), "Did not send RDI_RETRAIN_RSP");
        #10;
        check_condition((next_state == Retrain), "Did not reach Retrain next_state");
        #10;
        // --- Scenario 8: lp_state_req == Retrain ---
        $display("\n--- Scenario 8: Adapter requests Retrain ---");
        reset_uut();
        lp_state_req = Retrain;
        #10;
        lp_state_req = Nop;
        complete_stall();
        check_condition((message_send == RDI_RETRAIN_REQ), "Did not send RDI_RETRAIN_REQ");
        message_receive = RDI_RETRAIN_RSP;
        #10;
        message_receive = NOP;
        #10;
        check_condition((next_state == Retrain), "Did not reach Retrain next_state");
        #10;
        // --- Scenario 9: lp_state_req == LinkReset ---
        $display("\n--- Scenario 9: Adapter requests LinkReset ---");
        reset_uut();
        lp_state_req = LinkReset;
        #10;
        lp_state_req = Nop;
        complete_stall();
        check_condition((message_send == RDI_LINK_RESET_REQ), "Did not send RDI_LINK_RESET_REQ");
        message_receive = RDI_LINK_RESET_RSP;
        #10;
        message_receive = NOP;
        #10;
        check_condition((next_state == LinkReset), "Did not reach LinkReset next_state");
        #10;
        // --- Scenario 10: message_receive == RDI_LINK_RESET_REQ ---
        $display("\n--- Scenario 10: Peer sends RDI_LINK_RESET_REQ ---");
        reset_uut();
        message_receive = RDI_LINK_RESET_REQ;
        #10;
        message_receive = NOP;
        complete_stall();
        check_condition((message_send == RDI_LINK_RESET_RSP), "Did not send RDI_LINK_RESET_RSP");
        #10;
        check_condition((next_state == LinkReset), "Did not reach LinkReset next_state");
        #10;

        $display("=================================================");
        $display("   Simulation Completed.");
        $display("   Correct asserts: %0d", correct_count);
        $display("   Error asserts:   %0d", error_count);
        $display("=================================================");
        
        if (error_count == 0) begin
            $display("   >>> ALL TESTS PASSED <<<");
        end else begin
            $display("   >>> SOME TESTS FAILED <<<");
        end

        #50;
        $stop;
    end
endmodule
