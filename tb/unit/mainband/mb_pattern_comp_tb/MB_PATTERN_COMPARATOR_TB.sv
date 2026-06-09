`timescale 1ns/1ps

module MB_PATTERN_COMPARATOR_TB;

    parameter WIDTH = 32;
    parameter NUM_LANES = 16;

    // Inputs
    reg        i_clk;
    reg        i_rst_n;
    reg        i_enable;
    reg        i_comparison_mode;
    reg [NUM_LANES-1:0] i_lane_mask;
    reg [15:0] i_max_error_threshold_per_lane;
    reg [15:0] i_max_error_threshold_aggregate;
    reg [15:0] i_iteration_count;
    reg        i_pattern_mode;
    reg        i_clear_error;
    reg        i_pcmp_enable;

    // Patterns
    reg [WIDTH-1:0] local_gen [0:NUM_LANES-1];
    reg [WIDTH-1:0] rcv_data  [0:NUM_LANES-1];

    // Outputs
    wire       o_done;
    wire [NUM_LANES-1:0] o_per_lane_pass;
    wire [15:0] o_aggregate_error_counter;
    wire        o_aggregate_error;

    integer i, iter;
    integer seed = 32'hDEADBEEF;

    // Instantiate DUT
    unit_mb_pattern_comparator #(
        .NUM_LANES(NUM_LANES),
        .WIDTH(WIDTH)
    ) DUT (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_enable(i_enable),
        .i_comparison_mode(i_comparison_mode),
        .i_lane_mask(i_lane_mask),
        .i_max_error_threshold_per_lane(i_max_error_threshold_per_lane),
        .i_max_error_threshold_aggregate(i_max_error_threshold_aggregate),
        .i_iteration_count(i_iteration_count),
        .i_pattern_mode(i_pattern_mode),
        .i_clear_error(i_clear_error),
        .i_local_pattern(local_gen),
        .i_rx_pattern(rcv_data),
        .i_pcmp_enable(i_pcmp_enable),
        .o_done(o_done),
        .o_per_lane_pass(o_per_lane_pass),
        .o_aggregate_error_counter(o_aggregate_error_counter),
        .o_aggregate_error(o_aggregate_error)
    );

    // Clock gen
    always #5 i_clk = ~i_clk; // 100 MHz

    initial begin
        // Initialize inputs
        i_clk = 0;
        i_rst_n = 0;
        i_enable = 0;
        i_comparison_mode = 0;
        i_lane_mask = 0;
        i_max_error_threshold_per_lane = 16'd10;
        i_max_error_threshold_aggregate = 16'd50;
        i_iteration_count = 16'd128;
        i_pattern_mode = 0;
        i_clear_error = 0;
        i_pcmp_enable = 1;

        for (i = 0; i < NUM_LANES; i = i + 1) begin
            local_gen[i] = 0;
            rcv_data[i]  = 0;
        end

        // Assert reset
        #20;
        i_rst_n = 1;
        #10;

        // =====================================================================
        // TEST 1: LFSR MODE, PERFECT MATCH (NO ERRORS)
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 1: LFSR mode, No Errors ====", $time);
        i_pattern_mode = 0;
        i_comparison_mode = 0;
        i_lane_mask = 0;
        i_iteration_count = 16'd128;
        i_max_error_threshold_per_lane = 16'd10;

        @(posedge i_clk);
        i_enable = 1;

        // Drive matching random data
        for (iter = 0; iter < 128; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = $random(seed);
                rcv_data[i]  = local_gen[i];
            end
        end

        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        #10;

        $display("TEST 1: o_per_lane_pass = %b (Expected: all 1s)", o_per_lane_pass);
        if (o_per_lane_pass !== {NUM_LANES{1'b1}}) begin
            $display("-> FAILED Test 1!");
            $stop;
        end else begin
            $display("-> PASSED Test 1!");
        end

        #50;

        // =====================================================================
        // TEST 2: LFSR MODE, ERROR INJECTION WITH THRESHOLD
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 2: LFSR mode, Error Injection ====", $time);
        i_pattern_mode = 0;
        i_comparison_mode = 0;
        i_lane_mask = 0;
        i_iteration_count = 16'd128;
        i_max_error_threshold_per_lane = 16'd10;

        @(posedge i_clk);
        i_enable = 1;

        for (iter = 0; iter < 128; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = $random(seed);
                rcv_data[i]  = local_gen[i];

                // Inject 5 errors on Lane 3 (errors <= threshold 10 => should PASS)
                if (i == 3 && iter < 5) begin
                    rcv_data[i][0] = ~local_gen[i][0];
                end

                // Inject 15 errors on Lane 7 (errors > threshold 10 => should FAIL)
                if (i == 7 && iter < 15) begin
                    rcv_data[i][0] = ~local_gen[i][0];
                end
            end
        end

        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        #10;

        $display("TEST 2: o_per_lane_pass = %b (Expected: o_per_lane_pass[7] = 0, o_per_lane_pass[3] = 1)", o_per_lane_pass);
        if (o_per_lane_pass[7] !== 1'b0 || o_per_lane_pass[3] !== 1'b1) begin
            $display("-> FAILED Test 2!");
            $stop;
        end else begin
            $display("-> PASSED Test 2!");
        end

        #50;

        // =====================================================================
        // TEST 3: LFSR MODE WITH MASK
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 3: LFSR mode, Lane 7 Masked ====", $time);
        i_pattern_mode = 0;
        i_comparison_mode = 0;
        i_lane_mask = 16'b0000_0000_1000_0000; // Mask lane 7
        i_iteration_count = 16'd128;
        i_max_error_threshold_per_lane = 16'd10;

        @(posedge i_clk);
        i_enable = 1;

        for (iter = 0; iter < 128; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = $random(seed);
                rcv_data[i]  = local_gen[i];

                // Inject 15 errors on Lane 7 (since masked, should PASS)
                if (i == 7 && iter < 15) begin
                    rcv_data[i][0] = ~local_gen[i][0];
                end
            end
        end

        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        #10;

        $display("TEST 3: o_per_lane_pass = %b (Expected: o_per_lane_pass[7] = 1)", o_per_lane_pass);
        if (o_per_lane_pass[7] !== 1'b1) begin
            $display("-> FAILED Test 3!");
            $stop;
        end else begin
            $display("-> PASSED Test 3!");
        end

        #50;

        // =====================================================================
        // TEST 4: PER-LANE ID PATTERN MODE, PERFECT MATCH (16 CONSECUTIVE MATCHES)
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 4: Per-Lane ID Pattern mode, No Errors ====", $time);
        i_pattern_mode = 1; // Per-lane ID mode
        i_comparison_mode = 0;
        i_lane_mask = 0;
        i_iteration_count = 16'd10; // Only run 10 cycles (20 iterations)

        @(posedge i_clk);
        i_enable = 1;

        // Drive matching lane ID patterns
        for (iter = 0; iter < 10; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = {16'b1010_00000000_1010 + i[15:0], 16'b1010_00000000_1010 + i[15:0]};
                rcv_data[i]  = local_gen[i];
            end
            if (iter == 8) begin
                // At cycle 8 (8 cycles * 2 iterations/cycle = 16 iterations), all lanes should transition to pass
                #1;
                $display("Cycle 8: o_per_lane_pass = %b (Expected: all 1s)", o_per_lane_pass);
                if (o_per_lane_pass !== {NUM_LANES{1'b1}}) begin
                    $display("-> FAILED Test 4 midcheck!");
                    $stop;
                end
            end
        end

        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        #10;

        $display("TEST 4: Final o_per_lane_pass = %b", o_per_lane_pass);
        if (o_per_lane_pass !== {NUM_LANES{1'b1}}) begin
            $display("-> FAILED Test 4!");
            $stop;
        end else begin
            $display("-> PASSED Test 4!");
        end

        #50;

        // =====================================================================
        // TEST 5: PER-LANE ID PATTERN MODE, WITH MISMATCH (CONSECUTIVE RESET)
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 5: Per-Lane ID Pattern mode, With Mismatch ====", $time);
        i_pattern_mode = 1;
        i_comparison_mode = 0;
        i_lane_mask = 0;
        i_iteration_count = 16'd20; // 40 iterations

        @(posedge i_clk);
        i_enable = 1;

        for (iter = 0; iter < 20; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = {16'b1010_00000000_1010 + i[15:0], 16'b1010_00000000_1010 + i[15:0]};
                rcv_data[i]  = local_gen[i];

                // Inject error on Lane 2 at iteration 10 (cycle 5, upper 16 bits)
                if (i == 2 && iter == 5) begin
                    rcv_data[i][31:16] = ~local_gen[i][31:16];
                end
            end

            // Check after cycle 8 (iteration 16)
            if (iter == 8) begin
                #1;
                // Lane 2 should be 0 because the mismatch at cycle 5 reset its counter
                $display("Cycle 8 check: o_per_lane_pass[2] = %b (Expected: 0)", o_per_lane_pass[2]);
                if (o_per_lane_pass[2] !== 1'b0) begin
                    $display("-> FAILED Test 5 midcheck!");
                    $stop;
                end
            end
        end

        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        #10;

        $display("TEST 5: Final o_per_lane_pass = %b (Expected: all 1s since Lane 2 eventually had 16 consecutive matches after cycle 5)", o_per_lane_pass);
        if (o_per_lane_pass !== {NUM_LANES{1'b1}}) begin
            $display("-> FAILED Test 5!");
            $stop;
        end else begin
            $display("-> PASSED Test 5!");
        end

        #50;

        // =====================================================================
        // TEST 6: PER-LANE ID PATTERN MODE, LANE 4 MASKED
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 6: Per-Lane ID Pattern mode, Lane 4 Masked ====", $time);
        i_pattern_mode = 1;
        i_comparison_mode = 0;
        i_lane_mask = 16'b0000_0000_0001_0000; // Mask lane 4
        i_iteration_count = 16'd5; // Run 5 cycles (10 iterations)

        @(posedge i_clk);
        i_enable = 1;

        for (iter = 0; iter < 5; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = {16'b1010_00000000_1010 + i[15:0], 16'b1010_00000000_1010 + i[15:0]};
                rcv_data[i]  = local_gen[i];
            end
            // Check even at cycle 2: masked lane 4 should be 1 (PASS) immediately
            #1;
            if (o_per_lane_pass[4] !== 1'b1) begin
                $display("-> FAILED Test 6 midcheck: o_per_lane_pass[4] = %b", o_per_lane_pass[4]);
                $stop;
            end
        end

        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        #10;
        $display("-> PASSED Test 6!");

        #50;

        // =====================================================================
        // TEST 7: CLEAR ERROR INPUT
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 7: Clear Error Test ====", $time);
        i_pattern_mode = 0; // LFSR mode
        i_comparison_mode = 0;
        i_lane_mask = 0;
        i_iteration_count = 16'd30;
        i_max_error_threshold_per_lane = 16'd5;

        @(posedge i_clk);
        i_enable = 1;

        for (iter = 0; iter < 10; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = $random(seed);
                rcv_data[i]  = local_gen[i];
                // Inject errors to exceed threshold
                if (i == 5 && iter < 8) begin
                    rcv_data[i][0] = ~local_gen[i][0];
                end
            end
        end

        // Lane 5 should be 0 (FAIL)
        #1;
        $display("Before Clear: o_per_lane_pass[5] = %b", o_per_lane_pass[5]);
        if (o_per_lane_pass[5] !== 1'b0) begin
            $display("-> FAILED Test 7 (failed to flag error before clear)!");
            $stop;
        end

        // Assert clear error
        @(posedge i_clk);
        i_clear_error = 1;
        @(posedge i_clk);
        i_clear_error = 0;
        #1;

        $display("After Clear: o_per_lane_pass[5] = %b (Expected: 1)", o_per_lane_pass[5]);
        if (o_per_lane_pass[5] !== 1'b1) begin
            $display("-> FAILED Test 7 (clear failed)!");
            $stop;
        end else begin
            $display("-> PASSED Test 7!");
        end

        #50;

        // =====================================================================
        // TEST 8: AGGREGATE COMPARISON MODE
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 8: Aggregate comparison mode ====", $time);
        i_pattern_mode = 0;
        i_comparison_mode = 1; // Aggregate mode
        i_lane_mask = 0;
        i_iteration_count = 16'd10;
        i_max_error_threshold_aggregate = 16'd5;

        @(posedge i_clk);
        i_enable = 1;

        for (iter = 0; iter < 10; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = $random(seed);
                rcv_data[i]  = local_gen[i];
            end

            // Cycle 2: Inject errors at same UI (bit 5) in all lanes
            if (iter == 2) begin
                for (i = 0; i < NUM_LANES; i = i + 1) begin
                    rcv_data[i][5] = ~local_gen[i][5];
                end
            end
        end

        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        #10;

        $display("TEST 8: o_aggregate_error_counter = %d (Expected: 1 error UI)", o_aggregate_error_counter);
        if (o_aggregate_error_counter !== 16'd1) begin
            $display("-> FAILED Test 8!");
            $stop;
        end else begin
            $display("-> PASSED Test 8!");
        end

        #50;

        // =====================================================================
        // TEST 9: i_pcmp_enable GATING TEST
        // =====================================================================
        $display("[%0t] ==== STARTING TEST 9: i_pcmp_enable Gating Test ====", $time);
        i_pattern_mode = 0; // LFSR mode
        i_comparison_mode = 0; // Per-lane mode
        i_lane_mask = 0;
        i_iteration_count = 16'd5;
        i_max_error_threshold_per_lane = 16'd0; // Any error will fail lane immediately

        @(posedge i_clk);
        i_pcmp_enable = 0; // Disable comparison
        i_enable = 1;

        // Drive mismatches, but since i_pcmp_enable=0, no error should be detected
        // and iter_ctr should not increment (it should stay 0).
        for (iter = 0; iter < 10; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = 32'hAAAA_AAAA;
                rcv_data[i]  = 32'hBBBB_BBBB; // Mismatch on all lanes
            end
        end

        // Wait a few cycles, verify that iter_ctr (or o_done) is still 0, and o_per_lane_pass has no errors.
        #1;
        if (o_done) begin
            $display("-> FAILED Test 9: o_done went high when comparator was disabled!");
            $stop;
        end
        if (o_per_lane_pass !== {NUM_LANES{1'b1}}) begin
            $display("-> FAILED Test 9: errors detected while comparator was disabled!");
            $stop;
        end

        // Now enable i_pcmp_enable and drive matching data
        @(posedge i_clk);
        i_pcmp_enable = 1;
        for (i = 0; i < NUM_LANES; i = i + 1) begin
            local_gen[i] = 32'h1234_5678;
            rcv_data[i]  = 32'h1234_5678;
        end

        // Drive matching random data for the actual comparison
        for (iter = 0; iter < 5; iter = iter + 1) begin
            @(posedge i_clk);
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                local_gen[i] = $random(seed);
                rcv_data[i]  = local_gen[i]; // No errors now
            end
        end

        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        #10;

        if (o_per_lane_pass !== {NUM_LANES{1'b1}}) begin
            $display("-> FAILED Test 9: failed on matching iterations!");
            $stop;
        end else begin
            $display("-> PASSED Test 9!");
        end

        #50;

        $display("\n[%0t] ==== ALL TESTS PASSED SUCCESSFULLY ====", $time);
        $stop;
    end

endmodule
