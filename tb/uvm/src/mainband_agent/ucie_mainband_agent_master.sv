// =============================================================================
//  ucie_mainband_agent_master
// -----------------------------------------------------------------------------
//  Master agent for downstream Mainband path (Adapter -> PHY).
//  Encapsulates master driver, master monitor, and master sequencer.
// =============================================================================

class ucie_mainband_agent_master extends uvm_agent implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_agent_master)

  ucie_mainband_master_agent_config cfg;

  ucie_mainband_master_sequencer sequencer;
  ucie_mainband_driver_master    driver;
  ucie_mainband_monitor_master   monitor;

  // Analysis port exposing monitored downstream Tx flits driven into RTL
  uvm_analysis_port#(ucie_mainband_seq_item_mon) ap_rx;

  function new(string name = "ucie_mainband_agent_master", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null) begin
      if (!uvm_config_db#(ucie_mainband_master_agent_config)::get(this, "", "cfg", cfg)) begin
        `uvm_fatal("AGT_ERR", "Failed to retrieve master configuration 'cfg'")
      end
    end

    monitor = ucie_mainband_monitor_master::type_id::create("monitor", this);

    if (cfg.get_active_passive() == UVM_ACTIVE) begin
      sequencer = ucie_mainband_master_sequencer::type_id::create("sequencer", this);
      driver    = ucie_mainband_driver_master::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (monitor != null) begin
      ap_rx = monitor.ap;
    end

    if (cfg.get_active_passive() == UVM_ACTIVE && driver != null) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      wait_reset_start();
      handle_reset(phase);
      wait_reset_end();
    end
  endtask

  task wait_reset_start();
    if (cfg != null) begin
      cfg.wait_reset_start();
    end
  endtask

  task wait_reset_end();
    if (cfg != null) begin
      cfg.wait_reset_end();
    end
  endtask

  virtual function void handle_reset(uvm_phase phase);
    uvm_component children[$];
    get_children(children);
    foreach (children[idx]) begin
      ucie_mainband_reset_handler handler;
      if ($cast(handler, children[idx])) begin
        handler.handle_reset(phase);
      end
    end
  endfunction

endclass
