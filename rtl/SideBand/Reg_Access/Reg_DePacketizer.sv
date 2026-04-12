// ===========================================================================
//  Reg_DePacketizer
//  Part of the SideBand Register Access (Reg_Access) block
//
//  UCIe Specification ref3.0 §7.1.1 – Sideband Packet Types
//  "Register Accesses: These can be Configuration (CFG) or Memory Mapped
//   accesses for both Reads or Writes.  These can be associated with 32b
//   of data or 64b of data.  All register accesses (Reads or Writes) have
//   an associated completion."
//
//  Incoming packet (from RDI_CONTROL / Link_Controller output port):
//   ┌────────────────────── 128 bits ────────────────────────────────┐
//   │  payload [127:64]  │               header [63:0]              │
//   │  (wdata for write) │ cp│rsvd│dstid│addr/tag/MsgInfo│srcid│..  │
//   └────────────────────────────────────────────────────────────────┘
//
//  Register Access Header layout (Table 7-2 / 7-3, UCIe §7.1.1.1):
//   Bit  63      : cp (control parity, even parity over [62:0])
//   Bit  62      : ep (data parity for 64-bit data, = ^wdata; 0 for reads)
//   Bit  61:59   : rsvd2
//   Bit  58:56   : dstid[2:0]
//   Bits 55:40   : MsgInfo = {addr[23:8]}   <upper 16 bits of 24-bit addr>
//   Bits 39:32   : MsgSubcode = {addr[7:0]} <lower 8 bits of 24-bit addr>
//   Bits 31:29   : srcid[2:0]
//   Bits 28:22   : rsvd1
//   Bits 21:14   : be[7:0]                  byte-enable
//   Bits 13:11   : tag[2:0]
//   Bits 10:5    : rsvd0
//   Bits  4:0    : opcode[4:0]
//
//  Supported opcodes (UCIe §7.1.1, Table 7-1):
//   SB_32_MEM_READ      (5'b00000), SB_32_MEM_WRITE     (5'b00001)
//   SB_32_DMS_REG_READ  (5'b00010), SB_32_DMS_REG_WRITE (5'b00011)
//   SB_32_CFG_READ      (5'b00100), SB_32_CFG_WRITE     (5'b00101)
//   SB_64_MEM_READ      (5'b01000), SB_64_MEM_WRITE     (5'b01001)
//   SB_64_DMS_REG_READ  (5'b01010), SB_64_DMS_REG_WRITE (5'b01011)
//   SB_64_CFG_READ      (5'b01100), SB_64_CFG_WRITE     (5'b01101)
//
//  Outputs go to the FSM for address/data routing and to the register file.
// ===========================================================================

module Reg_DePacketizer
    import sb_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // -----------------------------------------------------------------------
    // Input from Link_Controller (reg_msg path)
    // UCIe §7.1.1: incoming 128-bit sideband packet
    // -----------------------------------------------------------------------
    input  logic [127:0] reg_msg,    // Full 128-bit packet
    input  logic         reg_vld,    // Valid strobe from upstream demux

    // -----------------------------------------------------------------------
    // Decoded outputs to FSM
    // -----------------------------------------------------------------------
    output sb_opcode_e   opcode,          // Decoded opcode [4:0]
    output logic [2:0]   tag,             // Transaction tag [2:0]
    output logic [23:0]  rf_addr,         // Register file byte address [23:0]
    output logic [7:0]   rf_be,           // Byte enable [7:0]
    output logic [63:0]  rf_wdata,        // Write data (payload[127:64])
    output logic [63:0]  Original_Header, // Latched request header → Completion_gen

    // -----------------------------------------------------------------------
    // Error / qualification flags to FSM
    // UCIe §7.1.1: parity checks
    // -----------------------------------------------------------------------
    output logic         parity_err,  // 1 = cp or ep mismatch
    output logic         ep,          // Latched ep bit (data parity valid)
    output logic         false_msg,   // 1 = opcode not a register access type

    // -----------------------------------------------------------------------
    // Backpressure / ready-flow
    // -----------------------------------------------------------------------
    output logic         reg_rdy      // 1 = block is idle, ready for next packet
);

// ---------------------------------------------------------------------------
// Internal – directly from header field extraction
// ---------------------------------------------------------------------------
sb_header_t hdr;          // Packed header struct view
logic        cp_calc;     // Computed control parity
logic        ep_calc;     // Computed data parity over wdata
logic        is_write;    // Current packet is a write
logic        is_64bit;    // Current packet carries 64-bit data/address

// == Header extraction =======================================================
// UCIe §7.1.1.1 Table 7-2/7-3:
//   Header[63:0] carries all control fields.
//   Payload[127:64] carries wdata for write transactions.
always_comb begin
    hdr = reg_msg[63:0];

    // Address reconstruction:
    //   addr[23:8]  = MsgInfo [55:40]
    //   addr[7:0]   = MsgSubcode [39:32]
    rf_addr  = {hdr.MsgInfo[15:0], hdr.MsgSubcode};   // [23:0]

    // Byte-Enable reconstructed from msgcode/rsvd1 field reused in reg-access
    // UCIe §7.1.1.1: bits [21:14] carry BE[7:0]
    rf_be    = reg_msg[21:14];

    // Tag: bits [13:11]
    tag      = reg_msg[13:11];

    // Write data is in the 64-bit payload word
    rf_wdata = reg_msg[127:64];

    // Opcode
    opcode   = sb_opcode_e'(hdr.opcode);

    // ep bit directly from header
    ep       = hdr.ep;   // UCIe §7.1.1: ep = ^wdata for write; 0 for read

    // Parity calculations
    // cp = even parity over header bits [62:0]  (UCIe §7.1.1)
    cp_calc  = ^reg_msg[62:0];

    // ep_calc: for 64-bit accesses, ep = XOR of all wdata bits
    ep_calc  = ^reg_msg[127:64];

    // Which accesses are writes?
    is_write = opcode inside {
        SB_32_MEM_WRITE, SB_32_DMS_REG_WRITE, SB_32_CFG_WRITE,
        SB_64_MEM_WRITE, SB_64_DMS_REG_WRITE, SB_64_CFG_WRITE
    };

    // 64-bit data variants
    is_64bit = opcode inside {
        SB_64_MEM_READ, SB_64_MEM_WRITE,
        SB_64_DMS_REG_READ, SB_64_DMS_REG_WRITE,
        SB_64_CFG_READ, SB_64_CFG_WRITE
    };

    // Parity error detection (UCIe §7.1.1)
    //  cp must always match; ep must match for writes
    parity_err = (cp_calc != reg_msg[63]);
    if (is_write) parity_err = parity_err || (ep_calc != hdr.ep);

    // false_msg: opcode is not any register-access type
    // UCIe §7.1.1: only the twelve reg-access opcodes are valid here
    false_msg = !(opcode inside {
        SB_32_MEM_READ,     SB_32_MEM_WRITE,
        SB_32_DMS_REG_READ, SB_32_DMS_REG_WRITE,
        SB_32_CFG_READ,     SB_32_CFG_WRITE,
        SB_64_MEM_READ,     SB_64_MEM_WRITE,
        SB_64_DMS_REG_READ, SB_64_DMS_REG_WRITE,
        SB_64_CFG_READ,     SB_64_CFG_WRITE
    });
end

// == Sequential latching =======================================================
// Latch decoded fields on valid cycle so FSM sees stable values across
// multiple clock cycles of execution.
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        Original_Header <= '0;
        reg_rdy         <= 1'b1;
    end else if (reg_vld) begin
        // Latch the original header so Completion_gen can echo back
        // srcid/dstid/tag for the completion routing (UCIe §7.1.1.2)
        Original_Header <= reg_msg[63:0];
        reg_rdy         <= 1'b0;   // busy until FSM completes
    end else begin
        reg_rdy         <= 1'b1;
    end
end

endmodule
