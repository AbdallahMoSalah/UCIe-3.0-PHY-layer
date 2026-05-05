module sb_deserializer_sva
#(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32
)
(

    input  logic                     RXCKSB,
    input  logic                     rst_n,

    input  logic                     RXDATASB,

    // registered outputs
    input logic [DATA_WIDTH-1:0]    rx_parallel_data,
    input logic                     rx_data_vld,

    // FIFO interface (combinational)
    input logic [DATA_WIDTH-1:0]    packet_data,
    input logic                     packet_done
);



property p_counter_wrap;
    @(posedge RXCKSB)
    disable iff (!rst_n)
    (sb_deserializer.bit_cnt == DATA_WIDTH-1) |=> (sb_deserializer.bit_cnt == 0);
endproperty

assert property(p_counter_wrap);
cover property(p_counter_wrap);

property p_counter_increment;
    @(posedge RXCKSB)
    disable iff (!rst_n)
    (sb_deserializer.bit_cnt != DATA_WIDTH-1) |=> (sb_deserializer.bit_cnt == $past(sb_deserializer.bit_cnt)+1);
endproperty

assert property(p_counter_increment);
cover property(p_counter_increment);


property p_packet_done_position;
    @(posedge RXCKSB)
    disable iff (!rst_n)
    packet_done |-> (sb_deserializer.bit_cnt == DATA_WIDTH-1);
endproperty

assert property(p_packet_done_position);
cover property(p_packet_done_position);


property p_packet_done_pulse;
    @(posedge RXCKSB)
    disable iff (!rst_n)
    packet_done |=> !packet_done;
endproperty

assert property(p_packet_done_pulse);
cover property(p_packet_done_pulse);

endmodule