// =============================================================================
//  rdi_cfg_agent
// -----------------------------------------------------------------------------
//  Top-level RDI Config Agent container for full backward compatibility.
//  Encapsulates both rx_agent (Master Agent, driving requests into RTL)
//  and tx_agent (Slave Agent, monitoring responses out of RTL).
// =============================================================================

class rdi_cfg_agent extends uvm_agent;
  `uvm_component_utils(rdi_cfg_agent)

  rdi_cfg_agent_config cfg;

  // Master and Slave sub-agents
  rdi_cfg_agent_master rx_agent;
  rdi_cfg_agent_slave  tx_agent;

  // Child configuration handles
  rdi_cfg_agent_config rx_cfg;
  rdi_cfg_agent_config tx_cfg;

  // Backward-compatible handles and analysis ports
  rdi_cfg_sequencer                    sequencer;
  uvm_analysis_port#(rdi_cfg_seq_item) ap_tx;  // Downstream requests into RTL (from rx_agent)
  uvm_analysis_port#(rdi_cfg_seq_item) ap_rx;  // Upstream responses out of RTL (from tx_agent)
  uvm_analysis_port#(rdi_cfg_seq_item) ap_ral; // Local RAL predictor updates (from tx_agent)
  uvm_analysis_port#(rdi_cfg_seq_item) ap;     // Alias to ap_ral

  function new(string name = "rdi_cfg_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(rdi_cfg_agent_config)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("AGT_ERR", "Failed to retrieve configuration 'cfg'")
    end

    // Create child configurations for Master (rx) and Slave (tx)
    rx_cfg = rdi_cfg_agent_config::type_id::create("rx_cfg");
    rx_cfg.set_vif(cfg.get_vif_rx());
    rx_cfg.set_vif_rx(cfg.get_vif_rx());
    rx_cfg.set_vif_tx(cfg.get_vif_tx());
    rx_cfg.set_is_active(cfg.get_is_active());
    rx_cfg.set_has_coverage(cfg.get_has_coverage());
    rx_cfg.set_has_checks(cfg.get_has_checks());
    rx_cfg.set_die_idx(cfg.get_die_idx());

    tx_cfg = rdi_cfg_agent_config::type_id::create("tx_cfg");
    tx_cfg.set_vif(cfg.get_vif_tx());
    tx_cfg.set_vif_rx(cfg.get_vif_rx());
    tx_cfg.set_vif_tx(cfg.get_vif_tx());
    tx_cfg.set_is_active(cfg.get_is_active());
    tx_cfg.set_has_coverage(cfg.get_has_coverage());
    tx_cfg.set_has_checks(cfg.get_has_checks());
    tx_cfg.set_die_idx(cfg.get_die_idx());

    // Set configuration DB for child sub-agents and their components
    uvm_config_db#(rdi_cfg_agent_config)::set(this, "rx_agent*", "cfg", rx_cfg);
    uvm_config_db#(rdi_cfg_agent_config)::set(this, "tx_agent*", "cfg", tx_cfg);

    rx_agent = rdi_cfg_agent_master::type_id::create("rx_agent", this);
    rx_agent.cfg = rx_cfg;

    tx_agent = rdi_cfg_agent_slave::type_id::create("tx_agent", this);
    tx_agent.cfg = tx_cfg;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Bind sub-agent ports and handles to top-level agent
    sequencer = rx_agent.sequencer;
    ap_tx     = rx_agent.ap_rx;   // Transmitted requests into RTL (from master rx_agent)
    ap_rx     = tx_agent.ap_tx;   // Received responses from RTL (from slave tx_agent)
    ap_ral    = tx_agent.ap_ral;  // Slave monitor ap_ral (local completions)
    ap        = ap_ral;
  endfunction

endclass
