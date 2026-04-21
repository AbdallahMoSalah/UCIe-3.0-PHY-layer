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


    //============================================================
    // Degrade Modes
    //============================================================
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;
    //============================================================
    // Lane ID
    //============================================================
    localparam lane_0_ID  = 16'b0101_00000000_0101;
    localparam lane_1_ID  = 16'b0101_00000001_0101;
    localparam lane_2_ID  = 16'b0101_00000010_0101;
    localparam lane_3_ID  = 16'b0101_00000011_0101; 
    localparam lane_4_ID  = 16'b0101_00000100_0101;
    localparam lane_5_ID  = 16'b0101_00000101_0101;
    localparam lane_6_ID  = 16'b0101_00000110_0101;
    localparam lane_7_ID  = 16'b0101_00000111_0101;
    localparam lane_8_ID  = 16'b0101_00001000_0101;
    localparam lane_9_ID  = 16'b0101_00001001_0101;
    localparam lane_10_ID = 16'b0101_00001010_0101;
    localparam lane_11_ID = 16'b0101_00001011_0101;
    localparam lane_12_ID = 16'b0101_00001100_0101;
    localparam lane_13_ID = 16'b0101_00001101_0101;
    localparam lane_14_ID = 16'b0101_00001110_0101;
    localparam lane_15_ID = 16'b0101_00001111_0101;

    // lane_reverse_en 
    reg lane_rev_en 

    // SEEDS
    reg[22:0] SEED_0;
    reg[22:0] SEED_1;
    reg[22:0] SEED_2;
    reg[22:0] SEED_3;
    reg[22:0] SEED_4;
    reg[22:0] SEED_5;
    reg[22:0] SEED_6;
    reg[22:0] SEED_7;
    assign SEED_0 = 23'h1DBFBC;
    assign SEED_1 = 23'h0607BB;
    assign SEED_2 = 23'h1EC760;
    assign SEED_3 = 23'h18C0DB;
    assign SEED_4 = 23'h010F12;
    assign SEED_5 = 23'h19CFC9;
    assign SEED_6 = 23'h0277CE;
    assign SEED_7 = 23'h1BB807;
    


    
endmodule