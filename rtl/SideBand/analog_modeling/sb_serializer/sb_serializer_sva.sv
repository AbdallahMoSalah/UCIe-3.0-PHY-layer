module sb_serializer_sva
#(
    parameter DATA_WIDTH = 64,
    parameter S_GAP_WIDTH  = 32
)
(
    input  logic                     clk_serial,
    input  logic                     clk_parallel,
    input  logic                     rst_n,
    input  logic                     pmo_en,

    // Parallel interface
    input  logic [DATA_WIDTH-1:0]    tx_parallel_data,
    input  logic                     tx_data_valid,
    input logic                     tx_rdy,

    // Serial output
    input logic                     TXDATASB,

    // Forwarded sideband clock
    input logic                     TXCKSB
);



property p_valid_hold;

@(posedge clk_parallel) disable iff (!rst_n)
tx_data_valid && !tx_rdy |=> $stable(tx_parallel_data);

endproperty

assert property (p_valid_hold);
cover property (p_valid_hold);

property p_S_SHIFT_length;

@(posedge sb_serializer.clk_serial) disable iff (!rst_n || pmo_en)
($past(sb_serializer.state) != sb_serializer.S_SHIFT) && sb_serializer.state == sb_serializer.S_SHIFT |-> ##64 sb_serializer.state != sb_serializer.S_SHIFT;

endproperty

assert property (p_S_SHIFT_length);
cover property (p_S_SHIFT_length);

property p_S_GAP_length;

@(posedge sb_serializer.clk_serial) disable iff (!rst_n)
$past(sb_serializer.state ) != (sb_serializer.S_GAP) && sb_serializer.state == sb_serializer.S_GAP |-> ##32 sb_serializer.state != sb_serializer.S_GAP;

endproperty

assert property (p_S_GAP_length);
cover property (p_S_GAP_length);

property p_clock_forward;

@(posedge sb_serializer.clk_serial) disable iff (!rst_n)
(sb_serializer.state != sb_serializer.S_SHIFT) |-> TXCKSB == 0;

endproperty

assert property (p_clock_forward);
cover property (p_clock_forward);

endmodule
