// =============================================================================
//  rdi_cfg_reset_handler
// -----------------------------------------------------------------------------
//  Interface class for handling reset events in RDI Config agent components.
// =============================================================================

`ifndef RDI_CFG_RESET_HANDLER_SV
`define RDI_CFG_RESET_HANDLER_SV

interface class rdi_cfg_reset_handler;
  pure virtual function void handle_reset(uvm_phase phase);
endclass

`endif // RDI_CFG_RESET_HANDLER_SV
