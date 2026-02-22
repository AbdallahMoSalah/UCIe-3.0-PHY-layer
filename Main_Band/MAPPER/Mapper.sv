module Mapper #(
    parameter WIDTH      = 32,
    parameter NUM_LANES  = 16,
    parameter N_BYTES    = 64
)(
    input  wire                     i_clk,
    input  wire                     i_rst_n,
    input  wire [8*N_BYTES-1:0]     i_in_data,
    input  wire                     mapper_en,
    input  wire [2:0]               i_width_deg_map,

    output reg  [WIDTH-1:0] o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3,
    output reg  [WIDTH-1:0] o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7,
    output reg  [WIDTH-1:0] o_lane_8,  o_lane_9,  o_lane_10, o_lane_11,
    output reg  [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15
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
    localparam N_BYTE_PER_LANE = WIDTH / 8;          // 4 bytes
    localparam NUM_WORDS       = N_BYTES / N_BYTE_PER_LANE; // 16 words

    localparam CLOCK_CYCLES_16 = NUM_WORDS / 16; // 1
    localparam CLOCK_CYCLES_8  = NUM_WORDS / 8;  // 2
    localparam CLOCK_CYCLES_4  = NUM_WORDS / 4;  // 4

    //============================================================
    // Internal Registers
    //============================================================
    reg [$clog2(CLOCK_CYCLES_4)-1:0] cycle_count;
    reg [WIDTH-1:0] lane_data [0:NUM_LANES-1];
    reg [8*N_BYTES-1:0] data_shift_reg;

    integer i;

    //============================================================
    // Sequential Logic
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count    <= 0;
            data_shift_reg <= 0;

            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i] <= 0;
        end

        else if (mapper_en) begin

            // Clear lanes every cycle
            for (i = 0; i < NUM_LANES; i = i + 1)
                lane_data[i] <= 0;

            case (i_width_deg_map)

            //====================================================
            // 16 Lanes Active
            //====================================================
            DEGRADE_LANES_0_TO_15: begin
                if (cycle_count < CLOCK_CYCLES_16) begin

                    if (cycle_count == 0)
                        data_shift_reg <= i_in_data;

                    for (i = 0; i < 16; i = i + 1)
                        lane_data[i] <= data_shift_reg[i*WIDTH +: WIDTH];

                    data_shift_reg <= data_shift_reg >> (16*WIDTH);
                    cycle_count    <= cycle_count + 1;
                end
                else
                    cycle_count <= 0;
            end

            //====================================================
            // Lanes 0 → 7
            //====================================================
            DEGRADE_LANES_0_TO_7: begin
                if (cycle_count < CLOCK_CYCLES_8) begin

                    if (cycle_count == 0)
                        data_shift_reg <= i_in_data;

                    for (i = 0; i < 8; i = i + 1)
                        lane_data[i] <= data_shift_reg[i*WIDTH +: WIDTH];

                    data_shift_reg <= data_shift_reg >> (8*WIDTH);
                    cycle_count    <= cycle_count + 1;
                end
                else
                    cycle_count <= 0;
            end

            //====================================================
            // Lanes 8 → 15
            //====================================================
            DEGRADE_LANES_8_TO_15: begin
                if (cycle_count < CLOCK_CYCLES_8) begin

                    if (cycle_count == 0)
                        data_shift_reg <= i_in_data;

                    for (i = 0; i < 8; i = i + 1)
                        lane_data[8+i] <= data_shift_reg[i*WIDTH +: WIDTH];

                    data_shift_reg <= data_shift_reg >> (8*WIDTH);
                    cycle_count    <= cycle_count + 1;
                end
                else
                    cycle_count <= 0;
            end

            //====================================================
            // Lanes 0 → 3
            //====================================================
            DEGRADE_LANES_0_TO_3: begin
                if (cycle_count < CLOCK_CYCLES_4) begin

                    if (cycle_count == 0)
                        data_shift_reg <= i_in_data;

                    for (i = 0; i < 4; i = i + 1)
                        lane_data[i] <= data_shift_reg[i*WIDTH +: WIDTH];

                    data_shift_reg <= data_shift_reg >> (4*WIDTH);
                    cycle_count    <= cycle_count + 1;
                end
                else
                    cycle_count <= 0;
            end

            //====================================================
            // Lanes 4 → 7
            //====================================================
            DEGRADE_LANES_4_TO_7: begin
                if (cycle_count < CLOCK_CYCLES_4) begin

                    if (cycle_count == 0)
                        data_shift_reg <= i_in_data;

                    for (i = 0; i < 4; i = i + 1)
                        lane_data[4+i] <= data_shift_reg[i*WIDTH +: WIDTH];

                    data_shift_reg <= data_shift_reg >> (4*WIDTH);
                    cycle_count    <= cycle_count + 1;
                end
                else
                    cycle_count <= 0;
            end

            default: begin
                cycle_count    <= 0;
                data_shift_reg <= 0;
            end

            endcase
        end
        else begin
            cycle_count    <= 0;
            data_shift_reg <= 0;
        end
    end

    //============================================================
    // Output Assignment
    //============================================================
    always @(*) begin
        o_lane_0  = lane_data[0];
        o_lane_1  = lane_data[1];
        o_lane_2  = lane_data[2];
        o_lane_3  = lane_data[3];
        o_lane_4  = lane_data[4];
        o_lane_5  = lane_data[5];
        o_lane_6  = lane_data[6];
        o_lane_7  = lane_data[7];
        o_lane_8  = lane_data[8];
        o_lane_9  = lane_data[9];
        o_lane_10 = lane_data[10];
        o_lane_11 = lane_data[11];
        o_lane_12 = lane_data[12];
        o_lane_13 = lane_data[13];
        o_lane_14 = lane_data[14];
        o_lane_15 = lane_data[15];
    end

endmodule 