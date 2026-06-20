// Module: MB_PATTERN_COMPARATOR
// Status: WIP  (spec-faithful development copy, lives in unsued/)
// Description:
//   UCIe 3.0 MainBand RX pattern comparator (Section 4.4, Figures 4-28 / 4-29).
//   It takes the two patterns required by the spec and compares them on every
//   Valid Lane of the module:
//       i_local_pattern : locally generated reference / expected pattern
//       i_rx_pattern    : pattern received from the Link partner
//
//   Two comparison schemes are implemented and selected by i_comparison_mode
//   (Table 7-11 Data Field bit [59]):
//       0 = Per-Lane comparison  (Fig 4-28, "Lane failure detection")
//             For each Lane, the accumulated bit errors are compared against the
//             per-Lane threshold.  Any Lane whose error count exceeds the
//             threshold gets a *sticky* error-detect bit that holds for the rest
//             of the test ("Once a pattern mismatch on a particular Lane is found,
//             this error bit is set for the remainder of the test").
//       1 = Aggregate comparison (Fig 4-29, "All Lane error detection")
//             "Pattern mismatches each UI on any Lane within the module are
//             accumulated into a 16-bit error counter. The Lane errors are ORed
//             to generate a module-level error and counted." i.e. per UI we OR
//             the mismatch across all (unmasked) Lanes, and count the UIs that
//             had at least one error.
//
//   Spec references:
//     - Comparison schemes ............ UCIe 3.0 Section 4.4 (Fig 4-28 / 4-29)
//     - Mode + result encodings ....... Table 7-11 (Data Field [59], MsgInfo [4])
//     - Per-Lane / aggregate thresholds Section 9.5.3.29 (Training Setup 4)
//     - Lane mask ..................... Section 9.5.3.28 (Training Setup 3)
//
// Author: Mohamed Anwar
module unit_mb_pattern_comparator #(
    parameter int NUM_LANES  = 16,   // Valid Lanes per module (x16 Standard Package => N = 16)
    parameter int WIDTH      = 32    // UI (bits) per Lane per clock
)(
    input  wire                  i_clk,
    input  wire                  i_rst_n,

    // ---------------- Control ----------------
    input  wire                  i_enable,             // run a comparison test while high
    input  wire                  i_comparison_mode,    // 0 = Per-Lane, 1 = Aggregate (Table 7-11 [59])
    input  wire [NUM_LANES-1:0]  i_lane_mask,          // 1 = Lane masked / excluded (Training Setup 3)
    input  wire [11:0]           i_max_error_threshold_per_lane,    // per-Lane threshold  (9.5.3.29)
    input  wire [15:0]           i_max_error_threshold_aggregate,   // aggregate threshold (9.5.3.29)
    input  wire [15:0]           i_iteration_count,                 // # compare cycles per test (e.g. 128); hold stable during a test
    input  wire                  i_pattern_mode,                    // 1 = perlane id pattern, 0 = LFSR pattern
    input  wire                  i_clear_error,
    // ---------------- Patterns (the two inputs) ----------------
    input  wire [WIDTH-1:0]      i_local_pattern [0:NUM_LANES-1],   // local / expected
    input  wire [WIDTH-1:0]      i_rx_pattern    [0:NUM_LANES-1],   // received from partner
    input  wire                  i_pcmp_enable,
    // ---------------- Results ----------------
    output reg                   o_done,                      // test complete, results valid
    output reg  [NUM_LANES-1:0]  o_per_lane_pass,             // 1 = Lane PASS, sticky (Fig 4-28 / per-lane ID)
    output reg                   o_aggregate_error             // 1 = Fail: aggregate count > threshold
);
    // =========================================================================
    // Popcount helper (number of set bits in a WIDTH-bit vector)
    // =========================================================================
    function automatic [15:0] popcount_w(input [WIDTH-1:0] v);
        integer i;
        begin
            popcount_w = 16'd0;
            for (i = 0; i < WIDTH; i = i + 1)
                popcount_w = popcount_w + v[i];
        end
    endfunction

    // =========================================================================
    // Per-cycle combinational mismatch evaluation
    // =========================================================================
    // Bitwise mismatch per Lane, masked Lanes contribute nothing.
    wire [WIDTH-1:0] mismatch_masked [0:NUM_LANES-1];

    genvar g;
    generate
        for (g = 0; g < NUM_LANES; g = g + 1) begin : gen_mismatch
            assign mismatch_masked[g] = i_lane_mask[g]
                                      ? {WIDTH{1'b0}}
                                      : (i_local_pattern[g] ^ i_rx_pattern[g]);
        end
    endgenerate

    // Per-Lane bit-error count this cycle, and aggregate UI-error count this cycle.
    reg  [15:0]      lane_inc [0:NUM_LANES-1];   // mismatched bits per Lane this cycle
    reg  [WIDTH-1:0] ui_any_mismatch;            // OR of all unmasked Lanes, per UI position
    reg  [15:0]      agg_inc;                    // number of UIs with >=1 error this cycle

    integer li, bi;
    always @(*) begin
        // Per-Lane: count mismatched bits in each Lane.
        for (li = 0; li < NUM_LANES; li = li + 1)
            lane_inc[li] = popcount_w(mismatch_masked[li]);

        // Aggregate: for each UI position OR the mismatch across all Lanes,
        // then count how many UIs had an error (module-level error per UI).
        for (bi = 0; bi < WIDTH; bi = bi + 1) begin
            ui_any_mismatch[bi] = 1'b0;
            for (li = 0; li < NUM_LANES; li = li + 1)
                ui_any_mismatch[bi] = ui_any_mismatch[bi] | mismatch_masked[li][bi];
        end
        agg_inc = popcount_w(ui_any_mismatch);
    end

    // =========================================================================
    // Test FSM and accumulation
    // =========================================================================
    localparam [1:0] S_IDLE    = 2'd0,
                     S_COMPARE = 2'd1,
                     S_DONE    = 2'd2;

    reg [1:0]  state;
    reg [15:0] iter_ctr;
    reg [15:0] lane_err_accum [0:NUM_LANES-1];   // accumulated bit errors per Lane
    reg [4:0]  consecutive_ctr [0:NUM_LANES-1];  // 16 consecutive successful iterations counter
    reg [15:0]  aggregate_error_counter;
    integer k;
    always @(posedge i_clk or negedge i_rst_n) begin
        reg [4:0] temp_ctr;
        if (!i_rst_n) begin
            state                     <= S_IDLE;
            iter_ctr                  <= 16'd0;
            o_done                    <= 1'b0;
            o_per_lane_pass           <= '0;
            aggregate_error_counter <= 16'd0;
            o_aggregate_error          <= 1'b0;
            for (k = 0; k < NUM_LANES; k = k + 1) begin
                lane_err_accum[k]  <= 16'd0;
                consecutive_ctr[k] <= 5'd0;
            end
        end else if (i_clear_error) begin
            state                     <= S_IDLE;
            iter_ctr                  <= 16'd0;
            o_done                    <= 1'b0;
            aggregate_error_counter <= 16'd0;
            o_aggregate_error          <= 1'b0;
            for (k = 0; k < NUM_LANES; k = k + 1) begin
                lane_err_accum[k]  <= 16'd0;
                consecutive_ctr[k] <= 5'd0;
                if (i_lane_mask[k])
                    o_per_lane_pass[k] <= 1'b1;
                else if (i_pattern_mode)
                    o_per_lane_pass[k] <= 1'b0;
                else
                    o_per_lane_pass[k] <= 1'b1;
            end
        end else begin
            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    o_done <= 1'b0;
                    if (i_enable) begin
                        // Start a fresh test: clear all accumulators / results.
                        iter_ctr                  <= 16'd0;
                        aggregate_error_counter <= 16'd0;
                        o_aggregate_error          <= 1'b0;
                        for (k = 0; k < NUM_LANES; k = k + 1) begin
                            lane_err_accum[k]  <= 16'd0;
                            consecutive_ctr[k] <= 5'd0;
                            if (i_lane_mask[k])
                                o_per_lane_pass[k] <= 1'b1;
                            else if (i_pattern_mode)
                                o_per_lane_pass[k] <= 1'b0;
                            else
                                o_per_lane_pass[k] <= 1'b1;
                        end
                        state <= S_COMPARE;
                    end
                end

                // ---------------------------------------------------------
                S_COMPARE: begin
                    if (!i_enable) begin
                        state <= S_IDLE;            // aborted before completion
                    end else if (i_pcmp_enable) begin
                        // 1. Lane Pass / Mismatch calculation
                        if (i_pattern_mode == 1'b1) begin
                            // ---- Per-lane ID pattern mode (16 consecutive successful iterations) ----
                            for (k = 0; k < NUM_LANES; k = k + 1) begin
                                if (i_lane_mask[k]) begin
                                    consecutive_ctr[k] <= 5'd0;
                                    o_per_lane_pass[k] <= 1'b1;
                                end else if (o_per_lane_pass[k]) begin
                                    consecutive_ctr[k] <= consecutive_ctr[k];
                                    o_per_lane_pass[k] <= 1'b1;
                                end else begin
                                    temp_ctr = consecutive_ctr[k];
                                    
                                    // Check iteration 1 (bits 15:0)
                                    if (mismatch_masked[k][15:0] == 16'd0) begin
                                        if (temp_ctr < 5'd16) temp_ctr = temp_ctr + 5'd1;
                                    end else begin
                                        temp_ctr = 5'd0;
                                    end
                                    
                                    // Check iteration 2 (bits 31:16)
                                    if (mismatch_masked[k][31:16] == 16'd0) begin
                                        if (temp_ctr < 5'd16) temp_ctr = temp_ctr + 5'd1;
                                    end else begin
                                        temp_ctr = 5'd0;
                                    end
                                    
                                    consecutive_ctr[k] <= temp_ctr;
                                    if (temp_ctr >= 5'd16) begin
                                        o_per_lane_pass[k] <= 1'b1;
                                    end
                                end
                            end
                        end else begin
                            // ---- LFSR mode ----
                            for (k = 0; k < NUM_LANES; k = k + 1) begin
                                if (i_lane_mask[k]) begin
                                    lane_err_accum[k]  <= 16'd0;
                                    o_per_lane_pass[k] <= 1'b1;
                                end else begin
                                    lane_err_accum[k] <= lane_err_accum[k] + lane_inc[k];
                                    // Sticky FAIL once accumulated errors exceed the threshold.
                                    if ((lane_err_accum[k] + lane_inc[k]) > i_max_error_threshold_per_lane)
                                        o_per_lane_pass[k] <= 1'b0;
                                end
                            end
                        end

                        // 2. Aggregate comparison
                        if (i_comparison_mode == 1'b1) begin
                            // ---- Aggregate comparison ----
                            // OR Lanes per UI, count error UIs, saturate at 16'hFFFF.
                            if (aggregate_error_counter > (16'hFFFF - agg_inc))
                                aggregate_error_counter <= 16'hFFFF;
                            else
                                aggregate_error_counter <= aggregate_error_counter + agg_inc;
                        end

                        // 3. Counter and state transitions
                        if (iter_ctr == i_iteration_count - 1)
                            state <= S_DONE;
                        else
                            iter_ctr <= iter_ctr + 16'd1;
                    end
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    o_done <= 1'b1;
                    // Aggregate result: Pass if error count is within threshold.
                    o_aggregate_error <= (aggregate_error_counter > i_max_error_threshold_aggregate);
                    if (!i_enable)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
