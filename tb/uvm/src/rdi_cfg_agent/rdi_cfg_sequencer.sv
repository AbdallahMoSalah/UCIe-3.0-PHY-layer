// =============================================================================
//  rdi_cfg_sequencer
// -----------------------------------------------------------------------------
//  Sequencer classes managing transaction queues for the RDI Config agents.
// =============================================================================

class rdi_cfg_sequencer extends uvm_sequencer #(rdi_cfg_seq_item);
  `uvm_component_utils(rdi_cfg_sequencer)

  function new(string name = "rdi_cfg_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class rdi_cfg_sequencer_master extends rdi_cfg_sequencer;
  `uvm_component_utils(rdi_cfg_sequencer_master)

  function new(string name = "rdi_cfg_sequencer_master", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class rdi_cfg_sequencer_slave extends rdi_cfg_sequencer;
  `uvm_component_utils(rdi_cfg_sequencer_slave)

  function new(string name = "rdi_cfg_sequencer_slave", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass
