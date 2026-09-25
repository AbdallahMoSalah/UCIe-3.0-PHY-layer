// =============================================================================
//  ucie_ltsm_monitor
// -----------------------------------------------------------------------------
//  Passive monitor tracking internal LTSM states of both dies.
// =============================================================================

class ucie_ltsm_monitor extends uvm_monitor;
  `uvm_component_utils(ucie_ltsm_monitor)

  virtual ucie_ltsm_monitor_if vif;

  // Independent analysis ports for Die 0 and Die 1
  uvm_analysis_port#(ltsm_state_transaction) ap_die0;
  uvm_analysis_port#(ltsm_state_transaction) ap_die1;

  function new(string name = "ucie_ltsm_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap_die0 = new("ap_die0", this);
    ap_die1 = new("ap_die1", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie_ltsm_monitor_if)::get(this, "", "vif_ltsm", vif)) begin
      `uvm_fatal("LTSM_MON_ERR", "Failed to retrieve virtual interface 'vif_ltsm'")
    end
  endfunction

  task run_phase(uvm_phase phase);
    wait(vif.rst_n === 1'b1);

    fork
      // Die 0 (Local) Monitoring Thread
      begin
        ltsm_state_n_pkg::state_n_e   prev_log0  = ltsm_state_n_pkg::LOG_RESET;
        LTSM_state_pkg::LTSM_state_e  prev_ctrl0 = LTSM_state_pkg::RESET;

        forever begin
          @(posedge vif.clk0);
          if (vif.rst_n) begin
            if (vif.state0 != prev_log0 || vif.ctrl_state0 != prev_ctrl0) begin
              ltsm_state_transaction tx = ltsm_state_transaction::type_id::create("tx");
              tx.die_idx    = 0;
              tx.log_state  = vif.state0;
              tx.ctrl_state = vif.ctrl_state0;
              
              `uvm_info("LTSM_MON_D0", $sformatf("State Change Detected: %s", tx.convert2string()), UVM_MEDIUM)
              ap_die0.write(tx);

              prev_log0  = vif.state0;
              prev_ctrl0 = vif.ctrl_state0;
            end
          end
        end
      end

      // Die 1 (Partner) Monitoring Thread
      begin
        ltsm_state_n_pkg::state_n_e   prev_log1  = ltsm_state_n_pkg::LOG_RESET;
        LTSM_state_pkg::LTSM_state_e  prev_ctrl1 = LTSM_state_pkg::RESET;

        forever begin
          @(posedge vif.clk1);
          if (vif.rst_n) begin
            if (vif.state1 != prev_log1 || vif.ctrl_state1 != prev_ctrl1) begin
              ltsm_state_transaction tx = ltsm_state_transaction::type_id::create("tx");
              tx.die_idx    = 1;
              tx.log_state  = vif.state1;
              tx.ctrl_state = vif.ctrl_state1;
              
              `uvm_info("LTSM_MON_D1", $sformatf("State Change Detected: %s", tx.convert2string()), UVM_MEDIUM)
              ap_die1.write(tx);

              prev_log1  = vif.state1;
              prev_ctrl1 = vif.ctrl_state1;
            end
          end
        end
      end
    join
  endtask

endclass
