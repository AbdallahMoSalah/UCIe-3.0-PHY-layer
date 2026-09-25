// =============================================================================
//  ucie_reg_model
// -----------------------------------------------------------------------------
//  UVM Register Abstraction Layer (RAL) definitions for the UCIe 3.0 PHY.
//  Defines registers for Config Space (addr[24]=0) and MMIO Space (addr[24]=1).
//  Matches all registers defined in RTL Reg_File.sv.
// =============================================================================

// -----------------------------------------------------------------------------
// 1. PCIe Ext Cap Header Register (Offset 000h)
// -----------------------------------------------------------------------------
class ucie_reg_pcie_ext_cap_hdr extends uvm_reg;
  `uvm_object_utils(ucie_reg_pcie_ext_cap_hdr)
  uvm_reg_field val;
  function new(string name = "ucie_reg_pcie_ext_cap_hdr");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RO", 0, 32'h0001_0023, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 2. DVSEC Header 1 Register (Offset 004h)
// -----------------------------------------------------------------------------
class ucie_reg_dvsec_hdr1 extends uvm_reg;
  `uvm_object_utils(ucie_reg_dvsec_hdr1)
  uvm_reg_field val;
  function new(string name = "ucie_reg_dvsec_hdr1");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RO", 0, 32'h0240_D2DE, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 3. DVSEC Header 2 Register (Offset 008h)
// -----------------------------------------------------------------------------
class ucie_reg_dvsec_hdr2 extends uvm_reg;
  `uvm_object_utils(ucie_reg_dvsec_hdr2)
  uvm_reg_field val;
  function new(string name = "ucie_reg_dvsec_hdr2");
    super.new(name, 16, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 16, 0, "RO", 0, 16'h0000, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 4. Capability Descriptor Register (Offset 00Ah)
// -----------------------------------------------------------------------------
class ucie_reg_cap_desc extends uvm_reg;
  `uvm_object_utils(ucie_reg_cap_desc)
  uvm_reg_field val;
  function new(string name = "ucie_reg_cap_desc");
    super.new(name, 16, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 16, 0, "RO", 0, 16'hFFF7, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 5. UCIe Link Capability Register (Offset 00Ch)
// -----------------------------------------------------------------------------
class ucie_reg_link_cap extends uvm_reg;
  `uvm_object_utils(ucie_reg_link_cap)
  uvm_reg_field val;
  function new(string name = "ucie_reg_link_cap");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RO", 0, 32'h0, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 6. UCIe Link Control Register (Offset 010h)
// -----------------------------------------------------------------------------
class ucie_reg_link_ctrl extends uvm_reg;
  `uvm_object_utils(ucie_reg_link_ctrl)

  rand uvm_reg_field multi_protocol_en;          // bit [1]
  rand uvm_reg_field target_link_width;          // bits [5:2]
  rand uvm_reg_field target_link_speed;          // bits [9:6]
  rand uvm_reg_field start_ucie_link_training;    // bit [10]
  rand uvm_reg_field retrain_ucie_link;          // bit [11]
  rand uvm_reg_field pmo_ctrl;                   // bit [21]
  rand uvm_reg_field pspt_ctrl;                  // bit [22]
  rand uvm_reg_field l2spd_ctrl;                 // bit [23]

  function new(string name = "ucie_reg_link_ctrl");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    multi_protocol_en = uvm_reg_field::type_id::create("multi_protocol_en");
    multi_protocol_en.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 0);

    target_link_width = uvm_reg_field::type_id::create("target_link_width");
    target_link_width.configure(this, 4, 2, "RW", 0, 4'h0, 1, 1, 0);

    target_link_speed = uvm_reg_field::type_id::create("target_link_speed");
    target_link_speed.configure(this, 4, 6, "RW", 0, 4'h5, 1, 1, 0);

    start_ucie_link_training = uvm_reg_field::type_id::create("start_ucie_link_training");
    start_ucie_link_training.configure(this, 1, 10, "RW", 0, 1'b0, 1, 1, 0);

    retrain_ucie_link = uvm_reg_field::type_id::create("retrain_ucie_link");
    retrain_ucie_link.configure(this, 1, 11, "RW", 0, 1'b0, 1, 1, 0);

    pmo_ctrl = uvm_reg_field::type_id::create("pmo_ctrl");
    pmo_ctrl.configure(this, 1, 21, "RW", 0, 1'b0, 1, 1, 0);

    pspt_ctrl = uvm_reg_field::type_id::create("pspt_ctrl");
    pspt_ctrl.configure(this, 1, 22, "RW", 0, 1'b0, 1, 1, 0);

    l2spd_ctrl = uvm_reg_field::type_id::create("l2spd_ctrl");
    l2spd_ctrl.configure(this, 1, 23, "RW", 0, 1'b0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 7. UCIe Link Status Register (Offset 014h)
// -----------------------------------------------------------------------------
class ucie_reg_link_status extends uvm_reg;
  `uvm_object_utils(ucie_reg_link_status)

  uvm_reg_field raw_format_en;                   // bit [0]
  uvm_reg_field link_width_enabled;              // bits [10:7]
  uvm_reg_field link_speed_enabled;              // bits [14:11]
  uvm_reg_field link_status;                     // bit [15]
  uvm_reg_field link_training_retraining;        // bit [16]
  rand uvm_reg_field link_status_changed;        // bit [17] (W1C)
  rand uvm_reg_field correctable_error;          // bit [19] (W1C-sticky)

  function new(string name = "ucie_reg_link_status");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    raw_format_en = uvm_reg_field::type_id::create("raw_format_en");
    raw_format_en.configure(this, 1, 0, "RO", 0, 1'b0, 1, 0, 0);

    link_width_enabled = uvm_reg_field::type_id::create("link_width_enabled");
    link_width_enabled.configure(this, 4, 7, "RO", 0, 4'h0, 1, 0, 0);

    link_speed_enabled = uvm_reg_field::type_id::create("link_speed_enabled");
    link_speed_enabled.configure(this, 4, 11, "RO", 0, 4'h0, 1, 0, 0);

    link_status = uvm_reg_field::type_id::create("link_status");
    link_status.configure(this, 1, 15, "RO", 0, 1'b0, 1, 0, 0);

    link_training_retraining = uvm_reg_field::type_id::create("link_training_retraining");
    link_training_retraining.configure(this, 1, 16, "RO", 0, 1'b0, 1, 0, 0);

    link_status_changed = uvm_reg_field::type_id::create("link_status_changed");
    link_status_changed.configure(this, 1, 17, "W1C", 0, 1'b0, 1, 1, 0);

    correctable_error = uvm_reg_field::type_id::create("correctable_error");
    correctable_error.configure(this, 1, 19, "W1C", 0, 1'b0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 8. Link Event Notification Control Register (Offset 018h)
// -----------------------------------------------------------------------------
class ucie_reg_link_event_notif_ctrl extends uvm_reg;
  `uvm_object_utils(ucie_reg_link_event_notif_ctrl)
  rand uvm_reg_field interrupt_num;
  function new(string name = "ucie_reg_link_event_notif_ctrl");
    super.new(name, 16, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    interrupt_num = uvm_reg_field::type_id::create("interrupt_num");
    interrupt_num.configure(this, 5, 0, "RW", 0, 5'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 9. Error Notification Control Register (Offset 01Ah)
// -----------------------------------------------------------------------------
class ucie_reg_error_notif_ctrl extends uvm_reg;
  `uvm_object_utils(ucie_reg_error_notif_ctrl)
  rand uvm_reg_field val;
  function new(string name = "ucie_reg_error_notif_ctrl");
    super.new(name, 16, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 16, 0, "RW", 0, 16'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 10. Register Locator 0 Low Register (Offset 01Ch)
// -----------------------------------------------------------------------------
class ucie_reg_reg_loc_0_low extends uvm_reg;
  `uvm_object_utils(ucie_reg_reg_loc_0_low)
  uvm_reg_field val;
  function new(string name = "ucie_reg_reg_loc_0_low");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RO", 0, 32'h0000_1F00, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 11. Register Locator 0 High Register (Offset 020h)
// -----------------------------------------------------------------------------
class ucie_reg_reg_loc_0_high extends uvm_reg;
  `uvm_object_utils(ucie_reg_reg_loc_0_high)
  uvm_reg_field val;
  function new(string name = "ucie_reg_reg_loc_0_high");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RO", 0, 32'h0000_0000, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 12. PHY Capability Register (Offset 1000h)
// -----------------------------------------------------------------------------
class ucie_reg_phy_cap extends uvm_reg;
  `uvm_object_utils(ucie_reg_phy_cap)
  uvm_reg_field val;
  function new(string name = "ucie_reg_phy_cap");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RO", 0, 32'h0, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 13. PHY Control Register (Offset 1004h)
// -----------------------------------------------------------------------------
class ucie_reg_phy_control extends uvm_reg;
  `uvm_object_utils(ucie_reg_phy_control)

  rand uvm_reg_field rx_term_enable;             // bit [3]
  rand uvm_reg_field tx_eq_enable;               // bit [4]
  rand uvm_reg_field rx_clk_mode;                // bit [5]
  rand uvm_reg_field rx_clk_phase;               // bit [6]
  rand uvm_reg_field force_x8_width_mode;        // bit [8]
  rand uvm_reg_field force_iq_correction;        // bit [9]

  function new(string name = "ucie_reg_phy_control");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rx_term_enable = uvm_reg_field::type_id::create("rx_term_enable");
    rx_term_enable.configure(this, 1, 3, "RW", 0, 1'b0, 1, 1, 0);

    tx_eq_enable = uvm_reg_field::type_id::create("tx_eq_enable");
    tx_eq_enable.configure(this, 1, 4, "RW", 0, 1'b0, 1, 1, 0);

    rx_clk_mode = uvm_reg_field::type_id::create("rx_clk_mode");
    rx_clk_mode.configure(this, 1, 5, "RW", 0, 1'b0, 1, 1, 0);

    rx_clk_phase = uvm_reg_field::type_id::create("rx_clk_phase");
    rx_clk_phase.configure(this, 1, 6, "RW", 0, 1'b0, 1, 1, 0);

    force_x8_width_mode = uvm_reg_field::type_id::create("force_x8_width_mode");
    force_x8_width_mode.configure(this, 1, 8, "RW", 0, 1'b0, 1, 1, 0);

    force_iq_correction = uvm_reg_field::type_id::create("force_iq_correction");
    force_iq_correction.configure(this, 1, 9, "RW", 0, 1'b0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 14. PHY Status Register (Offset 1008h)
// -----------------------------------------------------------------------------
class ucie_reg_phy_status extends uvm_reg;
  `uvm_object_utils(ucie_reg_phy_status)

  uvm_reg_field rx_term_status;                  // bit [3]
  uvm_reg_field tx_eq_status;                    // bit [4]
  uvm_reg_field rx_clk_mode_status;              // bit [5]
  uvm_reg_field rx_clk_phase_status;             // bit [6]
  uvm_reg_field lane_reversal_status;            // bit [7]

  function new(string name = "ucie_reg_phy_status");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    rx_term_status = uvm_reg_field::type_id::create("rx_term_status");
    rx_term_status.configure(this, 1, 3, "RO", 0, 1'b0, 1, 0, 0);

    tx_eq_status = uvm_reg_field::type_id::create("tx_eq_status");
    tx_eq_status.configure(this, 1, 4, "RO", 0, 1'b0, 1, 0, 0);

    rx_clk_mode_status = uvm_reg_field::type_id::create("rx_clk_mode_status");
    rx_clk_mode_status.configure(this, 1, 5, "RO", 0, 1'b0, 1, 0, 0);

    rx_clk_phase_status = uvm_reg_field::type_id::create("rx_clk_phase_status");
    rx_clk_phase_status.configure(this, 1, 6, "RO", 0, 1'b0, 1, 0, 0);

    lane_reversal_status = uvm_reg_field::type_id::create("lane_reversal_status");
    lane_reversal_status.configure(this, 1, 7, "RO", 0, 1'b0, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 15. PHY Initialization and Debug Register (Offset 100Ch)
// -----------------------------------------------------------------------------
class ucie_reg_phy_init_debug extends uvm_reg;
  `uvm_object_utils(ucie_reg_phy_init_debug)
  rand uvm_reg_field val;
  function new(string name = "ucie_reg_phy_init_debug");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 16. Training Setup 1 Register (Offset 1010h)
// -----------------------------------------------------------------------------
class ucie_reg_train_setup1 extends uvm_reg;
  `uvm_object_utils(ucie_reg_train_setup1)
  rand uvm_reg_field val;
  function new(string name = "ucie_reg_train_setup1");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 17. Training Setup 2 Register (Offset 1020h)
// -----------------------------------------------------------------------------
class ucie_reg_train_setup2 extends uvm_reg;
  `uvm_object_utils(ucie_reg_train_setup2)

  rand uvm_reg_field idle_count;                 // bits [15:0]
  rand uvm_reg_field iterations;                 // bits [31:16]

  function new(string name = "ucie_reg_train_setup2");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    idle_count = uvm_reg_field::type_id::create("idle_count");
    idle_count.configure(this, 16, 0, "RW", 0, 16'h0, 1, 1, 0);

    iterations = uvm_reg_field::type_id::create("iterations");
    iterations.configure(this, 16, 16, "RW", 0, 16'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 18. Training Setup 3 Register (Offset 1030h - 64-bit)
// -----------------------------------------------------------------------------
class ucie_reg_train_setup3 extends uvm_reg;
  `uvm_object_utils(ucie_reg_train_setup3)

  rand uvm_reg_field lane_mask;                  // bits [63:0]

  function new(string name = "ucie_reg_train_setup3");
    super.new(name, 64, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    lane_mask = uvm_reg_field::type_id::create("lane_mask");
    lane_mask.configure(this, 64, 0, "RW", 0, 64'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 19. Training Setup 4 Register (Offset 1050h)
// -----------------------------------------------------------------------------
class ucie_reg_train_setup4 extends uvm_reg;
  `uvm_object_utils(ucie_reg_train_setup4)

  rand uvm_reg_field per_lane_threshold;          // bits [15:0]
  rand uvm_reg_field aggregate_threshold;         // bits [31:16]

  function new(string name = "ucie_reg_train_setup4");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    per_lane_threshold = uvm_reg_field::type_id::create("per_lane_threshold");
    per_lane_threshold.configure(this, 16, 0, "RW", 0, 16'h0, 1, 1, 0);

    aggregate_threshold = uvm_reg_field::type_id::create("aggregate_threshold");
    aggregate_threshold.configure(this, 16, 16, "RW", 0, 16'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 20. Current Lane Map Module 0 Register (Offset 1060h - 64-bit)
// -----------------------------------------------------------------------------
class ucie_reg_curr_lane_map extends uvm_reg;
  `uvm_object_utils(ucie_reg_curr_lane_map)

  rand uvm_reg_field lane_map_enable;            // bits [15:0]

  function new(string name = "ucie_reg_curr_lane_map");
    super.new(name, 64, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    lane_map_enable = uvm_reg_field::type_id::create("lane_map_enable");
    lane_map_enable.configure(this, 16, 0, "RW", 0, 16'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 21. Error Log 0 Register (Offset 1080h)
// -----------------------------------------------------------------------------
class ucie_reg_err_log0 extends uvm_reg;
  `uvm_object_utils(ucie_reg_err_log0)

  uvm_reg_field state_n;                         // bits [7:0]
  uvm_reg_field lane_reversal_at_err;            // bit [8]
  uvm_reg_field width_degrade;                   // bit [9]
  uvm_reg_field state_n_minus_1;                 // bits [23:16]
  uvm_reg_field state_n_minus_2;                 // bits [31:24]

  function new(string name = "ucie_reg_err_log0");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    state_n = uvm_reg_field::type_id::create("state_n");
    state_n.configure(this, 8, 0, "RO", 0, 8'h0, 1, 0, 0);

    lane_reversal_at_err = uvm_reg_field::type_id::create("lane_reversal_at_err");
    lane_reversal_at_err.configure(this, 1, 8, "RO", 0, 1'b0, 1, 0, 0);

    width_degrade = uvm_reg_field::type_id::create("width_degrade");
    width_degrade.configure(this, 1, 9, "RO", 0, 1'b0, 1, 0, 0);

    state_n_minus_1 = uvm_reg_field::type_id::create("state_n_minus_1");
    state_n_minus_1.configure(this, 8, 16, "RO", 0, 8'h0, 1, 0, 0);

    state_n_minus_2 = uvm_reg_field::type_id::create("state_n_minus_2");
    state_n_minus_2.configure(this, 8, 24, "RO", 0, 8'h0, 1, 0, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 22. Error Log 1 Register (Offset 1090h)
// -----------------------------------------------------------------------------
class ucie_reg_err_log1 extends uvm_reg;
  `uvm_object_utils(ucie_reg_err_log1)
  rand uvm_reg_field val;
  function new(string name = "ucie_reg_err_log1");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 23. Runtime Link Test Control (Offset 1100h - 64-bit)
// -----------------------------------------------------------------------------
class ucie_reg_rt_link_test_ctrl extends uvm_reg;
  `uvm_object_utils(ucie_reg_rt_link_test_ctrl)

  rand uvm_reg_field apply_module_0_repair;     // bit [2]
  rand uvm_reg_field rt_link_test_start;         // bit [6]
  rand uvm_reg_field inject_stuck_at_fault;      // bit [7]
  rand uvm_reg_field module_0_repair_id;         // bits [14:8]

  function new(string name = "ucie_reg_rt_link_test_ctrl");
    super.new(name, 64, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    apply_module_0_repair = uvm_reg_field::type_id::create("apply_module_0_repair");
    apply_module_0_repair.configure(this, 1, 2, "RW", 0, 1'b0, 1, 1, 0);

    rt_link_test_start = uvm_reg_field::type_id::create("rt_link_test_start");
    rt_link_test_start.configure(this, 1, 6, "RW", 0, 1'b0, 1, 1, 0);

    inject_stuck_at_fault = uvm_reg_field::type_id::create("inject_stuck_at_fault");
    inject_stuck_at_fault.configure(this, 1, 7, "RW", 0, 1'b0, 1, 1, 0);

    module_0_repair_id = uvm_reg_field::type_id::create("module_0_repair_id");
    module_0_repair_id.configure(this, 7, 8, "RW", 0, 7'h0, 1, 1, 0);
  endfunction
endclass

// -----------------------------------------------------------------------------
// 24. Runtime Link Test Status Register (Offset 1108h)
// -----------------------------------------------------------------------------
class ucie_reg_rt_link_test_status extends uvm_reg;
  `uvm_object_utils(ucie_reg_rt_link_test_status)
  uvm_reg_field val;
  function new(string name = "ucie_reg_rt_link_test_status");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction
  virtual function void build();
    val = uvm_reg_field::type_id::create("val");
    val.configure(this, 32, 0, "RO", 0, 32'h0, 1, 0, 0);
  endfunction
endclass

// =============================================================================
//  Main Register Block Class (ucie_reg_block)
// =============================================================================
class ucie_reg_block extends uvm_reg_block;
  `uvm_object_utils(ucie_reg_block)

  // Config Space Registers
  rand ucie_reg_pcie_ext_cap_hdr      pcie_ext_cap_hdr;
  rand ucie_reg_dvsec_hdr1           dvsec_hdr1;
  rand ucie_reg_dvsec_hdr2           dvsec_hdr2;
  rand ucie_reg_cap_desc             cap_desc;
  rand ucie_reg_link_cap             ucie_link_cap;
  rand ucie_reg_link_ctrl            ucie_link_ctrl;
  rand ucie_reg_link_status          ucie_link_status;
  rand ucie_reg_link_event_notif_ctrl link_event_notif_ctrl;
  rand ucie_reg_error_notif_ctrl     error_notif_ctrl;
  rand ucie_reg_reg_loc_0_low        reg_loc_0_low;
  rand ucie_reg_reg_loc_0_high       reg_loc_0_high;

  // MMIO Space Registers
  rand ucie_reg_phy_cap              phy_cap;
  rand ucie_reg_phy_control          phy_control;
  rand ucie_reg_phy_status           phy_status;
  rand ucie_reg_phy_init_debug       phy_init_debug;
  rand ucie_reg_train_setup1         train_setup1;
  rand ucie_reg_train_setup2         train_setup2;
  rand ucie_reg_train_setup3         train_setup3;
  rand ucie_reg_train_setup4         train_setup4;
  rand ucie_reg_curr_lane_map        curr_lane_map;
  rand ucie_reg_err_log0             err_log0;
  rand ucie_reg_err_log1             err_log1;
  rand ucie_reg_rt_link_test_ctrl    rt_link_test_ctrl;
  rand ucie_reg_rt_link_test_status  rt_link_test_status;

  uvm_reg_map default_map;

  function new(string name = "ucie_reg_block", int has_coverage = UVM_NO_COVERAGE);
    super.new(name, has_coverage);
  endfunction

  virtual function void build();
    // 1. Create and configure Config Space registers
    pcie_ext_cap_hdr = ucie_reg_pcie_ext_cap_hdr::type_id::create("pcie_ext_cap_hdr");
    pcie_ext_cap_hdr.configure(this);
    pcie_ext_cap_hdr.build();

    dvsec_hdr1 = ucie_reg_dvsec_hdr1::type_id::create("dvsec_hdr1");
    dvsec_hdr1.configure(this);
    dvsec_hdr1.build();

    dvsec_hdr2 = ucie_reg_dvsec_hdr2::type_id::create("dvsec_hdr2");
    dvsec_hdr2.configure(this);
    dvsec_hdr2.build();

    cap_desc = ucie_reg_cap_desc::type_id::create("cap_desc");
    cap_desc.configure(this);
    cap_desc.build();

    ucie_link_cap = ucie_reg_link_cap::type_id::create("ucie_link_cap");
    ucie_link_cap.configure(this);
    ucie_link_cap.build();

    ucie_link_ctrl = ucie_reg_link_ctrl::type_id::create("ucie_link_ctrl");
    ucie_link_ctrl.configure(this);
    ucie_link_ctrl.build();

    ucie_link_status = ucie_reg_link_status::type_id::create("ucie_link_status");
    ucie_link_status.configure(this);
    ucie_link_status.build();

    link_event_notif_ctrl = ucie_reg_link_event_notif_ctrl::type_id::create("link_event_notif_ctrl");
    link_event_notif_ctrl.configure(this);
    link_event_notif_ctrl.build();

    error_notif_ctrl = ucie_reg_error_notif_ctrl::type_id::create("error_notif_ctrl");
    error_notif_ctrl.configure(this);
    error_notif_ctrl.build();

    reg_loc_0_low = ucie_reg_reg_loc_0_low::type_id::create("reg_loc_0_low");
    reg_loc_0_low.configure(this);
    reg_loc_0_low.build();

    reg_loc_0_high = ucie_reg_reg_loc_0_high::type_id::create("reg_loc_0_high");
    reg_loc_0_high.configure(this);
    reg_loc_0_high.build();

    // 2. Create and configure MMIO Space registers
    phy_cap = ucie_reg_phy_cap::type_id::create("phy_cap");
    phy_cap.configure(this);
    phy_cap.build();

    phy_control = ucie_reg_phy_control::type_id::create("phy_control");
    phy_control.configure(this);
    phy_control.build();

    phy_status = ucie_reg_phy_status::type_id::create("phy_status");
    phy_status.configure(this);
    phy_status.build();

    phy_init_debug = ucie_reg_phy_init_debug::type_id::create("phy_init_debug");
    phy_init_debug.configure(this);
    phy_init_debug.build();

    train_setup1 = ucie_reg_train_setup1::type_id::create("train_setup1");
    train_setup1.configure(this);
    train_setup1.build();

    train_setup2 = ucie_reg_train_setup2::type_id::create("train_setup2");
    train_setup2.configure(this);
    train_setup2.build();

    train_setup3 = ucie_reg_train_setup3::type_id::create("train_setup3");
    train_setup3.configure(this);
    train_setup3.build();

    train_setup4 = ucie_reg_train_setup4::type_id::create("train_setup4");
    train_setup4.configure(this);
    train_setup4.build();

    curr_lane_map = ucie_reg_curr_lane_map::type_id::create("curr_lane_map");
    curr_lane_map.configure(this);
    curr_lane_map.build();

    err_log0 = ucie_reg_err_log0::type_id::create("err_log0");
    err_log0.configure(this);
    err_log0.build();

    err_log1 = ucie_reg_err_log1::type_id::create("err_log1");
    err_log1.configure(this);
    err_log1.build();

    rt_link_test_ctrl = ucie_reg_rt_link_test_ctrl::type_id::create("rt_link_test_ctrl");
    rt_link_test_ctrl.configure(this);
    rt_link_test_ctrl.build();

    rt_link_test_status = ucie_reg_rt_link_test_status::type_id::create("rt_link_test_status");
    rt_link_test_status.configure(this);
    rt_link_test_status.build();

    // 3. Create the flat address map
    default_map = create_map("default_map", 'h0, 8, UVM_LITTLE_ENDIAN);

    // 4. Add Config Space registers (addr[24]=0)
    default_map.add_reg(pcie_ext_cap_hdr,      'h00_0000, "RO"); // Offset 000h
    default_map.add_reg(dvsec_hdr1,           'h00_0004, "RO"); // Offset 004h
    default_map.add_reg(dvsec_hdr2,           'h00_0008, "RO"); // Offset 008h
    default_map.add_reg(cap_desc,             'h00_000A, "RO"); // Offset 00Ah
    default_map.add_reg(ucie_link_cap,        'h00_000C, "RO"); // Offset 00Ch
    default_map.add_reg(ucie_link_ctrl,       'h00_0010, "RW"); // Offset 010h
    default_map.add_reg(ucie_link_status,     'h00_0014, "RO"); // Offset 014h
    default_map.add_reg(link_event_notif_ctrl,'h00_0018, "RW"); // Offset 018h
    default_map.add_reg(error_notif_ctrl,     'h00_001A, "RW"); // Offset 01Ah
    default_map.add_reg(reg_loc_0_low,        'h00_001C, "RO"); // Offset 01Ch
    default_map.add_reg(reg_loc_0_high,       'h00_0020, "RO"); // Offset 020h

    // 5. Add MMIO Space registers (addr[24]=1 -> add 25'h1000000)
    default_map.add_reg(phy_cap,              'h100_1000, "RO"); // Offset 1000h
    default_map.add_reg(phy_control,          'h100_1004, "RW"); // Offset 1004h
    default_map.add_reg(phy_status,           'h100_1008, "RO"); // Offset 1008h
    default_map.add_reg(phy_init_debug,       'h100_100C, "RW"); // Offset 100Ch
    default_map.add_reg(train_setup1,         'h100_1010, "RW"); // Offset 1010h
    default_map.add_reg(train_setup2,         'h100_1020, "RW"); // Offset 1020h
    default_map.add_reg(train_setup3,         'h100_1030, "RW"); // Offset 1030h
    default_map.add_reg(train_setup4,         'h100_1050, "RW"); // Offset 1050h
    default_map.add_reg(curr_lane_map,        'h100_1060, "RW"); // Offset 1060h
    default_map.add_reg(err_log0,             'h100_1080, "RO"); // Offset 1080h
    default_map.add_reg(err_log1,             'h100_1090, "RW"); // Offset 1090h
    default_map.add_reg(rt_link_test_ctrl,    'h100_1100, "RW"); // Offset 1100h
    default_map.add_reg(rt_link_test_status,  'h100_1108, "RO"); // Offset 1108h

    lock_model();
  endfunction
endclass
