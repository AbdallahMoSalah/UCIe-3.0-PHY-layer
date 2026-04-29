`timescale 1ns/1ps

module Mapper_tb;

parameter WIDTH = 32;

reg                 i_clk;
reg                 i_rst_n;
reg                 mapper_en;
reg  [2:0]          i_width_deg_map;
reg  [511:0]        i_in_data;
reg                 lp_irdy;
reg                 lp_valid;

wire [WIDTH-1:0]    o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3;
wire [WIDTH-1:0]    o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7;
wire [WIDTH-1:0]    o_lane_8,  o_lane_9,  o_lane_10, o_lane_11;
wire [WIDTH-1:0]    o_lane_12, o_lane_13, o_lane_14, o_lane_15;
wire                out_scramble_en;
wire                mapper_ready;

// Flat reg array used only inside checker (driven by always @(*))
reg [WIDTH-1:0] o_lane [0:15];

integer correct_count;
integer error_count;
integer i;

// =====================================================
// DUT
// =====================================================
Mapper DUT (
    .i_clk           (i_clk),
    .i_rst_n         (i_rst_n),
    .mapper_en       (mapper_en),
    .i_width_deg_map (i_width_deg_map),
    .i_in_data       (i_in_data),
    .lp_irdy         (lp_irdy),
    .lp_valid        (lp_valid),

    .o_lane_0  (o_lane_0),  .o_lane_1  (o_lane_1),
    .o_lane_2  (o_lane_2),  .o_lane_3  (o_lane_3),
    .o_lane_4  (o_lane_4),  .o_lane_5  (o_lane_5),
    .o_lane_6  (o_lane_6),  .o_lane_7  (o_lane_7),
    .o_lane_8  (o_lane_8),  .o_lane_9  (o_lane_9),
    .o_lane_10 (o_lane_10), .o_lane_11 (o_lane_11),
    .o_lane_12 (o_lane_12), .o_lane_13 (o_lane_13),
    .o_lane_14 (o_lane_14), .o_lane_15 (o_lane_15),

    .out_scramble_en    (out_scramble_en),
    .mapper_ready(mapper_ready)
);

// =====================================================
// Mirror wire outputs into flat array (combinational)
// =====================================================
always @(*) begin
    o_lane[0]  = o_lane_0;  o_lane[1]  = o_lane_1;
    o_lane[2]  = o_lane_2;  o_lane[3]  = o_lane_3;
    o_lane[4]  = o_lane_4;  o_lane[5]  = o_lane_5;
    o_lane[6]  = o_lane_6;  o_lane[7]  = o_lane_7;
    o_lane[8]  = o_lane_8;  o_lane[9]  = o_lane_9;
    o_lane[10] = o_lane_10; o_lane[11] = o_lane_11;
    o_lane[12] = o_lane_12; o_lane[13] = o_lane_13;
    o_lane[14] = o_lane_14; o_lane[15] = o_lane_15;
end

// =====================================================
// CLOCK  (period = 10 ns)
// =====================================================
initial i_clk = 0;
always  #5 i_clk = ~i_clk;

// =====================================================
// RESET & INIT
// =====================================================
initial begin
    i_rst_n         = 0;
    mapper_en       = 0;
    i_width_deg_map = 0;
    i_in_data       = 0;
    lp_irdy         = 0;
    lp_valid        = 0;
    correct_count   = 0;
    error_count     = 0;

    repeat(4) @(posedge i_clk);
    i_rst_n = 1;
end

// =====================================================
// MAIN TEST
// =====================================================
initial begin
    @(posedge i_rst_n);
    @(posedge i_clk);

    generate_pattern();

    // Both must be asserted: adapter has data & wants PL to sample
    lp_irdy  = 1;
    lp_valid = 1;

    run_mode(3'b011, 1);   // x16 lanes 0-15 — 1 cycle
    run_mode(3'b001, 2);   // x8  lanes 0-7  — 2 cycles
    run_mode(3'b010, 2);   // x8  lanes 8-15 — 2 cycles
    run_mode(3'b100, 4);   // x4  lanes 0-3  — 4 cycles
    run_mode(3'b101, 4);   // x4  lanes 4-7  — 4 cycles

    $display("--- Stall test: lp_irdy de-asserted mid transfer ---");
    test_stall();

    lp_irdy  = 0;
    lp_valid = 0;
    repeat(4) @(posedge i_clk);

    $display("=================================");
    $display("Correct Count = %0d", correct_count);
    $display("Error Count   = %0d", error_count);
    $display("=================================");

    if (error_count == 0)
        $display("ALL TESTS PASSED");
    else
        $display("TESTS FAILED (%0d errors)", error_count);

    $stop;
end

// =====================================================
// ✅ PATTERN (ثابت = 6)
// =====================================================
task generate_pattern;
begin
    i_in_data = {64{8'd6}};   // كل بايت = 6
end
endtask

// =====================================================
// RUN MODE
// =====================================================
task run_mode;
    input [2:0]   mode;
    input integer num_cycles;
    integer       c;
begin
    i_width_deg_map = mode;
    mapper_en       = 1;

    for (c = 0; c < num_cycles; c = c + 1) begin
        @(posedge i_clk);
        #1;
        check_output(mode, c);
    end

    mapper_en = 0;
    @(posedge i_clk);
end
endtask

// =====================================================
// STALL TEST
// =====================================================
task test_stall;
begin
    i_width_deg_map = 3'b001;
    mapper_en       = 1;
    lp_irdy         = 1;
    lp_valid        = 1;

    @(posedge i_clk); #1;
    check_output(3'b001, 0);

    lp_irdy = 0;
    repeat(3) @(posedge i_clk);

    lp_irdy = 1;

    @(posedge i_clk); #1;
    check_output(3'b001, 1);

    mapper_en = 0;
    lp_irdy   = 1;
    lp_valid  = 1;
    @(posedge i_clk);
end
endtask

// =====================================================
// CHECKER — Golden Model
// ALL declarations before any statements (Verilog-2001)
// =====================================================
task check_output;
    input [2:0]   mode;
    input integer cycle;

    reg [31:0] exp0,  exp1,  exp2,  exp3;
    reg [31:0] exp4,  exp5,  exp6,  exp7;
    reg [31:0] exp8,  exp9,  exp10, exp11;
    reg [31:0] exp12, exp13, exp14, exp15;
    integer    j;
    integer    cm;

begin
    exp0  = 0; exp1  = 0; exp2  = 0; exp3  = 0;
    exp4  = 0; exp5  = 0; exp6  = 0; exp7  = 0;
    exp8  = 0; exp9  = 0; exp10 = 0; exp11 = 0;
    exp12 = 0; exp13 = 0; exp14 = 0; exp15 = 0;

    case (mode)

    3'b011: begin
        exp0  = {i_in_data[ 0*8+:8],i_in_data[16*8+:8],i_in_data[32*8+:8],i_in_data[48*8+:8]};
        exp1  = {i_in_data[ 1*8+:8],i_in_data[17*8+:8],i_in_data[33*8+:8],i_in_data[49*8+:8]};
        exp2  = {i_in_data[ 2*8+:8],i_in_data[18*8+:8],i_in_data[34*8+:8],i_in_data[50*8+:8]};
        exp3  = {i_in_data[ 3*8+:8],i_in_data[19*8+:8],i_in_data[35*8+:8],i_in_data[51*8+:8]};
        exp4  = {i_in_data[ 4*8+:8],i_in_data[20*8+:8],i_in_data[36*8+:8],i_in_data[52*8+:8]};
        exp5  = {i_in_data[ 5*8+:8],i_in_data[21*8+:8],i_in_data[37*8+:8],i_in_data[53*8+:8]};
        exp6  = {i_in_data[ 6*8+:8],i_in_data[22*8+:8],i_in_data[38*8+:8],i_in_data[54*8+:8]};
        exp7  = {i_in_data[ 7*8+:8],i_in_data[23*8+:8],i_in_data[39*8+:8],i_in_data[55*8+:8]};
        exp8  = {i_in_data[ 8*8+:8],i_in_data[24*8+:8],i_in_data[40*8+:8],i_in_data[56*8+:8]};
        exp9  = {i_in_data[ 9*8+:8],i_in_data[25*8+:8],i_in_data[41*8+:8],i_in_data[57*8+:8]};
        exp10 = {i_in_data[10*8+:8],i_in_data[26*8+:8],i_in_data[42*8+:8],i_in_data[58*8+:8]};
        exp11 = {i_in_data[11*8+:8],i_in_data[27*8+:8],i_in_data[43*8+:8],i_in_data[59*8+:8]};
        exp12 = {i_in_data[12*8+:8],i_in_data[28*8+:8],i_in_data[44*8+:8],i_in_data[60*8+:8]};
        exp13 = {i_in_data[13*8+:8],i_in_data[29*8+:8],i_in_data[45*8+:8],i_in_data[61*8+:8]};
        exp14 = {i_in_data[14*8+:8],i_in_data[30*8+:8],i_in_data[46*8+:8],i_in_data[62*8+:8]};
        exp15 = {i_in_data[15*8+:8],i_in_data[31*8+:8],i_in_data[47*8+:8],i_in_data[63*8+:8]};
    end

    3'b001: begin
        cm = cycle % 2;
        exp0 = {i_in_data[(0 +cm*32)*8+:8],i_in_data[(8 +cm*32)*8+:8],
                i_in_data[(16+cm*32)*8+:8],i_in_data[(24+cm*32)*8+:8]};
        exp1 = {i_in_data[(1 +cm*32)*8+:8],i_in_data[(9 +cm*32)*8+:8],
                i_in_data[(17+cm*32)*8+:8],i_in_data[(25+cm*32)*8+:8]};
        exp2 = {i_in_data[(2 +cm*32)*8+:8],i_in_data[(10+cm*32)*8+:8],
                i_in_data[(18+cm*32)*8+:8],i_in_data[(26+cm*32)*8+:8]};
        exp3 = {i_in_data[(3 +cm*32)*8+:8],i_in_data[(11+cm*32)*8+:8],
                i_in_data[(19+cm*32)*8+:8],i_in_data[(27+cm*32)*8+:8]};
        exp4 = {i_in_data[(4 +cm*32)*8+:8],i_in_data[(12+cm*32)*8+:8],
                i_in_data[(20+cm*32)*8+:8],i_in_data[(28+cm*32)*8+:8]};
        exp5 = {i_in_data[(5 +cm*32)*8+:8],i_in_data[(13+cm*32)*8+:8],
                i_in_data[(21+cm*32)*8+:8],i_in_data[(29+cm*32)*8+:8]};
        exp6 = {i_in_data[(6 +cm*32)*8+:8],i_in_data[(14+cm*32)*8+:8],
                i_in_data[(22+cm*32)*8+:8],i_in_data[(30+cm*32)*8+:8]};
        exp7 = {i_in_data[(7 +cm*32)*8+:8],i_in_data[(15+cm*32)*8+:8],
                i_in_data[(23+cm*32)*8+:8],i_in_data[(31+cm*32)*8+:8]};
    end

    3'b010: begin
        cm = cycle % 2;
        exp8  = {i_in_data[(0 +cm*32)*8+:8],i_in_data[(8 +cm*32)*8+:8],
                 i_in_data[(16+cm*32)*8+:8],i_in_data[(24+cm*32)*8+:8]};
        exp9  = {i_in_data[(1 +cm*32)*8+:8],i_in_data[(9 +cm*32)*8+:8],
                 i_in_data[(17+cm*32)*8+:8],i_in_data[(25+cm*32)*8+:8]};
        exp10 = {i_in_data[(2 +cm*32)*8+:8],i_in_data[(10+cm*32)*8+:8],
                 i_in_data[(18+cm*32)*8+:8],i_in_data[(26+cm*32)*8+:8]};
        exp11 = {i_in_data[(3 +cm*32)*8+:8],i_in_data[(11+cm*32)*8+:8],
                 i_in_data[(19+cm*32)*8+:8],i_in_data[(27+cm*32)*8+:8]};
        exp12 = {i_in_data[(4 +cm*32)*8+:8],i_in_data[(12+cm*32)*8+:8],
                 i_in_data[(20+cm*32)*8+:8],i_in_data[(28+cm*32)*8+:8]};
        exp13 = {i_in_data[(5 +cm*32)*8+:8],i_in_data[(13+cm*32)*8+:8],
                 i_in_data[(21+cm*32)*8+:8],i_in_data[(29+cm*32)*8+:8]};
        exp14 = {i_in_data[(6 +cm*32)*8+:8],i_in_data[(14+cm*32)*8+:8],
                 i_in_data[(22+cm*32)*8+:8],i_in_data[(30+cm*32)*8+:8]};
        exp15 = {i_in_data[(7 +cm*32)*8+:8],i_in_data[(15+cm*32)*8+:8],
                 i_in_data[(23+cm*32)*8+:8],i_in_data[(31+cm*32)*8+:8]};
    end

    3'b100: begin
        cm = cycle % 4;
        exp0 = {i_in_data[(0 +cm*16)*8+:8],i_in_data[(4 +cm*16)*8+:8],
                i_in_data[(8 +cm*16)*8+:8],i_in_data[(12+cm*16)*8+:8]};
        exp1 = {i_in_data[(1 +cm*16)*8+:8],i_in_data[(5 +cm*16)*8+:8],
                i_in_data[(9 +cm*16)*8+:8],i_in_data[(13+cm*16)*8+:8]};
        exp2 = {i_in_data[(2 +cm*16)*8+:8],i_in_data[(6 +cm*16)*8+:8],
                i_in_data[(10+cm*16)*8+:8],i_in_data[(14+cm*16)*8+:8]};
        exp3 = {i_in_data[(3 +cm*16)*8+:8],i_in_data[(7 +cm*16)*8+:8],
                i_in_data[(11+cm*16)*8+:8],i_in_data[(15+cm*16)*8+:8]};
    end

    3'b101: begin
        cm = cycle % 4;
        exp4 = {i_in_data[(0 +cm*16)*8+:8],i_in_data[(4 +cm*16)*8+:8],
                i_in_data[(8 +cm*16)*8+:8],i_in_data[(12+cm*16)*8+:8]};
        exp5 = {i_in_data[(1 +cm*16)*8+:8],i_in_data[(5 +cm*16)*8+:8],
                i_in_data[(9 +cm*16)*8+:8],i_in_data[(13+cm*16)*8+:8]};
        exp6 = {i_in_data[(2 +cm*16)*8+:8],i_in_data[(6 +cm*16)*8+:8],
                i_in_data[(10+cm*16)*8+:8],i_in_data[(14+cm*16)*8+:8]};
        exp7 = {i_in_data[(3 +cm*16)*8+:8],i_in_data[(7 +cm*16)*8+:8],
                i_in_data[(11+cm*16)*8+:8],i_in_data[(15+cm*16)*8+:8]};
    end

    endcase

    if (o_lane[0]  !== exp0)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=0  exp=%h got=%h",mode,cycle,exp0, o_lane[0]);  end else correct_count=correct_count+1;
    if (o_lane[1]  !== exp1)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=1  exp=%h got=%h",mode,cycle,exp1, o_lane[1]);  end else correct_count=correct_count+1;
    if (o_lane[2]  !== exp2)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=2  exp=%h got=%h",mode,cycle,exp2, o_lane[2]);  end else correct_count=correct_count+1;
    if (o_lane[3]  !== exp3)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=3  exp=%h got=%h",mode,cycle,exp3, o_lane[3]);  end else correct_count=correct_count+1;
    if (o_lane[4]  !== exp4)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=4  exp=%h got=%h",mode,cycle,exp4, o_lane[4]);  end else correct_count=correct_count+1;
    if (o_lane[5]  !== exp5)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=5  exp=%h got=%h",mode,cycle,exp5, o_lane[5]);  end else correct_count=correct_count+1;
    if (o_lane[6]  !== exp6)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=6  exp=%h got=%h",mode,cycle,exp6, o_lane[6]);  end else correct_count=correct_count+1;
    if (o_lane[7]  !== exp7)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=7  exp=%h got=%h",mode,cycle,exp7, o_lane[7]);  end else correct_count=correct_count+1;
    if (o_lane[8]  !== exp8)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=8  exp=%h got=%h",mode,cycle,exp8, o_lane[8]);  end else correct_count=correct_count+1;
    if (o_lane[9]  !== exp9)  begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=9  exp=%h got=%h",mode,cycle,exp9, o_lane[9]);  end else correct_count=correct_count+1;
    if (o_lane[10] !== exp10) begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=10 exp=%h got=%h",mode,cycle,exp10,o_lane[10]); end else correct_count=correct_count+1;
    if (o_lane[11] !== exp11) begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=11 exp=%h got=%h",mode,cycle,exp11,o_lane[11]); end else correct_count=correct_count+1;
    if (o_lane[12] !== exp12) begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=12 exp=%h got=%h",mode,cycle,exp12,o_lane[12]); end else correct_count=correct_count+1;
    if (o_lane[13] !== exp13) begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=13 exp=%h got=%h",mode,cycle,exp13,o_lane[13]); end else correct_count=correct_count+1;
    if (o_lane[14] !== exp14) begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=14 exp=%h got=%h",mode,cycle,exp14,o_lane[14]); end else correct_count=correct_count+1;
    if (o_lane[15] !== exp15) begin error_count=error_count+1; $display("[ERR] mode=%b cy=%0d lane=15 exp=%h got=%h",mode,cycle,exp15,o_lane[15]); end else correct_count=correct_count+1;

end
endtask

endmodule
