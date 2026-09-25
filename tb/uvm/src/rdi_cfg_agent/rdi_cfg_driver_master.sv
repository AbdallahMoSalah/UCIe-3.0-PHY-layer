// =============================================================================
//  rdi_cfg_driver_master
// -----------------------------------------------------------------------------
//  Master driver for downstream configuration path (Adapter -> PHY).
//  Splits 128-bit transaction items into 32-bit chunks and drives them onto the bus.
// =============================================================================

class rdi_cfg_driver_master extends rdi_cfg_driver;
  `uvm_component_utils(rdi_cfg_driver_master)

  function new(string name = "rdi_cfg_driver_master", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  protected virtual task drive_transaction(rdi_cfg_seq_item item);
    drive_item(item);
  endtask

  virtual function void handle_reset(uvm_phase phase);
    super.handle_reset(phase);
    vif.drv_master_cb.cfg     <= '0;
    vif.drv_master_cb.cfg_vld <= 1'b0;
  endfunction

  // Drives transaction item chunk-by-chunk onto RDI config bus
  task drive_item(rdi_cfg_seq_item item);
    int num_chunks;
    bit [127:0] raw_data;
    
    repeat (item.pre_drive_delay) @(vif.drv_master_cb);

    item.pack_to_struct();
    raw_data = {item.sb_pkt.payload, item.sb_pkt.header.raw};

    // Decode expected chunk count from opcode
    num_chunks = sb_pkg::get_expected_chunks(item.opcode);

    `uvm_info("CFG_DRV_MASTER", $sformatf("Driving Master item: %s (%d chunks)", item.convert2string(), num_chunks), UVM_HIGH)

    // Drive chunks synchronously via drv_master_cb
    for (int i = 0; i < num_chunks; i++) begin
      @(vif.drv_master_cb);
      vif.drv_master_cb.cfg_vld <= 1'b1;
      vif.drv_master_cb.cfg     <= raw_data[i*32 +: 32];
    end
    
    @(vif.drv_master_cb);
    vif.drv_master_cb.cfg_vld <= 1'b0;
    vif.drv_master_cb.cfg     <= '0;

    repeat (item.post_drive_delay) @(vif.drv_master_cb);
  endtask

endclass
