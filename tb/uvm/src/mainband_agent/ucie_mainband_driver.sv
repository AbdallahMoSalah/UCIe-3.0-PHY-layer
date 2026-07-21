// =============================================================================
//  ucie_mainband_driver
// -----------------------------------------------------------------------------
//  UVM Driver for driving Mainband Flit data and performing valid/ready handshakes
//  with randomized pre/post drive delays, UVM_DEBUG tracing, and reset handling.
// =============================================================================

class ucie_mainband_driver extends uvm_driver #(ucie_mainband_seq_item_drv) implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_driver)

  virtual ucie_mainband_if vif;

  protected process process_drive_transactions;

  function new(string name = "ucie_mainband_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie_mainband_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("DRIVER", "Failed to retrieve virtual ucie_mainband_if handle from config DB")
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

  task wait_reset_end();
    while (vif.rst_n == 1'b0) begin
      @(posedge vif.clk);
    end
  endtask

  protected virtual task drive_transactions();
    vif.lp_valid <= 1'b0;
    vif.lp_irdy  <= 1'b0;
    vif.lp_data  <= '0;

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

  virtual function void handle_reset(uvm_phase phase);
    if (process_drive_transactions != null) begin
      process_drive_transactions.kill();
      process_drive_transactions = null;
    end

    // Re-initialize interface signals upon reset
    vif.lp_valid <= 1'b0;
    vif.lp_irdy  <= 1'b0;
    vif.lp_data  <= '0;
  endfunction

  task drive_transfer(ucie_mainband_seq_item_drv item);
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

    `uvm_info("MB_DRV_TRACK", $sformatf("Time=%0t Driven item:: %0s", $time, item.convert2string()), UVM_DEBUG)

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

endclass
