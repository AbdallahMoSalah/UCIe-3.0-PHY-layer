`timescale 1ns/1ps

module sb_serializer_tb;

parameter DATA_WIDTH = 64;
parameter GAP_WIDTH  = 32;

logic clk_parallel;
logic clk_serial;
logic rst_n;

logic pmo_en;

logic [DATA_WIDTH-1:0] tx_parallel_data;
logic tx_data_valid;
logic tx_rdy;

logic TXDATASB;
logic TXCKSB;

////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////

sb_serializer #(
.DATA_WIDTH(DATA_WIDTH),
.GAP_WIDTH(GAP_WIDTH)
) dut (
.clk_parallel(clk_parallel),
.clk_serial(clk_serial),
.rst_n(rst_n),
.pmo_en(pmo_en),

.tx_parallel_data(tx_parallel_data),
.tx_data_valid(tx_data_valid),
.tx_rdy(tx_rdy),

.TXDATASB(TXDATASB),
.TXCKSB(TXCKSB)
);

////////////////////////////////////////////////////////////
// CLOCK GENERATION
////////////////////////////////////////////////////////////

initial clk_parallel = 0;
always #5 clk_parallel = ~clk_parallel;   // 100 MHz equivalent

initial clk_serial = 0;
always #1 clk_serial = ~clk_serial;       // fast serial clock

////////////////////////////////////////////////////////////
// RESET
////////////////////////////////////////////////////////////

initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
end

////////////////////////////////////////////////////////////
// DRIVER
////////////////////////////////////////////////////////////

task send_packet(input logic [63:0] data);

    @(posedge clk_parallel);
    tx_parallel_data = data;
    tx_data_valid    = 1;

    wait(tx_rdy);

    @(posedge clk_parallel);

    tx_data_valid    = 0;

endtask

////////////////////////////////////////////////////////////
// MONITOR
////////////////////////////////////////////////////////////

logic [63:0] captured_data;
integer bit_index;

always @(posedge clk_serial) begin

    if(dut.state == dut.S_SHIFT) begin

        captured_data[bit_index] = TXDATASB;
        bit_index++;

        if(bit_index == DATA_WIDTH) begin
            $display("Serialized packet = %h", captured_data);
            bit_index = 0;
        end

    end

end

////////////////////////////////////////////////////////////
// TEST SEQUENCE
////////////////////////////////////////////////////////////

initial begin

    tx_parallel_data = 0;
    tx_data_valid    = 0;
    pmo_en           = 0;
    bit_index        = 0;

    wait(rst_n);

    #20;

    // Test 1
    send_packet(64'hA5A5A5A5DEADBEEF);
    send_packet($random);
    send_packet($random);
    send_packet($random);

    #2000;

    // Test 2
    send_packet(64'h123456789ABCDEF0);

    #2000;

    // PMO test
    pmo_en = 1;

    send_packet(64'h1111222233334444);
    send_packet(64'h5555666677778888);
    send_packet($random);
    send_packet($random);
    send_packet($random);

    #3000;

    $stop;

end

endmodule