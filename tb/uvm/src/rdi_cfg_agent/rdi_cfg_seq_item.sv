// =============================================================================
//  rdi_cfg_seq_item
// -----------------------------------------------------------------------------
//  Contains base sequence item, driver item, and monitor item for RDI Config agent.
// =============================================================================

// 1. Base sequence item containing common transaction properties & packing methods
class rdi_cfg_seq_item_base extends uvm_sequence_item;

  // --- Randomizable User Fields ---
  rand sb_pkg::sb_opcode_e  opcode;
  rand sb_pkg::sb_dstid_e   dstid;
  rand sb_pkg::sb_srcid_e   srcid;
  rand bit [4:0]            tag;
  rand bit [24:0]           addr;
  rand bit [63:0]           data;
  rand bit [7:0]            be;
  rand bit                  cr;

  // Completion Status & Response Metadata
  bit [2:0]                 status;
  bit                       is_response;
  rand bit                  is_valid_req;

  // --- Hardware-level packed struct representation ---
  sb_pkg::sb_packet_t       sb_pkt;

  `uvm_object_utils_begin(rdi_cfg_seq_item_base)
    `uvm_field_enum(sb_pkg::sb_opcode_e, opcode,       UVM_ALL_ON)
    `uvm_field_enum(sb_pkg::sb_dstid_e,   dstid,                              UVM_ALL_ON)
    `uvm_field_enum(sb_pkg::sb_srcid_e,   srcid,                              UVM_ALL_ON)
    `uvm_field_int(tag,                                UVM_ALL_ON)
    `uvm_field_int(addr,                               UVM_ALL_ON)
    `uvm_field_int(data,                               UVM_ALL_ON)
    `uvm_field_int(be,                                 UVM_ALL_ON)
    `uvm_field_int(cr,                                 UVM_ALL_ON)
    `uvm_field_int(status,                             UVM_ALL_ON)
    `uvm_field_int(is_response,                        UVM_ALL_ON)
    `uvm_field_int(is_valid_req,                       UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "rdi_cfg_seq_item_base");
    super.new(name);
    opcode       = sb_pkg::SB_32_CFG_READ;
    dstid        = sb_pkg::REMOTE_REG_ACCESS;
    srcid        = sb_pkg::ADAPTER;
    tag          = 5'h0;
    be           = 8'h0F; // Default 32-bit select
    cr           = 1'b0;
    status       = 3'b000;
    is_valid_req = 1'b1;
  endfunction

  static function bit is_valid_phy_addr(bit [24:0] a, sb_pkg::sb_opcode_e op = sb_pkg::SB_32_CFG_READ);
    if (op inside {sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE, sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE}) begin
      return (a inside {
        25'h00_0000, 25'h00_0004, 25'h00_0008, 25'h00_000A, 25'h00_000C,
        25'h00_0010, 25'h00_0014, 25'h00_0018, 25'h00_001A, 25'h00_001C, 25'h00_0020
      });
    end else if (op inside {sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE, sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE}) begin
      return (a inside {
        25'h100_1000, 25'h100_1004, 25'h100_1008, 25'h100_100C, 25'h100_1010,
        25'h100_1020, 25'h100_1030, 25'h100_1034, 25'h100_1050, 25'h100_1060,
        25'h100_1064, 25'h100_1080, 25'h100_1090, 25'h100_1100, 25'h100_1104, 25'h100_1108
      });
    end
    return 1'b0;
  endfunction

  // Helper to check if packet is a register access request
  virtual function bit is_reg_req();
    return (opcode inside {
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE,
      sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_32_DMS_REG_WRITE,
      sb_pkg::SB_64_DMS_REG_READ, sb_pkg::SB_64_DMS_REG_WRITE
    });
  endfunction

  // Helper to check if packet is a register READ request
  virtual function bit is_read_req();
    return (opcode inside {
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_CFG_READ,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_CFG_READ,
      sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_64_DMS_REG_READ
    });
  endfunction

  // 3-State Completion Helper:
  //   1 : Successful completion (opcode is CPL and status == 3'b000)
  //   0 : Error completion (opcode is CPL and status != 3'b000, e.g. UR/CA)
  //  -1 : Not a completion packet
  virtual function int check_cpl_status();
    if (!(opcode inside {
      sb_pkg::SB_COMPLETION_WITH_32_DATA,
      sb_pkg::SB_COMPLETION_WITH_64_DATA,
      sb_pkg::SB_COMPLETION_WITHOUT_DATA
    })) begin
      return -1;
    end
    return (status == sb_pkg::SB_CPL_SUCCESS) ? 1 : 0;
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
    sb_pkt.header.req.cr     = cr;

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
    opcode       = sb_pkt.header.req.opcode;
    dstid        = sb_pkt.header.req.dstid;
    srcid        = sb_pkt.header.req.srcid;
    tag          = sb_pkt.header.req.tag;
    be           = sb_pkt.header.req.be;
    cr           = sb_pkt.header.req.cr;
    data         = sb_pkt.payload;
    status       = sb_pkt.header.cpl.status;

    // Restore bit 24 for MMIO (1) vs CFG (0) space
    if (opcode inside {
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE
    }) begin
      addr = {1'b1, sb_pkt.header.req.addr[23:0]};
    end else begin
      addr = {1'b0, sb_pkt.header.req.addr[23:0]};
    end

    if (is_reg_req()) begin
      is_valid_req = is_valid_phy_addr(addr, opcode);
    end
  endfunction

  function void post_randomize();
    if (is_reg_req()) begin
      is_valid_req = is_valid_phy_addr(addr, opcode);
    end
    pack_to_struct();
  endfunction

  // --- Soft Constraints for Valid Sideband Items ---

  // 1. dstid cannot be LOCAL_ADAPTER
  constraint c_valid_dstid {
    soft dstid != sb_pkg::LOCAL_ADAPTER;
  }

  // 2. srcid cannot be PHY
  constraint c_valid_srcid {
    soft srcid != sb_pkg::PHY;
  }

  // 3. STACK0 and STACK1 source requests must target LOCAL_PHY with valid reg access opcodes
  constraint c_stack_src_dst_op {
    if (srcid inside {sb_pkg::STACK0, sb_pkg::STACK1}) {
      dstid == sb_pkg::LOCAL_PHY;
      opcode inside {
        sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
        sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
        sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
        sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE
      };
    }
  }

  // 4. Exclude illegal / non-standard opcodes in valid items
  constraint c_valid_opcode_exclusions {
    soft !(opcode inside {
      sb_pkg::SB_PRIORITY_MSG1,
      sb_pkg::SB_PRIORITY_MSG2,
      sb_pkg::SB_64_DMS_REG_READ,
      sb_pkg::SB_64_DMS_REG_WRITE,
      sb_pkg::SB_32_DMS_REG_READ,
      sb_pkg::SB_32_DMS_REG_WRITE,
      sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITH_DATA
    });
  }

  // 5. Register access requests CANNOT target REMOTE_PHY
  constraint c_reg_req_dstid {
    if (is_reg_req()) {
      soft dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::REMOTE_REG_ACCESS};
    }
  }

  // 6. Completion packets driven from Adapter MUST target REMOTE_ADAPTER
  constraint c_cpl_dstid {
    if (opcode inside {
      sb_pkg::SB_COMPLETION_WITHOUT_DATA,
      sb_pkg::SB_COMPLETION_WITH_32_DATA,
      sb_pkg::SB_COMPLETION_WITH_64_DATA
    }) {
      soft dstid == sb_pkg::REMOTE_ADAPTER;
    }
  }

  // 7. Opcode and Destination consistency for remote/local messages and reg requests
  constraint c_op_dst_consistency {
    if (opcode inside {sb_pkg::SB_MSG_WITHOUT_DATA, sb_pkg::SB_MSG_WITH_64_DATA}) {
      soft dstid inside {sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_PHY, sb_pkg::MNGT_PORT_DST};
    }
    if (is_reg_req() && dstid != sb_pkg::LOCAL_PHY) {
      soft dstid == sb_pkg::REMOTE_REG_ACCESS;
    }
  }

  // 8. cr (Credit Return) is only used for remote destinations
  constraint c_cr_val {
    if (!(dstid inside {sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_REG_ACCESS})) {
      soft cr == 1'b0;
    }
  }

  // 9. Completion status must be SUCCESS or UR (CA is ignored per RTL spec)
  constraint c_valid_status {
    soft status inside {sb_pkg::SB_CPL_SUCCESS, sb_pkg::SB_CPL_UR};
  }

  // 10. Opcode-consistent Address distribution for LOCAL_PHY reg requests (85% valid space, 15% invalid for UR status)
  constraint c_valid_phy_addr_dist {
    if (dstid == sb_pkg::LOCAL_PHY && is_reg_req()) {
      if (opcode inside {sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE, sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE}) {
        soft addr inside {
          25'h00_0000, 25'h00_0004, 25'h00_0008, 25'h00_000A, 25'h00_000C,
          25'h00_0010, 25'h00_0014, 25'h00_0018, 25'h00_001A, 25'h00_001C, 25'h00_0020
        } dist { 1 := 85, 0 := 15 };
      } else if (opcode inside {sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE, sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE}) {
        soft addr inside {
          25'h100_1000, 25'h100_1004, 25'h100_1008, 25'h100_100C, 25'h100_1010,
          25'h100_1020, 25'h100_1030, 25'h100_1034, 25'h100_1050, 25'h100_1060,
          25'h100_1064, 25'h100_1080, 25'h100_1090, 25'h100_1100, 25'h100_1104, 25'h100_1108
        } dist { 1 := 85, 0 := 15 };
      }
    }
  }

  // 11. Standard valid opcodes set
  constraint c_valid_opcodes {
    soft opcode inside {
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
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

      default: begin
        res = {res, $sformatf(" tag=%0d addr=%h data=%h status=%0d be=%h", 
                             sb_pkt.header.req.tag, sb_pkt.header.req.addr, 
                             sb_pkt.payload, sb_pkt.header.cpl.status, sb_pkt.header.req.be)};
      end
    endcase

    return res;
  endfunction

endclass


// 2. Driver sequence item containing driver-specific delay controls
class rdi_cfg_seq_item_drv extends rdi_cfg_seq_item_base;

  rand int unsigned pre_drive_delay;
  rand int unsigned post_drive_delay;

  constraint c_pre_drive_delay_default {
    soft pre_drive_delay <= 5;
  }

  constraint c_post_drive_delay_default {
    soft post_drive_delay <= 5;
  }

  `uvm_object_utils_begin(rdi_cfg_seq_item_drv)
    `uvm_field_int(pre_drive_delay,  UVM_ALL_ON)
    `uvm_field_int(post_drive_delay, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "rdi_cfg_seq_item_drv");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("%s, pre_delay=%0d, post_delay=%0d", super.convert2string(), pre_drive_delay, post_drive_delay);
  endfunction

endclass


// 3. Monitor sequence item containing monitor-populated transfer metrics
class rdi_cfg_seq_item_mon extends rdi_cfg_seq_item_base;

  int unsigned length;
  int unsigned prev_item_delay;

  `uvm_object_utils_begin(rdi_cfg_seq_item_mon)
    `uvm_field_int(length,          UVM_ALL_ON)
    `uvm_field_int(prev_item_delay, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "rdi_cfg_seq_item_mon");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("%s, length=%0d, prev_delay=%0d", super.convert2string(), length, prev_item_delay);
  endfunction

endclass

// Alias for default sequence item usage
typedef rdi_cfg_seq_item_drv rdi_cfg_seq_item;
