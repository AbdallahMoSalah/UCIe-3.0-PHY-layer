// =============================================================================
//  rdi_cfg_monitor_slave
// -----------------------------------------------------------------------------
//  Monitors upstream configuration path (PHY -> Adapter).
//  Collects response/message packets, matches completions against the static
//  pending_reqs table keyed by {die_idx, tag} to update ap_ral for the RAL predictor,
//  and broadcasts cross-die packets on ap_tx.
// =============================================================================

class rdi_cfg_monitor_slave extends rdi_cfg_monitor;
  `uvm_component_utils(rdi_cfg_monitor_slave)

  // Analysis ports exposing monitored TX packets and RAL predictor completions
  uvm_analysis_port#(rdi_cfg_seq_item) ap_tx;
  uvm_analysis_port#(rdi_cfg_seq_item) ap_ral;

  function new(string name = "rdi_cfg_monitor_slave", uvm_component parent = null);
    super.new(name, parent);
    ap_tx  = new("ap_tx", this);
    ap_ral = new("ap_ral", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (agent_config != null) begin
      vif = agent_config.get_vif_tx();
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
          item.is_response       = 1'b1; // Upstream Response/Message

          `uvm_info("CFG_MON_SLAVE", $sformatf("Monitored Upstream Packet (Tag %0d, Opcode %0s): %s", 
                    item.tag, item.opcode.name(), item.convert2string()), UVM_HIGH)

          ap_tx.write(item);

          // Local PHY Completion matching for RAL predictor
          // Local PHY Completion matching vs Cross-Die packet routing
          key = {agent_config.get_die_idx(), item.tag};
          if (item.opcode inside {
            sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA,
            sb_pkg::SB_COMPLETION_WITHOUT_DATA
          } && pending_reqs.exists(key)) begin
            item.addr = pending_reqs[key].addr;
            pending_reqs.delete(key);

            ap_ral.write(item);
          end

          chunk_idx = 0;
          raw_data  = '0;
        end
      end
    end
  endtask

endclass
