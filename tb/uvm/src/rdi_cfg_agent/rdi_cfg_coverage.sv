// =============================================================================
//  rdi_cfg_coverage
// -----------------------------------------------------------------------------
//  UVM Coverage Collector for the RDI Config agent.
//  Collects functional coverage for transmitted (ap_tx) and received (ap_rx)
//  sideband packets (REQ, CPL, MSG).
// =============================================================================

`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)

class rdi_cfg_coverage extends uvm_component;
  `uvm_component_utils(rdi_cfg_coverage)

  // Analysis export ports
  uvm_analysis_imp_tx#(rdi_cfg_seq_item, rdi_cfg_coverage) analysis_export_tx;
  uvm_analysis_imp_rx#(rdi_cfg_seq_item, rdi_cfg_coverage) analysis_export_rx;

  // =========================================================================
  // TRANSMIT COVERGROUPS (TX)
  // =========================================================================

  covergroup cg_tx_req with function sample(rdi_cfg_seq_item item);
    cp_opcode: coverpoint item.sb_pkt.header.req.opcode {
      bins req_opcodes[] = {
        sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
        sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_32_DMS_REG_WRITE,
        sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
        sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
        sb_pkg::SB_64_DMS_REG_READ, sb_pkg::SB_64_DMS_REG_WRITE,
        sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE
      };
    }
    cp_dstid: coverpoint item.sb_pkt.header.req.dstid {
      bins valid_dstids[] = {
        sb_pkg::LOCAL_ADAPTER, sb_pkg::LOCAL_PHY,
        sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_PHY,
        sb_pkg::REMOTE_REG_ACCESS, sb_pkg::MNGT_PORT_DST
      };
    }
    cp_srcid: coverpoint item.sb_pkt.header.req.srcid {
      bins valid_srcids[] = {
        sb_pkg::STACK0, sb_pkg::ADAPTER, sb_pkg::PHY,
        sb_pkg::MNGT_PORT_SRC, sb_pkg::STACK1
      };
    }
    cp_tag: coverpoint item.sb_pkt.header.req.tag {
      bins tags[8] = {[0:31]};
    }
    cp_be: coverpoint item.sb_pkt.header.req.be {
      bins be_32bit = {8'h0F};
      bins be_64bit = {8'hFF};
      bins others   = default;
    }

    cx_op_dst: cross cp_opcode, cp_dstid;
  endgroup

  covergroup cg_tx_cpl with function sample(rdi_cfg_seq_item item);
    cp_opcode: coverpoint item.sb_pkt.header.cpl.opcode {
      bins cpl_opcodes[] = {
        sb_pkg::SB_COMPLETION_WITHOUT_DATA,
        sb_pkg::SB_COMPLETION_WITH_32_DATA,
        sb_pkg::SB_COMPLETION_WITH_64_DATA
      };
    }
    cp_dstid: coverpoint item.sb_pkt.header.cpl.dstid {
      bins valid_dstids[] = {
        sb_pkg::LOCAL_ADAPTER, sb_pkg::LOCAL_PHY,
        sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_PHY,
        sb_pkg::REMOTE_REG_ACCESS, sb_pkg::MNGT_PORT_DST
      };
    }
    cp_srcid: coverpoint item.sb_pkt.header.cpl.srcid {
      bins valid_srcids[] = {
        sb_pkg::STACK0, sb_pkg::ADAPTER, sb_pkg::PHY,
        sb_pkg::MNGT_PORT_SRC, sb_pkg::STACK1
      };
    }
    cp_tag: coverpoint item.sb_pkt.header.cpl.tag {
      bins tags[8] = {[0:31]};
    }
    cp_status: coverpoint item.sb_pkt.header.cpl.status {
      bins status_val[] = {[0:7]};
    }

    cx_op_status: cross cp_opcode, cp_status;
  endgroup

  covergroup cg_tx_msg with function sample(rdi_cfg_seq_item item);
    cp_opcode: coverpoint item.sb_pkt.header.msg.opcode {
      bins msg_opcodes[] = {
        sb_pkg::SB_MSG_WITHOUT_DATA,
        sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA,
        sb_pkg::SB_MNGT_PORT_MSG_WITH_DATA,
        sb_pkg::SB_MSG_WITH_64_DATA,
        sb_pkg::SB_PRIORITY_MSG1,
        sb_pkg::SB_PRIORITY_MSG2
      };
    }
    cp_dstid: coverpoint item.sb_pkt.header.msg.dstid {
      bins valid_dstids[] = {
        sb_pkg::LOCAL_ADAPTER, sb_pkg::LOCAL_PHY,
        sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_PHY,
        sb_pkg::REMOTE_REG_ACCESS, sb_pkg::MNGT_PORT_DST
      };
    }
    cp_srcid: coverpoint item.sb_pkt.header.msg.srcid {
      bins valid_srcids[] = {
        sb_pkg::STACK0, sb_pkg::ADAPTER, sb_pkg::PHY,
        sb_pkg::MNGT_PORT_SRC, sb_pkg::STACK1
      };
    }
    cp_msgcode: coverpoint item.sb_pkt.header.msg.msgcode {
      bins msg_codes[] = {
        sb_pkg::SBINIT_OFFRESET_DOMAIN, sb_pkg::RX_TEST_SWEEP_DONE_RESULT,
        sb_pkg::SBINIT_REQ_DOMAIN,      sb_pkg::SBINIT_RESP_DOMAIN,
        sb_pkg::MBINIT_REQ_DOMAIN,      sb_pkg::MBINIT_RESP_DOMAIN,
        sb_pkg::MBTRAIN_REQ_DOMAIN,     sb_pkg::MBTRAIN_RESP_DOMAIN,
        sb_pkg::RECAL_REQ_DOMAIN,       sb_pkg::RECAL_RESP_DOMAIN,
        sb_pkg::PHYRETRAIN_REQ_DOMAIN,  sb_pkg::PHYRETRAIN_RESP_DOMAIN,
        sb_pkg::TRAINERROR_REQ_DOMAIN,  sb_pkg::TRAINERROR_RESP_DOMAIN,
        sb_pkg::RDI_REQ_DOMAIN,         sb_pkg::RDI_RESP_DOMAIN,
        sb_pkg::TEST_REQ_DOMAIN,        sb_pkg::TEST_RESP_DOMAIN
      };
    }

    cx_op_msgcode: cross cp_opcode, cp_msgcode;
  endgroup

  // =========================================================================
  // RECEIVE COVERGROUPS (RX)
  // =========================================================================

  covergroup cg_rx_req with function sample(rdi_cfg_seq_item item);
    cp_opcode: coverpoint item.sb_pkt.header.req.opcode {
      bins req_opcodes[] = {
        sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
        sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_32_DMS_REG_WRITE,
        sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
        sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
        sb_pkg::SB_64_DMS_REG_READ, sb_pkg::SB_64_DMS_REG_WRITE,
        sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE
      };
    }
    cp_dstid: coverpoint item.sb_pkt.header.req.dstid {
      bins valid_dstids[] = {
        sb_pkg::LOCAL_ADAPTER, sb_pkg::LOCAL_PHY,
        sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_PHY,
        sb_pkg::REMOTE_REG_ACCESS, sb_pkg::MNGT_PORT_DST
      };
    }
    cp_srcid: coverpoint item.sb_pkt.header.req.srcid {
      bins valid_srcids[] = {
        sb_pkg::STACK0, sb_pkg::ADAPTER, sb_pkg::PHY,
        sb_pkg::MNGT_PORT_SRC, sb_pkg::STACK1
      };
    }
    cp_tag: coverpoint item.sb_pkt.header.req.tag {
      bins tags[8] = {[0:31]};
    }
    cp_be: coverpoint item.sb_pkt.header.req.be {
      bins be_32bit = {8'h0F};
      bins be_64bit = {8'hFF};
      bins others   = default;
    }

    cx_op_dst: cross cp_opcode, cp_dstid;
  endgroup

  covergroup cg_rx_cpl with function sample(rdi_cfg_seq_item item);
    cp_opcode: coverpoint item.sb_pkt.header.cpl.opcode {
      bins cpl_opcodes[] = {
        sb_pkg::SB_COMPLETION_WITHOUT_DATA,
        sb_pkg::SB_COMPLETION_WITH_32_DATA,
        sb_pkg::SB_COMPLETION_WITH_64_DATA
      };
    }
    cp_dstid: coverpoint item.sb_pkt.header.cpl.dstid {
      bins valid_dstids[] = {
        sb_pkg::LOCAL_ADAPTER, sb_pkg::LOCAL_PHY,
        sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_PHY,
        sb_pkg::REMOTE_REG_ACCESS, sb_pkg::MNGT_PORT_DST
      };
    }
    cp_srcid: coverpoint item.sb_pkt.header.cpl.srcid {
      bins valid_srcids[] = {
        sb_pkg::STACK0, sb_pkg::ADAPTER, sb_pkg::PHY,
        sb_pkg::MNGT_PORT_SRC, sb_pkg::STACK1
      };
    }
    cp_tag: coverpoint item.sb_pkt.header.cpl.tag {
      bins tags[8] = {[0:31]};
    }
    cp_status: coverpoint item.sb_pkt.header.cpl.status {
      bins status_val[] = {[0:7]};
    }

    cx_op_status: cross cp_opcode, cp_status;
  endgroup

  covergroup cg_rx_msg with function sample(rdi_cfg_seq_item item);
    cp_opcode: coverpoint item.sb_pkt.header.msg.opcode {
      bins msg_opcodes[] = {
        sb_pkg::SB_MSG_WITHOUT_DATA,
        sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA,
        sb_pkg::SB_MNGT_PORT_MSG_WITH_DATA,
        sb_pkg::SB_MSG_WITH_64_DATA,
        sb_pkg::SB_PRIORITY_MSG1,
        sb_pkg::SB_PRIORITY_MSG2
      };
    }
    cp_dstid: coverpoint item.sb_pkt.header.msg.dstid {
      bins valid_dstids[] = {
        sb_pkg::LOCAL_ADAPTER, sb_pkg::LOCAL_PHY,
        sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_PHY,
        sb_pkg::REMOTE_REG_ACCESS, sb_pkg::MNGT_PORT_DST
      };
    }
    cp_srcid: coverpoint item.sb_pkt.header.msg.srcid {
      bins valid_srcids[] = {
        sb_pkg::STACK0, sb_pkg::ADAPTER, sb_pkg::PHY,
        sb_pkg::MNGT_PORT_SRC, sb_pkg::STACK1
      };
    }
    cp_msgcode: coverpoint item.sb_pkt.header.msg.msgcode {
      bins msg_codes[] = {
        sb_pkg::SBINIT_OFFRESET_DOMAIN, sb_pkg::RX_TEST_SWEEP_DONE_RESULT,
        sb_pkg::SBINIT_REQ_DOMAIN,      sb_pkg::SBINIT_RESP_DOMAIN,
        sb_pkg::MBINIT_REQ_DOMAIN,      sb_pkg::MBINIT_RESP_DOMAIN,
        sb_pkg::MBTRAIN_REQ_DOMAIN,     sb_pkg::MBTRAIN_RESP_DOMAIN,
        sb_pkg::RECAL_REQ_DOMAIN,       sb_pkg::RECAL_RESP_DOMAIN,
        sb_pkg::PHYRETRAIN_REQ_DOMAIN,  sb_pkg::PHYRETRAIN_RESP_DOMAIN,
        sb_pkg::TRAINERROR_REQ_DOMAIN,  sb_pkg::TRAINERROR_RESP_DOMAIN,
        sb_pkg::RDI_REQ_DOMAIN,         sb_pkg::RDI_RESP_DOMAIN,
        sb_pkg::TEST_REQ_DOMAIN,        sb_pkg::TEST_RESP_DOMAIN
      };
    }

    cx_op_msgcode: cross cp_opcode, cp_msgcode;
  endgroup

  function new(string name = "rdi_cfg_coverage", uvm_component parent = null);
    super.new(name, parent);

    analysis_export_tx = new("analysis_export_tx", this);
    analysis_export_rx = new("analysis_export_rx", this);

    cg_tx_req = new();
    cg_tx_cpl = new();
    cg_tx_msg = new();

    cg_rx_req = new();
    cg_rx_cpl = new();
    cg_rx_msg = new();
  endfunction

  // Sampling method for TX packets
  virtual function void write_tx(rdi_cfg_seq_item t);
    sb_pkg::sb_opcode_e op;
    op = t.sb_pkt.header.req.opcode;

    case (op)
      // REQ Opcodes
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
      sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_32_DMS_REG_WRITE,
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
      sb_pkg::SB_64_DMS_REG_READ, sb_pkg::SB_64_DMS_REG_WRITE,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE: begin
        cg_tx_req.sample(t);
      end

      // CPL Opcodes
      sb_pkg::SB_COMPLETION_WITHOUT_DATA,
      sb_pkg::SB_COMPLETION_WITH_32_DATA,
      sb_pkg::SB_COMPLETION_WITH_64_DATA: begin
        cg_tx_cpl.sample(t);
      end

      // MSG Opcodes
      sb_pkg::SB_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITH_DATA,
      sb_pkg::SB_MSG_WITH_64_DATA,
      sb_pkg::SB_PRIORITY_MSG1,
      sb_pkg::SB_PRIORITY_MSG2: begin
        cg_tx_msg.sample(t);
      end

      default: begin
        `uvm_warning("COV_WARN", $sformatf("Unrecognized TX opcode for coverage: %s", op.name()))
      end
    endcase
  endfunction

  // Sampling method for RX packets
  virtual function void write_rx(rdi_cfg_seq_item t);
    sb_pkg::sb_opcode_e op;
    op = t.sb_pkt.header.req.opcode;

    case (op)
      // REQ Opcodes
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
      sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_32_DMS_REG_WRITE,
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
      sb_pkg::SB_64_DMS_REG_READ, sb_pkg::SB_64_DMS_REG_WRITE,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE: begin
        cg_rx_req.sample(t);
      end

      // CPL Opcodes
      sb_pkg::SB_COMPLETION_WITHOUT_DATA,
      sb_pkg::SB_COMPLETION_WITH_32_DATA,
      sb_pkg::SB_COMPLETION_WITH_64_DATA: begin
        cg_rx_cpl.sample(t);
      end

      // MSG Opcodes
      sb_pkg::SB_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITH_DATA,
      sb_pkg::SB_MSG_WITH_64_DATA,
      sb_pkg::SB_PRIORITY_MSG1,
      sb_pkg::SB_PRIORITY_MSG2: begin
        cg_rx_msg.sample(t);
      end

      default: begin
        `uvm_warning("COV_WARN", $sformatf("Unrecognized RX opcode for coverage: %s", op.name()))
      end
    endcase
  endfunction

endclass
