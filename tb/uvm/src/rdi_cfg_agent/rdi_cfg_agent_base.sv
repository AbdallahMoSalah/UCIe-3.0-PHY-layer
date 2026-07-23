// =============================================================================
//  rdi_cfg_agent_base
// -----------------------------------------------------------------------------
//  Base class for RDI Config Agents. Instantiates monitor, driver, sequencer,
//  and coverage components. Master and Slave subclasses configure factory
//  instance overrides in their constructors to substitute specialized types.
// =============================================================================

class rdi_cfg_agent_base extends uvm_agent;
  `uvm_component_utils(rdi_cfg_agent_base)

  rdi_cfg_agent_config cfg;

  rdi_cfg_sequencer    sequencer;
  rdi_cfg_driver       driver;
  rdi_cfg_monitor      monitor;
  rdi_cfg_coverage     coverage;

  function new(string name = "rdi_cfg_agent_base", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null) begin
      if (!uvm_config_db#(rdi_cfg_agent_config)::get(this, "", "cfg", cfg)) begin
        `uvm_fatal("AGT_ERR", "Failed to retrieve configuration 'cfg'")
      end
    end

    // Monitor and Coverage are built by default
    monitor = rdi_cfg_monitor::type_id::create("monitor", this);

    if (cfg.get_has_coverage()) begin
      coverage = rdi_cfg_coverage::type_id::create("coverage", this);
    end

    if (cfg.get_active_passive() == UVM_ACTIVE) begin
      sequencer = rdi_cfg_sequencer::type_id::create("sequencer", this);
      driver    = rdi_cfg_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Explicitly propagate config and vif handles to child components
    if (monitor != null) begin
      monitor.agent_config = cfg;
      monitor.vif          = cfg.get_vif();
    end

    if (coverage != null && cfg.get_has_coverage()) begin
      coverage.agent_config = cfg;
    end

    if (cfg.get_active_passive() == UVM_ACTIVE && driver != null) begin
      driver.agent_config = cfg;
      driver.vif          = cfg.get_vif();
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass
