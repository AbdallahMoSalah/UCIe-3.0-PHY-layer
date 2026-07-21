// =============================================================================
//  ucie_mainband_sequencer
// -----------------------------------------------------------------------------
//  Sequencer for Mainband driver sequence items (ucie_mainband_seq_item_drv)
//  implementing ucie_mainband_reset_handler to stop active sequences and clear
//  objections upon reset events.
// =============================================================================

class ucie_mainband_sequencer extends uvm_sequencer #(ucie_mainband_seq_item_drv) implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_sequencer)

  function new(string name = "ucie_mainband_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void handle_reset(uvm_phase phase);
    int objections_count;
    
    // Stop all active sequences running on this sequencer
    stop_sequences();
    
    // Drop any outstanding objections held by this sequencer
    objections_count = uvm_test_done.get_objection_count(this);
    if (objections_count > 0) begin
      uvm_test_done.drop_objection(this, $sformatf("Dropping %0d objections at reset", objections_count), objections_count);
    end

    start_phase_sequence(phase);
  endfunction

endclass
