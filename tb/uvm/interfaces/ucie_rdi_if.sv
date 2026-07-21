// =============================================================================
//  ucie_rdi_if
// -----------------------------------------------------------------------------
//  SystemVerilog interface wrapping RDI control/state signals for both dies.
//  Enables Virtual Sequences to drive adapter state transitions and perform
//  clock/power management handshakes.
// =============================================================================

`timescale 1ns/1ps

interface ucie_rdi_if (
    input logic clk0, // Die 0 clock
    input logic clk1  // Die 1 clock
);

    // --- Die 0 (Local) RDI Signals ---
    RDI_SM_pkg::RDI_state lp_state_req0;
    logic                 lp_clk_ack0;
    logic                 lp_wake_req0;
    logic                 lp_stallack0;
    logic                 lp_linkerror0;

    RDI_SM_pkg::RDI_state pl_state_sts0;
    logic                 pl_clk_req0;
    logic                 pl_stallreq0;
    logic                 pl_wake_ack0;
    logic                 pl_trainerror0;
    logic                 pl_inband_pres0; // Inband Presence output from PHY 0

    // --- Die 1 (Partner) RDI Signals ---
    RDI_SM_pkg::RDI_state lp_state_req1;
    logic                 lp_clk_ack1;
    logic                 lp_wake_req1;
    logic                 lp_stallack1;
    logic                 lp_linkerror1;

    RDI_SM_pkg::RDI_state pl_state_sts1;
    logic                 pl_clk_req1;
    logic                 pl_stallreq1;
    logic                 pl_wake_ack1;
    logic                 pl_trainerror1;
    logic                 pl_inband_pres1; // Inband Presence output from PHY 1

    // Default Initialization
    initial begin
        lp_state_req0 = RDI_SM_pkg::Nop;
        lp_clk_ack0   = 1'b0;
        lp_wake_req0  = 1'b0;
        lp_stallack0  = 1'b0;
        lp_linkerror0 = 1'b0;

        lp_state_req1 = RDI_SM_pkg::Nop;
        lp_clk_ack1   = 1'b0;
        lp_wake_req1  = 1'b0;
        lp_stallack1  = 1'b0;
        lp_linkerror1 = 1'b0;
    end

endinterface
