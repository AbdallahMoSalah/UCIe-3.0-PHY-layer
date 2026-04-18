`timescale 1ns/1ps

module MB_PATTERN_COMPARATOR_TB;

    parameter WIDTH = 32;

    // Inputs
    reg        i_clk;
    reg        i_rst_n;
    reg [1:0]  i_type_of_com;
    reg        i_enable_pattern_com;
    reg [15:0] i_max_error_threshold_per_lane_ID;
    reg [15:0] i_max_error_threshold_aggergate;

    // Generators and Data
    reg [WIDTH-1:0] local_gen [0:15];
    reg [WIDTH-1:0] rcv_data  [0:15];

    // Outputs
    wire [15:0] o_per_lane_error;
    wire [31:0] o_error_counter;
    wire        o_error_done;

    integer i, iter;
    integer seed = 32'hDEADBEEF;

    // Instantiate DUT
    PATTERN_COMPARATOR #(
        .WIDTH(WIDTH)
    ) DUT (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_type_of_com(i_type_of_com),
        .i_enable_pattern_com(i_enable_pattern_com),
        .i_max_error_threshold_per_lane_ID(i_max_error_threshold_per_lane_ID),
        .i_max_error_threshold_aggergate(i_max_error_threshold_aggergate),

        .i_local_gen_0(local_gen[0]),   .i_local_gen_1(local_gen[1]),
        .i_local_gen_2(local_gen[2]),   .i_local_gen_3(local_gen[3]),
        .i_local_gen_4(local_gen[4]),   .i_local_gen_5(local_gen[5]),
        .i_local_gen_6(local_gen[6]),   .i_local_gen_7(local_gen[7]),
        .i_local_gen_8(local_gen[8]),   .i_local_gen_9(local_gen[9]),
        .i_local_gen_10(local_gen[10]), .i_local_gen_11(local_gen[11]),
        .i_local_gen_12(local_gen[12]), .i_local_gen_13(local_gen[13]),
        .i_local_gen_14(local_gen[14]), .i_local_gen_15(local_gen[15]),

        .i_data_0(rcv_data[0]),   .i_data_1(rcv_data[1]),
        .i_data_2(rcv_data[2]),   .i_data_3(rcv_data[3]),
        .i_data_4(rcv_data[4]),   .i_data_5(rcv_data[5]),
        .i_data_6(rcv_data[6]),   .i_data_7(rcv_data[7]),
        .i_data_8(rcv_data[8]),   .i_data_9(rcv_data[9]),
        .i_data_10(rcv_data[10]), .i_data_11(rcv_data[11]),
        .i_data_12(rcv_data[12]), .i_data_13(rcv_data[13]),
        .i_data_14(rcv_data[14]), .i_data_15(rcv_data[15]),

        .o_per_lane_error(o_per_lane_error),
        .o_error_counter(o_error_counter),
        .o_error_done(o_error_done)
    );

    // Clock gen
    always #5 i_clk = ~i_clk; // 100 MHz

    initial begin
        // Initialize
        i_clk = 0;
        i_rst_n = 0;
        i_type_of_com = 2'b01; // LFSR mode
        i_enable_pattern_com = 0;
        i_max_error_threshold_per_lane_ID = 16'd10; // Disable lane if > 10 errors
        i_max_error_threshold_aggergate = 16'd50;

        for (i = 0; i < 16; i = i + 1) begin
            local_gen[i] = 0;
            rcv_data[i]  = 0;
        end

        // Assert reset
        #20;
        i_rst_n = 1;
        #10;

        // ==========================================
        // TEST 1: PERFECT MATCH TEST
        // ==========================================
        $display("[%0t] ==== STARTING TEST 1: No Errors ====", $time);
        @(posedge i_clk);
        i_enable_pattern_com = 1;

        // Drive random data for 128 cycles, cleanly matching
        for (iter = 0; iter < 128; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < 16; i = i + 1) begin
                local_gen[i] = $random(seed);
                rcv_data[i]  = local_gen[i]; // Perfect match
            end
        end

        // Wait for completion
        wait(o_error_done);
        @(posedge i_clk);
        i_enable_pattern_com = 0;
        
        $display("[%0t] Test 1 Done. Total Errors: %0d", $time, o_error_counter);
        if (o_error_counter !== 0 || o_per_lane_error !== 0)
            $display("-> FAILED Test 1!");
        else
            $display("-> PASSED Test 1!");

        #50;

        // ==========================================
        // TEST 2: ERROR INJECTION TEST
        // ==========================================
        $display("[%0t] ==== STARTING TEST 2: Error Injection ====", $time);
        @(posedge i_clk);
        i_enable_pattern_com = 1;

        // Run 128 iterations
        // We will inject exactly:
        // - 5 errors in lane 3 (should not exceed threshold 10, won't disable)
        // - 20 errors in lane 7 (exceeds threshold 10, will disable lane / flag error)
        for (iter = 0; iter < 128; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < 16; i = i + 1) begin
                local_gen[i] = $random(seed);
                
                // Default match
                rcv_data[i] = local_gen[i]; 

                // Inject 1 bit error in lane 3 for first 5 iterations
                if (i == 3 && iter < 5) begin
                    rcv_data[i][0] = ~local_gen[i][0]; // flip bit 0
                end
                
                // Inject 2 bit errors in lane 7 for first 10 iterations (20 errors total)
                if (i == 7 && iter < 10) begin
                    rcv_data[i][0] = ~local_gen[i][0];
                    rcv_data[i][1] = ~local_gen[i][1];
                end
            end
        end

        wait(o_error_done);
        @(posedge i_clk);
        i_enable_pattern_com = 0;

        $display("[%0t] Test 2 Done. Total Errors: %0d", $time, o_error_counter);
        $display("Lane Flags: %b", o_per_lane_error);

        // Verify counts
        // Aggregate = 5 + 20 = 25
        if (o_error_counter === 25 && o_per_lane_error[7] === 1'b1 && o_per_lane_error[3] === 1'b0) begin
             $display("-> PASSED Test 2!");
        end else begin
             $display("-> FAILED Test 2! (Expected Aggregate=25, Lane 7 flaged)");
        end

        #100;
        $stop;
    end

endmodule
