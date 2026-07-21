// =============================================================================
//  ucie_env
// -----------------------------------------------------------------------------
//  Top-level UVM Environment containing Local (Die 0) and Partner (Die 1) 
//  agents, register blocks, predictors, passive monitors, and the coverage component.
// =============================================================================

class ucie_env extends uvm_env;
  `uvm_component_utils(ucie_env)

  // Config agents
  rdi_cfg_agent                 rdi_cfg_agt_L;
  rdi_cfg_agent                 rdi_cfg_agt_P;

  // Mainband agents for Die 0 (Local) and Die 1 (Partner)
  ucie_mainband_agent           mainband_agt_L;
  ucie_mainband_agent           mainband_agt_P;

  // Register Blocks (RAL)
  ucie_reg_block                reg_model_L;
  ucie_reg_block                reg_model_P;

  // RAL Predictors and Adapters
  uvm_reg_predictor#(rdi_cfg_seq_item) predictor_L;
  uvm_reg_predictor#(rdi_cfg_seq_item) predictor_P;
  reg2rdi_cfg_adapter           adapter_L;
  reg2rdi_cfg_adapter           adapter_P;

  // Passive LTSM Monitor, Coverage, Scoreboard, and Virtual Sequencer
  ucie_ltsm_monitor             ltsm_mon;
  ucie_ltsm_coverage            ltsm_cov;
  ucie_scoreboard               scoreboard;
  ucie_virtual_sequencer        vsqr;

  function new(string name = "ucie_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Create configuration agents
    rdi_cfg_agt_L = rdi_cfg_agent::type_id::create("rdi_cfg_agt_L", this);
    rdi_cfg_agt_P = rdi_cfg_agent::type_id::create("rdi_cfg_agt_P", this);

    // Create Mainband agents
    mainband_agt_L = ucie_mainband_agent::type_id::create("mainband_agt_L", this);
    mainband_agt_P = ucie_mainband_agent::type_id::create("mainband_agt_P", this);

    // Create Virtual Sequencer and Scoreboard
    vsqr       = ucie_virtual_sequencer::type_id::create("vsqr", this);
    scoreboard = ucie_scoreboard::type_id::create("scoreboard", this);

    // Build Register Blocks
    reg_model_L = ucie_reg_block::type_id::create("reg_model_L", this);
    reg_model_L.build();
    
    reg_model_P = ucie_reg_block::type_id::create("reg_model_P", this);
    reg_model_P.build();

    // Create Predictors and Adapters
    predictor_L = uvm_reg_predictor#(rdi_cfg_seq_item)::type_id::create("predictor_L", this);
    predictor_P = uvm_reg_predictor#(rdi_cfg_seq_item)::type_id::create("predictor_P", this);
    adapter_L   = reg2rdi_cfg_adapter::type_id::create("adapter_L");
    adapter_P   = reg2rdi_cfg_adapter::type_id::create("adapter_P");

    // Create FSM monitor and coverage components
    ltsm_mon = ucie_ltsm_monitor::type_id::create("ltsm_mon", this);
    ltsm_cov = ucie_ltsm_coverage::type_id::create("ltsm_cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // 1. Connect Local (Die 0) Sequencer and Adapter to RAL Map
    if (rdi_cfg_agt_L.cfg.is_active == UVM_ACTIVE) begin
      reg_model_L.default_map.set_sequencer(rdi_cfg_agt_L.sequencer, adapter_L);
    end

    // Connect Local Predictor to ap_ral
    predictor_L.map     = reg_model_L.default_map;
    predictor_L.adapter = adapter_L;
    rdi_cfg_agt_L.ap_ral.connect(predictor_L.bus_in);

    // 2. Connect Partner (Die 1) Sequencer and Adapter to RAL Map
    if (rdi_cfg_agt_P.cfg.is_active == UVM_ACTIVE) begin
      reg_model_P.default_map.set_sequencer(rdi_cfg_agt_P.sequencer, adapter_P);
    end

    // Connect Partner Predictor to ap_ral
    predictor_P.map     = reg_model_P.default_map;
    predictor_P.adapter = adapter_P;
    rdi_cfg_agt_P.ap_ral.connect(predictor_P.bus_in);

    // 3. Connect LTSM Monitor to Coverage Component Exports
    ltsm_mon.ap_die0.connect(ltsm_cov.die0_export);
    ltsm_mon.ap_die1.connect(ltsm_cov.die1_export);

    // 4. Connect Mainband Monitor Analysis Ports to Scoreboard FIFOs
    mainband_agt_L.monitor.ap_tx.connect(scoreboard.fifo_die0_tx.analysis_export);
    mainband_agt_L.monitor.ap_rx.connect(scoreboard.fifo_die0_rx.analysis_export);
    mainband_agt_P.monitor.ap_tx.connect(scoreboard.fifo_die1_tx.analysis_export);
    mainband_agt_P.monitor.ap_rx.connect(scoreboard.fifo_die1_rx.analysis_export);

    // 5. Connect Sideband/RDI Config Cross-Die Analysis Ports to Scoreboard FIFOs
    rdi_cfg_agt_L.ap_tx.connect(scoreboard.fifo_sb_die0_tx.analysis_export);
    rdi_cfg_agt_L.ap_rx.connect(scoreboard.fifo_sb_die0_rx.analysis_export);
    rdi_cfg_agt_P.ap_tx.connect(scoreboard.fifo_sb_die1_tx.analysis_export);
    rdi_cfg_agt_P.ap_rx.connect(scoreboard.fifo_sb_die1_rx.analysis_export);

    // 6. Connect Sequencers to Virtual Sequencer Handles
    vsqr.rdi_cfg_sqr_L  = rdi_cfg_agt_L.sequencer;
    vsqr.rdi_cfg_sqr_P  = rdi_cfg_agt_P.sequencer;
    vsqr.mainband_sqr_L = mainband_agt_L.sequencer;
    vsqr.mainband_sqr_P = mainband_agt_P.sequencer;
  endfunction

endclass
