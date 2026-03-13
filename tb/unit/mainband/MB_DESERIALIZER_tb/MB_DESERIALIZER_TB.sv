`timescale 1ns/1ps

module MB_DESERIALIZER_TB;

reg        i_clk;
reg        i_rst_n;
reg        in_des_data;
wire [31:0] deser_data_out;

integer i;
reg [31:0] test_data;

MB_DESERIALIZER DUT (
    .i_clk          (i_clk),
    .i_rst_n        (i_rst_n),
    .in_des_data    (in_des_data),
    .deser_data_out (deser_data_out)
);
initial begin
    $monitor("TIME=%0t | in_bit=%b | deser_out=%h",
              $time, in_des_data, deser_data_out);
end
initial i_clk = 0;
always #5 i_clk = ~i_clk;

initial begin
    $display("===== DESERIALIZER TEST START =====");

    i_rst_n     = 0;
    in_des_data = 0;
    test_data   = 32'hA5F00F3C;
    repeat(4) @(posedge i_clk);
    i_rst_n = 1;

    $display("Sending Data = %h", test_data);

    for (i = 0; i < 32; i = i + 1) begin
        in_des_data = test_data[i];
        @(posedge i_clk);
    end

    repeat(2) @(posedge i_clk);

    $display("Received = %h", deser_data_out);

    if (deser_data_out == test_data)
        $display("PASS: Data Correct");
    else
        $display("FAIL: Expected %h | Got %h", test_data, deser_data_out);

    $display("===== TEST FINISHED =====");
    #20;
    $stop;
end

endmodule