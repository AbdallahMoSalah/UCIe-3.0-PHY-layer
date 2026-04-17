`timescale 1ns/1ps

import RDI_SM_pkg::*;
import LTSM_state_pkg::*;
import UCIe_pkg::*;

module wrapper_sm_tb;

    // --- Signals ---
    logic           lclk;
    logic           rst_n;
    LTSM_state_e    state_sts;
    logic           pl_error;
    logic           lp_linkerror;
    RDI_state       lp_state_req;
    msg_no_e        message_receive;
    logic           Active_handshake_done;
    logic           stall_done;
    
    logic           stall_req;
    logic           Active_handshake_strt;
    msg_no_e        message_send;
    logic           trainerror;
    logic           phyinrecenter;
    logic           pm_exit;
    logic           inband_pres;
    RDI_state       rdi_state_sts;

    // --- Clock Generation (2GHz -> 500ps period) ---
    always #0.25 lclk = ~lclk;

    // --- Device Under Test ---
    wrapper_sm dut (
        .lclk(lclk),
        .rst_n(rst_n),
        .state_sts(state_sts),
        .pl_error(pl_error),
        .lp_linkerror(lp_linkerror),
        .lp_state_req(lp_state_req),
        .message_receive(message_receive),
        .Active_handshake_done(Active_handshake_done),
        .stall_done(stall_done),
        .stall_req(stall_req),
        .Active_handshake_strt(Active_handshake_strt),
        .message_send(message_send),
        .trainerror(trainerror),
        .phyinrecenter(phyinrecenter),
        .pm_exit(pm_exit),
        .inband_pres(inband_pres),
        .rdi_state_sts(rdi_state_sts)
    );

    // --- Test Stimulus ---
    initial begin
        // Initialize inputs
        lclk = 0;
        rst_n = 0;
        state_sts = RESET;
        pl_error = 0;
        lp_linkerror = 0;
        lp_state_req = Reset;
        message_receive = NOP;
        Active_handshake_done = 0;
        stall_done = 0;

        // Reset Sequence
        #1;
        rst_n = 1;
        #1;
        $display("[%0t] Reset released. Current RDI State: %s", $time, rdi_state_sts.name());

        // Test Scenario 1: Transition to Active
        // 1. Request Active from Adapter
        @(posedge lclk);
        lp_state_req = Active;
        
        // 2. Simulate LinkInit state from Link Layer SM
        @(posedge lclk);
        state_sts = LINKINIT;

        // 3. Move through Handshake logic
        // Reset state SM typically waits for handshake_done if it triggers it.
        wait(Active_handshake_strt);
        $display("[%0t] Active Handshake Started.", $time);
        
        #10;
        @(posedge lclk);
        Active_handshake_done = 1;
        
        // 4. Wait for transition in Main Controller
        wait(rdi_state_sts == Active);
        $display("[%0t] Transitioned to Active. Success!", $time);

        #100;
        $finish;
    end

    // Monitor
    initial begin
        $monitor("[%0t] RDI_STS: %s, MSG_SEND: %s", $time, rdi_state_sts.name(), message_send.name());
    end

endmodule
