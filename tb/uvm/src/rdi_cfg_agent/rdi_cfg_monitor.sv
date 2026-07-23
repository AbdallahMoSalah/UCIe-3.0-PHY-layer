// =============================================================================
//  rdi_cfg_monitor
// -----------------------------------------------------------------------------
//  Base monitor for RDI Configuration bus.
//  Provides shared configuration references, interface handles, helper methods,
//  and a static tag completion lookup table (pending_reqs) keyed by {die_idx, tag}
//  shared between Master (requests) and Slave (completions) monitors of each die.
// =============================================================================

class rdi_cfg_monitor extends uvm_monitor;
  `uvm_component_utils(rdi_cfg_monitor)

  rdi_cfg_agent_config agent_config;
  virtual rdi_cfg_if   vif;

  // Shared static completion table keyed by {die_idx (1-bit), tag (5-bit)}
  static rdi_cfg_seq_item pending_reqs[bit [5:0]];

  function new(string name = "rdi_cfg_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(rdi_cfg_agent_config)::get(this, "", "cfg", agent_config)) begin
      `uvm_fatal("MON_ERR", "Failed to retrieve agent configuration 'cfg'")
    end
    vif = agent_config.get_vif();
    if (vif == null) begin
      `uvm_fatal("MON_VIF_NULL", $sformatf("Virtual interface 'vif' is null in monitor %s", get_full_name()))
    end
  endfunction

  // Helper function to decode expected chunk count based on sideband opcode
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
