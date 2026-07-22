// =============================================================================
//  rdi_cfg_seq_item
// -----------------------------------------------------------------------------
//  Unified UVM sequence item for the RDI Config agent. Carries local and remote
//  register writes/reads and messages. Packs/unpacks to the sb_packet_t struct.
// =============================================================================

class rdi_cfg_seq_item extends uvm_sequence_item;
  `uvm_object_utils(rdi_cfg_seq_item)

  // --- Randomizable User Fields ---
  rand sb_pkg::sb_opcode_e  opcode;
  rand bit [3:0]            dstid;
  rand bit [3:0]            srcid;
  rand bit [4:0]            tag;
  rand bit [24:0]           addr;
  rand bit [63:0]           data;
  rand bit [7:0]            be;

  // Completion Status & Response Metadata
  bit [2:0]                 status;
  bit                       is_response;

  // --- Hardware-level packed struct representation ---
  sb_pkg::sb_packet_t       sb_pkt;

  function new(string name = "rdi_cfg_seq_item");
    super.new(name);
    opcode = sb_pkg::SB_32_CFG_READ;
    dstid  = 4'h0;
    srcid  = 4'h2;
    tag    = 5'h0;
    be     = 8'h0F; // Default 32-bit select
    status = 3'b000;
  endfunction

  // Packs class properties into the sb_pkt struct
  function void pack_to_struct();
    sb_pkt = '0;
    sb_pkt.header.raw = '0;
    
    // Set standard header fields
    sb_pkt.header.req.opcode = opcode;
    sb_pkt.header.req.dstid  = sb_pkg::sb_dstid_e'(dstid);
    sb_pkt.header.req.srcid  = sb_pkg::sb_srcid_e'(srcid);
    sb_pkt.header.req.tag    = tag;

    case (opcode)
      // 32-bit Write Access
      sb_pkg::SB_32_CFG_WRITE, sb_pkg::SB_32_MEM_WRITE, sb_pkg::SB_32_DMS_REG_WRITE: begin
        sb_pkt.header.req.addr = addr;
        sb_pkt.header.req.be   = be;
        sb_pkt.payload         = {32'h0, data[31:0]};
      end
      
      // 64-bit Write Access
      sb_pkg::SB_64_CFG_WRITE, sb_pkg::SB_64_MEM_WRITE, sb_pkg::SB_64_DMS_REG_WRITE: begin
        sb_pkt.header.req.addr = addr;
        sb_pkt.header.req.be   = be;
        sb_pkt.payload         = data;
      end
      
      // Read Access (Header only)
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_DMS_REG_READ,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_DMS_REG_READ: begin
        sb_pkt.header.req.addr = addr;
        sb_pkt.header.req.be   = be;
      end
      
      // Completion packets
      sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA: begin
        sb_pkt.header.cpl.status = status;
        sb_pkt.payload = data;
      end
      sb_pkg::SB_COMPLETION_WITHOUT_DATA: begin
        sb_pkt.header.cpl.status = status;
      end
      
      // Message packets
      sb_pkg::SB_MSG_WITH_64_DATA: begin
        sb_pkt.payload = data;
      end
      
      default: begin
        sb_pkt.payload = data;
      end
    endcase

    // Compute header parity (even parity over header bits 61:0)
    sb_pkt.header.req.cp = ^(sb_pkt.header.raw[61:0]);

    // Compute data parity (dp): XOR over payload if packet carries data, else 1'b0
    if (opcode inside {
      sb_pkg::SB_32_CFG_WRITE, sb_pkg::SB_32_MEM_WRITE, sb_pkg::SB_32_DMS_REG_WRITE,
      sb_pkg::SB_64_CFG_WRITE, sb_pkg::SB_64_MEM_WRITE, sb_pkg::SB_64_DMS_REG_WRITE,
      sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA,
      sb_pkg::SB_MSG_WITH_64_DATA, sb_pkg::SB_MNGT_PORT_MSG_WITH_DATA
    }) begin
      sb_pkt.header.req.dp = ^(sb_pkt.payload);
    end else begin
      sb_pkt.header.req.dp = 1'b0;
    end
  endfunction

  // Unpacks the sb_pkt struct into class properties
  function void unpack_from_struct();
    opcode = sb_pkt.header.req.opcode;
    dstid  = sb_pkt.header.req.dstid;
    srcid  = sb_pkt.header.req.srcid;
    tag    = sb_pkt.header.req.tag;
    addr   = sb_pkt.header.req.addr;
    be     = sb_pkt.header.req.be;
    data   = sb_pkt.payload;
    status = sb_pkt.header.cpl.status;
  endfunction

  function void post_randomize();
    pack_to_struct();
  endfunction

  // Standard constraints
  constraint c_valid_opcodes {
    opcode inside {
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE,
      sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA,
      sb_pkg::SB_COMPLETION_WITHOUT_DATA, sb_pkg::SB_MSG_WITH_64_DATA,
      sb_pkg::SB_MSG_WITHOUT_DATA
    };
  }

  // Debug print helper
  virtual function string convert2string();
    sb_pkg::sb_opcode_e op;
    string res;
    string dst_str, src_str;

    // Ensure sb_pkt is packed if uninitialized
    if (sb_pkt.header.raw == '0 && opcode != sb_pkg::SB_32_MEM_READ) begin
      pack_to_struct();
    end

    op = sb_pkt.header.req.opcode;

    // Common prefix for all packet types
    dst_str = (sb_pkt.header.req.dstid.name() != "") ? 
              sb_pkt.header.req.dstid.name() : 
              $sformatf("%0d", sb_pkt.header.req.dstid);
    src_str = (sb_pkt.header.req.srcid.name() != "") ? 
              sb_pkt.header.req.srcid.name() : 
              $sformatf("%0d", sb_pkt.header.req.srcid);

    res = $sformatf("op=%s dst=%s src=%s", op.name(), dst_str, src_str);

    case (op)
      // -----------------------------------------------------------------------
      // REQUEST PACKETS (REQ)
      // -----------------------------------------------------------------------
      sb_pkg::SB_32_CFG_WRITE, sb_pkg::SB_32_MEM_WRITE, sb_pkg::SB_32_DMS_REG_WRITE,
      sb_pkg::SB_64_CFG_WRITE, sb_pkg::SB_64_MEM_WRITE, sb_pkg::SB_64_DMS_REG_WRITE: begin
        res = {res, $sformatf(" tag=%0d addr=%h be=%h data=%h", 
                             sb_pkt.header.req.tag, sb_pkt.header.req.addr, 
                             sb_pkt.header.req.be, sb_pkt.payload)};
      end

      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_DMS_REG_READ,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_DMS_REG_READ: begin
        res = {res, $sformatf(" tag=%0d addr=%h be=%h", 
                             sb_pkt.header.req.tag, sb_pkt.header.req.addr, 
                             sb_pkt.header.req.be)};
      end

      // -----------------------------------------------------------------------
      // COMPLETION PACKETS (CPL)
      // -----------------------------------------------------------------------
      sb_pkg::SB_COMPLETION_WITH_32_DATA, sb_pkg::SB_COMPLETION_WITH_64_DATA: begin
        res = {res, $sformatf(" tag=%0d status=%0d be=%h data=%h", 
                             sb_pkt.header.cpl.tag, sb_pkt.header.cpl.status, 
                             sb_pkt.header.cpl.be, sb_pkt.payload)};
      end

      sb_pkg::SB_COMPLETION_WITHOUT_DATA: begin
        res = {res, $sformatf(" tag=%0d status=%0d be=%h", 
                             sb_pkt.header.cpl.tag, sb_pkt.header.cpl.status, 
                             sb_pkt.header.cpl.be)};
      end

      // -----------------------------------------------------------------------
      // MESSAGE PACKETS (MSG)
      // -----------------------------------------------------------------------
      sb_pkg::SB_MSG_WITH_64_DATA, sb_pkg::SB_MNGT_PORT_MSG_WITH_DATA: begin
        string msgcode_str;
        msgcode_str = (sb_pkt.header.msg.msgcode.name() != "") ? 
                      sb_pkt.header.msg.msgcode.name() : 
                      $sformatf("%h", sb_pkt.header.msg.msgcode);
        res = {res, $sformatf(" msgcode=%s subcode=%h info=%h data=%h", 
                             msgcode_str, sb_pkt.header.msg.MsgSubcode, 
                             sb_pkt.header.msg.MsgInfo, sb_pkt.payload)};
      end

      sb_pkg::SB_MSG_WITHOUT_DATA, sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA,
      sb_pkg::SB_PRIORITY_MSG1, sb_pkg::SB_PRIORITY_MSG2: begin
        string msgcode_str;
        msgcode_str = (sb_pkt.header.msg.msgcode.name() != "") ? 
                      sb_pkt.header.msg.msgcode.name() : 
                      $sformatf("%h", sb_pkt.header.msg.msgcode);
        res = {res, $sformatf(" msgcode=%s subcode=%h info=%h", 
                             msgcode_str, sb_pkt.header.msg.MsgSubcode, 
                             sb_pkt.header.msg.MsgInfo)};
      end

      // -----------------------------------------------------------------------
      // DEFAULT / FALLBACK
      // -----------------------------------------------------------------------
      default: begin
        res = {res, $sformatf(" tag=%0d addr=%h data=%h status=%0d be=%h", 
                             sb_pkt.header.req.tag, sb_pkt.header.req.addr, 
                             sb_pkt.payload, sb_pkt.header.cpl.status, sb_pkt.header.req.be)};
      end
    endcase

    return res;
  endfunction

endclass
