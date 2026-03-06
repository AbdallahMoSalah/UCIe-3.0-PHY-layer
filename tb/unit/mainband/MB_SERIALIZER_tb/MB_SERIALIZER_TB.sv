`timescale 1ns/1ps

module MB_SERIALIZER_TB;

parameter DATA_WIDTH = 32;

reg i_clk;
reg i_rst_n;
reg Ser_en;
reg [DATA_WIDTH-1:0] in_data;

wire SER_out;

integer i;

// DUT
MB_SERIALIZER #(
    .DATA_WIDTH(DATA_WIDTH)
) DUT (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .Ser_en(Ser_en),
    .in_data(in_data),
    .SER_out(SER_out)
);

//////////////////////
// CLOCK
//////////////////////
initial begin
    i_clk = 0;
    forever #5 i_clk = ~i_clk;
end

//////////////////////
// TEST
//////////////////////
initial begin

    $display("===== SERIALIZER TEST START =====");

    i_rst_n = 0;
    Ser_en  = 0;
    in_data = 0;

    #20;
    i_rst_n = 1;

    // test pattern
    in_data = 32'hA5A5F0F0;

    // enable serializer
    @(posedge i_clk);
    Ser_en = 1;

    // print serialized bits
    for(i = 0; i < DATA_WIDTH; i = i + 1) begin
        @(posedge i_clk);
        #1;
        $display("Bit %0d = %b", i, SER_out);
    end

    Ser_en = 0;

    #20;

    $display("===== TEST FINISHED =====");

    $stop;

end

endmodule