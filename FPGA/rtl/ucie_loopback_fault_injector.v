`timescale 1ns/1ps
// =============================================================================
// Module  : ucie_loopback_fault_injector
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : Single-path (self-fold) fault-injection channel for a ONE-DIE
//           self-loopback.  It folds a UCIe_FPGA_top_wrapper_link die's own
//           exposed TX parallel boundary back onto its own RX parallel boundary
//           (exactly the fold UCIe_FPGA_loopback did internally), but routes it
//           through the same fault taps the UCIe_PHY_wrapper_tb used between two
//           dies - now applied to the die's own loopback:
//
//             * corrupt[NUM_LANES] : per-lane stuck-at-0 on the MB data lane word
//             * reverse            : MB lane-order reversal
//             * vld_err            : flip the MB valid-frame strobe
//             * block_sideband     : cut the sideband self-fold
//
//           Purely combinational; TX and RX run in the same word-clock domain
//           (no SerDes), so the fold stays lock-step word-for-word.
//
//           Fold (fault-tapped):
//             mb_tx_ser_en       -> mb_rx_data_valid
//             mb_tx_lane[]       -> mb_rx_lane[]            (corrupt/reverse)
//             mb_tx_valid_ser_en -> mb_rx_valid_frame_vld  (flip via vld_err)
//             mb_tx_valid_word   -> mb_rx_valid_frame_data
//             mb_tx_ckp/ckn/trk  -> mb_rx_ckp/ckn/trk      (untouched)
//             sb_tx_data/vld     -> sb_rx_data/vld          (block_sideband)
// =============================================================================
module ucie_loopback_fault_injector #(
    parameter NUM_LANES     = 16,
    parameter DATA_WIDTH_MB = 32
)(
    // ---- Fault-injection controls (drive from GPIO/PS) ----
    input  [NUM_LANES-1:0]                  corrupt,
    input                                   reverse,
    input                                   vld_err,
    input                                   block_sideband,

    // ---- Die TX parallel boundary in (from die.o_mb_tx_* / o_sb_tx_*) ----
    input                                   mb_tx_ser_en,
    input  [NUM_LANES*DATA_WIDTH_MB-1:0]    mb_tx_lane,
    input                                   mb_tx_valid_ser_en,
    input  [DATA_WIDTH_MB-1:0]              mb_tx_valid_word,
    input                                   mb_tx_ckp,
    input                                   mb_tx_ckn,
    input                                   mb_tx_trk,
    input  [63:0]                           sb_tx_data,
    input                                   sb_tx_vld,

    // ---- Die RX parallel boundary out (to die.i_mb_rx_* / i_sb_rx_*) ----
    output                                  mb_rx_data_valid,
    output [NUM_LANES*DATA_WIDTH_MB-1:0]    mb_rx_lane,
    output                                  mb_rx_valid_frame_vld,
    output [DATA_WIDTH_MB-1:0]              mb_rx_valid_frame_data,
    output                                  mb_rx_ckp,
    output                                  mb_rx_ckn,
    output                                  mb_rx_trk,
    output [63:0]                           sb_rx_data,
    output                                  sb_rx_vld
);

    // MainBand data-lane fold with per-lane corruption + reversal.
    //   Lane i occupies bits [i*DATA_WIDTH_MB +: DATA_WIDTH_MB].
    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i = i + 1) begin : g_lane
            assign mb_rx_lane[i*DATA_WIDTH_MB +: DATA_WIDTH_MB] =
                corrupt[i] ? {DATA_WIDTH_MB{1'b0}} :
                (reverse
                    ? mb_tx_lane[(NUM_LANES-1-i)*DATA_WIDTH_MB +: DATA_WIDTH_MB]
                    : mb_tx_lane[i*DATA_WIDTH_MB +: DATA_WIDTH_MB]);
        end
    endgenerate

    // MainBand word/valid/clock fold
    assign mb_rx_data_valid       = mb_tx_ser_en;
    assign mb_rx_valid_frame_vld  = mb_tx_valid_ser_en ^ vld_err;
    assign mb_rx_valid_frame_data = mb_tx_valid_word;
    assign mb_rx_ckp              = mb_tx_ckp;
    assign mb_rx_ckn              = mb_tx_ckn;
    assign mb_rx_trk              = mb_tx_trk;

    // SideBand fold (block_sideband cuts it)
    assign sb_rx_data = block_sideband ? 64'b0 : sb_tx_data;
    assign sb_rx_vld  = block_sideband ? 1'b0  : sb_tx_vld;

endmodule
