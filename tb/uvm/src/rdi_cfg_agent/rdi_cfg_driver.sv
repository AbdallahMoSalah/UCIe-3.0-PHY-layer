// =============================================================================
//  rdi_cfg_driver
// -----------------------------------------------------------------------------
//  Base driver class for RDI Config Agent. Contains agent configuration reference
//  and virtual interface handle.
// =============================================================================

class rdi_cfg_driver extends uvm_driver #(rdi_cfg_seq_item);
  `uvm_component_utils(rdi_cfg_driver)

  rdi_cfg_agent_config agent_config;
  virtual rdi_cfg_if   vif;

  function new(string name = "rdi_cfg_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(rdi_cfg_agent_config)::get(this, "", "cfg", agent_config)) begin
      `uvm_fatal("DRV_ERR", "Failed to retrieve agent configuration 'agent_config'")
    end
    vif = agent_config.get_vif();
  endfunction

endclass
