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
  uvm_tlm_analysis_fifo #(rdi_cfg_seq_item_mon)          fifo_sb_die0_tx;
  uvm_tlm_analysis_fifo #(rdi_cfg_seq_item_mon)          fifo_sb_die0_rx;
  uvm_tlm_analysis_fifo #(rdi_cfg_seq_item_mon)          fifo_sb_die1_tx;
  uvm_tlm_analysis_fifo #(rdi_cfg_seq_item_mon)          fifo_sb_die1_rx;

  // 4 Sideband Analysis Imps for Filtering Monitor Broadcasts
  uvm_analysis_imp_sb_die0_tx #(rdi_cfg_seq_item_mon, ucie_scoreboard) imp_sb_die0_tx;
  uvm_analysis_imp_sb_die0_rx #(rdi_cfg_seq_item_mon, ucie_scoreboard) imp_sb_die0_rx;
  uvm_analysis_imp_sb_die1_tx #(rdi_cfg_seq_item_mon, ucie_scoreboard) imp_sb_die1_tx;
  uvm_analysis_imp_sb_die1_rx #(rdi_cfg_seq_item_mon, ucie_scoreboard) imp_sb_die1_rx;

  // Transaction verification counters
  int match_count;
  int mismatch_count;

  // Pending invalid requests lookup tables for UR completion verification
  rdi_cfg_seq_item_mon invalid_pending_reqs_die0[bit [4:0]];
  rdi_cfg_seq_item_mon invalid_pending_reqs_die1[bit [4:0]];

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

  // Write Callbacks for Sideband Downstream Requests (RX) & Upstream Responses (TX)

  // Die 0 Downstream Requests (Adapter -> PHY, from master monitor via ap_rx)
  function void write_sb_die0_rx(rdi_cfg_seq_item_mon item);
    // Record invalid local register requests for UR response verification
    if (item.dstid == sb_pkg::LOCAL_PHY && item.is_reg_req() && !item.is_valid_req) begin
      `uvm_info("SCOREBOARD_INVALID_REQ", $sformatf("Queuing Die0 Invalid Local Reg Request (Tag %0d, Addr 0x%h)", 
                item.tag, item.addr), UVM_HIGH)
      invalid_pending_reqs_die0[item.tag] = item;
    end

    if (!(item.dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::REMOTE_PHY, sb_pkg::LOCAL_ADAPTER})) begin
      `uvm_info("SCOREBOARD_SB_FILTER", $sformatf("Queuing Die0 SB TX Cross-Die Packet (Tag %0d, Dstid %0d): %s", 
                item.tag, item.dstid, item.convert2string()), UVM_HIGH)
      fifo_sb_die0_tx.write(item);
    end
  endfunction

  // Die 0 Upstream Responses (PHY -> Adapter, from slave monitor via ap_tx)
  function void write_sb_die0_tx(rdi_cfg_seq_item_mon item);
    rdi_cfg_seq_item_mon req_item;
    bit is_local_comp;

    // Check for local UR completion matching invalid request
    if (item.dstid == 3'b000 && item.check_cpl_status() != -1 && invalid_pending_reqs_die0.exists(item.tag)) begin
      req_item = invalid_pending_reqs_die0[item.tag];
      invalid_pending_reqs_die0.delete(item.tag);

      if (item.status == sb_pkg::SB_CPL_UR && item.data == req_item.sb_pkt.header.raw) begin
        match_count++;
        `uvm_info("SCOREBOARD", $sformatf("[UR MATCH #%0d] Die0 UR completion verified (Tag %0d, Status=UR, Payload=Header)", 
                  match_count, item.tag), UVM_LOW)
      end else begin
        mismatch_count++;
        `uvm_error("SCOREBOARD", $sformatf("[UR MISMATCH] Die0 UR completion failed (Tag %0d, Status=%0d, Data=0x%h, Expected Header=0x%h)", 
                   item.tag, item.status, item.data, req_item.sb_pkt.header.raw))
      end
    end

    is_local_comp = (item.check_cpl_status() != -1) && (item.dstid == 0);
    if (!is_local_comp && !(item.dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::REMOTE_PHY, sb_pkg::LOCAL_ADAPTER})) begin
      `uvm_info("SCOREBOARD_SB_FILTER", $sformatf("Queuing Die0 SB RX Cross-Die Packet (Tag %0d, Opcode %0s): %s", 
                item.tag, item.opcode.name(), item.convert2string()), UVM_HIGH)
      fifo_sb_die0_rx.write(item);
    end
  endfunction

  // Die 1 Downstream Requests (Adapter -> PHY, from master monitor via ap_rx)
  function void write_sb_die1_rx(rdi_cfg_seq_item_mon item);
    // Record invalid local register requests for UR response verification
    if (item.dstid == sb_pkg::LOCAL_PHY && item.is_reg_req() && !item.is_valid_req) begin
      `uvm_info("SCOREBOARD_INVALID_REQ", $sformatf("Queuing Die1 Invalid Local Reg Request (Tag %0d, Addr 0x%h)", 
                item.tag, item.addr), UVM_HIGH)
      invalid_pending_reqs_die1[item.tag] = item;
    end

    if (!(item.dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::REMOTE_PHY, sb_pkg::LOCAL_ADAPTER})) begin
      `uvm_info("SCOREBOARD_SB_FILTER", $sformatf("Queuing Die1 SB TX Cross-Die Packet (Tag %0d, Dstid %0d): %s", 
                item.tag, item.dstid, item.convert2string()), UVM_HIGH)
      fifo_sb_die1_tx.write(item);
    end
  endfunction

  // Die 1 Upstream Responses (PHY -> Adapter, from slave monitor via ap_tx)
  function void write_sb_die1_tx(rdi_cfg_seq_item_mon item);
    rdi_cfg_seq_item_mon req_item;
    bit is_local_comp;

    // Check for local UR completion matching invalid request
    if (item.dstid == 3'b000 && item.check_cpl_status() != -1 && invalid_pending_reqs_die1.exists(item.tag)) begin
      req_item = invalid_pending_reqs_die1[item.tag];
      invalid_pending_reqs_die1.delete(item.tag);

      if (item.status == sb_pkg::SB_CPL_UR && item.data == req_item.sb_pkt.header.raw) begin
        match_count++;
        `uvm_info("SCOREBOARD", $sformatf("[UR MATCH #%0d] Die1 UR completion verified (Tag %0d, Status=UR, Payload=Header)", 
                  match_count, item.tag), UVM_LOW)
      end else begin
        mismatch_count++;
        `uvm_error("SCOREBOARD", $sformatf("[UR MISMATCH] Die1 UR completion failed (Tag %0d, Status=%0d, Data=0x%h, Expected Header=0x%h)", 
                   item.tag, item.status, item.data, req_item.sb_pkt.header.raw))
      end
    end

    is_local_comp = (item.check_cpl_status() != -1) && (item.dstid == 0);
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
    rdi_cfg_seq_item_mon tx_item;
    rdi_cfg_seq_item_mon rx_item;

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
    rdi_cfg_seq_item_mon tx_item;
    rdi_cfg_seq_item_mon rx_item;

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

    if (invalid_pending_reqs_die0.num() > 0) begin
      `uvm_error("SCOREBOARD", $sformatf("invalid_pending_reqs_die0 not empty at test completion (%0d leftover items)", invalid_pending_reqs_die0.num()))
    end
    if (invalid_pending_reqs_die1.num() > 0) begin
      `uvm_error("SCOREBOARD", $sformatf("invalid_pending_reqs_die1 not empty at test completion (%0d leftover items)", invalid_pending_reqs_die1.num()))
    end
  endfunction

endclass
