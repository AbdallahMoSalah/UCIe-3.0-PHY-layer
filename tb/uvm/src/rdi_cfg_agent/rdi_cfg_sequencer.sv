// =============================================================================
//  rdi_cfg_sequencer
// -----------------------------------------------------------------------------
//  Sequencer class managing transaction queues for the RDI Config agent.
// =============================================================================

class rdi_cfg_sequencer extends uvm_sequencer #(rdi_cfg_seq_item);
  `uvm_component_utils(rdi_cfg_sequencer)

  function new(string name = "rdi_cfg_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass
