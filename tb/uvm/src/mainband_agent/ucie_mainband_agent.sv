// =============================================================================
//  ucie_mainband_agent
// -----------------------------------------------------------------------------
//  Standard UVM Agent encapsulating Mainband Driver, Monitor, and Sequencer,
//  implementing top-level reset handling propagation to child components.
// =============================================================================

class ucie_mainband_agent extends uvm_agent implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_agent)

  virtual ucie_mainband_if vif;

  ucie_mainband_driver    driver;
  ucie_mainband_monitor   monitor;
  ucie_mainband_sequencer sequencer;

  function new(string name = "ucie_mainband_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    uvm_config_db#(virtual ucie_mainband_if)::get(this, "", "vif", vif);
    
    monitor = ucie_mainband_monitor::type_id::create("monitor", this);

    if (get_is_active() == UVM_ACTIVE) begin
      driver    = ucie_mainband_driver::type_id::create("driver", this);
      sequencer = ucie_mainband_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
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
    if (vif != null && vif.rst_n !== 1'b0) begin
      @(negedge vif.rst_n);
    end
  endtask

  task wait_reset_end();
    if (vif != null) begin
      while (vif.rst_n == 1'b0) begin
        @(posedge vif.clk);
      end
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
