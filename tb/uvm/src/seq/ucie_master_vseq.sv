// =============================================================================
//  ucie_master_vseq
// -----------------------------------------------------------------------------
//  Unified UVM master virtual sequence executing the parameterized test plan.
//  Triggers and verifies link training, handles the RDI active state transition
//  and clock handshakes, and runs power management transitions.
// =============================================================================

class ucie_master_vseq extends ucie_vseq_base;
  `uvm_object_utils(ucie_master_vseq)

  ucie_scenario_cfg cfg;

  function new(string name = "ucie_master_vseq");
    super.new(name);
  endfunction

  virtual task body();
    if (cfg == null) begin
      `uvm_fatal("VSEQ_ERR", "Scenario configuration 'cfg' is null!")
    end

    `uvm_info("VSEQ_START", $sformatf("Starting master virtual sequence"), UVM_LOW)

    // 0. Wait for reset release and stable clocks
    wait (vif_ltsm.rst_n === 1'b1);
    repeat (10) @(posedge vif_ltsm.clk0);
    `uvm_info("VSEQ_START", "Reset released and clocks stable. Starting programming...", UVM_LOW)

    // Initialize RDI state requests to Nop to release reset
    vif_rdi.lp_state_req0 = RDI_SM_pkg::Nop;
    vif_rdi.lp_state_req1 = RDI_SM_pkg::Nop;

    // 1. Apply physical package channel settings/faults
    vif_channel.corrupt_0to1               = cfg.corrupt_lanes_L2P;
    vif_channel.corrupt_1to0               = cfg.corrupt_lanes_P2L;
    vif_channel.reverse_0to1               = cfg.reverse_L2P;
    vif_channel.reverse_1to0               = cfg.reverse_P2L;
    vif_channel.block_sideband             = cfg.block_sideband;
    vif_channel.rx_vld_error_inject_0_to_1 = cfg.inject_vld_error;

    // 2. Program speed and width configuration in RAL on both dies
    write_reg_L(reg_model_L.ucie_link_ctrl, {10'h0, cfg.target_speed_L, cfg.target_width_L, 2'h0});
    write_reg_P(reg_model_P.ucie_link_ctrl, {10'h0, cfg.target_speed_P, cfg.target_width_P, 2'h0});

    // 3. Kick link training by writing start bit (bit 10) in ucie_link_ctrl
    `uvm_info("VSEQ_TRAIN", "Kicking link training via start bit write...", UVM_LOW)
    write_reg_L(reg_model_L.ucie_link_ctrl, {10'h0, cfg.target_speed_L, cfg.target_width_L, 2'h0} | 32'h0000_0400);
    write_reg_P(reg_model_P.ucie_link_ctrl, {10'h0, cfg.target_speed_P, cfg.target_width_P, 2'h0} | 32'h0000_0400);

    // 4. Wait for inband_pres on both dies
    `uvm_info("VSEQ_TRAIN", "Waiting for inband_pres on both dies...", UVM_LOW)
    if (!cfg.expect_trainerror) begin
      wait (vif_rdi.pl_inband_pres0 === 1'b1 && vif_rdi.pl_inband_pres1 === 1'b1);
    end

    // Request Active state once inband_pres is asserted
    if (!cfg.expect_trainerror) begin
      vif_rdi.lp_state_req0 = RDI_SM_pkg::Active;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::Active;
    end

    // 5. Verify transition completion and negotiated link speed/width
    if (cfg.expect_active) begin
      `uvm_info("VSEQ_TRAIN", "Waiting for pl_state_sts to reach Active...", UVM_LOW)
      wait (vif_rdi.pl_state_sts0 == RDI_SM_pkg::Active && vif_rdi.pl_state_sts1 == RDI_SM_pkg::Active);

      `uvm_info("VSEQ_TRAIN", "Link trained to Active state on both dies successfully!", UVM_LOW)

      // Verification of Negotiated Speed/Width from registers
      begin
        bit [63:0] status_val_L;
        bit [63:0] status_val_P;
        
        read_reg_L(reg_model_L.ucie_link_status, status_val_L);
        read_reg_P(reg_model_P.ucie_link_status, status_val_P);

        // link_status is bit [15]. Width is [10:7]. Speed is [14:11].
        if (status_val_L[15] !== 1'b1) begin
          `uvm_error("VSEQ_CHECK", $sformatf("Local link status bit 15 is not active: %h", status_val_L))
        end
        if (status_val_L[10:7] !== cfg.expect_negotiated_width_L) begin
          `uvm_error("VSEQ_CHECK", $sformatf("Width mismatch: expected %0d, got %0d", 
                      cfg.expect_negotiated_width_L, status_val_L[10:7]))
        end
        if (status_val_L[14:11] !== cfg.expect_negotiated_speed_L) begin
          `uvm_error("VSEQ_CHECK", $sformatf("Speed mismatch: expected %0d, got %0d", 
                      cfg.expect_negotiated_speed_L, status_val_L[14:11]))
        end
      end

      // Transmit Mainband data burst and Sideband remote message burst concurrently upon reaching Active state
      send_active_bursts();
    end 
    else if (cfg.expect_trainerror) begin
      `uvm_info("VSEQ_TRAIN", "Waiting for link to signal pl_trainerror or state LOG_TRAINERROR...", UVM_LOW)
      wait (vif_rdi.pl_trainerror0 === 1'b1 || vif_rdi.pl_trainerror1 === 1'b1 ||
            vif_ltsm.state0 == ltsm_state_n_pkg::LOG_TRAINERROR || vif_ltsm.state1 == ltsm_state_n_pkg::LOG_TRAINERROR ||
            vif_ltsm.ctrl_state0 == ltsm_state_n_pkg::CTRL_TRAINERROR || vif_ltsm.ctrl_state1 == ltsm_state_n_pkg::CTRL_TRAINERROR);
      `uvm_info("VSEQ_TRAIN", "Link entered training error state as expected.", UVM_LOW)
    end

    // 6. Execute Power Management (PM) test flows
    if (cfg.run_pm_l1 && cfg.expect_active) begin
      `uvm_info("VSEQ_PM", "Initiating PM transition to L1 state...", UVM_LOW)
      
      // Request L1 state transition
      vif_rdi.lp_state_req0 = RDI_SM_pkg::L_1;
      #1us;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::L_1;

      // Wait until FSMs power down to L1
      wait (vif_rdi.pl_state_sts0 == RDI_SM_pkg::L_1 && vif_rdi.pl_state_sts1 == RDI_SM_pkg::L_1);
      `uvm_info("VSEQ_PM", "Link successfully settled in L1 state", UVM_LOW)

      #200ns;

      // Exit L1: Trigger wakeups
      `uvm_info("VSEQ_PM", "Waking up link from L1...", UVM_LOW)
      vif_rdi.lp_wake_req0 = 1'b1;
      vif_rdi.lp_wake_req1 = 1'b1;
      
      wait (vif_rdi.pl_wake_ack0 === 1'b1);
      vif_rdi.lp_wake_req0 = 1'b0;
      vif_rdi.lp_wake_req1 = 1'b0;

      // Kick L1 -> Retrain transition with Active, then drop to Nop while retraining
      vif_rdi.lp_state_req0 = RDI_SM_pkg::Active;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::Active;
      #50ns;
      vif_rdi.lp_state_req0 = RDI_SM_pkg::Nop;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::Nop;

      // Wait for inband_pres, then request Active for final handshake
      wait (vif_rdi.pl_inband_pres0 === 1'b1 && vif_rdi.pl_inband_pres1 === 1'b1);
      vif_rdi.lp_state_req0 = RDI_SM_pkg::Active;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::Active;

      // Retrain back to Active
      wait (vif_rdi.pl_state_sts0 == RDI_SM_pkg::Active && vif_rdi.pl_state_sts1 == RDI_SM_pkg::Active);
      `uvm_info("VSEQ_PM", "Link retrained back to Active state successfully.", UVM_LOW)

      // Transmit Mainband data burst and Sideband remote message burst concurrently upon returning to Active state
      send_active_bursts();
    end

    if (cfg.run_pm_l2 && cfg.expect_active) begin
      `uvm_info("VSEQ_PM", "Initiating PM transition to L2 state...", UVM_LOW)
      
      // Request L2 state transition
      vif_rdi.lp_state_req0 = RDI_SM_pkg::L_2;
      #1us;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::L_2;

      // Wait until FSMs power down to L2
      wait (vif_rdi.pl_state_sts0 == RDI_SM_pkg::L_2 && vif_rdi.pl_state_sts1 == RDI_SM_pkg::L_2);
      `uvm_info("VSEQ_PM", "Link successfully settled in L2 state", UVM_LOW)

      #200ns;

      // Exit L2: Per UCIe spec, requesting Active triggers L2 -> Reset transition
      `uvm_info("VSEQ_PM", "Waking up link from L2...", UVM_LOW)
      vif_rdi.lp_state_req0 = RDI_SM_pkg::Active;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::Active;

      wait (vif_rdi.pl_state_sts0 == RDI_SM_pkg::Reset && vif_rdi.pl_state_sts1 == RDI_SM_pkg::Reset);
      `uvm_info("VSEQ_PM", "Link successfully transitioned from L2 to Reset", UVM_LOW)

      vif_rdi.lp_state_req0 = RDI_SM_pkg::Nop;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::Nop;

      // Re-trigger start bit write to start link training after Reset exit on both dies
      write_reg_L(reg_model_L.ucie_link_ctrl, {10'h0, cfg.target_speed_L, cfg.target_width_L, 2'h0} | 32'h0000_0400);
      write_reg_P(reg_model_P.ucie_link_ctrl, {10'h0, cfg.target_speed_P, cfg.target_width_P, 2'h0} | 32'h0000_0400);

      vif_rdi.lp_state_req0 = RDI_SM_pkg::Active;
      vif_rdi.lp_state_req1 = RDI_SM_pkg::Active;

      // Retrain back to Active
      wait (vif_rdi.pl_state_sts0 == RDI_SM_pkg::Active && vif_rdi.pl_state_sts1 == RDI_SM_pkg::Active);
      `uvm_info("VSEQ_PM", "Link retrained back to Active state successfully.", UVM_LOW)

      // Transmit Mainband data burst and Sideband remote message burst concurrently upon returning to Active state
      send_active_bursts();
    end

    `uvm_info("VSEQ_DONE", "Master virtual sequence complete", UVM_LOW)
  endtask

endclass
