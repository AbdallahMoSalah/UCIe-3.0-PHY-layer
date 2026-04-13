// ===========================================================================
//  Completion_gen
//  Builds the sideband completion packet that must be returned for every
//  register-access request.
//
//  UCIe §7.1.1.2 – "Completion: The target returns a Completion for every
//  Register-Access request."
//
//  Completion header layout (Table 7-7, UCIe §7.1.1.2):
//   Bit  63      : cp (even parity over bits[62:0])
//   Bit  62      : ep (data parity – even parity of data payload; 0 if no data)
//   Bit  61:59   : rsvd2
//   Bit  58:56   : dstid[2:0]  ← mirrored from request srcid
//   Bits 55:35   : rsvd / MsgInfo (zeroed for completion)
//   Bits 34:32   : status[2:0]
//                    3'b000 – Successful Completion (SC)
//                    3'b001 – Unsupported Request   (UR)
//                    3'b010 – Completer Abort        (CA) [not used here]
//                    3'b111 – Stall                  [handled by higher layer]
//   Bits 31:29   : srcid[2:0]  ← mirrored from request dstid
//   Bits 28:22   : rsvd1
//   Bits 21:14   : rsvd (BE not used in completion)
//   Bits 13:11   : tag[2:0]    ← mirrored from request tag
//   Bits 10:5    : rsvd0
//   Bits  4:0    : opcode[4:0] – Completion opcode:
//                    5'b10000 – Completion without Data  (read 0 bytes / write)
//                    5'b10001 – Completion with 32b Data (32-bit read)
//                    5'b11001 – Completion with 64b Data (64-bit read)
//
//  Payload [127:64]: read-data (rf_rdata) for reads, zeros for writes / errors
// ===========================================================================

module Completion_gen
    import sb_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // -----------------------------------------------------------------------
    // Trigger from FSM
    // -----------------------------------------------------------------------
    input  logic         completion_start,  // 1-cycle pulse from FSM:GENERATE
    input  logic [2:0]   status,            // SC / UR from FSM

    // -----------------------------------------------------------------------
    // From Reg_DePacketizer – original request header for field mirroring
    // UCIe §7.1.1.2: "The completion must contain the same tag and source
    // identifier as the corresponding request header."
    // -----------------------------------------------------------------------
    input  logic [63:0]  Original_Header,   // Latched request header

    // -----------------------------------------------------------------------
    // Read data from Register File (64 bits)
    // UCIe §7.1.1.2: carried in completion payload for read operations
    // -----------------------------------------------------------------------
    input  logic [63:0]  rf_rdata,          // Register-file read data
    input  logic         rdata_vld,         // Read-data valid

    // -----------------------------------------------------------------------
    // Output completion packet to Link_Controller TX path
    // -----------------------------------------------------------------------
    output logic [127:0] completion_msg,    // Full 128-bit completion packet
    output logic         completion_vld,    // Packet is valid
    input  logic         completion_rdy     // Back-pressure from TX arbiter
);

// ---------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------
sb_header_t   req_hdr;           // View into original request header
sb_header_t   cpl_hdr;           // Completion header being built
sb_opcode_e   cpl_opcode;        // Determined completion opcode
logic [63:0]  cpl_payload;       // Data payload (zeros or rf_rdata)
logic         is_64bit_read;     // True if original request was 64-bit read
logic         is_32bit_read;     // True if original request was 32-bit read
logic         is_read;

// ---------------------------------------------------------------------------
// Decode original request opcode
// ---------------------------------------------------------------------------
always_comb begin
    req_hdr = Original_Header;

    is_32bit_read = req_hdr.opcode inside {
        SB_32_MEM_READ, SB_32_DMS_REG_READ, SB_32_CFG_READ
    };
    is_64bit_read = req_hdr.opcode inside {
        SB_64_MEM_READ, SB_64_DMS_REG_READ, SB_64_CFG_READ
    };
    is_read = is_32bit_read || is_64bit_read;

    // -----------------------------------------------------------------------
    // Choose completion opcode  (UCIe §7.1.1.2, Table 7-1)
    // -----------------------------------------------------------------------
    if (|status) begin
        // Any error → no-data completion so requestor can decode the error code
        // UCIe §7.1.1.2: for UR completions, data is not returned.
        cpl_opcode  = SB_COMPLETION_WITHOUT_DATA;
        cpl_payload = '0;
    end else if (is_32bit_read) begin
        // SB_COMPLETION_WITH_32_DATA (opcode 5'b10001)
        cpl_opcode  = SB_COMPLETION_WITH_32_DATA;
        cpl_payload = {32'h0, rf_rdata[31:0]};  // lower 32 bits only
    end else if (is_64bit_read) begin
        // SB_COMPLETION_WITH_64_DATA (opcode 5'b11001)
        cpl_opcode  = SB_COMPLETION_WITH_64_DATA;
        cpl_payload = rf_rdata;
    end else begin
        // Write completed successfully – no data
        // SB_COMPLETION_WITHOUT_DATA (opcode 5'b10000)
        cpl_opcode  = SB_COMPLETION_WITHOUT_DATA;
        cpl_payload = '0;
    end

    // -----------------------------------------------------------------------
    // Build completion header
    // UCIe §7.1.1.2: dstid ← req srcid, srcid ← req dstid, tag unchanged
    // -----------------------------------------------------------------------
    cpl_hdr            = '0;
    cpl_hdr.opcode     = cpl_opcode;

    // Mirror tag from request (bits [13:11] of original header reused)
    // Packed into MsgSubcode[2:0] equivalent position [13:11]
    // (Completion header uses same 64-bit layout; tag sits at bits [13:11])
    cpl_hdr.MsgSubcode = {5'b0, req_hdr[13:11]};  // tag in low 3 bits

    // status[2:0] sits at bits [34:32] of the full 64-bit header,
    // which is MsgInfo[2:0] in our packed struct (bits [41:40..39:32]=MsgSubcode)
    // Use MsgInfo[2:0] for status encoding per Table 7-7
    cpl_hdr.MsgInfo    = {13'b0, status};

    // Route back to requester: swap srcid/dstid
    cpl_hdr.srcid      = req_hdr.dstid;   // responder → was target, now source
    cpl_hdr.dstid      = req_hdr.srcid;   // send back to requester

    // Data parity (UCIe §7.1.1): ep = XOR of payload bits for data-carrying
    // completions; 0 otherwise
    cpl_hdr.ep         = (cpl_opcode != SB_COMPLETION_WITHOUT_DATA)
                         ? ^cpl_payload : 1'b0;

    // Control parity: even parity over header bits [62:0]
    // Temporarily assign payload, compute cp, then finalise below
    cpl_hdr.cp         = 1'b0;   // placeholder; adjusted after cp calc
end

// ---------------------------------------------------------------------------
// Sequential – register output when FSM triggers completion
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        completion_msg <= '0;
        completion_vld <= 1'b0;
    end else if (completion_start) begin
        // Assemble 128-bit packet.
        // Compute cp over final header [62:0] (excluding bit 63 itself)
        // then set bit 63.
        automatic logic [62:0] hdr_low = {
            cpl_hdr[62:0]   // everything except cp at bit 63
        };
        automatic logic cp_final = ^hdr_low;

        completion_msg <= {cpl_payload, cp_final, cpl_hdr[62:0]};
        completion_vld <= 1'b1;
    end else if (completion_rdy && completion_vld) begin
        // Downstream accepted; de-assert valid
        completion_vld <= 1'b0;
        completion_msg <= '0;
    end
end

endmodule
