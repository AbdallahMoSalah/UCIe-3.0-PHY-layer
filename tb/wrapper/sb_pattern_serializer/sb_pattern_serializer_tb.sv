`timescale 1ns/1ps
import sb_pkg::*;
module sb_pattern_serializer_tb;

////////////////////////////////////////////////////////////
// Clock / Reset
////////////////////////////////////////////////////////////

logic clk;
logic clk_parallel;
logic rst_n;

////////////////////////////////////////////////////////
// Clock
////////////////////////////////////////////////////////
initial begin
    clk = 0;
    clk_parallel = 0;
end
always #(SERDES_CLK/2) clk = ~clk;

always #(SB_CLK/2) clk_parallel = ~clk_parallel;   // 100 MHz equivalent

////////////////////////////////////////////////////////////
// Control Signals
////////////////////////////////////////////////////////////

logic start_pat_req;
logic pattern_mode;
logic send_4_iter;
logic four_iter_done;

////////////////////////////////////////////////////////////
// Mapper Interface
////////////////////////////////////////////////////////////

logic [63:0] mapper_data;
logic mapper_valid;
logic mapper_ready;

////////////////////////////////////////////////////////////
// Serializer Interface
////////////////////////////////////////////////////////////

logic [63:0] ser_data;
logic ser_valid;
logic ser_ready;

logic tx_serial_out;
logic TXCKSB;

////////////////////////////////////////////////////////////
// DUTs
////////////////////////////////////////////////////////////

sb_pattern_engine dut_pattern (

    .clk(clk_parallel),
    .rst_n(rst_n),

    .pattern_mode(pattern_mode),
    .start_pat_req(start_pat_req),
    .send_4_iter(send_4_iter),

    .four_iter_done(four_iter_done),

    .mapper_data(mapper_data),
    .mapper_valid(mapper_valid),
    .mapper_ready(mapper_ready),

    .ser_ready(ser_ready),

    .ser_data(ser_data),
    .ser_valid(ser_valid)
);

sb_serializer dut_serializer (

    .clk_serial(clk),
    .clk_parallel(clk_parallel),
    .rst_n(rst_n),

    .pmo_en(1'b0),

    .tx_parallel_data(ser_data),
    .tx_data_valid(ser_valid),
    .tx_ready(ser_ready),

    .tx_serial_out(tx_serial_out),
    .TXCKSB(TXCKSB)
);

bind sb_serializer sb_serializer_sva SVA_ser (    
    .clk_serial(clk),
    .clk_parallel(clk_parallel),
    .rst_n(rst_n),
    .pmo_en(pmo_en),

    .tx_parallel_data(tx_parallel_data),
    .tx_data_valid(tx_data_valid),
    .tx_ready(tx_ready),

    .tx_serial_out(tx_serial_out),
    .TXCKSB(TXCKSB)
);

////////////////////////////////////////////////////////////
// Reset
////////////////////////////////////////////////////////////

initial begin
    rst_n = 0;
    #40;
    rst_n = 1;
end

////////////////////////////////////////////////////////////
// Iteration Monitor
////////////////////////////////////////////////////////////

int iter_count;
int prev_count;

always @(posedge clk_parallel) begin
    if(ser_valid && ser_ready)
        iter_count++;
end

////////////////////////////////////////////////////////////
// Test Sequence
////////////////////////////////////////////////////////////

initial begin

    mapper_data  = 0;
    mapper_valid = 0;

    start_pat_req = 0;
    pattern_mode = 1;
    send_4_iter  = 0;

    iter_count   = 0;

    wait(rst_n);

////////////////////////////////////////////////////////////
// TEST 1
// Pattern streaming without counting
////////////////////////////////////////////////////////////

    $display("TEST1: start_pat_req=1, send_4_iter=0");

    @(posedge clk_parallel);
    pattern_mode = 1;
    start_pat_req = 1;
    send_4_iter  = 0;

    repeat(49) @(posedge clk_parallel);

    if(four_iter_done)
        $fatal("ERROR: four_iter_done asserted while send_4_iter=0");

////////////////////////////////////////////////////////////
// TEST 2
// Start counting
////////////////////////////////////////////////////////////

    $display("TEST2: start 4 iteration counting");

    send_4_iter = 1;


    while(!four_iter_done)
        @(posedge clk_parallel);
    
    $display("four_iter_done detected");

////////////////////////////////////////////////////////////
// Verify iteration count
////////////////////////////////////////////////////////////

    if(iter_count < 4)
        $fatal("ERROR: less than 4 iterations sent");

////////////////////////////////////////////////////////////
// Stop pattern immediately
////////////////////////////////////////////////////////////

    repeat(2) @(posedge clk_parallel);
    pattern_mode = 0;
    start_pat_req = 0;
    send_4_iter = 0;


    prev_count = iter_count;

    repeat(25) @(posedge clk_parallel);

    if(iter_count > prev_count)
        $fatal("ERROR: pattern continued after done");

    mapper_data  = $random;
    mapper_valid = 1;
    @(posedge clk_parallel);
    while(!mapper_ready)
        @(posedge clk_parallel);
    
    mapper_valid = 0;
    repeat(25) @(posedge clk_parallel);

////////////////////////////////////////////////////////////
// Finish
////////////////////////////////////////////////////////////

    $display("TEST PASSED");
    $stop;

end

endmodule