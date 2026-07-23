// =============================================================================
//  rdi_cfg_agent_config
// -----------------------------------------------------------------------------
//  Configuration object for the RDI Config agent. Contains virtual interface
//  handles (vif, vif_rx, vif_tx), agent mode (active/passive), coverage control,
//  checks, and die index.
// =============================================================================

class rdi_cfg_agent_config extends uvm_object;

  protected virtual rdi_cfg_if      vif;
  protected virtual rdi_cfg_if      vif_rx;
  protected virtual rdi_cfg_if      vif_tx;
  protected uvm_active_passive_enum active_passive = UVM_ACTIVE;
  protected bit                     has_coverage   = 1'b1;
  protected bit                     has_checks     = 1'b1;
  protected int                     die_idx        = 0; // 0 = Local, 1 = Partner

  `uvm_object_utils(rdi_cfg_agent_config)

  function new(string name = "rdi_cfg_agent_config");
    super.new(name);
  endfunction

  // Getter & Setter for Default Virtual Interface
  virtual function virtual rdi_cfg_if get_vif();
    if (vif != null)    return vif;
    if (vif_rx != null) return vif_rx;
    return vif_tx;
  endfunction

  virtual function void set_vif(virtual rdi_cfg_if value);
    vif = value;
  endfunction

  // Getter & Setter for RX Virtual Interface (Downstream: Adapter -> PHY)
  virtual function virtual rdi_cfg_if get_vif_rx();
    if (vif_rx != null) return vif_rx;
    return vif;
  endfunction

  virtual function void set_vif_rx(virtual rdi_cfg_if value);
    vif_rx = value;
  endfunction

  // Getter & Setter for TX Virtual Interface (Upstream: PHY -> Adapter)
  virtual function virtual rdi_cfg_if get_vif_tx();
    if (vif_tx != null) return vif_tx;
    return vif;
  endfunction

  virtual function void set_vif_tx(virtual rdi_cfg_if value);
    vif_tx = value;
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

class rdi_cfg_agent_config_master extends rdi_cfg_agent_config;
  `uvm_object_utils(rdi_cfg_agent_config_master)

  function new(string name = "rdi_cfg_agent_config_master");
    super.new(name);
  endfunction

  virtual function virtual rdi_cfg_if get_vif();
    return get_vif_rx();
  endfunction
endclass

class rdi_cfg_agent_config_slave extends rdi_cfg_agent_config;
  `uvm_object_utils(rdi_cfg_agent_config_slave)

  function new(string name = "rdi_cfg_agent_config_slave");
    super.new(name);
  endfunction

  virtual function virtual rdi_cfg_if get_vif();
    return get_vif_tx();
  endfunction
endclass
