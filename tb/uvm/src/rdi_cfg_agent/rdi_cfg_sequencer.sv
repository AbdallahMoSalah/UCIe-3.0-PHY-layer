// =============================================================================
//  rdi_cfg_sequencer
// -----------------------------------------------------------------------------
//  Sequencer classes managing transaction queues for the RDI Config agents.
// =============================================================================

class rdi_cfg_sequencer extends uvm_sequencer #(rdi_cfg_seq_item) implements rdi_cfg_reset_handler;
  `uvm_component_utils(rdi_cfg_sequencer)

  function new(string name = "rdi_cfg_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void handle_reset(uvm_phase phase);
    int objections_count;

    stop_sequences();

    objections_count = uvm_test_done.get_objection_count(this);
    if (objections_count > 0) begin
      uvm_test_done.drop_objection(this, $sformatf("Dropping %0d objections at reset", objections_count), objections_count);
    end

    start_phase_sequence(phase);
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
