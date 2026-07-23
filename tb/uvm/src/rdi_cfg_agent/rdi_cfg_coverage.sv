// =============================================================================
//  rdi_cfg_coverage
// -----------------------------------------------------------------------------
//  UVM Coverage Collector for the RDI Config agent.
//  Collects functional coverage for sideband packets (REQ, CPL, MSG).
// =============================================================================

class rdi_cfg_coverage extends uvm_component;
  `uvm_component_utils(rdi_cfg_coverage)

  // Agent configuration reference
  rdi_cfg_agent_config agent_config;

  // Single Analysis Imp export
  uvm_analysis_imp#(rdi_cfg_seq_item, rdi_cfg_coverage) analysis_export;

  // =========================================================================
  // COVERGROUPS
  // =========================================================================

  covergroup cg_req with function sample(rdi_cfg_seq_item item);
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

  covergroup cg_cpl with function sample(rdi_cfg_seq_item item);
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

  covergroup cg_msg with function sample(rdi_cfg_seq_item item);
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
    analysis_export = new("analysis_export", this);

    cg_req = new();
    cg_cpl = new();
    cg_msg = new();
  endfunction

  // Unified sample dispatch method
  virtual function void write(rdi_cfg_seq_item t);
    sb_pkg::sb_opcode_e op;
    if (agent_config != null && !agent_config.get_has_coverage()) return;

    op = t.sb_pkt.header.req.opcode;

    case (op)
      // REQ Opcodes
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
      sb_pkg::SB_32_DMS_REG_READ, sb_pkg::SB_32_DMS_REG_WRITE,
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
      sb_pkg::SB_64_DMS_REG_READ, sb_pkg::SB_64_DMS_REG_WRITE,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE: begin
        cg_req.sample(t);
      end

      // CPL Opcodes
      sb_pkg::SB_COMPLETION_WITHOUT_DATA,
      sb_pkg::SB_COMPLETION_WITH_32_DATA,
      sb_pkg::SB_COMPLETION_WITH_64_DATA: begin
        cg_cpl.sample(t);
      end

      // MSG Opcodes
      sb_pkg::SB_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITHOUT_DATA,
      sb_pkg::SB_MNGT_PORT_MSG_WITH_DATA,
      sb_pkg::SB_MSG_WITH_64_DATA,
      sb_pkg::SB_PRIORITY_MSG1,
      sb_pkg::SB_PRIORITY_MSG2: begin
        cg_msg.sample(t);
      end

      default: begin
        `uvm_warning("COV_WARN", $sformatf("Unrecognized opcode for coverage: %s", op.name()))
      end
    endcase
  endfunction

endclass
