// =============================================================================
//  rdi_comp_req_decoder
//  UCIe Sideband RDI Controller — Completion / Request Destination Decoder
//
//  Pure combinational decode: inspects the SB packet opcode to classify
//  the packet as either a completion or a request.
//
//  Output
//  ──────
//  sel = 1 → completion  (route to down_comp_FIFO  — high priority)
//  sel = 0 → request     (route to down_req_FIFO   — low priority)
//
//  Used as the second decode stage in the downstream path, after the
//  local/remote split performed by rdi_dst_decoder.
// =============================================================================

`timescale 1ns/1ps

import sb_pkg::*;

module rdi_comp_req_decoder (
    // Incoming 128-bit SB packet
    input  logic [127:0] pkt,

    // 0 = request (down_req_FIFO),  1 = completion (down_comp_FIFO)
    output logic         sel
);

    sb_opcode_e opcode;
    assign opcode = sb_opcode_e'(pkt[4:0]);

    always_comb begin
        case (opcode)
            SB_COMPLETION_WITHOUT_DATA,
            SB_COMPLETION_WITH_32_DATA,
            SB_COMPLETION_WITH_64_DATA:
                sel = 1'b1;   // completion
            default:
                sel = 1'b0;   // request
        endcase
    end

endmodule
