// =============================================================================
//  ucie_mainband_burst_seq
// -----------------------------------------------------------------------------
//  Burst Sequence containing randomized num_packets property, invoking
//  ucie_mainband_single_pkt_seq repeatedly on the target sequencer.
// =============================================================================

class ucie_mainband_burst_seq extends uvm_sequence #(ucie_mainband_seq_item_drv);
  `uvm_object_utils(ucie_mainband_burst_seq)

  rand int num_packets;

  constraint c_num_packets { num_packets inside {[5:20]}; }

  function new(string name = "ucie_mainband_burst_seq");
    super.new(name);
  endfunction

  task body();
    `uvm_info("MB_BURST_SEQ", $sformatf("Starting Mainband burst sequence with %0d packets...", num_packets), UVM_LOW)

    for (int i = 0; i < num_packets; i++) begin
      ucie_mainband_single_pkt_seq single_seq;
      single_seq = ucie_mainband_single_pkt_seq::type_id::create($sformatf("single_seq_%0d", i));
      
      if (!single_seq.randomize()) begin
        `uvm_error("MB_BURST_SEQ", "Failed to randomize single packet sequence")
      end
      
      single_seq.start(m_sequencer, this);
    end

    `uvm_info("MB_BURST_SEQ", $sformatf("Completed Mainband burst sequence of %0d packets", num_packets), UVM_LOW)
  endtask
endclass
