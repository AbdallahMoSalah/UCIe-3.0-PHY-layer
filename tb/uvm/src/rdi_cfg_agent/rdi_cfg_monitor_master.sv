// =============================================================================
//  rdi_cfg_monitor_master
// -----------------------------------------------------------------------------
//  Monitors downstream configuration path (Adapter -> PHY).
//  Collects request packets, registers local PHY requests into static pending_reqs
//  table keyed by {die_idx, tag}, and broadcasts cross-die requests on ap_rx.
// =============================================================================

class rdi_cfg_monitor_master extends rdi_cfg_monitor;
  `uvm_component_utils(rdi_cfg_monitor_master)

  // Analysis port exposing monitored RX requests
  uvm_analysis_port#(rdi_cfg_seq_item) ap_rx;

  function new(string name = "rdi_cfg_monitor_master", uvm_component parent = null);
    super.new(name, parent);
    ap_rx = new("ap_rx", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (agent_config != null) begin
      vif = agent_config.get_vif_rx();
    end
  endfunction

  task run_phase(uvm_phase phase);
    bit [127:0]          raw_data = '0;
    int                  chunk_idx = 0;
    int                  expected_chunks = 2;
    sb_pkg::sb_opcode_e  opcode;
    bit [5:0]            key;

    wait(vif.rst_n === 1'b1);

    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.cfg_vld) begin
        raw_data[chunk_idx*32 +: 32] = vif.mon_cb.cfg;
        if (chunk_idx == 0) begin
          opcode = sb_pkg::sb_opcode_e'(vif.mon_cb.cfg[4:0]);
          expected_chunks = get_expected_chunks(opcode);
        end
        chunk_idx++;

        if (chunk_idx == expected_chunks) begin
          rdi_cfg_seq_item item = rdi_cfg_seq_item::type_id::create("item");
          item.sb_pkt.header.raw = raw_data[63:0];
          item.sb_pkt.payload    = raw_data[127:64];
          item.unpack_from_struct();
          item.is_response       = 1'b0; // Downstream Request
          
          `uvm_info("CFG_MON_MASTER", $sformatf("Monitored Downstream Request (Tag %0d, Dstid %0d): %s", 
                    item.tag, item.dstid, item.convert2string()), UVM_HIGH)
          
          ap_rx.write(item);

          // If targeting local PHY registers, store for completion matching
          if (item.dstid == sb_pkg::LOCAL_PHY) begin
            key = {agent_config.get_die_idx(), item.tag};
            pending_reqs[key] = item;
          end

          chunk_idx = 0;
          raw_data  = '0;
        end
      end
    end
  endtask

endclass
