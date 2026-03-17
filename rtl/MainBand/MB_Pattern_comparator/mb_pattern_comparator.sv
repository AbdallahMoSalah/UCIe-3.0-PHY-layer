// Module: MB_pattern_comparator
// Status: Under Editing
// Description: Pattern comparator for MainBand lanes (Per-Lane & Aggregate modes)
// Author: Mohamed Anwar
module PATTERN_COMPARATOR #(
    parameter WIDTH = 32 
)(
input wire i_clk ,
input wire i_rst_n ,
input wire type_of_com ,
input wire i_enable_pattern_com ,
input wire [5:0]  i_max_error_threshold_per_lane_ID , // 32_bit may be error per lane 
input wire [15:0] i_max_error_threshold_aggergate ,  // pattern mismatches ... are accumulated into a 16-bit error counter 

input wire [WIDTH-1:0] i_local_gen_0, i_local_gen_1, i_local_gen_2, i_local_gen_3,
input wire [WIDTH-1:0] i_local_gen_4, i_local_gen_5, i_local_gen_6, i_local_gen_7,
input wire [WIDTH-1:0] i_local_gen_8, i_local_gen_9, i_local_gen_10, i_local_gen_11,
input wire [WIDTH-1:0] i_local_gen_12, i_local_gen_13, i_local_gen_14, i_local_gen_15,

input wire [WIDTH-1:0] i_data_0 ,  i_data_1 ,  i_data_2 ,  i_data_3 ,
input wire [WIDTH-1:0] i_data_4 ,  i_data_5 ,  i_data_6 ,  i_data_7 ,
input wire [WIDTH-1:0] i_data_8 ,  i_data_9 ,  i_data_10 , i_data_11 ,
input wire [WIDTH-1:0] i_data_12 , i_data_13 , i_data_14 , i_data_15 و

output reg [15:0] o_per_lane_error ,
output reg o_error_done 

);

endmodule