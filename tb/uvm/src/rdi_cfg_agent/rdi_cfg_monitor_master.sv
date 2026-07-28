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
  uvm_analysis_port#(rdi_cfg_seq_item_mon) ap_rx;

  function new(string name = "rdi_cfg_monitor_master", uvm_component parent = null);
    super.new(name, parent);
    ap_rx = new("ap_rx", this);
  endfunction

  protected virtual task collect_transaction();
    monitor_requests();
  endtask

  task monitor_requests();
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
          item.is_response       = 1'b0; // Downstream Request
          item.length            = expected_chunks;
          item.prev_item_delay   = idle_cnt;
          
          `uvm_info("CFG_MON_MASTER", $sformatf("Monitored Downstream Request (Tag %0d, Dstid %0d): %s", 
                    item.tag, item.dstid, item.convert2string()), UVM_HIGH)
          
          ap_rx.write(item);

          // If targeting local PHY registers and request is valid, store for completion matching
          if (item.dstid == sb_pkg::LOCAL_PHY && item.is_reg_req() && item.is_valid_req) begin
            key = {agent_config.get_die_idx(), item.tag};
            pending_reqs[key] = item;
          end

          chunk_idx = 0;
          raw_data  = '0;
          idle_cnt  = 0;
        end
      end
    end
  endtask

endclass
