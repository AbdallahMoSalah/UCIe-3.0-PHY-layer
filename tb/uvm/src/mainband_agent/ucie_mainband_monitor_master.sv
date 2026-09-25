// =============================================================================
//  ucie_mainband_monitor_master
// -----------------------------------------------------------------------------
//  Master monitor for downstream Mainband path (Adapter -> PHY).
//  Samples Tx flits driven into RTL (lp_valid, lp_irdy, lp_data, pl_trdy).
// =============================================================================

class ucie_mainband_monitor_master extends uvm_monitor implements ucie_mainband_reset_handler;
  `uvm_component_utils(ucie_mainband_monitor_master)

  ucie_mainband_master_agent_config agent_config;
  virtual ucie_mainband_master_if   vif;

  // Primary analysis port exposing monitored Tx flits
  uvm_analysis_port #(ucie_mainband_seq_item_mon) ap;

  protected process process_collect_transactions;

  function new(string name = "ucie_mainband_monitor_master", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
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
          collect_transactions();
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

  protected virtual task collect_transactions();
    fork
      begin
        process_collect_transactions = process::self();
        forever begin
          collect_transaction();
        end
      end
    join
  endtask

  protected virtual task collect_transaction();
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
          ap.write(item);
          `uvm_info("MB_MON_TX_TRACK", $sformatf("Time=%0t Monitored Master Tx item:: %0s", $time, item.convert2string()), UVM_DEBUG)
        end

        idle_cnt = 0;
      end
    end
  endtask

  virtual function void handle_reset(uvm_phase phase);
    if (process_collect_transactions != null) begin
      process_collect_transactions.kill();
      process_collect_transactions = null;
    end
  endfunction

endclass
