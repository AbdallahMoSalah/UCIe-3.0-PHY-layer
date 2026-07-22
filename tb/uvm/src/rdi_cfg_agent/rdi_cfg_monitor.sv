// =============================================================================
//  rdi_cfg_monitor
// -----------------------------------------------------------------------------
//  Monitors both downstream (request) and upstream (response) config paths.
//  Implements tag-based completion matching, destination-based routing,
//  and 3 analysis ports (ap_tx for cross-die requests, ap_rx for cross-die responses,
//  and ap_ral for local RAL predictor updates).
// =============================================================================

class rdi_cfg_monitor extends uvm_monitor;
  `uvm_component_utils(rdi_cfg_monitor)

  rdi_cfg_agent_config cfg;
  virtual rdi_cfg_if   vif;

  // 3 Analysis Ports
  uvm_analysis_port#(rdi_cfg_seq_item) ap_tx;  // Downstream cross-die packets
  uvm_analysis_port#(rdi_cfg_seq_item) ap_rx;  // Upstream cross-die packets
  uvm_analysis_port#(rdi_cfg_seq_item) ap_ral; // Local completions & requests for RAL predictor
  uvm_analysis_port#(rdi_cfg_seq_item) ap;     // Alias to ap_ral for backward compatibility

  // Tag lookup associative array for local register access completions
  rdi_cfg_seq_item pending_reqs[bit [4:0]];

  function new(string name = "rdi_cfg_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap_tx  = new("ap_tx", this);
    ap_rx  = new("ap_rx", this);
    ap_ral = new("ap_ral", this);
    ap     = ap_ral; // Point backward-compatible handle to ap_ral
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(rdi_cfg_agent_config)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("MON_ERR", "Failed to retrieve agent configuration 'cfg'")
    end
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    wait(vif.rst_n === 1'b1);
    
    fork
      monitor_downstream();
      monitor_upstream();
    join
  endtask

  // Thread 1: Monitor downstream transactions (Requests: Adapter -> PHY)
  task monitor_downstream();
    bit [127:0]          raw_data = '0;
    int                  chunk_idx = 0;
    int                  expected_chunks = 2;
    sb_pkg::sb_opcode_e  opcode;
    
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.lp_cfg_vld) begin
        raw_data[chunk_idx*32 +: 32] = vif.mon_cb.lp_cfg;
        if (chunk_idx == 0) begin
          opcode = sb_pkg::sb_opcode_e'(vif.mon_cb.lp_cfg[4:0]);
          expected_chunks = get_expected_chunks(opcode);
        end
        chunk_idx++;
        
        if (chunk_idx == expected_chunks) begin
          rdi_cfg_seq_item item = rdi_cfg_seq_item::type_id::create("item");
          item.sb_pkt.header.raw = raw_data[63:0];
          item.sb_pkt.payload    = raw_data[127:64];
          item.unpack_from_struct();
          item.is_response       = 1'b0; // Request

          // Unconditional broadcast on ap_tx for all downstream requests
          `uvm_info("CFG_MON_DS", $sformatf("Monitored Downstream Packet (Tag %0d, Dstid %0d): %s", 
                    item.tag, item.dstid, item.convert2string()), UVM_HIGH)
          ap_tx.write(item);

          // Local PHY Register Access: store in pending_reqs by tag for completion matching
          if (item.dstid == sb_pkg::LOCAL_PHY) begin
            pending_reqs[item.tag] = item;
          end
          
          chunk_idx = 0;
          raw_data  = '0;
        end
      end
    end
  endtask

  // Thread 2: Monitor upstream transactions (Responses/Messages: PHY -> Adapter)
  task monitor_upstream();
    bit [127:0]          raw_data = '0;
    int                  chunk_idx = 0;
    int                  expected_chunks = 2;
    sb_pkg::sb_opcode_e  opcode;
    
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.pl_cfg_vld) begin
        raw_data[chunk_idx*32 +: 32] = vif.mon_cb.pl_cfg;
        if (chunk_idx == 0) begin
          opcode = sb_pkg::sb_opcode_e'(vif.mon_cb.pl_cfg[4:0]);
          expected_chunks = get_expected_chunks(opcode);
        end
        chunk_idx++;
        
        if (chunk_idx == expected_chunks) begin
          rdi_cfg_seq_item item = rdi_cfg_seq_item::type_id::create("item");
          item.sb_pkt.header.raw = raw_data[63:0];
          item.sb_pkt.payload    = raw_data[127:64];
          item.unpack_from_struct();
          item.is_response       = 1'b1; // Upstream Response/Message

          // Unconditional broadcast on ap_rx for all upstream packets
          `uvm_info("CFG_MON_US", $sformatf("Monitored Upstream Packet (Tag %0d, Opcode %0s): %s", 
                    item.tag, item.opcode.name(), item.convert2string()), UVM_HIGH)
          ap_rx.write(item);

          // Local PHY Completion matching for RAL predictor
          if (item.opcode inside {
            sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA,
            sb_pkg::SB_COMPLETION_WITHOUT_DATA
          } && pending_reqs.exists(item.tag)) begin
            item.addr = pending_reqs[item.tag].addr;
            pending_reqs.delete(item.tag);

            `uvm_info("CFG_MON_US_RAL", $sformatf("Monitored Local PHY Completion (Tag %0d): %s", 
                      item.tag, item.convert2string()), UVM_HIGH)
            ap_ral.write(item);
          end
          
          chunk_idx = 0;
          raw_data  = '0;
        end
      end
    end
  endtask

  // Helper function to decode chunk counts based on opcode
  function int get_expected_chunks(sb_pkg::sb_opcode_e op);
    case (op)
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_32_CFG_READ,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_DMS_REG_READ, sb_pkg::SB_64_CFG_READ,
      sb_pkg::SB_COMPLETION_WITHOUT_DATA, sb_pkg::SB_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA: begin
        return 2;
      end
      sb_pkg::SB_32_MEM_WRITE, sb_pkg::SB_32_DMS_REG_WRITE, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_COMPLETION_WITH_32_DATA: begin
        return 3;
      end
      sb_pkg::SB_64_MEM_WRITE, sb_pkg::SB_64_DMS_REG_WRITE, sb_pkg::SB_64_CFG_WRITE,
      sb_pkg::SB_COMPLETION_WITH_64_DATA, sb_pkg::SB_MSG_WITH_64_DATA: begin
        return 4;
      end
      default: return 2;
    endcase
  endfunction

endclass
