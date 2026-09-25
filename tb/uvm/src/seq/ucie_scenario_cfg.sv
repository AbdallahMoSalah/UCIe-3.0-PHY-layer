// =============================================================================
//  ucie_scenario_cfg
// -----------------------------------------------------------------------------
//  Configuration object carrying parameters for a single UVM execution run.
//  Defines registers, channel errors, and expected training outcomes.
// =============================================================================

class ucie_scenario_cfg extends uvm_object;
  `uvm_object_utils(ucie_scenario_cfg)

  // --- Target Register Control Settings ---
  rand bit [3:0]  target_width_L;
  rand bit [3:0]  target_width_P;
  rand bit [3:0]  target_speed_L;
  rand bit [3:0]  target_speed_P;
  rand bit        force_x8_mode_L;
  rand bit        force_x8_mode_P;

  // --- Fault Injection & Channel Parameters ---
  bit [15:0]      corrupt_lanes_L2P;
  bit [15:0]      corrupt_lanes_P2L;
  bit             reverse_L2P;
  bit             reverse_P2L;
  bit             block_sideband;
  bit             inject_vld_error;

  // --- Expected Outcomes (for self-checking) ---
  bit             expect_active;
  bit             expect_trainerror;
  bit [3:0]       expect_negotiated_width_L;
  bit [3:0]       expect_negotiated_width_P;
  bit [3:0]       expect_negotiated_speed_L;
  bit [3:0]       expect_negotiated_speed_P;

  // --- Power Management Sequences ---
  bit             run_pm_l1;
  bit             run_pm_l2;

  function new(string name = "ucie_scenario_cfg");
    super.new(name);
    // Defaults: happy path x16, full speed, expect active
    target_width_L = 4'h2; // x16
    target_width_P = 4'h2;
    target_speed_L = 4'h5; // 16 GT/s
    target_speed_P = 4'h5;
    force_x8_mode_L = 1'b0;
    force_x8_mode_P = 1'b0;
    
    corrupt_lanes_L2P = '0;
    corrupt_lanes_P2L = '0;
    reverse_L2P       = 1'b0;
    reverse_P2L       = 1'b0;
    block_sideband     = 1'b0;
    inject_vld_error   = 1'b0;

    expect_active     = 1'b1;
    expect_trainerror = 1'b0;
    expect_negotiated_width_L = 4'h2; // x16
    expect_negotiated_width_P = 4'h2;
    expect_negotiated_speed_L = 4'h5;
    expect_negotiated_speed_P = 4'h5;

    run_pm_l1         = 1'b0;
    run_pm_l2         = 1'b0;
  endfunction
endclass
