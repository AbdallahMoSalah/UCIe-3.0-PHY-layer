`timescale 1ns/1ps

module Mapper_tb;

parameter WIDTH = 32;

reg                 i_clk;
reg                 i_rst_n;
reg                 mapper_en;
reg  [2:0]          i_width_deg_map;
reg  [511:0]        i_in_data;

wire [WIDTH-1:0]    o_lane [0:15];

integer correct_count;
integer error_count;
integer i;

// =====================================================
// DUT
// =====================================================
Mapper DUT (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .mapper_en(mapper_en),
    .i_width_deg_map(i_width_deg_map),
    .i_in_data(i_in_data),

    .o_lane_0(o_lane[0]),
    .o_lane_1(o_lane[1]),
    .o_lane_2(o_lane[2]),
    .o_lane_3(o_lane[3]),
    .o_lane_4(o_lane[4]),
    .o_lane_5(o_lane[5]),
    .o_lane_6(o_lane[6]),
    .o_lane_7(o_lane[7]),
    .o_lane_8(o_lane[8]),
    .o_lane_9(o_lane[9]),
    .o_lane_10(o_lane[10]),
    .o_lane_11(o_lane[11]),
    .o_lane_12(o_lane[12]),
    .o_lane_13(o_lane[13]),
    .o_lane_14(o_lane[14]),
    .o_lane_15(o_lane[15])
);

// =====================================================
// CLOCK
// =====================================================
always #5 i_clk = ~i_clk;

// =====================================================
// RESET
// =====================================================
initial begin
    i_clk = 0;
    i_rst_n = 0;
    mapper_en = 0;
    i_width_deg_map = 0;
    i_in_data = 0;
    correct_count = 0;
    error_count = 0;

    #20 i_rst_n = 1;
end

// =====================================================
// MAIN TEST
// =====================================================
initial begin
    @(posedge i_rst_n);

    generate_pattern();

    run_mode(3'b011, 1);  // x16
    run_mode(3'b001, 2);  // x8 
    run_mode(3'b010, 2);  // x8
    run_mode(3'b100, 4);  // x4 group 
    run_mode(3'b101, 4);  // x4 group 

    #20;

    $display("=================================");
    $display("Correct Count = %0d", correct_count);
    $display("Error Count   = %0d", error_count);
    $display("=================================");

    if (error_count == 0)
        $display("TEST PASSED ✅");
    else
        $display("TEST FAILED ❌");

    $stop;
end

// =====================================================
// PATTERN GENERATOR
// =====================================================
task generate_pattern;
begin
    for (i = 0; i < 64; i = i + 1)
        i_in_data[i*8 +: 8] = i;
end
endtask

// =====================================================
// RUN MODE
// =====================================================
task run_mode;
input [2:0] mode;
input integer cycles;
integer c;
begin
    i_width_deg_map = mode;
    mapper_en = 1;

    for (c = 0; c < cycles; c = c + 1) begin
        @(posedge i_clk);
        #1;
        check_output(mode, c);
    end

    mapper_en = 0;
    @(posedge i_clk);
end
endtask

// =====================================================
// CHECKER (Golden Model)
// =====================================================
task check_output;
input [2:0] mode;
input integer cycle;

reg [WIDTH-1:0] expected [0:15];
integer j;

begin
    for (j = 0; j < 16; j = j + 1)
        expected[j] = 0;

    case(mode)

    // ==============================
    // x16 MODE
    // ==============================
    3'b011: begin
        for (j = 0; j < 16; j = j + 1)
            expected[j] = {
                i_in_data[(j)*8 +: 8],
                i_in_data[(j+16)*8 +: 8],
                i_in_data[(j+32)*8 +: 8],
                i_in_data[(j+48)*8 +: 8]
            };
    end

    // ==============================
    // x8 MODE (lanes 0–7)
    // ==============================
    3'b001: begin
        for (j = 0; j < 8; j = j + 1)
            expected[j] = {
                i_in_data[(j + cycle*32)*8 +: 8],
                i_in_data[(j+8 + cycle*32)*8 +: 8],
                i_in_data[(j+16 + cycle*32)*8 +: 8],
                i_in_data[(j+24 + cycle*32)*8 +: 8]
            };
    end

    // ==============================
    // x8 MODE (lanes 8–15)
    // ==============================
    3'b010: begin
        for (j = 8; j < 16; j = j + 1)
            expected[j] = {
                i_in_data[(j-8 + cycle*32)*8 +: 8],
                i_in_data[(j-8+8 + cycle*32)*8 +: 8],
                i_in_data[(j-8+16 + cycle*32)*8 +: 8],
                i_in_data[(j-8+24 + cycle*32)*8 +: 8]
            };
    end

    // ==============================
    // x4 MODE (lanes 0–3)
    // ==============================
    3'b100: begin
        for (j = 0; j < 4; j = j + 1)
            expected[j] = {
                i_in_data[(j + cycle*16)*8 +: 8],
                i_in_data[(j+4 + cycle*16)*8 +: 8],
                i_in_data[(j+8 + cycle*16)*8 +: 8],
                i_in_data[(j+12 + cycle*16)*8 +: 8]
            };
    end

    // ==============================
    // x4 MODE (lanes 4–7)
    // ==============================
    3'b101: begin
        for (j = 4; j < 8; j = j + 1)
            expected[j] = {
                i_in_data[(j-4 + cycle*16)*8 +: 8],
                i_in_data[(j-4+4 + cycle*16)*8 +: 8],
                i_in_data[(j-4+8 + cycle*16)*8 +: 8],
                i_in_data[(j-4+12 + cycle*16)*8 +: 8]
            };
    end

    endcase

    // ==============================
    // COMPARE
    // ==============================
    for (j = 0; j < 16; j = j + 1) begin
        if (o_lane[j] === expected[j])
            correct_count++;
        else begin
            error_count++;
            $display("Mismatch @ lane %0d | Expected=%h | Got=%h",
                     j, expected[j], o_lane[j]);
        end
    end

end
endtask

endmodule