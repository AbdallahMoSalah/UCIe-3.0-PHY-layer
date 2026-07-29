// =============================================================================
//  ucie_mainband_agent
// -----------------------------------------------------------------------------
//  Top-level Mainband Agent container for full backward compatibility.
//  Encapsulates both rx_agent (Master Agent, driving downstream flits into RTL)
//  and tx_agent (Slave Agent, monitoring upstream flits out of RTL).
// =============================================================================

class ucie_mainband_agent extends uvm_agent;
  `uvm_component_utils(ucie_mainband_agent)

  ucie_mainband_agent_config cfg;

  // Master and Slave sub-agents
  ucie_mainband_agent_master rx_agent;
  ucie_mainband_agent_slave  tx_agent;

  // Child configuration handles
  ucie_mainband_master_agent_config rx_cfg;
  ucie_mainband_slave_agent_config  tx_cfg;

  // Backward-compatible handles and analysis ports
  ucie_mainband_sequencer                        sequencer;
  uvm_analysis_port#(ucie_mainband_seq_item_mon) ap_rx;  // Downstream Tx flits into RTL (from master rx_agent)
  uvm_analysis_port#(ucie_mainband_seq_item_mon) ap_tx;  // Upstream Rx flits out of RTL (from slave tx_agent)

  function new(string name = "ucie_mainband_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(ucie_mainband_agent_config)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("AGT_ERR", "Failed to retrieve configuration 'cfg'")
    end

    // Create child configuration for Master (rx)
    rx_cfg = ucie_mainband_master_agent_config::type_id::create("rx_cfg");
    rx_cfg.set_vif(cfg.get_vif_master());
    rx_cfg.set_is_active(cfg.get_is_active());
    rx_cfg.set_has_coverage(cfg.get_has_coverage());
    rx_cfg.set_has_checks(cfg.get_has_checks());
    rx_cfg.set_die_idx(cfg.get_die_idx());

    // Create child configuration for Slave (tx) - Passive agent as slave has no driver signals
    tx_cfg = ucie_mainband_slave_agent_config::type_id::create("tx_cfg");
    tx_cfg.set_vif(cfg.get_vif_slave());
    tx_cfg.set_is_active(UVM_PASSIVE);
    tx_cfg.set_has_coverage(cfg.get_has_coverage());
    tx_cfg.set_has_checks(cfg.get_has_checks());
    tx_cfg.set_die_idx(cfg.get_die_idx());

    // Set configuration DB for child sub-agents and their components
    uvm_config_db#(ucie_mainband_master_agent_config)::set(this, "rx_agent*", "cfg", rx_cfg);
    uvm_config_db#(ucie_mainband_slave_agent_config)::set(this, "tx_agent*", "cfg", tx_cfg);

    rx_agent = ucie_mainband_agent_master::type_id::create("rx_agent", this);
    rx_agent.cfg = rx_cfg;

    tx_agent = ucie_mainband_agent_slave::type_id::create("tx_agent", this);
    tx_agent.cfg = tx_cfg;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Bind sub-agent ports and handles to top-level agent
    sequencer = rx_agent.sequencer;
    ap_rx     = rx_agent.ap_rx;  // Downstream Tx flits into RTL (from master rx_agent)
    ap_tx     = tx_agent.ap_tx;  // Upstream Rx flits from RTL (from slave tx_agent)
  endfunction

endclass
