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

    // -------------------------------------------------------------------------
    // o_clk_n is the differential complement of o_clk_p: o_clk_p phase-shifted
    // by half a UI.  The toggling clock equals i_clk, so a half-cycle shift is
    // simply the inverted clock (~i_clk); both lanes park at 0 during the zero
    // phase.  This is a synthesizable clock inversion and replaces the old
    //   assign #(local_period/2) o_clk_n = o_clk_p;
    // so the PLL period is no longer needed.
    // -------------------------------------------------------------------------
    always @(*) begin
        if (!i_rst_n) begin
            o_clk_p = 0;
            o_clk_n = 0;
            track = 0;
            counter_toggle = 0;
            counter_main = 0;
            counter_zero = 0;
            o_done = 0;
        end else begin
            if (clk_embedded_en) begin//strobe mode potential optmization
                o_clk_p = i_clk;
                o_clk_n = ~i_clk;
                track = i_clk;
            end else begin
                if (clk_pattern_en) begin
                    if (counter_main < MAIN) begin
                        if (counter_toggle < TOGGLE) begin
                            o_clk_p = i_clk;
                            o_clk_n = ~i_clk;
                            track = i_clk;
                            counter_toggle = counter_toggle + 1;
                        end else if (counter_toggle == TOGGLE && counter_zero < ZERO) begin
                            o_clk_p = 0;
                            o_clk_n = 0;
                            track = 0;
                            counter_zero = counter_zero + 1;
                            if (counter_zero == ZERO && counter_main < MAIN) begin
                                counter_toggle = 0;
                                counter_zero = 0;
                                counter_main = counter_main + 1;
                            end
                        end
                    end
                    if (counter_main == MAIN) begin
                        o_done = 1;
                    end
                end else begin
                    counter_main <= 0;
                    o_done <= 0;
                end
            end
        end
    end
endmodule
