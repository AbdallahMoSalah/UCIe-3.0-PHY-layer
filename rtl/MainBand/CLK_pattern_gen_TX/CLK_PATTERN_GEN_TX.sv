`timescale 1ps/1ps
// =============================================================================
// Module  : CLK_PATTERN_GEN_TX
// Project : UCIe 3.0 Main-Band Physical Layer
// Purpose : Transmit the UCIe clock-training pattern on the differential
//           clock lane pair.
//
// Pattern structure (per UCIe MBINIT spec):
//   Repeat MAIN=128 times:
//     • TOGGLE=32 clock cycles: o_clk_p = i_clk  (live toggle)
//     • ZERO=16   clock cycles: o_clk_p = 0       (forced low)
//   Total = 128 × 48 = 6144 PLL_clk edges
//
// Embedded-clock mode (clk_embedded_en):
//   o_clk_p = i_clk continuously (pass-through, no patterning).
//
// o_clk_n is always a half-period delayed version of o_clk_p.
//
// FIX (vs original): counters are now fully sequential (always_ff),
//   removing the combinational self-update loop that caused simulation
//   hangs.
// =============================================================================

module CLK_PATTERN_GEN_TX (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic clk_pattern_en,
    input  logic clk_embedded_en,
    input  real  i_period,          // i_clk period in ps (from MB_PLL)

    output logic o_clk_p,
    output logic o_clk_n,
    output logic track,
    output logic o_done
);
    // =========================================================================
    // Pattern constants
    // =========================================================================
    localparam bit [7:0] MAIN   = 128;   // outer burst count
    localparam bit [5:0] TOGGLE = 32;    // live-clock cycles per burst
    localparam bit [5:0] ZERO   = 16;    // forced-low cycles per burst

    // =========================================================================
    // Half-period differential output  (o_clk_n = o_clk_p delayed by T/2)
    // =========================================================================
    phase_delay pd (
        .i_half_period  (i_period / 2.0),
        .in_signal      (o_clk_p),
        .delayed_signal (o_clk_n)
    );

    initial begin
        $display("[DEBUG GEN INITIAL] THIS IS THE ACTIVE CLK_PATTERN_GEN_TX MODIFIED BY AG");
    end

    // =========================================================================
    // Sequential counters (posedge i_clk domain)
    // =========================================================================
    //   phase_cnt : 0 .. TOGGLE+ZERO-1 (= 47) within one burst
    //   burst_cnt : 0 .. MAIN           (128 = done)
    // =========================================================================
    logic [5:0] phase_cnt;  // 6-bit: 0..47
    logic [7:0] burst_cnt;  // 8-bit: 0..128

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            phase_cnt <= '0;
            burst_cnt <= '0;
        end else if (!clk_pattern_en) begin
            // Held in reset when pattern is disabled
            phase_cnt <= '0;
            burst_cnt <= '0;
        end else if (burst_cnt < MAIN) begin
            if (phase_cnt == 0) begin
                $display("[DEBUG GEN] posedge: clk_pattern_en=%b, phase_cnt=%0d, burst_cnt=%0d at t=%0t", clk_pattern_en, phase_cnt, burst_cnt, $time);
            end
            if (phase_cnt == (TOGGLE + ZERO - 1)) begin
                phase_cnt <= '0;
                burst_cnt <= burst_cnt + 1;
            end else begin
                phase_cnt <= phase_cnt + 1;
            end
        end
        // else: burst_cnt == MAIN → stay, o_done stays asserted
    end

    // =========================================================================
    // Combinational output MUX
    // =========================================================================
    assign o_done  = clk_pattern_en && (burst_cnt >= MAIN);
    assign o_clk_p = clk_pattern_en ? ((burst_cnt < MAIN && phase_cnt < TOGGLE) ? i_clk : 1'b0) :
                     (clk_embedded_en ? i_clk : 1'b0);
    assign track   = clk_pattern_en ? ((burst_cnt < MAIN && phase_cnt < TOGGLE) ? i_clk : 1'b0) :
                     (clk_embedded_en ? i_clk : 1'b0);

endmodule


// =============================================================================
// Sub-module : phase_delay
// Purpose    : Simulate a fixed delay on one signal edge (for differential pair)
// =============================================================================
module phase_delay (
    input  real  i_half_period,
    input  logic in_signal,
    output logic delayed_signal
);
    always @(in_signal) begin
        delayed_signal <= #(i_half_period) in_signal;
    end
endmodule