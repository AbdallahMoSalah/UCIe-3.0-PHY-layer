`timescale 1ns/1ps
// =============================================================================
// Module  : VALID_RX_WRAPPER
// Description:
//   Wrapper يضم:
//     • MB_DESERIALIZER_VALID  (unit_valid_deserializer.sv)
//       → يحوّل الـ serial bit-stream الخاص بـ valid lane إلى كلمة 32-bit.
//       → يولّد enable_des_valid_frame=1 لما الـ frame = 0x0F0F0F0F.
//
//     • VALID_DETECTOR  (Valid_RX.sv)  [= LFSR_RX بالـ naming الخاص بالمشروع]
//       → يستقبل الـ par_data_out (= RVLD_L) ويقرر هل الـ pattern صح أو لا.
//       → يشتغل بثلاث modes: IDLE / ITER_128 / CONSEC_16.
//
//   Data Flow:
//     ser_data_in (DDR 1-bit)
//       ──► MB_DESERIALIZER_VALID ──► par_data_out (32-bit, MB_clk)
//                                 ──► enable_des_valid_frame
//                                 ──► de_ser_done
//       ──► VALID_DETECTOR        ──► detection_result
//                                 ──► o_valid_frame_detect
//
//   Clock Domains:
//     pll_clk  : يشغّل الـ deserializer (edge-detect FSM + shift register)
//     MB_clk   : يشغّل الـ CDC sync FFs + output regs + VALID_DETECTOR
// =============================================================================

module VALID_RX_WRAPPER #(
    parameter DATA_WIDTH = 32
)(
    // ── Clocks & Reset ────────────────────────────────────────────────────────
    input  wire                   MB_clk,            // Main-Band clock  (slow)
    input  wire                   pll_clk,           // PLL clock (fast, DDR)
    input  wire                   i_rst_n,           // Active-low async reset

    // ── Serial Input ─────────────────────────────────────────────────────────
    input  wire                   ser_data_in,       // Valid-lane serial stream (1-bit DDR)

    // ── VALID_DETECTOR Control ────────────────────────────────────────────────
    input  wire [11:0]            i_max_error_threshold, // Threshold for ITER_128 mode
    input  wire                   i_enable_cons,     // 1 → CONSEC_16 mode
    input  wire                   i_enable_128,      // 1 → ITER_128 mode
    input  wire                   i_enable_detector, // Master enable for VALID_DETECTOR

    // ── Deserialized Outputs (MB_clk domain) ─────────────────────────────────
    output wire [DATA_WIDTH-1:0]  par_data_out,          // Latest 32-bit deserialized word
    output wire                   de_ser_done,           // 1-cycle pulse per received word
    output wire                   enable_des_valid_frame, // 1 when last frame == 0x0F0F0F0F

    // ── Detector Outputs (MB_clk domain) ─────────────────────────────────────
    output wire                   detection_result,      // 1 = pattern NOT detected (error)
    output wire                   o_valid_frame_detect   // 1 when RVLD_L != VALID_PATTERN
);

    // =========================================================================
    // Internal wire: 32-bit parallel word  deserializer ──► detector
    // =========================================================================
    logic [DATA_WIDTH-1:0] w_par_data;

    // =========================================================================
    // Instance 1: MB_DESERIALIZER_VALID   (unit_valid_deserializer.sv)
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

    // Expose the parallel word at the wrapper boundary as well
    assign par_data_out = w_par_data;

    // =========================================================================
    // Instance 2: VALID_DETECTOR  (Valid_RX.sv)
    //   Runs entirely in MB_clk domain.
    //   Receives w_par_data as RVLD_L every clock cycle.
    // =========================================================================
    VALID_DETECTOR u_valid_detector (
        .i_clk                  (MB_clk),           // Detector on MB_clk
        .i_rst_n                (i_rst_n),
        .RVLD_L                 (w_par_data),        // Feed deserialized word
        .i_max_error_threshold  (i_max_error_threshold),
        .i_enable_cons          (i_enable_cons),
        .i_enable_128           (i_enable_128),
        .i_enable_detector      (i_enable_detector),
        .detection_result       (detection_result),
        .o_valid_frame_detect   (o_valid_frame_detect)
    );

endmodule
