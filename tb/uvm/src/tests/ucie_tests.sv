// =============================================================================
//  ucie_tests
// -----------------------------------------------------------------------------
//  Subclasses of ucie_base_test configuring and running the virtual sequence
//  for different UCIe scenarios.
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Happy Path Link Bring-up Test (SC1)
// -----------------------------------------------------------------------------
class ucie_happy_path_test extends ucie_base_test;
  `uvm_component_utils(ucie_happy_path_test)

  function new(string name = "ucie_happy_path_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    ucie_master_vseq vseq;
    ucie_scenario_cfg cfg;
    
    phase.raise_objection(this);
    
    // Create scenario configuration
    cfg = ucie_scenario_cfg::type_id::create("cfg");
    cfg.target_width_L = 4'h2; // x16
    cfg.target_width_P = 4'h2; // x16
    cfg.target_speed_L = 4'h5; // 16 GT/s
    cfg.target_speed_P = 4'h5;
    
    cfg.expect_active  = 1'b1;
    cfg.expect_negotiated_width_L = 4'h2;
    cfg.expect_negotiated_width_P = 4'h2;
    cfg.expect_negotiated_speed_L = 4'h5;
    cfg.expect_negotiated_speed_P = 4'h5;

    // Create and run virtual sequence
    vseq = ucie_master_vseq::type_id::create("vseq");
    vseq.cfg = cfg;
    init_vseq(vseq);

    vseq.start(env.vsqr); // Started on null sequencer-less style
    
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------
// 2. Asymmetric Link Width Negotiation Test (SC3)
// -----------------------------------------------------------------------------
class ucie_asymmetric_width_test extends ucie_base_test;
  `uvm_component_utils(ucie_asymmetric_width_test)

  function new(string name = "ucie_asymmetric_width_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    ucie_master_vseq vseq;
    ucie_scenario_cfg cfg;
    
    phase.raise_objection(this);
    
    cfg = ucie_scenario_cfg::type_id::create("cfg");
    cfg.target_width_L = 4'h2; // Local wants x16
    cfg.target_width_P = 4'h1; // Partner wants x8
    
    cfg.expect_active  = 1'b1;
    cfg.expect_negotiated_width_L = 4'h1; // Both must settle at x8
    cfg.expect_negotiated_width_P = 4'h1;

    vseq = ucie_master_vseq::type_id::create("vseq");
    vseq.cfg = cfg;
    init_vseq(vseq);
    vseq.start(env.vsqr);
    
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------
// 3. Lane Reversal Test (SC6)
// -----------------------------------------------------------------------------
class ucie_lane_reversal_test extends ucie_base_test;
  `uvm_component_utils(ucie_lane_reversal_test)

  function new(string name = "ucie_lane_reversal_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    ucie_master_vseq vseq;
    ucie_scenario_cfg cfg;
    
    phase.raise_objection(this);
    
    cfg = ucie_scenario_cfg::type_id::create("cfg");
    cfg.reverse_L2P    = 1'b1; // Apply lane reversal on physical path
    
    cfg.expect_active  = 1'b1;
    cfg.expect_negotiated_width_L = 4'h2; // Reversal allows training at x16
    cfg.expect_negotiated_width_P = 4'h2;

    vseq = ucie_master_vseq::type_id::create("vseq");
    vseq.cfg = cfg;
    init_vseq(vseq);
    vseq.start(env.vsqr);
    
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------
// 4. Mid-Train Lane Repair and Width Degradation Test (SC13 / SC14)
// -----------------------------------------------------------------------------
class ucie_lane_repair_test extends ucie_base_test;
  `uvm_component_utils(ucie_lane_repair_test)

  function new(string name = "ucie_lane_repair_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    ucie_master_vseq vseq;
    ucie_scenario_cfg cfg;
    
    phase.raise_objection(this);
    
    cfg = ucie_scenario_cfg::type_id::create("cfg");
    // Induce upper-half lane corruption (lanes 8..15 bad on L2P path)
    cfg.corrupt_lanes_L2P = 16'hFF00; 
    
    // PHY degrades link width to x8 (4'h1)
    cfg.expect_active  = 1'b1;
    cfg.expect_negotiated_width_L = 4'h1; // Settle at x8 (degraded)
    cfg.expect_negotiated_width_P = 4'h1;

    vseq = ucie_master_vseq::type_id::create("vseq");
    vseq.cfg = cfg;
    init_vseq(vseq);
    vseq.start(env.vsqr);
    
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------
// 5. Sideband Blocked / TrainError Test
// -----------------------------------------------------------------------------
class ucie_trainerror_test extends ucie_base_test;
  `uvm_component_utils(ucie_trainerror_test)

  function new(string name = "ucie_trainerror_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(1000us);
  endfunction

  task run_phase(uvm_phase phase);
    ucie_master_vseq vseq;
    ucie_scenario_cfg cfg;
    
    phase.raise_objection(this);
    
    cfg = ucie_scenario_cfg::type_id::create("cfg");
    // Block the sideband clock so speed/parameter negotiation fails
    cfg.block_sideband = 1'b1;
    
    // Link must not train successfully and should enter TRAINERROR
    cfg.expect_active      = 1'b0;
    cfg.expect_trainerror  = 1'b1;

    vseq = ucie_master_vseq::type_id::create("vseq");
    vseq.cfg = cfg;
    init_vseq(vseq);
    vseq.start(env.vsqr);
    
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------
// 6. Power Management L1 Mode Test
// -----------------------------------------------------------------------------
class ucie_pm_l1_test extends ucie_base_test;
  `uvm_component_utils(ucie_pm_l1_test)

  function new(string name = "ucie_pm_l1_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(1500us);
  endfunction

  task run_phase(uvm_phase phase);
    ucie_master_vseq vseq;
    ucie_scenario_cfg cfg;
    
    phase.raise_objection(this);
    
    cfg = ucie_scenario_cfg::type_id::create("cfg");
    cfg.expect_active = 1'b1;
    cfg.run_pm_l1     = 1'b1;

    vseq = ucie_master_vseq::type_id::create("vseq");
    vseq.cfg = cfg;
    init_vseq(vseq);
    vseq.start(env.vsqr);
    
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------
// 7. Power Management L2 Mode Test
// -----------------------------------------------------------------------------
class ucie_pm_l2_test extends ucie_base_test;
  `uvm_component_utils(ucie_pm_l2_test)

  function new(string name = "ucie_pm_l2_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_top.set_timeout(1500us);
  endfunction

  task run_phase(uvm_phase phase);
    ucie_master_vseq vseq;
    ucie_scenario_cfg cfg;
    
    phase.raise_objection(this);
    
    cfg = ucie_scenario_cfg::type_id::create("cfg");
    cfg.expect_active = 1'b1;
    cfg.run_pm_l2     = 1'b1;

    vseq = ucie_master_vseq::type_id::create("vseq");
    vseq.cfg = cfg;
    init_vseq(vseq);
    vseq.start(env.vsqr);
    
    phase.drop_objection(this);
  endtask
endclass
