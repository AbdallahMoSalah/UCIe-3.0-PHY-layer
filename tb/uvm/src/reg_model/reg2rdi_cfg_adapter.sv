// =============================================================================
//  reg2rdi_cfg_adapter
// -----------------------------------------------------------------------------
//  UVM register adapter translating register accesses to rdi_cfg_seq_item.
//  Assigns unique auto-incrementing tags and evaluates completion statuses.
// =============================================================================

class reg2rdi_cfg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(reg2rdi_cfg_adapter)

  function new(string name = "reg2rdi_cfg_adapter");
    super.new(name);
    supports_byte_enable = 0; // Flat words
    provides_responses   = 0; // Predictor handles asynchronously
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    static bit [4:0] tag_counter = 0;
    rdi_cfg_seq_item item = rdi_cfg_seq_item::type_id::create("item");

    item.addr  = rw.addr[24:0];
    item.data  = rw.data;
    item.srcid = sb_pkg::ADAPTER;
    item.dstid = sb_pkg::LOCAL_PHY;
    item.tag   = tag_counter++;
    
    // Choose byte enables
    item.be = (rw.n_bits == 64) ? 8'hFF : 8'h0F;

    if (rw.kind == UVM_WRITE) begin
      if (rw.addr[24] == 1'b0) begin
        item.opcode = (rw.n_bits == 64) ? sb_pkg::SB_64_CFG_WRITE : sb_pkg::SB_32_CFG_WRITE;
      end else begin
        item.opcode = (rw.n_bits == 64) ? sb_pkg::SB_64_MEM_WRITE : sb_pkg::SB_32_MEM_WRITE;
      end
    end 
    else begin // UVM_READ
      if (rw.addr[24] == 1'b0) begin
        item.opcode = (rw.n_bits == 64) ? sb_pkg::SB_64_CFG_READ : sb_pkg::SB_32_CFG_READ;
      end else begin
        item.opcode = (rw.n_bits == 64) ? sb_pkg::SB_64_MEM_READ : sb_pkg::SB_32_MEM_READ;
      end
    end

    item.pack_to_struct();
    return item;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    rdi_cfg_seq_item item;
    if (!$cast(item, bus_item)) begin
      `uvm_fatal("REG_ADAPT", "Failed to cast bus_item to rdi_cfg_seq_item")
      return;
    end
    
    rw.addr = item.addr;
    rw.data = item.data;
    
    // Determine read/write status
    if (item.opcode inside {
      sb_pkg::SB_32_CFG_WRITE, sb_pkg::SB_64_CFG_WRITE,
      sb_pkg::SB_32_MEM_WRITE, sb_pkg::SB_64_MEM_WRITE
    }) begin
      rw.kind = UVM_WRITE;
    end else begin
      rw.kind = UVM_READ;
    end
    
    // Evaluate completion status: 3'b000 indicates Successful completion
    rw.status = (item.status == 3'b000) ? UVM_IS_OK : UVM_NOT_OK;
  endfunction

endclass
