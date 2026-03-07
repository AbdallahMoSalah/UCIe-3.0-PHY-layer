module CLK_PATTERN_GEN_TX(i_clk,i_rst_n,clk_pattern_en,o_clk_p,o_clk_n,track,o_done); 
    parameter MAIN=128;
    parameter TOGGLE=16;
    parameter ZERO=8;

    input logic i_clk,i_rst_n,clk_pattern_en;
    output logic o_clk_p,o_clk_n,track,o_done;
    logic [4:0]counter_toggle;
    logic [2:0]counter_zero;
    logic [6:0] counter_main;

    always @(*) begin
        if (!i_rst_n) begin
            o_clk_p = 0;
            o_clk_n = 1;
            track = 0;
            counter_toggle = 0;
            counter_main = 0;
            counter_zero = 0;
            o_done = 0;
        end
        else begin
            if (clk_pattern_en && counter_main < MAIN-1) begin
                if (counter_toggle < TOGGLE) begin
                    o_clk_p = i_clk;
                    track = i_clk;
                    o_clk_n = ~i_clk;
                counter_toggle = counter_toggle +1; 
                end
                else if (counter_toggle == TOGGLE && counter_zero < ZERO-1) begin
                    o_clk_p = 0;
                    track = 0;
                    o_clk_n = 0;
                    counter_zero = counter_zero + 1;
                end
                    else if (counter_zero == ZERO-1 && counter_main < MAIN-1) begin
                        counter_toggle = 0;
                        counter_zero = 0;
                        counter_main = counter_main + 1;
                    end
                        if (counter_main == MAIN-1) begin
                            o_done = 1;
                        end
                    end
            else begin
                o_clk_p = 0;
                o_clk_n = 0;
                track = 0;
            end
        end
    end
endmodule