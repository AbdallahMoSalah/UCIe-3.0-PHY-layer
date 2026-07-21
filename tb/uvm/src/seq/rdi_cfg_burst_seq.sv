// =============================================================================
//  rdi_cfg_burst_seq
// -----------------------------------------------------------------------------
//  Burst Sequence generating a randomized sequence of Sideband remote messages.
// =============================================================================

class rdi_cfg_burst_seq extends uvm_sequence #(rdi_cfg_seq_item);
  `uvm_object_utils(rdi_cfg_burst_seq)

  rand int num_packets;

  constraint c_num_packets { num_packets inside {[3:10]}; }

  function new(string name = "rdi_cfg_burst_seq");
    super.new(name);
  endfunction

  task body();
    `uvm_info("SB_BURST_SEQ", $sformatf("Starting Sideband remote message burst sequence with %0d packets...", num_packets), UVM_LOW)

    for (int i = 0; i < num_packets; i++) begin
      rdi_cfg_single_pkt_seq single_seq;
      single_seq = rdi_cfg_single_pkt_seq::type_id::create($sformatf("single_seq_%0d", i));
      
      if (!single_seq.randomize()) begin
        `uvm_error("SB_BURST_SEQ", "Failed to randomize single Sideband packet sequence")
      end
      
      single_seq.start(m_sequencer, this);
    end

    `uvm_info("SB_BURST_SEQ", $sformatf("Completed Sideband remote message burst sequence of %0d packets", num_packets), UVM_LOW)
  endtask
endclass
