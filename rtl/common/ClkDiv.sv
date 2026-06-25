module ClkDiv  #(
parameter RangeWidth = 8
) (
    input i_ref_clk,
    input i_rst_n,
    input i_clk_en,
    input [RangeWidth-1:0] i_div_ratio,
    output o_div_clk
);
    wire [7:0]half_tog,half_tog_p1;
    reg [7:0] cur_ratio;
    wire Clk_Div_EN,odd;
    reg div_clk;
    reg [7:0] cnt;
    reg tog_flag;
    ////high and low level calculation
    assign half_tog = (i_div_ratio >> 1 )-1;
    assign half_tog_p1 = half_tog + 1'b1;


    assign Clk_Div_EN = ((i_div_ratio > 8'd1) && (i_clk_en==1)) ? 1'b1 : 1'b0;
    assign odd = i_div_ratio[0];
    assign o_div_clk = (Clk_Div_EN) ? div_clk : i_ref_clk;

    always @(posedge i_ref_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cnt <= '0;
            tog_flag <= 1'b0;
            div_clk <= 1'b1;
            cur_ratio <= 8'd0;
        end else if (Clk_Div_EN) begin
            if (!odd && (cnt == half_tog)) begin
                div_clk <= ~o_div_clk;
                cnt <= '0;
            end else if ( odd && ( ((cnt == half_tog) && tog_flag)|| ((cnt ==half_tog_p1) && !tog_flag) ) ) begin
                div_clk <= ~o_div_clk;
                cnt <= '0;
                tog_flag <= ~tog_flag;
            end else begin
                cnt <= cnt + 8'd1;
            end
            end
    end
endmodule
