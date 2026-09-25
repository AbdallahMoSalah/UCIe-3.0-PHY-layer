// =============================================================================
//  rdi_cfg_driver_slave
// -----------------------------------------------------------------------------
//  Slave driver for upstream configuration path (PHY -> Adapter).
//  Implements credit return (cfg_crd) per complete packet for non-completion
//  packets (requests & messages).
// =============================================================================

class rdi_cfg_driver_slave extends rdi_cfg_driver;
  `uvm_component_utils(rdi_cfg_driver_slave)

  function new(string name = "rdi_cfg_driver_slave", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  protected virtual task drive_transactions();
    vif.drv_slave_cb.cfg_crd <= 1'b0;
    fork
      begin
        process_drive_transactions = process::self();
        credit_return_handler();
      end
    join
  endtask

  virtual function void handle_reset(uvm_phase phase);
    super.handle_reset(phase);
    vif.drv_slave_cb.cfg_crd <= 1'b0;
  endfunction

  // Automatically pulse credit grant (cfg_crd) when a complete non-completion packet is sampled
  task credit_return_handler();
    int                 chunk_idx = 0;
    int                 expected_chunks = 2;
    sb_pkg::sb_opcode_e opcode;

    vif.drv_slave_cb.cfg_crd <= 1'b0;

    forever begin
      @(vif.drv_slave_cb);
      vif.drv_slave_cb.cfg_crd <= 1'b0;

      if (vif.drv_slave_cb.cfg_vld) begin
        if (chunk_idx == 0) begin
          opcode = sb_pkg::sb_opcode_e'(vif.drv_slave_cb.cfg[4:0]);
          expected_chunks = sb_pkg::get_expected_chunks(opcode);
        end
        chunk_idx++;

        if (chunk_idx == expected_chunks) begin
          // Check if opcode is NOT a completion (completions do not return credits)
          if (!(opcode inside {
            sb_pkg::SB_COMPLETION_WITHOUT_DATA,
            sb_pkg::SB_COMPLETION_WITH_32_DATA,
            sb_pkg::SB_COMPLETION_WITH_64_DATA
          })) begin
            vif.drv_slave_cb.cfg_crd <= 1'b1;
          end

          chunk_idx = 0;
        end
      end
    end
  endtask

endclass
