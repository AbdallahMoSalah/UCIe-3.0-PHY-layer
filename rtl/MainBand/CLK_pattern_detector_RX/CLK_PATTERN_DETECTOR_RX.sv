`timescale 1ps/1ps

module CLK_PATTERN_DETECTOR_RX (
    input  logic i_clk,              // pll_clk of the local (RX-side) die
    input  logic i_rst_n,
    input  logic clk_detector_en,
    input  logic clk_p,
    input  logic clk_n,
    input  logic track,
    output logic clk_p_pattern_pass,
    output logic clk_n_pattern_pass,
    output logic track_pattern_pass
);

    // Negedge latches
    logic p_neg, n_neg, t_neg;
    always_ff @(negedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            p_neg <= 1'b0;
            n_neg <= 1'b0;
            t_neg <= 1'b0;
        end else begin
            p_neg <= clk_p;
            n_neg <= clk_n;
            t_neg <= track;
        end
    end

    // Activity flags evaluated at posedge
    wire p_act = clk_p ^ p_neg;
    wire n_act = clk_n ^ n_neg;
    wire t_act = track ^ t_neg;

    // Counters
    logic [9:0] cnt_p, cnt_n, cnt_t;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n || !clk_detector_en) begin
            cnt_p              <= '0;
            cnt_n              <= '0;
            cnt_t              <= '0;
            clk_p_pattern_pass <= 1'b0;
            clk_n_pattern_pass <= 1'b0;
            track_pattern_pass <= 1'b0;
        end else begin
            // clk_p
            if (p_act) begin
                if (cnt_p >= 10'd500) begin
                    clk_p_pattern_pass <= 1'b1;
                end else begin
                    cnt_p <= cnt_p + 1'b1;
                end
            end
            
            // clk_n
            if (n_act) begin
                if (cnt_n >= 10'd500) begin
                    clk_n_pattern_pass <= 1'b1;
                end else begin
                    cnt_n <= cnt_n + 1'b1;
                end
            end

            // track
            if (t_act) begin
                if (cnt_t >= 10'd500) begin
                    track_pattern_pass <= 1'b1;
                end else begin
                    cnt_t <= cnt_t + 1'b1;
                end
            end
        end
    end

endmodule