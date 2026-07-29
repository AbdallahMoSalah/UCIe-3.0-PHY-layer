// =============================================================================
//  ucie_mainband_slave_if
// -----------------------------------------------------------------------------
//  SystemVerilog interface encapsulating Mainband Slave Receive signals
//  (PHY to Adapter/TB upstream path).
// =============================================================================

`timescale 1ns/1ps

interface ucie_mainband_slave_if #(
    parameter int FLITW = 512
)(
    input logic clk,
    input logic rst_n
);

  // --- Receive Interface (PHY to Adapter/TB) ---
  logic [FLITW-1:0] pl_data;
  logic             pl_valid;

endinterface
