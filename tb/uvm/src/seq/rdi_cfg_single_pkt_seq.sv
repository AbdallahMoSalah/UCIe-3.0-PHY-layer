// =============================================================================
//  rdi_cfg_single_pkt_seq
// -----------------------------------------------------------------------------
//  Sequence generating a single Sideband remote message packet item (rdi_cfg_seq_item).
// =============================================================================

class rdi_cfg_single_pkt_seq extends uvm_sequence #(rdi_cfg_seq_item);
  `uvm_object_utils(rdi_cfg_single_pkt_seq)

  rand sb_pkg::sb_opcode_e opcode;
  rand bit [3:0]           dstid;
  rand sb_pkg::sb_srcid_e  srcid;
  rand bit [4:0]           tag;
  rand bit [63:0]          data;
  rand bit                 cr;

  constraint c_default_msg {
    soft opcode inside {
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE,
      sb_pkg::SB_MSG_WITH_64_DATA, sb_pkg::SB_MSG_WITHOUT_DATA
    };
    soft !(srcid inside {sb_pkg::PHY});
    if (opcode inside {
      sb_pkg::SB_32_MEM_READ, sb_pkg::SB_32_MEM_WRITE,
      sb_pkg::SB_32_CFG_READ, sb_pkg::SB_32_CFG_WRITE,
      sb_pkg::SB_64_MEM_READ, sb_pkg::SB_64_MEM_WRITE,
      sb_pkg::SB_64_CFG_READ, sb_pkg::SB_64_CFG_WRITE
    }) {
      soft dstid == sb_pkg::REMOTE_REG_ACCESS;
      soft srcid == sb_pkg::ADAPTER;
    } else {
      soft dstid inside {sb_pkg::REMOTE_ADAPTER, sb_pkg::REMOTE_PHY, sb_pkg::MNGT_PORT_DST};
      soft srcid inside {sb_pkg::ADAPTER, sb_pkg::MNGT_PORT_SRC};
    }
  }

  function new(string name = "rdi_cfg_single_pkt_seq");
    super.new(name);
  endfunction

  task body();
    rdi_cfg_seq_item item;
    item = rdi_cfg_seq_item::type_id::create("item");
    start_item(item);
    if (!item.randomize() with {
      // soft opcode == local::opcode;
      // soft dstid  == local::dstid;
      // soft srcid  == local::srcid;
      // soft tag    == local::tag;
      // soft data   == local::data;
      // soft cr     == local::cr;
    }) begin
      `uvm_error("SEQ_RND_FAIL", "Randomization failed for rdi_cfg_single_pkt_seq item")
    end
    item.pack_to_struct();
    finish_item(item);
  endtask
endclass
