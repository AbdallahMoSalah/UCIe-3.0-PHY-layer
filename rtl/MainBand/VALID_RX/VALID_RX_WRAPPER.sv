`timescale 1ns/1ps
// =============================================================================
// Module  : VALID_RX_WRAPPER
// Description:
//   Wrapper يضم MB_DESERIALIZER_VALID (unit_valid_deserializer) و
//   VALID_DETECTOR (هو الـ LFSR_RX حسب تسمية المشروع).
//
//   Data flow:
//     ser_data_in (1-bit serial, DDR)
//       → MB_DESERIALIZER_VALID
//           → par_data_out    (32-bit parallel, MB_clk domain)
//           → enable_des_valid_frame (= 1 when last frame == 0x0F0F0F0F)
//           → de_ser_done     (1-cycle pulse per new word)
//       → VALID_DETECTOR (uses par_data_out as RVLD_L)
//           → detection_result
//           → o_valid_frame_detect
//
//   Notes:
//     • MB_DESERIALIZER_VALID is free-running (no external enable).
//     • VALID_DETECTOR is gated by i_enable_detector, i_enable_cons,
//       i_enable_128, and i_max_error_threshold from outside.
// =============================================================================

module VALID_RX_WRAPPER #(
    parameter DATA_WIDTH = 32
)(
    // ── Clocks & Reset ────────────────────────────────────────────────────────
    input  wire                   MB_clk,           // Main-Band clock (slow)
    input  wire                   pll_clk,          // PLL clock (fast, DDR)
    input  wire                   i_rst_n,          // Active-low async reset

    // ── Serial Input ─────────────────────────────────────────────────────────
    input  wire                   ser_data_in,      // Valid-lane serial stream

    // ── VALID_DETECTOR Control ────────────────────────────────────────────────
    input  wire [11:0]            i_max_error_threshold,
    input  wire                   i_enable_cons,    // Enable CONSEC_16 mode
    input  wire                   i_enable_128,     // Enable ITER_128 mode
    input  wire                   i_enable_detector,// Master enable for detector

    // ── Deserialized Data Output (MB_clk domain) ──────────────────────────────
    output wire [DATA_WIDTH-1:0]  par_data_out,     // Latest 32-bit word
    output wire                   de_ser_done,      // 1-cycle pulse per word
    output wire                   enable_des_valid_frame, // 1 if last frame == 0x0F0F0F0F

    // ── Detector Outputs (MB_clk domain) ─────────────────────────────────────
    output wire                   detection_result,     // Pattern-detection verdict
    output wire                   o_valid_frame_detect  // 1 if RVLD_L != VALID_PATTERN
);

    // =========================================================================
    // Internal wire: 32-bit parallel word from deserializer → detector
    // =========================================================================
    wire [DATA_WIDTH-1:0] w_par_data;

    // =========================================================================
    // Instance 1: MB_DESERIALIZER_VALID  (unit_valid_deserializer)
    //   Deserializes the 1-bit DDR valid-lane stream into a 32-bit parallel
    //   word and produces enable_des_valid_frame when the word == 0x0F0F0F0F.
    // =========================================================================
    MB_DESERIALIZER_VALID #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_valid_des (
        .MB_clk                 (MB_clk),
        .pll_clk                (pll_clk),
        .i_rst_n                (i_rst_n),
        .ser_data_in            (ser_data_in),
        .enable_des_valid_frame (enable_des_valid_frame),
        .par_data_out           (w_par_data),
        .de_ser_done            (de_ser_done)
    );

    assign par_data_out = w_par_data;

    // =========================================================================
    // Instance 2: VALID_DETECTOR
    //   Receives the deserialized 32-bit word and performs pattern detection
    //   in one of three modes: IDLE, ITER_128, CONSEC_16.
    //   Runs on MB_clk (same clock domain as deserializer outputs).
    // =========================================================================
    VALID_DETECTOR u_valid_detector (
        .i_clk                  (MB_clk),
        .i_rst_n                (i_rst_n),
        .RVLD_L                 (w_par_data),
        .i_max_error_threshold  (i_max_error_threshold),
        .i_enable_cons          (i_enable_cons),
        .i_enable_128           (i_enable_128),
        .i_enable_detector      (i_enable_detector),
        .detection_result       (detection_result),
        .o_valid_frame_detect   (o_valid_frame_detect)
    );

endmodule
