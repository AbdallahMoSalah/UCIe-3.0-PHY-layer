module Demapper #(
    parameter N_BYTES   = 64 ,
    parameter NUM_LANES = 16 ,
    parameter WIDTH     = 32  
) (
    input  wire                     i_clk,
    input  wire                     i_rst_n,
    input  wire   [WIDTH-1:0] i_lane_0,  i_lane_1,  i_lane_2,  i_lane_3,
    input  wire   [WIDTH-1:0] i_lane_4,  i_lane_5,  i_lane_6,  i_lane_7,
    input  wire   [WIDTH-1:0] i_lane_8,  i_lane_9,  i_lane_10, i_lane_11,
    input  wire   [WIDTH-1:0] i_lane_12, i_lane_13, i_lane_14, i_lane_15,
    input  wire                     demapper_en,
    input  wire                     rx_data_valid,
    input  wire [2:0]               i_width_deg_demap,
    output reg                      pl_valid, 
    output reg [8*N_BYTES-1:0]      o_out_data
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
    // Calculations
    //============================================================
    localparam N_BYTE_PER_LANE = WIDTH / 8;
    localparam NUM_WORDS       = N_BYTES / N_BYTE_PER_LANE;

    localparam CLOCK_CYCLES_16 = NUM_WORDS / 16; //1 cycle
    localparam CLOCK_CYCLES_8  = NUM_WORDS / 8; //2 cycle
    localparam CLOCK_CYCLES_4  = NUM_WORDS / 4; //4 cycle

    reg [1:0] cycle_count;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count <= 2'd0;
            pl_valid    <= 1'b0;
            o_out_data  <= 0;
        end
        else begin
            // Default assignments
            pl_valid <= 1'b0;

            if (demapper_en && rx_data_valid) begin
                case (i_width_deg_demap)

                //====================================================
                // x16 MODE — inverse of Mapper DEGRADE_LANES_0_TO_15
                // Mapper: o_lane_N <= {src[391+N*8+:8], src[263+N*8+:8], src[135+N*8+:8], src[N*8+:8]}
                // Demapper: reconstruct each 8-bit slice of o_out_data from i_lane_N[byte]
                //====================================================
                DEGRADE_LANES_0_TO_15: begin
                    // Byte 0  (bits   7:0)   = i_lane_0[7:0]
                    // Byte 1  (bits  15:8)   = i_lane_1[7:0]
                    // ...
                    // Byte 15 (bits 127:120) = i_lane_15[7:0]
                    // Byte 16 (bits 135:128) = i_lane_0[15:8]
                    // ...
                    // Byte 47 (bits 383:376) = i_lane_15[23:16]
                    // Byte 48 (bits 391:384) = i_lane_0[31:24]
                    // ...
                    // Byte 63 (bits 511:504) = i_lane_15[31:24]
                    o_out_data <= {
                        i_lane_15[31:24], i_lane_14[31:24], i_lane_13[31:24], i_lane_12[31:24],
                        i_lane_11[31:24], i_lane_10[31:24], i_lane_9[31:24],  i_lane_8[31:24],
                        i_lane_7[31:24],  i_lane_6[31:24],  i_lane_5[31:24],  i_lane_4[31:24],
                        i_lane_3[31:24],  i_lane_2[31:24],  i_lane_1[31:24],  i_lane_0[31:24],

                        i_lane_15[23:16], i_lane_14[23:16], i_lane_13[23:16], i_lane_12[23:16],
                        i_lane_11[23:16], i_lane_10[23:16], i_lane_9[23:16],  i_lane_8[23:16],
                        i_lane_7[23:16],  i_lane_6[23:16],  i_lane_5[23:16],  i_lane_4[23:16],
                        i_lane_3[23:16],  i_lane_2[23:16],  i_lane_1[23:16],  i_lane_0[23:16],

                        i_lane_15[15:8],  i_lane_14[15:8],  i_lane_13[15:8],  i_lane_12[15:8],
                        i_lane_11[15:8],  i_lane_10[15:8],  i_lane_9[15:8],   i_lane_8[15:8],
                        i_lane_7[15:8],   i_lane_6[15:8],   i_lane_5[15:8],   i_lane_4[15:8],
                        i_lane_3[15:8],   i_lane_2[15:8],   i_lane_1[15:8],   i_lane_0[15:8],

                        i_lane_15[7:0],   i_lane_14[7:0],   i_lane_13[7:0],   i_lane_12[7:0],
                        i_lane_11[7:0],   i_lane_10[7:0],   i_lane_9[7:0],    i_lane_8[7:0],
                        i_lane_7[7:0],    i_lane_6[7:0],    i_lane_5[7:0],    i_lane_4[7:0],
                        i_lane_3[7:0],    i_lane_2[7:0],    i_lane_1[7:0],    i_lane_0[7:0]};
                    if (cycle_count == CLOCK_CYCLES_16-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

            //====================================================
            // x8 MODE (LANES 0–7) — inverse of Mapper DEGRADE_LANES_0_TO_7
            // Mapper cycle 0: lane_N <= {src[199+N*8+:8], src[135+N*8+:8], src[71+N*8+:8], src[N*8+:8]}
            //                 → fills o_out_data[255:0]
            // Mapper cycle 1: lane_N <= {src[455+N*8+:8], src[391+N*8+:8], src[327+N*8+:8], src[263+N*8+:8]}
            //                 → fills o_out_data[511:256]
            //====================================================
            DEGRADE_LANES_0_TO_7: begin
                case (cycle_count)
                    // cycle 0 → reconstruct o_out_data[255:0]
                    // src[7:0]=lane0[7:0], src[15:8]=lane1[7:0],...,src[63:56]=lane7[7:0]
                    // src[71:64]=lane0[15:8],...,src[127:120]=lane7[15:8]
                    // src[135:128]=lane0[23:16],...,src[191:184]=lane7[23:16]
                    // src[199:192]=lane0[31:24],...,src[255:248]=lane7[31:24]
                    0: o_out_data[4*N_BYTES-1:0] <= {
                        i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                        i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],

                        i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                        i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],

                        i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                        i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],

                        i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0],
                        i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]};

                    // cycle 1 → reconstruct o_out_data[511:256]
                    // src[263:256]=lane0[7:0],...,src[319:312]=lane7[7:0]
                    // src[327:320]=lane0[15:8],...,src[383:376]=lane7[15:8]
                    // src[391:384]=lane0[23:16],...,src[447:440]=lane7[23:16]
                    // src[455:448]=lane0[31:24],...,src[511:504]=lane7[31:24]
                    1: o_out_data[8*N_BYTES-1:4*N_BYTES] <= {
                        i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                        i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],

                        i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                        i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],

                        i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                        i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],

                        i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0],
                        i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]};

                    default: o_out_data <= 0;
                endcase
                    if (cycle_count == CLOCK_CYCLES_8-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

            //====================================================
            // x8 MODE (LANES 8–15) — inverse of Mapper DEGRADE_LANES_8_TO_15
            // Same bit-slice pattern as lanes 0-7 but using lanes 8-15
            //====================================================
            DEGRADE_LANES_8_TO_15: begin
                case (cycle_count)
                    // cycle 0 → reconstruct o_out_data[255:0]
                    0: o_out_data[4*N_BYTES-1:0] <= {
                        i_lane_15[31:24], i_lane_14[31:24], i_lane_13[31:24], i_lane_12[31:24],
                        i_lane_11[31:24], i_lane_10[31:24], i_lane_9[31:24],  i_lane_8[31:24],

                        i_lane_15[23:16], i_lane_14[23:16], i_lane_13[23:16], i_lane_12[23:16],
                        i_lane_11[23:16], i_lane_10[23:16], i_lane_9[23:16],  i_lane_8[23:16],

                        i_lane_15[15:8],  i_lane_14[15:8],  i_lane_13[15:8],  i_lane_12[15:8],
                        i_lane_11[15:8],  i_lane_10[15:8],  i_lane_9[15:8],   i_lane_8[15:8],

                        i_lane_15[7:0],   i_lane_14[7:0],   i_lane_13[7:0],   i_lane_12[7:0],
                        i_lane_11[7:0],   i_lane_10[7:0],   i_lane_9[7:0],    i_lane_8[7:0]};

                    // cycle 1 → reconstruct o_out_data[511:256]
                    1: o_out_data[8*N_BYTES-1:4*N_BYTES] <= {
                        i_lane_15[31:24], i_lane_14[31:24], i_lane_13[31:24], i_lane_12[31:24],
                        i_lane_11[31:24], i_lane_10[31:24], i_lane_9[31:24],  i_lane_8[31:24],

                        i_lane_15[23:16], i_lane_14[23:16], i_lane_13[23:16], i_lane_12[23:16],
                        i_lane_11[23:16], i_lane_10[23:16], i_lane_9[23:16],  i_lane_8[23:16],

                        i_lane_15[15:8],  i_lane_14[15:8],  i_lane_13[15:8],  i_lane_12[15:8],
                        i_lane_11[15:8],  i_lane_10[15:8],  i_lane_9[15:8],   i_lane_8[15:8],

                        i_lane_15[7:0],   i_lane_14[7:0],   i_lane_13[7:0],   i_lane_12[7:0],
                        i_lane_11[7:0],   i_lane_10[7:0],   i_lane_9[7:0],    i_lane_8[7:0]};

                    default: o_out_data <= 0;
                endcase
                    if (cycle_count == CLOCK_CYCLES_8-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

            //====================================================
            // x4 MODES — inverse of Mapper DEGRADE_LANES_0_TO_3
            // Mapper cycle 0: lane_N <= {src[103+N*8+:8], src[71+N*8+:8], src[39+N*8+:8], src[N*8+:8]}
            //                 → fills o_out_data[127:0]
            // Mapper cycle 1: fills o_out_data[255:128]
            // Mapper cycle 2: fills o_out_data[383:256]
            // Mapper cycle 3: fills o_out_data[511:384]
            //====================================================
            DEGRADE_LANES_0_TO_3: begin
                case (cycle_count)
                    // cycle 0 → reconstruct o_out_data[127:0]
                    // src[7:0]=lane0[7:0], src[15:8]=lane1[7:0], src[23:16]=lane2[7:0], src[31:24]=lane3[7:0]
                    // src[39:32]=lane0[15:8],..., src[63:56]=lane3[15:8]
                    // src[71:64]=lane0[23:16],..., src[95:88]=lane3[23:16]
                    // src[103:96]=lane0[31:24],..., src[127:120]=lane3[31:24]
                    0: o_out_data[2*N_BYTES-1:0] <= {
                        i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],
                        i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],
                        i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],
                        i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]};

                    // cycle 1 → reconstruct o_out_data[255:128]
                    // src[135:128]=lane0[7:0],..., src[159:152]=lane3[7:0]
                    // src[167:160]=lane0[15:8],..., src[191:184]=lane3[15:8]
                    // src[199:192]=lane0[23:16],..., src[223:216]=lane3[23:16]
                    // src[231:224]=lane0[31:24],..., src[255:248]=lane3[31:24]
                    1: o_out_data[4*N_BYTES-1:2*N_BYTES] <= {
                        i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],
                        i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],
                        i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],
                        i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]};

                    // cycle 2 → reconstruct o_out_data[383:256]
                    2: o_out_data[6*N_BYTES-1:4*N_BYTES] <= {
                        i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],
                        i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],
                        i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],
                        i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]};

                    // cycle 3 → reconstruct o_out_data[511:384]
                    3: o_out_data[8*N_BYTES-1:6*N_BYTES] <= {
                        i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],
                        i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],
                        i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],
                        i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]};

                    default: o_out_data <= 0;
                endcase
                    if (cycle_count == CLOCK_CYCLES_4-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

            DEGRADE_LANES_4_TO_7: begin
                case (cycle_count)
                    // cycle 0 → reconstruct o_out_data[127:0]
                    0: o_out_data[2*N_BYTES-1:0] <= {
                        i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                        i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                        i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                        i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0]};

                    // cycle 1 → reconstruct o_out_data[255:128]
                    1: o_out_data[4*N_BYTES-1:2*N_BYTES] <= {
                        i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                        i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                        i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                        i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0]};

                    // cycle 2 → reconstruct o_out_data[383:256]
                    2: o_out_data[6*N_BYTES-1:4*N_BYTES] <= {
                        i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                        i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                        i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                        i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0]};

                    // cycle 3 → reconstruct o_out_data[511:384]
                    3: o_out_data[8*N_BYTES-1:6*N_BYTES] <= {
                        i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                        i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                        i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                        i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0]};

                    default: o_out_data <= 0;
                endcase
                    if (cycle_count == CLOCK_CYCLES_4-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

                default: begin
                    cycle_count <= 2'd0;
                end

                endcase
            end
            else if (!demapper_en) begin
                cycle_count <= 2'd0;
                o_out_data  <= 0;
            end
        end
    end

endmodule