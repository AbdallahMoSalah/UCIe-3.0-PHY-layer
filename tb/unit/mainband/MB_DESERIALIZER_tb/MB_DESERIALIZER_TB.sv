`timescale 1ns/1ps

module MB_DESERIALIZER_TB;

/* ---------------- Signals ---------------- */
reg MB_clk;
reg pll_clk;
reg i_ckp;
reg i_ckn;
reg i_rst_n;
reg ser_valid;
reg ser_data_in;

wire [31:0] par_data_out;
wire        de_ser_done;

/* ---------------- DUT ---------------- */
MB_DESERIALIZER DUT (
    .MB_clk(MB_clk),
    .pll_clk(pll_clk),
    .i_ckp(i_ckp),
    .i_ckn(i_ckn),
    .i_rst_n(i_rst_n),
    .ser_valid(ser_valid),
    .ser_data_in(ser_data_in),
    .par_data_out(par_data_out),
    .de_ser_done(de_ser_done)
);

/* ---------------- Clock Generation ---------------- */
always #5  MB_clk  = ~MB_clk;   // 100 MHz
always #7  pll_clk = ~pll_clk;
always #3  i_ckp   = ~i_ckp;
always #3  i_ckn   = ~i_ckn;

/* ---------------- Stimulus ---------------- */
integer i;
reg [31:0] test_data = 32'hA5A5F0F0;

initial begin
    // init
    MB_clk = 0;
    pll_clk = 0;
    i_ckp = 0;
    i_ckn = 1;
    i_rst_n = 0;
    ser_valid = 0;
    ser_data_in = 0;

    // reset
    #20;
    i_rst_n = 1;

    // send serial data (MSB first)
    for (i = 31; i >= 0; i = i - 1) begin
        ser_data_in = test_data[i];
        #6; // aligned with i_ckp تقريبًا
    end

    // trigger save
    #10;
    ser_valid = 1;
    #10;
    ser_valid = 0;

    // wait result
    #50;

    $display("Expected = %h", test_data);
    $display("Output   = %h", par_data_out);

    if (par_data_out == test_data)
        $display("PASS ✅");
    else
        $display("FAIL ❌");

    #20;
    $stop;
end

endmodule