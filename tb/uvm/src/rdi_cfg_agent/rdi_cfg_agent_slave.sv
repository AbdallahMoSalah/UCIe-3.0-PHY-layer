// =============================================================================
//  rdi_cfg_agent_slave
// -----------------------------------------------------------------------------
//  Slave agent for upstream configuration path (PHY -> Adapter / TX side from RTL).
//  Uses UVM factory instance overrides to substitute slave driver, monitor, and sequencer.
// =============================================================================

class rdi_cfg_agent_slave extends rdi_cfg_agent_base;
  `uvm_component_utils(rdi_cfg_agent_slave)

  // Analysis ports exposing monitored TX packets and RAL predictor completions
  uvm_analysis_port#(rdi_cfg_seq_item) ap_tx;
  uvm_analysis_port#(rdi_cfg_seq_item) ap_ral;

  function new(string name = "rdi_cfg_agent_slave", uvm_component parent = null);
    super.new(name, parent);

    rdi_cfg_driver::type_id::set_inst_override(rdi_cfg_driver_slave::get_type(), "driver", this);
    rdi_cfg_monitor::type_id::set_inst_override(rdi_cfg_monitor_slave::get_type(), "monitor", this);
    rdi_cfg_sequencer::type_id::set_inst_override(rdi_cfg_sequencer_slave::get_type(), "sequencer", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    rdi_cfg_monitor_slave mon_slave;
    super.connect_phase(phase);

    if ($cast(mon_slave, monitor)) begin
      ap_tx  = mon_slave.ap_tx;
      ap_ral = mon_slave.ap_ral;

      if (cfg.get_has_coverage() && coverage != null) begin
        mon_slave.ap_tx.connect(coverage.analysis_export);
      end
    end else begin
      `uvm_fatal("CAST_ERR", "Failed to cast monitor to rdi_cfg_monitor_slave")
    end
  endfunction

endclass
