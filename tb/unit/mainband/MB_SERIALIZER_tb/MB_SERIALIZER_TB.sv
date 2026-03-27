`timescale 1ns/1ps

module MB_SERIALIZER_TB;

parameter DATA_WIDTH = 32;

reg i_clk;
reg PLL_clk;
reg i_rst_n;
reg Ser_en;
reg [DATA_WIDTH-1:0] in_data;

wire SER_out;

integer i;
reg [DATA_WIDTH-1:0] expected_data;

// DUT
MB_SERIALIZER #(
    .DATA_WIDTH(DATA_WIDTH)
) DUT (
    .mb_clk(i_clk),
    .PLL_clk(PLL_clk),
    .i_rst_n(i_rst_n),
    .Ser_en(Ser_en),
    .in_data(in_data),
    .SER_out(SER_out)
);

// CLOCKS
initial begin
    i_clk = 0;
    forever #5 i_clk = ~i_clk; // 10ns
end

initial begin
    PLL_clk = 0;
    forever #2.5 PLL_clk = ~PLL_clk; // 5ns
end

// TEST
initial begin
    $display("===== SERIALIZER TEST START =====");

    i_rst_n = 0;
    Ser_en  = 0;
    in_data = 0;
    #20;
    i_rst_n = 1;

    // LOAD TEST DATA
    in_data = 32'hA5A5F0F0;
    expected_data = in_data;

    // KEEP Ser_en HIGH for a few i_clk cycles
    @(posedge i_clk);
    Ser_en = 1;
    repeat (3) @(posedge i_clk);
    Ser_en = 0;

    // WAIT a few PLL_clk cycles
    repeat (5) @(posedge PLL_clk);

    // CHECK LSB FIRST
    for (i = 0; i < DATA_WIDTH; i = i + 1) begin
        @(posedge PLL_clk);
        #1;
        if (SER_out !== expected_data[0]) begin
            $display(" Bit %0d ERROR: expected=%b got=%b", i, expected_data[0], SER_out);
        end else begin
            $display(" Bit %0d correct: %b", i, SER_out);
        end
        expected_data = expected_data >> 1; // shift right LSB first
    end

    $display("===== TEST FINISHED =====");
    $stop;
end

endmodule