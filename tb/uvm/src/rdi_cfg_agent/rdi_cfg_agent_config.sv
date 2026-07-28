// =============================================================================
//  rdi_cfg_agent_config
// -----------------------------------------------------------------------------
//  Configuration objects for the RDI Config agent architecture.
//
//  - rdi_cfg_agent_config_base: Common base configuration object containing
//    shared parameters (active_passive, has_coverage, has_checks, die_idx).
//
//  - rdi_cfg_sub_agent_config: Configuration for single-interface sub-agents
//    (Master and Slave agents). Extends rdi_cfg_agent_config_base and holds
//    a single virtual interface handle (vif).
//
//  - rdi_cfg_agent_config: Top-level configuration object for the wrapper
//    agent (rdi_cfg_agent). Extends rdi_cfg_agent_config_base and holds
//    separate RX and TX virtual interfaces (vif_rx, vif_tx).
// =============================================================================

// Common base configuration class for all RDI Config agent configuration objects
class rdi_cfg_agent_config_base extends uvm_object;

  protected uvm_active_passive_enum active_passive = UVM_ACTIVE;
  protected bit                     has_coverage   = 1'b1;
  protected bit                     has_checks     = 1'b1;
  protected int                     die_idx        = 0; // 0 = Local, 1 = Partner

  `uvm_object_utils(rdi_cfg_agent_config_base)

  function new(string name = "rdi_cfg_agent_config_base");
    super.new(name);
  endfunction

  // Getter & Setter for Active/Passive control
  virtual function uvm_active_passive_enum get_active_passive();
    return active_passive;
  endfunction

  virtual function void set_active_passive(uvm_active_passive_enum value);
    active_passive = value;
  endfunction

  // Backward compatibility alias for is_active
  virtual function uvm_active_passive_enum get_is_active();
    return active_passive;
  endfunction

  virtual function void set_is_active(uvm_active_passive_enum value);
    active_passive = value;
  endfunction

  // Getter & Setter for Coverage control
  virtual function bit get_has_coverage();
    return has_coverage;
  endfunction

  virtual function void set_has_coverage(bit value);
    has_coverage = value;
  endfunction

  // Getter & Setter for Checks control
  virtual function bit get_has_checks();
    return has_checks;
  endfunction

  virtual function void set_has_checks(bit value);
    has_checks = value;
  endfunction

  // Getter & Setter for Die Index
  virtual function int get_die_idx();
    return die_idx;
  endfunction

  virtual function void set_die_idx(int value);
    die_idx = value;
  endfunction

endclass

// Sub-agent configuration object for single-interface sub-agents (Master / Slave)
class rdi_cfg_sub_agent_config extends rdi_cfg_agent_config_base;

  protected virtual rdi_cfg_if vif;

  `uvm_object_utils(rdi_cfg_sub_agent_config)

  function new(string name = "rdi_cfg_sub_agent_config");
    super.new(name);
  endfunction

  // Getter & Setter for Virtual Interface
  virtual function virtual rdi_cfg_if get_vif();
    return vif;
  endfunction

  virtual function void set_vif(virtual rdi_cfg_if value);
    vif = value;
  endfunction

  // Task for waiting reset to start
  virtual task wait_reset_start();
    virtual rdi_cfg_if v = get_vif();
    if (v != null && v.rst_n !== 1'b0) begin
      @(negedge v.rst_n);
    end
  endtask

  // Task for waiting reset to be finished
  virtual task wait_reset_end();
    virtual rdi_cfg_if v = get_vif();
    if (v != null) begin
      while (v.rst_n === 1'b0) begin
        @(posedge v.clk);
      end
    end
  endtask

endclass

// Top-level configuration object for the wrapper agent (rdi_cfg_agent)
class rdi_cfg_agent_config extends rdi_cfg_agent_config_base;

  protected virtual rdi_cfg_if vif_rx;
  protected virtual rdi_cfg_if vif_tx;

  `uvm_object_utils(rdi_cfg_agent_config)

  function new(string name = "rdi_cfg_agent_config");
    super.new(name);
  endfunction

  // Getter & Setter for RX Virtual Interface (Downstream: Adapter -> PHY)
  virtual function virtual rdi_cfg_if get_vif_rx();
    return vif_rx;
  endfunction

  virtual function void set_vif_rx(virtual rdi_cfg_if value);
    vif_rx = value;
  endfunction

  // Getter & Setter for TX Virtual Interface (Upstream: PHY -> Adapter)
  virtual function virtual rdi_cfg_if get_vif_tx();
    return vif_tx;
  endfunction

  virtual function void set_vif_tx(virtual rdi_cfg_if value);
    vif_tx = value;
  endfunction

endclass
