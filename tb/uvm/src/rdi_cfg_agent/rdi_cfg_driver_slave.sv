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

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (agent_config != null) begin
      vif = agent_config.get_vif_tx();
    end
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_slave_cb.cfg_crd <= 1'b0;

    wait(vif.rst_n === 1'b1);
    
    credit_return_handler();
  endtask

  // Automatically pulse credit grant when valid chunk is sampled on mon_cb
  task credit_return_handler();
    forever begin
      @(vif.drv_slave_cb);
      if (vif.mon_cb.cfg_vld) begin
        // Return 1 chunk credit next cycle
        vif.drv_slave_cb.cfg_crd <= 1'b1;
      end else begin
        vif.drv_slave_cb.cfg_crd <= 1'b0;
      end
    end
  endtask

endclass
