
`timescale 1ns/1ps

module mapper_tb;

    // =========================================================
    // Parameters
    // =========================================================
    parameter WIDTH      = 32;
    parameter NUM_LANES  = 16;
    parameter N_BYTES    = 64;

    localparam N_BYTE_PER_LANE = WIDTH / 8;
    localparam NUM_WORDS       = N_BYTES / N_BYTE_PER_LANE;

    // =========================================================
    // DUT Signals
    // =========================================================
    reg                      i_clk;
    reg                      i_rst_n;
    reg  [8*N_BYTES-1:0]     i_in_data;
    reg                      mapper_en;
    reg  [2:0]               i_width_deg_map;

    wire [WIDTH-1:0] o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3;
    wire [WIDTH-1:0] o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7;
    wire [WIDTH-1:0] o_lane_8,  o_lane_9,  o_lane_10, o_lane_11;
    wire [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15;

    // =========================================================
    // Instantiate DUT
    // =========================================================
    Mapper #(
        .WIDTH(WIDTH),
        .NUM_LANES(NUM_LANES),
        .N_BYTES(N_BYTES)
    ) dut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_in_data(i_in_data),
        .mapper_en(mapper_en),
        .i_width_deg_map(i_width_deg_map),

        .o_lane_0(o_lane_0),
        .o_lane_1(o_lane_1),
        .o_lane_2(o_lane_2),
        .o_lane_3(o_lane_3),
        .o_lane_4(o_lane_4),
        .o_lane_5(o_lane_5),
        .o_lane_6(o_lane_6),
        .o_lane_7(o_lane_7),
        .o_lane_8(o_lane_8),
        .o_lane_9(o_lane_9),
        .o_lane_10(o_lane_10),
        .o_lane_11(o_lane_11),
        .o_lane_12(o_lane_12),
        .o_lane_13(o_lane_13),
        .o_lane_14(o_lane_14),
        .o_lane_15(o_lane_15)
    );

    // =========================================================
    // Clock
    // =========================================================
    initial i_clk = 0;
    always #5 i_clk = ~i_clk;

    // =========================================================
    // Reset
    // =========================================================
    task reset_dut;
    begin
        i_rst_n   = 0;
        mapper_en = 0;
        i_in_data = 0;
        #20;
        i_rst_n = 1;
        #10;
    end
    endtask

    // =========================================================
    // Load incremental pattern
    // =========================================================
    task load_input;
begin
    i_in_data = 512'h3F3E3D3C3B3A3938_3736353433323130_2F2E2D2C2B2A2928_2726252423222120_1F1E1D1C1B1A1918_1716151413121110_0F0E0D0C0B0A0908_0706050403020100;
end
endtask

    // =========================================================
    // Simple Mode Test
    // =========================================================
    task run_mode;
        input [2:0] mode;
        input integer cycles;
    begin
        $display("\nRunning mode = %0d", mode);

        i_width_deg_map = mode;
        mapper_en       = 1;

        repeat(cycles) @(posedge i_clk);

        mapper_en = 0;
        @(posedge i_clk);
    end
    endtask

    // =========================================================
    // Test Sequence
    // =========================================================
    initial begin

        reset_dut();
        load_input();

        // 16 lanes → 1 cycle
        run_mode(3'b011, 1);

        // lanes 0-7 → 2 cycles
        run_mode(3'b001, 2);

        // lanes 8-15 → 2 cycles
        run_mode(3'b010, 2);

        // lanes 0-3 → 4 cycles
        run_mode(3'b100, 4);

        // lanes 4-7 → 4 cycles
        run_mode(3'b101, 4);

        $display("\nSimulation Finished.");
        #20;
        $stop;
    end

endmodule
