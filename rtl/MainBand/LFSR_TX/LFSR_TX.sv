module moduleName #(
    parameter WIDTH = 32
) (
    input logic       i_clk,
    input logic       i_rst_n,
    input logic       scramble_en,
    input logic       i_en_reverse_order ,
    input logic [2:0] i_width_deg_map    ,
    input logic [WIDTH-1:0] i_lane_0 ,   input logic [WIDTH-1:0] lane_1 ,  
    input logic [WIDTH-1:0] i_lane_2 ,   input logic [WIDTH-1:0] i_lane_3 ,  
    input logic [WIDTH-1:0] i_lane_4 ,   input logic [WIDTH-1:0] i_lane_5 ,  
    input logic [WIDTH-1:0] i_lane_6 ,   input logic [WIDTH-1:0] i_lane_7 ,  
    input logic [WIDTH-1:0] i_lane_8 ,   input logic [WIDTH-1:0] i_lane_9 ,  
    input logic [WIDTH-1:0] i_lane_10,   input logic [WIDTH-1:0] i_lane_11,  
    input logic [WIDTH-1:0] i_lane_12,   input logic [WIDTH-1:0] i_lane_13,  
    input logic [WIDTH-1:0] i_lane_14,   input logic [WIDTH-1:0] i_lane_15, 

    output logic [WIDTH-1:0] o_lane_0 ,   output logic [WIDTH-1:0] o_lane_1 ,  
    output logic [WIDTH-1:0] o_lane_2 ,   output logic [WIDTH-1:0] o_lane_3 ,  
    output logic [WIDTH-1:0] o_lane_4 ,   output logic [WIDTH-1:0] o_lane_5 ,  
    output logic [WIDTH-1:0] o_lane_6 ,   output logic [WIDTH-1:0] o_lane_7 ,  
    output logic [WIDTH-1:0] o_lane_8 ,   output logic [WIDTH-1:0] o_lane_9 ,  
    output logic [WIDTH-1:0] o_lane_10,   output logic [WIDTH-1:0] o_lane_11,  
    output logic [WIDTH-1:0] o_lane_12,   output logic [WIDTH-1:0] o_lane_13,  
    output logic [WIDTH-1:0] o_lane_14,   output logic [WIDTH-1:0] o_lane_15, 

    output logic       valid_frame_en,
    output logic       o_lfsr_tx_done ,

);
    
endmodule