`timescale 1ns/1ps

module sb_serdes_loopback_tb_m2;

import sb_serializer_tb_pkg::*;

parameter DATA_WIDTH = 64;
parameter SB_FREQ = 100.0;
parameter  SB_CLK = (1000/SB_FREQ);

parameter  SERDES_FREQ = 800.0;
parameter  SERDES_CLK = (1000/SERDES_FREQ);


logic clk;
logic rst_n;

logic pmo_en;

// TX side
logic [DATA_WIDTH-1:0] tx_parallel_data;
logic tx_data_valid;
logic tx_rdy;

// serial link
logic TXDATASB;
logic clk_parallel;
logic TXCKSB;
logic RXCKSB;

// RX side
logic [DATA_WIDTH-1:0] rx_parallel_data_serial;
logic rx_data_vld_serial;
logic packet_done;
logic [DATA_WIDTH-1:0] packet_data;

logic [DATA_WIDTH-1:0]    rx_parallel_data_out;
logic                     rx_data_vld;


sb_serializer_class obj = new;

////////////////////////////////////////////////////////
// Expected queue
////////////////////////////////////////////////////////

logic [DATA_WIDTH-1:0] expected_q[$];

logic [DATA_WIDTH-1:0] tx_data_exp;
int pass, fail;

////////////////////////////////////////////////////////
// DUTs
////////////////////////////////////////////////////////

assign #(SERDES_CLK/2) RXCKSB  = TXCKSB;
sb_serializer serializer (

    .clk_serial(clk),
    .clk_parallel(clk_parallel),
    .rst_n(rst_n),
    .pmo_en(pmo_en),

    .tx_parallel_data(tx_parallel_data),
    .tx_data_valid(tx_data_valid),
    .tx_rdy(tx_rdy),

    .TXDATASB(TXDATASB),
    .TXCKSB(TXCKSB)
);

sb_deserializer deserializer (

    .RXCKSB(RXCKSB),
    .clk_parallel(clk_parallel),
    .rst_n(rst_n),

    .RXDATASB(TXDATASB),

    .rx_parallel_data_out(rx_parallel_data_out),
    .rx_data_vld(rx_data_vld)
);

bind sb_serializer sb_serializer_sva SVA_ser (    
    .clk_serial(clk),
    .clk_parallel(clk_parallel),
    .rst_n(rst_n),
    .pmo_en(pmo_en),

    .tx_parallel_data(tx_parallel_data),
    .tx_data_valid(tx_data_valid),
    .tx_rdy(tx_rdy),

    .TXDATASB(TXDATASB),
    .TXCKSB(TXCKSB)
);

bind sb_deserializer sb_deserializer_sva SVA_des (

    .rst_n(rst_n),

    .RXCKSB(RXCKSB),
    .clk_parallel(clk_parallel),

    .rx_parallel_data_out(rx_parallel_data_out),
    .rx_data_vld(rx_data_vld)
);

////////////////////////////////////////////////////////
// Clock
////////////////////////////////////////////////////////

always #(SERDES_CLK/2) clk = ~clk;

always #(SB_CLK/2) clk_parallel = ~clk_parallel;   // 100 MHz equivalent

////////////////////////////////////////////////////////
// Reset
////////////////////////////////////////////////////////

initial begin
    clk_parallel = 0;
    clk = 0;
    rst_n = 0;
    #50;
    rst_n = 1;
end

////////////////////////////////////////////////////////
// Send packet task
////////////////////////////////////////////////////////

task send_packet(input logic [63:0] data);

    @(posedge clk_parallel);
    tx_parallel_data = data;
    tx_data_valid    = 1;

    @(posedge clk_parallel);
    while(!tx_rdy)
        @(posedge clk_parallel);

    expected_q.push_back(data);

    tx_data_valid = 0;

endtask


always_ff @(posedge clk) begin
    obj.sample_cov(serializer.state);
end

always_comb begin
    if(!rst_n) begin
        obj.cvr_gp.stop();
    end
    else begin
        obj.cvr_gp.start();
    end
end


always @(posedge clk_parallel) begin

    if(rx_data_vld) begin

        check_result();

    end

end

////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////

initial begin
    tx_parallel_data = '0;
    tx_data_valid = 0;
    pmo_en = 0;

    wait(rst_n);

    ////////////////////////////////////////////////////
    // TEST 1 normal mode
    ////////////////////////////////////////////////////

    pmo_en = 0;
    send_packet(64'hA5A5A5A5A5A5A5A5);

    repeat(10)
        send_packet($random);

    repeat(200) @(posedge clk);

    ////////////////////////////////////////////////////
    // TEST 2 PMO mode
    ////////////////////////////////////////////////////

    pmo_en = 1;
    send_packet(64'hA5A5A5A5A5A5A5A5);

    repeat(20)
        send_packet($random);

    repeat(200) @(posedge clk);


    ////////////////////////////////////////////////////
    // TEST 3 normal mode not heavy
    ////////////////////////////////////////////////////

    pmo_en = 0;
    send_packet(64'hA5A5A5A5A5A5A5A5);

    repeat(10) begin
        repeat(25) @(posedge clk);
        send_packet($random);
    end

    repeat(200) @(posedge clk);

    ////////////////////////////////////////////////////
    // TEST 4 PMO mode not heavy
    ////////////////////////////////////////////////////

    pmo_en = 1;
    send_packet(64'hA5A5A5A5A5A5A5A5);

    repeat(10) begin
        repeat(25) @(posedge clk);
        send_packet($random);
    end

    repeat(200) @(posedge clk);

    ////////////////////////////////////////////////////
    // TEST 3 heavy load PMO
    ////////////////////////////////////////////////////

    repeat(50) begin 
        pmo_en = $random;
        send_packet($random);
    end

    repeat(200) @(posedge clk);


    repeat(50) begin
        pmo_en = $random;
        send_packet($random);
    end

    repeat(200) @(posedge clk);

    pmo_en = 0;
    repeat (100000) begin 
        obj.testtype = WITHOUT_RESET;
        send_random();

    end
    ////////////////////////////////////////////////////

    $display("PASS = %0d", pass);
    $display("FAIL = %0d", fail);

    $stop;

end

task check_result();

    tx_data_exp = expected_q.pop_front();
    if(rx_parallel_data_out === tx_data_exp) begin
        pass++;
    end
    else begin
        fail++;
        $display("Mismatch at time %0t", $time);
        $display("FAIL exp=%h act=%h", tx_data_exp, rx_parallel_data_out );
    end

endtask

// -----------------------------------
// Random Send Task
// ----------------------------------   
task send_random(); 
    
    @(posedge clk_parallel);
    obj.tx_rdy = tx_rdy;
    if(tx_data_valid && tx_rdy)begin
        expected_q.push_back(tx_parallel_data);  
    end
    assert(obj.randomize());
    
    rst_n = obj.rst_n;
    tx_data_valid = obj.tx_data_valid;
    tx_parallel_data = obj.tx_parallel_data;

    
    
endtask

endmodule