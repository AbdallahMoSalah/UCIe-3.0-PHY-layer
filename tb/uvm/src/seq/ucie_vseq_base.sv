// =============================================================================
//  ucie_vseq_base
// -----------------------------------------------------------------------------
//  Base Virtual Sequence class. Contains sequencer and register model handles,
//  virtual interface pointers, and common utility tasks to simplify derived
//  sequences. Uses the sequencer-less style (handles mapped manually by test).
// =============================================================================

class ucie_vseq_base extends uvm_sequence;
  `uvm_object_utils(ucie_vseq_base)
  `uvm_declare_p_sequencer(ucie_virtual_sequencer)

  // Sequencer handles
  rdi_cfg_sequencer           cfg_seqr_L;
  rdi_cfg_sequencer           cfg_seqr_P;

  // Register model handles (RAL)
  ucie_reg_block              reg_model_L;
  ucie_reg_block              reg_model_P;

  // Virtual interfaces (probed and channel controls)
  virtual ucie_ltsm_monitor_if vif_ltsm;
  virtual ucie_channel_if      vif_channel;
  virtual ucie_rdi_if          vif_rdi;

  function new(string name = "ucie_vseq_base");
    super.new(name);
  endfunction

  // Helper task: Send Mainband data burst on Die 0, Die 1, or both via p_sequencer
  task send_mainband_burst(bit send_L = 1'b1, bit send_P = 1'b1);
    fork
      if (send_L) begin
        ucie_mainband_burst_seq burst_L = ucie_mainband_burst_seq::type_id::create("burst_L");
        if (!burst_L.randomize()) `uvm_error("VSEQ", "Failed to randomize burst_L")
        burst_L.start(p_sequencer.mainband_sqr_L, this);
      end
      if (send_P) begin
        ucie_mainband_burst_seq burst_P = ucie_mainband_burst_seq::type_id::create("burst_P");
        if (!burst_P.randomize()) `uvm_error("VSEQ", "Failed to randomize burst_P")
        burst_P.start(p_sequencer.mainband_sqr_P, this);
      end
    join
    #500ns; // Pipeline drain time for receiver sampling
  endtask

  // Helper task: Send Sideband remote message burst on Die 0, Die 1, or both via p_sequencer
  task send_sideband_remote_msg(bit send_L = 1'b1, bit send_P = 1'b1);
    fork
      if (send_L) begin
        rdi_cfg_burst_seq burst_sb_L = rdi_cfg_burst_seq::type_id::create("burst_sb_L");
        if (!burst_sb_L.randomize()) `uvm_error("VSEQ", "Failed to randomize burst_sb_L")
        burst_sb_L.start(p_sequencer.rdi_cfg_sqr_L, this);
      end
      if (send_P) begin
        rdi_cfg_burst_seq burst_sb_P = rdi_cfg_burst_seq::type_id::create("burst_sb_P");
        if (!burst_sb_P.randomize()) `uvm_error("VSEQ", "Failed to randomize burst_sb_P")
        burst_sb_P.start(p_sequencer.rdi_cfg_sqr_P, this);
      end
    join
    #2us; // Allow in-flight Sideband packets to finish traversing physical inter-die link
  endtask

  // Helper task: Transmit both Mainband and Sideband bursts concurrently upon reaching Active state
  task send_active_bursts(bit send_L = 1'b1, bit send_P = 1'b1);
    fork
      send_mainband_burst(send_L, send_P);
      send_sideband_remote_msg(send_L, send_P);
    join
  endtask

  // Helper task: Write Local (Die 0) register via RAL
  task write_reg_L(uvm_reg rg, bit [63:0] val);
    uvm_status_e status;
    rg.write(status, val, .parent(this));
  endtask

  // Helper task: Read Local (Die 0) register via RAL
  task read_reg_L(uvm_reg rg, output bit [63:0] val);
    uvm_status_e status;
    rg.read(status, val, .parent(this));
    #200ns; // Wait for transaction completion and predictor mirror update
    val = rg.get_mirrored_value();
  endtask

  // Helper task: Write Partner (Die 1) register via RAL
  task write_reg_P(uvm_reg rg, bit [63:0] val);
    uvm_status_e status;
    rg.write(status, val, .parent(this));
  endtask

  // Helper task: Read Partner (Die 1) register via RAL
  task read_reg_P(uvm_reg rg, output bit [63:0] val);
    uvm_status_e status;
    rg.read(status, val, .parent(this));
    #200ns; // Wait for transaction completion and predictor mirror update
    val = rg.get_mirrored_value();
  endtask

  // Helper task: Block sequence execution until internal state is reached
  task wait_for_ltsm_state(int die_idx, ltsm_state_n_pkg::state_n_e target_state);
    if (die_idx == 0) begin
      wait (vif_ltsm.state0 == target_state);
    end else begin
      wait (vif_ltsm.state1 == target_state);
    end
  endtask

  // Helper task: Block sequence execution until controller state is reached
  task wait_for_ctrl_state(int die_idx, ltsm_state_n_pkg::ltsm_ctrl_state_e target_state);
    if (die_idx == 0) begin
      wait (vif_ltsm.ctrl_state0 == target_state);
    end else begin
      wait (vif_ltsm.ctrl_state1 == target_state);
    end
  endtask

endclass
