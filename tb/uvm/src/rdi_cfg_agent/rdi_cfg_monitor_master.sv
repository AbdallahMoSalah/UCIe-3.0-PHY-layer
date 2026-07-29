// =============================================================================
//  rdi_cfg_monitor_master
// -----------------------------------------------------------------------------
//  Monitors downstream configuration path (Adapter -> PHY).
//  Collects request packets, registers local PHY requests into static pending_reqs
//  table keyed by {die_idx, tag}, and broadcasts cross-die requests on ap_rx.
// =============================================================================

class rdi_cfg_monitor_master extends rdi_cfg_monitor;
  `uvm_component_utils(rdi_cfg_monitor_master)

  function new(string name = "rdi_cfg_monitor_master", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  protected virtual function bit is_response_direction();
    return 1'b0;
  endfunction

  protected virtual function void process_monitored_item(rdi_cfg_seq_item_mon item);
    bit [5:0] key;

    `uvm_info("CFG_MON_MASTER", $sformatf("Monitored Downstream Request (Tag %0d, Dstid %0d): %s", 
              item.tag, item.dstid, item.convert2string()), UVM_HIGH)

    // If targeting local PHY registers and request is valid, store for completion matching
    if (item.dstid == sb_pkg::LOCAL_PHY && item.is_reg_req() && item.is_valid_req) begin
      key = {agent_config.get_die_idx(), item.tag};
      pending_reqs[key] = item;
    end
  endfunction

endclass
