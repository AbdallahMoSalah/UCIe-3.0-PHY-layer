// =============================================================================
//  ucie_mainband_agent_config
// -----------------------------------------------------------------------------
//  Configuration objects for the Mainband agent architecture.
//
//  - ucie_mainband_agent_config_base: Common base configuration class containing
//    shared parameters (active_passive, has_coverage, has_checks, die_idx).
//
//  - ucie_mainband_master_agent_config: Configuration for Master sub-agent
//    holding virtual handle to ucie_mainband_master_if (Adapter -> PHY).
//
//  - ucie_mainband_slave_agent_config: Configuration for Slave sub-agent
//    holding virtual handle to ucie_mainband_slave_if (PHY -> Adapter).
//
//  - ucie_mainband_agent_config: Top-level configuration object for wrapper agent
//    (ucie_mainband_agent) holding both Master and Slave virtual interfaces.
// =============================================================================

// Common base configuration class for all Mainband agent configuration objects
class ucie_mainband_agent_config_base extends uvm_object;

  protected uvm_active_passive_enum active_passive = UVM_ACTIVE;
  protected bit                     has_coverage   = 1'b1;
  protected bit                     has_checks     = 1'b1;
  protected int                     die_idx        = 0; // 0 = Local, 1 = Partner

  `uvm_object_utils(ucie_mainband_agent_config_base)

  function new(string name = "ucie_mainband_agent_config_base");
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

// Configuration object for Master sub-agent (downstream transmit path)
class ucie_mainband_master_agent_config extends ucie_mainband_agent_config_base;

  protected virtual ucie_mainband_master_if vif;

  `uvm_object_utils(ucie_mainband_master_agent_config)

  function new(string name = "ucie_mainband_master_agent_config");
    super.new(name);
  endfunction

  virtual function virtual ucie_mainband_master_if get_vif();
    return vif;
  endfunction

  virtual function void set_vif(virtual ucie_mainband_master_if value);
    vif = value;
  endfunction

  virtual task wait_reset_start();
    virtual ucie_mainband_master_if v = get_vif();
    if (v != null && v.rst_n !== 1'b0) begin
      @(negedge v.rst_n);
    end
  endtask

  virtual task wait_reset_end();
    virtual ucie_mainband_master_if v = get_vif();
    if (v != null) begin
      while (v.rst_n === 1'b0) begin
        @(posedge v.clk);
      end
    end
  endtask

endclass

// Configuration object for Slave sub-agent (upstream receive path)
class ucie_mainband_slave_agent_config extends ucie_mainband_agent_config_base;

  protected virtual ucie_mainband_slave_if vif;

  `uvm_object_utils(ucie_mainband_slave_agent_config)

  function new(string name = "ucie_mainband_slave_agent_config");
    super.new(name);
    active_passive = UVM_PASSIVE;
  endfunction

  virtual function virtual ucie_mainband_slave_if get_vif();
    return vif;
  endfunction

  virtual function void set_vif(virtual ucie_mainband_slave_if value);
    vif = value;
  endfunction

  virtual task wait_reset_start();
    virtual ucie_mainband_slave_if v = get_vif();
    if (v != null && v.rst_n !== 1'b0) begin
      @(negedge v.rst_n);
    end
  endtask

  virtual task wait_reset_end();
    virtual ucie_mainband_slave_if v = get_vif();
    if (v != null) begin
      while (v.rst_n === 1'b0) begin
        @(posedge v.clk);
      end
    end
  endtask

endclass

// Top-level configuration object for wrapper agent (ucie_mainband_agent)
class ucie_mainband_agent_config extends ucie_mainband_agent_config_base;

  protected virtual ucie_mainband_master_if vif_master;
  protected virtual ucie_mainband_slave_if  vif_slave;

  `uvm_object_utils(ucie_mainband_agent_config)

  function new(string name = "ucie_mainband_agent_config");
    super.new(name);
  endfunction

  virtual function virtual ucie_mainband_master_if get_vif_master();
    return vif_master;
  endfunction

  virtual function void set_vif_master(virtual ucie_mainband_master_if value);
    vif_master = value;
  endfunction

  virtual function virtual ucie_mainband_slave_if get_vif_slave();
    return vif_slave;
  endfunction

  virtual function void set_vif_slave(virtual ucie_mainband_slave_if value);
    vif_slave = value;
  endfunction

endclass
