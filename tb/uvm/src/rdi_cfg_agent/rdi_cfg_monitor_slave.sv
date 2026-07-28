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
  uvm_analysis_port#(rdi_cfg_seq_item_mon) ap_tx;
  uvm_analysis_port#(rdi_cfg_seq_item_mon) ap_ral;

  function new(string name = "rdi_cfg_monitor_slave", uvm_component parent = null);
    super.new(name, parent);
    ap_tx  = new("ap_tx", this);
    ap_ral = new("ap_ral", this);
  endfunction

  protected virtual task collect_transaction();
    monitor_responses();
  endtask

  task monitor_responses();
    bit [127:0]          raw_data = '0;
    int                  chunk_idx = 0;
    int                  expected_chunks = 2;
    sb_pkg::sb_opcode_e  opcode;
    bit [5:0]            key;
    int unsigned         idle_cnt = 0;

    forever begin
      @(vif.mon_cb);
      if (!vif.mon_cb.cfg_vld) begin
        if (chunk_idx == 0) begin
          idle_cnt++;
        end
      end else begin
        raw_data[chunk_idx*32 +: 32] = vif.mon_cb.cfg;
        if (chunk_idx == 0) begin
          opcode = sb_pkg::sb_opcode_e'(vif.mon_cb.cfg[4:0]);
          expected_chunks = get_expected_chunks(opcode);
        end
        chunk_idx++;

        if (chunk_idx == expected_chunks) begin
          rdi_cfg_seq_item_mon item = rdi_cfg_seq_item_mon::type_id::create("item");
          item.sb_pkt.header.raw = raw_data[63:0];
          item.sb_pkt.payload    = raw_data[127:64];
          item.unpack_from_struct();
          item.is_response       = 1'b1; // Upstream Response/Message
          item.length            = expected_chunks;
          item.prev_item_delay   = idle_cnt;

          `uvm_info("CFG_MON_SLAVE", $sformatf("Monitored Upstream Packet (Tag %0d, Opcode %0s): %s", 
                    item.tag, item.opcode.name(), item.convert2string()), UVM_HIGH)

          // Local PHY Completion matching for RAL predictor
          key = {agent_config.get_die_idx(), item.tag};
          if (item.dstid == 3'b000 && item.opcode inside {
            sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA,
            sb_pkg::SB_COMPLETION_WITHOUT_DATA
          } && pending_reqs.exists(key)) begin
            item.addr = pending_reqs[key].addr;
            pending_reqs.delete(key);

            ap_ral.write(item);
          end

          ap_tx.write(item);

          chunk_idx = 0;
          raw_data  = '0;
          idle_cnt  = 0;
        end
      end
    end
  endtask

endclass
