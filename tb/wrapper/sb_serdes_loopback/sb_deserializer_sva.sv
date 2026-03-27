module sb_deserializer_sva
#(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32
)
(

    input  logic rst_n,

    input  logic rx_serial_in,
    input  logic RXCKSB,

    input logic [DATA_WIDTH-1:0] rx_parallel_data,
    input logic rx_data_valid
);



property p_valid_hold_des;

@(posedge RXCKSB) disable iff (!rst_n)
rx_data_valid |-> sb_deserializer.bit_cnt == 0;

endproperty

assert property (p_valid_hold_des);
cover property (p_valid_hold_des);

property p_valid_trans;

@(posedge RXCKSB) disable iff (!rst_n)
rx_data_valid |-> ##1 !rx_data_valid;

endproperty

assert property (p_valid_trans);
cover property (p_valid_trans);


endmodule