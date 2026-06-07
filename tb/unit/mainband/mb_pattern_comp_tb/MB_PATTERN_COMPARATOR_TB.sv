`timescale 1ns/1ps

module MB_PATTERN_COMPARATOR_TB;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam NUM_LANES = 16;
    localparam WIDTH     = 32;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg                      i_clk;
    reg                      i_rst_n;
    reg                      i_enable;
    reg                      i_comparison_mode;    // 0 = Per-Lane, 1 = Aggregate
    reg  [NUM_LANES-1:0]     i_lane_mask;
    reg  [11:0]              i_min_pass_threshold_per_lane;
    reg  [15:0]              i_max_error_threshold_aggregate;
    reg  [15:0]              i_iteration_count;

    reg  [WIDTH-1:0]         i_local_pattern [0:NUM_LANES-1];
    reg  [WIDTH-1:0]         i_rx_pattern    [0:NUM_LANES-1];

    wire                     o_done;
    wire [NUM_LANES-1:0]     o_per_lane_pass;
    wire                     o_all_lane_pass;
    wire [15:0]              o_aggregate_error_counter;
    wire                     o_aggregate_pass;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    unit_mb_pattern_comparator #(
        .NUM_LANES (NUM_LANES),
        .WIDTH     (WIDTH)
    ) DUT (
        .i_clk                          (i_clk),
        .i_rst_n                        (i_rst_n),
        .i_enable                       (i_enable),
        .i_comparison_mode              (i_comparison_mode),
        .i_lane_mask                    (i_lane_mask),
        .i_min_pass_threshold_per_lane  (i_min_pass_threshold_per_lane),
        .i_max_error_threshold_aggregate(i_max_error_threshold_aggregate),
        .i_iteration_count              (i_iteration_count),
        .i_local_pattern                (i_local_pattern),
        .i_rx_pattern                   (i_rx_pattern),
        .o_done                         (o_done),
        .o_per_lane_pass                (o_per_lane_pass),
        .o_all_lane_pass                (o_all_lane_pass),
        .o_aggregate_error_counter      (o_aggregate_error_counter),
        .o_aggregate_pass               (o_aggregate_pass)
    );

    // -------------------------------------------------------------------------
    // Clock: 100 MHz
    // -------------------------------------------------------------------------
    always #5 i_clk = ~i_clk;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    integer i, iter;
    integer fail_count;

    task reset_dut;
        begin
            i_enable          = 0;
            i_comparison_mode = 0;
            i_lane_mask       = '0;
            i_min_pass_threshold_per_lane   = 12'd0;
            i_max_error_threshold_aggregate = 16'd0;
            i_iteration_count = 16'd128;
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                i_local_pattern[i] = '0;
                i_rx_pattern[i]    = '0;
            end
            i_rst_n = 0;
            @(posedge i_clk); @(posedge i_clk);
            i_rst_n = 1;
            @(posedge i_clk);
        end
    endtask

    // =========================================================================
    // TEST SEQUENCE
    // =========================================================================
    initial begin
        fail_count = 0;
        i_clk      = 0;
        reset_dut();

        // =====================================================================
        // TEST 1: Per-Lane mode — perfect match, all lanes should PASS
        //   128 cycles × 32 bits = 4096 passes per lane.
        //   Threshold = 4096 → every lane must reach exactly 4096.
        // =====================================================================
        $display("\n[%0t] ===== TEST 1: Per-Lane, Perfect Match =====", $time);
        i_comparison_mode             = 1'b0;
        i_lane_mask                   = '0;
        i_min_pass_threshold_per_lane = 12'd4096;
        i_iteration_count             = 16'd128;

        // Enable before fork so first pattern cycle is the first S_COMPARE cycle
        @(posedge i_clk);
        i_enable = 1;

        fork
            begin : pattern_t1
                for (iter = 0; iter < 128; iter = iter + 1) begin
                    @(posedge i_clk);
                    for (i = 0; i < NUM_LANES; i = i + 1) begin
                        i_local_pattern[i] = $urandom;
                        i_rx_pattern[i]    = i_local_pattern[i];   // perfect match
                    end
                end
            end
            begin : wait_t1
                wait (o_done === 1'b1);
                @(posedge i_clk);
                i_enable = 0;
            end
        join

        @(posedge i_clk);
        if (o_all_lane_pass !== 1'b1 || o_per_lane_pass !== {NUM_LANES{1'b1}}) begin
            $display("  FAIL: expected all lanes pass. per_lane_pass=%b all=%b",
                     o_per_lane_pass, o_all_lane_pass);
            fail_count = fail_count + 1;
        end else
            $display("  PASS: all lanes passed. per_lane_pass=%b", o_per_lane_pass);

        reset_dut();

        // =====================================================================
        // TEST 2: Per-Lane mode — lane 5 has all errors (0 passes), rest perfect
        //   Lane 5: rcv = ~local → 0 passes → should NOT get pass flag.
        //   Threshold = 100. Others get 128*32 = 4096 passes → PASS.
        // =====================================================================
        $display("\n[%0t] ===== TEST 2: Per-Lane, Lane 5 All Errors =====", $time);
        i_comparison_mode             = 1'b0;
        i_lane_mask                   = '0;
        i_min_pass_threshold_per_lane = 12'd100;
        i_iteration_count             = 16'd128;

        @(posedge i_clk);
        i_enable = 1;

        fork
            begin : pattern_t2
                for (iter = 0; iter < 128; iter = iter + 1) begin
                    @(posedge i_clk);
                    for (i = 0; i < NUM_LANES; i = i + 1) begin
                        i_local_pattern[i] = $urandom;
                        if (i == 5)
                            i_rx_pattern[i] = ~i_local_pattern[i];   // all bits wrong
                        else
                            i_rx_pattern[i] = i_local_pattern[i];    // perfect match
                    end
                end
            end
            begin : wait_t2
                wait (o_done === 1'b1);
                @(posedge i_clk);
                i_enable = 0;
            end
        join

        @(posedge i_clk);
        if (o_per_lane_pass[5] !== 1'b0) begin
            $display("  FAIL: lane 5 should not have pass flag. per_lane_pass=%b", o_per_lane_pass);
            fail_count = fail_count + 1;
        end else if (o_per_lane_pass[4] !== 1'b1 || o_per_lane_pass[6] !== 1'b1) begin
            $display("  FAIL: neighboring lanes should pass. per_lane_pass=%b", o_per_lane_pass);
            fail_count = fail_count + 1;
        end else
            $display("  PASS: lane 5 no pass flag, others passed. per_lane_pass=%b", o_per_lane_pass);

        reset_dut();

        // =====================================================================
        // TEST 3: Per-Lane mode — lane 2 masked, all others perfect
        //   Lane 2 has all errors but is masked → o_all_lane_pass should still be 1.
        // =====================================================================
        $display("\n[%0t] ===== TEST 3: Per-Lane, Masked Lane Ignored =====", $time);
        i_comparison_mode             = 1'b0;
        i_lane_mask                   = 16'h0004;    // mask lane 2
        i_min_pass_threshold_per_lane = 12'd100;
        i_iteration_count             = 16'd128;

        @(posedge i_clk);
        i_enable = 1;

        fork
            begin : pattern_t3
                for (iter = 0; iter < 128; iter = iter + 1) begin
                    @(posedge i_clk);
                    for (i = 0; i < NUM_LANES; i = i + 1) begin
                        i_local_pattern[i] = $urandom;
                        if (i == 2)
                            i_rx_pattern[i] = ~i_local_pattern[i]; // errors, but masked
                        else
                            i_rx_pattern[i] = i_local_pattern[i];
                    end
                end
            end
            begin : wait_t3
                wait (o_done === 1'b1);
                @(posedge i_clk);
                i_enable = 0;
            end
        join

        @(posedge i_clk);
        if (o_all_lane_pass !== 1'b1) begin
            $display("  FAIL: masked lane should not block all_lane_pass. all=%b per=%b",
                     o_all_lane_pass, o_per_lane_pass);
            fail_count = fail_count + 1;
        end else
            $display("  PASS: masked lane ignored, all_lane_pass=1. per_lane_pass=%b", o_per_lane_pass);

        reset_dut();

        // =====================================================================
        // TEST 4: Aggregate mode — perfect match → 0 errors → pass
        // =====================================================================
        $display("\n[%0t] ===== TEST 4: Aggregate, No Errors =====", $time);
        i_comparison_mode               = 1'b1;
        i_lane_mask                     = '0;
        i_max_error_threshold_aggregate = 16'd10;
        i_iteration_count               = 16'd128;

        @(posedge i_clk);
        i_enable = 1;

        fork
            begin : pattern_t4
                for (iter = 0; iter < 128; iter = iter + 1) begin
                    @(posedge i_clk);
                    for (i = 0; i < NUM_LANES; i = i + 1) begin
                        i_local_pattern[i] = $urandom;
                        i_rx_pattern[i]    = i_local_pattern[i];
                    end
                end
            end
            begin : wait_t4
                wait (o_done === 1'b1);
                @(posedge i_clk);
                i_enable = 0;
            end
        join

        @(posedge i_clk);
        if (o_aggregate_error_counter !== 16'd0 || o_aggregate_pass !== 1'b1) begin
            $display("  FAIL: expected 0 errors. counter=%0d pass=%b",
                     o_aggregate_error_counter, o_aggregate_pass);
            fail_count = fail_count + 1;
        end else
            $display("  PASS: 0 errors, aggregate_pass=1");

        reset_dut();

        // =====================================================================
        // TEST 5: Aggregate mode — inject exactly 10 error UIs
        //   Each cycle for first 10 cycles: flip bit[0] of lane 0.
        //   Each flip → 1 UI position has mismatch on at least 1 lane → 1 error UI.
        //   Expected: aggregate_error_counter = 10, threshold = 10 → pass.
        //
        //   i_enable is raised one cycle before the fork so the DUT enters
        //   S_COMPARE exactly when iter=0 patterns are first driven.
        // =====================================================================
        $display("\n[%0t] ===== TEST 5: Aggregate, Exactly 10 Error UIs =====", $time);
        i_comparison_mode               = 1'b1;
        i_lane_mask                     = '0;
        i_max_error_threshold_aggregate = 16'd10;
        i_iteration_count               = 16'd128;

        @(posedge i_clk);
        i_enable = 1;

        fork
            begin : pattern_t5
                for (iter = 0; iter < 128; iter = iter + 1) begin
                    @(posedge i_clk);
                    for (i = 0; i < NUM_LANES; i = i + 1) begin
                        i_local_pattern[i] = 32'hAAAA_AAAA;
                        i_rx_pattern[i]    = i_local_pattern[i];
                    end
                    if (iter < 10)
                        i_rx_pattern[0][0] = ~i_local_pattern[0][0];
                end
            end
            begin : wait_t5
                wait (o_done === 1'b1);
                @(posedge i_clk);
                i_enable = 0;
            end
        join

        @(posedge i_clk);
        if (o_aggregate_error_counter !== 16'd10) begin
            $display("  FAIL: expected 10 error UIs, got %0d. pass=%b",
                     o_aggregate_error_counter, o_aggregate_pass);
            fail_count = fail_count + 1;
        end else if (o_aggregate_pass !== 1'b1) begin
            $display("  FAIL: counter=10 <= threshold=10, should pass. pass=%b", o_aggregate_pass);
            fail_count = fail_count + 1;
        end else
            $display("  PASS: aggregate_error_counter=%0d, aggregate_pass=1",
                     o_aggregate_error_counter);

        reset_dut();

        // =====================================================================
        // TEST 6: Aggregate mode — errors exceed threshold → FAIL
        //   20 error UIs, threshold = 10 → aggregate_pass should be 0.
        // =====================================================================
        $display("\n[%0t] ===== TEST 6: Aggregate, Errors Exceed Threshold =====", $time);
        i_comparison_mode               = 1'b1;
        i_lane_mask                     = '0;
        i_max_error_threshold_aggregate = 16'd10;
        i_iteration_count               = 16'd128;

        @(posedge i_clk);
        i_enable = 1;

        fork
            begin : pattern_t6
                for (iter = 0; iter < 128; iter = iter + 1) begin
                    @(posedge i_clk);
                    for (i = 0; i < NUM_LANES; i = i + 1) begin
                        i_local_pattern[i] = 32'h5555_5555;
                        i_rx_pattern[i]    = i_local_pattern[i];
                    end
                    if (iter < 20)
                        i_rx_pattern[3][0] = ~i_local_pattern[3][0];
                end
            end
            begin : wait_t6
                wait (o_done === 1'b1);
                @(posedge i_clk);
                i_enable = 0;
            end
        join

        @(posedge i_clk);
        if (o_aggregate_error_counter !== 16'd20) begin
            $display("  FAIL: expected 20 error UIs, got %0d", o_aggregate_error_counter);
            fail_count = fail_count + 1;
        end else if (o_aggregate_pass !== 1'b0) begin
            $display("  FAIL: 20 errors > threshold 10, should fail. pass=%b", o_aggregate_pass);
            fail_count = fail_count + 1;
        end else
            $display("  PASS: aggregate_error_counter=%0d > threshold, aggregate_pass=0",
                     o_aggregate_error_counter);

        reset_dut();

        // =====================================================================
        // TEST 7: Abort — de-assert i_enable mid-test, FSM should return to IDLE
        // =====================================================================
        $display("\n[%0t] ===== TEST 7: Abort Mid-Test =====", $time);
        i_comparison_mode             = 1'b0;
        i_lane_mask                   = '0;
        i_min_pass_threshold_per_lane = 12'd4096;
        i_iteration_count             = 16'd128;

        for (i = 0; i < NUM_LANES; i = i + 1) begin
            i_local_pattern[i] = $urandom;
            i_rx_pattern[i]    = i_local_pattern[i];
        end

        @(posedge i_clk);
        i_enable = 1;
        repeat(20) @(posedge i_clk);
        i_enable = 0;
        repeat(5) @(posedge i_clk);

        if (o_done !== 1'b0) begin
            $display("  FAIL: o_done should be 0 after abort, got %b", o_done);
            fail_count = fail_count + 1;
        end else
            $display("  PASS: FSM aborted cleanly, o_done=0");

        reset_dut();

        // =====================================================================
        // SUMMARY
        // =====================================================================
        $display("\n[%0t] ===== SIMULATION COMPLETE — %0d failure(s) =====\n",
                 $time, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");

        $finish;
    end

endmodule
