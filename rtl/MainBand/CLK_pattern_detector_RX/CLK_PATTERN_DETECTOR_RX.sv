module CLK_PATTERN_DETECTOR_RX(
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic clk_detector_en,

    input  logic clk_p,
    input  logic clk_n,
    input  logic track,

    output logic clk_check_done,
    output logic clk_pattern_error
);

parameter MAIN   = 128;
parameter TOGGLE = 16;
parameter ZERO   = 8;

logic [4:0] counter_toggle;
logic [3:0] counter_zero;
logic [7:0] counter_main;

logic clk_p_d;

always @(posedge i_clk , negedge i_rst_n ) begin

    if (!i_rst_n) begin
        counter_toggle    <= 0;
        counter_zero      <= 0;
        counter_main      <= 0;
        clk_check_done    <= 0;
        clk_pattern_error <= 0;
        clk_p_d           <= 0;
    end

    else begin

        clk_p_d <= i_clk;

        if (!clk_detector_en) begin
            counter_toggle   <= 0;
            counter_zero     <= 0;
            counter_main     <= 0;
            clk_check_done   <= 0;
            clk_pattern_error<= 0;
        end

        else begin

            // -------- Toggle Phase --------
            if (counter_toggle < TOGGLE) begin

                if ((clk_p == clk_p_d) && (clk_n == ~clk_p_d) && (track == clk_p_d)) begin
                    counter_toggle <= counter_toggle + 1;
                end
                else begin
                    clk_pattern_error <= 1;
                end

            end

            // -------- Zero Phase --------
            else if (counter_zero < ZERO) begin

                if (clk_p == 0 && clk_n == 0 && track == 0) begin
                    counter_zero <= counter_zero + 1;
                end
                else begin
                    clk_pattern_error <= 1;
                end

            end

            // -------- Next Pattern --------
            else begin
                counter_toggle <= 0;
                counter_zero   <= 0;
                counter_main   <= counter_main + 1;
            end

            // -------- Done --------
            if (counter_main == MAIN-1) begin
                clk_check_done <= 1;
            end

        end
    end
end

endmodule