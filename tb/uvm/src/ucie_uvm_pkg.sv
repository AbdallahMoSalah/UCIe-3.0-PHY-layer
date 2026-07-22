// =============================================================================
//  ucie_uvm_pkg
// -----------------------------------------------------------------------------
//  Unified package file compiling all components of the UCIe 3.0 PHY Layer UVM env.
// =============================================================================

package ucie_uvm_pkg;

  import uvm_pkg::*;
  import sb_pkg::*;
  import ltsm_state_n_pkg::*;
  
  `include "uvm_macros.svh"

  // 1. RDI Config Agent Files
  `include "rdi_cfg_agent/rdi_cfg_agent_config.sv"
  `include "rdi_cfg_agent/rdi_cfg_seq_item.sv"
  `include "rdi_cfg_agent/rdi_cfg_driver.sv"
  `include "rdi_cfg_agent/rdi_cfg_monitor.sv"
  `include "rdi_cfg_agent/rdi_cfg_coverage.sv"
  `include "rdi_cfg_agent/rdi_cfg_sequencer.sv"
  `include "rdi_cfg_agent/rdi_cfg_agent.sv"

  // 2. Mainband Agent Files
  `include "mainband_agent/ucie_mainband_reset_handler.sv"
  `include "mainband_agent/ucie_mainband_seq_item.sv"
  `include "mainband_agent/ucie_mainband_driver.sv"
  `include "mainband_agent/ucie_mainband_monitor.sv"
  `include "mainband_agent/ucie_mainband_sequencer.sv"
  `include "mainband_agent/ucie_mainband_agent.sv"

  // 3. Passive LTSM Monitor Files
  `include "ltsm_agent/ltsm_state_transaction.sv"
  `include "ltsm_agent/ucie_ltsm_monitor.sv"

  // 4. Register Abstraction Layer (RAL)
  `include "reg_model/ucie_reg_model.sv"
  `include "reg_model/reg2rdi_cfg_adapter.sv"

  // 5. Coverage Component, Scoreboard, and Virtual Sequencer
  `include "ucie_ltsm_coverage.sv"
  `include "ucie_virtual_sequencer.sv"
  `include "ucie_scoreboard.sv"

  // 6. UVM Environment
  `include "ucie_env.sv"

  // 7. Sequences & Virtual Sequences
  `include "seq/rdi_cfg_single_pkt_seq.sv"
  `include "seq/rdi_cfg_burst_seq.sv"
  `include "seq/ucie_mainband_single_pkt_seq.sv"
  `include "seq/ucie_mainband_burst_seq.sv"
  `include "seq/ucie_vseq_base.sv"
  `include "seq/ucie_scenario_cfg.sv"
  `include "seq/ucie_master_vseq.sv"

  // 8. Testcases
  `include "tests/ucie_base_test.sv"
  `include "tests/ucie_tests.sv"

endpackage
