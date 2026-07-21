// =============================================================================
//  ucie_base_test
// -----------------------------------------------------------------------------
//  Base UVM Test class. Resolves virtual interfaces from the Config DB, builds
//  the top environment, and provides init_vseq() to initialize virtual sequences
//  without requiring a physical virtual sequencer component.
// =============================================================================

class ucie_base_test extends uvm_test;
  `uvm_component_utils(ucie_base_test)

  ucie_env                     env;
  
  // Agent configuration handles
  rdi_cfg_agent_config         agent_cfg_L;
  rdi_cfg_agent_config         agent_cfg_P;

  // Virtual interfaces retrieved from top TB
  virtual rdi_cfg_if           vif_cfg_L;
  virtual rdi_cfg_if           vif_cfg_P;
  virtual ucie_ltsm_monitor_if vif_ltsm;
  virtual ucie_channel_if      vif_channel;
  virtual ucie_rdi_if          vif_rdi;

  function new(string name = "ucie_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(100us);

    // 1. Retrieve virtual interfaces from configuration database
    if (!uvm_config_db#(virtual rdi_cfg_if)::get(this, "", "vif_cfg_L", vif_cfg_L))
      `uvm_fatal("TST_ERR", "Failed to retrieve vif_cfg_L from config_db")

    if (!uvm_config_db#(virtual rdi_cfg_if)::get(this, "", "vif_cfg_P", vif_cfg_P))
      `uvm_fatal("TST_ERR", "Failed to retrieve vif_cfg_P from config_db")

    if (!uvm_config_db#(virtual ucie_ltsm_monitor_if)::get(this, "", "vif_ltsm", vif_ltsm))
      `uvm_fatal("TST_ERR", "Failed to retrieve vif_ltsm from config_db")

    if (!uvm_config_db#(virtual ucie_channel_if)::get(this, "", "vif_channel", vif_channel))
      `uvm_fatal("TST_ERR", "Failed to retrieve vif_channel from config_db")

    if (!uvm_config_db#(virtual ucie_rdi_if)::get(this, "", "vif_rdi", vif_rdi))
      `uvm_fatal("TST_ERR", "Failed to retrieve vif_rdi from config_db")

    // 2. Create agent configurations and set interfaces
    agent_cfg_L = rdi_cfg_agent_config::type_id::create("agent_cfg_L");
    agent_cfg_L.vif = vif_cfg_L;
    agent_cfg_L.die_idx = 0;
    agent_cfg_L.is_active = UVM_ACTIVE;
    uvm_config_db#(rdi_cfg_agent_config)::set(this, "env.rdi_cfg_agt_L*", "cfg", agent_cfg_L);

    agent_cfg_P = rdi_cfg_agent_config::type_id::create("agent_cfg_P");
    agent_cfg_P.vif = vif_cfg_P;
    agent_cfg_P.die_idx = 1;
    agent_cfg_P.is_active = UVM_ACTIVE;
    uvm_config_db#(rdi_cfg_agent_config)::set(this, "env.rdi_cfg_agt_P*", "cfg", agent_cfg_P);

    // Pass LTSM virtual interface to passive monitor
    uvm_config_db#(virtual ucie_ltsm_monitor_if)::set(this, "env.ltsm_mon", "vif_ltsm", vif_ltsm);

    // 3. Create the environment
    env = ucie_env::type_id::create("env", this);
  endfunction

  // Binds virtual sequence variables to physical component handles
  virtual function void init_vseq(ucie_vseq_base vseq);
    vseq.cfg_seqr_L  = env.rdi_cfg_agt_L.sequencer;
    vseq.cfg_seqr_P  = env.rdi_cfg_agt_P.sequencer;
    vseq.reg_model_L = env.reg_model_L;
    vseq.reg_model_P = env.reg_model_P;
    vseq.vif_ltsm    = vif_ltsm;
    vseq.vif_channel = vif_channel;
    vseq.vif_rdi      = vif_rdi;
  endfunction

  // Enable UVM report server formatting
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

endclass
