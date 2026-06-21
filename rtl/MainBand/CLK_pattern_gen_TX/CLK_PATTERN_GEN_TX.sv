`timescale 1ps/1ps

module CLK_PATTERN_GEN_TX (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic clk_pattern_en,
    input  logic clk_embedded_en,
    output logic o_clk_p,
    output logic o_clk_n,
    output logic track,
    output logic o_done,
    input  real  i_period
);
    parameter MAIN   = 64;
    parameter TOGGLE = 32;
    parameter ZERO   = 16;

    logic [7:0] counter_main;
    logic [6:0] counter_toggle;
    logic [4:0] counter_zero;

    typedef enum logic [1:0] {
        ST_IDLE_GEN,
        ST_TOGGLE_GEN,
        ST_ZERO_GEN,
        ST_DONE_GEN
    } state_t;

    state_t state;

    phase_delay pd (
        .i_half_period(i_period / 2.0),
        .in_signal(o_clk_p),
        .delayed_signal(o_clk_n)
    );

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state          <= ST_IDLE_GEN;
            counter_toggle <= 0;
            counter_zero   <= 0;
            counter_main   <= 0;
        end else begin
            if (clk_embedded_en) begin
                state          <= ST_IDLE_GEN;
                counter_toggle <= 0;
                counter_zero   <= 0;
                counter_main   <= 0;
            end else if (clk_pattern_en) begin
                case (state)
                    ST_IDLE_GEN: begin
                        state          <= ST_TOGGLE_GEN;
                        counter_toggle <= 0;
                        counter_zero   <= 0;
                        counter_main   <= 0;
                    end

                    ST_TOGGLE_GEN: begin
                        if (counter_toggle == TOGGLE - 1) begin
                            counter_toggle <= 0;
                            state          <= ST_ZERO_GEN;
                        end else begin
                            counter_toggle <= counter_toggle + 1'b1;
                        end
                    end

                    ST_ZERO_GEN: begin
                        if (counter_zero == ZERO - 1) begin
                            counter_zero <= 0;
                            if (counter_main == MAIN - 1) begin
                                state <= ST_DONE_GEN;
                            end else begin
                                counter_main <= counter_main + 1'b1;
                                state        <= ST_TOGGLE_GEN;
                            end
                        end else begin
                            counter_zero <= counter_zero + 1'b1;
                        end
                    end

                    ST_DONE_GEN: begin
                        // Stay in done state until clk_pattern_en is deasserted
                    end
                endcase
            end else begin
                state          <= ST_IDLE_GEN;
                counter_toggle <= 0;
                counter_zero   <= 0;
                counter_main   <= 0;
            end
        end
    end

    always_comb begin
        if (clk_embedded_en) begin
            o_clk_p = i_clk;
            track   = i_clk;
            o_done  = 1'b0;
        end else if (clk_pattern_en) begin
            case (state)
                ST_TOGGLE_GEN: begin
                    o_clk_p = i_clk;
                    track   = i_clk;
                    o_done  = 1'b0;
                end
                ST_ZERO_GEN: begin
                    o_clk_p = 1'b0;
                    track   = 1'b0;
                    o_done  = 1'b0;
                end
                ST_DONE_GEN: begin
                    o_clk_p = 1'b0;
                    track   = 1'b0;
                    o_done  = 1'b1;
                end
                default: begin
                    o_clk_p = 1'b0;
                    track   = 1'b0;
                    o_done  = 1'b0;
                end
            endcase
        end else begin
            o_clk_p = 1'b0;
            track   = 1'b0;
            o_done  = 1'b0;
        end
    end

endmodule

module phase_delay (
    input real   i_half_period,
    input logic  in_signal,
    output logic delayed_signal
);
    always @(in_signal) begin
        delayed_signal <= #(i_half_period) in_signal;
    end
endmodule