module sb_serializer_tb;
import sb_serializer_tb_pkg::*;

logic clk;
logic rst_n;

logic [DATA_WIDTH-1:0] tx_parallel_data;
logic tx_data_valid;
logic tx_ready;

logic tx_serial_out;
logic TXCKSB;

sb_serializer_class obj = new;

int pass,fail;
/////////////////////////////////////////////////////
// DUT
/////////////////////////////////////////////////////

sb_serializer dut (
    .clk(clk),
    .rst_n(rst_n),
    .pmo_en(0),

    .tx_parallel_data(tx_parallel_data),
    .tx_data_valid(tx_data_valid),
    .tx_ready(tx_ready),

    .tx_serial_out(tx_serial_out),
    .TXCKSB(TXCKSB)
);

bind sb_serializer sb_serializer_sva SVA (    
    .clk(clk),
    .rst_n(rst_n),
    .pmo_en(0),

    .tx_parallel_data(tx_parallel_data),
    .tx_data_valid(tx_data_valid),
    .tx_ready(tx_ready),

    .tx_serial_out(tx_serial_out),
    .TXCKSB(TXCKSB)
);


/////////////////////////////////////////////////////
// Clock
/////////////////////////////////////////////////////

initial clk = 0;
always #5 clk = ~clk;

/////////////////////////////////////////////////////
// Reset
/////////////////////////////////////////////////////

initial begin
    rst_n = 0;
    tx_data_valid = 0;
    #50;
    rst_n = 1;
end

/////////////////////////////////////////////////////
// Packet Send Task
/////////////////////////////////////////////////////

task send_packet(input logic [63:0] data);

    @(negedge clk);

    while (!tx_ready)
        @(negedge clk);

    tx_parallel_data = data;
    tx_data_valid    = 1;

    @(negedge clk);

    tx_data_valid    = 0;

endtask

always_ff @(posedge clk) begin
    obj.sample_cov(dut.state);
end

always_comb begin
    if(!rst_n) begin
        obj.cvr_gp.stop();
    end
    else begin
        obj.cvr_gp.start();
    end
end
/////////////////////////////////////////////////////
// Monitor
/////////////////////////////////////////////////////

logic [DATA_WIDTH-1 : 0] serial_capture;
int bit_count;
logic rx_data_valid;

assign #1 RXCKSB    = TXCKSB;
always_ff @(posedge RXCKSB or negedge rst_n) begin

    if(!rst_n) begin
        bit_count <= 0;
        serial_capture <= 0;
        rx_data_valid <= 0;
    end
    else begin

        serial_capture <= {tx_serial_out, serial_capture[DATA_WIDTH-1:1]};

        if(bit_count == DATA_WIDTH-1) begin
            serial_capture <= {tx_serial_out, serial_capture[DATA_WIDTH-1:1]};
            rx_data_valid <= 1;
            bit_count <= 0;
        end
        else if(bit_count == 0 && rx_data_valid) begin
            rx_data_valid <= 0;
        end
        else begin
            bit_count <= bit_count + 1;
            rx_data_valid <= 0;
        end
    end

end

always @(posedge clk) begin

    if(rx_data_valid) begin

        check_result();

    end

end

/////////////////////////////////////////////////////
// Testcases
/////////////////////////////////////////////////////

initial begin

    wait(rst_n);

    //////////////////////////////////////////////////
    // TEST 1 : single packet
    //////////////////////////////////////////////////

    send_packet(64'hA5A5A5A5A5A5A5A5);

    repeat(200) @(posedge clk);

    //////////////////////////////////////////////////
    // TEST 2 : back to back
    //////////////////////////////////////////////////

    send_packet(64'h1111111111111111);
    send_packet(64'h2222222222222222);

    repeat(200) @(posedge clk);

    //////////////////////////////////////////////////
    // TEST 3 : random traffic
    //////////////////////////////////////////////////

    repeat(10) begin

        send_packet($random);

        repeat($urandom_range(0,20))
            @(posedge clk);

    end

    //////////////////////////////////////////////////
    // TEST 4 : heavy load
    //////////////////////////////////////////////////

    repeat(50) begin
        send_packet($random);
    end

    repeat(200) @(posedge clk);

    //////////////////////////////////////////////////
    // TEST 5 : 
    //////////////////////////////////////////////////
    repeat (1000000) begin 
        obj.testtype = WITHOUT_RESET;
        send_random();

    end

    $display("TEST DONE");
    #20 $display("PASS = %0d", pass);
    $display("FAIL = %0d", fail);
    $stop;

end

task check_result();

    if(serial_capture === tx_parallel_data) begin
        pass++;
    end
    else begin
        fail++;
        $display("Mismatch at time %0t", $time);
        $display("FAIL exp=%h act=%h", serial_capture, tx_parallel_data);
    end

endtask


// -----------------------------------
// Random Send Task
// ----------------------------------   
task send_random(); 
    
    @(negedge clk);
    obj.tx_ready = tx_ready;
    assert(obj.randomize());
    
    rst_n = obj.rst_n;
    tx_parallel_data = obj.tx_parallel_data;
    tx_data_valid = obj.tx_data_valid;
    
endtask

endmodule