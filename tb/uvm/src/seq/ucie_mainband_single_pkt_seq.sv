// =============================================================================
//  ucie_mainband_single_pkt_seq
// -----------------------------------------------------------------------------
//  Sequence generating a single Mainband transaction flit item (ucie_mainband_seq_item_drv).
// =============================================================================

class ucie_mainband_single_pkt_seq extends uvm_sequence #(ucie_mainband_seq_item_drv);
  `uvm_object_utils(ucie_mainband_single_pkt_seq)

  rand bit [255:0] data;

  function new(string name = "ucie_mainband_single_pkt_seq");
    super.new(name);
  endfunction

  task body();
    ucie_mainband_seq_item_drv item;
    item = ucie_mainband_seq_item_drv::type_id::create("item");
    start_item(item);
    if (!item.randomize() with { data == local::data; }) begin
      item.data = data;
    end
    finish_item(item);
  endtask
endclass
