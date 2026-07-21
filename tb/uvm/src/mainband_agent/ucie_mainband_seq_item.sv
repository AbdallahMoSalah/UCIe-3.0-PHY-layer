// =============================================================================
//  ucie_mainband_seq_item
// -----------------------------------------------------------------------------
//  Contains base sequence item, driver item, and monitor item for Mainband agent.
// =============================================================================

// 1. Base sequence item containing common transaction properties (data)
class ucie_mainband_seq_item_base extends uvm_sequence_item;

  rand bit [255:0] data;

  `uvm_object_utils_begin(ucie_mainband_seq_item_base)
    `uvm_field_int(data, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "ucie_mainband_seq_item_base");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("data=0x%h", data);
  endfunction

endclass


// 2. Driver sequence item containing driver-specific delay controls
class ucie_mainband_seq_item_drv extends ucie_mainband_seq_item_base;

  rand int unsigned pre_drive_delay;
  rand int unsigned post_drive_delay;

  constraint c_pre_drive_delay_default {
    soft pre_drive_delay <= 5;
  }

  constraint c_post_drive_delay_default {
    soft post_drive_delay <= 5;
  }

  `uvm_object_utils_begin(ucie_mainband_seq_item_drv)
    `uvm_field_int(pre_drive_delay,  UVM_ALL_ON)
    `uvm_field_int(post_drive_delay, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "ucie_mainband_seq_item_drv");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("%s, pre_delay=%0d, post_delay=%0d", super.convert2string(), pre_drive_delay, post_drive_delay);
  endfunction

endclass


// 3. Monitor sequence item containing monitor-populated transfer metrics
class ucie_mainband_seq_item_mon extends ucie_mainband_seq_item_base;

  int unsigned length;
  int unsigned prev_item_delay;

  `uvm_object_utils_begin(ucie_mainband_seq_item_mon)
    `uvm_field_int(length,          UVM_ALL_ON)
    `uvm_field_int(prev_item_delay, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "ucie_mainband_seq_item_mon");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("%s, length=%0d, prev_delay=%0d", super.convert2string(), length, prev_item_delay);
  endfunction

endclass

// Alias for default sequence item usage
typedef ucie_mainband_seq_item_drv ucie_mainband_seq_item;
