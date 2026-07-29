// =============================================================================
//  rdi_cfg_agent_master
// -----------------------------------------------------------------------------
//  Master agent for downstream configuration path (Adapter -> PHY / RX side into RTL).
//  Uses UVM factory instance overrides to substitute master driver, monitor, and sequencer.
// =============================================================================

class rdi_cfg_agent_master extends rdi_cfg_agent_base;
  `uvm_component_utils(rdi_cfg_agent_master)

  // Analysis port exposing monitored RX request transactions
  uvm_analysis_port#(rdi_cfg_seq_item_mon) ap_rx;

  function new(string name = "rdi_cfg_agent_master", uvm_component parent = null);
    super.new(name, parent);

    rdi_cfg_driver::type_id::set_inst_override(rdi_cfg_driver_master::get_type(), "driver", this);
    rdi_cfg_monitor::type_id::set_inst_override(rdi_cfg_monitor_master::get_type(), "monitor", this);
    rdi_cfg_sequencer::type_id::set_inst_override(rdi_cfg_sequencer_master::get_type(), "sequencer", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (monitor != null) begin
      ap_rx = monitor.ap;

      if (cfg.get_has_coverage() && coverage != null) begin
        monitor.ap.connect(coverage.analysis_export);
      end
    end
  endfunction

endclass
