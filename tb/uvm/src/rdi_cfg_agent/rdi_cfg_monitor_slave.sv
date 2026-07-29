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

  // Analysis port exposing RAL predictor completions
  uvm_analysis_port#(rdi_cfg_seq_item_mon) ap_ral;

  function new(string name = "rdi_cfg_monitor_slave", uvm_component parent = null);
    super.new(name, parent);
    ap_ral = new("ap_ral", this);
  endfunction

  protected virtual function bit is_response_direction();
    return 1'b1;
  endfunction

  protected virtual function void process_monitored_item(rdi_cfg_seq_item_mon item);
    bit [5:0] key;

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
  endfunction

endclass
