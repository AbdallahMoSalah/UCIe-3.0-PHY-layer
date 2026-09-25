`timescale 1ns/1ps
// =============================================================================
// Module  : ucie_link_fault_injector
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : Channel model / fault-injection block sitting BETWEEN two
//           UCIe_FPGA_top_wrapper_link dies on their exposed MainBand/SideBand
//           PARALLEL boundary.  It replays, on the parallel boundary, the same
//           faults the UCIe_PHY_wrapper_tb applied on the serial boundary
//           between die0 and die1:
//
//             * corrupt_0to1 / corrupt_1to0 : per-lane stuck-at-0 on the MB
//                 data lane word (TB: i_RD_P[i] = corrupt ? 1'b0 : ...).
//             * reverse_0to1 / reverse_1to0 : MB lane-order reversal
//                 (TB: reverse_lanes_* on o_TD_P[NUM_LANES-1-i]).
//             * vld_err_0to1 / vld_err_1to0 : flip the MB valid-frame strobe
//                 (TB: i_RVLD_P = o_TVLD ^ rx_vld_error_inject).
//             * block_sideband : cut the sideband both ways
//                 (TB: RXCKSB/RXDATASB forced 0 when block_sideband).
//
//           The block is purely combinational: it maps each die's registered TX
//           parallel outputs to the partner die's RX parallel inputs, exactly
//           mirroring the internal fold that UCIe_FPGA_loopback performed, but
//           now die0.TX -> die1.RX and die1.TX -> die0.RX.
//
//           Cross-connect (per direction, X = source die, Y = sink die):
//             X.o_mb_tx_ser_en       -> Y.i_mb_rx_data_valid
//             X.o_mb_tx_lane[]       -> Y.i_mb_rx_lane[]        (corrupt/reverse)
//             X.o_mb_tx_valid_ser_en -> Y.i_mb_rx_valid_frame_vld (flip)
//             X.o_mb_tx_valid_word   -> Y.i_mb_rx_valid_frame_data
//             X.o_mb_tx_ckp/ckn/trk  -> Y.i_mb_rx_ckp/ckn/trk    (untouched)
//             X.o_sb_tx_data/vld     -> Y.i_sb_rx_data/vld        (block)
// =============================================================================
module ucie_link_fault_injector #(
    parameter NUM_LANES     = 16,
    parameter DATA_WIDTH_MB = 32
)(
    // =========================================================================
    // Fault-injection controls (drive from GPIO/PS)
    // =========================================================================
    input  [NUM_LANES-1:0]                  corrupt_0to1,
    input  [NUM_LANES-1:0]                  corrupt_1to0,
    input                                   reverse_0to1,
    input                                   reverse_1to0,
    input                                   vld_err_0to1,
    input                                   vld_err_1to0,
    input                                   block_sideband,

    // =========================================================================
    // Die-0 TX parallel boundary (from die0.o_mb_tx_* / o_sb_tx_*)
    // =========================================================================
    input                                   d0_mb_tx_ser_en,
    input  [NUM_LANES*DATA_WIDTH_MB-1:0]    d0_mb_tx_lane,
    input                                   d0_mb_tx_valid_ser_en,
    input  [DATA_WIDTH_MB-1:0]              d0_mb_tx_valid_word,
    input                                   d0_mb_tx_ckp,
    input                                   d0_mb_tx_ckn,
    input                                   d0_mb_tx_trk,
    input  [63:0]                           d0_sb_tx_data,
    input                                   d0_sb_tx_vld,

    // =========================================================================
    // Die-1 TX parallel boundary (from die1.o_mb_tx_* / o_sb_tx_*)
    // =========================================================================
    input                                   d1_mb_tx_ser_en,
    input  [NUM_LANES*DATA_WIDTH_MB-1:0]    d1_mb_tx_lane,
    input                                   d1_mb_tx_valid_ser_en,
    input  [DATA_WIDTH_MB-1:0]              d1_mb_tx_valid_word,
    input                                   d1_mb_tx_ckp,
    input                                   d1_mb_tx_ckn,
    input                                   d1_mb_tx_trk,
    input  [63:0]                           d1_sb_tx_data,
    input                                   d1_sb_tx_vld,

    // =========================================================================
    // Die-0 RX parallel boundary (to die0.i_mb_rx_* / i_sb_rx_*)  <- die1 TX
    // =========================================================================
    output                                  d0_mb_rx_data_valid,
    output [NUM_LANES*DATA_WIDTH_MB-1:0]    d0_mb_rx_lane,
    output                                  d0_mb_rx_valid_frame_vld,
    output [DATA_WIDTH_MB-1:0]              d0_mb_rx_valid_frame_data,
    output                                  d0_mb_rx_ckp,
    output                                  d0_mb_rx_ckn,
    output                                  d0_mb_rx_trk,
    output [63:0]                           d0_sb_rx_data,
    output                                  d0_sb_rx_vld,

    // =========================================================================
    // Die-1 RX parallel boundary (to die1.i_mb_rx_* / i_sb_rx_*)  <- die0 TX
    // =========================================================================
    output                                  d1_mb_rx_data_valid,
    output [NUM_LANES*DATA_WIDTH_MB-1:0]    d1_mb_rx_lane,
    output                                  d1_mb_rx_valid_frame_vld,
    output [DATA_WIDTH_MB-1:0]              d1_mb_rx_valid_frame_data,
    output                                  d1_mb_rx_ckp,
    output                                  d1_mb_rx_ckn,
    output                                  d1_mb_rx_trk,
    output [63:0]                           d1_sb_rx_data,
    output                                  d1_sb_rx_vld
);

    // =========================================================================
    // MainBand data-lane cross-connect with per-lane corruption + reversal.
    //   Lane i occupies bits [i*DATA_WIDTH_MB +: DATA_WIDTH_MB].
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i = i + 1) begin : g_lane
            // die0 -> die1
            assign d1_mb_rx_lane[i*DATA_WIDTH_MB +: DATA_WIDTH_MB] =
                corrupt_0to1[i] ? {DATA_WIDTH_MB{1'b0}} :
                (reverse_0to1
                    ? d0_mb_tx_lane[(NUM_LANES-1-i)*DATA_WIDTH_MB +: DATA_WIDTH_MB]
                    : d0_mb_tx_lane[i*DATA_WIDTH_MB +: DATA_WIDTH_MB]);
            // die1 -> die0
            assign d0_mb_rx_lane[i*DATA_WIDTH_MB +: DATA_WIDTH_MB] =
                corrupt_1to0[i] ? {DATA_WIDTH_MB{1'b0}} :
                (reverse_1to0
                    ? d1_mb_tx_lane[(NUM_LANES-1-i)*DATA_WIDTH_MB +: DATA_WIDTH_MB]
                    : d1_mb_tx_lane[i*DATA_WIDTH_MB +: DATA_WIDTH_MB]);
        end
    endgenerate

    // =========================================================================
    // MainBand word/valid/clock cross-connect (die0 TX -> die1 RX)
    // =========================================================================
    assign d1_mb_rx_data_valid       = d0_mb_tx_ser_en;
    assign d1_mb_rx_valid_frame_vld  = d0_mb_tx_valid_ser_en ^ vld_err_0to1;
    assign d1_mb_rx_valid_frame_data = d0_mb_tx_valid_word;
    assign d1_mb_rx_ckp              = d0_mb_tx_ckp;
    assign d1_mb_rx_ckn              = d0_mb_tx_ckn;
    assign d1_mb_rx_trk              = d0_mb_tx_trk;

    // MainBand word/valid/clock cross-connect (die1 TX -> die0 RX)
    assign d0_mb_rx_data_valid       = d1_mb_tx_ser_en;
    assign d0_mb_rx_valid_frame_vld  = d1_mb_tx_valid_ser_en ^ vld_err_1to0;
    assign d0_mb_rx_valid_frame_data = d1_mb_tx_valid_word;
    assign d0_mb_rx_ckp              = d1_mb_tx_ckp;
    assign d0_mb_rx_ckn              = d1_mb_tx_ckn;
    assign d0_mb_rx_trk              = d1_mb_tx_trk;

    // =========================================================================
    // SideBand cross-connect (block_sideband cuts both directions)
    // =========================================================================
    assign d1_sb_rx_data = block_sideband ? 64'b0 : d0_sb_tx_data;
    assign d1_sb_rx_vld  = block_sideband ? 1'b0  : d0_sb_tx_vld;
    assign d0_sb_rx_data = block_sideband ? 64'b0 : d1_sb_tx_data;
    assign d0_sb_rx_vld  = block_sideband ? 1'b0  : d1_sb_tx_vld;

endmodule
