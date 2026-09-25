// =============================================================================
//  ucie_channel_if
// -----------------------------------------------------------------------------
//  SystemVerilog interface representing the physical package link.
// =============================================================================

`timescale 1ns/1ps

interface ucie_channel_if #(
    parameter int NUM_LANES = 16
)();

    logic [NUM_LANES-1:0] corrupt_0to1;
    logic [NUM_LANES-1:0] corrupt_1to0;
    logic                 reverse_0to1;
    logic                 reverse_1to0;
    logic                 block_sideband;
    logic                 rx_vld_error_inject_0_to_1;

    // Initialization
    initial begin
        corrupt_0to1               = '0;
        corrupt_1to0               = '0;
        reverse_0to1               = 1'b0;
        reverse_1to0               = 1'b0;
        block_sideband             = 1'b0;
        rx_vld_error_inject_0_to_1 = 1'b0;
    end

endinterface
