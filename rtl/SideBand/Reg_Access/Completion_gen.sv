// ===========================================================================
//  Completion_gen (Updated & Fixed Version)
//  Builds the sideband completion packet that must be returned for every
//  register-access request.
//
//  Fixes Applied based on UCIe Spec Rev 3.0:
//  1. UR/CA status returns 64b_DATA carrying the Original Request Header.
//  2. Data Parity (ep) and Control Parity (cp) use Odd Parity (XNOR).
//  3. Byte Enables (BE) at bits [21:14] are mirrored from the request.
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
    input  logic [2:0]   status,            // SC(000) / UR(001) from FSM

    // -----------------------------------------------------------------------
    // From Reg_DePacketizer 
    // -----------------------------------------------------------------------
    input  logic[63:0]  Original_Header,   // Latched original request header

    // -----------------------------------------------------------------------
    // Read data from Register File
    // -----------------------------------------------------------------------
    input  logic[63:0]  rf_rdata,          // Register-file read data
    input  logic         rdata_vld,         // Read-data valid

    // -----------------------------------------------------------------------
    // Output completion packet to Link_Controller TX path
    // -----------------------------------------------------------------------
    output logic[127:0] completion_msg,    // Full 128-bit completion packet
    output logic         completion_vld,    // Packet is valid
    input  logic         completion_rdy     // Back-pressure from TX arbiter
);

// ---------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------
sb_header_t   req_hdr;           // View into original request header
sb_header_t   cpl_hdr;           // Completion header being built
sb_opcode_e   cpl_opcode;        // Determined completion opcode
logic [63:0]  cpl_payload;       // Data payload (rf_rdata or Original_Header)
logic         is_64bit_read;     
logic         is_32bit_read;     
logic         is_read;

// ---------------------------------------------------------------------------
// Decode original request opcode & Construct Payload
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
    // Choose completion opcode & Payload (Fixed for UR/CA Fast-Forward)
    // -----------------------------------------------------------------------
    if (|status) begin
        // [FIX]: Any error (UR/CA) -> Return 64b Data containing Original Header
        cpl_opcode  = SB_COMPLETION_WITH_64_DATA;
        cpl_payload = Original_Header;
    end else if (is_32bit_read) begin
        // Successful 32-bit read
        cpl_opcode  = SB_COMPLETION_WITH_32_DATA;
        cpl_payload = {32'h0, rf_rdata[31:0]};  // lower 32 bits only
    end else if (is_64bit_read) begin
        // Successful 64-bit read
        cpl_opcode  = SB_COMPLETION_WITH_64_DATA;
        cpl_payload = rf_rdata;
    end else begin
        // Write completed successfully – no data
        cpl_opcode  = SB_COMPLETION_WITHOUT_DATA;
        cpl_payload = '0;
    end

    // -----------------------------------------------------------------------
    // Build completion header
    // -----------------------------------------------------------------------
    cpl_hdr            = '0;
    cpl_hdr.opcode     = cpl_opcode;

    // Mirror Tag (bits [13:11] mapped to MsgSubcode equivalent)
    cpl_hdr.MsgSubcode = {5'b0, req_hdr[13:11]};  

    // Insert Status into bits [34:32] (Mapped to MsgInfo equivalent)
    cpl_hdr.MsgInfo    = {13'b0, status};

    // Swap srcid/dstid to route back to requester
    cpl_hdr.srcid      = req_hdr.dstid;   
    cpl_hdr.dstid      = req_hdr.srcid;   

    // [FIX]: Mirror Byte Enables (BE) into bits [21:14]
    // Because cpl_hdr is a packed struct, we can safely index its bits directly
    cpl_hdr[21:14]     = req_hdr[21:14];

    // [FIX]: Data Parity (Odd Parity -> XNOR)
    // ep = XNOR of payload bits for data-carrying completions; 0 otherwise
    cpl_hdr.ep         = (cpl_opcode != SB_COMPLETION_WITHOUT_DATA) ? ~(^cpl_payload) : 1'b0;

    // Control parity placeholder (calculated sequentially to avoid long combinational path)
    cpl_hdr.cp         = 1'b0;   
end

// ---------------------------------------------------------------------------
// Sequential – register output when FSM triggers completion
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        completion_msg <= '0;
        completion_vld <= 1'b0;
    end else if (completion_start) begin
        
        // [FIX]: Control Parity (Odd Parity -> XNOR)
        // Compute odd parity over final header[62:0]
        automatic logic [62:0] hdr_low = cpl_hdr[62:0];
        automatic logic cp_final       = ~(^hdr_low);

        // Assemble final 128-bit packet
        completion_msg <= {cpl_payload, cp_final, cpl_hdr[62:0]};
        completion_vld <= 1'b1;
        
    end else if (completion_rdy && completion_vld) begin
        // Downstream accepted; de-assert valid
        completion_vld <= 1'b0;
        completion_msg <= '0;
    end
end

endmodule