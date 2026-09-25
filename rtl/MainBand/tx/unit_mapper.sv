module unit_mapper #(
    parameter WIDTH      = 32,
    parameter NUM_LANES  = 16,
    parameter N_BYTES    = 64
)(
    input  wire                      i_clk,
    input  wire                      i_rst_n,
    input  wire [8*N_BYTES-1:0]      i_in_data,
    input  wire                      mapper_en,
    input  wire [2:0]                i_width_deg_map,
    input  wire                      lp_irdy,
    input  wire                      lp_valid,

    output reg  [WIDTH-1:0] o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3,
    output reg  [WIDTH-1:0] o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7,
    output reg  [WIDTH-1:0] o_lane_8,  o_lane_9,  o_lane_10, o_lane_11,
    output reg  [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15,
    output reg              out_scramble_en,
    output reg              mapper_ready // pl_trdy
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
    localparam N_BYTE_PER_LANE = WIDTH / 8;                    // 4 bytes per lane at 32-bit width
    localparam NUM_WORDS       = N_BYTES / N_BYTE_PER_LANE;    // Total words per flit

    localparam CLOCK_CYCLES_16 = (NUM_WORDS + 15) / 16;  // Cycles needed when 16 lanes active
    localparam CLOCK_CYCLES_8  = (NUM_WORDS + 7) / 8;    // Cycles needed when 8 lanes active
    localparam CLOCK_CYCLES_4  = (NUM_WORDS + 3) / 4;    // Cycles needed when 4 lanes active

    //============================================================
    // Skid Buffer (1-Entry)
    //============================================================
    // Cycle Counter
    reg [1:0] cycle_count;

    // Skid Buffer (1-Entry)
    reg [8*N_BYTES-1:0] buf_data;
    reg                 buf_full;

    // Packet done determines when the transmission completes
    wire packet_done = buf_full && (
        ((i_width_deg_map == DEGRADE_LANES_0_TO_15) && (int'(cycle_count) == CLOCK_CYCLES_16 - 1)) ||
        (((i_width_deg_map == DEGRADE_LANES_0_TO_7) || (i_width_deg_map == DEGRADE_LANES_8_TO_15)) && (int'(cycle_count) == CLOCK_CYCLES_8 - 1)) ||
        (((i_width_deg_map == DEGRADE_LANES_0_TO_3) || (i_width_deg_map == DEGRADE_LANES_4_TO_7)) && (int'(cycle_count) == CLOCK_CYCLES_4 - 1)) ||
        // Fallback for safety on unsupported/default modes
        (i_width_deg_map != DEGRADE_LANES_0_TO_15 && 
         i_width_deg_map != DEGRADE_LANES_0_TO_7 && 
         i_width_deg_map != DEGRADE_LANES_8_TO_15 && 
         i_width_deg_map != DEGRADE_LANES_0_TO_3 && 
         i_width_deg_map != DEGRADE_LANES_4_TO_7)
    );

    // mapper_ready is high when buffer is empty or transmission is done
    assign mapper_ready = (mapper_en && i_rst_n) ? (!buf_full || packet_done) : 1'b0;

    // Push when input is valid and unit_mapper is ready to accept
    wire push = lp_valid && lp_irdy && mapper_ready;

    wire pop = packet_done;

    // Skid Buffer Sequential Logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            buf_full <= 1'b0;
            buf_data <= {8*N_BYTES{1'b0}};
        end else if (mapper_en) begin
            if (push) begin
                buf_data <= i_in_data;
                buf_full <= 1'b1;
            end else if (pop) begin
                buf_full <= 1'b0;
            end
        end else begin
            buf_full <= 1'b0;
        end
    end

    // Cycle Counter Logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count <= 2'd0;
        end else if (mapper_en) begin
            if (buf_full) begin
                if (packet_done) begin
                    cycle_count <= 2'd0;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end else begin
                cycle_count <= 2'd0;
            end
        end else begin
            cycle_count <= 2'd0;
        end
    end

    //============================================================
    // Outputs Logic (Scramble Enable and Parameterized Lane Mapping)
    //============================================================
    wire [8*N_BYTES-1:0] map_src   = push ? i_in_data : buf_data;
    wire [1:0]           map_cycle = push ? 2'd0 : (cycle_count + 1'b1);

    logic [WIDTH-1:0] lane_next [16];

    always_comb begin
        for (int k = 0; k < 16; k++) begin
            lane_next[k] = {WIDTH{1'b0}};
        end

        if (push || (buf_full && !packet_done)) begin
            case (i_width_deg_map)
                DEGRADE_LANES_0_TO_15: begin
                    for (int k = 0; k < 16; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (map_cycle * 16 + k) + p * 16;
                            if (byte_idx < N_BYTES) begin
                                lane_next[k][p*8 +: 8] = map_src[byte_idx*8 +: 8];
                            end
                        end
                    end
                end

                DEGRADE_LANES_0_TO_7: begin
                    for (int k = 0; k < 8; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (map_cycle * 8 + k) + p * 8;
                            if (byte_idx < N_BYTES) begin
                                lane_next[k][p*8 +: 8] = map_src[byte_idx*8 +: 8];
                            end
                        end
                    end
                end

                DEGRADE_LANES_8_TO_15: begin
                    for (int k = 0; k < 8; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (map_cycle * 8 + k) + p * 8;
                            if (byte_idx < N_BYTES) begin
                                lane_next[8 + k][p*8 +: 8] = map_src[byte_idx*8 +: 8];
                            end
                        end
                    end
                end

                DEGRADE_LANES_0_TO_3: begin
                    for (int k = 0; k < 4; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (map_cycle * 4 + k) + p * 4;
                            if (byte_idx < N_BYTES) begin
                                lane_next[k][p*8 +: 8] = map_src[byte_idx*8 +: 8];
                            end
                        end
                    end
                end

                DEGRADE_LANES_4_TO_7: begin
                    for (int k = 0; k < 4; k++) begin
                        for (int p = 0; p < N_BYTE_PER_LANE; p++) begin
                            int byte_idx;
                            byte_idx = (map_cycle * 4 + k) + p * 4;
                            if (byte_idx < N_BYTES) begin
                                lane_next[4 + k][p*8 +: 8] = map_src[byte_idx*8 +: 8];
                            end
                        end
                    end
                end

                default: begin
                    for (int k = 0; k < 16; k++) begin
                        lane_next[k] = {WIDTH{1'b0}};
                    end
                end
            endcase
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            out_scramble_en <= 1'b0;
            o_lane_0        <= {WIDTH{1'b0}};
            o_lane_1        <= {WIDTH{1'b0}};
            o_lane_2        <= {WIDTH{1'b0}};
            o_lane_3        <= {WIDTH{1'b0}};
            o_lane_4        <= {WIDTH{1'b0}};
            o_lane_5        <= {WIDTH{1'b0}};
            o_lane_6        <= {WIDTH{1'b0}};
            o_lane_7        <= {WIDTH{1'b0}};
            o_lane_8        <= {WIDTH{1'b0}};
            o_lane_9        <= {WIDTH{1'b0}};
            o_lane_10       <= {WIDTH{1'b0}};
            o_lane_11       <= {WIDTH{1'b0}};
            o_lane_12       <= {WIDTH{1'b0}};
            o_lane_13       <= {WIDTH{1'b0}};
            o_lane_14       <= {WIDTH{1'b0}};
            o_lane_15       <= {WIDTH{1'b0}};
        end else if (mapper_en) begin
            if (push || (buf_full && !packet_done)) begin
                out_scramble_en <= 1'b1;
                o_lane_0        <= lane_next[0];
                o_lane_1        <= lane_next[1];
                o_lane_2        <= lane_next[2];
                o_lane_3        <= lane_next[3];
                o_lane_4        <= lane_next[4];
                o_lane_5        <= lane_next[5];
                o_lane_6        <= lane_next[6];
                o_lane_7        <= lane_next[7];
                o_lane_8        <= lane_next[8];
                o_lane_9        <= lane_next[9];
                o_lane_10       <= lane_next[10];
                o_lane_11       <= lane_next[11];
                o_lane_12       <= lane_next[12];
                o_lane_13       <= lane_next[13];
                o_lane_14       <= lane_next[14];
                o_lane_15       <= lane_next[15];
            end else begin
                out_scramble_en <= 1'b0;
                o_lane_0        <= {WIDTH{1'b0}};
                o_lane_1        <= {WIDTH{1'b0}};
                o_lane_2        <= {WIDTH{1'b0}};
                o_lane_3        <= {WIDTH{1'b0}};
                o_lane_4        <= {WIDTH{1'b0}};
                o_lane_5        <= {WIDTH{1'b0}};
                o_lane_6        <= {WIDTH{1'b0}};
                o_lane_7        <= {WIDTH{1'b0}};
                o_lane_8        <= {WIDTH{1'b0}};
                o_lane_9        <= {WIDTH{1'b0}};
                o_lane_10       <= {WIDTH{1'b0}};
                o_lane_11       <= {WIDTH{1'b0}};
                o_lane_12       <= {WIDTH{1'b0}};
                o_lane_13       <= {WIDTH{1'b0}};
                o_lane_14       <= {WIDTH{1'b0}};
                o_lane_15       <= {WIDTH{1'b0}};
            end
        end else begin
            out_scramble_en <= 1'b0;
            o_lane_0        <= {WIDTH{1'b0}};
            o_lane_1        <= {WIDTH{1'b0}};
            o_lane_2        <= {WIDTH{1'b0}};
            o_lane_3        <= {WIDTH{1'b0}};
            o_lane_4        <= {WIDTH{1'b0}};
            o_lane_5        <= {WIDTH{1'b0}};
            o_lane_6        <= {WIDTH{1'b0}};
            o_lane_7        <= {WIDTH{1'b0}};
            o_lane_8        <= {WIDTH{1'b0}};
            o_lane_9        <= {WIDTH{1'b0}};
            o_lane_10       <= {WIDTH{1'b0}};
            o_lane_11       <= {WIDTH{1'b0}};
            o_lane_12       <= {WIDTH{1'b0}};
            o_lane_13       <= {WIDTH{1'b0}};
            o_lane_14       <= {WIDTH{1'b0}};
            o_lane_15       <= {WIDTH{1'b0}};
        end
    end

endmodule
