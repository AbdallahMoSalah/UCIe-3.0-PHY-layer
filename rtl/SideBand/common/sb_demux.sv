`timescale 1ns/1ps

// =============================================================================
//  sb_demux
//  1-of-2 sideband demultiplexer.
//
//  Parameter
//  ─────────
//  DATA_WIDTH : width of the data channel (default 128-bit SB packet)
//
//  Interface
//  ─────────
//  data_in      : incoming data  (broadcast to both outputs)
//  vld_in       : incoming valid
//  sel          : output select  (0 → port 0,  1 → port 1)
//                 driven externally by a decoder (e.g. rdi_dst_decoder)
//
//  data_out_0 / vld_out_0 : active when sel == 0
//  data_out_1 / vld_out_1 : active when sel == 1
//
//  Notes
//  ─────
//  • Pure combinational — no rdy / backpressure signals.
//  • Data is broadcast; only the selected port's vld is asserted.
//  • No internal routing logic — all decode is done externally via sel.
// =============================================================================

module sb_demux #(
    parameter int DATA_WIDTH = 128
)(
    // ── Ingress ──────────────────────────────────────────────────────────────
    input  logic [DATA_WIDTH-1:0] data_in,
    input  logic                  vld_in,

    // ── Select (from external decoder) ───────────────────────────────────────
    input  logic                  sel,      // 0 = port 0,  1 = port 1

    // ── Port 0 ───────────────────────────────────────────────────────────────
    output logic [DATA_WIDTH-1:0] data_out_0,
    output logic                  vld_out_0,

    // ── Port 1 ───────────────────────────────────────────────────────────────
    output logic [DATA_WIDTH-1:0] data_out_1,
    output logic                  vld_out_1
);

    // Broadcast data; gate valid to the selected port only.
    assign data_out_0 = data_in;
    assign data_out_1 = data_in;

    assign vld_out_0  = vld_in & ~sel;
    assign vld_out_1  = vld_in &  sel;

endmodule
