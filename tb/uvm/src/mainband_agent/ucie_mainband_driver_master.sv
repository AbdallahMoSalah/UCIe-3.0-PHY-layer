// =============================================================================
//  ucie_mainband_driver_master
// -----------------------------------------------------------------------------
//  Master driver for downstream Mainband path (Adapter -> PHY).
//  Drives Mainband Flit data and performs valid/ready handshakes.
// =============================================================================

class ucie_mainband_driver_master extends uvm_driver #(ucie_mainband_seq_item_drv) implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_driver_master)

  ucie_mainband_master_agent_config agent_config;
  virtual ucie_mainband_master_if   vif;

  protected process process_drive_transactions;

  function new(string name = "ucie_mainband_driver_master", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(ucie_mainband_master_agent_config)::get(this, "", "cfg", agent_config));
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (agent_config != null) begin
      vif = agent_config.get_vif();
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      fork
        begin
          wait_reset_end();
          drive_transactions();
          disable fork;
        end
      join
    end
  endtask

  protected virtual task wait_reset_end();
    if (agent_config != null) begin
      agent_config.wait_reset_end();
    end
  endtask

  protected virtual task drive_transactions();
    if (vif != null) begin
      vif.lp_valid <= 1'b0;
      vif.lp_irdy  <= 1'b0;
      vif.lp_data  <= '0;
    end

    fork
      begin
        process_drive_transactions = process::self();
        forever begin
          seq_item_port.get_next_item(req);
          drive_transfer(req);
          seq_item_port.item_done();
        end
      end
    join
  endtask

  protected virtual task drive_transfer(ucie_mainband_seq_item_drv item);
    // Pre-drive delay
    for (int i = 0; i < item.pre_drive_delay; i++) begin
      @(posedge vif.clk);
    end

    // Drive Valid, Ready, and Data on negedge clock edge
    @(negedge vif.clk);
    vif.lp_valid <= 1'b1;
    vif.lp_irdy  <= 1'b1;
    vif.lp_data  <= item.data;

    // Wait on positive clock edge for handshake completion (lp_valid & lp_irdy & pl_trdy)
    do begin
      @(posedge vif.clk);
    end while (vif.pl_trdy !== 1'b1 && vif.rst_n);

    `uvm_info("MB_DRV_TRACK", $sformatf("Time=%0t Driven Master item:: %0s", $time, item.convert2string()), UVM_DEBUG)

    // Complete handshake and deassert signals
    @(negedge vif.clk);
    vif.lp_valid <= 1'b0;
    vif.lp_irdy  <= 1'b0;
    vif.lp_data  <= '0;

    // Post-drive delay
    for (int i = 0; i < item.post_drive_delay; i++) begin
      @(posedge vif.clk);
    end
  endtask

  virtual function void handle_reset(uvm_phase phase);
    if (process_drive_transactions != null) begin
      process_drive_transactions.kill();
      process_drive_transactions = null;
    end
    if (vif != null) begin
      vif.lp_valid <= 1'b0;
      vif.lp_irdy  <= 1'b0;
      vif.lp_data  <= '0;
    end
  endfunction

endclass
