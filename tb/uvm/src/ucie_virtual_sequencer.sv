// =============================================================================
//  ucie_virtual_sequencer
// -----------------------------------------------------------------------------
//  Top-level Virtual Sequencer referencing Sideband CFG and Mainband sequencers.
// =============================================================================

class ucie_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(ucie_virtual_sequencer)

  rdi_cfg_sequencer       rdi_cfg_sqr_L;
  rdi_cfg_sequencer       rdi_cfg_sqr_P;
  ucie_mainband_sequencer mainband_sqr_L;
  ucie_mainband_sequencer mainband_sqr_P;

  function new(string name = "ucie_virtual_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass
