`timescale 1ps/1ps

module CLK_PATTERN_GEN_TX(i_clk,i_rst_n,clk_pattern_en,clk_embedded_en,o_clk_p,o_clk_n,track,o_done,i_period);
    parameter MAIN=128;
    parameter TOGGLE=32;
    parameter ZERO=16;

    input logic i_clk,i_rst_n,clk_pattern_en,clk_embedded_en;
    input real  i_period;           // i_clk period in ps (from MB_PLL)
    output logic o_clk_p,o_clk_n,track,o_done;
    logic [6:0]counter_toggle;
    logic [4:0]counter_zero;
    logic [7:0] counter_main;
// o_clk_n is o_clk_p delayed by half the i_clk period → true differential pair
phase_delay pd (.i_half_period(i_period / 2.0),.in_signal(o_clk_p),.delayed_signal(o_clk_n));

    always @(*) begin

        if (!i_rst_n) begin
            o_clk_p = 0;
            track = 0;
            counter_toggle = 0;
            counter_main = 0;
            counter_zero = 0;
            o_done = 0;
        end
        else begin
            if (clk_embedded_en) begin
                 if (counter_toggle < TOGGLE) begin
                    o_clk_p = i_clk;
                    track = i_clk;

                counter_toggle = counter_toggle +1; 
                end
                else if (counter_toggle == TOGGLE && counter_zero < ZERO) begin
                    o_clk_p = 0;
                    track = 0;

                    counter_zero = counter_zero + 1;
                    if (counter_zero == ZERO) begin
                        counter_toggle = 0;
                        counter_zero = 0;
                       
                    end
                end
                
            end else begin
                   if (clk_pattern_en ) begin
                    if (counter_main < MAIN) begin
                if (counter_toggle < TOGGLE) begin
                    o_clk_p = i_clk;
                    track = i_clk;

                counter_toggle = counter_toggle +1; 
                end
                else if (counter_toggle == TOGGLE && counter_zero < ZERO) begin
                    o_clk_p = 0;
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
                    
                end
            else begin
                counter_main <= 0;
                o_done <= 0;
            end 
                end
        end
    end
endmodule

module phase_delay(
    input real   i_half_period,
    input logic  in_signal,
    output logic delayed_signal
);
    // Non-blocking with variable delay: each edge of in_signal schedules
    // delayed_signal to update i_half_period ps later.
    always @(in_signal) begin
        delayed_signal <= #(i_half_period) in_signal;
    end
endmodule