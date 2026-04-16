`timescale 1ns/1ps

module MB_DESERIALIZER_TB;

parameter DATA_WIDTH = 32;

/* ---------------- Signals ---------------- */
reg MB_clk;
reg pll_clk;
reg i_ckp;
reg i_ckn;
reg i_rst_n;
reg ser_valid;
reg ser_data_in;

wire [DATA_WIDTH-1:0] par_data_out;
wire        de_ser_done;

/* ---------------- DUT ---------------- */
MB_DESERIALIZER #(
    .DATA_WIDTH(DATA_WIDTH)
) DUT (
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
initial begin
    MB_clk = 0;
    forever #8 MB_clk = ~MB_clk; // 16ns period
end

initial begin
    pll_clk = 0;
    forever #0.25 pll_clk = ~pll_clk; // 0.5ns period (2GHz)
end

// maintain i_ckp for compilation backwards compatibility
initial begin
    i_ckp = 0;
    forever #3 i_ckp = ~i_ckp;
end


/* ---------------- Stimulus ---------------- */
integer i;
reg [DATA_WIDTH-1:0] test_data = 32'hA5A5F0F0;

initial begin
    // init
    i_ckn = 1;
    i_rst_n = 0;
    ser_valid = 0;
    ser_data_in = 0;

    // reset
    #50;
    i_rst_n = 1;

    // Align with MB_clk
    @(posedge MB_clk);
    
    // Shift data generation by 90 degrees to satisfy setup/hold
    #0.5;

    // send serial data (LSB first to match standard)
    for (i = 0; i < DATA_WIDTH; i = i + 1) begin
        ser_data_in = test_data[i];
        #0.25; // Duration of DDR bit (half period of pll_clk)
    end

    // The shift register now holds the 32 bits
    // trigger save (in reality, PHY would assert ser_valid)
    ser_valid = 1;
    #2; // hold for 1 PLL_clk cycle
    ser_valid = 0;

    // wait for result on MB_clk
    @(posedge de_ser_done);
    @(posedge MB_clk);

    $display("Expected = %h", test_data);
    $display("Output   = %h", par_data_out);

    if (par_data_out === test_data)
        $display("PASS ✅");
    else
        $display("FAIL ❌");

    #20;
    $stop;
end

endmodule