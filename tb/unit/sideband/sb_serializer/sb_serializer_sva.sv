module sb_serializer_sva
#(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32
)
(
    input  logic                     clk,
    input  logic                     rst_n,
    input logic pmo_en,

    // Parallel interface
    input  logic [DATA_WIDTH-1:0]    tx_parallel_data,
    input  logic                     tx_data_valid,
    input logic                     tx_ready,

    // Serial output
    input logic                     tx_serial_out,

    // Forwarded sideband clock
    input logic                     TXCKSB
);



property p_valid_hold;

@(posedge clk) disable iff (!rst_n)
tx_data_valid && !tx_ready |-> $stable(tx_parallel_data);

endproperty

assert property (p_valid_hold);
cover property (p_valid_hold);

property p_shift_length;

@(posedge clk) disable iff (!rst_n || pmo_en)
($past(sb_serializer.state) != sb_serializer.SHIFT) && sb_serializer.state == sb_serializer.SHIFT |-> ##64 sb_serializer.state != sb_serializer.SHIFT;

endproperty

assert property (p_shift_length);
cover property (p_shift_length);

property p_gap_length;

@(posedge clk) disable iff (!rst_n)
$past(sb_serializer.state != sb_serializer.GAP) && sb_serializer.state == sb_serializer.GAP |-> ##32 sb_serializer.state != sb_serializer.GAP;

endproperty

assert property (p_gap_length);
cover property (p_gap_length);

property p_clock_forward;

@(posedge clk) disable iff (!rst_n)
(sb_serializer.state != sb_serializer.SHIFT) |-> TXCKSB == 0;

endproperty

assert property (p_clock_forward);
cover property (p_clock_forward);

endmodule