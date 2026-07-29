// =============================================================================
//  rdi_cfg_monitor
// -----------------------------------------------------------------------------
//  Base monitor for RDI Configuration bus.
//  Provides shared configuration references, interface handles, helper methods,
//  and a static tag completion lookup table (pending_reqs) keyed by {die_idx, tag}
//  shared between Master (requests) and Slave (completions) monitors of each die.
// =============================================================================

class rdi_cfg_monitor extends uvm_monitor implements rdi_cfg_reset_handler;
  `uvm_component_utils(rdi_cfg_monitor)

  rdi_cfg_sub_agent_config agent_config;
  virtual rdi_cfg_if       vif;

  // Primary analysis port exposing monitored transactions
  uvm_analysis_port#(rdi_cfg_seq_item_mon) ap;

  // Shared static completion table keyed by {die_idx (1-bit), tag (5-bit)}
  static rdi_cfg_seq_item_mon pending_reqs[bit [5:0]];

  protected process process_collect_transactions;

  function new(string name = "rdi_cfg_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(rdi_cfg_sub_agent_config)::get(this, "", "cfg", agent_config));
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (agent_config != null) begin
      vif = agent_config.get_vif();
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
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

  protected virtual function bit is_response_direction();
    return 1'b0;
  endfunction

  protected virtual function void process_monitored_item(rdi_cfg_seq_item_mon item);
  endfunction

  // Task which collects transactions from virtual interface
  protected virtual task collect_transaction();
    bit [127:0]          raw_data = '0;
    int                  chunk_idx = 0;
    int                  expected_chunks = 2;
    sb_pkg::sb_opcode_e  opcode;
    int unsigned         idle_cnt = 0;

    forever begin
      @(vif.mon_cb);
      if (!vif.mon_cb.cfg_vld) begin
        if (chunk_idx == 0) begin
          idle_cnt++;
        end
      end else begin
        raw_data[chunk_idx*32 +: 32] = vif.mon_cb.cfg;
        if (chunk_idx == 0) begin
          opcode = sb_pkg::sb_opcode_e'(vif.mon_cb.cfg[4:0]);
          expected_chunks = get_expected_chunks(opcode);
        end
        chunk_idx++;

        if (chunk_idx == expected_chunks) begin
          rdi_cfg_seq_item_mon item = rdi_cfg_seq_item_mon::type_id::create("item");
          item.sb_pkt.header.raw = raw_data[63:0];
          item.sb_pkt.payload    = raw_data[127:64];
          item.unpack_from_struct();
          item.is_response       = is_response_direction();
          item.length            = expected_chunks;
          item.prev_item_delay   = idle_cnt;

          process_monitored_item(item);
          ap.write(item);

          chunk_idx = 0;
          raw_data  = '0;
          idle_cnt  = 0;
        end
      end
    end
  endtask

  // Base task for collecting all transactions
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

  virtual function void handle_reset(uvm_phase phase);
    if (process_collect_transactions != null) begin
      process_collect_transactions.kill();
      process_collect_transactions = null;
    end
  endfunction

  // Helper function to decode expected chunk count based on sideband opcode
  function int get_expected_chunks(sb_pkg::sb_opcode_e op);
    return sb_pkg::get_expected_chunks(op);
  endfunction

endclass
