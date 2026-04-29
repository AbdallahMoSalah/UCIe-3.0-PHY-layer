`timescale 1ns / 1ps

import UCIe_pkg::*;
import RDI_SM_pkg::*;
import LTSM_state_pkg::*;
import reset_state_pkg::*;
// ============================================================================
// Module      : unit_reset_state_tb
// Description : Directed testbench for the unit_reset_state module.
//               Sequentially stimulates and verifies all key state transitions
//               including LinkError, Disable, LinkReset, and Active flows.
// ============================================================================
module unit_reset_state_tb;

    // Signals
    logic lclk;
    logic lp_linkerror;
    logic Active_handshake_done;
    logic EN;
    LTSM_state_e state_sts;
    RDI_state lp_state_req;
    msg_no_e message_receive;

    RDI_state next_state;
    logic Active_handshake_strt;
    reset_state cs_reg; 
    msg_no_e message_send;


    // Instantiate the DUT
    unit_reset_state dut (
        .lclk(lclk),
        .lp_linkerror(lp_linkerror),
        .Active_handshake_done(Active_handshake_done),
        .EN(EN),
        .state_sts(state_sts),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .next_state(next_state),
        .Active_handshake_strt(Active_handshake_strt),
        .cs_reg(cs_reg),
        .message_send(message_send)
    );

    // Clock Generation
    initial begin
        lclk = 0;
        forever #5 lclk = ~lclk;
    end

    initial begin
        //initial values
        EN=1;
        lp_linkerror=0;
        Active_handshake_done=0;
        state_sts=RESET;
        lp_state_req=Nop;
        message_receive=NOTHING;
        lp_state_req=Reset;
        #10;
        // --------------------------------------------------------------------
        // Scenario 1: Link Error through local lp_linkerror PHY signal
        // Expected: FSM asserts RDI_LINK_ERROR_REQ, waits for RSP, then enters linkerror
        // --------------------------------------------------------------------
        $display("scenario 1: link error through lp_linkerror");
        @(negedge lclk);    
        lp_linkerror=1;
        @(negedge lclk);    
        lp_linkerror=0;
        #30;
        @(negedge lclk);
        message_receive=RDI_LINK_ERROR_RSP;
        @(negedge lclk);
        message_receive=NOTHING;
        #10 EN=0;
        // --------------------------------------------------------------------
        // Scenario 2: LinkError triggered by a remote RDI_LINK_ERROR_REQ message
        // Expected: FSM asserts RDI_LINK_ERROR_RSP and transitions to linkerror
        // --------------------------------------------------------------------
        #10 EN=1;
        $display("scenario 2: LinkError through remote request");
        #10
        @(negedge lclk);
        message_receive=RDI_LINK_ERROR_REQ;
        @(negedge lclk);
        message_receive=NOTHING;
        #30 EN=0;
        // --------------------------------------------------------------------
        // Scenario 3: Disabled state triggered by local adapter request
        // Expected: FSM transitions to d_req, sends RDI_DISABLE_REQ, waits for RSP, then enters disabled
        // --------------------------------------------------------------------
        #10 EN=1;
        $display("scenario 3: disable through adapter request");
        #10;
        @(negedge lclk);
        lp_state_req=Nop;
        @(negedge lclk);
        lp_state_req=Disabled;
        #30 
        @(negedge lclk);
        message_receive=RDI_DISABLE_RSP;
        @(negedge lclk);
        message_receive=NOTHING;
        #10 EN=0;
        // --------------------------------------------------------------------
        // Scenario 4: Disabled state triggered by a remote RDI_DISABLE_REQ message
        // Expected: FSM replies with RDI_DISABLE_RSP and enters disabled state
        // --------------------------------------------------------------------
        #10 EN=1;
        $display("scenario 4: link Disabled through remote request");
        #10;
        @(negedge lclk);
        message_receive=RDI_DISABLE_REQ;
        @(negedge lclk);
        message_receive=NOTHING;
        #50 EN=0;
        // --------------------------------------------------------------------
        // Scenario 5: LinkReset triggered by local adapter request
        // Expected: FSM sends RDI_LINK_RESET_REQ, waits for RSP, then enters linkreset
        // --------------------------------------------------------------------
        #10 EN=1;
        $display("scenario 5: link reset through adapter request");
        #10;
        @(negedge lclk);
        lp_state_req=Nop;
        @(negedge lclk);
        lp_state_req=LinkReset;
        #30 
        @(negedge lclk);
        message_receive=RDI_LINK_RESET_RSP;
        @(negedge lclk);
        message_receive=NOTHING;
        #10 EN=0;
        // --------------------------------------------------------------------
        // Scenario 6: LinkReset triggered by a remote RDI_LINK_RESET_REQ message
        // Expected: FSM replies with RDI_LINK_RESET_RSP and enters linkreset state
        // --------------------------------------------------------------------
        #10 EN=1;
        $display("scenario 6: link reset through remote request ");
        #10;
        @(negedge lclk);
        message_receive=RDI_LINK_RESET_REQ;
        @(negedge lclk);
        message_receive=NOTHING;
        #30 EN=0;
        // --------------------------------------------------------------------
        // Scenario 7: Active state sequence triggered by local adapter request
        // Expected: FSM navigates training -> INPP -> NOP_rcvd -> active_hs -> active
        //           dependent on intermediate state_sts and handshake signals.
        // --------------------------------------------------------------------
        #10 EN=1;
        $display("scenario 7: active through adapter request");
        #10;
        @(negedge lclk);
        lp_state_req=Active;
        @(negedge lclk);
        #50;
        @(negedge lclk);
        state_sts=LINKINIT;
        #40;
        @(negedge lclk);
        lp_state_req=Nop;
        @(negedge lclk);
        lp_state_req=Active;
        #60;
        @(negedge lclk);
        Active_handshake_done=1;
        @(negedge lclk);
        Active_handshake_done=0;
        #10 EN=0;
        #10 $stop;
    end 
endmodule
