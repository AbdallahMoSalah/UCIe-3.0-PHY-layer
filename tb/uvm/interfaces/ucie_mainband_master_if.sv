// =============================================================================
//  ucie_mainband_master_if
// -----------------------------------------------------------------------------
//  SystemVerilog interface encapsulating Mainband Master Transmit signals
//  (Adapter/TB to PHY downstream path).
// =============================================================================

`timescale 1ns/1ps

interface ucie_mainband_master_if #(
    parameter int FLITW = 512
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

  initial begin
    lp_data  = '0;
    lp_valid = 1'b0;
    lp_irdy  = 1'b0;
  end

endinterface
