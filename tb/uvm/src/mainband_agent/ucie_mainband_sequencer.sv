// =============================================================================
//  ucie_mainband_sequencer
// -----------------------------------------------------------------------------
//  Sequencer managing transaction queues for the Mainband Master agent.
// =============================================================================

class ucie_mainband_master_sequencer extends uvm_sequencer #(ucie_mainband_seq_item_drv) implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_master_sequencer)

  function new(string name = "ucie_mainband_master_sequencer", uvm_component parent = null);
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

// Alias for default sequencer handle compatibility
typedef ucie_mainband_master_sequencer ucie_mainband_sequencer;
