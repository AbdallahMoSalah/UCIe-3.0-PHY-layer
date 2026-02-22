`timescale 1ns/1ps

module tb_mapper();

    //============================================================
    // Parameters
    //============================================================
    parameter WIDTH      = 32;
    parameter NUM_LANES  = 16;
    parameter N_BYTES    = 64;
    
    // Calculate derived parameters
    localparam N_BYTE_PER_LANE = WIDTH / 8;
    localparam NUM_WORDS       = N_BYTES / N_BYTE_PER_LANE;
    localparam CLOCK_CYCLES_16 = NUM_WORDS / 16;
    localparam CLOCK_CYCLES_8  = NUM_WORDS / 8;
    localparam CLOCK_CYCLES_4  = NUM_WORDS / 4;
    
    //============================================================
    // Testbench Signals
    //============================================================
    reg                         i_clk;
    reg                         i_rst_n;
    reg  [8*N_BYTES-1:0]        i_in_data;
    reg                         mapper_en;
    reg  [2:0]                  i_width_deg_map;
    
    wire [WIDTH-1:0] o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3;
    wire [WIDTH-1:0] o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7;
    wire [WIDTH-1:0] o_lane_8,  o_lane_9,  o_lane_10, o_lane_11;
    wire [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15;
    
    //============================================================
    // Degrade Modes (from DUT)
    //============================================================
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;
    
    //============================================================
    // Clock Generation
    //============================================================
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk; // 100MHz clock
    end
    
    //============================================================
    // DUT Instantiation
    //============================================================
    Mapper #(
        .WIDTH     (WIDTH),
        .NUM_LANES (NUM_LANES),
        .N_BYTES   (N_BYTES)
    ) dut (
        .i_clk            (i_clk),
        .i_rst_n          (i_rst_n),
        .i_in_data        (i_in_data),
        .mapper_en        (mapper_en),
        .i_width_deg_map  (i_width_deg_map),
        .o_lane_0         (o_lane_0),
        .o_lane_1         (o_lane_1),
        .o_lane_2         (o_lane_2),
        .o_lane_3         (o_lane_3),
        .o_lane_4         (o_lane_4),
        .o_lane_5         (o_lane_5),
        .o_lane_6         (o_lane_6),
        .o_lane_7         (o_lane_7),
        .o_lane_8         (o_lane_8),
        .o_lane_9         (o_lane_9),
        .o_lane_10        (o_lane_10),
        .o_lane_11        (o_lane_11),
        .o_lane_12        (o_lane_12),
        .o_lane_13        (o_lane_13),
        .o_lane_14        (o_lane_14),
        .o_lane_15        (o_lane_15)
    );
    
    //============================================================
    // Test Procedure
    //============================================================
    integer i, j, test_num;
    reg [WIDTH-1:0] expected_data [0:NUM_LANES-1];
    reg [8*N_BYTES-1:0] test_pattern;
    
    initial begin
        // Initialize signals
        i_rst_n = 0;
        mapper_en = 0;
        i_width_deg_map = 3'b000;
        i_in_data = 0;
        test_num = 0;
        
        // Apply reset
        #20;
        i_rst_n = 1;
        #10;
        
        //========================================================
        // Test 1: All lanes active (DEGRADE_LANES_0_TO_15)
        //========================================================
        test_num = test_num + 1;
        $display("========================================");
        $display("Test %0d: All 16 lanes active", test_num);
        $display("========================================");
        
        // Generate test pattern with unique values per word
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            for (j = 0; j < N_BYTE_PER_LANE; j = j + 1) begin
                test_pattern[(i*N_BYTE_PER_LANE + j)*8 +: 8] = i*16 + j;
            end
        end
        i_in_data = test_pattern;
        
        // Enable mapper
        mapper_en = 1;
        i_width_deg_map = DEGRADE_LANES_0_TO_15;
        
        // Wait for processing
        #20;
        
        // Check first cycle outputs
        check_lanes(0, CLOCK_CYCLES_16, 16, 0);
        
        // Wait for completion
        #(CLOCK_CYCLES_16 * 10);
        
        //========================================================
        // Test 2: Lanes 0-7 active
        //========================================================
        test_num = test_num + 1;
        $display("========================================");
        $display("Test %0d: Lanes 0-7 active", test_num);
        $display("========================================");
        
        // Generate new test pattern
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            for (j = 0; j < N_BYTE_PER_LANE; j = j + 1) begin
                test_pattern[(i*N_BYTE_PER_LANE + j)*8 +: 8] = i*16 + j + 100;
            end
        end
        i_in_data = test_pattern;
        
        i_width_deg_map = DEGRADE_LANES_0_TO_7;
        #10;
        
        // Check outputs
        check_lanes(0, CLOCK_CYCLES_8, 8, 0);
        
        #(CLOCK_CYCLES_8 * 10);
        
        //========================================================
        // Test 3: Lanes 8-15 active
        //========================================================
        test_num = test_num + 1;
        $display("========================================");
        $display("Test %0d: Lanes 8-15 active", test_num);
        $display("========================================");
        
        // Generate new test pattern
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            for (j = 0; j < N_BYTE_PER_LANE; j = j + 1) begin
                test_pattern[(i*N_BYTE_PER_LANE + j)*8 +: 8] = i*16 + j + 200;
            end
        end
        i_in_data = test_pattern;
        
        i_width_deg_map = DEGRADE_LANES_8_TO_15;
        #10;
        
        // Check outputs
        check_lanes(8, CLOCK_CYCLES_8, 8, 0);
        
        #(CLOCK_CYCLES_8 * 10);
        
        //========================================================
        // Test 4: Lanes 0-3 active
        //========================================================
        test_num = test_num + 1;
        $display("========================================");
        $display("Test %0d: Lanes 0-3 active", test_num);
        $display("========================================");
        
        // Generate new test pattern
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            for (j = 0; j < N_BYTE_PER_LANE; j = j + 1) begin
                test_pattern[(i*N_BYTE_PER_LANE + j)*8 +: 8] = i*16 + j + 300;
            end
        end
        i_in_data = test_pattern;
        
        i_width_deg_map = DEGRADE_LANES_0_TO_3;
        #10;
        
        // Check outputs
        check_lanes(0, CLOCK_CYCLES_4, 4, 0);
        
        #(CLOCK_CYCLES_4 * 10);
        
        //========================================================
        // Test 5: Lanes 4-7 active
        //========================================================
        test_num = test_num + 1;
        $display("========================================");
        $display("Test %0d: Lanes 4-7 active", test_num);
        $display("========================================");
        
        // Generate new test pattern
        for (i = 0; i < NUM_WORDS; i = i + 1) begin
            for (j = 0; j < N_BYTE_PER_LANE; j = j + 1) begin
                test_pattern[(i*N_BYTE_PER_LANE + j)*8 +: 8] = i*16 + j + 400;
            end
        end
        i_in_data = test_pattern;
        
        i_width_deg_map = DEGRADE_LANES_4_TO_7;
        #10;
        
        // Check outputs
        check_lanes(4, CLOCK_CYCLES_4, 4, 0);
        
        #(CLOCK_CYCLES_4 * 10);
        
        //========================================================
        // Test 6: Disable mapper
        //========================================================
        test_num = test_num + 1;
        $display("========================================");
        $display("Test %0d: Disable mapper", test_num);
        $display("========================================");
        
        mapper_en = 0;
        #20;
        
        // Check all lanes are zero
        check_all_lanes_zero();
        
        //========================================================
        // Test 7: Reset during operation
        //========================================================
        test_num = test_num + 1;
        $display("========================================");
        $display("Test %0d: Reset during operation", test_num);
        $display("========================================");
        
        mapper_en = 1;
        i_width_deg_map = DEGRADE_LANES_0_TO_15;
        #15;
        
        i_rst_n = 0;
        #10;
        i_rst_n = 1;
        #20;
        
        // Check all lanes are zero after reset
        check_all_lanes_zero();
        
        //========================================================
        // End of tests
        //========================================================
        $display("========================================");
        $display("All tests completed!");
        $display("========================================");
        #100;
        $finish;
    end
    
    //============================================================
    // Task: Check lane outputs
    //============================================================
    task check_lanes;
        input integer start_lane;
        input integer num_cycles;
        input integer num_active_lanes;
        input integer expected_offset;
        
        integer lane, cycle, errors;
        reg [WIDTH-1:0] expected;
        begin
            errors = 0;
            
            // Sample outputs for each cycle
            for (cycle = 0; cycle < num_cycles; cycle = cycle + 1) begin
                @(posedge i_clk);
                #1; // Small delay for outputs to settle
                
                $display("Cycle %0d:", cycle);
                
                for (lane = 0; lane < num_active_lanes; lane = lane + 1) begin
                    // Calculate expected value based on test pattern
                    expected = {WIDTH{1'b0}};
                    for (j = 0; j < N_BYTE_PER_LANE; j = j + 1) begin
                        expected[j*8 +: 8] = (cycle*num_active_lanes + lane)*N_BYTE_PER_LANE + j + expected_offset;
                    end
                    
                    case (start_lane + lane)
                        0:  compare_lane_output(o_lane_0,  expected, 0,  cycle, errors);
                        1:  compare_lane_output(o_lane_1,  expected, 1,  cycle, errors);
                        2:  compare_lane_output(o_lane_2,  expected, 2,  cycle, errors);
                        3:  compare_lane_output(o_lane_3,  expected, 3,  cycle, errors);
                        4:  compare_lane_output(o_lane_4,  expected, 4,  cycle, errors);
                        5:  compare_lane_output(o_lane_5,  expected, 5,  cycle, errors);
                        6:  compare_lane_output(o_lane_6,  expected, 6,  cycle, errors);
                        7:  compare_lane_output(o_lane_7,  expected, 7,  cycle, errors);
                        8:  compare_lane_output(o_lane_8,  expected, 8,  cycle, errors);
                        9:  compare_lane_output(o_lane_9,  expected, 9,  cycle, errors);
                        10: compare_lane_output(o_lane_10, expected, 10, cycle, errors);
                        11: compare_lane_output(o_lane_11, expected, 11, cycle, errors);
                        12: compare_lane_output(o_lane_12, expected, 12, cycle, errors);
                        13: compare_lane_output(o_lane_13, expected, 13, cycle, errors);
                        14: compare_lane_output(o_lane_14, expected, 14, cycle, errors);
                        15: compare_lane_output(o_lane_15, expected, 15, cycle, errors);
                    endcase
                end
            end
            
            if (errors == 0)
                $display("PASS: All lane outputs matched expected values");
            else
                $display("FAIL: Found %0d errors", errors);
        end
    endtask
    
    //============================================================
    // Task: Compare single lane output
    //============================================================
    task compare_lane_output;
        input [WIDTH-1:0] actual;
        input [WIDTH-1:0] expected;
        input integer lane_num;
        input integer cycle_num;
        inout integer errors;
        begin
            if (actual !== expected) begin
                $display("  ERROR: Lane %0d (Cycle %0d) - Expected: %h, Actual: %h", 
                         lane_num, cycle_num, expected, actual);
                errors = errors + 1;
            end else begin
                $display("  Lane %0d: %h (OK)", lane_num, actual);
            end
        end
    endtask
    
    //============================================================
    // Task: Check all lanes are zero
    //============================================================
    task check_all_lanes_zero;
        integer errors;
        begin
            errors = 0;
            #1;
            
            if (o_lane_0  !== 0) errors = errors + 1;
            if (o_lane_1  !== 0) errors = errors + 1;
            if (o_lane_2  !== 0) errors = errors + 1;
            if (o_lane_3  !== 0) errors = errors + 1;
            if (o_lane_4  !== 0) errors = errors + 1;
            if (o_lane_5  !== 0) errors = errors + 1;
            if (o_lane_6  !== 0) errors = errors + 1;
            if (o_lane_7  !== 0) errors = errors + 1;
            if (o_lane_8  !== 0) errors = errors + 1;
            if (o_lane_9  !== 0) errors = errors + 1;
            if (o_lane_10 !== 0) errors = errors + 1;
            if (o_lane_11 !== 0) errors = errors + 1;
            if (o_lane_12 !== 0) errors = errors + 1;
            if (o_lane_13 !== 0) errors = errors + 1;
            if (o_lane_14 !== 0) errors = errors + 1;
            if (o_lane_15 !== 0) errors = errors + 1;
            
            if (errors == 0)
                $display("PASS: All lanes are zero");
            else
                $display("FAIL: %0d lanes are non-zero", errors);
        end
    endtask
    
    //============================================================
    // Monitor waveforms
    //============================================================
    initial begin
        $dumpfile("tb_mapper.vcd");
        $dumpvars(0, tb_mapper);
    end

endmodule