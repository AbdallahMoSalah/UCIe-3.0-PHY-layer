import sb_pkg::*;
module sb_priority_arbiter #(
    parameter int DATA_WIDTH = 128
) (
    // High Priority Input Interface
    input  logic [DATA_WIDTH-1:0] hip_msg,
    input  logic                  hip_vld,
    output logic                  hip_rdy,

    // Low Priority Input Interface
    input  logic [DATA_WIDTH-1:0] lop_msg,
    input  logic                  lop_vld,
    output logic                  lop_rdy,

    // Arbitrated Output Interface
    output logic [DATA_WIDTH-1:0] out_msg,
    output logic                  out_vld,
    input  logic                  out_rdy
);
    sb_packet_t sb_packet;
    always_comb begin
        // Priority 1: High Priority Input
        if (hip_vld) begin
            out_msg = hip_msg;
            out_vld = 1'b1;
        end
        // Priority 2: Low Priority Input
        else begin
            out_msg = lop_msg;
            out_vld = lop_vld;
        end

        // ── Ready signals ────────────────────────────────────────────────────
        // rdy MUST be independent of vld (standard valid/ready handshake).
        // hip_rdy: downstream is free (out_rdy=1) and no starvation.
        // lop_rdy: downstream is free AND no high-priority msg is present.
        hip_rdy = out_rdy;
        lop_rdy = out_rdy && !hip_vld;
   
        `ifdef SIMULATION
             // DEBUG
             // synthesis translate_off
             sb_packet = out_msg; 
             if (out_vld) begin
             $display("[%0t] [sb_priority_arbiter %m] Received Message! dstid=%0s out_msg[127:64]=%h [63:0]=%s", 
                      $time, sb_packet.header.req.dstid, sb_packet.payload, sb_packet.header.req.opcode);
             end
             // synthesis translate_on
        `endif

    end

endmodule
