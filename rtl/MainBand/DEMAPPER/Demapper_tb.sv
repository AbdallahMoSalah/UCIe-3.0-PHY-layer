module Demapper_tb;

    //============================================================
    // Parameters (same as DUT)
    //============================================================
    localparam N_BYTES   = 64;
    localparam WIDTH     = 32;
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;

    //============================================================
    // DUT Signals
    //============================================================
    logic i_clk;
    logic i_rst_n;
    logic demapper_en;
    logic [2:0] i_width_deg_demap;

    logic [WIDTH-1:0] i_lane [0:15];

    wire pl_valid;
    wire [8*N_BYTES-1:0] o_out_data;

    //============================================================
    // Clock Generation (100 MHz)
    //============================================================
    initial i_clk = 0;
    always #5 i_clk = ~i_clk;

    //============================================================
    // DUT Instantiation
    //============================================================
    Demapper #(
        .N_BYTES(N_BYTES),
        .WIDTH(WIDTH)
    ) dut (

        .i_clk(i_clk),
        .i_rst_n(i_rst_n),

        .i_lane_0 (i_lane[0]),
        .i_lane_1 (i_lane[1]),
        .i_lane_2 (i_lane[2]),
        .i_lane_3 (i_lane[3]),
        .i_lane_4 (i_lane[4]),
        .i_lane_5 (i_lane[5]),
        .i_lane_6 (i_lane[6]),
        .i_lane_7 (i_lane[7]),
        .i_lane_8 (i_lane[8]),
        .i_lane_9 (i_lane[9]),
        .i_lane_10(i_lane[10]),
        .i_lane_11(i_lane[11]),
        .i_lane_12(i_lane[12]),
        .i_lane_13(i_lane[13]),
        .i_lane_14(i_lane[14]),
        .i_lane_15(i_lane[15]),

        .demapper_en(demapper_en),
        .i_width_deg_demap(i_width_deg_demap),

        .pl_valid(pl_valid),
        .o_out_data(o_out_data)
    );
initial begin
i_rst_n=0;
@(negedge i_clk);
i_rst_n=1;demapper_en=1;i_width_deg_demap=DEGRADE_LANES_0_TO_15;
i_lane[0]=32'b11111111111111111111111111111111;
i_lane[1]=32'b11111111111111111111111111111111;
i_lane[2]=32'b11111111111111111111111111111111;
i_lane[3]=32'b11111111111111111111111111111111;
i_lane[4]=32'b11111111111111111111111111111111;
i_lane[5]=32'b11111111111111111111111111111111;
i_lane[6]=32'b11111111111111111111111111111111;
i_lane[7]=32'b11111111111111111111111111111111;
i_lane[8]=32'b11111111111111111111111111111111;
i_lane[9]=32'b11111111111111111111111111111111;
i_lane[10]=32'b11111111111111111111111111111111;
i_lane[11]=32'b11111111111111111111111111111111;
i_lane[12]=32'b11111111111111111111111111111111;
i_lane[13]=32'b11111111111111111111111111111111;
i_lane[14]=32'b11111111111111111111111111111111;
i_lane[15]=32'b11111111111111111111111111111111;

@(negedge i_clk);
$display("16x out=%0b,valid=%0b",o_out_data,pl_valid);
@(negedge i_clk);
i_rst_n=0;
@(negedge i_clk);
i_rst_n=1;demapper_en=1;i_width_deg_demap=DEGRADE_LANES_0_TO_7;
i_lane[0]=32'd0;
i_lane[1]=32'd0;
i_lane[2]=32'd0;
i_lane[3]=32'd0;
i_lane[4]=32'd0;
i_lane[5]=32'd0;
i_lane[6]=32'd0;
i_lane[7]=32'd0;
@(negedge i_clk);
i_lane[0]=32'd0;
i_lane[1]=32'd0;
i_lane[2]=32'd0;
i_lane[3]=32'd0;
i_lane[4]=32'd0;
i_lane[5]=32'd0;
i_lane[6]=32'd0;
i_lane[7]=32'd0;
@(negedge i_clk);
$display("8x_0->7 out=%0b,valid=%0b",o_out_data,pl_valid);

@(negedge i_clk);
i_rst_n=0;
@(negedge i_clk);
i_rst_n=1;demapper_en=1;i_width_deg_demap=DEGRADE_LANES_8_TO_15;
i_lane[8]=32'haaaaaaaa;
i_lane[9]=32'haaaaaaaa;
i_lane[10]=32'haaaaaaaa;
i_lane[11]=32'haaaaaaaa;
i_lane[12]=32'haaaaaaaa;
i_lane[13]=32'haaaaaaaa;
i_lane[14]=32'haaaaaaaa;
i_lane[15]=32'haaaaaaaa;
@(negedge i_clk);
i_lane[8]=32'hbbbbbbbb;
i_lane[9]=32'hbbbbbbbb;
i_lane[10]=32'hbbbbbbbb;
i_lane[11]=32'hbbbbbbbb;
i_lane[12]=32'hbbbbbbbb;
i_lane[13]=32'hbbbbbbbb;
i_lane[14]=32'hbbbbbbbb;
i_lane[15]=32'hbbbbbbbb;
@(negedge i_clk);
$display("8x_8->15 out=%0h,valid=%0b",o_out_data,pl_valid);
i_rst_n=1;demapper_en=1;i_width_deg_demap=DEGRADE_LANES_8_TO_15;
i_lane[8]=32'haaaaaaaa;
i_lane[9]=32'haaaaaaaa;
i_lane[10]=32'haaaaaaaa;
i_lane[11]=32'haaaaaaaa;
i_lane[12]=32'haaaaaaaa;
i_lane[13]=32'haaaaaaaa;
i_lane[14]=32'haaaaaaaa;
i_lane[15]=32'haaaaaaaa;
@(negedge i_clk);
i_lane[8]=32'hbbbbbbbb;
i_lane[9]=32'hbbbbbbbb;
i_lane[10]=32'hbbbbbbbb;
i_lane[11]=32'hbbbbbbbb;
i_lane[12]=32'hbbbbbbbb;
i_lane[13]=32'hbbbbbbbb;
i_lane[14]=32'hbbbbbbbb;
i_lane[15]=32'hbbbbbbbb;
@(negedge i_clk);
$display("8x_8->15 out=%0h,valid=%0b",o_out_data,pl_valid);
@(negedge i_clk);
i_rst_n=0;
@(negedge i_clk);
i_rst_n=1;demapper_en=1;i_width_deg_demap=DEGRADE_LANES_0_TO_3;
i_lane[0]=32'h9A9A9A9A;
i_lane[1]=32'h9A9A9A9A;
i_lane[2]=32'h9A9A9A9A;
i_lane[3]=32'h9A9A9A9A;
@(negedge i_clk);
i_lane[0]=32'hBCBCBCBC;
i_lane[1]=32'hBCBCBCBC;
i_lane[2]=32'hBCBCBCBC;
i_lane[3]=32'hBCBCBCBC;
@(negedge i_clk);
i_lane[0]=32'hDEDEDEDE;
i_lane[1]=32'hDEDEDEDE;
i_lane[2]=32'hDEDEDEDE;
i_lane[3]=32'hDEDEDEDE;
@(negedge i_clk);
i_lane[0]=32'hF1F1F1F1;
i_lane[1]=32'hF1F1F1F1;
i_lane[2]=32'hF1F1F1F1;
i_lane[3]=32'hF1F1F1F1;
@(negedge i_clk);
$display("4x_0->3 out=%0h,valid=%0b",o_out_data,pl_valid);
i_lane[0]=32'h98989898;
i_lane[1]=32'h98989898;
i_lane[2]=32'h98989898;
i_lane[3]=32'h98989898;
@(negedge i_clk);
i_lane[0]=32'hBABABABA;
i_lane[1]=32'hBABABABA;
i_lane[2]=32'hBABABABA;
i_lane[3]=32'hBABABABA;
@(negedge i_clk);
i_lane[0]=32'hDCDCDCDC;
i_lane[1]=32'hDCDCDCDC;
i_lane[2]=32'hDCDCDCDC;
i_lane[3]=32'hDCDCDCDC;
@(negedge i_clk);
i_lane[0]=32'hF2F2F2F2;
i_lane[1]=32'hF2F2F2F2;
i_lane[2]=32'hF2F2F2F2;
i_lane[3]=32'hF2F2F2F2;
@(negedge i_clk);
$display("4x_0->3 out=%0h,valid=%0b",o_out_data,pl_valid);
@(negedge i_clk);
$stop;

end

endmodule