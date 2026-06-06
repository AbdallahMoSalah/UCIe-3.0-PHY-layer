`timescale 1ns/1ps

module Mapper_tb;

parameter WIDTH = 32;

// =====================================================
// Signal Declarations
// =====================================================
reg                 i_clk;
reg                 i_rst_n;
reg                 mapper_en;
reg  [2:0]          i_width_deg_map;
reg  [511:0]        i_in_data;
reg                 lp_irdy;
reg                 lp_valid;

wire [WIDTH-1:0]    o_lane [0:15];
wire                out_scramble_en;
wire                mapper_ready;

integer correct_count;
integer error_count;
integer i;
reg checker_en;

// =====================================================
// DUT Instantiation
// =====================================================
Mapper DUT (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .mapper_en(mapper_en),
    .i_width_deg_map(i_width_deg_map),
    .i_in_data(i_in_data),
    .lp_irdy(lp_irdy),
    .lp_valid(lp_valid),

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
    .o_lane_15(o_lane[15]),
    
    .out_scramble_en(out_scramble_en),
    .mapper_ready(mapper_ready)
);

// =====================================================
// CLOCK GENERATION
// =====================================================
always #5 i_clk = ~i_clk;

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
// RUN MODE TEST TASK
// =====================================================
task run_mode_test;
    input [2:0] mode;
    input bit active_handshake;
    input integer num_runs;
    integer cycles_per_run;
    integer r, c;
    begin
        case (mode)
            3'b011:  cycles_per_run = 1;
            3'b001,
            3'b010:  cycles_per_run = 2;
            3'b100,
            3'b101:  cycles_per_run = 4;
            default: cycles_per_run = 1;
        endcase

        i_width_deg_map = mode;
        mapper_en = 1;
        
        for (r = 0; r < num_runs; r = r + 1) begin
            // Change in_data per run to test different patterns
            for (i = 0; i < 64; i = i + 1) begin
                i_in_data[i*8 +: 8] = i + r;
            end

            // Drive handshakes
            lp_valid = active_handshake;
            lp_irdy = active_handshake;

            for (c = 0; c < cycles_per_run; c = c + 1) begin
                @(posedge i_clk);
            end
        end

        // Return to IDLE
        lp_valid = 0;
        lp_irdy = 0;
        mapper_en = 0;
        @(posedge i_clk);
    end
endtask

// =====================================================
// STALL TEST TASK
// =====================================================
task run_stall_test;
    begin
        i_width_deg_map = 3'b100; // x4
        mapper_en = 1;
        
        // Cycle 0: Active (maps cycle 0)
        lp_valid = 1;
        lp_irdy = 1;
        @(posedge i_clk);

        // Cycle 1: Stall (valid = 0, holds cycle_count at 1)
        lp_valid = 0;
        lp_irdy = 1;
        @(posedge i_clk);

        // Cycle 2: Stall (irdy = 0, holds cycle_count at 1)
        lp_valid = 1;
        lp_irdy = 0;
        @(posedge i_clk);

        // Cycle 3: Active (maps cycle 1, cycle_count becomes 2)
        lp_valid = 1;
        lp_irdy = 1;
        @(posedge i_clk);

        // Cycle 4: Active (maps cycle 2, cycle_count becomes 3)
        lp_valid = 1;
        lp_irdy = 1;
        @(posedge i_clk);

        // Cycle 5: Active (maps cycle 3, cycle_count wraps to 0)
        lp_valid = 1;
        lp_irdy = 1;
        @(posedge i_clk);

        // Return to IDLE
        lp_valid = 0;
        lp_irdy = 0;
        mapper_en = 0;
        @(posedge i_clk);
    end
endtask

// =====================================================
// RESET TEST TASK
// =====================================================
task run_reset_test;
    begin
        i_width_deg_map = 3'b001; // x8
        mapper_en = 1;
        lp_valid = 1;
        lp_irdy = 1;
        
        // Start transaction
        @(posedge i_clk);
        
        // Mid-transaction reset
        #1;
        i_rst_n = 0;
        checker_en = 0; // stop checking during reset
        
        repeat (2) @(posedge i_clk);
        
        // Verify outputs are cleared
        #1;
        if (o_lane[0] !== 0 || out_scramble_en !== 0 || mapper_ready !== 1) begin
            error_count = error_count + 1;
            $display("[ERROR] Reset failed: outputs or control signals not cleared.");
        end else begin
            correct_count = correct_count + 3;
        end
        
        // Release reset
        i_rst_n = 1;
        lp_valid = 0;
        lp_irdy = 0;
        mapper_en = 0;
        @(posedge i_clk);
        
        // Re-enable checker and run normal test to verify recovery
        checker_en = 1;
        $display("[TEST] Verifying recovery after reset...");
        run_mode_test(3'b001, 1, 2);
    end
endtask

// =====================================================
// MAIN TEST SEQUENCE
// =====================================================
initial begin
    i_clk = 0;
    i_rst_n = 0;
    mapper_en = 0;
    i_width_deg_map = 0;
    i_in_data = 0;
    lp_irdy = 0;
    lp_valid = 0;
    correct_count = 0;
    error_count = 0;
    checker_en = 0;

    // Release Reset
    #20;
    i_rst_n = 1;
    #10;
    
    // Generate initial pattern
    generate_pattern();

    // Enable checker on the next clock edge
    @(posedge i_clk);
    #1;
    checker_en = 1;

    // Scenario 1: NONE_DEGRADE / IDLE (3'b000)
    $display("[TEST] Starting Mode: NONE_DEGRADE (3'b000)...");
    run_mode_test(3'b000, 1, 5);

    // Scenario 2: x16 Mode (3'b011)
    $display("[TEST] Starting Mode: x16 (3'b011)...");
    run_mode_test(3'b011, 1, 5);

    // Scenario 3: x8 Lanes 0-7 (3'b001)
    $display("[TEST] Starting Mode: x8 Lanes 0-7 (3'b001)...");
    run_mode_test(3'b001, 1, 3);

    // Scenario 4: x8 Lanes 8-15 (3'b010)
    $display("[TEST] Starting Mode: x8 Lanes 8-15 (3'b010)...");
    run_mode_test(3'b010, 1, 3);

    // Scenario 5: x4 Lanes 0-3 (3'b100)
    $display("[TEST] Starting Mode: x4 Lanes 0-3 (3'b100)...");
    run_mode_test(3'b100, 1, 3);

    // Scenario 6: x4 Lanes 4-7 (3'b101)
    $display("[TEST] Starting Mode: x4 Lanes 4-7 (3'b101)...");
    run_mode_test(3'b101, 1, 3);

    // Scenario 7: Handshake Stall Test
    $display("[TEST] Starting Handshake Stall Test in x4 Mode...");
    run_stall_test();

    // Scenario 8: Mid-transaction Reset Test
    $display("[TEST] Starting Reset Test in x8 Mode...");
    run_reset_test();

    // End Simulation
    #50;
    checker_en = 0;
    
    $display("=================================");
    $display("Test Done!");
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
// SELF-CHECKING REFERENCE MODEL
// =====================================================
reg [2:0]   prev_mode;
reg [511:0] prev_in_data;
reg         prev_data_active;
reg [1:0]   prev_cycle_count;
reg         prev_mapper_en;

// Sample inputs to model one-cycle delay (since DUT registers outputs)
always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        prev_mode        <= 0;
        prev_in_data     <= 0;
        prev_data_active <= 0;
        prev_cycle_count <= 0;
        prev_mapper_en   <= 0;
    end else begin
        prev_mode        <= i_width_deg_map;
        prev_in_data     <= i_in_data;
        prev_data_active <= lp_irdy && lp_valid;
        prev_cycle_count <= DUT.cycle_count;
        prev_mapper_en   <= mapper_en;
    end
end

// Checker logic
always @(posedge i_clk) begin
    if (checker_en && i_rst_n) begin
        #1; // Wait for DUT outputs to settle
        check_outputs();
    end
end

task check_outputs;
    reg [WIDTH-1:0] expected [0:15];
    reg expected_scramble_en;
    reg expected_ready;
    integer j;
    reg prev_mode_active;
    reg [2:0] prev_cycles_needed;
    begin
        // Initialize expected values
        for (j = 0; j < 16; j = j + 1) begin
            expected[j] = 0;
        end
        expected_scramble_en = 0;
        expected_ready = 0;

        prev_mode_active = (prev_mode == 3'b011) ||
                           (prev_mode == 3'b001) ||
                           (prev_mode == 3'b010) ||
                           (prev_mode == 3'b100) ||
                           (prev_mode == 3'b101);

        case (prev_mode)
            3'b011:  prev_cycles_needed = 3'd1;
            3'b001,
            3'b010:  prev_cycles_needed = 3'd2;
            3'b100,
            3'b101:  prev_cycles_needed = 3'd4;
            default: prev_cycles_needed = 3'd1;
        endcase

        if (!prev_mapper_en || !prev_mode_active) begin
            expected_ready = 1;
        end else begin
            if (!prev_data_active) begin
                if (prev_cycle_count == 0 || prev_cycle_count == prev_cycles_needed - 1) begin
                    expected_ready = 1;
                end else begin
                    expected_ready = 0;
                end
            end else begin
                if (prev_cycle_count == prev_cycles_needed - 1) begin
                    expected_ready = 1;
                end else begin
                    expected_ready = 0;
                end
            end
        end

        if (prev_mapper_en && prev_data_active && prev_mode_active) begin
                expected_scramble_en = 1;
                case (prev_mode)
                    3'b011: begin // DEGRADE_LANES_0_TO_15 (x16)
                        for (j = 0; j < 16; j = j + 1) begin
                            expected[j] = {
                                prev_in_data[(j+48)*8 +: 8],
                                prev_in_data[(j+32)*8 +: 8],
                                prev_in_data[(j+16)*8 +: 8],
                                prev_in_data[j*8 +: 8]
                            };
                        end
                    end

                    3'b001: begin // DEGRADE_LANES_0_TO_7 (x8)
                        for (j = 0; j < 8; j = j + 1) begin
                            expected[j] = {
                                prev_in_data[(j + 24 + prev_cycle_count*32)*8 +: 8],
                                prev_in_data[(j + 16 + prev_cycle_count*32)*8 +: 8],
                                prev_in_data[(j + 8 + prev_cycle_count*32)*8 +: 8],
                                prev_in_data[(j + prev_cycle_count*32)*8 +: 8]
                            };
                        end
                    end

                    3'b010: begin // DEGRADE_LANES_8_TO_15 (x8)
                        for (j = 8; j < 16; j = j + 1) begin
                            expected[j] = {
                                prev_in_data[(j-8 + 24 + prev_cycle_count*32)*8 +: 8],
                                prev_in_data[(j-8 + 16 + prev_cycle_count*32)*8 +: 8],
                                prev_in_data[(j-8 + 8 + prev_cycle_count*32)*8 +: 8],
                                prev_in_data[(j-8 + prev_cycle_count*32)*8 +: 8]
                            };
                        end
                    end

                    3'b100: begin // DEGRADE_LANES_0_TO_3 (x4)
                        for (j = 0; j < 4; j = j + 1) begin
                            expected[j] = {
                                prev_in_data[(j + 12 + prev_cycle_count*16)*8 +: 8],
                                prev_in_data[(j + 8 + prev_cycle_count*16)*8 +: 8],
                                prev_in_data[(j + 4 + prev_cycle_count*16)*8 +: 8],
                                prev_in_data[(j + prev_cycle_count*16)*8 +: 8]
                            };
                        end
                    end

                    3'b101: begin // DEGRADE_LANES_4_TO_7 (x4)
                        for (j = 4; j < 8; j = j + 1) begin
                            expected[j] = {
                                prev_in_data[(j-4 + 12 + prev_cycle_count*16)*8 +: 8],
                                prev_in_data[(j-4 + 8 + prev_cycle_count*16)*8 +: 8],
                                prev_in_data[(j-4 + 4 + prev_cycle_count*16)*8 +: 8],
                                prev_in_data[(j-4 + prev_cycle_count*16)*8 +: 8]
                            };
                        end
                    end
                    
                    default: begin
                        // IDLE / unsupported mode
                    end
                endcase
            end
        end

        // Compare all outputs
        for (j = 0; j < 16; j = j + 1) begin
            if (o_lane[j] === expected[j]) begin
                correct_count = correct_count + 1;
            end else begin
                error_count = error_count + 1;
                $display("[ERROR] Lane %0d mismatch at time %0t: Expected = %h, Got = %h (Mode = %b, Cycle = %0d)",
                         j, $time, expected[j], o_lane[j], prev_mode, prev_cycle_count);
            end
        end

        if (out_scramble_en === expected_scramble_en) begin
            correct_count = correct_count + 1;
        end else begin
            error_count = error_count + 1;
            $display("[ERROR] out_scramble_en mismatch at time %0t: Expected = %b, Got = %b",
                     $time, expected_scramble_en, out_scramble_en);
        end

        if (mapper_ready === expected_ready) begin
            correct_count = correct_count + 1;
        end else begin
            error_count = error_count + 1;
            $display("[ERROR] mapper_ready mismatch at time %0t: Expected = %b, Got = %b (Mode = %b, Cycle = %0d)",
                     $time, expected_ready, mapper_ready, prev_mode, prev_cycle_count);
        end
    
endtask

endmodule