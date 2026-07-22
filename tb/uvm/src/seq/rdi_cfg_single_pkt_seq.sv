// =============================================================================
//  rdi_cfg_single_pkt_seq
// -----------------------------------------------------------------------------
//  Sequence generating a single Sideband remote message packet item (rdi_cfg_seq_item).
// =============================================================================

class rdi_cfg_single_pkt_seq extends uvm_sequence #(rdi_cfg_seq_item);
  `uvm_object_utils(rdi_cfg_single_pkt_seq)

  rand sb_pkg::sb_opcode_e  opcode;
  rand bit [3:0]            dstid;
  rand bit [3:0]            srcid;
  rand bit [4:0]            tag;
  rand bit [63:0]           data;

  constraint c_default_msg {
    soft opcode == sb_pkg::SB_MSG_WITH_64_DATA;
    !(dstid inside {sb_pkg::LOCAL_PHY, sb_pkg::LOCAL_ADAPTER});
    soft srcid  == sb_pkg::ADAPTER;
  }

  function new(string name = "rdi_cfg_single_pkt_seq");
    super.new(name);
  endfunction

  task body();
    rdi_cfg_seq_item item;
    item = rdi_cfg_seq_item::type_id::create("item");
    start_item(item);
    if (!item.randomize() with {
      opcode == local::opcode;
      dstid  == local::dstid;
      srcid  == local::srcid;
      tag    == local::tag;
      data   == local::data;
    }) begin
      item.opcode = opcode;
      item.dstid  = dstid;
      item.srcid  = srcid;
      item.tag    = tag;
      item.data   = data;
    end
    item.pack_to_struct();
    finish_item(item);
  endtask
endclass
