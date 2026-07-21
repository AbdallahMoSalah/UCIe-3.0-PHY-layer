// =============================================================================
//  rdi_cfg_driver
// -----------------------------------------------------------------------------
//  Drives configuration transactions onto the RDI Config interface.
//  Splits 128-bit packets into 32-bit chunks (2, 3, or 4 chunks based on opcode)
//  and implements automatic credit return to the PHY.
// =============================================================================

class rdi_cfg_driver extends uvm_driver #(rdi_cfg_seq_item);
  `uvm_component_utils(rdi_cfg_driver)

  rdi_cfg_agent_config cfg;
  virtual rdi_cfg_if   vif;

  function new(string name = "rdi_cfg_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(rdi_cfg_agent_config)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("DRV_ERR", "Failed to retrieve agent configuration 'cfg'")
    end
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    // Reset signals on startup
    vif.lp_cfg     <= '0;
    vif.lp_cfg_vld <= 1'b0;
    vif.lp_cfg_crd <= 1'b0;

    wait(vif.rst_n === 1'b1);
    
    fork
      get_and_drive();
      credit_return_handler();
    join
  endtask

  // Fetch sequence items and drive them
  task get_and_drive();
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  // Drives the transaction item chunk-by-chunk onto the RDI config bus
  task drive_item(rdi_cfg_seq_item item);
    int num_chunks;
    bit [127:0] raw_data;
    
    item.pack_to_struct();
    raw_data = {item.sb_pkt.payload, item.sb_pkt.header.raw};

    // Decode expected chunk count from opcode (matching rdi_aggregator.sv logic)
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

    `uvm_info("CFG_DRV", $sformatf("Driving TX item: %s (%d chunks)", item.convert2string(), num_chunks), UVM_HIGH)

    // Drive chunks synchronously
    for (int i = 0; i < num_chunks; i++) begin
      @(vif.drv_cb);
      vif.drv_cb.lp_cfg_vld <= 1'b1;
      vif.drv_cb.lp_cfg     <= raw_data[i*32 +: 32];
    end
    
    @(vif.drv_cb);
    vif.drv_cb.lp_cfg_vld <= 1'b0;
    vif.drv_cb.lp_cfg     <= '0;
  endtask

  // Automatically pulse credit grant when the PHY drives chunks on pl_cfg
  task credit_return_handler();
    forever begin
      @(vif.drv_cb);
      // Whenever we sample pl_cfg_vld high on the clock edge, consume it
      if (vif.mon_cb.pl_cfg_vld) begin
        // Return 1 chunk credit next cycle
        vif.drv_cb.lp_cfg_crd <= 1'b1;
      end else begin
        vif.drv_cb.lp_cfg_crd <= 1'b0;
      end
    end
  endtask

endclass
