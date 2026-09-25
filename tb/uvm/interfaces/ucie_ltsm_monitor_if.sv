// =============================================================================
//  ucie_ltsm_monitor_if
// -----------------------------------------------------------------------------
//  SystemVerilog interface to probe the internal LTSM FSM states of Die 0 & Die 1.
// =============================================================================

`timescale 1ns/1ps

interface ucie_ltsm_monitor_if (
    input logic clk0, // lclk from Die 0
    input logic clk1  // lclk from Die 1
);
    logic rst_n;

    // --- Die 0 (Local) state probes ---
    ltsm_state_n_pkg::state_n_e   state0;
    LTSM_state_pkg::LTSM_state_e  ctrl_state0;

    // --- Die 1 (Partner) state probes ---
    ltsm_state_n_pkg::state_n_e   state1;
    LTSM_state_pkg::LTSM_state_e  ctrl_state1;

endinterface
