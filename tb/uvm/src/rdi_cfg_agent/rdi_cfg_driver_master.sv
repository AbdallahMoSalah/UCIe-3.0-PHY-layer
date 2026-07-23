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

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (agent_config != null) begin
      vif = agent_config.get_vif_rx();
    end
  endfunction

  task run_phase(uvm_phase phase);
    // Reset signals on startup via clocking block
    vif.drv_master_cb.cfg     <= '0;
    vif.drv_master_cb.cfg_vld <= 1'b0;

    wait(vif.rst_n === 1'b1);
    
    get_and_drive();
  endtask

  // Fetch sequence items and drive them
  task get_and_drive();
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  // Drives transaction item chunk-by-chunk onto RDI config bus
  task drive_item(rdi_cfg_seq_item item);
    int num_chunks;
    bit [127:0] raw_data;
    
    item.pack_to_struct();
    raw_data = {item.sb_pkt.payload, item.sb_pkt.header.raw};

    // Decode expected chunk count from opcode
    case (item.opcode)
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_32_CFG_READ,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_DMS_REG_READ, sb_pkg::SB_64_CFG_READ,
      sb_pkg::SB_COMPLETION_WITHOUT_DATA, sb_pkg::SB_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA: begin
        num_chunks = 2; // Header only
      end
      
      sb_pkg::SB_32_MEM_WRITE, sb_pkg::SB_32_DMS_REG_WRITE, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_COMPLETION_WITH_32_DATA: begin
        num_chunks = 3; // Header + 32-bit data
      end
      
      sb_pkg::SB_64_MEM_WRITE, sb_pkg::SB_64_DMS_REG_WRITE, sb_pkg::SB_64_CFG_WRITE,
      sb_pkg::SB_COMPLETION_WITH_64_DATA, sb_pkg::SB_MSG_WITH_64_DATA: begin
        num_chunks = 4; // Header + 64-bit data
      end
      
      default: num_chunks = 2;
    endcase

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
  endtask

endclass
