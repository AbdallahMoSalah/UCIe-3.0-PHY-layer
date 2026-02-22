`timescale 1ns/1ps

module tb_Mapper;

    //============================================================
    // Parameters
    //============================================================
    parameter WIDTH     = 32;
    parameter NUM_LANES = 16;
    parameter N_BYTES   = 64;

    localparam TOTAL_BITS = 8 * N_BYTES;
    localparam CLK_PERIOD = 10;

    //============================================================
    // DUT Signals
    //============================================================
    reg                     clk;
    reg                     rst_n;
    reg                     mapper_en;
    reg  [2:0]              i_width_deg_map;
    reg  [TOTAL_BITS-1:0]   i_in_data;

    wire [WIDTH-1:0] o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3;
    wire [WIDTH-1:0] o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7;
    wire [WIDTH-1:0] o_lane_8,  o_lane_9,  o_lane_10, o_lane_11;
    wire [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15;

    //============================================================
    // Monitoring Signals
    //============================================================
    integer total_tests, passed_tests, failed_tests;
    integer test_num;
    reg [WIDTH-1:0] lane_array [0:NUM_LANES-1];

    //============================================================
    // Instantiate DUT
    //============================================================
    Mapper #(
        .WIDTH(WIDTH),
        .NUM_LANES(NUM_LANES),
        .N_BYTES(N_BYTES)
    ) dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_in_data(i_in_data),
        .mapper_en(mapper_en),
        .i_width_deg_map(i_width_deg_map),

        .o_lane_0(o_lane_0),   .o_lane_1(o_lane_1),
        .o_lane_2(o_lane_2),   .o_lane_3(o_lane_3),
        .o_lane_4(o_lane_4),   .o_lane_5(o_lane_5),
        .o_lane_6(o_lane_6),   .o_lane_7(o_lane_7),
        .o_lane_8(o_lane_8),   .o_lane_9(o_lane_9),
        .o_lane_10(o_lane_10), .o_lane_11(o_lane_11),
        .o_lane_12(o_lane_12), .o_lane_13(o_lane_13),
        .o_lane_14(o_lane_14), .o_lane_15(o_lane_15)
    );

    //============================================================
    // Clock Generation
    //============================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //============================================================
    // Reset and Initialization
    //============================================================
    initial begin
        // Initialize signals
        rst_n = 0;
        mapper_en = 0;
        i_width_deg_map = 0;
        i_in_data = 0;
        
        // Initialize counters
        total_tests = 0;
        passed_tests = 0;
        failed_tests = 0;
        test_num = 0;
        
        // Apply reset
        #(CLK_PERIOD*2);
        rst_n = 1;
        #(CLK_PERIOD);
        
        $display("==========================================================");
        $display("          MAPPER TESTBENCH STARTED                       ");
        $display("==========================================================");
        $display("Time: %0t, Reset de-asserted", $time);
    end

    //============================================================
    // Collect lane outputs into array for easier access
    //============================================================
    always @* begin
        lane_array[0]  = o_lane_0;
        lane_array[1]  = o_lane_1;
        lane_array[2]  = o_lane_2;
        lane_array[3]  = o_lane_3;
        lane_array[4]  = o_lane_4;
        lane_array[5]  = o_lane_5;
        lane_array[6]  = o_lane_6;
        lane_array[7]  = o_lane_7;
        lane_array[8]  = o_lane_8;
        lane_array[9]  = o_lane_9;
        lane_array[10] = o_lane_10;
        lane_array[11] = o_lane_11;
        lane_array[12] = o_lane_12;
        lane_array[13] = o_lane_13;
        lane_array[14] = o_lane_14;
        lane_array[15] = o_lane_15;
    end

    //============================================================
    // Enhanced Golden Model Task
    //============================================================
    task automatic check_lanes;
        input integer active_lanes;
        input integer test_id;
        integer i;
        reg [WIDTH-1:0] expected;
        reg mismatch_found;
        begin
            mismatch_found = 0;
            
            for (i = 0; i < active_lanes; i = i + 1) begin
                expected = i_in_data[i*WIDTH +: WIDTH];
                
                if (lane_array[i] !== expected) begin
                    $error("Time: %0t, Test %0d: Lane%0d mismatch - Expected: 0x%h, Actual: 0x%h", 
                           $time, test_id, i, expected, lane_array[i]);
                    mismatch_found = 1;
                    failed_tests = failed_tests + 1;
                end
            end
            
            // Check that unused lanes are zero
            for (i = active_lanes; i < NUM_LANES; i = i + 1) begin
                if (lane_array[i] !== 0) begin
                    $error("Time: %0t, Test %0d: Lane%0d should be 0 but is 0x%h", 
                           $time, test_id, i, lane_array[i]);
                    mismatch_found = 1;
                    failed_tests = failed_tests + 1;
                end
            end
            
            if (!mismatch_found) begin
                $display("Time: %0t, Test %0d: PASSED - %0d lanes verified", 
                        $time, test_id, active_lanes);
                passed_tests = passed_tests + 1;
            end
            
            total_tests = total_tests + 1;
        end
    endtask

    //============================================================
    // Generate random input data
    //============================================================
    task automatic generate_random_data;
        integer i;
        begin
            for (i = 0; i < TOTAL_BITS/32; i = i + 1) begin
                i_in_data[i*32 +: 32] = $urandom();
            end
        end
    endtask

    //============================================================
    // Generate patterned input data
    //============================================================
    task automatic generate_pattern_data;
        input integer pattern_type;
        integer i;
        begin
            for (i = 0; i < TOTAL_BITS/WIDTH; i = i + 1) begin
                case (pattern_type)
                    0: i_in_data[i*WIDTH +: WIDTH] = i;                    // Sequential
                    1: i_in_data[i*WIDTH +: WIDTH] = 32'hDEADBEEF + i;    // Pattern with offset
                    2: i_in_data[i*WIDTH +: WIDTH] = {8'hA5, 8'h5A, 8'hA5, 8'h5A}; // Alternating
                    default: i_in_data[i*WIDTH +: WIDTH] = $urandom();
                endcase
            end
        end
    endtask

    //============================================================
    // Main Test Sequence
    //============================================================
    initial begin
        // Wait for reset to complete
        @(posedge rst_n);
        @(posedge clk);
        
        //========================================================
        // Test 1: Reset State (mapper_en = 0)
        //========================================================
        test_num = test_num + 1;
        $display("\n--- Test %0d: Reset State Check ---", test_num);
        generate_random_data();
        i_width_deg_map = 3'b011;
        mapper_en = 0;
        @(posedge clk);
        #1;
        check_lanes(0, test_num);  // Should have no outputs when disabled

        //========================================================
        // Test 2: 16 Lanes (All lanes active)
        //========================================================
        test_num = test_num + 1;
        $display("\n--- Test %0d: 16 Lanes Mode ---", test_num);
        generate_pattern_data(0);  // Sequential pattern
        i_width_deg_map = 3'b011;  // 16 lanes (assuming this encoding)
        mapper_en = 1;
        @(posedge clk);
        #1;
        check_lanes(16, test_num);
        mapper_en = 0;

        //========================================================
        // Test 3: 8 Lanes (0→7)
        //========================================================
        test_num = test_num + 1;
        $display("\n--- Test %0d: 8 Lanes Mode ---", test_num);
        generate_pattern_data(1);  // Pattern with offset
        i_width_deg_map = 3'b010;  // 8 lanes (adjust encoding as needed)
        mapper_en = 1;
        @(posedge clk);
        #1;
        check_lanes(8, test_num);
        mapper_en = 0;

        //========================================================
        // Test 4: 4 Lanes (0→3)
        //========================================================
        test_num = test_num + 1;
        $display("\n--- Test %0d: 4 Lanes Mode ---", test_num);
        generate_pattern_data(2);  // Alternating pattern
        i_width_deg_map = 3'b001;  // 4 lanes (adjust encoding as needed)
        mapper_en = 1;
        @(posedge clk);
        #1;
        check_lanes(4, test_num);
        mapper_en = 0;

        //========================================================
        // Test 5: 2 Lanes
        //========================================================
        test_num = test_num + 1;
        $display("\n--- Test %0d: 2 Lanes Mode ---", test_num);
        generate_random_data();
        i_width_deg_map = 3'b100;  // 2 lanes (adjust encoding as needed)
        mapper_en = 1;
        @(posedge clk);
        #1;
        check_lanes(2, test_num);
        mapper_en = 0;

        //========================================================
        // Test 6: 1 Lane
        //========================================================
        test_num = test_num + 1;
        $display("\n--- Test %0d: 1 Lane Mode ---", test_num);
        generate_random_data();
        i_width_deg_map = 3'b101;  // 1 lane (adjust encoding as needed)
        mapper_en = 1;
        @(posedge clk);
        #1;
        check_lanes(1, test_num);
        mapper_en = 0;

        //========================================================
        // Test 7: Consecutive Operations
        //========================================================
        test_num = test_num + 1;
        $display("\n--- Test %0d: Consecutive Operations ---", test_num);
        
        // First operation - 16 lanes
        generate_random_data();
        i_width_deg_map = 3'b011;
        mapper_en = 1;
        @(posedge clk);
        #1;
        check_lanes(16, test_num);
        
        // Second operation immediately - 8 lanes
        generate_random_data();
        i_width_deg_map = 3'b010;
        @(posedge clk);
        #1;
        check_lanes(8, test_num);
        
        // Third operation - 4 lanes
        generate_random_data();
        i_width_deg_map = 3'b001;
        @(posedge clk);
        #1;
        check_lanes(4, test_num);
        
        mapper_en = 0;

        //========================================================
        // Random Tests
        //========================================================
        $display("\n--- Random Tests ---");
        repeat (20) begin
            test_num = test_num + 1;
            generate_random_data();
            
            // Random lane configuration (adjust ranges based on your encoding)
            i_width_deg_map = $urandom_range(1, 5);
            
            // Determine number of active lanes based on encoding
            case (i_width_deg_map)
                3'b001: check_lanes(4, test_num);   // 4 lanes
                3'b010: check_lanes(8, test_num);   // 8 lanes
                3'b011: check_lanes(16, test_num);  // 16 lanes
                3'b100: check_lanes(2, test_num);   // 2 lanes
                3'b101: check_lanes(1, test_num);   // 1 lane
                default: check_lanes(0, test_num);  // Invalid, expect 0
            endcase
            
            mapper_en = 1;
            @(posedge clk);
            #1;
            mapper_en = 0;
            #(CLK_PERIOD);
        end

        //========================================================
        // Boundary Tests
        //========================================================
        test_num = test_num + 1;
        $display("\n--- Test %0d: Boundary Values ---", test_num);
        
        // All zeros
        i_in_data = 0;
        i_width_deg_map = 3'b011;
        mapper_en = 1;
        @(posedge clk);
        #1;
        check_lanes(16, test_num);
        
        // All ones
        i_in_data = {TOTAL_BITS{1'b1}};
        @(posedge clk);
        #1;
        check_lanes(16, test_num);
        
        mapper_en = 0;

        //========================================================
        // Test Summary
        //========================================================
        #(CLK_PERIOD*2);
        $display("\n==========================================================");
        $display("                 TEST SUMMARY                              ");
        $display("==========================================================");
        $display("Total Tests  : %0d", total_tests);
        $display("Passed Tests : %0d", passed_tests);
        $display("Failed Tests : %0d", failed_tests);
        $display("==========================================================");
        
        if (failed_tests == 0) begin
            $display("              ALL TESTS PASSED!                           ");
        end else begin
            $display("              SOME TESTS FAILED!                          ");
        end
        $display("==========================================================");
        
        $finish;
    end

    //============================================================
    // Waveform Dumping
    //============================================================
    initial begin
        $dumpfile("tb_Mapper.vcd");
        $dumpvars(0, tb_Mapper);
    end

    //============================================================
    // Timeout Monitor
    //============================================================
    initial begin
        #100000;  // 100us timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    //============================================================
    // Monitor important events
    //============================================================
    always @(posedge clk) begin
        if (mapper_en) begin
            $display("Time: %0t, Mapping enabled with width_deg: %b, Data: 0x%h", 
                    $time, i_width_deg_map, i_in_data);
        end
    end

endmodule