`timescale 1ns/1ps

module sb_pattern_detector_tb;

logic clk;
logic rst_n;

logic pattern_mode;

logic [63:0] packet_data;
logic packet_done;

logic pattern_detected;

logic [63:0] data_out;
logic data_valid;

////////////////////////////////////////////////////////////
// Clock
////////////////////////////////////////////////////////////

initial clk = 0;
always #5 clk = ~clk;

////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////

sb_pattern_detector dut(
    .clk(clk),
    .rst_n(rst_n),
    .pattern_mode(pattern_mode),
    .packet_data(packet_data),
    .packet_done(packet_done),
    .pattern_detected(pattern_detected),
    .data_out(data_out),
    .data_valid(data_valid)
);

////////////////////////////////////////////////////////////
// Reset
////////////////////////////////////////////////////////////

initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
end

////////////////////////////////////////////////////////////
// Helper task
////////////////////////////////////////////////////////////

task send_packet(input logic [63:0] data);
begin
    @(negedge clk);
    packet_data = data;
    packet_done = 1;

    @(negedge clk);
    packet_done = 0;
end
endtask

////////////////////////////////////////////////////////////
// Test sequence
////////////////////////////////////////////////////////////

initial begin

    packet_data = 0;
    packet_done = 0;
    pattern_mode = 0;

    wait(rst_n);
    pattern_mode = 1;

    /////////////////////////////////////////////////////////
    // TEST1 : single pattern packet
    /////////////////////////////////////////////////////////

    $display("TEST1 single packet");

    send_packet(64'h5555555555555555);
    send_packet(64'h5555555555555555);

    if(!pattern_detected)
        $fatal("Error detected with single packet");

    send_packet(64'h5555555555555555);

    if(!pattern_detected)
        $fatal("Error detected with single packet");

    send_packet($random);
    send_packet(64'h5555555555555555);

    if(pattern_detected)
        $fatal("Error detected with single packet");

    $display("TEST PASSED");

    $stop;

end

endmodule