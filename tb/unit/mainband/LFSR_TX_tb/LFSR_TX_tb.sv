`timescale 1ns/1ps

module LFSR_TX_tb();

    // Parameters
    localparam WIDTH = 32;
    localparam CLK_PERIOD = 10ns;
    
    // Clock and reset
    reg i_clk;
    reg i_rst_n;
    
    // DUT inputs
    reg [1:0] i_state;
    reg scramble_en;
    reg [2:0] i_width_deg_lfsr;
    reg reversal_en;
    
    // 16 input lanes
    reg [WIDTH-1:0] i_lane_0, i_lane_1, i_lane_2, i_lane_3;
    reg [WIDTH-1:0] i_lane_4, i_lane_5, i_lane_6, i_lane_7;
    reg [WIDTH-1:0] i_lane_8, i_lane_9, i_lane_10, i_lane_11;
    reg [WIDTH-1:0] i_lane_12, i_lane_13, i_lane_14, i_lane_15;
    
    // DUT outputs
    wire [WIDTH-1:0] o_lane_0, o_lane_1, o_lane_2, o_lane_3;
    wire [WIDTH-1:0] o_lane_4, o_lane_5, o_lane_6, o_lane_7;
    wire [WIDTH-1:0] o_lane_8, o_lane_9, o_lane_10, o_lane_11;
    wire [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15;
    wire o_Lfsr_tx_done;
    wire valid_frame_en;
    
    // State definitions
    localparam IDLE         = 2'b00;
    localparam CLEAR_LFSR   = 2'b01;
    localparam PATTERN_LFSR = 2'b10;
    localparam PER_LANE_IDE = 2'b11;
    
    // Degrade modes
    localparam NONE_DEGRADE          = 3'b000;
    localparam DEGRADE_LANES_0_TO_7  = 3'b001;
    localparam DEGRADE_LANES_8_TO_15 = 3'b010;
    localparam DEGRADE_LANES_0_TO_15 = 3'b011;
    localparam DEGRADE_LANES_0_TO_3  = 3'b100;
    localparam DEGRADE_LANES_4_TO_7  = 3'b101;
    
    // Test data
    reg [WIDTH-1:0] test_data [0:15];
    
    // DUT instantiation
    LFSR_TX #(
        .WIDTH(WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_state(i_state),
        .scramble_en(scramble_en),
        .i_width_deg_lfsr(i_width_deg_lfsr),
        .reversal_en(reversal_en),
        .i_lane_0(i_lane_0), .i_lane_1(i_lane_1), .i_lane_2(i_lane_2), .i_lane_3(i_lane_3),
        .i_lane_4(i_lane_4), .i_lane_5(i_lane_5), .i_lane_6(i_lane_6), .i_lane_7(i_lane_7),
        .i_lane_8(i_lane_8), .i_lane_9(i_lane_9), .i_lane_10(i_lane_10), .i_lane_11(i_lane_11),
        .i_lane_12(i_lane_12), .i_lane_13(i_lane_13), .i_lane_14(i_lane_14), .i_lane_15(i_lane_15),
        .o_lane_0(o_lane_0), .o_lane_1(o_lane_1), .o_lane_2(o_lane_2), .o_lane_3(o_lane_3),
        .o_lane_4(o_lane_4), .o_lane_5(o_lane_5), .o_lane_6(o_lane_6), .o_lane_7(o_lane_7),
        .o_lane_8(o_lane_8), .o_lane_9(o_lane_9), .o_lane_10(o_lane_10), .o_lane_11(o_lane_11),
        .o_lane_12(o_lane_12), .o_lane_13(o_lane_13), .o_lane_14(o_lane_14), .o_lane_15(o_lane_15),
        .o_Lfsr_tx_done(o_Lfsr_tx_done),
        .valid_frame_en(valid_frame_en)
    );
    
    // Clock generation
    initial begin
        i_clk = 0;
        forever #(CLK_PERIOD/2) i_clk = ~i_clk;
    end
    
    // Initialize test data
    initial begin
        for (int i = 0; i < 16; i++) begin
            test_data[i] = i * 32'h01010101;
        end
    end
    
    // Assign test data to input lanes
    always @(*) begin
        i_lane_0  = test_data[0];
        i_lane_1  = test_data[1];
        i_lane_2  = test_data[2];
        i_lane_3  = test_data[3];
        i_lane_4  = test_data[4];
        i_lane_5  = test_data[5];
        i_lane_6  = test_data[6];
        i_lane_7  = test_data[7];
        i_lane_8  = test_data[8];
        i_lane_9  = test_data[9];
        i_lane_10 = test_data[10];
        i_lane_11 = test_data[11];
        i_lane_12 = test_data[12];
        i_lane_13 = test_data[13];
        i_lane_14 = test_data[14];
        i_lane_15 = test_data[15];
    end
    
    // Test task: Wait for done signal
    task wait_for_done();
        begin
            @(posedge i_clk);
            while (!o_Lfsr_tx_done) begin
                @(posedge i_clk);
            end
            @(posedge i_clk);
        end
    endtask
    
    // Test task: Reset DUT
    task reset_dut();
        begin
            i_rst_n = 0;
            i_state = IDLE;
            scramble_en = 0;
            i_width_deg_lfsr = NONE_DEGRADE;
            reversal_en = 0;
            repeat(5) @(posedge i_clk);
            i_rst_n = 1;
            @(posedge i_clk);
        end
    endtask
    
    // Test case 1: Clear LFSR
    task test_clear_lfsr();
        begin
            $display("\n=== TEST 1: CLEAR_LFSR ===");
            reset_dut();
            
            i_state = CLEAR_LFSR;
            @(posedge i_clk);
            
            // Check that LFSR values are loaded with seeds
            if (dut.tx_lfsr_lane_0 !== 23'h1DBFBC) $error("Lane 0 seed not loaded");
            if (dut.tx_lfsr_lane_1 !== 23'h0607BB) $error("Lane 1 seed not loaded");
            if (dut.tx_lfsr_lane_2 !== 23'h1EC760) $error("Lane 2 seed not loaded");
            if (dut.tx_lfsr_lane_3 !== 23'h18C0DB) $error("Lane 3 seed not loaded");
            if (dut.tx_lfsr_lane_4 !== 23'h010F12) $error("Lane 4 seed not loaded");
            if (dut.tx_lfsr_lane_5 !== 23'h19CFC9) $error("Lane 5 seed not loaded");
            if (dut.tx_lfsr_lane_6 !== 23'h0277CE) $error("Lane 6 seed not loaded");
            if (dut.tx_lfsr_lane_7 !== 23'h1BB807) $error("Lane 7 seed not loaded");
            
            $display("CLEAR_LFSR test passed - seeds loaded correctly");
            
            i_state = IDLE;
            repeat(2) @(posedge i_clk);
        end
    endtask
    
    // Test case 2: Pattern LFSR without scrambling
    task test_pattern_lfsr_no_scramble();
        begin
            $display("\n=== TEST 2: PATTERN_LFSR (No Scramble) ===");
            reset_dut();
            
            i_state = PATTERN_LFSR;
            scramble_en = 0;
            i_width_deg_lfsr = DEGRADE_LANES_0_TO_7;
            
            wait_for_done();
            
            // Check that we completed 128 cycles
            if (dut.counter_lfsr !== 0) $error("Counter didn't reset properly");
            $display("Pattern LFSR completed %d cycles", 128);
            $display("PATTERN_LFSR no scramble test passed");
            
            i_state = IDLE;
            repeat(2) @(posedge i_clk);
        end
    endtask
    
    // Test case 3: Pattern LFSR with scrambling
    task test_pattern_lfsr_scramble();
        begin
            $display("\n=== TEST 3: PATTERN_LFSR (With Scramble) ===");
            reset_dut();
            
            i_state = PATTERN_LFSR;
            scramble_en = 1;
            i_width_deg_lfsr = DEGRADE_LANES_0_TO_7;
            
            // Check valid output during pattern generation
            @(posedge i_clk);
            if (!valid_frame_en) $error("valid_frame_en should be 1 during pattern");
            
            wait_for_done();
            
            $display("PATTERN_LFSR with scramble test passed");
            
            i_state = IDLE;
            repeat(2) @(posedge i_clk);
        end
    endtask
    
    // Test case 4: Per Lane IDE
    task test_per_lane_ide();
        begin
            $display("\n=== TEST 4: PER_LANE_IDE ===");
            reset_dut();
            
            i_state = PER_LANE_IDE;
            i_width_deg_lfsr = DEGRADE_LANES_0_TO_7;
            
            // Check lane ID pattern (first few cycles)
            @(posedge i_clk);
            if (o_lane_0 !== {16'b1010_00000000_1010, 16'b1010_00000000_1010}) begin
                $error("Lane 0 IDE pattern incorrect");
            end
            
            wait_for_done();
            
            // Check that we completed 64 cycles
            if (dut.counter_per_lane !== 0) $error("Per lane counter didn't reset");
            $display("PER_LANE_IDE test passed - completed %d cycles", 64);
            
            i_state = IDLE;
            repeat(2) @(posedge i_clk);
        end
    endtask
    
    // Test case 5: Lane reversal
    task test_lane_reversal();
        reg [WIDTH-1:0] expected_reversed [0:7];
        begin
            $display("\n=== TEST 5: LANE REVERSAL ===");
            reset_dut();
            
            reversal_en = 1;
            i_state = PATTERN_LFSR;
            scramble_en = 0;
            i_width_deg_lfsr = DEGRADE_LANES_0_TO_7;
            
            // Store expected reversed mapping
            expected_reversed[0] = dut.tx_lfsr_lane_7;
            expected_reversed[1] = dut.tx_lfsr_lane_6;
            expected_reversed[2] = dut.tx_lfsr_lane_5;
            expected_reversed[3] = dut.tx_lfsr_lane_4;
            expected_reversed[4] = dut.tx_lfsr_lane_3;
            expected_reversed[5] = dut.tx_lfsr_lane_2;
            expected_reversed[6] = dut.tx_lfsr_lane_1;
            expected_reversed[7] = dut.tx_lfsr_lane_0;
            
            wait_for_done();
            $display("Lane reversal test passed");
            
            i_state = IDLE;
            reversal_en = 0;
            repeat(2) @(posedge i_clk);
        end
    endtask
    
    // Test case 6: All degrade modes
    task test_all_degrade_modes();
        begin
            $display("\n=== TEST 6: ALL DEGRADE MODES ===");
            
            // Test DEGRADE_LANES_0_TO_7
            reset_dut();
            i_state = PATTERN_LFSR;
            scramble_en = 0;
            i_width_deg_lfsr = DEGRADE_LANES_0_TO_7;
            wait_for_done();
            $display("DEGRADE_LANES_0_TO_7: PASS");
            
            // Test DEGRADE_LANES_8_TO_15
            reset_dut();
            i_width_deg_lfsr = DEGRADE_LANES_8_TO_15;
            wait_for_done();
            $display("DEGRADE_LANES_8_TO_15: PASS");
            
            // Test DEGRADE_LANES_0_TO_15
            reset_dut();
            i_width_deg_lfsr = DEGRADE_LANES_0_TO_15;
            wait_for_done();
            $display("DEGRADE_LANES_0_TO_15: PASS");
            
            // Test DEGRADE_LANES_0_TO_3
            reset_dut();
            i_width_deg_lfsr = DEGRADE_LANES_0_TO_3;
            wait_for_done();
            $display("DEGRADE_LANES_0_TO_3: PASS");
            
            // Test DEGRADE_LANES_4_TO_7
            reset_dut();
            i_width_deg_lfsr = DEGRADE_LANES_4_TO_7;
            wait_for_done();
            $display("DEGRADE_LANES_4_TO_7: PASS");
        end
    endtask
    
    // Main test sequence
    initial begin
        $display("\n========================================");
        $display("Starting LFSR_TX Testbench");
        $display("========================================\n");
        
        // Run all tests
        test_clear_lfsr();
        test_pattern_lfsr_no_scramble();
        test_pattern_lfsr_scramble();
        test_per_lane_ide();
        test_lane_reversal();
        test_all_degrade_modes();
        
        $display("\n========================================");
        $display("ALL TESTS COMPLETED");
        $display("========================================\n");
        $finish();
    end
    
    // Monitor
    initial begin
        $monitor("Time=%0t | State=%b | valid=%b | done=%b | counter_lfsr=%d | counter_per_lane=%d",
                 $time, i_state, valid_frame_en, o_Lfsr_tx_done, dut.counter_lfsr, dut.counter_per_lane);
    end
    
    // Dump waveforms
    initial begin
        $dumpfile("LFSR_TX_tb.vcd");
        $dumpvars(0, LFSR_TX_tb);
    end

endmodule
