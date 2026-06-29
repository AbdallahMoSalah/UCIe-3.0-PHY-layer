module unit_demapper #(
    parameter N_BYTES   = 64 ,
    parameter NUM_LANES = 16 ,
    parameter WIDTH     = 32  
) (
    input  logic                     i_clk,
    input  logic                     i_rst_n,
    input  logic   [WIDTH-1:0] i_lane_0,  i_lane_1,  i_lane_2,  i_lane_3,
    input  logic   [WIDTH-1:0] i_lane_4,  i_lane_5,  i_lane_6,  i_lane_7,
    input  logic   [WIDTH-1:0] i_lane_8,  i_lane_9,  i_lane_10, i_lane_11,
    input  logic   [WIDTH-1:0] i_lane_12, i_lane_13, i_lane_14, i_lane_15,
    input  logic                     demapper_en,
    input  logic                     rx_data_valid,
    input  logic [2:0]               i_width_deg_demap,
    output logic                      pl_valid,
    output logic    [8*N_BYTES-1:0]   o_out_data
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
    localparam CLOCK_CYCLES_8  = NUM_WORDS / 8;  //2 cycle
    localparam CLOCK_CYCLES_4  = NUM_WORDS / 4;  //4 cycle

    logic [1:0] cycle_count;

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
                //====================================================
                DEGRADE_LANES_0_TO_15: begin
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
                        i_lane_3[7:0],    i_lane_2[7:0],    i_lane_1[7:0],    i_lane_0[7:0]
                    };
                    if (int'(cycle_count) == CLOCK_CYCLES_16-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

                //====================================================
                // x8 MODE (LANES 0–7)
                //====================================================
                DEGRADE_LANES_0_TO_7: begin
                    case (cycle_count)
                        0: o_out_data[4*N_BYTES-1:0] <= {
                            i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                            i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],

                            i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                            i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],

                            i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                            i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],

                            i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0],
                            i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]
                        };

                        1: o_out_data[8*N_BYTES-1:4*N_BYTES] <= {
                            i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                            i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],

                            i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                            i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],

                            i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                            i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],

                            i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0],
                            i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]
                        };
                        default : o_out_data <= 0;
                    endcase
                    if (int'(cycle_count) == CLOCK_CYCLES_8-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

                //====================================================
                // x8 MODE (LANES 8–15)
                //====================================================
                DEGRADE_LANES_8_TO_15: begin
                    case (cycle_count)
                        0: o_out_data[4*N_BYTES-1:0] <= {
                            i_lane_15[31:24], i_lane_14[31:24], i_lane_13[31:24], i_lane_12[31:24],
                            i_lane_11[31:24], i_lane_10[31:24], i_lane_9[31:24],  i_lane_8[31:24],

                            i_lane_15[23:16], i_lane_14[23:16], i_lane_13[23:16], i_lane_12[23:16],
                            i_lane_11[23:16], i_lane_10[23:16], i_lane_9[23:16],  i_lane_8[23:16],

                            i_lane_15[15:8],  i_lane_14[15:8],  i_lane_13[15:8],  i_lane_12[15:8],
                            i_lane_11[15:8],  i_lane_10[15:8],  i_lane_9[15:8],   i_lane_8[15:8],

                            i_lane_15[7:0],   i_lane_14[7:0],   i_lane_13[7:0],   i_lane_12[7:0],
                            i_lane_11[7:0],   i_lane_10[7:0],   i_lane_9[7:0],    i_lane_8[7:0]
                        };

                        1: o_out_data[8*N_BYTES-1:4*N_BYTES] <= {
                            i_lane_15[31:24], i_lane_14[31:24], i_lane_13[31:24], i_lane_12[31:24],
                            i_lane_11[31:24], i_lane_10[31:24], i_lane_9[31:24],  i_lane_8[31:24],

                            i_lane_15[23:16], i_lane_14[23:16], i_lane_13[23:16], i_lane_12[23:16],
                            i_lane_11[23:16], i_lane_10[23:16], i_lane_9[23:16],  i_lane_8[23:16],

                            i_lane_15[15:8],  i_lane_14[15:8],  i_lane_13[15:8],  i_lane_12[15:8],
                            i_lane_11[15:8],  i_lane_10[15:8],  i_lane_9[15:8],   i_lane_8[15:8],

                            i_lane_15[7:0],   i_lane_14[7:0],   i_lane_13[7:0],   i_lane_12[7:0],
                            i_lane_11[7:0],   i_lane_10[7:0],   i_lane_9[7:0],    i_lane_8[7:0]
                        };
                        default: o_out_data <= 0;   
                    endcase
                    if (int'(cycle_count) == CLOCK_CYCLES_8-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

                //====================================================
                // x4 MODES
                //====================================================
                DEGRADE_LANES_0_TO_3: begin
                    case (cycle_count)
                        0: o_out_data[2*N_BYTES-1:0] <= {
                            i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],
                            i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],
                            i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],
                            i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]
                        };
                       
                        1: o_out_data[4*N_BYTES-1:2*N_BYTES] <= {
                            i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],
                            i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],
                            i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],
                            i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]
                        };
                       
                        2: o_out_data[6*N_BYTES-1:4*N_BYTES] <= {
                            i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],
                            i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],
                            i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],
                            i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]
                        };
                       
                        3: o_out_data[8*N_BYTES-1:6*N_BYTES] <= {
                            i_lane_3[31:24], i_lane_2[31:24], i_lane_1[31:24], i_lane_0[31:24],
                            i_lane_3[23:16], i_lane_2[23:16], i_lane_1[23:16], i_lane_0[23:16],
                            i_lane_3[15:8],  i_lane_2[15:8],  i_lane_1[15:8],  i_lane_0[15:8],
                            i_lane_3[7:0],   i_lane_2[7:0],   i_lane_1[7:0],   i_lane_0[7:0]
                        };
                        default : o_out_data <= 0;
                    endcase
                    if (int'(cycle_count) == CLOCK_CYCLES_4-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1;
                    end
                end

                DEGRADE_LANES_4_TO_7: begin
                    case (cycle_count)
                        0: o_out_data[2*N_BYTES-1:0] <= {
                            i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                            i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                            i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                            i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0]
                        };
                       
                        1: o_out_data[4*N_BYTES-1:2*N_BYTES] <= {
                            i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                            i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                            i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                            i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0]
                        };
                       
                        2: o_out_data[6*N_BYTES-1:4*N_BYTES] <= {
                            i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                            i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                            i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                            i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0]
                        };
                       
                        3: o_out_data[8*N_BYTES-1:6*N_BYTES] <= {
                            i_lane_7[31:24], i_lane_6[31:24], i_lane_5[31:24], i_lane_4[31:24],
                            i_lane_7[23:16], i_lane_6[23:16], i_lane_5[23:16], i_lane_4[23:16],
                            i_lane_7[15:8],  i_lane_6[15:8],  i_lane_5[15:8],  i_lane_4[15:8],
                            i_lane_7[7:0],   i_lane_6[7:0],   i_lane_5[7:0],   i_lane_4[7:0]
                        };
                        default : o_out_data <= 0;
                    endcase
                    if (int'(cycle_count) == CLOCK_CYCLES_4-1) begin
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
