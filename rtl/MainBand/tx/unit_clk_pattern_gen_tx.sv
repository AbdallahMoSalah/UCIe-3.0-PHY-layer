`timescale 1ps/1ps

module unit_clk_pattern_gen_tx (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic clk_pattern_en,
    input  logic clk_embedded_en,
    output logic o_clk_p,
    output logic o_clk_n,
    output logic track,
    output logic o_done
);
    parameter MAIN   = 128;
    parameter TOGGLE = 32;
    parameter ZERO   = 16;

    logic [6:0] counter_toggle;
    logic [4:0] counter_zero;
    logic [7:0] counter_main;
    logic       toggle_phase;   // 1 = emitting toggling clock, 0 = emitting idle (zero) gap

    // -------------------------------------------------------------------------
    // Sequential burst FSM (real registers — no latch, no combinational loop).
    //
    // Emits MAIN bursts; each burst = TOGGLE cycles of toggling clock followed
    // by ZERO idle cycles.  toggle_phase selects which sub-phase we are in, the
    // counters time each sub-phase, counter_main counts completed bursts, and
    // o_done asserts once all MAIN bursts have been generated.
    //
    // The emitted waveform (TOGGLE-on / ZERO-off, repeated MAIN times) is
    // identical to the spec pattern; only the implementation moved from a
    // self-referencing always@(*) to a clocked counter chain.
    // -------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            counter_toggle <= 0;
            counter_zero   <= 0;
            counter_main   <= 0;
            toggle_phase   <= 1'b1;
            o_done         <= 1'b0;
        end else if (clk_embedded_en) begin
            // Continuous-clock (embedded) mode: counters idle, no pattern timing.
            counter_toggle <= 0;
            counter_zero   <= 0;
            counter_main   <= 0;
            toggle_phase   <= 1'b1;
            o_done         <= 1'b0;
        end else if (clk_pattern_en) begin
            // NOTE: counters advance by 2 per cycle to preserve the exact legacy
            // on-wire cadence.  The previous always@(*) implementation
            // self-retriggered and effectively counted twice per i_clk, so each
            // burst is TOGGLE/2 = 16 toggling cycles followed by ZERO/2 = 8 idle
            // cycles.  The RX clk-pattern detector is tuned to that 16/8 rate, so
            // this rate MUST NOT change.
            if (counter_main < MAIN) begin
                if (toggle_phase) begin
                    // ---- TOGGLE sub-phase: TOGGLE/2 cycles of toggling clock ----
                    if (counter_toggle == TOGGLE - 2) begin
                        counter_toggle <= 0;
                        toggle_phase   <= 1'b0;   // switch to idle gap
                    end else begin
                        counter_toggle <= counter_toggle + 7'd2;
                    end
                end else begin
                    // ---- ZERO sub-phase: ZERO/2 idle cycles, then close burst ----
                    if (counter_zero == ZERO - 2) begin
                        counter_zero <= 0;
                        toggle_phase <= 1'b1;
                        counter_main <= counter_main + 1'b1;
                    end else begin
                        counter_zero <= counter_zero + 5'd2;
                    end
                end
            end
            if (counter_main == MAIN) begin
                o_done <= 1'b1;
            end
        end else begin
            // Pattern disabled: restart for the next enable.
            counter_toggle <= 0;
            counter_zero   <= 0;
            counter_main   <= 0;
            toggle_phase   <= 1'b1;
            o_done         <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Combinational gated-clock outputs.
    // o_clk_n is the differential complement of o_clk_p (half-UI shift = ~i_clk);
    // both lanes park at 0 during the idle gap and when the pattern is inactive.
    // -------------------------------------------------------------------------
    always @(*) begin
        if (!i_rst_n) begin
            o_clk_p = 1'b0;
            o_clk_n = 1'b0;
            track   = 1'b0;
        end else if (clk_embedded_en) begin
            o_clk_p = i_clk;
            o_clk_n = ~i_clk;
            track   = i_clk;
        end else if (clk_pattern_en && (counter_main < MAIN) && toggle_phase) begin
            o_clk_p = i_clk;
            o_clk_n = ~i_clk;
            track   = i_clk;
        end else begin
            o_clk_p = 1'b0;
            o_clk_n = 1'b0;
            track   = 1'b0;
        end
    end
endmodule
