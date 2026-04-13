// ===========================================================================
//  Reg_Access  (top-level wrapper)
//  SideBand Register-Access block for UCIe PHY layer
//
//  UCIe §7.1.1 – "Register Accesses: These can be Configuration (CFG) or
//  Memory Mapped accesses for both Reads or Writes.  All register accesses
//  (Reads or Writes) have an associated completion."
//
//  Architecture (docs/SB/SB_Reg_Access_arc.png):
//
//    RDI_CONTROL ──reg_msg / reg_vld──► ┌────────────────────┐
//                                       │    Reg_Access      │
//    ◄── completion_msg / vld ──────────│                    │
//                                       │ ┌────────────────┐ │   rf_addr  ┐
//                                       │ │Reg_DePacketizer│ │──►rf_be    │──► Reg_File
//                                       │ └───────┬────────┘ │   rf_wdata │   (standalone)
//                                       │         │          │   rd_en    │
//                                       │ ┌───────▼────────┐ │   wr_en    │
//                                       │ │  Reg_Access    │ │◄──rf_rdata─┘
//                                       │ │     FSM        │ │   rdata_vld
//                                       │ └───────┬────────┘ │
//                                       │         │          │
//                                       │ ┌───────▼────────┐ │
//                                       │ │ Completion_gen │ │
//                                       │ └────────────────┘ │
//                                       └────────────────────┘
//
//  NOTE: Reg_File is intentionally NOT instantiated here.
//        It is a standalone module connected by the parent integrator.
//        Reg_Access exposes the register-file bus as external ports.
//
//  Subblock                Role
//  ─────────────────────────────────────────────────────────────
//  Reg_DePacketizer         Decodes incoming SB reg-access packet
//  Reg_Access_FSM           IDLE→DECODE→EXECUTE→GENERATE controller
//  Completion_gen           Assembles and sends SB completion packet
// ===========================================================================

module Reg_Access
    import sb_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // =========================================================================
    // Sideband IN – incoming register-access request from RDI_CONTROL
    // =========================================================================
    input  logic [127:0] reg_msg,         // 128-bit SB packet
    input  logic         reg_vld,         // Packet valid

    // =========================================================================
    // Sideband OUT – completion to Link_Controller TX path
    // =========================================================================
    output logic [127:0] completion_msg,  // Completion packet
    output logic         completion_vld,  // Valid
    input  logic         completion_rdy,  // Back-pressure from TX arbiter

    // =========================================================================
    // Register File bus – connected externally to the standalone Reg_File
    // =========================================================================
    output logic [23:0]  rf_addr,         // Byte address to Reg_File
    output logic [7:0]   rf_be,           // Byte enables to Reg_File
    output logic [63:0]  rf_wdata,        // Write data to Reg_File
    output logic         rd_en,           // Read  enable to Reg_File
    output logic         wr_en,           // Write enable to Reg_File
    input  logic [63:0]  rf_rdata,        // Read data from Reg_File
    input  logic         rdata_vld,       // Data-valid from Reg_File

    // =========================================================================
    // Ready indication back to RDI_CONTROL
    // =========================================================================
    output logic         reg_rdy          // High when ready to accept next packet
);

// ---------------------------------------------------------------------------
// Internal wires between subblocks
// ---------------------------------------------------------------------------

// Reg_DePacketizer → FSM
sb_opcode_e   opcode;
logic [2:0]   tag;
logic [23:0]  rf_addr_dec;
logic [7:0]   rf_be_dec;
logic [63:0]  rf_wdata_dec;
logic [63:0]  Original_Header;
logic         parity_err;
logic         ep;
logic         false_msg;

// FSM → Completion_gen
logic [2:0]   status;
logic         completion_start;

// ---------------------------------------------------------------------------
// Sub-block instantiation
// ---------------------------------------------------------------------------

Reg_DePacketizer u_Reg_DePacketizer (
    .clk             ( clk             ),
    .rst_n           ( rst_n           ),
    .reg_msg         ( reg_msg         ),
    .reg_vld         ( reg_vld         ),
    .opcode          ( opcode          ),
    .tag             ( tag             ),
    .rf_addr         ( rf_addr_dec     ),
    .rf_be           ( rf_be_dec       ),
    .rf_wdata        ( rf_wdata_dec    ),
    .Original_Header ( Original_Header ),
    .parity_err      ( parity_err      ),
    .ep              ( ep              ),
    .false_msg       ( false_msg       ),
    .reg_rdy         ( reg_rdy         )
);

Reg_Access_FSM u_Reg_Access_FSM (
    .clk              ( clk              ),
    .rst_n            ( rst_n            ),
    .opcode           ( opcode           ),
    .rf_addr          ( rf_addr          ),
    .rf_be            ( rf_be            ),
    .rf_wdata         ( rf_wdata         ),
    .Original_Header  ( Original_Header  ),
    .parity_err       ( parity_err       ),
    .ep               ( ep               ),
    .false_msg        ( false_msg        ),
    .reg_vld          ( reg_vld          ),
    .rf_addr_o        ( rf_addr          ),
    .rf_be_o          ( rf_be            ),
    .rf_wdata_o       ( rf_wdata         ),
    .rd_en            ( rd_en            ),
    .wr_en            ( wr_en            ),
    .rdata_vld        ( rdata_vld        ),
    .status           ( status           ),
    .completion_start ( completion_start )
);


Completion_gen u_Completion_gen (
    .clk              ( clk              ),
    .rst_n            ( rst_n            ),
    .completion_start ( completion_start ),
    .status           ( status           ),
    .Original_Header  ( Original_Header  ),
    .rf_rdata         ( rf_rdata         ),
    .rdata_vld        ( rdata_vld        ),
    .completion_msg   ( completion_msg   ),
    .completion_vld   ( completion_vld   ),
    .completion_rdy   ( completion_rdy   )
);

endmodule
