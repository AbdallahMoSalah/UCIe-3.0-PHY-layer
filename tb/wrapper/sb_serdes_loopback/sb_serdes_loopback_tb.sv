module sb_serdes_loopback_tb;

import sb_serializer_tb_pkg::*;

parameter DATA_WIDTH = 64;

logic clk;
logic rst_n;

logic pmo_en;

// TX side
logic [DATA_WIDTH-1:0] tx_parallel_data;
logic tx_data_valid;
logic tx_rdy;

// serial link
logic TXDATASB;
logic TXCKSB;
logic RXCKSB;

// RX side
logic [DATA_WIDTH-1:0] rx_parallel_data;
logic rx_data_vld;
logic packet_done;
logic [DATA_WIDTH-1:0] packet_data;


sb_serializer_class obj = new;

////////////////////////////////////////////////////////
// Expected queue
////////////////////////////////////////////////////////

logic [DATA_WIDTH-1:0] expected_q[$];

int pass, fail;

////////////////////////////////////////////////////////
// DUTs
////////////////////////////////////////////////////////

assign #(5) RXCKSB  = TXCKSB;
sb_serializer serializer (

    .clk(clk),
    .rst_n(rst_n),
    .pmo_en(pmo_en),

    .tx_parallel_data(tx_parallel_data),
    .tx_data_valid(tx_data_valid),
    .tx_rdy(tx_rdy),

    .TXDATASB(TXDATASB),
    .TXCKSB(TXCKSB)
);

sb_deserializer deserializer (

    .rst_n(rst_n),

    .RXDATASB(TXDATASB),
    .RXCKSB(RXCKSB),

    .rx_parallel_data(rx_parallel_data),
    .rx_data_vld(rx_data_vld),
    .packet_done(packet_done),
    .packet_data(packet_data)
);

bind sb_serializer sb_serializer_sva SVA_ser (    
    .clk(clk),
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
    

    .RXDATASB(TXDATASB),
    .RXCKSB(RXCKSB),

    .rx_parallel_data(rx_parallel_data),
    .rx_data_vld(rx_data_vld),
    .packet_done(packet_done),
    .packet_data(packet_data)
);

////////////////////////////////////////////////////////
// Clock
////////////////////////////////////////////////////////

initial clk = 0;
always #5 clk = ~clk;

////////////////////////////////////////////////////////
// Reset
////////////////////////////////////////////////////////

initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
end

////////////////////////////////////////////////////////
// Send packet task
////////////////////////////////////////////////////////

task send_packet(input logic [63:0] data);

    @(negedge clk);

    while(!tx_rdy)
        @(negedge clk);

    tx_parallel_data = data;
    tx_data_valid    = 1;

    expected_q.push_back(data);

    @(negedge clk);

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

////////////////////////////////////////////////////////
// RX monitor
////////////////////////////////////////////////////////

/* always @(posedge clk) begin

    if(rx_data_vld) begin

        logic [63:0] exp;

        exp = expected_q.pop_front();

        if(rx_parallel_data === exp) begin
            pass++;
        end
        else begin
            fail++;
            $display("Mismatch time=%0t exp=%h got=%h",
                      $time, exp, rx_parallel_data);
        end

    end

end */

always @(posedge RXCKSB) begin

    if(packet_done) begin

        check_result();

    end

end

////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////

initial begin

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
    // TEST 3 heavy load PMO
    ////////////////////////////////////////////////////

    repeat(50)
        send_packet($random);

    repeat(200) @(posedge clk);


    repeat(50) begin
        pmo_en = $random;
        send_packet($random);
    end

    repeat(200) @(posedge clk);

    pmo_en = 0;
    repeat (1000000) begin 
        obj.testtype = WITHOUT_RESET;
        send_random();

    end
    ////////////////////////////////////////////////////

    $display("PASS = %0d", pass);
    $display("FAIL = %0d", fail);

    $stop;

end

task check_result();

    if(packet_data === tx_parallel_data) begin
        pass++;
    end
    else begin
        fail++;
        $display("Mismatch at time %0t", $time);
        $display("FAIL exp=%h act=%h", rx_parallel_data, tx_parallel_data);
    end

endtask

// -----------------------------------
// Random Send Task
// ----------------------------------   
task send_random(); 
    
    @(negedge clk);
    obj.tx_rdy = tx_rdy;
    assert(obj.randomize());
    
    rst_n = obj.rst_n;
    tx_parallel_data = obj.tx_parallel_data;
    tx_data_valid = obj.tx_data_valid;
    
endtask

endmodule