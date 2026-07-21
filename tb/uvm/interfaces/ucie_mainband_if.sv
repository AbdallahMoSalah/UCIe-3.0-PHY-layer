// =============================================================================
//  ucie_mainband_if
// -----------------------------------------------------------------------------
//  SystemVerilog interface encapsulating Mainband Tx and Rx signals for a single die.
// =============================================================================

`timescale 1ns/1ps

interface ucie_mainband_if #(
    parameter int FLITW = 256
)(
    input logic clk,
    input logic rst_n
);

  // --- Transmit Interface (Adapter/TB to PHY) ---
  logic [FLITW-1:0] lp_data;
  logic             lp_valid;
  logic             lp_irdy;
  logic             pl_trdy;
  logic             pl_error;

  // --- Receive Interface (PHY to Adapter/TB) ---
  logic [FLITW-1:0] pl_data;
  logic             pl_valid;

  initial begin
    lp_data  = '0;
    lp_valid = 1'b0;
    lp_irdy  = 1'b0;
  end

endinterface
