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

    $display("--- Generating Incremental Data Pattern ---");
    generate_pattern();

    // Both must be asserted: adapter has data & wants PL to sample
    lp_irdy  = 1;
    lp_valid = 1;

    $display("--- Running Standard Modes ---");
    run_mode(3'b011, 1);   // x16 lanes 0-15 — 1 cycle
    run_mode(3'b001, 2);   // x8  lanes 0-7  — 2 cycles
    run_mode(3'b010, 2);   // x8  lanes 8-15 — 2 cycles
    run_mode(3'b100, 4);   // x4  lanes 0-3  — 4 cycles
    run_mode(3'b101, 4);   // x4  lanes 4-7  — 4 cycles

    $display("--- Running NONE_DEGRADE (3'b000) Mode ---");
    run_mode(3'b000, 1);   // NONE_DEGRADE — 1 cycle (should drive zero/idle)

    $display("--- Stall tests: lp_irdy de-asserted mid-transfer for all modes ---");
    test_all_stalls();

    $display("--- Mid-Transfer Reset Test ---");
    test_mid_transfer_reset();

    $display("--- pl_trdy Check when Disabled ---");
    test_ready_when_disabled();

    $display("--- pl_trdy Check when Enabled ---");
    test_ready_when_enabled();

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
// ✅ PATTERN (Incremental bytes)
// =====================================================
task generate_pattern;
    integer b;
begin
    for (b = 0; b < 64; b = b + 1) begin
        i_in_data[b*8 +: 8] = b;
    end
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
// STALL TEST TASK FOR A SINGLE MODE
// =====================================================
// Behaviour under test:
//   Once mapper_en=1 the counter runs EVERY clock.
//   When data_active=0 that clock slot outputs zeros
//   (scramble_en=0) but cycle_count still increments.
//   mapper_ready fires exactly num_cycles clocks after
//   enable, regardless of stalls.
// =====================================================
task run_stall_test_on_mode;
    input [2:0]   mode;
    input integer num_cycles;   // flit length in active clocks (no stall)
    integer       total;        // total loop ticks = num_cycles + 1 stall
    integer       c;
begin
    $display("Stall test for mode %b (%0d-cycle flit, 1-clock stall injected at clock 1)",
             mode, num_cycles);
    i_width_deg_map = mode;
    mapper_en       = 1;
    lp_irdy         = 1;
    lp_valid        = 1;

    // For single-cycle modes no stall is possible; run normally.
    if (num_cycles == 1) begin
        @(posedge i_clk); #1;
        if (mapper_ready !== 1'b1) begin
            error_count = error_count + 1;
            $display("[ERR] mode=%b 1-cycle: mapper_ready not asserted!", mode);
        end else correct_count = correct_count + 1;
    end
    else begin
        // Walk through all flit clocks one by one, injecting 1 stall after
        // flit clock 0.  Each posedge (stall or normal) advances cycle_count
        // by 1, so mapper_ready fires exactly on flit clock num_cycles-1.
        // We track flit_clk = how many posedges have been consumed so far.
        begin : stall_block
            integer flit_clk;
            flit_clk = 0;

            // -- flit clock 0 (normal) --
            @(posedge i_clk); #1;
            flit_clk = flit_clk + 1;
            // mapper_ready expected only on flit clock num_cycles-1
            if ((num_cycles == 1) ? (mapper_ready !== 1'b1) : (mapper_ready !== 1'b0)) begin
                error_count = error_count + 1;
                $display("[ERR] mode=%b: mapper_ready wrong after flit clk 0", mode);
            end else correct_count = correct_count + 1;

            // -- stall clock (irdy=0, counts as flit clock 1) --
            lp_irdy = 0;
            @(posedge i_clk); #1;
            // All lanes must be 0, scramble_en=0 during stall
            if (|{o_lane_0, o_lane_1, o_lane_2, o_lane_3,
                  o_lane_4, o_lane_5, o_lane_6, o_lane_7,
                  o_lane_8, o_lane_9, o_lane_10, o_lane_11,
                  o_lane_12,o_lane_13,o_lane_14,o_lane_15}
                || out_scramble_en) begin
                error_count = error_count + 1;
                $display("[ERR] mode=%b: non-zero lane or scramble_en high during stall!", mode);
            end else correct_count = correct_count + 1;
            flit_clk = flit_clk + 1;
            // For 2-cycle modes flit clock 1 is the last: mapper_ready must pulse now
            if (flit_clk == num_cycles) begin
                if (mapper_ready !== 1'b1) begin
                    error_count = error_count + 1;
                    $display("[ERR] mode=%b: mapper_ready not asserted on stall clock (last flit clk)!", mode);
                end else correct_count = correct_count + 1;
            end else begin
                if (mapper_ready !== 1'b0) begin
                    error_count = error_count + 1;
                    $display("[ERR] mode=%b: mapper_ready early on stall clock!", mode);
                end else correct_count = correct_count + 1;
            end
            lp_irdy = 1;

            // -- remaining normal flit clocks (2 … num_cycles-1) --
            while (flit_clk < num_cycles) begin
                @(posedge i_clk); #1;
                flit_clk = flit_clk + 1;
                if (flit_clk == num_cycles) begin
                    // last flit clock
                    if (mapper_ready !== 1'b1) begin
                        error_count = error_count + 1;
                        $display("[ERR] mode=%b: mapper_ready not asserted on last flit clock!", mode);
                    end else correct_count = correct_count + 1;
                end else begin
                    if (mapper_ready !== 1'b0) begin
                        error_count = error_count + 1;
                        $display("[ERR] mode=%b: mapper_ready early at flit clk %0d!", mode, flit_clk);
                    end else correct_count = correct_count + 1;
                end
            end
        end
    end

    mapper_en = 0;
    @(posedge i_clk);
end
endtask

// =====================================================
// STALL ALL ACTIVE MODES
// =====================================================
task test_all_stalls;
begin
    run_stall_test_on_mode(3'b011, 1);
    run_stall_test_on_mode(3'b001, 2);
    run_stall_test_on_mode(3'b010, 2);
    run_stall_test_on_mode(3'b100, 4);
    run_stall_test_on_mode(3'b101, 4);
end
endtask

// =====================================================
// MID-TRANSFER RESET TEST
// =====================================================
task test_mid_transfer_reset;
begin
    $display("Testing reset during a transfer...");
    i_width_deg_map = 3'b100; // x4 mode, 4 cycles
    mapper_en       = 1;
    lp_irdy         = 1;
    lp_valid        = 1;

    // Run 2 cycles first
    @(posedge i_clk);
    @(posedge i_clk);

    // Pulse reset
    i_rst_n = 0;
    @(posedge i_clk);
    i_rst_n = 1;
    #1;

    // Verify all outputs are zeroed immediately after reset
    if (o_lane_0 !== 0 || o_lane_1 !== 0 || o_lane_2 !== 0 || o_lane_3 !== 0 ||
        o_lane_4 !== 0 || o_lane_5 !== 0 || o_lane_6 !== 0 || o_lane_7 !== 0 ||
        o_lane_8 !== 0 || o_lane_9 !== 0 || o_lane_10 !== 0 || o_lane_11 !== 0 ||
        o_lane_12 !== 0 || o_lane_13 !== 0 || o_lane_14 !== 0 || o_lane_15 !== 0 ||
        out_scramble_en !== 0 || mapper_ready !== 0) begin
        error_count = error_count + 1;
        $display("[ERR] Outputs not cleared after synchronous reset!");
    end else begin
        correct_count = correct_count + 1;
        $display("[OK] Outputs successfully cleared by reset.");
    end

    mapper_en = 0;
    @(posedge i_clk);
end
endtask

// =====================================================
// CHECKER — Golden Model
// =====================================================
task check_output;
    input [2:0]   mode;
    input integer cycle;

    reg [31:0] exp0,  exp1,  exp2,  exp3;
    reg [31:0] exp4,  exp5,  exp6,  exp7;
    reg [31:0] exp8,  exp9,  exp10, exp11;
    reg [31:0] exp12, exp13, exp14, exp15;
    integer    cm;

begin
    exp0  = 0; exp1  = 0; exp2  = 0; exp3  = 0;
    exp4  = 0; exp5  = 0; exp6  = 0; exp7  = 0;
    exp8  = 0; exp9  = 0; exp10 = 0; exp11 = 0;
    exp12 = 0; exp13 = 0; exp14 = 0; exp15 = 0;

    case (mode)

    3'b011: begin
        exp0  = {i_in_data[48*8+:8],i_in_data[32*8+:8],i_in_data[16*8+:8],i_in_data[ 0*8+:8]};
        exp1  = {i_in_data[49*8+:8],i_in_data[33*8+:8],i_in_data[17*8+:8],i_in_data[ 1*8+:8]};
        exp2  = {i_in_data[50*8+:8],i_in_data[34*8+:8],i_in_data[18*8+:8],i_in_data[ 2*8+:8]};
        exp3  = {i_in_data[51*8+:8],i_in_data[35*8+:8],i_in_data[19*8+:8],i_in_data[ 3*8+:8]};
        exp4  = {i_in_data[52*8+:8],i_in_data[36*8+:8],i_in_data[20*8+:8],i_in_data[ 4*8+:8]};
        exp5  = {i_in_data[53*8+:8],i_in_data[37*8+:8],i_in_data[21*8+:8],i_in_data[ 5*8+:8]};
        exp6  = {i_in_data[54*8+:8],i_in_data[38*8+:8],i_in_data[22*8+:8],i_in_data[ 6*8+:8]};
        exp7  = {i_in_data[55*8+:8],i_in_data[39*8+:8],i_in_data[23*8+:8],i_in_data[ 7*8+:8]};
        exp8  = {i_in_data[56*8+:8],i_in_data[40*8+:8],i_in_data[24*8+:8],i_in_data[ 8*8+:8]};
        exp9  = {i_in_data[57*8+:8],i_in_data[41*8+:8],i_in_data[25*8+:8],i_in_data[ 9*8+:8]};
        exp10 = {i_in_data[58*8+:8],i_in_data[42*8+:8],i_in_data[26*8+:8],i_in_data[10*8+:8]};
        exp11 = {i_in_data[59*8+:8],i_in_data[43*8+:8],i_in_data[27*8+:8],i_in_data[11*8+:8]};
        exp12 = {i_in_data[60*8+:8],i_in_data[44*8+:8],i_in_data[28*8+:8],i_in_data[12*8+:8]};
        exp13 = {i_in_data[61*8+:8],i_in_data[45*8+:8],i_in_data[29*8+:8],i_in_data[13*8+:8]};
        exp14 = {i_in_data[62*8+:8],i_in_data[46*8+:8],i_in_data[30*8+:8],i_in_data[14*8+:8]};
        exp15 = {i_in_data[63*8+:8],i_in_data[47*8+:8],i_in_data[31*8+:8],i_in_data[15*8+:8]};
    end

    3'b001: begin
        cm = cycle % 2;
        exp0 = {i_in_data[(24+cm*32)*8+:8],i_in_data[(16+cm*32)*8+:8],
                i_in_data[(8 +cm*32)*8+:8],i_in_data[(0 +cm*32)*8+:8]};
        exp1 = {i_in_data[(25+cm*32)*8+:8],i_in_data[(17+cm*32)*8+:8],
                i_in_data[(9 +cm*32)*8+:8],i_in_data[(1 +cm*32)*8+:8]};
        exp2 = {i_in_data[(26+cm*32)*8+:8],i_in_data[(18+cm*32)*8+:8],
                i_in_data[(10+cm*32)*8+:8],i_in_data[(2 +cm*32)*8+:8]};
        exp3 = {i_in_data[(27+cm*32)*8+:8],i_in_data[(19+cm*32)*8+:8],
                i_in_data[(11+cm*32)*8+:8],i_in_data[(3 +cm*32)*8+:8]};
        exp4 = {i_in_data[(28+cm*32)*8+:8],i_in_data[(20+cm*32)*8+:8],
                i_in_data[(12+cm*32)*8+:8],i_in_data[(4 +cm*32)*8+:8]};
        exp5 = {i_in_data[(29+cm*32)*8+:8],i_in_data[(21+cm*32)*8+:8],
                i_in_data[(13+cm*32)*8+:8],i_in_data[(5 +cm*32)*8+:8]};
        exp6 = {i_in_data[(30+cm*32)*8+:8],i_in_data[(22+cm*32)*8+:8],
                i_in_data[(14+cm*32)*8+:8],i_in_data[(6 +cm*32)*8+:8]};
        exp7 = {i_in_data[(31+cm*32)*8+:8],i_in_data[(23+cm*32)*8+:8],
                i_in_data[(15+cm*32)*8+:8],i_in_data[(7 +cm*32)*8+:8]};
    end

    3'b010: begin
        cm = cycle % 2;
        exp8  = {i_in_data[(24+cm*32)*8+:8],i_in_data[(16+cm*32)*8+:8],
                 i_in_data[(8 +cm*32)*8+:8],i_in_data[(0 +cm*32)*8+:8]};
        exp9  = {i_in_data[(25+cm*32)*8+:8],i_in_data[(17+cm*32)*8+:8],
                 i_in_data[(9 +cm*32)*8+:8],i_in_data[(1 +cm*32)*8+:8]};
        exp10 = {i_in_data[(26+cm*32)*8+:8],i_in_data[(18+cm*32)*8+:8],
                 i_in_data[(10+cm*32)*8+:8],i_in_data[(2 +cm*32)*8+:8]};
        exp11 = {i_in_data[(27+cm*32)*8+:8],i_in_data[(19+cm*32)*8+:8],
                 i_in_data[(11+cm*32)*8+:8],i_in_data[(3 +cm*32)*8+:8]};
        exp12 = {i_in_data[(28+cm*32)*8+:8],i_in_data[(20+cm*32)*8+:8],
                 i_in_data[(12+cm*32)*8+:8],i_in_data[(4 +cm*32)*8+:8]};
        exp13 = {i_in_data[(29+cm*32)*8+:8],i_in_data[(21+cm*32)*8+:8],
                 i_in_data[(13+cm*32)*8+:8],i_in_data[(5 +cm*32)*8+:8]};
        exp14 = {i_in_data[(30+cm*32)*8+:8],i_in_data[(22+cm*32)*8+:8],
                 i_in_data[(14+cm*32)*8+:8],i_in_data[(6 +cm*32)*8+:8]};
        exp15 = {i_in_data[(31+cm*32)*8+:8],i_in_data[(23+cm*32)*8+:8],
                 i_in_data[(15+cm*32)*8+:8],i_in_data[(7 +cm*32)*8+:8]};
    end

    3'b100: begin
        cm = cycle % 4;
        exp0 = {i_in_data[(12+cm*16)*8+:8],i_in_data[(8 +cm*16)*8+:8],
                i_in_data[(4 +cm*16)*8+:8],i_in_data[(0 +cm*16)*8+:8]};
        exp1 = {i_in_data[(13+cm*16)*8+:8],i_in_data[(9 +cm*16)*8+:8],
                i_in_data[(5 +cm*16)*8+:8],i_in_data[(1 +cm*16)*8+:8]};
        exp2 = {i_in_data[(14+cm*16)*8+:8],i_in_data[(10+cm*16)*8+:8],
                i_in_data[(6 +cm*16)*8+:8],i_in_data[(2 +cm*16)*8+:8]};
        exp3 = {i_in_data[(15+cm*16)*8+:8],i_in_data[(11+cm*16)*8+:8],
                i_in_data[(7 +cm*16)*8+:8],i_in_data[(3 +cm*16)*8+:8]};
    end

    3'b101: begin
        cm = cycle % 4;
        exp4 = {i_in_data[(12+cm*16)*8+:8],i_in_data[(8 +cm*16)*8+:8],
                i_in_data[(4 +cm*16)*8+:8],i_in_data[(0 +cm*16)*8+:8]};
        exp5 = {i_in_data[(13+cm*16)*8+:8],i_in_data[(9 +cm*16)*8+:8],
                i_in_data[(5 +cm*16)*8+:8],i_in_data[(1 +cm*16)*8+:8]};
        exp6 = {i_in_data[(14+cm*16)*8+:8],i_in_data[(10+cm*16)*8+:8],
                i_in_data[(6 +cm*16)*8+:8],i_in_data[(2 +cm*16)*8+:8]};
        exp7 = {i_in_data[(15+cm*16)*8+:8],i_in_data[(11+cm*16)*8+:8],
                i_in_data[(7 +cm*16)*8+:8],i_in_data[(3 +cm*16)*8+:8]};
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

    if (out_scramble_en !== 1'b1) begin
        error_count = error_count + 1;
        $display("[ERR] mode=%b cy=%0d out_scramble_en not asserted!", mode, cycle);
    end else correct_count = correct_count + 1;
end
endtask

// =====================================================
// PL_TRDY CHECK WHEN DISABLED
// =====================================================
task test_ready_when_disabled;
begin
    mapper_en       = 0;
    i_width_deg_map = 3'b011;
    lp_irdy         = 1;
    lp_valid        = 1;
    
    repeat(5) begin
        @(posedge i_clk);
        #1;
        if (mapper_ready !== 1'b0) begin
            error_count = error_count + 1;
            $display("[ERR] pl_trdy (mapper_ready) is not low when mapper_en is low!");
        end else begin
            correct_count = correct_count + 1;
        end
    end
end
endtask

// =====================================================
// PL_TRDY CHECK WHEN ENABLED
// =====================================================
task test_ready_when_enabled;
begin
    // Test in x16 mode (1 cycle)
    i_width_deg_map = 3'b011;
    mapper_en       = 1;
    lp_irdy         = 1;
    lp_valid        = 1;

    @(posedge i_clk);
    #1;
    if (mapper_ready !== 1'b1) begin
        error_count = error_count + 1;
        $display("[ERR] pl_trdy (mapper_ready) not asserted at end of x16 mapping!");
    end else begin
        correct_count = correct_count + 1;
        $display("[OK] pl_trdy asserted correctly at the end of x16 mapping.");
    end

    // Test in x8 mode (2 cycles)
    i_width_deg_map = 3'b001;
    // Cycle 0: should be low
    @(posedge i_clk);
    #1;
    if (mapper_ready !== 1'b0) begin
        error_count = error_count + 1;
        $display("[ERR] pl_trdy asserted too early in cycle 0 of x8 mapping!");
    end else begin
        correct_count = correct_count + 1;
    end
    
    // Cycle 1: should be high
    @(posedge i_clk);
    #1;
    if (mapper_ready !== 1'b1) begin
        error_count = error_count + 1;
        $display("[ERR] pl_trdy not asserted in cycle 1 of x8 mapping!");
    end else begin
        correct_count = correct_count + 1;
        $display("[OK] pl_trdy behavior verified for multi-cycle mode.");
    end

    mapper_en = 0;
    @(posedge i_clk);
end
endtask

endmodule
