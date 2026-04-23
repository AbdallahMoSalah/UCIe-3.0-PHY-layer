module LFSR_Transmitter #(
    parameter WIDTH = 32 // Parameter for signal width
)(
    input logic i_clk,                      // Clock signal
    input logic i_rst_n,                    // Active-low reset signal
    input logic [1:0] i_state,              // State input (IDLE, CLEAR_LFSR, PATTERN_LFSR, PER_LANE_IDE)
    input logic scramble_en, // Enable scrambling pattern (1: scrambler, 0: pattern)
    input logic [2:0] i_width_deg_lfsr, // Lane mapping code
    input logic reversal_en,          // input for lane reversal
    // 16 input signals
    input logic [WIDTH-1:0] i_lane_0, input logic [WIDTH-1:0] i_lane_1,
    input logic [WIDTH-1:0] i_lane_2, input logic [WIDTH-1:0] i_lane_3,
    input logic [WIDTH-1:0] i_lane_4, input logic [WIDTH-1:0] i_lane_5,
    input logic [WIDTH-1:0] i_lane_6, input logic [WIDTH-1:0] i_lane_7,
    input logic [WIDTH-1:0] i_lane_8, input logic [WIDTH-1:0] i_lane_9,
    input logic [WIDTH-1:0] i_lane_10, input logic [WIDTH-1:0] i_lane_11,
    input logic [WIDTH-1:0] i_lane_12, input logic [WIDTH-1:0] i_lane_13,
    input logic [WIDTH-1:0] i_lane_14, input logic [WIDTH-1:0] i_lane_15,
    // 16 output signals
    output reg [WIDTH-1:0] o_lane_0, output reg [WIDTH-1:0] o_lane_1,
    output reg [WIDTH-1:0] o_lane_2, output reg [WIDTH-1:0] o_lane_3,
    output reg [WIDTH-1:0] o_lane_4, output reg [WIDTH-1:0] o_lane_5,
    output reg [WIDTH-1:0] o_lane_6, output reg [WIDTH-1:0] o_lane_7,
    output reg [WIDTH-1:0] o_lane_8, output reg [WIDTH-1:0] o_lane_9,
    output reg [WIDTH-1:0] o_lane_10, output reg [WIDTH-1:0] o_lane_11,
    output reg [WIDTH-1:0] o_lane_12, output reg [WIDTH-1:0] o_lane_13,
    output reg [WIDTH-1:0] o_lane_14, output reg [WIDTH-1:0] o_lane_15,
    output reg o_Lfsr_tx_done,
    output reg valid_frame_en           
);

    // State and lane mapping parameters
    localparam IDLE           = 2'b00;
    localparam CLEAR_LFSR     = 2'b01;
    localparam PATTERN_LFSR   = 2'b10;
    localparam PER_LANE_IDE   = 2'b11;


    // Degrade Modes
   
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;

    // Counters
    reg [6:0] counter_lfsr;        // 7-bit counter (0 to 127)
    reg [5:0] counter_per_lane;    // 6-bit counter (0 to 63)

    // Lane IDs with prepended and appended 1010
    localparam LANE_ID_0  = 16'b1010_00000000_1010;
    localparam LANE_ID_1  = 16'b1010_00000001_1010;
    localparam LANE_ID_2  = 16'b1010_00000010_1010;
    localparam LANE_ID_3  = 16'b1010_00000011_1010;
    localparam LANE_ID_4  = 16'b1010_00000100_1010;
    localparam LANE_ID_5  = 16'b1010_00000101_1010;
    localparam LANE_ID_6  = 16'b1010_00000110_1010;
    localparam LANE_ID_7  = 16'b1010_00000111_1010;
    localparam LANE_ID_8  = 16'b1010_00001000_1010;
    localparam LANE_ID_9  = 16'b1010_00001001_1010;
    localparam LANE_ID_10 = 16'b1010_00001010_1010;
    localparam LANE_ID_11 = 16'b1010_00001011_1010;
    localparam LANE_ID_12 = 16'b1010_00001100_1010;
    localparam LANE_ID_13 = 16'b1010_00001101_1010;
    localparam LANE_ID_14 = 16'b1010_00001110_1010;
    localparam LANE_ID_15 = 16'b1010_00001111_1010;

    /*----------------------------------------
     * Registers
    ----------------------------------------*/
    reg [1:0] current_state;
    reg [1:0] i_state_reg;
    logic i_state_changed = (i_state_reg != i_state);
    /*----------------------------------------
     * FSM logic
    ----------------------------------------*/
    always @ (posedge i_clk or negedge i_rst_n) begin
        if (~i_rst_n) begin
            current_state <= IDLE;
            i_state_reg   <= 2'b00;
        end else begin
            i_state_reg <= i_state;
            case (current_state)
                /*-----------------------------------------
                 * IDLE state
                -----------------------------------------*/
                IDLE: begin
                    if (i_state_changed && (i_state == 2'b01)) begin // just transititon upon changing the input
                        current_state <= CLEAR_LFSR;
                    end else if (i_state_changed && i_state == 2'b10) begin
                        current_state <= PATTERN_LFSR;
                    end else if (i_state_changed && i_state == 2'b11) begin
                        current_state <= PER_LANE_IDE;
                    end else begin
                        current_state <= IDLE;
                    end
                end
                /*-----------------------------------------
                 * CLEAR_LFSR state
                -----------------------------------------*/
                CLEAR_LFSR: begin
                    current_state <= IDLE;
                end
                /*-----------------------------------------
                 * PATTERN_LFSR state
                -----------------------------------------*/
                PATTERN_LFSR: begin
                    if (&counter_lfsr) begin // counter_lfsr = 7'd127
                        current_state <= IDLE;
                    end else begin
                        current_state <= PATTERN_LFSR;
                    end
                end
                /*-----------------------------------------
                 * PER_LANE_IDE state
                -----------------------------------------*/
                PER_LANE_IDE: begin
                    if (&counter_per_lane) begin // counter_per_lane = 6'd63
                        current_state <= IDLE;
                    end else begin
                        current_state <= PER_LANE_IDE;
                    end
                end
                /*-----------------------------------------
                 * default
                -----------------------------------------*/
                default: begin
                    current_state <= IDLE;
                end
            endcase
        end
    end
  /************************************************************************************************/
    // LFSR registers for each lane
    reg [22:0] tx_lfsr_lane_0, tx_lfsr_lane_1, tx_lfsr_lane_2, tx_lfsr_lane_3;
    reg [22:0] tx_lfsr_lane_4, tx_lfsr_lane_5, tx_lfsr_lane_6, tx_lfsr_lane_7;

    // Bit 23 storage for LFSR outputs
    reg [8:0] o_lane_0_23, o_lane_1_23, o_lane_2_23, o_lane_3_23;
    reg [8:0] o_lane_4_23, o_lane_5_23, o_lane_6_23, o_lane_7_23;

    // New register to store reversal state
    reg lane_reversal_enabled;

    // Function to compute the next LFSR state (unchanged)
    function [31:0] next_lfsr_state;
        input [22:0] current_state;
        reg [31:0] next_state;
        begin
            next_state[0]  = current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[14] ^ current_state[15] ^ current_state[17] ^ current_state[18] ^ current_state[19] ^ current_state[20] ^ current_state[22];
            next_state[1]  = current_state[0] ^ current_state[3] ^ current_state[4] ^ current_state[9] ^ current_state[11] ^ current_state[15] ^ current_state[18] ^ current_state[19] ^ current_state[20];
            next_state[2]  = current_state[1] ^ current_state[4] ^ current_state[5] ^ current_state[10] ^ current_state[12] ^ current_state[16] ^ current_state[19] ^ current_state[20] ^ current_state[21];
            next_state[3]  = current_state[2] ^ current_state[5] ^ current_state[6] ^ current_state[11] ^ current_state[13] ^ current_state[17] ^ current_state[20] ^ current_state[21] ^ current_state[22];
            next_state[4]  = current_state[0] ^ current_state[2] ^ current_state[3] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[12] ^ current_state[14] ^ current_state[16] ^ current_state[18] ^ current_state[22];
            next_state[5]  = current_state[0] ^ current_state[1] ^ current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[9] ^ current_state[13] ^ current_state[15] ^ current_state[16] ^ current_state[17] ^ current_state[19] ^ current_state[21];
            next_state[6]  = current_state[1] ^  current_state[2] ^ current_state[3] ^ current_state[4] ^ current_state[5] ^ current_state[6] ^ current_state[7] ^ current_state[8] ^ current_state[10] ^ current_state[14] ^ current_state[16] ^ current_state[17] ^ current_state[18] ^ current_state[20] ^ current_state[22];                        
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

    //reg x_1, x_4 ,x_7 ,x_15 ,x_20 ,x_22;
    // Main always block for state machine and logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            counter_lfsr <= 0;
            counter_per_lane <= 0;
            o_Lfsr_tx_done <= 0;
            valid_frame_en <= 0;
            lane_reversal_enabled <= 0;
            o_lane_1 <= 0; o_lane_2 <= 0; o_lane_3 <= 0;
            o_lane_4 <= 0; o_lane_5 <= 0; o_lane_6 <= 0; o_lane_7 <= 0;
            o_lane_8 <= 0; o_lane_9 <= 0; o_lane_10 <= 0; o_lane_11 <= 0;
            o_lane_12 <= 0; o_lane_13 <= 0; o_lane_14 <= 0; o_lane_15 <= 0;
            o_lane_0_23 <= 0; o_lane_1_23 <= 0; o_lane_2_23 <= 0; o_lane_3_23 <= 0;   // ASK
            o_lane_4_23 <= 0; o_lane_5_23 <= 0; o_lane_6_23 <= 0; o_lane_7_23 <= 0;   // ASK
            tx_lfsr_lane_0 <= 23'h1DBFBC; tx_lfsr_lane_1 <= 23'h0607BB;
            tx_lfsr_lane_2 <= 23'h1EC760; tx_lfsr_lane_3 <= 23'h18C0DB;
            tx_lfsr_lane_4 <= 23'h010F12; tx_lfsr_lane_5 <= 23'h19CFC9;
            tx_lfsr_lane_6 <= 23'h0277CE; tx_lfsr_lane_7 <= 23'h1BB807;

            /*------------------------------------------------------------------------------
            --  
            ------------------------------------------------------------------------------*/

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
            o_lane_0 <= 0; o_lane_1 <= 0; o_lane_2 <= 0; o_lane_3 <= 0;
            o_lane_4 <= 0; o_lane_5 <= 0; o_lane_6 <= 0; o_lane_7 <= 0;
            o_lane_8 <= 0; o_lane_9 <= 0; o_lane_10 <= 0; o_lane_11 <= 0;
            o_lane_12 <= 0; o_lane_13 <= 0; o_lane_14 <= 0; o_lane_15 <= 0;

            case (current_state)
                IDLE: begin
                    counter_lfsr <= 0;
                    counter_per_lane <= 0;
                    valid_frame_en <= 0;
                    if (reversal_en) begin
                        lane_reversal_enabled <= 1;
                        o_Lfsr_tx_done <= 1;
                    end else begin
                        o_Lfsr_tx_done <= 0;
                    end
                end
                CLEAR_LFSR: begin
                    tx_lfsr_lane_0 <= 23'h1DBFBC; tx_lfsr_lane_1 <= 23'h0607BB;
                    tx_lfsr_lane_2 <= 23'h1EC760; tx_lfsr_lane_3 <= 23'h18C0DB;
                    tx_lfsr_lane_4 <= 23'h010F12; tx_lfsr_lane_5 <= 23'h19CFC9;
                    tx_lfsr_lane_6 <= 23'h0277CE; tx_lfsr_lane_7 <= 23'h1BB807;

                    /*------------------------------------------------------------------------------
                    --  
                    ------------------------------------------------------------------------------*/

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
                    {o_lane_0_23, tx_lfsr_lane_0} <= next_lfsr_state(tx_lfsr_lane_0);
                    {o_lane_1_23, tx_lfsr_lane_1} <= next_lfsr_state(tx_lfsr_lane_1);
                    {o_lane_2_23, tx_lfsr_lane_2} <= next_lfsr_state(tx_lfsr_lane_2);
                    {o_lane_3_23, tx_lfsr_lane_3} <= next_lfsr_state(tx_lfsr_lane_3);
                    {o_lane_4_23, tx_lfsr_lane_4} <= next_lfsr_state(tx_lfsr_lane_4);
                    {o_lane_5_23, tx_lfsr_lane_5} <= next_lfsr_state(tx_lfsr_lane_5);
                    {o_lane_6_23, tx_lfsr_lane_6} <= next_lfsr_state(tx_lfsr_lane_6);
                    {o_lane_7_23, tx_lfsr_lane_7} <= next_lfsr_state(tx_lfsr_lane_7);

                    if (scramble_en) begin
                        valid_frame_en <= 1;
                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                if (lane_reversal_enabled) begin
                                    o_lane_0 <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_15;
                                    o_lane_1 <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_14;
                                    o_lane_2 <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_13;
                                    o_lane_3 <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_12;
                                    o_lane_4 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_11;
                                    o_lane_5 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_10;
                                    o_lane_6 <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_9;
                                    o_lane_7 <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_8;
                                end else begin
                                    o_lane_0 <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_0;
                                    o_lane_1 <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_1;
                                    o_lane_2 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_2;
                                    o_lane_3 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_3;
                                    o_lane_4 <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_4;
                                    o_lane_5 <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_5;
                                    o_lane_6 <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_6;
                                    o_lane_7 <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_7;
                                end
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                if (lane_reversal_enabled) begin
                                    o_lane_8  <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_7;
                                    o_lane_9  <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_6;
                                    o_lane_10 <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_5;
                                    o_lane_11 <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_4;
                                    o_lane_12 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_3;
                                    o_lane_13 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_2;
                                    o_lane_14 <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_1;
                                    o_lane_15 <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_0;
                                end else begin
                                    o_lane_8  <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_8;
                                    o_lane_9  <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_9;
                                    o_lane_10 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_10;
                                    o_lane_11 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_11;
                                    o_lane_12 <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_12;
                                    o_lane_13 <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_13;
                                    o_lane_14 <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_14;
                                    o_lane_15 <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_15;
                                end
                            end
                             DEGRADE_LANES_0_TO_3: begin  
                                if (lane_reversal_enabled) begin      //ask 
                                    o_lane_0 <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_7;
                                    o_lane_1 <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_6;
                                    o_lane_2 <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_5;
                                    o_lane_3 <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_4;
                                end else begin
                                    o_lane_0 <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_0;
                                    o_lane_1 <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_1;
                                    o_lane_2 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_2;
                                    o_lane_3 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_3;
                                  
                                end
                            end
                               DEGRADE_LANES_4_TO_7: begin         //stop here 22/4
                              if (lane_reversal_enabled) begin
                                    o_lane_4 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_3;
                                    o_lane_5 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_2;
                                    o_lane_6 <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_1;
                                    o_lane_7 <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_0;
                                end else begin
                                    o_lane_4 <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_4;
                                    o_lane_5 <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_5;
                                    o_lane_6 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_6;
                                    o_lane_7 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_7;
                                  
                                end
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                if (lane_reversal_enabled) begin
                                    o_lane_0  <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_15;
                                    o_lane_1  <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_14;
                                    o_lane_2  <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_13;
                                    o_lane_3  <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_12;
                                    o_lane_4  <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_11;
                                    o_lane_5  <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_10;
                                    o_lane_6  <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_9;
                                    o_lane_7  <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_8;
                                    o_lane_8  <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_7;
                                    o_lane_9  <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_6;
                                    o_lane_10 <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_5;
                                    o_lane_11 <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_4;
                                    o_lane_12 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_3;
                                    o_lane_13 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_2;
                                    o_lane_14 <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_1;
                                    o_lane_15 <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_0;
                                end else begin
                                    o_lane_0  <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_0;
                                    o_lane_1  <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_1;
                                    o_lane_2  <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_2;
                                    o_lane_3  <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_3;
                                    o_lane_4  <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_4;
                                    o_lane_5  <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_5;
                                    o_lane_6  <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_6;
                                    o_lane_7  <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_7;
                                    o_lane_8  <= {tx_lfsr_lane_0, o_lane_0_23} ^ i_lane_8;
                                    o_lane_9  <= {tx_lfsr_lane_1, o_lane_1_23} ^ i_lane_9;
                                    o_lane_10 <= {tx_lfsr_lane_2, o_lane_2_23} ^ i_lane_10;
                                    o_lane_11 <= {tx_lfsr_lane_3, o_lane_3_23} ^ i_lane_11;
                                    o_lane_12 <= {tx_lfsr_lane_4, o_lane_4_23} ^ i_lane_12;
                                    o_lane_13 <= {tx_lfsr_lane_5, o_lane_5_23} ^ i_lane_13;
                                    o_lane_14 <= {tx_lfsr_lane_6, o_lane_6_23} ^ i_lane_14;
                                    o_lane_15 <= {tx_lfsr_lane_7, o_lane_7_23} ^ i_lane_15;
                                end
                            end
                        endcase
                    end
                    else begin
                        case (i_width_deg_lfsr)
                            DEGRADE_LANES_0_TO_7: begin
                                if (counter_lfsr == 127) begin
                                    counter_lfsr <= 0;
                                    o_Lfsr_tx_done <= 1;
                                    valid_frame_en <= 0;
                                end else begin
                                    if (lane_reversal_enabled) begin
                                        o_lane_0 <= {tx_lfsr_lane_7, o_lane_7_23};
                                        o_lane_1 <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_2 <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_3 <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_4 <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_5 <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_6 <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_7 <= {tx_lfsr_lane_0, o_lane_0_23};
                                    end else begin
                                        o_lane_0 <= {tx_lfsr_lane_0, o_lane_0_23};
                                        o_lane_1 <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_2 <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_3 <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_4 <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_5 <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_6 <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_7 <= {tx_lfsr_lane_7, o_lane_7_23};
                                    end
                                    counter_lfsr <= counter_lfsr + 1;
                                    o_Lfsr_tx_done <= 0;
                                    valid_frame_en <= 1;
                                end
                            end
                            DEGRADE_LANES_8_TO_15: begin
                                if (counter_lfsr == 127) begin
                                    counter_lfsr <= 0;
                                    o_Lfsr_tx_done <= 1;
                                    valid_frame_en <= 0;
                                end else begin
                                    if (lane_reversal_enabled) begin
                                        o_lane_8  <= {tx_lfsr_lane_7, o_lane_7_23};
                                        o_lane_9  <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_10 <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_11 <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_12 <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_13 <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_14 <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_15 <= {tx_lfsr_lane_0, o_lane_0_23};
                                    end else begin
                                        o_lane_8  <= {tx_lfsr_lane_0, o_lane_0_23};
                                        o_lane_9  <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_10 <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_11 <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_12 <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_13 <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_14 <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_15 <= {tx_lfsr_lane_7, o_lane_7_23};
                                    end
                                    counter_lfsr <= counter_lfsr + 1;
                                    o_Lfsr_tx_done <= 0;
                                    valid_frame_en <= 1;
                                end
                            end
                              DEGRADE_LANES_0_TO_3: begin
                                if (counter_lfsr == 127) begin
                                    counter_lfsr <= 0;
                                    o_Lfsr_tx_done <= 1;
                                    valid_frame_en <= 0;
                                end else begin
                                    if (lane_reversal_enabled) begin
                                        o_lane_0 <= {tx_lfsr_lane_7, o_lane_7_23};
                                        o_lane_1 <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_2 <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_3 <= {tx_lfsr_lane_4, o_lane_4_23};
                                     
                                    end else begin
                                        o_lane_0 <= {tx_lfsr_lane_0, o_lane_0_23};
                                        o_lane_1 <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_2 <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_3 <= {tx_lfsr_lane_3, o_lane_3_23};
                                    end
                                    counter_lfsr <= counter_lfsr + 1;
                                    o_Lfsr_tx_done <= 0;
                                    valid_frame_en <= 1;
                                end
                            end
                               DEGRADE_LANES_4_TO_7: begin
                                if (counter_lfsr == 127) begin
                                    counter_lfsr <= 0;
                                    o_Lfsr_tx_done <= 1;
                                    valid_frame_en <= 0;
                                end else begin
                                    if (lane_reversal_enabled) begin
                                        o_lane_4 <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_5 <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_6 <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_7 <= {tx_lfsr_lane_0, o_lane_0_23};
                                     
                                    end else begin
                                        o_lane_4 <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_5 <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_6 <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_7 <= {tx_lfsr_lane_7, o_lane_7_23};
                                    end
                                    counter_lfsr <= counter_lfsr + 1;
                                    o_Lfsr_tx_done <= 0;
                                    valid_frame_en <= 1;
                                end
                            end
                            DEGRADE_LANES_0_TO_15: begin
                                if (counter_lfsr == 127) begin
                                    counter_lfsr <= 0;
                                    o_Lfsr_tx_done <= 1;
                                    valid_frame_en <= 0;
                                end else begin
                                    if (lane_reversal_enabled) begin
                                        o_lane_0  <= {tx_lfsr_lane_7, o_lane_7_23};
                                        o_lane_1  <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_2  <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_3  <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_4  <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_5  <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_6  <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_7  <= {tx_lfsr_lane_0, o_lane_0_23};
                                        o_lane_8  <= {tx_lfsr_lane_7, o_lane_7_23};
                                        o_lane_9  <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_10 <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_11 <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_12 <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_13 <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_14 <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_15 <= {tx_lfsr_lane_0, o_lane_0_23};
                                    end else begin
                                        o_lane_0  <= {tx_lfsr_lane_0, o_lane_0_23};
                                        o_lane_1  <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_2  <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_3  <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_4  <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_5  <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_6  <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_7  <= {tx_lfsr_lane_7, o_lane_7_23};
                                        o_lane_8  <= {tx_lfsr_lane_0, o_lane_0_23};
                                        o_lane_9  <= {tx_lfsr_lane_1, o_lane_1_23};
                                        o_lane_10 <= {tx_lfsr_lane_2, o_lane_2_23};
                                        o_lane_11 <= {tx_lfsr_lane_3, o_lane_3_23};
                                        o_lane_12 <= {tx_lfsr_lane_4, o_lane_4_23};
                                        o_lane_13 <= {tx_lfsr_lane_5, o_lane_5_23};
                                        o_lane_14 <= {tx_lfsr_lane_6, o_lane_6_23};
                                        o_lane_15 <= {tx_lfsr_lane_7, o_lane_7_23};
                                    end
                                    counter_lfsr <= counter_lfsr + 1;
                                    o_Lfsr_tx_done <= 0;
                                    valid_frame_en <= 1;
                                end
                            end
                        endcase
                    end
                end

                PER_LANE_IDE: begin
                    case (i_width_deg_lfsr)
                        DEGRADE_LANES_0_TO_7: begin
                            if (counter_per_lane == 63) begin
                                counter_per_lane <= 0;
                                o_Lfsr_tx_done <= 1;
                                valid_frame_en <= 0;
                            end else begin
                                if (lane_reversal_enabled) begin
                                    o_lane_0 <= {LANE_ID_15, LANE_ID_15};
                                    o_lane_1 <= {LANE_ID_14, LANE_ID_14};
                                    o_lane_2 <= {LANE_ID_13, LANE_ID_13};
                                    o_lane_3 <= {LANE_ID_12, LANE_ID_12};
                                    o_lane_4 <= {LANE_ID_11, LANE_ID_11};
                                    o_lane_5 <= {LANE_ID_10, LANE_ID_10};
                                    o_lane_6 <= {LANE_ID_9, LANE_ID_9};
                                    o_lane_7 <= {LANE_ID_8, LANE_ID_8};
                                end else begin
                                    o_lane_0 <= {LANE_ID_0, LANE_ID_0};
                                    o_lane_1 <= {LANE_ID_1, LANE_ID_1};
                                    o_lane_2 <= {LANE_ID_2, LANE_ID_2};
                                    o_lane_3 <= {LANE_ID_3, LANE_ID_3};
                                    o_lane_4 <= {LANE_ID_4, LANE_ID_4};
                                    o_lane_5 <= {LANE_ID_5, LANE_ID_5};
                                    o_lane_6 <= {LANE_ID_6, LANE_ID_6};
                                    o_lane_7 <= {LANE_ID_7, LANE_ID_7};
                                end
                                counter_per_lane <= counter_per_lane + 1;
                                o_Lfsr_tx_done <= 0;
                                valid_frame_en <= 1;
                            end
                        end
                        DEGRADE_LANES_8_TO_15: begin
                            if (counter_per_lane == 63) begin
                                counter_per_lane <= 0;
                                o_Lfsr_tx_done <= 1;
                                valid_frame_en <= 0;
                            end else begin
                                if (lane_reversal_enabled) begin
                                    o_lane_8  <= {LANE_ID_7, LANE_ID_7};
                                    o_lane_9  <= {LANE_ID_6, LANE_ID_6};
                                    o_lane_10 <= {LANE_ID_5, LANE_ID_5};
                                    o_lane_11 <= {LANE_ID_4, LANE_ID_4};
                                    o_lane_12 <= {LANE_ID_3, LANE_ID_3};
                                    o_lane_13 <= {LANE_ID_2, LANE_ID_2};
                                    o_lane_14 <= {LANE_ID_1, LANE_ID_1};
                                    o_lane_15 <= {LANE_ID_0, LANE_ID_0};
                                end else begin
                                    o_lane_8  <= {LANE_ID_8, LANE_ID_8};
                                    o_lane_9  <= {LANE_ID_9, LANE_ID_9};
                                    o_lane_10 <= {LANE_ID_10, LANE_ID_10};
                                    o_lane_11 <= {LANE_ID_11, LANE_ID_11};
                                    o_lane_12 <= {LANE_ID_12, LANE_ID_12};
                                    o_lane_13 <= {LANE_ID_13, LANE_ID_13};
                                    o_lane_14 <= {LANE_ID_14, LANE_ID_14};
                                    o_lane_15 <= {LANE_ID_15, LANE_ID_15};
                                end
                                counter_per_lane <= counter_per_lane + 1;
                                o_Lfsr_tx_done <= 0;
                                valid_frame_en <= 1;
                            end
                        end
                          DEGRADE_LANES_0_TO_3: begin
                            if (counter_per_lane == 63) begin
                                counter_per_lane <= 0;
                                o_Lfsr_tx_done <= 1;
                                valid_frame_en <= 0;
                            end else begin
                                if (lane_reversal_enabled) begin
                                    o_lane_0 <= {LANE_ID_7, LANE_ID_7};
                                    o_lane_1 <= {LANE_ID_6, LANE_ID_6};
                                    o_lane_2 <= {LANE_ID_5, LANE_ID_5};
                                    o_lane_3 <= {LANE_ID_4, LANE_ID_4};
                                end else begin
                                    o_lane_0 <= {LANE_ID_0, LANE_ID_0};
                                    o_lane_1 <= {LANE_ID_1, LANE_ID_1};
                                    o_lane_2 <= {LANE_ID_2, LANE_ID_2};
                                    o_lane_3 <= {LANE_ID_3, LANE_ID_3};
                                end
                                counter_per_lane <= counter_per_lane + 1;
                                o_Lfsr_tx_done <= 0;
                                valid_frame_en <= 1;
                            end
                        end
                           DEGRADE_LANES_4_TO_7: begin
                            if (counter_per_lane == 63) begin
                                counter_per_lane <= 0;
                                o_Lfsr_tx_done <= 1;
                                valid_frame_en <= 0;
                            end else begin
                                if (lane_reversal_enabled) begin
                                    o_lane_4 <= {LANE_ID_3, LANE_ID_3};
                                    o_lane_5 <= {LANE_ID_2, LANE_ID_2};
                                    o_lane_6 <= {LANE_ID_1, LANE_ID_1};
                                    o_lane_7 <= {LANE_ID_0, LANE_ID_0};
                                end else begin
                                    o_lane_4 <= {LANE_ID_4, LANE_ID_4};
                                    o_lane_5 <= {LANE_ID_5, LANE_ID_5};
                                    o_lane_6 <= {LANE_ID_6, LANE_ID_6};
                                    o_lane_7 <= {LANE_ID_7, LANE_ID_7};
                                end
                                counter_per_lane <= counter_per_lane + 1;
                                o_Lfsr_tx_done <= 0;
                                valid_frame_en <= 1;
                            end
                        end
                        DEGRADE_LANES_0_TO_15: begin
                            if (counter_per_lane == 63) begin
                                counter_per_lane <= 0;
                                o_Lfsr_tx_done <= 1;
                                valid_frame_en <= 0;
                            end else begin
                                if (lane_reversal_enabled) begin
                                    o_lane_0  <= {LANE_ID_15, LANE_ID_15};
                                    o_lane_1  <= {LANE_ID_14, LANE_ID_14};
                                    o_lane_2  <= {LANE_ID_13, LANE_ID_13};
                                    o_lane_3  <= {LANE_ID_12, LANE_ID_12};
                                    o_lane_4  <= {LANE_ID_11, LANE_ID_11};
                                    o_lane_5  <= {LANE_ID_10, LANE_ID_10};
                                    o_lane_6  <= {LANE_ID_9, LANE_ID_9};
                                    o_lane_7  <= {LANE_ID_8, LANE_ID_8};
                                    o_lane_8  <= {LANE_ID_7, LANE_ID_7};
                                    o_lane_9  <= {LANE_ID_6, LANE_ID_6};
                                    o_lane_10 <= {LANE_ID_5, LANE_ID_5};
                                    o_lane_11 <= {LANE_ID_4, LANE_ID_4};
                                    o_lane_12 <= {LANE_ID_3, LANE_ID_3};
                                    o_lane_13 <= {LANE_ID_2, LANE_ID_2};
                                    o_lane_14 <= {LANE_ID_1, LANE_ID_1};
                                    o_lane_15 <= {LANE_ID_0, LANE_ID_0};
                                end else begin
                                    o_lane_0  <= {LANE_ID_0, LANE_ID_0};
                                    o_lane_1  <= {LANE_ID_1, LANE_ID_1};
                                    o_lane_2  <= {LANE_ID_2, LANE_ID_2};
                                    o_lane_3  <= {LANE_ID_3, LANE_ID_3};
                                    o_lane_4  <= {LANE_ID_4, LANE_ID_4};
                                    o_lane_5  <= {LANE_ID_5, LANE_ID_5};
                                    o_lane_6  <= {LANE_ID_6, LANE_ID_6};
                                    o_lane_7  <= {LANE_ID_7, LANE_ID_7};
                                    o_lane_8  <= {LANE_ID_8, LANE_ID_8};
                                    o_lane_9  <= {LANE_ID_9, LANE_ID_9};
                                    o_lane_10 <= {LANE_ID_10, LANE_ID_10};
                                    o_lane_11 <= {LANE_ID_11, LANE_ID_11};
                                    o_lane_12 <= {LANE_ID_12, LANE_ID_12};
                                    o_lane_13 <= {LANE_ID_13, LANE_ID_13};
                                    o_lane_14 <= {LANE_ID_14, LANE_ID_14};
                                    o_lane_15 <= {LANE_ID_15, LANE_ID_15};
                                end
                                counter_per_lane <= counter_per_lane + 1;
                                o_Lfsr_tx_done <= 0;
                                valid_frame_en <= 1;
                            end
                        end
                    endcase
                end
            endcase
        end
    end
endmodule