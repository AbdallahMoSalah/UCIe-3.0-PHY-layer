// =============================================================================
//  ucie_mainband_monitor
// -----------------------------------------------------------------------------
//  UVM Passive Monitor running 2 concurrent threads to sample Tx and Rx Mainband flits,
//  populating item length and prev_item_delay on ucie_mainband_seq_item_mon,
//  logging at UVM_DEBUG, and handling resets.
// =============================================================================

class ucie_mainband_monitor extends uvm_monitor implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_monitor)

  virtual ucie_mainband_if vif;

  // Analysis Ports for Tx and Rx streams producing ucie_mainband_seq_item_mon
  uvm_analysis_port #(ucie_mainband_seq_item_mon) ap_tx;
  uvm_analysis_port #(ucie_mainband_seq_item_mon) ap_rx;

  protected process process_tx_monitor;
  protected process process_rx_monitor;

  function new(string name = "ucie_mainband_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap_tx = new("ap_tx", this);
    ap_rx = new("ap_rx", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie_mainband_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("MONITOR", "Failed to retrieve virtual ucie_mainband_if handle from config DB")
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      fork
        begin
          wait_reset_end();
          collect_transactions();
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

  protected virtual task collect_transactions();
    fork
      begin
        process_tx_monitor = process::self();
        tx_monitor();
      end
      begin
        process_rx_monitor = process::self();
        rx_monitor();
      end
    join
  endtask

  virtual function void handle_reset(uvm_phase phase);
    if (process_tx_monitor != null) begin
      process_tx_monitor.kill();
      process_tx_monitor = null;
    end
    if (process_rx_monitor != null) begin
      process_rx_monitor.kill();
      process_rx_monitor = null;
    end
  endfunction

  // Thread 1: Monitor Transmitted Flits on Tx side (valid && irdy && trdy)
  task tx_monitor();
    int unsigned idle_cnt;
    idle_cnt = 0;

    forever begin
      @(posedge vif.clk);

      if (!vif.rst_n) begin
        idle_cnt = 0;
      end else if (!(vif.lp_valid && vif.lp_irdy)) begin
        idle_cnt++;
      end else begin
        // Tx transfer initiated
        ucie_mainband_seq_item_mon item;
        item = ucie_mainband_seq_item_mon::type_id::create("tx_item");
        item.prev_item_delay = idle_cnt;
        item.data            = vif.lp_data;
        item.length          = 1;

        // Count cycles while waiting for pl_trdy handshake completion
        while (vif.rst_n && !(vif.lp_valid && vif.lp_irdy && vif.pl_trdy)) begin
          @(posedge vif.clk);
          item.length++;
        end

        if (vif.rst_n) begin
          ap_tx.write(item);
          `uvm_info("MB_MON_TX_TRACK", $sformatf("Time=%0t Monitored Tx item:: %0s", $time, item.convert2string()), UVM_DEBUG)
        end

        idle_cnt = 0;
      end
    end
  endtask

  // Thread 2: Monitor Received Flits on Rx side (pl_valid)
  task rx_monitor();
    int unsigned idle_cnt;
    idle_cnt = 0;

    forever begin
      @(posedge vif.clk);

      if (!vif.rst_n) begin
        idle_cnt = 0;
      end else if (!vif.pl_valid) begin
        idle_cnt++;
      end else begin
        // Rx Flit received
        ucie_mainband_seq_item_mon item;
        item = ucie_mainband_seq_item_mon::type_id::create("rx_item");
        item.prev_item_delay = idle_cnt;
        item.data            = vif.pl_data;
        item.length          = 1;

        ap_rx.write(item);
        `uvm_info("MB_MON_RX_TRACK", $sformatf("Time=%0t Monitored Rx item:: %0s", $time, item.convert2string()), UVM_DEBUG)

        idle_cnt = 0;
      end
    end
  endtask

endclass
