module LFSR_Receiver #(
    parameter WIDTH = 32 // Parameter for signal WIDTH
)(
    input i_clk,
    input i_rst_n,
    input [1:0] i_state,
    input [2:0] i_width_deg_lfsr, // Lane mapping code
    input logic i_descramble_en, // Enable scrambling pattern
    input i_enable_buffer,                   // Enable for Data Come from buffer
    // Input from DESERIALIZER 
    input logic [WIDTH-1:0] i_data_in_0, i_data_in_1, i_data_in_2, i_data_in_3, i_data_in_4, i_data_in_5,
    input logic [WIDTH-1:0] i_data_in_6, i_data_in_7, i_data_in_8, i_data_in_9,
    input logic [WIDTH-1:0] i_data_in_10, i_data_in_11, i_data_in_12, i_data_in_13,
    input logic [WIDTH-1:0] i_data_in_14, i_data_in_15,
    // Output of pattern bypass
    output logic [WIDTH-1:0] o_Data_by_0, o_Data_by_1, o_Data_by_2, o_Data_by_3, o_Data_by_4,
    output logic [WIDTH-1:0] o_Data_by_5, o_Data_by_6, o_Data_by_7, o_Data_by_8,
    output logic [WIDTH-1:0] o_Data_by_9, o_Data_by_10, o_Data_by_11, o_Data_by_12,
    output logic [WIDTH-1:0] o_Data_by_13, o_Data_by_14, o_Data_by_15,
    // Output from locally generated parameter
    output logic [WIDTH-1:0] o_final_gene_0, o_final_gene_1, o_final_gene_2, o_final_gene_3,
    output logic [WIDTH-1:0] o_final_gene_4, o_final_gene_5, o_final_gene_6, o_final_gene_7,
    output logic [WIDTH-1:0] o_final_gene_8, o_final_gene_9, o_final_gene_10, o_final_gene_11,
    output logic [WIDTH-1:0] o_final_gene_12, o_final_gene_13, o_final_gene_14, o_final_gene_15,
    output logic i_enable_pattern_comp
);



// assign i_enable_pattern_comp = (i_state == 2'b10 && i_descramble_en && !i_enable_buffer) ? 0 : 1;

// Declare LFSR logicisters for each lane
logic [8:0] o_lane_0_23, o_lane_1_23, o_lane_2_23, o_lane_3_23;
logic [8:0] o_lane_4_23, o_lane_5_23, o_lane_6_23, o_lane_7_23;

// State definitions
localparam IDLE           = 2'b00; // Idle state
localparam CLEAR_LFSR     = 2'b01; // Clear LFSR pattern
localparam PATTERN_LFSR   = 2'b10; // LFSR pattern generation state
localparam PER_LANE_IDE   = 2'b11; // Per-lane identification state

// Lane configuration definitions
 localparam NONE_DEGRADE           = 3'b000;
 localparam DEGRADE_LANES_0_TO_7   = 3'b001;
 localparam DEGRADE_LANES_8_TO_15  = 3'b010;
 localparam DEGRADE_LANES_0_TO_15  = 3'b011;
 localparam DEGRADE_LANES_0_TO_3   = 3'b100;
 localparam DEGRADE_LANES_4_TO_7   = 3'b101;

// Define Lane IDs as parameters with prepended and appended 1010
parameter LANE_ID_0  = 16'b1010_00000000_1010;
parameter LANE_ID_1  = 16'b1010_00000001_1010;
parameter LANE_ID_2  = 16'b1010_00000010_1010;
parameter LANE_ID_3  = 16'b1010_00000011_1010;
parameter LANE_ID_4  = 16'b1010_00000100_1010;
parameter LANE_ID_5  = 16'b1010_00000101_1010;
parameter LANE_ID_6  = 16'b1010_00000110_1010;
parameter LANE_ID_7  = 16'b1010_00000111_1010;
parameter LANE_ID_8  = 16'b1010_00001000_1010;
parameter LANE_ID_9  = 16'b1010_00001001_1010;
parameter LANE_ID_10 = 16'b1010_00001010_1010;
parameter LANE_ID_11 = 16'b1010_00001011_1010;
parameter LANE_ID_12 = 16'b1010_00001100_1010;
parameter LANE_ID_13 = 16'b1010_00001101_1010;
parameter LANE_ID_14 = 16'b1010_00001110_1010;
parameter LANE_ID_15 = 16'b1010_00001111_1010;

// Internal signals and logicisters
//logic [1:0] delay_counter; // 2-bit counter to track 2 clock cycles
//logic cont;
// Declare LFSR logicisters for each lane
logic [22:0] rx_lfsr_lane_0, rx_lfsr_lane_1, rx_lfsr_lane_2, rx_lfsr_lane_3;
logic [22:0] rx_lfsr_lane_4, rx_lfsr_lane_5, rx_lfsr_lane_6, rx_lfsr_lane_7;

// Temporary logicisters for delaying o_Data_by_* by 1 clock cycle
logic [WIDTH-1:0] temp_Data_by_0, temp_Data_by_1, temp_Data_by_2, temp_Data_by_3;
logic [WIDTH-1:0] temp_Data_by_4, temp_Data_by_5, temp_Data_by_6, temp_Data_by_7;
logic [WIDTH-1:0] temp_Data_by_8, temp_Data_by_9, temp_Data_by_10, temp_Data_by_11;
logic [WIDTH-1:0] temp_Data_by_12, temp_Data_by_13, temp_Data_by_14, temp_Data_by_15;


logic [22:0] seed_0;
logic [22:0] seed_1;
logic [22:0] seed_2;
logic [22:0] seed_3;
logic [22:0] seed_4;
logic [22:0] seed_5;
logic [22:0] seed_6;
logic [22:0] seed_7;

assign seed_0 = 23'h1DBFBC;
assign seed_1 = 23'h0607BB;
assign seed_2 = 23'h1EC760;
assign seed_3 = 23'h18C0DB;
assign seed_4 = 23'h010F12;
assign seed_5 = 23'h19CFC9;
assign seed_6 = 23'h0277CE;
assign seed_7 = 23'h1BB807;

// Function to compute the next LFSR state (unchanged)
function [31:0] next_lfsr_state;
    input [22:0] current_state;
    logic [31:0] next_state;
    begin
        next_state[0]  = current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
        next_state[1]  = current_state[0] ^ current_state[3] ^ current_state[4] ^ current_state[9] ^ current_state[11] ^ current_state[15] ^ current_state[18] ^ current_state[19] ^ current_state[20];
        next_state[2]  = current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[21];
        next_state[3]  = current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[20] ^ current_state[21] ^ current_state[22];
        next_state[4]  = current_state[0] ^ current_state[2] ^ current_state[3] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[12] ^ current_state[14] ^ current_state[16] ^ current_state[18] ^ current_state[22];
        next_state[5]  = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[21];
        next_state[6]  = current_state[1] ^  current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20] ^ current_state[22];            next_state[7]  = current_state[0] ^ current_state[3] ^ current_state[4] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[11] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[19];            
        next_state[7]  = current_state[0] ^ current_state[3] ^current_state[4]  ^current_state[6]  ^current_state[7]  ^current_state[9]  ^current_state[11]  ^current_state[15]  ^current_state[16]  ^current_state[17]  ^current_state[18]  ^current_state[19]  ;
        next_state[8]  = current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20];
        next_state[9]  = current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[8] ^ current_state[9] ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21];
        next_state[10] = current_state[3] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[10] ^ current_state[12] ^ current_state[14] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21] ^ current_state[22];
        next_state[11] = current_state[0] ^ current_state[2] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[10] ^ current_state[11] ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[22];
        next_state[12] = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[6] ^ current_state[11] ^ current_state[12] ^ current_state[14] ^ current_state[17] ^ current_state[20];
        next_state[13] = current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[7] ^ current_state[12] ^ current_state[13] ^ current_state[15] ^ current_state[18] ^ current_state[21];
        next_state[14] = current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[8] ^ current_state[13] ^ current_state[14] ^ current_state[16] ^ current_state[19] ^ current_state[22];
        next_state[15] = current_state[0] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[6] ^ current_state[8] ^ current_state[9] ^ current_state[14] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[20] ^ current_state[21];
        next_state[16] = current_state[1] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[7] ^ current_state[9] ^ current_state[10] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[21] ^ current_state[22];
        next_state[17] = current_state[0] ^ current_state[4] ^ current_state[6] ^ current_state[10] ^ current_state[11] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[21] ^ current_state[22];
        next_state[18] = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[7] ^ current_state[8] ^ current_state[11] ^ current_state[12] ^ current_state[16] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[21] ^ current_state[22];
        next_state[19] = current_state[0] ^ current_state[1] ^ current_state[3] ^ current_state[5] ^ current_state[9] ^ current_state[12] ^ current_state[13] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[20] ^ current_state[22];
        next_state[20] = current_state[0] ^ current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[8] ^ current_state[10] ^ current_state[13] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20];
        next_state[21] = current_state[1] ^ current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[11] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[21];
        next_state[22] = current_state[2] ^ current_state[3] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[12] ^ current_state[15] ^ current_state[16] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
        next_state[23] = next_state[0] ^ next_state[2] ^ next_state[3] ^ next_state[4] ^ next_state[5] ^ next_state[7] ^ next_state[9] ^ next_state[11] ^ next_state[13] ^ next_state[17] ^ next_state[19] ^ next_state[20];
        next_state[24] = next_state[1] ^ next_state[3] ^ next_state[4] ^ next_state[5] ^ next_state[6] ^ next_state[8] ^ next_state[10] ^ next_state[12] ^ next_state[14] ^ next_state[18] ^ next_state[20] ^ next_state[21];
        next_state[25] = next_state[2] ^ next_state[4] ^ next_state[5] ^ next_state[6] ^ next_state[7] ^ next_state[9] ^ next_state[11] ^ next_state[13] ^ next_state[15] ^ next_state[19] ^ next_state[21] ^ next_state[22];
        next_state[26] = next_state[0] ^ next_state[2] ^ next_state[3] ^ next_state[6] ^ next_state[7] ^ next_state[10] ^ next_state[12] ^ next_state[14] ^ next_state[20] ^ next_state[21] ^ next_state[22];
        next_state[27] = next_state[0] ^ next_state[1] ^ next_state[2] ^ next_state[3] ^ next_state[4] ^ next_state[5] ^ next_state[7] ^ next_state[11] ^ next_state[13] ^ next_state[15] ^ next_state[16] ^ next_state[22];
        next_state[28] = next_state[0] ^ next_state[1] ^ next_state[3] ^ next_state[4] ^ next_state[6] ^ next_state[12] ^ next_state[14] ^ next_state[17] ^ next_state[21];
        next_state[29] = next_state[1] ^ next_state[2] ^ next_state[4] ^ next_state[5] ^ next_state[7] ^ next_state[13] ^ next_state[15] ^ next_state[18] ^ next_state[22];
        next_state[30] = next_state[0] ^ next_state[3] ^ next_state[6] ^ next_state[14] ^ next_state[19] ^ next_state[21];
        next_state[31] = next_state[1] ^ next_state[4] ^ next_state[7] ^ next_state[15] ^ next_state[20] ^ next_state[22];
        next_lfsr_state = next_state;
    end
endfunction

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        // Reset temporary logicisters
        {temp_Data_by_0, temp_Data_by_1, temp_Data_by_2, temp_Data_by_3, temp_Data_by_4, temp_Data_by_5, temp_Data_by_6, temp_Data_by_7,
         temp_Data_by_8, temp_Data_by_9, temp_Data_by_10, temp_Data_by_11, temp_Data_by_12, temp_Data_by_13, temp_Data_by_14, temp_Data_by_15} <= 0;
        // Reset output logicisters
        
        {o_final_gene_0, o_final_gene_1, o_final_gene_2, o_final_gene_3, o_final_gene_4, o_final_gene_5, o_final_gene_6, o_final_gene_7,
         o_final_gene_8, o_final_gene_9, o_final_gene_10, o_final_gene_11, o_final_gene_12, o_final_gene_13, o_final_gene_14, o_final_gene_15} <= 0;
               
        // Initialize LFSR logicisters with predefined seeds
        rx_lfsr_lane_0  <= 23'h1DBFBC; rx_lfsr_lane_1  <= 23'h0607BB; rx_lfsr_lane_2  <= 23'h1EC760; rx_lfsr_lane_3  <= 23'h18C0DB;
        rx_lfsr_lane_4  <= 23'h010F12; rx_lfsr_lane_5  <= 23'h19CFC9; rx_lfsr_lane_6  <= 23'h0277CE; rx_lfsr_lane_7  <= 23'h1BB807;

        i_enable_pattern_comp <= 0;

        //--------------------------- lane 0 -----------------------------------//
            o_lane_0_23[8] <= seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ 
                              seed_0[7]  ^ seed_0[4]  ^ seed_0[1];

            o_lane_0_23[7] <= seed_0[21] ^ seed_0[19] ^ seed_0[14] ^ 
                              seed_0[6]  ^ seed_0[3]  ^ seed_0[0];

            o_lane_0_23[6] <= seed_0[20] ^ seed_0[18] ^ seed_0[13] ^ 
                              seed_0[5]  ^ seed_0[2]  ^ seed_0[22] ^ seed_0[20] ^
                              seed_0[15] ^ seed_0[7]  ^  seed_0[4] ^ 
                              seed_0[1];

            o_lane_0_23[5] <= seed_0[19] ^ seed_0[17] ^ seed_0[12] ^ seed_0[4]  ^ 
                              seed_0[1]  ^ seed_0[21] ^ seed_0[19] ^ seed_0[14] ^
                              seed_0[6]  ^  seed_0[3] ^ seed_0[0];
            o_lane_0_23[4] <= seed_0[18] ^ seed_0[16] ^ seed_0[11] ^ 
                              seed_0[3]  ^ seed_0[0]  ^ seed_0[20] ^ seed_0[18] ^
                              seed_0[13] ^ seed_0[5]  ^ seed_0[2]  ^ seed_0[22] ^
                              seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^
                              seed_0[4]  ^ seed_0[1];

            o_lane_0_23[3] <= seed_0[17] ^ seed_0[15] ^ seed_0[10] ^ seed_0[0]  ^
                              seed_0[2]  ^ seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ 
                              seed_0[7]  ^ seed_0[4]  ^ seed_0[1]  ^ seed_0[19] ^
                              seed_0[17] ^ seed_0[12] ^ seed_0[4]  ^ seed_0[1]  ^ 
                              seed_0[21] ^ seed_0[19] ^ seed_0[14] ^ seed_0[6]  ^
                              seed_0[3]  ;

            o_lane_0_23[2] <= seed_0[16] ^ seed_0[14] ^ seed_0[9]  ^ seed_0[1]  ^
                              seed_0[21] ^ seed_0[19] ^ seed_0[14] ^ seed_0[6]  ^
                              seed_0[3]  ^ seed_0[0]  ^ seed_0[18] ^ seed_0[16] ^ 
                              seed_0[11] ^ seed_0[3]  ^ seed_0[0]  ^ seed_0[20] ^
                              seed_0[18] ^ seed_0[13] ^ seed_0[5]  ^ seed_0[2]  ^
                              seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^
                              seed_0[4]  ^ seed_0[1] ;
            o_lane_0_23[1] <= seed_0[15] ^ seed_0[13] ^ seed_0[8]  ^  seed_0[0] ^
                              seed_0[0]  ^ seed_0[20] ^ seed_0[18] ^ seed_0[13] ^
                              seed_0[5]  ^ seed_0[2]  ^ seed_0[22] ^ seed_0[20] ^ 
                              seed_0[15] ^ seed_0[7]  ^ seed_0[4]  ^ seed_0[1]  ^
                              seed_0[17] ^ seed_0[15] ^ seed_0[10] ^ seed_0[2]  ^  
                              seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^ 
                              seed_0[4]  ^ seed_0[1]  ^ seed_0[19] ^ seed_0[17] ^ 
                              seed_0[12] ^ seed_0[4]  ^ seed_0[1]  ^ seed_0[21] ^
                              seed_0[19] ^ seed_0[14] ^ seed_0[6]  ^ seed_0[3]  ;
                              
            o_lane_0_23[0] <= seed_0[14] ^ seed_0[12] ^ seed_0[7]  ^ seed_0[22] ^
                              seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^ seed_0[4]  ^ 
                              seed_0[1]  ^ seed_0[19] ^ seed_0[17] ^ seed_0[12] ^
                              seed_0[4]  ^ seed_0[1]  ^ seed_0[21] ^ seed_0[19] ^
                              seed_0[14] ^ seed_0[6]  ^ seed_0[3]  ^ seed_0[0]  ^
                              seed_0[16] ^ seed_0[14] ^ seed_0[9]  ^ seed_0[1]  ^
                              seed_0[21] ^ seed_0[19] ^ seed_0[14] ^ seed_0[6]  ^ 
                              seed_0[3]  ^ seed_0[0]  ^ seed_0[18] ^ seed_0[16] ^
                              seed_0[11] ^ seed_0[3]  ^ seed_0[0]  ^ seed_0[20] ^
                              seed_0[18] ^ seed_0[13] ^ seed_0[5]  ^ seed_0[2]  ^
                              seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^
                              seed_0[4]  ^ seed_0[1]  ; 

        //--------------------------- lane 1 -----------------------------------//
            o_lane_1_23[8] <= seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ 
                              seed_1[7]  ^ seed_1[4]  ^ seed_1[1];

            o_lane_1_23[7] <= seed_1[21] ^ seed_1[19] ^ seed_1[14] ^ 
                              seed_1[6]  ^ seed_1[3]  ^ seed_1[0];

            o_lane_1_23[6] <= seed_1[20] ^ seed_1[18] ^ seed_1[13] ^ 
                              seed_1[5]  ^ seed_1[2]  ^ seed_1[22] ^ seed_1[20] ^
                              seed_1[15] ^ seed_1[7]  ^  seed_1[4] ^ 
                              seed_1[1];

            o_lane_1_23[5] <= seed_1[19] ^ seed_1[17] ^ seed_1[12] ^ seed_1[4]  ^ 
                              seed_1[1]  ^ seed_1[21] ^ seed_1[19] ^ seed_1[14] ^
                              seed_1[6]  ^  seed_1[3] ^ seed_1[0];
            o_lane_1_23[4] <= seed_1[18] ^ seed_1[16] ^ seed_1[11] ^ 
                              seed_1[3]  ^ seed_1[0]  ^ seed_1[20] ^ seed_1[18] ^
                              seed_1[13] ^ seed_1[5]  ^ seed_1[2]  ^ seed_1[22] ^
                              seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^
                              seed_1[4]  ^ seed_1[1];
            o_lane_1_23[3] <= seed_1[17] ^ seed_1[15] ^ seed_1[10] ^ seed_1[0]  ^
                              seed_1[2]  ^ seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ 
                              seed_1[7]  ^ seed_1[4]  ^ seed_1[1]  ^ seed_1[19] ^
                              seed_1[17] ^ seed_1[12] ^ seed_1[4]  ^ seed_1[1]  ^ 
                              seed_1[21] ^ seed_1[19] ^ seed_1[14] ^ seed_1[6]  ^
                              seed_1[3]  ;

            o_lane_1_23[2] <= seed_1[16] ^ seed_1[14] ^ seed_1[9]  ^ seed_1[1]  ^
                              seed_1[21] ^ seed_1[19] ^ seed_1[14] ^ seed_1[6]  ^
                              seed_1[3]  ^ seed_1[0]  ^ seed_1[18] ^ seed_1[16] ^ 
                              seed_1[11] ^ seed_1[3]  ^ seed_1[0]  ^ seed_1[20] ^
                              seed_1[18] ^ seed_1[13] ^ seed_1[5]  ^ seed_1[2]  ^
                              seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^
                              seed_1[4]  ^ seed_1[1] ;

            o_lane_1_23[1] <= seed_1[15] ^ seed_1[13] ^ seed_1[8]  ^  seed_1[0] ^
                              seed_1[0]  ^ seed_1[20] ^ seed_1[18] ^ seed_1[13] ^
                              seed_1[5]  ^ seed_1[2]  ^ seed_1[22] ^ seed_1[20] ^ 
                              seed_1[15] ^ seed_1[7]  ^ seed_1[4]  ^ seed_1[1]  ^
                              seed_1[17] ^ seed_1[15] ^ seed_1[10] ^ seed_1[2]  ^  
                              seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^ 
                              seed_1[4]  ^ seed_1[1]  ^ seed_1[19] ^ seed_1[17] ^ 
                              seed_1[12] ^ seed_1[4]  ^ seed_1[1]  ^ seed_1[21] ^
                              seed_1[19] ^ seed_1[14] ^ seed_1[6]  ^ seed_1[3]  ;
                              
            o_lane_1_23[0] <= seed_1[14] ^ seed_1[12] ^ seed_1[7]  ^ seed_1[22] ^
                              seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^ seed_1[4]  ^ 
                              seed_1[1]  ^ seed_1[19] ^ seed_1[17] ^ seed_1[12] ^
                              seed_1[4]  ^ seed_1[1]  ^ seed_1[21] ^ seed_1[19] ^
                              seed_1[14] ^ seed_1[6]  ^ seed_1[3]  ^ seed_1[0]  ^
                              seed_1[16] ^ seed_1[14] ^ seed_1[9]  ^ seed_1[1]  ^
                              seed_1[21] ^ seed_1[19] ^ seed_1[14] ^ seed_1[6]  ^ 
                              seed_1[3]  ^ seed_1[0]  ^ seed_1[18] ^ seed_1[16] ^
                              seed_1[11] ^ seed_1[3]  ^ seed_1[0]  ^ seed_1[20] ^
                              seed_1[18] ^ seed_1[13] ^ seed_1[5]  ^ seed_1[2]  ^
                              seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^
                              seed_1[4]  ^ seed_1[1]  ;  

        //--------------------------- lane 2 -----------------------------------//
            o_lane_2_23[8] <= seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ 
                              seed_2[7]  ^ seed_2[4]  ^ seed_2[1];

            o_lane_2_23[7] <= seed_2[21] ^ seed_2[19] ^ seed_2[14] ^ 
                              seed_2[6]  ^ seed_2[3]  ^ seed_2[0];

            o_lane_2_23[6] <= seed_2[20] ^ seed_2[18] ^ seed_2[13] ^ 
                              seed_2[5]  ^ seed_2[2]  ^ seed_2[22] ^ seed_2[20] ^
                              seed_2[15] ^ seed_2[7]  ^  seed_2[4] ^ 
                              seed_2[1];

            o_lane_2_23[5] <= seed_2[19] ^ seed_2[17] ^ seed_2[12] ^ seed_2[4]  ^ 
                              seed_2[1]  ^ seed_2[21] ^ seed_2[19] ^ seed_2[14] ^
                              seed_2[6]  ^  seed_2[3] ^ seed_2[0];
            o_lane_2_23[4] <= seed_2[18] ^ seed_2[16] ^ seed_2[11] ^ 
                              seed_2[3]  ^ seed_2[0]  ^ seed_2[20] ^ seed_2[18] ^
                              seed_2[13] ^ seed_2[5]  ^ seed_2[2]  ^ seed_2[22] ^
                              seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^
                              seed_2[4]  ^ seed_2[1];

            o_lane_2_23[3] <= seed_2[17] ^ seed_2[15] ^ seed_2[10] ^ seed_2[0]  ^
                              seed_2[2]  ^ seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ 
                              seed_2[7]  ^ seed_2[4]  ^ seed_2[1]  ^ seed_2[19] ^
                              seed_2[17] ^ seed_2[12] ^ seed_2[4]  ^ seed_2[1]  ^ 
                              seed_2[21] ^ seed_2[19] ^ seed_2[14] ^ seed_2[6]  ^
                              seed_2[3]  ;

            o_lane_2_23[2] <= seed_2[16] ^ seed_2[14] ^ seed_2[9]  ^ seed_2[1]  ^
                              seed_2[21] ^ seed_2[19] ^ seed_2[14] ^ seed_2[6]  ^
                              seed_2[3]  ^ seed_2[0]  ^ seed_2[18] ^ seed_2[16] ^ 
                              seed_2[11] ^ seed_2[3]  ^ seed_2[0]  ^ seed_2[20] ^
                              seed_2[18] ^ seed_2[13] ^ seed_2[5]  ^ seed_2[2]  ^
                              seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^
                              seed_2[4]  ^ seed_2[1] ;

            o_lane_2_23[1] <= seed_2[15] ^ seed_2[13] ^ seed_2[8]  ^  seed_2[0] ^
                              seed_2[0]  ^ seed_2[20] ^ seed_2[18] ^ seed_2[13] ^
                              seed_2[5]  ^ seed_2[2]  ^ seed_2[22] ^ seed_2[20] ^ 
                              seed_2[15] ^ seed_2[7]  ^ seed_2[4]  ^ seed_2[1]  ^
                              seed_2[17] ^ seed_2[15] ^ seed_2[10] ^ seed_2[2]  ^  
                              seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^ 
                              seed_2[4]  ^ seed_2[1]  ^ seed_2[19] ^ seed_2[17] ^ 
                              seed_2[12] ^ seed_2[4]  ^ seed_2[1]  ^ seed_2[21] ^
                              seed_2[19] ^ seed_2[14] ^ seed_2[6]  ^ seed_2[3]  ;
                              
            o_lane_2_23[0] <= seed_2[14] ^ seed_2[12] ^ seed_2[7]  ^ seed_2[22] ^
                              seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^ seed_2[4]  ^ 
                              seed_2[1]  ^ seed_2[19] ^ seed_2[17] ^ seed_2[12] ^
                              seed_2[4]  ^ seed_2[1]  ^ seed_2[21] ^ seed_2[19] ^
                              seed_2[14] ^ seed_2[6]  ^ seed_2[3]  ^ seed_2[0]  ^
                              seed_2[16] ^ seed_2[14] ^ seed_2[9]  ^ seed_2[1]  ^
                              seed_2[21] ^ seed_2[19] ^ seed_2[14] ^ seed_2[6]  ^ 
                              seed_2[3]  ^ seed_2[0]  ^ seed_2[18] ^ seed_2[16] ^
                              seed_2[11] ^ seed_2[3]  ^ seed_2[0]  ^ seed_2[20] ^
                              seed_2[18] ^ seed_2[13] ^ seed_2[5]  ^ seed_2[2]  ^
                              seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^
                              seed_2[4]  ^ seed_2[1]  ; 
            
        //--------------------------- lane 3 -----------------------------------//
          o_lane_3_23[8] <= seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ 
                            seed_3[7]  ^ seed_3[4]  ^ seed_3[1];

          o_lane_3_23[7] <= seed_3[21] ^ seed_3[19] ^ seed_3[14] ^ 
                            seed_3[6]  ^ seed_3[3]  ^ seed_3[0];

          o_lane_3_23[6] <= seed_3[20] ^ seed_3[18] ^ seed_3[13] ^ 
                            seed_3[5]  ^ seed_3[2]  ^ seed_3[22] ^ seed_3[20] ^
                            seed_3[15] ^ seed_3[7]  ^  seed_3[4] ^ 
                            seed_3[1];

          o_lane_3_23[5] <= seed_3[19] ^ seed_3[17] ^ seed_3[12] ^ seed_3[4]  ^ 
                            seed_3[1]  ^ seed_3[21] ^ seed_3[19] ^ seed_3[14] ^
                            seed_3[6]  ^  seed_3[3] ^ seed_3[0];

          o_lane_3_23[4] <= seed_3[18] ^ seed_3[16] ^ seed_3[11] ^ 
                            seed_3[3]  ^ seed_3[0]  ^ seed_3[20] ^ seed_3[18] ^
                            seed_3[13] ^ seed_3[5]  ^ seed_3[2]  ^ seed_3[22] ^
                            seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^
                            seed_3[4]  ^ seed_3[1];

          o_lane_3_23[3] <= seed_3[17] ^ seed_3[15] ^ seed_3[10] ^ seed_3[0]  ^
                            seed_3[2]  ^ seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ 
                            seed_3[7]  ^ seed_3[4]  ^ seed_3[1]  ^ seed_3[19] ^
                            seed_3[17] ^ seed_3[12] ^ seed_3[4]  ^ seed_3[1]  ^ 
                            seed_3[21] ^ seed_3[19] ^ seed_3[14] ^ seed_3[6]  ^
                            seed_3[3]  ;

          o_lane_3_23[2] <= seed_3[16] ^ seed_3[14] ^ seed_3[9]  ^ seed_3[1]  ^
                            seed_3[21] ^ seed_3[19] ^ seed_3[14] ^ seed_3[6]  ^
                            seed_3[3]  ^ seed_3[0]  ^ seed_3[18] ^ seed_3[16] ^ 
                            seed_3[11] ^ seed_3[3]  ^ seed_3[0]  ^ seed_3[20] ^
                            seed_3[18] ^ seed_3[13] ^ seed_3[5]  ^ seed_3[2]  ^
                            seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^
                            seed_3[4]  ^ seed_3[1] ;
          o_lane_3_23[1] <= seed_3[15] ^ seed_3[13] ^ seed_3[8]  ^  seed_3[0] ^
                            seed_3[0]  ^ seed_3[20] ^ seed_3[18] ^ seed_3[13] ^
                            seed_3[5]  ^ seed_3[2]  ^ seed_3[22] ^ seed_3[20] ^ 
                            seed_3[15] ^ seed_3[7]  ^ seed_3[4]  ^ seed_3[1]  ^
                            seed_3[17] ^ seed_3[15] ^ seed_3[10] ^ seed_3[2]  ^  
                            seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^ 
                            seed_3[4]  ^ seed_3[1]  ^ seed_3[19] ^ seed_3[17] ^ 
                            seed_3[12] ^ seed_3[4]  ^ seed_3[1]  ^ seed_3[21] ^
                            seed_3[19] ^ seed_3[14] ^ seed_3[6]  ^ seed_3[3]  ;
                            
          o_lane_3_23[0] <= seed_3[14] ^ seed_3[12] ^ seed_3[7]  ^ seed_3[22] ^
                            seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^ seed_3[4]  ^ 
                            seed_3[1]  ^ seed_3[19] ^ seed_3[17] ^ seed_3[12] ^
                            seed_3[4]  ^ seed_3[1]  ^ seed_3[21] ^ seed_3[19] ^
                            seed_3[14] ^ seed_3[6]  ^ seed_3[3]  ^ seed_3[0]  ^
                            seed_3[16] ^ seed_3[14] ^ seed_3[9]  ^ seed_3[1]  ^
                            seed_3[21] ^ seed_3[19] ^ seed_3[14] ^ seed_3[6]  ^ 
                            seed_3[3]  ^ seed_3[0]  ^ seed_3[18] ^ seed_3[16] ^
                            seed_3[11] ^ seed_3[3]  ^ seed_3[0]  ^ seed_3[20] ^
                            seed_3[18] ^ seed_3[13] ^ seed_3[5]  ^ seed_3[2]  ^
                            seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^
                            seed_3[4]  ^ seed_3[1]  ;

        //--------------------------- lane 4 -----------------------------------//
          o_lane_4_23[8] <= seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ 
                            seed_4[7]  ^ seed_4[4]  ^ seed_4[1];

          o_lane_4_23[7] <= seed_4[21] ^ seed_4[19] ^ seed_4[14] ^ 
                            seed_4[6]  ^ seed_4[3]  ^ seed_4[0];

          o_lane_4_23[6] <= seed_4[20] ^ seed_4[18] ^ seed_4[13] ^ 
                            seed_4[5]  ^ seed_4[2]  ^ seed_4[22] ^ seed_4[20] ^
                            seed_4[15] ^ seed_4[7]  ^  seed_4[4] ^ 
                            seed_4[1];

          o_lane_4_23[5] <= seed_4[19] ^ seed_4[17] ^ seed_4[12] ^ seed_4[4]  ^ 
                            seed_4[1]  ^ seed_4[21] ^ seed_4[19] ^ seed_4[14] ^
                            seed_4[6]  ^  seed_4[3] ^ seed_4[0];
          o_lane_4_23[4] <= seed_4[18] ^ seed_4[16] ^ seed_4[11] ^ 
                            seed_4[3]  ^ seed_4[0]  ^ seed_4[20] ^ seed_4[18] ^
                            seed_4[13] ^ seed_4[5]  ^ seed_4[2]  ^ seed_4[22] ^
                            seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^
                            seed_4[4]  ^ seed_4[1];

          o_lane_4_23[3] <= seed_4[17] ^ seed_4[15] ^ seed_4[10] ^ seed_4[0]  ^
                            seed_4[2]  ^ seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ 
                            seed_4[7]  ^ seed_4[4]  ^ seed_4[1]  ^ seed_4[19] ^
                            seed_4[17] ^ seed_4[12] ^ seed_4[4]  ^ seed_4[1]  ^ 
                            seed_4[21] ^ seed_4[19] ^ seed_4[14] ^ seed_4[6]  ^
                            seed_4[3];

          o_lane_4_23[2] <= seed_4[16] ^ seed_4[14] ^ seed_4[9]  ^ seed_4[1]  ^
                            seed_4[21] ^ seed_4[19] ^ seed_4[14] ^ seed_4[6]  ^
                            seed_4[3]  ^ seed_4[0]  ^ seed_4[18] ^ seed_4[16] ^ 
                            seed_4[11] ^ seed_4[3]  ^ seed_4[0]  ^ seed_4[20] ^
                            seed_4[18] ^ seed_4[13] ^ seed_4[5]  ^ seed_4[2]  ^
                            seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^
                            seed_4[4]  ^ seed_4[1];

          o_lane_4_23[1] <= seed_4[15] ^ seed_4[13] ^ seed_4[8]  ^  seed_4[0] ^
                            seed_4[0]  ^ seed_4[20] ^ seed_4[18] ^ seed_4[13] ^
                            seed_4[5]  ^ seed_4[2]  ^ seed_4[22] ^ seed_4[20] ^ 
                            seed_4[15] ^ seed_4[7]  ^ seed_4[4]  ^ seed_4[1]  ^
                            seed_4[17] ^ seed_4[15] ^ seed_4[10] ^ seed_4[2]  ^  
                            seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^ 
                            seed_4[4]  ^ seed_4[1]  ^ seed_4[19] ^ seed_4[17] ^ 
                            seed_4[12] ^ seed_4[4]  ^ seed_4[1]  ^ seed_4[21] ^
                            seed_4[19] ^ seed_4[14] ^ seed_4[6]  ^ seed_4[3];
                            
          o_lane_4_23[0] <= seed_4[14] ^ seed_4[12] ^ seed_4[7]  ^ seed_4[22] ^
                            seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^ seed_4[4]  ^ 
                            seed_4[1]  ^ seed_4[19] ^ seed_4[17] ^ seed_4[12] ^
                            seed_4[4]  ^ seed_4[1]  ^ seed_4[21] ^ seed_4[19] ^
                            seed_4[14] ^ seed_4[6]  ^ seed_4[3]  ^ seed_4[0]  ^
                            seed_4[16] ^ seed_4[14] ^ seed_4[9]  ^ seed_4[1]  ^
                            seed_4[21] ^ seed_4[19] ^ seed_4[14] ^ seed_4[6]  ^ 
                            seed_4[3]  ^ seed_4[0]  ^ seed_4[18] ^ seed_4[16] ^
                            seed_4[11] ^ seed_4[3]  ^ seed_4[0]  ^ seed_4[20] ^
                            seed_4[18] ^ seed_4[13] ^ seed_4[5]  ^ seed_4[2]  ^
                            seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^
                            seed_4[4]  ^ seed_4[1]; 

        //--------------------------- lane 5 -----------------------------------//
            o_lane_5_23[8] <= seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ 
                              seed_5[7]  ^ seed_5[4]  ^ seed_5[1];

            o_lane_5_23[7] <= seed_5[21] ^ seed_5[19] ^ seed_5[14] ^ 
                              seed_5[6]  ^ seed_5[3]  ^ seed_5[0];

            o_lane_5_23[6] <= seed_5[20] ^ seed_5[18] ^ seed_5[13] ^ 
                              seed_5[5]  ^ seed_5[2]  ^ seed_5[22] ^ seed_5[20] ^
                              seed_5[15] ^ seed_5[7]  ^  seed_5[4] ^ 
                              seed_5[1];

            o_lane_5_23[5] <= seed_5[19] ^ seed_5[17] ^ seed_5[12] ^ seed_5[4]  ^ 
                              seed_5[1]  ^ seed_5[21] ^ seed_5[19] ^ seed_5[14] ^
                              seed_5[6]  ^  seed_5[3] ^ seed_5[0];

            o_lane_5_23[4] <= seed_5[18] ^ seed_5[16] ^ seed_5[11] ^ 
                              seed_5[3]  ^ seed_5[0]  ^ seed_5[20] ^ seed_5[18] ^
                              seed_5[13] ^ seed_5[5]  ^ seed_5[2]  ^ seed_5[22] ^
                              seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^
                              seed_5[4]  ^ seed_5[1];

            o_lane_5_23[3] <= seed_5[17] ^ seed_5[15] ^ seed_5[10] ^ seed_5[0]  ^
                              seed_5[2]  ^ seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ 
                              seed_5[7]  ^ seed_5[4]  ^ seed_5[1]  ^ seed_5[19] ^
                              seed_5[17] ^ seed_5[12] ^ seed_5[4]  ^ seed_5[1]  ^ 
                              seed_5[21] ^ seed_5[19] ^ seed_5[14] ^ seed_5[6]  ^
                              seed_5[3]  ;

            o_lane_5_23[2] <= seed_5[16] ^ seed_5[14] ^ seed_5[9]  ^ seed_5[1]  ^
                              seed_5[21] ^ seed_5[19] ^ seed_5[14] ^ seed_5[6]  ^
                              seed_5[3]  ^ seed_5[0]  ^ seed_5[18] ^ seed_5[16] ^ 
                              seed_5[11] ^ seed_5[3]  ^ seed_5[0]  ^ seed_5[20] ^
                              seed_5[18] ^ seed_5[13] ^ seed_5[5]  ^ seed_5[2]  ^
                              seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^
                              seed_5[4]  ^ seed_5[1] ;

            o_lane_5_23[1] <= seed_5[15] ^ seed_5[13] ^ seed_5[8]  ^  seed_5[0] ^
                              seed_5[0]  ^ seed_5[20] ^ seed_5[18] ^ seed_5[13] ^
                              seed_5[5]  ^ seed_5[2]  ^ seed_5[22] ^ seed_5[20] ^ 
                              seed_5[15] ^ seed_5[7]  ^ seed_5[4]  ^ seed_5[1]  ^
                              seed_5[17] ^ seed_5[15] ^ seed_5[10] ^ seed_5[2]  ^  
                              seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^ 
                              seed_5[4]  ^ seed_5[1]  ^ seed_5[19] ^ seed_5[17] ^ 
                              seed_5[12] ^ seed_5[4]  ^ seed_5[1]  ^ seed_5[21] ^
                              seed_5[19] ^ seed_5[14] ^ seed_5[6]  ^ seed_5[3]  ;
                              
            o_lane_5_23[0] <= seed_5[14] ^ seed_5[12] ^ seed_5[7]  ^ seed_5[22] ^
                              seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^ seed_5[4]  ^ 
                              seed_5[1]  ^ seed_5[19] ^ seed_5[17] ^ seed_5[12] ^
                              seed_5[4]  ^ seed_5[1]  ^ seed_5[21] ^ seed_5[19] ^
                              seed_5[14] ^ seed_5[6]  ^ seed_5[3]  ^ seed_5[0]  ^
                              seed_5[16] ^ seed_5[14] ^ seed_5[9]  ^ seed_5[1]  ^
                              seed_5[21] ^ seed_5[19] ^ seed_5[14] ^ seed_5[6]  ^ 
                              seed_5[3]  ^ seed_5[0]  ^ seed_5[18] ^ seed_5[16] ^
                              seed_5[11] ^ seed_5[3]  ^ seed_5[0]  ^ seed_5[20] ^
                              seed_5[18] ^ seed_5[13] ^ seed_5[5]  ^ seed_5[2]  ^
                              seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^
                              seed_5[4]  ^ seed_5[1]  ; 

        //--------------------------- lane 6 -----------------------------------//
          o_lane_6_23[8] <= seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ 
                            seed_6[7]  ^ seed_6[4]  ^ seed_6[1];

          o_lane_6_23[7] <= seed_6[21] ^ seed_6[19] ^ seed_6[14] ^ 
                            seed_6[6]  ^ seed_6[3]  ^ seed_6[0];

          o_lane_6_23[6] <= seed_6[20] ^ seed_6[18] ^ seed_6[13] ^ 
                            seed_6[5]  ^ seed_6[2]  ^ seed_6[22] ^ seed_6[20] ^
                            seed_6[15] ^ seed_6[7]  ^  seed_6[4] ^ 
                            seed_6[1];

          o_lane_6_23[5] <= seed_6[19] ^ seed_6[17] ^ seed_6[12] ^ seed_6[4]  ^ 
                            seed_6[1]  ^ seed_6[21] ^ seed_6[19] ^ seed_6[14] ^
                            seed_6[6]  ^  seed_6[3] ^ seed_6[0];

          o_lane_6_23[4] <= seed_6[18] ^ seed_6[16] ^ seed_6[11] ^ 
                            seed_6[3]  ^ seed_6[0]  ^ seed_6[20] ^ seed_6[18] ^
                            seed_6[13] ^ seed_6[5]  ^ seed_6[2]  ^ seed_6[22] ^
                            seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^
                            seed_6[4]  ^ seed_6[1];

          o_lane_6_23[3] <= seed_6[17] ^ seed_6[15] ^ seed_6[10] ^ seed_6[0]  ^
                            seed_6[2]  ^ seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ 
                            seed_6[7]  ^ seed_6[4]  ^ seed_6[1]  ^ seed_6[19] ^
                            seed_6[17] ^ seed_6[12] ^ seed_6[4]  ^ seed_6[1]  ^ 
                            seed_6[21] ^ seed_6[19] ^ seed_6[14] ^ seed_6[6]  ^
                            seed_6[3] ;
          o_lane_6_23[2] <= seed_6[16] ^ seed_6[14] ^ seed_6[9]  ^ seed_6[1]  ^
                            seed_6[21] ^ seed_6[19] ^ seed_6[14] ^ seed_6[6]  ^
                            seed_6[3]  ^ seed_6[0]  ^ seed_6[18] ^ seed_6[16] ^ 
                            seed_6[11] ^ seed_6[3]  ^ seed_6[0]  ^ seed_6[20] ^
                            seed_6[18] ^ seed_6[13] ^ seed_6[5]  ^ seed_6[2]  ^
                            seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^
                            seed_6[4]  ^ seed_6[1];

          o_lane_6_23[1] <= seed_6[15] ^ seed_6[13] ^ seed_6[8]  ^  seed_6[0] ^
                            seed_6[0]  ^ seed_6[20] ^ seed_6[18] ^ seed_6[13] ^
                            seed_6[5]  ^ seed_6[2]  ^ seed_6[22] ^ seed_6[20] ^ 
                            seed_6[15] ^ seed_6[7]  ^ seed_6[4]  ^ seed_6[1]  ^
                            seed_6[17] ^ seed_6[15] ^ seed_6[10] ^ seed_6[2]  ^  
                            seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^ 
                            seed_6[4]  ^ seed_6[1]  ^ seed_6[19] ^ seed_6[17] ^ 
                            seed_6[12] ^ seed_6[4]  ^ seed_6[1]  ^ seed_6[21] ^
                            seed_6[19] ^ seed_6[14] ^ seed_6[6]  ^ seed_6[3];
                            
          o_lane_6_23[0] <= seed_6[14] ^ seed_6[12] ^ seed_6[7]  ^ seed_6[22] ^
                            seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^ seed_6[4]  ^ 
                            seed_6[1]  ^ seed_6[19] ^ seed_6[17] ^ seed_6[12] ^
                            seed_6[4]  ^ seed_6[1]  ^ seed_6[21] ^ seed_6[19] ^
                            seed_6[14] ^ seed_6[6]  ^ seed_6[3]  ^ seed_6[0]  ^
                            seed_6[16] ^ seed_6[14] ^ seed_6[9]  ^ seed_6[1]  ^
                            seed_6[21] ^ seed_6[19] ^ seed_6[14] ^ seed_6[6]  ^ 
                            seed_6[3]  ^ seed_6[0]  ^ seed_6[18] ^ seed_6[16] ^
                            seed_6[11] ^ seed_6[3]  ^ seed_6[0]  ^ seed_6[20] ^
                            seed_6[18] ^ seed_6[13] ^ seed_6[5]  ^ seed_6[2]  ^
                            seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^
                            seed_6[4]  ^ seed_6[1]; 

        //--------------------------- lane 7 -----------------------------------//
            o_lane_7_23[8] <= seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ 
                              seed_7[7]  ^ seed_7[4]  ^ seed_7[1];

            o_lane_7_23[7] <= seed_7[21] ^ seed_7[19] ^ seed_7[14] ^ 
                              seed_7[6]  ^ seed_7[3]  ^ seed_7[0];

            o_lane_7_23[6] <= seed_7[20] ^ seed_7[18] ^ seed_7[13] ^ 
                              seed_7[5]  ^ seed_7[2]  ^ seed_7[22] ^ seed_7[20] ^
                              seed_7[15] ^ seed_7[7]  ^  seed_7[4] ^ 
                              seed_7[1];

            o_lane_7_23[5] <= seed_7[19] ^ seed_7[17] ^ seed_7[12] ^ seed_7[4]  ^ 
                              seed_7[1]  ^ seed_7[21] ^ seed_7[19] ^ seed_7[14] ^
                              seed_7[6]  ^  seed_7[3] ^ seed_7[0];
            o_lane_7_23[4] <= seed_7[18] ^ seed_7[16] ^ seed_7[11] ^ 
                              seed_7[3]  ^ seed_7[0]  ^ seed_7[20] ^ seed_7[18] ^
                              seed_7[13] ^ seed_7[5]  ^ seed_7[2]  ^ seed_7[22] ^
                              seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^
                              seed_7[4]  ^ seed_7[1];

            o_lane_7_23[3] <= seed_7[17] ^ seed_7[15] ^ seed_7[10] ^ seed_7[0]  ^
                              seed_7[2]  ^ seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ 
                              seed_7[7]  ^ seed_7[4]  ^ seed_7[1]  ^ seed_7[19] ^
                              seed_7[17] ^ seed_7[12] ^ seed_7[4]  ^ seed_7[1]  ^ 
                              seed_7[21] ^ seed_7[19] ^ seed_7[14] ^ seed_7[6]  ^
                              seed_7[3];

            o_lane_7_23[2] <= seed_7[16] ^ seed_7[14] ^ seed_7[9]  ^ seed_7[1]  ^
                              seed_7[21] ^ seed_7[19] ^ seed_7[14] ^ seed_7[6]  ^
                              seed_7[3]  ^ seed_7[0]  ^ seed_7[18] ^ seed_7[16] ^ 
                              seed_7[11] ^ seed_7[3]  ^ seed_7[0]  ^ seed_7[20] ^
                              seed_7[18] ^ seed_7[13] ^ seed_7[5]  ^ seed_7[2]  ^
                              seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^
                              seed_7[4]  ^ seed_7[1];

            o_lane_7_23[1] <= seed_7[15] ^ seed_7[13] ^ seed_7[8]  ^  seed_7[0] ^
                              seed_7[0]  ^ seed_7[20] ^ seed_7[18] ^ seed_7[13] ^
                              seed_7[5]  ^ seed_7[2]  ^ seed_7[22] ^ seed_7[20] ^ 
                              seed_7[15] ^ seed_7[7]  ^ seed_7[4]  ^ seed_7[1]  ^
                              seed_7[17] ^ seed_7[15] ^ seed_7[10] ^ seed_7[2]  ^  
                              seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^ 
                              seed_7[4]  ^ seed_7[1]  ^ seed_7[19] ^ seed_7[17] ^ 
                              seed_7[12] ^ seed_7[4]  ^ seed_7[1]  ^ seed_7[21] ^
                              seed_7[19] ^ seed_7[14] ^ seed_7[6]  ^ seed_7[3];
                              
            o_lane_7_23[0] <= seed_7[14] ^ seed_7[12] ^ seed_7[7]  ^ seed_7[22] ^
                              seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^ seed_7[4]  ^ 
                              seed_7[1]  ^ seed_7[19] ^ seed_7[17] ^ seed_7[12] ^
                              seed_7[4]  ^ seed_7[1]  ^ seed_7[21] ^ seed_7[19] ^
                              seed_7[14] ^ seed_7[6]  ^ seed_7[3]  ^ seed_7[0]  ^
                              seed_7[16] ^ seed_7[14] ^ seed_7[9]  ^ seed_7[1]  ^
                              seed_7[21] ^ seed_7[19] ^ seed_7[14] ^ seed_7[6]  ^ 
                              seed_7[3]  ^ seed_7[0]  ^ seed_7[18] ^ seed_7[16] ^
                              seed_7[11] ^ seed_7[3]  ^ seed_7[0]  ^ seed_7[20] ^
                              seed_7[18] ^ seed_7[13] ^ seed_7[5]  ^ seed_7[2]  ^
                              seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^
                              seed_7[4]  ^ seed_7[1]; 

    end
    else begin  
        {o_final_gene_0, o_final_gene_1, o_final_gene_2, o_final_gene_3, o_final_gene_4, o_final_gene_5, o_final_gene_6, o_final_gene_7,
         o_final_gene_8, o_final_gene_9, o_final_gene_10, o_final_gene_11, o_final_gene_12, o_final_gene_13, o_final_gene_14, o_final_gene_15} <= 0;

        case (i_state)
            IDLE: begin
                temp_Data_by_0  <= i_data_in_0;   temp_Data_by_1 <= i_data_in_1; temp_Data_by_2 <= i_data_in_2; temp_Data_by_3 <= i_data_in_3;
                temp_Data_by_4  <= i_data_in_4;   temp_Data_by_5 <= i_data_in_5; temp_Data_by_6 <= i_data_in_6; temp_Data_by_7 <= i_data_in_7;
                temp_Data_by_8  <= i_data_in_8;   temp_Data_by_9 <= i_data_in_9; temp_Data_by_10 <= i_data_in_10; temp_Data_by_11 <= i_data_in_11;
                temp_Data_by_12 <= i_data_in_12; temp_Data_by_13 <= i_data_in_13; temp_Data_by_14 <= i_data_in_14; temp_Data_by_15 <= i_data_in_15;
            end

            CLEAR_LFSR: begin
                // Reset LFSR logicisters to initial seeds
                rx_lfsr_lane_0  <= 23'h1DBFBC; rx_lfsr_lane_1  <= 23'h0607BB; rx_lfsr_lane_2  <= 23'h1EC760; rx_lfsr_lane_3  <= 23'h18C0DB;
                rx_lfsr_lane_4  <= 23'h010F12; rx_lfsr_lane_5  <= 23'h19CFC9; rx_lfsr_lane_6  <= 23'h0277CE; rx_lfsr_lane_7  <= 23'h1BB807;
                 temp_Data_by_0 <= i_data_in_0; temp_Data_by_1 <= i_data_in_1; temp_Data_by_2 <= i_data_in_2; temp_Data_by_3 <= i_data_in_3;
                        temp_Data_by_4 <= i_data_in_4; temp_Data_by_5 <= i_data_in_5; temp_Data_by_6 <= i_data_in_6; temp_Data_by_7 <= i_data_in_7;
                        temp_Data_by_8 <= i_data_in_8; temp_Data_by_9 <= i_data_in_9; temp_Data_by_10 <= i_data_in_10; temp_Data_by_11 <= i_data_in_11;
                        temp_Data_by_12 <= i_data_in_12; temp_Data_by_13 <= i_data_in_13; temp_Data_by_14 <= i_data_in_14; temp_Data_by_15 <= i_data_in_15;

                //--------------------------- lane 0 -----------------------------------//
                    o_lane_0_23[8] <= seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ 
                                      seed_0[7]  ^ seed_0[4]  ^ seed_0[1];

                    o_lane_0_23[7] <= seed_0[21] ^ seed_0[19] ^ seed_0[14] ^ 
                                      seed_0[6]  ^ seed_0[3]  ^ seed_0[0];

                    o_lane_0_23[6] <= seed_0[20] ^ seed_0[18] ^ seed_0[13] ^ 
                                      seed_0[5]  ^ seed_0[2]  ^ seed_0[22] ^ seed_0[20] ^
                                      seed_0[15] ^ seed_0[7]  ^  seed_0[4] ^ 
                                      seed_0[1];

                    o_lane_0_23[5] <= seed_0[19] ^ seed_0[17] ^ seed_0[12] ^ seed_0[4]  ^ 
                                      seed_0[1]  ^ seed_0[21] ^ seed_0[19] ^ seed_0[14] ^
                                      seed_0[6]  ^  seed_0[3] ^ seed_0[0];
                    o_lane_0_23[4] <= seed_0[18] ^ seed_0[16] ^ seed_0[11] ^ 
                                      seed_0[3]  ^ seed_0[0]  ^ seed_0[20] ^ seed_0[18] ^
                                      seed_0[13] ^ seed_0[5]  ^ seed_0[2]  ^ seed_0[22] ^
                                      seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^
                                      seed_0[4]  ^ seed_0[1];

                    o_lane_0_23[3] <= seed_0[17] ^ seed_0[15] ^ seed_0[10] ^ seed_0[0]  ^
                                      seed_0[2]  ^ seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ 
                                      seed_0[7]  ^ seed_0[4]  ^ seed_0[1]  ^ seed_0[19] ^
                                      seed_0[17] ^ seed_0[12] ^ seed_0[4]  ^ seed_0[1]  ^ 
                                      seed_0[21] ^ seed_0[19] ^ seed_0[14] ^ seed_0[6]  ^
                                      seed_0[3]  ;

                    o_lane_0_23[2] <= seed_0[16] ^ seed_0[14] ^ seed_0[9]  ^ seed_0[1]  ^
                                      seed_0[21] ^ seed_0[19] ^ seed_0[14] ^ seed_0[6]  ^
                                      seed_0[3]  ^ seed_0[0]  ^ seed_0[18] ^ seed_0[16] ^ 
                                      seed_0[11] ^ seed_0[3]  ^ seed_0[0]  ^ seed_0[20] ^
                                      seed_0[18] ^ seed_0[13] ^ seed_0[5]  ^ seed_0[2]  ^
                                      seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^
                                      seed_0[4]  ^ seed_0[1] ;
                    o_lane_0_23[1] <= seed_0[15] ^ seed_0[13] ^ seed_0[8]  ^  seed_0[0] ^
                                      seed_0[0]  ^ seed_0[20] ^ seed_0[18] ^ seed_0[13] ^
                                      seed_0[5]  ^ seed_0[2]  ^ seed_0[22] ^ seed_0[20] ^ 
                                      seed_0[15] ^ seed_0[7]  ^ seed_0[4]  ^ seed_0[1]  ^
                                      seed_0[17] ^ seed_0[15] ^ seed_0[10] ^ seed_0[2]  ^  
                                      seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^ 
                                      seed_0[4]  ^ seed_0[1]  ^ seed_0[19] ^ seed_0[17] ^ 
                                      seed_0[12] ^ seed_0[4]  ^ seed_0[1]  ^ seed_0[21] ^
                                      seed_0[19] ^ seed_0[14] ^ seed_0[6]  ^ seed_0[3]  ;
                                      
                    o_lane_0_23[0] <= seed_0[14] ^ seed_0[12] ^ seed_0[7]  ^ seed_0[22] ^
                                      seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^ seed_0[4]  ^ 
                                      seed_0[1]  ^ seed_0[19] ^ seed_0[17] ^ seed_0[12] ^
                                      seed_0[4]  ^ seed_0[1]  ^ seed_0[21] ^ seed_0[19] ^
                                      seed_0[14] ^ seed_0[6]  ^ seed_0[3]  ^ seed_0[0]  ^
                                      seed_0[16] ^ seed_0[14] ^ seed_0[9]  ^ seed_0[1]  ^
                                      seed_0[21] ^ seed_0[19] ^ seed_0[14] ^ seed_0[6]  ^ 
                                      seed_0[3]  ^ seed_0[0]  ^ seed_0[18] ^ seed_0[16] ^
                                      seed_0[11] ^ seed_0[3]  ^ seed_0[0]  ^ seed_0[20] ^
                                      seed_0[18] ^ seed_0[13] ^ seed_0[5]  ^ seed_0[2]  ^
                                      seed_0[22] ^ seed_0[20] ^ seed_0[15] ^ seed_0[7]  ^
                                      seed_0[4]  ^ seed_0[1]  ; 

                //--------------------------- lane 1 -----------------------------------//
                    o_lane_1_23[8] <= seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ 
                                      seed_1[7]  ^ seed_1[4]  ^ seed_1[1];

                    o_lane_1_23[7] <= seed_1[21] ^ seed_1[19] ^ seed_1[14] ^ 
                                      seed_1[6]  ^ seed_1[3]  ^ seed_1[0];

                    o_lane_1_23[6] <= seed_1[20] ^ seed_1[18] ^ seed_1[13] ^ 
                                      seed_1[5]  ^ seed_1[2]  ^ seed_1[22] ^ seed_1[20] ^
                                      seed_1[15] ^ seed_1[7]  ^  seed_1[4] ^ 
                                      seed_1[1];

                    o_lane_1_23[5] <= seed_1[19] ^ seed_1[17] ^ seed_1[12] ^ seed_1[4]  ^ 
                                      seed_1[1]  ^ seed_1[21] ^ seed_1[19] ^ seed_1[14] ^
                                      seed_1[6]  ^  seed_1[3] ^ seed_1[0];
                    o_lane_1_23[4] <= seed_1[18] ^ seed_1[16] ^ seed_1[11] ^ 
                                      seed_1[3]  ^ seed_1[0]  ^ seed_1[20] ^ seed_1[18] ^
                                      seed_1[13] ^ seed_1[5]  ^ seed_1[2]  ^ seed_1[22] ^
                                      seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^
                                      seed_1[4]  ^ seed_1[1];
                    o_lane_1_23[3] <= seed_1[17] ^ seed_1[15] ^ seed_1[10] ^ seed_1[0]  ^
                                      seed_1[2]  ^ seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ 
                                      seed_1[7]  ^ seed_1[4]  ^ seed_1[1]  ^ seed_1[19] ^
                                      seed_1[17] ^ seed_1[12] ^ seed_1[4]  ^ seed_1[1]  ^ 
                                      seed_1[21] ^ seed_1[19] ^ seed_1[14] ^ seed_1[6]  ^
                                      seed_1[3]  ;

                    o_lane_1_23[2] <= seed_1[16] ^ seed_1[14] ^ seed_1[9]  ^ seed_1[1]  ^
                                      seed_1[21] ^ seed_1[19] ^ seed_1[14] ^ seed_1[6]  ^
                                      seed_1[3]  ^ seed_1[0]  ^ seed_1[18] ^ seed_1[16] ^ 
                                      seed_1[11] ^ seed_1[3]  ^ seed_1[0]  ^ seed_1[20] ^
                                      seed_1[18] ^ seed_1[13] ^ seed_1[5]  ^ seed_1[2]  ^
                                      seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^
                                      seed_1[4]  ^ seed_1[1] ;

                    o_lane_1_23[1] <= seed_1[15] ^ seed_1[13] ^ seed_1[8]  ^  seed_1[0] ^
                                      seed_1[0]  ^ seed_1[20] ^ seed_1[18] ^ seed_1[13] ^
                                      seed_1[5]  ^ seed_1[2]  ^ seed_1[22] ^ seed_1[20] ^ 
                                      seed_1[15] ^ seed_1[7]  ^ seed_1[4]  ^ seed_1[1]  ^
                                      seed_1[17] ^ seed_1[15] ^ seed_1[10] ^ seed_1[2]  ^  
                                      seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^ 
                                      seed_1[4]  ^ seed_1[1]  ^ seed_1[19] ^ seed_1[17] ^ 
                                      seed_1[12] ^ seed_1[4]  ^ seed_1[1]  ^ seed_1[21] ^
                                      seed_1[19] ^ seed_1[14] ^ seed_1[6]  ^ seed_1[3]  ;
                                      
                    o_lane_1_23[0] <= seed_1[14] ^ seed_1[12] ^ seed_1[7]  ^ seed_1[22] ^
                                      seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^ seed_1[4]  ^ 
                                      seed_1[1]  ^ seed_1[19] ^ seed_1[17] ^ seed_1[12] ^
                                      seed_1[4]  ^ seed_1[1]  ^ seed_1[21] ^ seed_1[19] ^
                                      seed_1[14] ^ seed_1[6]  ^ seed_1[3]  ^ seed_1[0]  ^
                                      seed_1[16] ^ seed_1[14] ^ seed_1[9]  ^ seed_1[1]  ^
                                      seed_1[21] ^ seed_1[19] ^ seed_1[14] ^ seed_1[6]  ^ 
                                      seed_1[3]  ^ seed_1[0]  ^ seed_1[18] ^ seed_1[16] ^
                                      seed_1[11] ^ seed_1[3]  ^ seed_1[0]  ^ seed_1[20] ^
                                      seed_1[18] ^ seed_1[13] ^ seed_1[5]  ^ seed_1[2]  ^
                                      seed_1[22] ^ seed_1[20] ^ seed_1[15] ^ seed_1[7]  ^
                                      seed_1[4]  ^ seed_1[1]  ;  

                //--------------------------- lane 2 -----------------------------------//
                    o_lane_2_23[8] <= seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ 
                                      seed_2[7]  ^ seed_2[4]  ^ seed_2[1];

                    o_lane_2_23[7] <= seed_2[21] ^ seed_2[19] ^ seed_2[14] ^ 
                                      seed_2[6]  ^ seed_2[3]  ^ seed_2[0];

                    o_lane_2_23[6] <= seed_2[20] ^ seed_2[18] ^ seed_2[13] ^ 
                                      seed_2[5]  ^ seed_2[2]  ^ seed_2[22] ^ seed_2[20] ^
                                      seed_2[15] ^ seed_2[7]  ^  seed_2[4] ^ 
                                      seed_2[1];

                    o_lane_2_23[5] <= seed_2[19] ^ seed_2[17] ^ seed_2[12] ^ seed_2[4]  ^ 
                                      seed_2[1]  ^ seed_2[21] ^ seed_2[19] ^ seed_2[14] ^
                                      seed_2[6]  ^  seed_2[3] ^ seed_2[0];
                    o_lane_2_23[4] <= seed_2[18] ^ seed_2[16] ^ seed_2[11] ^ 
                                      seed_2[3]  ^ seed_2[0]  ^ seed_2[20] ^ seed_2[18] ^
                                      seed_2[13] ^ seed_2[5]  ^ seed_2[2]  ^ seed_2[22] ^
                                      seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^
                                      seed_2[4]  ^ seed_2[1];

                    o_lane_2_23[3] <= seed_2[17] ^ seed_2[15] ^ seed_2[10] ^ seed_2[0]  ^
                                      seed_2[2]  ^ seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ 
                                      seed_2[7]  ^ seed_2[4]  ^ seed_2[1]  ^ seed_2[19] ^
                                      seed_2[17] ^ seed_2[12] ^ seed_2[4]  ^ seed_2[1]  ^ 
                                      seed_2[21] ^ seed_2[19] ^ seed_2[14] ^ seed_2[6]  ^
                                      seed_2[3]  ;

                    o_lane_2_23[2] <= seed_2[16] ^ seed_2[14] ^ seed_2[9]  ^ seed_2[1]  ^
                                      seed_2[21] ^ seed_2[19] ^ seed_2[14] ^ seed_2[6]  ^
                                      seed_2[3]  ^ seed_2[0]  ^ seed_2[18] ^ seed_2[16] ^ 
                                      seed_2[11] ^ seed_2[3]  ^ seed_2[0]  ^ seed_2[20] ^
                                      seed_2[18] ^ seed_2[13] ^ seed_2[5]  ^ seed_2[2]  ^
                                      seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^
                                      seed_2[4]  ^ seed_2[1] ;

                    o_lane_2_23[1] <= seed_2[15] ^ seed_2[13] ^ seed_2[8]  ^  seed_2[0] ^
                                      seed_2[0]  ^ seed_2[20] ^ seed_2[18] ^ seed_2[13] ^
                                      seed_2[5]  ^ seed_2[2]  ^ seed_2[22] ^ seed_2[20] ^ 
                                      seed_2[15] ^ seed_2[7]  ^ seed_2[4]  ^ seed_2[1]  ^
                                      seed_2[17] ^ seed_2[15] ^ seed_2[10] ^ seed_2[2]  ^  
                                      seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^ 
                                      seed_2[4]  ^ seed_2[1]  ^ seed_2[19] ^ seed_2[17] ^ 
                                      seed_2[12] ^ seed_2[4]  ^ seed_2[1]  ^ seed_2[21] ^
                                      seed_2[19] ^ seed_2[14] ^ seed_2[6]  ^ seed_2[3]  ;
                                      
                    o_lane_2_23[0] <= seed_2[14] ^ seed_2[12] ^ seed_2[7]  ^ seed_2[22] ^
                                      seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^ seed_2[4]  ^ 
                                      seed_2[1]  ^ seed_2[19] ^ seed_2[17] ^ seed_2[12] ^
                                      seed_2[4]  ^ seed_2[1]  ^ seed_2[21] ^ seed_2[19] ^
                                      seed_2[14] ^ seed_2[6]  ^ seed_2[3]  ^ seed_2[0]  ^
                                      seed_2[16] ^ seed_2[14] ^ seed_2[9]  ^ seed_2[1]  ^
                                      seed_2[21] ^ seed_2[19] ^ seed_2[14] ^ seed_2[6]  ^ 
                                      seed_2[3]  ^ seed_2[0]  ^ seed_2[18] ^ seed_2[16] ^
                                      seed_2[11] ^ seed_2[3]  ^ seed_2[0]  ^ seed_2[20] ^
                                      seed_2[18] ^ seed_2[13] ^ seed_2[5]  ^ seed_2[2]  ^
                                      seed_2[22] ^ seed_2[20] ^ seed_2[15] ^ seed_2[7]  ^
                                      seed_2[4]  ^ seed_2[1]  ; 
                    
                //--------------------------- lane 3 -----------------------------------//
                  o_lane_3_23[8] <= seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ 
                                    seed_3[7]  ^ seed_3[4]  ^ seed_3[1];

                  o_lane_3_23[7] <= seed_3[21] ^ seed_3[19] ^ seed_3[14] ^ 
                                    seed_3[6]  ^ seed_3[3]  ^ seed_3[0];

                  o_lane_3_23[6] <= seed_3[20] ^ seed_3[18] ^ seed_3[13] ^ 
                                    seed_3[5]  ^ seed_3[2]  ^ seed_3[22] ^ seed_3[20] ^
                                    seed_3[15] ^ seed_3[7]  ^  seed_3[4] ^ 
                                    seed_3[1];

                  o_lane_3_23[5] <= seed_3[19] ^ seed_3[17] ^ seed_3[12] ^ seed_3[4]  ^ 
                                    seed_3[1]  ^ seed_3[21] ^ seed_3[19] ^ seed_3[14] ^
                                    seed_3[6]  ^  seed_3[3] ^ seed_3[0];

                  o_lane_3_23[4] <= seed_3[18] ^ seed_3[16] ^ seed_3[11] ^ 
                                    seed_3[3]  ^ seed_3[0]  ^ seed_3[20] ^ seed_3[18] ^
                                    seed_3[13] ^ seed_3[5]  ^ seed_3[2]  ^ seed_3[22] ^
                                    seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^
                                    seed_3[4]  ^ seed_3[1];

                  o_lane_3_23[3] <= seed_3[17] ^ seed_3[15] ^ seed_3[10] ^ seed_3[0]  ^
                                    seed_3[2]  ^ seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ 
                                    seed_3[7]  ^ seed_3[4]  ^ seed_3[1]  ^ seed_3[19] ^
                                    seed_3[17] ^ seed_3[12] ^ seed_3[4]  ^ seed_3[1]  ^ 
                                    seed_3[21] ^ seed_3[19] ^ seed_3[14] ^ seed_3[6]  ^
                                    seed_3[3]  ;

                  o_lane_3_23[2] <= seed_3[16] ^ seed_3[14] ^ seed_3[9]  ^ seed_3[1]  ^
                                    seed_3[21] ^ seed_3[19] ^ seed_3[14] ^ seed_3[6]  ^
                                    seed_3[3]  ^ seed_3[0]  ^ seed_3[18] ^ seed_3[16] ^ 
                                    seed_3[11] ^ seed_3[3]  ^ seed_3[0]  ^ seed_3[20] ^
                                    seed_3[18] ^ seed_3[13] ^ seed_3[5]  ^ seed_3[2]  ^
                                    seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^
                                    seed_3[4]  ^ seed_3[1] ;
                  o_lane_3_23[1] <= seed_3[15] ^ seed_3[13] ^ seed_3[8]  ^  seed_3[0] ^
                                    seed_3[0]  ^ seed_3[20] ^ seed_3[18] ^ seed_3[13] ^
                                    seed_3[5]  ^ seed_3[2]  ^ seed_3[22] ^ seed_3[20] ^ 
                                    seed_3[15] ^ seed_3[7]  ^ seed_3[4]  ^ seed_3[1]  ^
                                    seed_3[17] ^ seed_3[15] ^ seed_3[10] ^ seed_3[2]  ^  
                                    seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^ 
                                    seed_3[4]  ^ seed_3[1]  ^ seed_3[19] ^ seed_3[17] ^ 
                                    seed_3[12] ^ seed_3[4]  ^ seed_3[1]  ^ seed_3[21] ^
                                    seed_3[19] ^ seed_3[14] ^ seed_3[6]  ^ seed_3[3]  ;
                                    
                  o_lane_3_23[0] <= seed_3[14] ^ seed_3[12] ^ seed_3[7]  ^ seed_3[22] ^
                                    seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^ seed_3[4]  ^ 
                                    seed_3[1]  ^ seed_3[19] ^ seed_3[17] ^ seed_3[12] ^
                                    seed_3[4]  ^ seed_3[1]  ^ seed_3[21] ^ seed_3[19] ^
                                    seed_3[14] ^ seed_3[6]  ^ seed_3[3]  ^ seed_3[0]  ^
                                    seed_3[16] ^ seed_3[14] ^ seed_3[9]  ^ seed_3[1]  ^
                                    seed_3[21] ^ seed_3[19] ^ seed_3[14] ^ seed_3[6]  ^ 
                                    seed_3[3]  ^ seed_3[0]  ^ seed_3[18] ^ seed_3[16] ^
                                    seed_3[11] ^ seed_3[3]  ^ seed_3[0]  ^ seed_3[20] ^
                                    seed_3[18] ^ seed_3[13] ^ seed_3[5]  ^ seed_3[2]  ^
                                    seed_3[22] ^ seed_3[20] ^ seed_3[15] ^ seed_3[7]  ^
                                    seed_3[4]  ^ seed_3[1]  ;

                //--------------------------- lane 4 -----------------------------------//
                  o_lane_4_23[8] <= seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ 
                                    seed_4[7]  ^ seed_4[4]  ^ seed_4[1];

                  o_lane_4_23[7] <= seed_4[21] ^ seed_4[19] ^ seed_4[14] ^ 
                                    seed_4[6]  ^ seed_4[3]  ^ seed_4[0];

                  o_lane_4_23[6] <= seed_4[20] ^ seed_4[18] ^ seed_4[13] ^ 
                                    seed_4[5]  ^ seed_4[2]  ^ seed_4[22] ^ seed_4[20] ^
                                    seed_4[15] ^ seed_4[7]  ^  seed_4[4] ^ 
                                    seed_4[1];

                  o_lane_4_23[5] <= seed_4[19] ^ seed_4[17] ^ seed_4[12] ^ seed_4[4]  ^ 
                                    seed_4[1]  ^ seed_4[21] ^ seed_4[19] ^ seed_4[14] ^
                                    seed_4[6]  ^  seed_4[3] ^ seed_4[0];
                  o_lane_4_23[4] <= seed_4[18] ^ seed_4[16] ^ seed_4[11] ^ 
                                    seed_4[3]  ^ seed_4[0]  ^ seed_4[20] ^ seed_4[18] ^
                                    seed_4[13] ^ seed_4[5]  ^ seed_4[2]  ^ seed_4[22] ^
                                    seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^
                                    seed_4[4]  ^ seed_4[1];

                  o_lane_4_23[3] <= seed_4[17] ^ seed_4[15] ^ seed_4[10] ^ seed_4[0]  ^
                                    seed_4[2]  ^ seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ 
                                    seed_4[7]  ^ seed_4[4]  ^ seed_4[1]  ^ seed_4[19] ^
                                    seed_4[17] ^ seed_4[12] ^ seed_4[4]  ^ seed_4[1]  ^ 
                                    seed_4[21] ^ seed_4[19] ^ seed_4[14] ^ seed_4[6]  ^
                                    seed_4[3];

                  o_lane_4_23[2] <= seed_4[16] ^ seed_4[14] ^ seed_4[9]  ^ seed_4[1]  ^
                                    seed_4[21] ^ seed_4[19] ^ seed_4[14] ^ seed_4[6]  ^
                                    seed_4[3]  ^ seed_4[0]  ^ seed_4[18] ^ seed_4[16] ^ 
                                    seed_4[11] ^ seed_4[3]  ^ seed_4[0]  ^ seed_4[20] ^
                                    seed_4[18] ^ seed_4[13] ^ seed_4[5]  ^ seed_4[2]  ^
                                    seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^
                                    seed_4[4]  ^ seed_4[1];

                  o_lane_4_23[1] <= seed_4[15] ^ seed_4[13] ^ seed_4[8]  ^  seed_4[0] ^
                                    seed_4[0]  ^ seed_4[20] ^ seed_4[18] ^ seed_4[13] ^
                                    seed_4[5]  ^ seed_4[2]  ^ seed_4[22] ^ seed_4[20] ^ 
                                    seed_4[15] ^ seed_4[7]  ^ seed_4[4]  ^ seed_4[1]  ^
                                    seed_4[17] ^ seed_4[15] ^ seed_4[10] ^ seed_4[2]  ^  
                                    seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^ 
                                    seed_4[4]  ^ seed_4[1]  ^ seed_4[19] ^ seed_4[17] ^ 
                                    seed_4[12] ^ seed_4[4]  ^ seed_4[1]  ^ seed_4[21] ^
                                    seed_4[19] ^ seed_4[14] ^ seed_4[6]  ^ seed_4[3];
                                    
                  o_lane_4_23[0] <= seed_4[14] ^ seed_4[12] ^ seed_4[7]  ^ seed_4[22] ^
                                    seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^ seed_4[4]  ^ 
                                    seed_4[1]  ^ seed_4[19] ^ seed_4[17] ^ seed_4[12] ^
                                    seed_4[4]  ^ seed_4[1]  ^ seed_4[21] ^ seed_4[19] ^
                                    seed_4[14] ^ seed_4[6]  ^ seed_4[3]  ^ seed_4[0]  ^
                                    seed_4[16] ^ seed_4[14] ^ seed_4[9]  ^ seed_4[1]  ^
                                    seed_4[21] ^ seed_4[19] ^ seed_4[14] ^ seed_4[6]  ^ 
                                    seed_4[3]  ^ seed_4[0]  ^ seed_4[18] ^ seed_4[16] ^
                                    seed_4[11] ^ seed_4[3]  ^ seed_4[0]  ^ seed_4[20] ^
                                    seed_4[18] ^ seed_4[13] ^ seed_4[5]  ^ seed_4[2]  ^
                                    seed_4[22] ^ seed_4[20] ^ seed_4[15] ^ seed_4[7]  ^
                                    seed_4[4]  ^ seed_4[1]; 

                //--------------------------- lane 5 -----------------------------------//
                    o_lane_5_23[8] <= seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ 
                                      seed_5[7]  ^ seed_5[4]  ^ seed_5[1];

                    o_lane_5_23[7] <= seed_5[21] ^ seed_5[19] ^ seed_5[14] ^ 
                                      seed_5[6]  ^ seed_5[3]  ^ seed_5[0];

                    o_lane_5_23[6] <= seed_5[20] ^ seed_5[18] ^ seed_5[13] ^ 
                                      seed_5[5]  ^ seed_5[2]  ^ seed_5[22] ^ seed_5[20] ^
                                      seed_5[15] ^ seed_5[7]  ^  seed_5[4] ^ 
                                      seed_5[1];

                    o_lane_5_23[5] <= seed_5[19] ^ seed_5[17] ^ seed_5[12] ^ seed_5[4]  ^ 
                                      seed_5[1]  ^ seed_5[21] ^ seed_5[19] ^ seed_5[14] ^
                                      seed_5[6]  ^  seed_5[3] ^ seed_5[0];

                    o_lane_5_23[4] <= seed_5[18] ^ seed_5[16] ^ seed_5[11] ^ 
                                      seed_5[3]  ^ seed_5[0]  ^ seed_5[20] ^ seed_5[18] ^
                                      seed_5[13] ^ seed_5[5]  ^ seed_5[2]  ^ seed_5[22] ^
                                      seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^
                                      seed_5[4]  ^ seed_5[1];

                    o_lane_5_23[3] <= seed_5[17] ^ seed_5[15] ^ seed_5[10] ^ seed_5[0]  ^
                                      seed_5[2]  ^ seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ 
                                      seed_5[7]  ^ seed_5[4]  ^ seed_5[1]  ^ seed_5[19] ^
                                      seed_5[17] ^ seed_5[12] ^ seed_5[4]  ^ seed_5[1]  ^ 
                                      seed_5[21] ^ seed_5[19] ^ seed_5[14] ^ seed_5[6]  ^
                                      seed_5[3]  ;

                    o_lane_5_23[2] <= seed_5[16] ^ seed_5[14] ^ seed_5[9]  ^ seed_5[1]  ^
                                      seed_5[21] ^ seed_5[19] ^ seed_5[14] ^ seed_5[6]  ^
                                      seed_5[3]  ^ seed_5[0]  ^ seed_5[18] ^ seed_5[16] ^ 
                                      seed_5[11] ^ seed_5[3]  ^ seed_5[0]  ^ seed_5[20] ^
                                      seed_5[18] ^ seed_5[13] ^ seed_5[5]  ^ seed_5[2]  ^
                                      seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^
                                      seed_5[4]  ^ seed_5[1] ;

                    o_lane_5_23[1] <= seed_5[15] ^ seed_5[13] ^ seed_5[8]  ^  seed_5[0] ^
                                      seed_5[0]  ^ seed_5[20] ^ seed_5[18] ^ seed_5[13] ^
                                      seed_5[5]  ^ seed_5[2]  ^ seed_5[22] ^ seed_5[20] ^ 
                                      seed_5[15] ^ seed_5[7]  ^ seed_5[4]  ^ seed_5[1]  ^
                                      seed_5[17] ^ seed_5[15] ^ seed_5[10] ^ seed_5[2]  ^  
                                      seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^ 
                                      seed_5[4]  ^ seed_5[1]  ^ seed_5[19] ^ seed_5[17] ^ 
                                      seed_5[12] ^ seed_5[4]  ^ seed_5[1]  ^ seed_5[21] ^
                                      seed_5[19] ^ seed_5[14] ^ seed_5[6]  ^ seed_5[3]  ;
                                      
                    o_lane_5_23[0] <= seed_5[14] ^ seed_5[12] ^ seed_5[7]  ^ seed_5[22] ^
                                      seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^ seed_5[4]  ^ 
                                      seed_5[1]  ^ seed_5[19] ^ seed_5[17] ^ seed_5[12] ^
                                      seed_5[4]  ^ seed_5[1]  ^ seed_5[21] ^ seed_5[19] ^
                                      seed_5[14] ^ seed_5[6]  ^ seed_5[3]  ^ seed_5[0]  ^
                                      seed_5[16] ^ seed_5[14] ^ seed_5[9]  ^ seed_5[1]  ^
                                      seed_5[21] ^ seed_5[19] ^ seed_5[14] ^ seed_5[6]  ^ 
                                      seed_5[3]  ^ seed_5[0]  ^ seed_5[18] ^ seed_5[16] ^
                                      seed_5[11] ^ seed_5[3]  ^ seed_5[0]  ^ seed_5[20] ^
                                      seed_5[18] ^ seed_5[13] ^ seed_5[5]  ^ seed_5[2]  ^
                                      seed_5[22] ^ seed_5[20] ^ seed_5[15] ^ seed_5[7]  ^
                                      seed_5[4]  ^ seed_5[1]  ; 

                //--------------------------- lane 6 -----------------------------------//
                  o_lane_6_23[8] <= seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ 
                                    seed_6[7]  ^ seed_6[4]  ^ seed_6[1];

                  o_lane_6_23[7] <= seed_6[21] ^ seed_6[19] ^ seed_6[14] ^ 
                                    seed_6[6]  ^ seed_6[3]  ^ seed_6[0];

                  o_lane_6_23[6] <= seed_6[20] ^ seed_6[18] ^ seed_6[13] ^ 
                                    seed_6[5]  ^ seed_6[2]  ^ seed_6[22] ^ seed_6[20] ^
                                    seed_6[15] ^ seed_6[7]  ^  seed_6[4] ^ 
                                    seed_6[1];

                  o_lane_6_23[5] <= seed_6[19] ^ seed_6[17] ^ seed_6[12] ^ seed_6[4]  ^ 
                                    seed_6[1]  ^ seed_6[21] ^ seed_6[19] ^ seed_6[14] ^
                                    seed_6[6]  ^  seed_6[3] ^ seed_6[0];

                  o_lane_6_23[4] <= seed_6[18] ^ seed_6[16] ^ seed_6[11] ^ 
                                    seed_6[3]  ^ seed_6[0]  ^ seed_6[20] ^ seed_6[18] ^
                                    seed_6[13] ^ seed_6[5]  ^ seed_6[2]  ^ seed_6[22] ^
                                    seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^
                                    seed_6[4]  ^ seed_6[1];

                  o_lane_6_23[3] <= seed_6[17] ^ seed_6[15] ^ seed_6[10] ^ seed_6[0]  ^
                                    seed_6[2]  ^ seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ 
                                    seed_6[7]  ^ seed_6[4]  ^ seed_6[1]  ^ seed_6[19] ^
                                    seed_6[17] ^ seed_6[12] ^ seed_6[4]  ^ seed_6[1]  ^ 
                                    seed_6[21] ^ seed_6[19] ^ seed_6[14] ^ seed_6[6]  ^
                                    seed_6[3] ;
                  o_lane_6_23[2] <= seed_6[16] ^ seed_6[14] ^ seed_6[9]  ^ seed_6[1]  ^
                                    seed_6[21] ^ seed_6[19] ^ seed_6[14] ^ seed_6[6]  ^
                                    seed_6[3]  ^ seed_6[0]  ^ seed_6[18] ^ seed_6[16] ^ 
                                    seed_6[11] ^ seed_6[3]  ^ seed_6[0]  ^ seed_6[20] ^
                                    seed_6[18] ^ seed_6[13] ^ seed_6[5]  ^ seed_6[2]  ^
                                    seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^
                                    seed_6[4]  ^ seed_6[1];

                  o_lane_6_23[1] <= seed_6[15] ^ seed_6[13] ^ seed_6[8]  ^  seed_6[0] ^
                                    seed_6[0]  ^ seed_6[20] ^ seed_6[18] ^ seed_6[13] ^
                                    seed_6[5]  ^ seed_6[2]  ^ seed_6[22] ^ seed_6[20] ^ 
                                    seed_6[15] ^ seed_6[7]  ^ seed_6[4]  ^ seed_6[1]  ^
                                    seed_6[17] ^ seed_6[15] ^ seed_6[10] ^ seed_6[2]  ^  
                                    seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^ 
                                    seed_6[4]  ^ seed_6[1]  ^ seed_6[19] ^ seed_6[17] ^ 
                                    seed_6[12] ^ seed_6[4]  ^ seed_6[1]  ^ seed_6[21] ^
                                    seed_6[19] ^ seed_6[14] ^ seed_6[6]  ^ seed_6[3];
                                    
                  o_lane_6_23[0] <= seed_6[14] ^ seed_6[12] ^ seed_6[7]  ^ seed_6[22] ^
                                    seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^ seed_6[4]  ^ 
                                    seed_6[1]  ^ seed_6[19] ^ seed_6[17] ^ seed_6[12] ^
                                    seed_6[4]  ^ seed_6[1]  ^ seed_6[21] ^ seed_6[19] ^
                                    seed_6[14] ^ seed_6[6]  ^ seed_6[3]  ^ seed_6[0]  ^
                                    seed_6[16] ^ seed_6[14] ^ seed_6[9]  ^ seed_6[1]  ^
                                    seed_6[21] ^ seed_6[19] ^ seed_6[14] ^ seed_6[6]  ^ 
                                    seed_6[3]  ^ seed_6[0]  ^ seed_6[18] ^ seed_6[16] ^
                                    seed_6[11] ^ seed_6[3]  ^ seed_6[0]  ^ seed_6[20] ^
                                    seed_6[18] ^ seed_6[13] ^ seed_6[5]  ^ seed_6[2]  ^
                                    seed_6[22] ^ seed_6[20] ^ seed_6[15] ^ seed_6[7]  ^
                                    seed_6[4]  ^ seed_6[1]; 

                //--------------------------- lane 7 -----------------------------------//
                    o_lane_7_23[8] <= seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ 
                                      seed_7[7]  ^ seed_7[4]  ^ seed_7[1];

                    o_lane_7_23[7] <= seed_7[21] ^ seed_7[19] ^ seed_7[14] ^ 
                                      seed_7[6]  ^ seed_7[3]  ^ seed_7[0];

                    o_lane_7_23[6] <= seed_7[20] ^ seed_7[18] ^ seed_7[13] ^ 
                                      seed_7[5]  ^ seed_7[2]  ^ seed_7[22] ^ seed_7[20] ^
                                      seed_7[15] ^ seed_7[7]  ^  seed_7[4] ^ 
                                      seed_7[1];

                    o_lane_7_23[5] <= seed_7[19] ^ seed_7[17] ^ seed_7[12] ^ seed_7[4]  ^ 
                                      seed_7[1]  ^ seed_7[21] ^ seed_7[19] ^ seed_7[14] ^
                                      seed_7[6]  ^  seed_7[3] ^ seed_7[0];
                    o_lane_7_23[4] <= seed_7[18] ^ seed_7[16] ^ seed_7[11] ^ 
                                      seed_7[3]  ^ seed_7[0]  ^ seed_7[20] ^ seed_7[18] ^
                                      seed_7[13] ^ seed_7[5]  ^ seed_7[2]  ^ seed_7[22] ^
                                      seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^
                                      seed_7[4]  ^ seed_7[1];

                    o_lane_7_23[3] <= seed_7[17] ^ seed_7[15] ^ seed_7[10] ^ seed_7[0]  ^
                                      seed_7[2]  ^ seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ 
                                      seed_7[7]  ^ seed_7[4]  ^ seed_7[1]  ^ seed_7[19] ^
                                      seed_7[17] ^ seed_7[12] ^ seed_7[4]  ^ seed_7[1]  ^ 
                                      seed_7[21] ^ seed_7[19] ^ seed_7[14] ^ seed_7[6]  ^
                                      seed_7[3];

                    o_lane_7_23[2] <= seed_7[16] ^ seed_7[14] ^ seed_7[9]  ^ seed_7[1]  ^
                                      seed_7[21] ^ seed_7[19] ^ seed_7[14] ^ seed_7[6]  ^
                                      seed_7[3]  ^ seed_7[0]  ^ seed_7[18] ^ seed_7[16] ^ 
                                      seed_7[11] ^ seed_7[3]  ^ seed_7[0]  ^ seed_7[20] ^
                                      seed_7[18] ^ seed_7[13] ^ seed_7[5]  ^ seed_7[2]  ^
                                      seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^
                                      seed_7[4]  ^ seed_7[1];

                    o_lane_7_23[1] <= seed_7[15] ^ seed_7[13] ^ seed_7[8]  ^  seed_7[0] ^
                                      seed_7[0]  ^ seed_7[20] ^ seed_7[18] ^ seed_7[13] ^
                                      seed_7[5]  ^ seed_7[2]  ^ seed_7[22] ^ seed_7[20] ^ 
                                      seed_7[15] ^ seed_7[7]  ^ seed_7[4]  ^ seed_7[1]  ^
                                      seed_7[17] ^ seed_7[15] ^ seed_7[10] ^ seed_7[2]  ^  
                                      seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^ 
                                      seed_7[4]  ^ seed_7[1]  ^ seed_7[19] ^ seed_7[17] ^ 
                                      seed_7[12] ^ seed_7[4]  ^ seed_7[1]  ^ seed_7[21] ^
                                      seed_7[19] ^ seed_7[14] ^ seed_7[6]  ^ seed_7[3];
                                      
                    o_lane_7_23[0] <= seed_7[14] ^ seed_7[12] ^ seed_7[7]  ^ seed_7[22] ^
                                      seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^ seed_7[4]  ^ 
                                      seed_7[1]  ^ seed_7[19] ^ seed_7[17] ^ seed_7[12] ^
                                      seed_7[4]  ^ seed_7[1]  ^ seed_7[21] ^ seed_7[19] ^
                                      seed_7[14] ^ seed_7[6]  ^ seed_7[3]  ^ seed_7[0]  ^
                                      seed_7[16] ^ seed_7[14] ^ seed_7[9]  ^ seed_7[1]  ^
                                      seed_7[21] ^ seed_7[19] ^ seed_7[14] ^ seed_7[6]  ^ 
                                      seed_7[3]  ^ seed_7[0]  ^ seed_7[18] ^ seed_7[16] ^
                                      seed_7[11] ^ seed_7[3]  ^ seed_7[0]  ^ seed_7[20] ^
                                      seed_7[18] ^ seed_7[13] ^ seed_7[5]  ^ seed_7[2]  ^
                                      seed_7[22] ^ seed_7[20] ^ seed_7[15] ^ seed_7[7]  ^
                                      seed_7[4]  ^ seed_7[1]; 


            end

            PATTERN_LFSR: begin
                if (i_enable_buffer) begin
                    // First update all LFSR states
                    {o_lane_0_23, rx_lfsr_lane_0} <= next_lfsr_state(rx_lfsr_lane_0);
                    {o_lane_1_23, rx_lfsr_lane_1} <= next_lfsr_state(rx_lfsr_lane_1);
                    {o_lane_2_23, rx_lfsr_lane_2} <= next_lfsr_state(rx_lfsr_lane_2);
                    {o_lane_3_23, rx_lfsr_lane_3} <= next_lfsr_state(rx_lfsr_lane_3);
                    {o_lane_4_23, rx_lfsr_lane_4} <= next_lfsr_state(rx_lfsr_lane_4);
                    {o_lane_5_23, rx_lfsr_lane_5} <= next_lfsr_state(rx_lfsr_lane_5);
                    {o_lane_6_23, rx_lfsr_lane_6} <= next_lfsr_state(rx_lfsr_lane_6);
                    {o_lane_7_23, rx_lfsr_lane_7} <= next_lfsr_state(rx_lfsr_lane_7);

                    // Then check descrambling enable
                    if (i_descramble_en) begin
                        // Process based on current state
                        i_enable_pattern_comp<=0;
                        
                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                temp_Data_by_0 <= {rx_lfsr_lane_0, o_lane_0_23} ^ i_data_in_0;
                                temp_Data_by_1 <= {rx_lfsr_lane_1, o_lane_1_23} ^ i_data_in_1;
                                temp_Data_by_2 <= {rx_lfsr_lane_2, o_lane_2_23} ^ i_data_in_2;
                                temp_Data_by_3 <= {rx_lfsr_lane_3, o_lane_3_23} ^ i_data_in_3;
                                temp_Data_by_4 <= {rx_lfsr_lane_4, o_lane_4_23} ^ i_data_in_4;
                                temp_Data_by_5 <= {rx_lfsr_lane_5, o_lane_5_23} ^ i_data_in_5;
                                temp_Data_by_6 <= {rx_lfsr_lane_6, o_lane_6_23} ^ i_data_in_6;
                                temp_Data_by_7 <= {rx_lfsr_lane_7, o_lane_7_23} ^ i_data_in_7;
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                temp_Data_by_8  <= {rx_lfsr_lane_0, o_lane_0_23} ^ i_data_in_8;
                                temp_Data_by_9  <= {rx_lfsr_lane_1, o_lane_1_23} ^ i_data_in_9;
                                temp_Data_by_10 <= {rx_lfsr_lane_2, o_lane_2_23} ^ i_data_in_10;
                                temp_Data_by_11 <= {rx_lfsr_lane_3, o_lane_3_23} ^ i_data_in_11;
                                temp_Data_by_12 <= {rx_lfsr_lane_4, o_lane_4_23} ^ i_data_in_12;
                                temp_Data_by_13 <= {rx_lfsr_lane_5, o_lane_5_23} ^ i_data_in_13;
                                temp_Data_by_14 <= {rx_lfsr_lane_6, o_lane_6_23} ^ i_data_in_14;
                                temp_Data_by_15 <= {rx_lfsr_lane_7, o_lane_7_23} ^ i_data_in_15;
                            end
                            DEGRADE_LANES_0_TO_3: begin
                                temp_Data_by_0 <= {rx_lfsr_lane_0, o_lane_0_23} ^ i_data_in_0;
                                temp_Data_by_1 <= {rx_lfsr_lane_1, o_lane_1_23} ^ i_data_in_1;
                                temp_Data_by_2 <= {rx_lfsr_lane_2, o_lane_2_23} ^ i_data_in_2;
                                temp_Data_by_3 <= {rx_lfsr_lane_3, o_lane_3_23} ^ i_data_in_3;
                            end
                            DEGRADE_LANES_4_TO_7: begin
                                temp_Data_by_4  <= {rx_lfsr_lane_0, o_lane_0_23} ^ i_data_in_4;
                                temp_Data_by_5  <= {rx_lfsr_lane_1, o_lane_1_23} ^ i_data_in_5;
                                temp_Data_by_6 <= {rx_lfsr_lane_2, o_lane_2_23} ^ i_data_in_6;
                                temp_Data_by_7 <= {rx_lfsr_lane_3, o_lane_3_23} ^ i_data_in_7;
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                temp_Data_by_0  <= {rx_lfsr_lane_0, o_lane_0_23} ^ i_data_in_0;
                                temp_Data_by_1  <= {rx_lfsr_lane_1, o_lane_1_23} ^ i_data_in_1;
                                temp_Data_by_2  <= {rx_lfsr_lane_2, o_lane_2_23} ^ i_data_in_2;
                                temp_Data_by_3  <= {rx_lfsr_lane_3, o_lane_3_23} ^ i_data_in_3;
                                temp_Data_by_4  <= {rx_lfsr_lane_4, o_lane_4_23} ^ i_data_in_4;
                                temp_Data_by_5  <= {rx_lfsr_lane_5, o_lane_5_23} ^ i_data_in_5;
                                temp_Data_by_6  <= {rx_lfsr_lane_6, o_lane_6_23} ^ i_data_in_6;
                                temp_Data_by_7  <= {rx_lfsr_lane_7, o_lane_7_23} ^ i_data_in_7;
                                temp_Data_by_8  <= {rx_lfsr_lane_0, o_lane_0_23} ^ i_data_in_8;
                                temp_Data_by_9  <= {rx_lfsr_lane_1, o_lane_1_23} ^ i_data_in_9;
                                temp_Data_by_10 <= {rx_lfsr_lane_2, o_lane_2_23} ^ i_data_in_10;
                                temp_Data_by_11 <= {rx_lfsr_lane_3, o_lane_3_23} ^ i_data_in_11;
                                temp_Data_by_12 <= {rx_lfsr_lane_4, o_lane_4_23} ^ i_data_in_12;
                                temp_Data_by_13 <= {rx_lfsr_lane_5, o_lane_5_23} ^ i_data_in_13;
                                temp_Data_by_14 <= {rx_lfsr_lane_6, o_lane_6_23} ^ i_data_in_14;
                                temp_Data_by_15 <= {rx_lfsr_lane_7, o_lane_7_23} ^ i_data_in_15;
                            end
                        endcase
                    end
                    else begin
                        i_enable_pattern_comp<=1;
                        temp_Data_by_0  <= i_data_in_0;  temp_Data_by_1  <= i_data_in_1; temp_Data_by_2   <= i_data_in_2; temp_Data_by_3   <= i_data_in_3;
                        temp_Data_by_4  <= i_data_in_4;  temp_Data_by_5  <= i_data_in_5; temp_Data_by_6   <= i_data_in_6; temp_Data_by_7   <= i_data_in_7;
                        temp_Data_by_8  <= i_data_in_8;  temp_Data_by_9  <= i_data_in_9; temp_Data_by_10  <= i_data_in_10; temp_Data_by_11 <= i_data_in_11;
                        temp_Data_by_12 <= i_data_in_12; temp_Data_by_13 <= i_data_in_13; temp_Data_by_14 <= i_data_in_14; temp_Data_by_15 <= i_data_in_15;
                      

                        // Generate local LFSR patterns
                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                o_final_gene_0 <= {rx_lfsr_lane_0, o_lane_0_23};
                                o_final_gene_1 <= {rx_lfsr_lane_1, o_lane_1_23};
                                o_final_gene_2 <= {rx_lfsr_lane_2, o_lane_2_23};
                                o_final_gene_3 <= {rx_lfsr_lane_3, o_lane_3_23};
                                o_final_gene_4 <= {rx_lfsr_lane_4, o_lane_4_23};
                                o_final_gene_5 <= {rx_lfsr_lane_5, o_lane_5_23};
                                o_final_gene_6 <= {rx_lfsr_lane_6, o_lane_6_23};
                                o_final_gene_7 <= {rx_lfsr_lane_7, o_lane_7_23};
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                o_final_gene_8  <= {rx_lfsr_lane_0, o_lane_0_23};
                                o_final_gene_9  <= {rx_lfsr_lane_1, o_lane_1_23};
                                o_final_gene_10 <= {rx_lfsr_lane_2, o_lane_2_23};
                                o_final_gene_11 <= {rx_lfsr_lane_3, o_lane_3_23};
                                o_final_gene_12 <= {rx_lfsr_lane_4, o_lane_4_23};
                                o_final_gene_13 <= {rx_lfsr_lane_5, o_lane_5_23};
                                o_final_gene_14 <= {rx_lfsr_lane_6, o_lane_6_23};
                                o_final_gene_15 <= {rx_lfsr_lane_7, o_lane_7_23};
                            end
                             DEGRADE_LANES_0_TO_3: begin
                                o_final_gene_0 <= {rx_lfsr_lane_0, o_lane_0_23};
                                o_final_gene_1 <= {rx_lfsr_lane_1, o_lane_1_23};
                                o_final_gene_2 <= {rx_lfsr_lane_2, o_lane_2_23};
                                o_final_gene_3 <= {rx_lfsr_lane_3, o_lane_3_23};
                            end
                            DEGRADE_LANES_4_TO_7: begin
                                o_final_gene_4  <= {rx_lfsr_lane_0, o_lane_0_23};
                                o_final_gene_5  <= {rx_lfsr_lane_1, o_lane_1_23};
                                o_final_gene_6  <= {rx_lfsr_lane_2, o_lane_2_23} ;
                                o_final_gene_7  <= {rx_lfsr_lane_3, o_lane_3_23} ;
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                o_final_gene_0  <= {rx_lfsr_lane_0, o_lane_0_23};
                                o_final_gene_1  <= {rx_lfsr_lane_1, o_lane_1_23};
                                o_final_gene_2  <= {rx_lfsr_lane_2, o_lane_2_23};
                                o_final_gene_3  <= {rx_lfsr_lane_3, o_lane_3_23};
                                o_final_gene_4  <= {rx_lfsr_lane_4, o_lane_4_23};
                                o_final_gene_5  <= {rx_lfsr_lane_5, o_lane_5_23};
                                o_final_gene_6  <= {rx_lfsr_lane_6, o_lane_6_23};
                                o_final_gene_7  <= {rx_lfsr_lane_7, o_lane_7_23};
                                o_final_gene_8  <= {rx_lfsr_lane_0, o_lane_0_23};
                                o_final_gene_9  <= {rx_lfsr_lane_1, o_lane_1_23};
                                o_final_gene_10 <= {rx_lfsr_lane_2, o_lane_2_23};
                                o_final_gene_11 <= {rx_lfsr_lane_3, o_lane_3_23};
                                o_final_gene_12 <= {rx_lfsr_lane_4, o_lane_4_23};
                                o_final_gene_13 <= {rx_lfsr_lane_5, o_lane_5_23};
                                o_final_gene_14 <= {rx_lfsr_lane_6, o_lane_6_23};
                                o_final_gene_15 <= {rx_lfsr_lane_7, o_lane_7_23};
                            end
                        endcase
                    end
                end
            end

            PER_LANE_IDE: begin
                if (i_enable_buffer) begin
                    i_enable_pattern_comp<=1;
                    temp_Data_by_0 <= i_data_in_0; temp_Data_by_1 <= i_data_in_1; temp_Data_by_2 <= i_data_in_2; temp_Data_by_3 <= i_data_in_3;
                    temp_Data_by_4 <= i_data_in_4; temp_Data_by_5 <= i_data_in_5; temp_Data_by_6 <= i_data_in_6; temp_Data_by_7 <= i_data_in_7;
                    temp_Data_by_8 <= i_data_in_8; temp_Data_by_9 <= i_data_in_9; temp_Data_by_10 <= i_data_in_10; temp_Data_by_11 <= i_data_in_11;
                    temp_Data_by_12 <= i_data_in_12; temp_Data_by_13 <= i_data_in_13; temp_Data_by_14 <= i_data_in_14; temp_Data_by_15 <= i_data_in_15;
                    case (i_width_deg_lfsr)
                        DEGRADE_LANES_0_TO_7: begin
                            o_final_gene_0 <= {LANE_ID_0, LANE_ID_0};
                            o_final_gene_1 <= {LANE_ID_1, LANE_ID_1};
                            o_final_gene_2 <= {LANE_ID_2, LANE_ID_2};
                            o_final_gene_3 <= {LANE_ID_3, LANE_ID_3};
                            o_final_gene_4 <= {LANE_ID_4, LANE_ID_4};
                            o_final_gene_5 <= {LANE_ID_5, LANE_ID_5};
                            o_final_gene_6 <= {LANE_ID_6, LANE_ID_6};
                            o_final_gene_7 <= {LANE_ID_7, LANE_ID_7};
                        end
                        DEGRADE_LANES_8_TO_15: begin
                            o_final_gene_8  <= {LANE_ID_8, LANE_ID_8};
                            o_final_gene_9  <= {LANE_ID_9, LANE_ID_9};
                            o_final_gene_10 <= {LANE_ID_10, LANE_ID_10};
                            o_final_gene_11 <= {LANE_ID_11, LANE_ID_11};
                            o_final_gene_12 <= {LANE_ID_12, LANE_ID_12};
                            o_final_gene_13 <= {LANE_ID_13, LANE_ID_13};
                            o_final_gene_14 <= {LANE_ID_14, LANE_ID_14};
                            o_final_gene_15 <= {LANE_ID_15, LANE_ID_15};
                        end
                            DEGRADE_LANES_0_TO_3: begin
                            o_final_gene_0 <= {LANE_ID_0, LANE_ID_0};
                            o_final_gene_1 <= {LANE_ID_1, LANE_ID_1};
                            o_final_gene_2 <= {LANE_ID_2, LANE_ID_2};
                            o_final_gene_3 <= {LANE_ID_3, LANE_ID_3};
                        end
                            DEGRADE_LANES_4_TO_7: begin
                            o_final_gene_4 <= {LANE_ID_4, LANE_ID_4};
                            o_final_gene_5 <= {LANE_ID_5, LANE_ID_5};
                            o_final_gene_6 <= {LANE_ID_6, LANE_ID_6};
                            o_final_gene_7 <= {LANE_ID_7, LANE_ID_7};
                        end
                        DEGRADE_LANES_0_TO_15: begin
                            o_final_gene_0  <= {LANE_ID_0, LANE_ID_0};
                            o_final_gene_1  <= {LANE_ID_1, LANE_ID_1};
                            o_final_gene_2  <= {LANE_ID_2, LANE_ID_2};
                            o_final_gene_3  <= {LANE_ID_3, LANE_ID_3};
                            o_final_gene_4  <= {LANE_ID_4, LANE_ID_4};
                            o_final_gene_5  <= {LANE_ID_5, LANE_ID_5};
                            o_final_gene_6  <= {LANE_ID_6, LANE_ID_6};
                            o_final_gene_7  <= {LANE_ID_7, LANE_ID_7};
                            o_final_gene_8  <= {LANE_ID_8, LANE_ID_8};
                            o_final_gene_9  <= {LANE_ID_9, LANE_ID_9};
                            o_final_gene_10 <= {LANE_ID_10, LANE_ID_10};
                            o_final_gene_11 <= {LANE_ID_11, LANE_ID_11};
                            o_final_gene_12 <= {LANE_ID_12, LANE_ID_12};
                            o_final_gene_13 <= {LANE_ID_13, LANE_ID_13};
                            o_final_gene_14 <= {LANE_ID_14, LANE_ID_14};
                            o_final_gene_15 <= {LANE_ID_15, LANE_ID_15};
                        end
                    endcase
                end
            end
        endcase
    end
end
// Assign delayed values to outputs
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        // Reset outputs
        o_Data_by_0 <= 0; o_Data_by_1 <= 0; o_Data_by_2 <= 0; o_Data_by_3 <= 0;
        o_Data_by_4 <= 0; o_Data_by_5 <= 0; o_Data_by_6 <= 0; o_Data_by_7 <= 0;
        o_Data_by_8 <= 0; o_Data_by_9 <= 0; o_Data_by_10 <= 0; o_Data_by_11 <= 0;
        o_Data_by_12 <= 0; o_Data_by_13 <= 0; o_Data_by_14 <= 0; o_Data_by_15 <= 0;
    end
    else begin
        if (i_enable_buffer) begin
            // Assign temp_Data_by_* to o_Data_by_* when i_enable_buffer is 1
            o_Data_by_0 <= i_data_in_0; o_Data_by_1 <= i_data_in_1; o_Data_by_2 <= i_data_in_2; o_Data_by_3 <= i_data_in_3;
            o_Data_by_4 <= i_data_in_4; o_Data_by_5 <= i_data_in_5; o_Data_by_6 <= i_data_in_6; o_Data_by_7 <= i_data_in_7;
            o_Data_by_8 <= i_data_in_8; o_Data_by_9 <= i_data_in_9; o_Data_by_10 <= i_data_in_10; o_Data_by_11 <= i_data_in_11;
            o_Data_by_12 <= i_data_in_12; o_Data_by_13 <= i_data_in_13; o_Data_by_14 <= i_data_in_14; o_Data_by_15 <= i_data_in_15;
        end
        else begin
            // Assign 0 or default value when i_enable_buffer is 0
            o_Data_by_0 <= 0; o_Data_by_1 <= 0; o_Data_by_2 <= 0; o_Data_by_3 <= 0;
            o_Data_by_4 <= 0; o_Data_by_5 <= 0; o_Data_by_6 <= 0; o_Data_by_7 <= 0;
            o_Data_by_8 <= 0; o_Data_by_9 <= 0; o_Data_by_10 <= 0; o_Data_by_11 <= 0;
            o_Data_by_12 <= 0; o_Data_by_13 <= 0; o_Data_by_14 <= 0; o_Data_by_15 <= 0;
        end
    end
end
endmodule