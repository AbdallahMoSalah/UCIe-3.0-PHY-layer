module unit_demapper #(
    parameter N_BYTES   = 64,
    parameter NUM_LANES = 16,
    parameter WIDTH     = 32
) (
    input  logic                     i_clk,
    input  logic                     i_rst_n,
    input  logic   [WIDTH-1:0]       i_lane_0,  i_lane_1,  i_lane_2,  i_lane_3,
    input  logic   [WIDTH-1:0]       i_lane_4,  i_lane_5,  i_lane_6,  i_lane_7,
    input  logic   [WIDTH-1:0]       i_lane_8,  i_lane_9,  i_lane_10, i_lane_11,
    input  logic   [WIDTH-1:0]       i_lane_12, i_lane_13, i_lane_14, i_lane_15,
    input  logic                     demapper_en,
    input  logic                     rx_data_valid,
    input  logic [2:0]               i_width_deg_demap,
    output logic                     pl_valid,
    output logic   [8*N_BYTES-1:0]   o_out_data
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

    localparam CLOCK_CYCLES_16 = (NUM_WORDS + 15) / 16;
    localparam CLOCK_CYCLES_8  = (NUM_WORDS + 7) / 8;
    localparam CLOCK_CYCLES_4  = (NUM_WORDS + 3) / 4;

    logic [1:0] cycle_count;

    wire [WIDTH-1:0] lane_in [16];
    assign lane_in[0]  = i_lane_0;
    assign lane_in[1]  = i_lane_1;
    assign lane_in[2]  = i_lane_2;
    assign lane_in[3]  = i_lane_3;
    assign lane_in[4]  = i_lane_4;
    assign lane_in[5]  = i_lane_5;
    assign lane_in[6]  = i_lane_6;
    assign lane_in[7]  = i_lane_7;
    assign lane_in[8]  = i_lane_8;
    assign lane_in[9]  = i_lane_9;
    assign lane_in[10] = i_lane_10;
    assign lane_in[11] = i_lane_11;
    assign lane_in[12] = i_lane_12;
    assign lane_in[13] = i_lane_13;
    assign lane_in[14] = i_lane_14;
    assign lane_in[15] = i_lane_15;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count <= 2'd0;
            pl_valid    <= 1'b0;
            o_out_data  <= {8*N_BYTES{1'b0}};
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
                    for (int k = 0; k < 16; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (int'(cycle_count) * 16 + k) + p * 16;
                            if (byte_idx < N_BYTES) begin
                                o_out_data[byte_idx*8 +: 8] <= lane_in[k][p*8 +: 8];
                            end
                        end
                    end
                    if (int'(cycle_count) == CLOCK_CYCLES_16-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                //====================================================
                // x8 MODE (LANES 0–7)
                //====================================================
                DEGRADE_LANES_0_TO_7: begin
                    for (int k = 0; k < 8; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (int'(cycle_count) * 8 + k) + p * 8;
                            if (byte_idx < N_BYTES) begin
                                o_out_data[byte_idx*8 +: 8] <= lane_in[k][p*8 +: 8];
                            end
                        end
                    end
                    if (int'(cycle_count) == CLOCK_CYCLES_8-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                //====================================================
                // x8 MODE (LANES 8–15)
                //====================================================
                DEGRADE_LANES_8_TO_15: begin
                    for (int k = 0; k < 8; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (int'(cycle_count) * 8 + k) + p * 8;
                            if (byte_idx < N_BYTES) begin
                                o_out_data[byte_idx*8 +: 8] <= lane_in[8 + k][p*8 +: 8];
                            end
                        end
                    end
                    if (int'(cycle_count) == CLOCK_CYCLES_8-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                //====================================================
                // x4 MODES
                //====================================================
                DEGRADE_LANES_0_TO_3: begin
                    for (int k = 0; k < 4; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (int'(cycle_count) * 4 + k) + p * 4;
                            if (byte_idx < N_BYTES) begin
                                o_out_data[byte_idx*8 +: 8] <= lane_in[k][p*8 +: 8];
                            end
                        end
                    end
                    if (int'(cycle_count) == CLOCK_CYCLES_4-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                DEGRADE_LANES_4_TO_7: begin
                    for (int k = 0; k < 4; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (int'(cycle_count) * 4 + k) + p * 4;
                            if (byte_idx < N_BYTES) begin
                                o_out_data[byte_idx*8 +: 8] <= lane_in[4 + k][p*8 +: 8];
                            end
                        end
                    end
                    if (int'(cycle_count) == CLOCK_CYCLES_4-1) begin
                        pl_valid    <= 1'b1;
                        cycle_count <= 2'd0;
                    end
                    else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                default: begin
                    cycle_count <= 2'd0;
                end

                endcase
            end
            else if (!demapper_en) begin
                cycle_count <= 2'd0;
                o_out_data  <= {8*N_BYTES{1'b0}};
            end
        end
    end

endmodule
