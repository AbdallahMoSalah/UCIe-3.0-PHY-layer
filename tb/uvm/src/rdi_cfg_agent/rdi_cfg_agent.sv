// =============================================================================
//  rdi_cfg_agent
// -----------------------------------------------------------------------------
//  Encapsulates driver, monitor, and sequencer for RDI configuration bus.
// =============================================================================

class rdi_cfg_agent extends uvm_agent;
  `uvm_component_utils(rdi_cfg_agent)

  rdi_cfg_agent_config cfg;
  
  rdi_cfg_sequencer    sequencer;
  rdi_cfg_driver       driver;
  rdi_cfg_monitor      monitor;

  // Analysis ports exposed to env
  uvm_analysis_port#(rdi_cfg_seq_item) ap_tx;  // Downstream cross-die transactions
  uvm_analysis_port#(rdi_cfg_seq_item) ap_rx;  // Upstream cross-die transactions
  uvm_analysis_port#(rdi_cfg_seq_item) ap_ral; // Local RAL predictor transactions
  uvm_analysis_port#(rdi_cfg_seq_item) ap;     // Alias to ap_ral for backward compatibility

  function new(string name = "rdi_cfg_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if (!uvm_config_db#(rdi_cfg_agent_config)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("AGT_ERR", "Failed to retrieve configuration 'cfg'")
    end

    // Monitor is always instantiated
    monitor = rdi_cfg_monitor::type_id::create("monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      sequencer = rdi_cfg_sequencer::type_id::create("sequencer", this);
      driver    = rdi_cfg_driver::type_id::create("driver", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    
    // Bind monitor analysis ports to agent-level analysis ports
    ap_tx  = monitor.ap_tx;
    ap_rx  = monitor.ap_rx;
    ap_ral = monitor.ap_ral;
    ap     = monitor.ap;

    if (cfg.is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass
