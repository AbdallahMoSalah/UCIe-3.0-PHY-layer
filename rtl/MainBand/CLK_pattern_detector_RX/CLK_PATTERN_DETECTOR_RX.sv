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

logic [4:0] counter_p;
logic [4:0] counter_n;
logic [3:0] counter_zero;
logic [7:0] counter_main;
logic [4:0] counter_16_consecetive;


always @(posedge clk_p , negedge i_rst_n ) begin
    if (!i_rst_n) begin
        counter_p    <= 0;
        counter_n      <= 0;
        counter_main      <= 0;
        counter_zero <= 0;
        counter_16_consecetive <= 0;
        clk_check_done    <= 0;
        clk_pattern_error <= 0;
    end
    else begin

        if (!clk_detector_en) begin
            counter_p   <= 0;
            counter_n     <= 0;
            counter_main     <= 0;
            counter_zero <= 0;
        counter_16_consecetive <= 0;
            clk_check_done   <= 0;
            clk_pattern_error<= 0;
        end

        else begin
     if (clk_p ^ clk_n == 1) begin
        counter_p <= counter_p + 1;
     end

        end
    end
end

always @(negedge clk_p , negedge i_rst_n ) begin
    if (!i_rst_n) begin
        counter_p    <= 0;
        counter_n      <= 0;
        counter_main      <= 0;
        counter_zero <= 0;
        counter_16_consecetive <= 0;
        clk_check_done    <= 0;
        clk_pattern_error <= 0;
    end
    else begin

        if (!clk_detector_en) begin
            counter_p   <= 0;
            counter_n     <= 0;
           counter_main     <= 0;
            counter_zero <= 0;
        counter_16_consecetive <= 0;
            clk_check_done   <= 0;
            clk_pattern_error<= 0;
        end

        else begin
     if (clk_p ^ clk_n == 1) begin
        counter_n <= counter_n + 1;
     end
        end
    end
end

always @(posedge i_clk , negedge i_rst_n ) begin
    if (!i_rst_n) begin
        counter_p    <= 0;
        counter_n      <= 0;
        counter_main      <= 0;
        counter_zero <= 0;
        counter_16_consecetive <= 0;
        clk_check_done    <= 0;
        clk_pattern_error <= 0;
    end
    else begin

        if (!clk_detector_en) begin
            counter_p   <= 0;
            counter_n     <= 0;
           counter_main     <= 0;
            counter_zero <= 0;
        counter_16_consecetive <= 0;
            clk_check_done   <= 0;
            clk_pattern_error<= 0;
        end

        else begin
     if (counter_p == TOGGLE && counter_n == TOGGLE) begin
        counter_zero <= counter_zero + 1; 
        if (counter_zero == ZERO) begin
            counter_p <= 0;
            counter_n <= 0;
            counter_zero <= 0;
            counter_main <= counter_main + 1;
            counter_16_consecetive <= counter_16_consecetive + 1;
        end
        if (counter_16_consecetive == 16) begin
            clk_check_done <= 1;
        end
        else begin
            if (counter_main == MAIN && counter_16_consecetive != 16) begin
                clk_pattern_error <= 1;
            end
        end
     end     
        end
    end 
end
endmodule