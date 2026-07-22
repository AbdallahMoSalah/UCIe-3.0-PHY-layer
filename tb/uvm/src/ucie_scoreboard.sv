// =============================================================================
//  ucie_scoreboard
// -----------------------------------------------------------------------------
//  UVM Scoreboard utilizing TLM analysis FIFOs and analysis exports to compare
//  Mainband and Sideband cross-die transactions across Die 0 and Die 1.
//  Filters out local PHY register transactions and queues cross-die messages.
// =============================================================================

`uvm_analysis_imp_decl(_sb_die0_tx)
`uvm_analysis_imp_decl(_sb_die0_rx)
`uvm_analysis_imp_decl(_sb_die1_tx)
`uvm_analysis_imp_decl(_sb_die1_rx)

class ucie_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(ucie_scoreboard)

  // 4 Mainband TLM Analysis FIFOs
  uvm_tlm_analysis_fifo #(ucie_mainband_seq_item_mon) fifo_die0_tx;
  uvm_tlm_analysis_fifo #(ucie_mainband_seq_item_mon) fifo_die0_rx;
  uvm_tlm_analysis_fifo #(ucie_mainband_seq_item_mon) fifo_die1_tx;
  uvm_tlm_analysis_fifo #(ucie_mainband_seq_item_mon) fifo_die1_rx;

  // 4 Sideband TLM Analysis FIFOs for Cross-Die RDI Config / Messages
  uvm_tlm_analysis_fifo #(rdi_cfg_seq_item)          fifo_sb_die0_tx;
  uvm_tlm_analysis_fifo #(rdi_cfg_seq_item)          fifo_sb_die0_rx;
  uvm_tlm_analysis_fifo #(rdi_cfg_seq_item)          fifo_sb_die1_tx;
  uvm_tlm_analysis_fifo #(rdi_cfg_seq_item)          fifo_sb_die1_rx;

  // 4 Sideband Analysis Imps for Filtering Monitor Broadcasts
  uvm_analysis_imp_sb_die0_tx #(rdi_cfg_seq_item, ucie_scoreboard) imp_sb_die0_tx;
  uvm_analysis_imp_sb_die0_rx #(rdi_cfg_seq_item, ucie_scoreboard) imp_sb_die0_rx;
  uvm_analysis_imp_sb_die1_tx #(rdi_cfg_seq_item, ucie_scoreboard) imp_sb_die1_tx;
  uvm_analysis_imp_sb_die1_rx #(rdi_cfg_seq_item, ucie_scoreboard) imp_sb_die1_rx;

  // Transaction verification counters
  int match_count;
  int mismatch_count;

  function new(string name = "ucie_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    fifo_die0_tx    = new("fifo_die0_tx", this);
    fifo_die0_rx    = new("fifo_die0_rx", this);
    fifo_die1_tx    = new("fifo_die1_tx", this);
    fifo_die1_rx    = new("fifo_die1_rx", this);

    fifo_sb_die0_tx = new("fifo_sb_die0_tx", this);
    fifo_sb_die0_rx = new("fifo_sb_die0_rx", this);
    fifo_sb_die1_tx = new("fifo_sb_die1_tx", this);
    fifo_sb_die1_rx = new("fifo_sb_die1_rx", this);

    imp_sb_die0_tx  = new("imp_sb_die0_tx", this);
    imp_sb_die0_rx  = new("imp_sb_die0_rx", this);
    imp_sb_die1_tx  = new("imp_sb_die1_tx", this);
    imp_sb_die1_rx  = new("imp_sb_die1_rx", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    match_count    = 0;
    mismatch_count = 0;
  endfunction

  // Write Callbacks for Sideband Downstream / Upstream Monitoring (Filtering Cross-Die Traffic)
  function void write_sb_die0_tx(rdi_cfg_seq_item item);
    if (!(item.dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::REMOTE_PHY, sb_pkg::LOCAL_ADAPTER})) begin
      `uvm_info("SCOREBOARD_SB_FILTER", $sformatf("Queuing Die0 SB TX Cross-Die Packet (Tag %0d, Dstid %0d): %s", 
                item.tag, item.dstid, item.convert2string()), UVM_HIGH)
      fifo_sb_die0_tx.write(item);
    end
  endfunction

  function void write_sb_die0_rx(rdi_cfg_seq_item item);
    bit is_local_comp = (item.opcode inside {sb_pkg::SB_COMPLETION_WITHOUT_DATA, sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA}) && (item.dstid == 0);
    if (!is_local_comp && !(item.dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::REMOTE_PHY, sb_pkg::LOCAL_ADAPTER})) begin
      `uvm_info("SCOREBOARD_SB_FILTER", $sformatf("Queuing Die0 SB RX Cross-Die Packet (Tag %0d, Opcode %0s): %s", 
                item.tag, item.opcode.name(), item.convert2string()), UVM_HIGH)
      fifo_sb_die0_rx.write(item);
    end
  endfunction

  function void write_sb_die1_tx(rdi_cfg_seq_item item);
    if (!(item.dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::REMOTE_PHY, sb_pkg::LOCAL_ADAPTER})) begin
      `uvm_info("SCOREBOARD_SB_FILTER", $sformatf("Queuing Die1 SB TX Cross-Die Packet (Tag %0d, Dstid %0d): %s", 
                item.tag, item.dstid, item.convert2string()), UVM_HIGH)
      fifo_sb_die1_tx.write(item);
    end
  endfunction

  function void write_sb_die1_rx(rdi_cfg_seq_item item);
    bit is_local_comp = (item.opcode inside {sb_pkg::SB_COMPLETION_WITHOUT_DATA, sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA}) && (item.dstid == 0);
    if (!is_local_comp && !(item.dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::REMOTE_PHY, sb_pkg::LOCAL_ADAPTER})) begin
      `uvm_info("SCOREBOARD_SB_FILTER", $sformatf("Queuing Die1 SB RX Cross-Die Packet (Tag %0d, Opcode %0s): %s", 
                item.tag, item.opcode.name(), item.convert2string()), UVM_HIGH)
      fifo_sb_die1_rx.write(item);
    end
  endfunction

  task run_phase(uvm_phase phase);
    fork
      compare_die0_to_die1();
      compare_die1_to_die0();
      compare_sb_die0_to_die1();
      compare_sb_die1_to_die0();
    join
  endtask

  // Thread 1: Verify Die 0 Mainband Tx flits against Die 1 Mainband Rx flits
  task compare_die0_to_die1();
    ucie_mainband_seq_item_mon tx_item;
    ucie_mainband_seq_item_mon rx_item;

    forever begin
      fifo_die0_tx.get(tx_item);
      fifo_die1_rx.get(rx_item);

      if (tx_item.data === rx_item.data) begin
        match_count++;
        `uvm_info("SCOREBOARD", $sformatf("[MB DIE0 -> DIE1 MATCH #%0d] Data 0x%h verified successfully", 
                  match_count, rx_item.data), UVM_LOW)
      end else begin
        mismatch_count++;
        `uvm_error("SCOREBOARD", $sformatf("[MB DIE0 -> DIE1 MISMATCH] Expected 0x%h, Received 0x%h", 
                   tx_item.data, rx_item.data))
      end
    end
  endtask

  // Thread 2: Verify Die 1 Mainband Tx flits against Die 0 Mainband Rx flits
  task compare_die1_to_die0();
    ucie_mainband_seq_item_mon tx_item;
    ucie_mainband_seq_item_mon rx_item;

    forever begin
      fifo_die1_tx.get(tx_item);
      fifo_die0_rx.get(rx_item);

      if (tx_item.data === rx_item.data) begin
        match_count++;
        `uvm_info("SCOREBOARD", $sformatf("[MB DIE1 -> DIE0 MATCH #%0d] Data 0x%h verified successfully", 
                  match_count, rx_item.data), UVM_LOW)
      end else begin
        mismatch_count++;
        `uvm_error("SCOREBOARD", $sformatf("[MB DIE1 -> DIE0 MISMATCH] Expected 0x%h, Received 0x%h", 
                   tx_item.data, rx_item.data))
      end
    end
  endtask

  // Thread 3: Verify Die 0 Sideband Tx packets against Die 1 Sideband Rx packets
  task compare_sb_die0_to_die1();
    rdi_cfg_seq_item tx_item;
    rdi_cfg_seq_item rx_item;

    forever begin
      fifo_sb_die0_tx.get(tx_item);
      fifo_sb_die1_rx.get(rx_item);

      if (tx_item.sb_pkt === rx_item.sb_pkt) begin
        match_count++;
        `uvm_info("SCOREBOARD", $sformatf("[SB DIE0 -> DIE1 MATCH #%0d] Sideband Packet verified successfully (%s)", 
                  match_count, rx_item.convert2string()), UVM_LOW)
      end else begin
        mismatch_count++;
        `uvm_error("SCOREBOARD", $sformatf("[SB DIE0 -> DIE1 MISMATCH] Expected %s, Received %s", 
                   tx_item.convert2string(), rx_item.convert2string()))
      end
    end
  endtask

  // Thread 4: Verify Die 1 Sideband Tx packets against Die 0 Sideband Rx packets
  task compare_sb_die1_to_die0();
    rdi_cfg_seq_item tx_item;
    rdi_cfg_seq_item rx_item;

    forever begin
      fifo_sb_die1_tx.get(tx_item);
      fifo_sb_die0_rx.get(rx_item);

      if (tx_item.sb_pkt === rx_item.sb_pkt) begin
        match_count++;
        `uvm_info("SCOREBOARD", $sformatf("[SB DIE1 -> DIE0 MATCH #%0d] Sideband Packet verified successfully (%s)", 
                  match_count, rx_item.convert2string()), UVM_LOW)
      end else begin
        mismatch_count++;
        `uvm_error("SCOREBOARD", $sformatf("[SB DIE1 -> DIE0 MISMATCH] Expected %s, Received %s", 
                   tx_item.convert2string(), rx_item.convert2string()))
      end
    end
  endtask

  // Check Phase: Assert zero mismatches and empty FIFOs
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("SCOREBOARD", $sformatf("--- Scoreboard Report: Matches=%0d, Mismatches=%0d ---", 
              match_count, mismatch_count), UVM_LOW)

    if (mismatch_count > 0) begin
      `uvm_error("SCOREBOARD", $sformatf("Scoreboard verification failed with %0d mismatches", mismatch_count))
    end

    if (!fifo_die0_tx.is_empty()) begin
      `uvm_error("SCOREBOARD", $sformatf("fifo_die0_tx not empty at test completion (%0d leftover items)", fifo_die0_tx.used()))
    end
    if (!fifo_die0_rx.is_empty()) begin
      `uvm_error("SCOREBOARD", $sformatf("fifo_die0_rx not empty at test completion (%0d leftover items)", fifo_die0_rx.used()))
    end
    if (!fifo_die1_tx.is_empty()) begin
      `uvm_error("SCOREBOARD", $sformatf("fifo_die1_tx not empty at test completion (%0d leftover items)", fifo_die1_tx.used()))
    end
    if (!fifo_die1_rx.is_empty()) begin
      `uvm_error("SCOREBOARD", $sformatf("fifo_die1_rx not empty at test completion (%0d leftover items)", fifo_die1_rx.used()))
    end

    if (!fifo_sb_die0_tx.is_empty()) begin
      `uvm_error("SCOREBOARD", $sformatf("fifo_sb_die0_tx not empty at test completion (%0d leftover items)", fifo_sb_die0_tx.used()))
    end
    if (!fifo_sb_die0_rx.is_empty()) begin
      `uvm_error("SCOREBOARD", $sformatf("fifo_sb_die0_rx not empty at test completion (%0d leftover items)", fifo_sb_die0_rx.used()))
    end
    if (!fifo_sb_die1_tx.is_empty()) begin
      `uvm_error("SCOREBOARD", $sformatf("fifo_sb_die1_tx not empty at test completion (%0d leftover items)", fifo_sb_die1_tx.used()))
    end
    if (!fifo_sb_die1_rx.is_empty()) begin
      `uvm_error("SCOREBOARD", $sformatf("fifo_sb_die1_rx not empty at test completion (%0d leftover items)", fifo_sb_die1_rx.used()))
    end
  endfunction

endclass
