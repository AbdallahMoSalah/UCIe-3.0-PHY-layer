// =============================================================================
//  ucie_mainband_agent_slave
// -----------------------------------------------------------------------------
//  Slave agent for upstream Mainband path (PHY -> Adapter).
//  Purely passive sub-agent instantiating slave monitor for Rx flit sampling.
//  No drivers or sequencers required.
// =============================================================================

class ucie_mainband_agent_slave extends uvm_agent implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_agent_slave)

  ucie_mainband_slave_agent_config cfg;

  ucie_mainband_monitor_slave monitor;

  // Analysis port exposing monitored upstream Rx flits coming out of RTL
  uvm_analysis_port#(ucie_mainband_seq_item_mon) ap_tx;

  function new(string name = "ucie_mainband_agent_slave", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (cfg == null) begin
      if (!uvm_config_db#(ucie_mainband_slave_agent_config)::get(this, "", "cfg", cfg)) begin
        `uvm_fatal("AGT_ERR", "Failed to retrieve slave configuration 'cfg'")
      end
    end

    monitor = ucie_mainband_monitor_slave::type_id::create("monitor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (monitor != null) begin
      ap_tx = monitor.ap;
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
