// =============================================================================
//  ucie_mainband_reset_handler
// -----------------------------------------------------------------------------
//  Interface class for handling reset events in Mainband agent components.
// =============================================================================

`ifndef UCIE_MAINBAND_RESET_HANDLER_SV
`define UCIE_MAINBAND_RESET_HANDLER_SV

interface class ucie_mainband_reset_handler;
  pure virtual function void handle_reset(uvm_phase phase);
endclass

`endif // UCIE_MAINBAND_RESET_HANDLER_SV
