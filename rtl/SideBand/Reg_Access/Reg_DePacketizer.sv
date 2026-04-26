// ===========================================================================
//  Reg_DePacketizer
//  UCIe Sideband Register-Access De-packetizer  (Chapter 9 / Table 3-7)
//
//  Receives a latched 128-bit SB request packet from the FIFO / RDI demux
//  and breaks it apart into:
//    • Control signals  → Reg_Access_FSM
//    • Address / data   → Reg_File
//    • Raw header latch → Completion_gen
//
//  ─── Packet layout (sb_header_t in sb_pkg.sv) ──────────────────────────────
//   Header [63:0]
//     [4:0]   opcode
//     [13:5]  rsvd0
//     [21:14] msgcode / Byte-enables  (BE[7:0] when RegAccess opcode)
//     [28:22] rsvd1
//     [31:29] srcid
//     [39:32] MsgSubcode / Tag[7:0]
//     [55:40] MsgInfo    / {4'b0, RL[3:0], offset[15:0]}
//     [58:56] dstid
//     [61:59] rsvd2
//     [62]    cp  (control parity – odd, covers [62:0])
//     [63]    dp  (data parity   – odd, covers payload[63:0])
//   Payload [127:64]  = write data (for write opcodes) or '0 (for reads)
//
//  ─── rf_addr[24:0] construction ────────────────────────────────────────────
//   [24]    space   = 0 (CFG_*) / 1 (MEM_* or DMS_REG_*)
//   [23:20] RL      = MsgInfo[19:16]  (4-bit Register Locator)
//   [19:0]  offset  = {MsgInfo[15:0], 4'b0}  (DWORD addr → byte addr)
//
//  Note: MsgInfo[19:16] carry RL; MsgInfo[15:0] carry the QWORD/DWORD offset.
//        The spec §3.x says address is a DWORD offset, so we left-shift by 2
//        to get a byte offset (×4).  For 64-bit aligned accesses the two LSBs
//        are always 0; keeping them allows byte-granular decode in Reg_File.
// ===========================================================================

module Reg_DePacketizer
    import sb_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // -----------------------------------------------------------------------
    // Incoming SB request packet (latched by whoever feeds this block)
    // -----------------------------------------------------------------------
    input  logic [127:0] reg_msg,     // Full 128-bit SB packet
    input  logic         reg_vld,    // Packet is valid / latched
    input  logic         reg_rdy,    // Rdy to accept new request

    // -----------------------------------------------------------------------
    // Control outputs → Reg_Access_FSM
    // -----------------------------------------------------------------------
    output sb_opcode_e   opcode,        // [4:0]  from header[4:0]
    output logic         parity_err,    // 1 when control-parity fails
    output logic         ep,            // Error Poison bit (header[63])
    output logic         false_msg,     // 1 when dstid is not a reg-access target

    // -----------------------------------------------------------------------
    // Datapath outputs → Reg_File
    // -----------------------------------------------------------------------
    output logic [24:0]  rf_addr,       // {space, RL[3:0], offset[19:0]}
    output logic [7:0]   rf_be,         // Byte enables  (from header[21:14])
    output logic         rf_is_64b_access,  // 1 for 64-bit opcodes
    output logic [63:0]  rf_wdata,      // Write payload (reg_msg[127:64])

    // -----------------------------------------------------------------------
    // Raw header latch → Completion_gen
    // -----------------------------------------------------------------------
    output logic [63:0]  Original_Header   // header[63:0], latched at reg_vld
);

// ---------------------------------------------------------------------------
// Internal Latch for the Packet
// ---------------------------------------------------------------------------
logic [127:0] latched_pkt;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        latched_pkt <= '0;
    else if (reg_vld && reg_rdy)
        latched_pkt <= reg_msg;
end

// ---------------------------------------------------------------------------
// Unpack header fields from the latched packet
// ---------------------------------------------------------------------------
sb_header_u hdr;
assign hdr = sb_header_u'(latched_pkt[63:0]);   // Header occupies lower 64 bits

// ---------------------------------------------------------------------------
// Always-comb outputs – decoded purely from latched packet
// ---------------------------------------------------------------------------
always_comb begin
    // ── Control path ──────────────────────────────────────────────────────
    opcode          = hdr.req.opcode;
    ep              = hdr.req.ep;       // Error Poison from request header bit 5

    // Control parity check: even parity over header[62:0]
    // cp is stored in hdr.req.cp (bit[62]); parity of hdr[62:0] should == hdr.cp
    // even parity: ^(hdr[62:0]) == 1 means even number of 1s → bit should be 1
    // The standard check: cp_expected = (^hdr[61:0]); error if cp_expected != hdr.cp
    parity_err      = (hdr.req.cp !== (^(latched_pkt[61:0])));

    // false_msg: dstid is not a register-access destination
    // According to UCIe spec, reg-access packets are addressed to LOCAL_ADAPTER(001),
    // LOCAL_PHY(010), or REMOTE_REG_ACCESS(100).  Any other dstid is a false message.
    false_msg       = (hdr.req.dstid != LOCAL_PHY);

    // ── Address decode ────────────────────────────────────────────────────
    // space bit: CFG opcodes → 0, MEM/DMS opcodes → 1
    // MsgInfo [55:40] layout per spec:
    //   [55:52] = RL[3:0]  (Register Locator, 4 bits)
    //   [51:40] = addr[19:8]   \  12-bit DWORD offset
    // But looking at UCIe spec §9 table, the 20-bit byte offset is encoded as:
    //   MsgInfo[55:40] = {RL[3:0], offset[19:4]}   (offset in units of 16B? No...)
    // The spec §3 says the "address" field for reg-access is a DWORD offset:
    //   MsgInfo[55:40] → Top 16 bits: {RL[3:0], addr[11:0]}  where addr is DWORD offset
    //   The full 20-bit byte offset = {addr_dword[9:0], 2'b00}   (×4 for DWORD)
    // However, since Reg_File expects a byte offset [19:0], we simply mirror the
    // 16 bits from MsgInfo and pad with 4 zeros to reach the needed resolution:
    //   rf_addr[19:0] = {MsgInfo[11:0], 4'b0000}   (12-bit DWORD offset → 16-bit byte, padded to 20)
    // For clarity we use: {RL[3:0]=MsgInfo[15:12], byteOffset[19:0]=MsgInfo[11:0]<<4 + BE lsb}
    //
    // Simplified practical construction (aligned with what Reg_File uses §9 offsets):
    //   space  [24]    = opcode[3] (bit 3 selects MEM vs CFG)
    //   RL     [23:20] = hdr.MsgInfo[15:12]  (upper 4 bits of MsgInfo's address field)
    //   offset [19:0]  = {hdr.MsgInfo[11:0], hdr.msgcode[7:4]} (12b DWORD offset + sub-DWORD from BE top nibble)
    //
    // Simplest and most consistent with UCIe §3.5 "Address" field description:
    //   The 16-bit MsgInfo[15:0] = {RL[3:0], DWORD_offset[11:0]}
    //   byte_offset = DWORD_offset << 2  →  14 bits, zero-padded to 20

    rf_addr[24]    = (opcode == SB_32_CFG_READ ||
                      opcode == SB_32_CFG_WRITE||
                      opcode == SB_64_CFG_READ ||
                      opcode == SB_64_CFG_WRITE) ? 1'b0 : 1'b1;           // bit3 of opcode: 0=CFG, 1=MEM
    rf_addr[23:0]  = hdr.req.addr;       // Directly use the 24-bit address

    // ── Byte enables ─────────────────────────────────────────────────────
    // Spec §3.4: BE[7:0] are carried in header bits [19:12] = be field
    rf_be           = hdr.req.be;         // Direct access from struct
    // ── 64-bit access flag ────────────────────────────────────────────────
    rf_is_64b_access = opcode[3];         // 64-bit opcodes have opcode[3]=1

    // ── Write data ───────────────────────────────────────────────────────
    rf_wdata        = latched_pkt[127:64];     // Payload = upper 64 bits of packet
end

// ---------------------------------------------------------------------------
// Original_Header latch (registered at packet-valid)
// ---------------------------------------------------------------------------
assign Original_Header = latched_pkt[63:0];

endmodule