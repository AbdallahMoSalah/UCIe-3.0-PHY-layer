// =============================================================================
//  rdi_cfg_agent_config
// -----------------------------------------------------------------------------
//  Configuration object for the RDI Config agent. Contains the virtual interface
//  handle, agent mode (active/passive), and the die index.
// =============================================================================

class rdi_cfg_agent_config extends uvm_object;
  `uvm_object_utils(rdi_cfg_agent_config)

  virtual rdi_cfg_if            vif;
  uvm_active_passive_enum       is_active = UVM_ACTIVE;
  int                           die_idx; // 0 = Local, 1 = Partner

  function new(string name = "rdi_cfg_agent_config");
    super.new(name);
  endfunction
endclass
