// ===========================================================================
//  Reg_Access  (Top-level wrapper)
//  UCIe Sideband Register-Access Block – Chapter 9
//
//  Instantiates and wires together:
//    1. Reg_DePacketizer  – breaks the 128-bit SB packet into control/datapath
//    2. Reg_Access_FSM    – sequences DECODE → EXECUTE → GEN
//    3. Completion_gen    – builds the SB completion packet
//
//  ─── External Interfaces ────────────────────────────────────────────────
//    • SB RX side  : reg_msg / reg_vld / reg_vld / reg_rdy
//    • SB TX side  : completion_msg / completion_vld / completion_rdy
//    • PHY context : phy_in_reset
//    • Reg_File interface : rf_addr, rf_be, rf_is_64b_access, rf_wdata,
//                           rd_en, wr_en, rf_rdata, rdata_vld, addr_err_o
// ===========================================================================

module Reg_Access
    import sb_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // -----------------------------------------------------------------------
    // SB RX interface (from Link_Demux / RDI control)
    // -----------------------------------------------------------------------
    input  logic [127:0] reg_msg,           // Incoming 128-bit SB packet
    input  logic         reg_vld,          // Packet is latched/valid
    output logic         reg_rdy,          // Handshake: block is rdy

    // -----------------------------------------------------------------------
    // PHY context
    // -----------------------------------------------------------------------
    input  logic         phy_in_reset,     // 1 during Link/Soft Reset → UR all reqs

    // -----------------------------------------------------------------------
    // SB TX interface (to Link_Controller TX arbiter)
    // -----------------------------------------------------------------------
    output logic [127:0] completion_msg,   // Completion SB packet
    output logic         completion_vld,   // Completion valid
    input  logic         completion_rdy,   // TX arbiter rdy

    // =======================================================================
    //  Register-access interface to Reg_File
    // =======================================================================
    output logic [24:0]  rf_addr,
    output logic [7:0]   rf_be,
    output logic         rf_is_64b_access,
    output logic [63:0]  rf_wdata,
    output logic         rd_en,
    output logic         wr_en,
    input  logic [63:0]  rf_rdata,
    input  logic         rdata_vld,
    input  logic         addr_err_o
);

// ===========================================================================
//  Internal wires connecting sub-modules
// ===========================================================================

// DePacketizer → FSM
sb_opcode_e  opcode_w;
logic        parity_err_w;
logic        ep_w;
logic        false_msg_w;

// DePacketizer → Completion_gen
logic [63:0] orig_hdr_w;

// FSM → Completion_gen
logic [2:0]  status_w;
logic        completion_start_w;

// ===========================================================================
//  1. Reg_DePacketizer
// ===========================================================================
Reg_DePacketizer u_depacketizer (
    .clk             (clk),
    .rst_n           (rst_n),
    // Packet input
    .reg_msg          (reg_msg),
    .reg_vld         (reg_vld),
    .reg_rdy         (reg_rdy),
    // Control → FSM
    .opcode          (opcode_w),
    .parity_err      (parity_err_w),
    .ep              (ep_w),
    .false_msg       (false_msg_w),
    // Datapath → Reg_File
    .rf_addr         (rf_addr),
    .rf_be           (rf_be),
    .rf_is_64b_access(rf_is_64b_access),
    .rf_wdata        (rf_wdata),
    // Raw header → Completion_gen
    .Original_Header (orig_hdr_w)
);

// ===========================================================================
//  2. Reg_Access_FSM
//     The FSM sees addr_err from Reg_File as an additional error flag.
//     We OR it into parity_err input (or pass false_msg – using parity_err
//     since addr_err is a decode-time error).  In practice the FSM evaluates
//     error in DECODE state before rd_en/wr_en are issued; addr_err is only
//     valid during EXECUTE.  We feed it into the FSM's `ep` so that if the
//     register file asserts addr_err the completion transitions to UR.
// ===========================================================================
Reg_Access_FSM u_fsm (
    .clk             (clk),
    .rst_n           (rst_n),
    // Handshake
    .reg_vld         (reg_vld),
    .reg_rdy         (reg_rdy),
    .completion_rdy  (completion_rdy),
    // From DePacketizer
    .opcode          (opcode_w),
    .parity_err      (parity_err_w),
    .ep              (ep_w),
    .false_msg       (false_msg_w),
    // To/From Reg_File
    .rd_en           (rd_en),
    .wr_en           (wr_en),
    .rdata_vld       (rdata_vld),
    .rf_addr_err     (addr_err_o),
    // To Completion_gen
    .status          (status_w),
    .completion_start(completion_start_w)
);

// ===========================================================================
//  3. Completion_gen
// ===========================================================================
Completion_gen u_completion_gen (
    .clk             (clk),
    .rst_n           (rst_n),
    // From FSM
    .completion_start(completion_start_w),
    .status          (status_w),
    // From DePacketizer
    .Original_Header (orig_hdr_w),
    // From Reg_File
    .rf_rdata        (rf_rdata),
    .rdata_vld       (rdata_vld),
    // To TX arbiter
    .completion_msg  (completion_msg),
    .completion_vld  (completion_vld),
    .completion_rdy  (completion_rdy)
);

endmodule
