// =============================================================================
//  rdi_cfg_driver_slave
// -----------------------------------------------------------------------------
//  Slave driver for upstream configuration path (PHY -> Adapter).
//  Implements automatic credit return (cfg_crd) when PHY drives valid chunks.
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

  // Automatically pulse credit grant when valid chunk is sampled on mon_cb
  task credit_return_handler();
    forever begin
      @(vif.drv_slave_cb);
      if (vif.mon_cb.cfg_vld) begin
        vif.drv_slave_cb.cfg_crd <= 1'b1;
      end else begin
        vif.drv_slave_cb.cfg_crd <= 1'b0;
      end
    end
  endtask

endclass
