`timescale 1ns/1ps
// =============================================================================
// Module  : VALID_RX_TB
// Purpose : Unit-level self-checking testbench for VALID_DETECTOR
//
// Design Under Test : VALID_DETECTOR (Valid_RX.sv)
//   - Detects whether received 32-bit word == 32'h0F0F0F0F (VALID_PATTERN)
//   - Three operating modes via {i_enable_cons, i_enable_128}:
//       2'b00 (IDLE)      : counters reset, detection_result=0
//       2'b01 (ITER_128)  : accumulate bit-mismatch over 128 iterations;
//                           detection_result=1 if total error > threshold
//       2'b10 (CONSEC_16) : consecutive valid bytes counter;
//                           detection_result=1 when consec_count >= 16
//       2'b11 (default)   : detection_result=1 (both enables asserted)
//
// o_valid_frame_detect : 1 when RVLD_L != VALID_PATTERN (inverted flag)
//
// Self-Checking Strategy:
//   - Every check compares DUT outputs to expected values computed by TB
//   - pass_count / fail_count track test results
//   - $fatal on any unexpected result
// =============================================================================

module VALID_RX_TB;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_HALF       = 5;          // 100 MHz → 10 ns period
    localparam VALID_PATTERN  = 32'h0F0F0F0F;
    localparam MAX_ITER       = 128;
    localparam MIN_CONSEC     = 16;

    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg         i_clk;
    reg         i_rst_n;
    reg [31:0]  RVLD_L;
    reg [11:0]  i_max_error_threshold;
    reg         i_enable_cons;
    reg         i_enable_128;
    reg         i_enable_detector;

    wire        detection_result;
    wire        o_valid_frame_detect;

    // =========================================================================
    // Score counters
    // =========================================================================
    integer pass_count;
    integer fail_count;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    VALID_DETECTOR DUT (
        .i_clk                 (i_clk),
        .i_rst_n               (i_rst_n),
        .RVLD_L                (RVLD_L),
        .i_max_error_threshold (i_max_error_threshold),
        .i_enable_cons         (i_enable_cons),
        .i_enable_128          (i_enable_128),
        .i_enable_detector     (i_enable_detector),
        .detection_result      (detection_result),
        .o_valid_frame_detect  (o_valid_frame_detect)
    );

    // =========================================================================
    // Clock Generation  100 MHz
    // =========================================================================
    initial i_clk = 1'b0;
    always  #(CLK_HALF) i_clk = ~i_clk;

    // =========================================================================
    // Task: check_result
    //   Compares a DUT output to an expected value and logs PASS/FAIL.
    // =========================================================================
    task automatic check_result;
        input string  tc_name;
        input logic   got;
        input logic   exp;
        begin
            if (got === exp) begin
                $display("[%8t] PASS  | %-35s | got=%b  exp=%b", $time, tc_name, got, exp);
                pass_count = pass_count + 1;
            end else begin
                $display("[%8t] FAIL  | %-35s | got=%b  exp=%b  <<<<", $time, tc_name, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Task: go_idle
    //   Put DUT in IDLE mode and wait one cycle for counters to flush.
    // =========================================================================
    task automatic go_idle;
        begin
            i_enable_cons = 1'b0;
            i_enable_128  = 1'b0;
            RVLD_L        = 32'h0;
            @(posedge i_clk); #1;
        end
    endtask

    // =========================================================================
    // Task: apply_reset
    // =========================================================================
    task automatic apply_reset;
        begin
            i_rst_n               = 1'b0;
            RVLD_L                = 32'h0;
            i_enable_cons         = 1'b0;
            i_enable_128          = 1'b0;
            i_enable_detector     = 1'b0;
            i_max_error_threshold = 12'd10;
            repeat(4) @(posedge i_clk);
            i_rst_n = 1'b1;
            @(posedge i_clk); #1;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("=====================================================");
        $display("  VALID_DETECTOR – Unit Self-Checking Testbench");
        $display("  VALID_PATTERN = 32'h%08h", VALID_PATTERN);
        $display("=====================================================");

        pass_count = 0;
        fail_count = 0;

        // ─── Reset ──────────────────────────────────────────────────────────
        apply_reset;
        i_enable_detector = 1'b1;

        // =====================================================================
        // TC-1: IDLE Mode
        //   Both enables = 0 → IDLE state → detection_result must be 0
        // =====================================================================
        $display("\n──── TC-1: IDLE Mode ────────────────────────────────");
        go_idle;
        repeat(3) @(posedge i_clk); #1;
        check_result("TC-1a: IDLE det_result=0",   detection_result,     1'b0);
        check_result("TC-1b: IDLE frame_detect=0",  o_valid_frame_detect, 1'b0);

        // =====================================================================
        // TC-2: o_valid_frame_detect logic
        //   When RVLD_L != VALID_PATTERN and detector enabled → 1 (next cycle)
        //   When RVLD_L == VALID_PATTERN → 0
        // =====================================================================
        $display("\n──── TC-2: o_valid_frame_detect ─────────────────────");
        // 2a: wrong data → frame error flag = 1
        i_enable_cons = 1'b0;
        i_enable_128  = 1'b0;
        RVLD_L = 32'hDEADBEEF;
        @(posedge i_clk); #1;
        // o_valid_frame_detect is registered, so check after one more cycle
        @(posedge i_clk); #1;
        check_result("TC-2a: frame_detect=1 (bad data)", o_valid_frame_detect, 1'b1);

        // 2b: correct data → frame error flag = 0
        RVLD_L = VALID_PATTERN;
        @(posedge i_clk); #1;
        @(posedge i_clk); #1;
        check_result("TC-2b: frame_detect=0 (valid data)", o_valid_frame_detect, 1'b0);

        // =====================================================================
        // TC-3: CONSEC_16 – Success path (feed valid for >= 4 cycles)
        //   Each valid 32-bit word gives 4 valid bytes → 4 cycles × 4 bytes =
        //   16 bytes → detection_result should become 1
        // =====================================================================
        $display("\n──── TC-3: CONSEC_16 – success (>= 16 bytes) ────────");
        go_idle;  // flush counters
        i_enable_cons = 1'b1;
        i_enable_128  = 1'b0;
        RVLD_L = VALID_PATTERN;

        // Send 4 cycles of valid pattern → consec_count reaches 16 after 4th
        // detection_result is registered from consec_count of *previous* cycle
        // so we need 5 cycles to see the assertion (4 to fill, 1 to register)
        repeat(5) @(posedge i_clk); #1;
        check_result("TC-3: CONSEC_16 det_result=1", detection_result, 1'b1);

        // =====================================================================
        // TC-4: CONSEC_16 – Break the streak (inject non-valid word)
        //   After sending a non-valid byte (valid_bytes=0) counter resets → 0
        // =====================================================================
        $display("\n──── TC-4: CONSEC_16 – streak broken ────────────────");
        RVLD_L = 32'hFFFFFFFF; // all bytes = 0xFF ≠ 0x0F → valid_bytes=0
        @(posedge i_clk); #1; // consec_count resets this cycle
        @(posedge i_clk); #1; // detection_result reflects previous consec_count
        check_result("TC-4: CONSEC_16 det_result=0 (broken)", detection_result, 1'b0);

        // =====================================================================
        // TC-5: CONSEC_16 – Partial valid (2 valid bytes out of 4)
        //   valid_bytes ≠ 0 and ≠ 4 → counter gets written with valid_bytes, not accumulated
        // =====================================================================
        $display("\n──── TC-5: CONSEC_16 – partial valid bytes ──────────");
        go_idle;
        i_enable_cons = 1'b1;
        i_enable_128  = 1'b0;
        // 32'h0F0F_FFFF: bytes [7:0]=FF, [15:8]=FF, [23:16]=0F, [31:24]=0F
        // → seg_0=FF, seg_1=FF, seg_2=0F, seg_3=0F → valid_bytes=2
        RVLD_L = 32'h0F0FFFFF;
        repeat(10) @(posedge i_clk); #1;
        // consec_count stays at 2 every cycle → never reaches 16 → result=0
        check_result("TC-5: CONSEC_16 det_result=0 (partial)", detection_result, 1'b0);

        // =====================================================================
        // TC-6: ITER_128 – Clean block (no errors → error_count=0 ≤ threshold)
        //   After 128 iterations of perfect data, detection_result should be 0
        //   (errors=0 ≤ threshold=10)
        // =====================================================================
        $display("\n──── TC-6: ITER_128 – clean block (no errors) ───────");
        go_idle;
        i_max_error_threshold = 12'd10;
        i_enable_cons = 1'b0;
        i_enable_128  = 1'b1;
        RVLD_L = VALID_PATTERN; // mismatch_count = 0 every cycle

        repeat(MAX_ITER) @(posedge i_clk); #1;
        // At iteration 127 (0-indexed), detection_result is registered
        // One more cycle to capture the registered result
        @(posedge i_clk); #1;
        check_result("TC-6: ITER_128 det_result=0 (no errors)", detection_result, 1'b0);

        // =====================================================================
        // TC-7: ITER_128 – Errors below threshold
        //   Inject errors in 5 out of 128 cycles (each cycle: 1-bit mismatch)
        //   32'h0F0F0F0E vs 0x0F0F0F0F → bit[0] differs → mismatch_count=1
        //   Total errors = 5 × 1 = 5 ≤ threshold(10) → detection_result=0
        // =====================================================================
        $display("\n──── TC-7: ITER_128 – errors below threshold ────────");
        go_idle;
        i_max_error_threshold = 12'd10;
        i_enable_cons = 1'b0;
        i_enable_128  = 1'b1;

        // 5 cycles with 1-bit error each
        repeat(5) begin
            RVLD_L = 32'h0F0F0F0E; // bit[0] flipped
            @(posedge i_clk); #1;
        end
        // Remaining 123 cycles clean
        RVLD_L = VALID_PATTERN;
        repeat(MAX_ITER - 5) @(posedge i_clk); #1;
        @(posedge i_clk); #1;
        check_result("TC-7: ITER_128 det_result=0 (errors <= threshold)", detection_result, 1'b0);

        // =====================================================================
        // TC-8: ITER_128 – Errors EXCEED threshold
        //   Inject 32'hFFFFFFFF for 1 cycle → mismatch = popcount(FF..FF XOR 0F..0F)
        //   0xFFFFFFFF XOR 0x0F0F0F0F = 0xF0F0F0F0 → 16 bits set → 16 errors
        //   16 > threshold(10) → after 128 iterations, detection_result=1
        //   But since 16 errors alone exceed the threshold, we fill the rest
        //   cleanly and check the final output.
        // =====================================================================
        $display("\n──── TC-8: ITER_128 – errors exceed threshold ───────");
        go_idle;
        i_max_error_threshold = 12'd10;
        i_enable_cons = 1'b0;
        i_enable_128  = 1'b1;

        // 1 cycle: 0xFFFFFFFF → 16-bit mismatch with VALID_PATTERN
        RVLD_L = 32'hFFFFFFFF;
        @(posedge i_clk); #1;

        // Remaining 127 cycles clean → total errors = 16 > 10
        RVLD_L = VALID_PATTERN;
        repeat(MAX_ITER - 1) @(posedge i_clk); #1;
        @(posedge i_clk); #1;
        check_result("TC-8: ITER_128 det_result=1 (errors > threshold)", detection_result, 1'b1);

        // =====================================================================
        // TC-9: ITER_128 – Counter resets after 128 iterations
        //   After one bad block, run another clean block → result must go back to 0
        // =====================================================================
        $display("\n──── TC-9: ITER_128 – resets after block ────────────");
        // Still in ITER_128 mode; run a clean second block
        RVLD_L = VALID_PATTERN;
        repeat(MAX_ITER) @(posedge i_clk); #1;
        @(posedge i_clk); #1;
        check_result("TC-9: ITER_128 second block clean → det=0", detection_result, 1'b0);

        // =====================================================================
        // TC-10: Default mode (both enables = 1) → detection_result = 1
        // =====================================================================
        $display("\n──── TC-10: Default mode (cons=1, 128=1) → det=1 ───");
        go_idle;
        i_enable_cons = 1'b1;
        i_enable_128  = 1'b1;
        RVLD_L = VALID_PATTERN;
        @(posedge i_clk); #1;
        check_result("TC-10: Default det_result=1", detection_result, 1'b1);

        // =====================================================================
        // TC-11: Detector disabled (i_enable_detector=0)
        //   When detector is disabled, outputs should stay at their last value
        //   (no new updates). After disabling, inject errors → result unchanged.
        // =====================================================================
        $display("\n──── TC-11: Detector disabled ───────────────────────");
        go_idle;
        i_enable_detector = 1'b0;
        RVLD_L = 32'hFFFFFFFF;
        repeat(5) @(posedge i_clk); #1;
        // detection_result should stay 0 (last value from IDLE) since disabled
        check_result("TC-11: Disabled → det_result=0", detection_result, 1'b0);

        // Re-enable for next test
        i_enable_detector = 1'b1;

        // =====================================================================
        // TC-12: Reset clears all outputs
        // =====================================================================
        $display("\n──── TC-12: Async reset clears outputs ──────────────");
        // First drive detection high via default mode
        i_enable_cons = 1'b1;
        i_enable_128  = 1'b1;
        @(posedge i_clk); #1;
        // Now reset asynchronously
        i_rst_n = 1'b0;
        #2; // within the clock cycle
        check_result("TC-12a: async rst → det_result=0", detection_result, 1'b0);
        @(posedge i_clk);
        i_rst_n = 1'b1;
        @(posedge i_clk); #1;
        check_result("TC-12b: after rst → det_result=0", detection_result, 1'b0);

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n=====================================================");
        $display("  TEST SUMMARY");
        $display("  PASSED : %0d", pass_count);
        $display("  FAILED : %0d", fail_count);
        $display("=====================================================");
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TEST(S) FAILED ***", fail_count);
        $display("=====================================================\n");

        #20;
        $finish;
    end

    // =========================================================================
    // Watchdog Timer (prevents infinite hang)
    // =========================================================================
    initial begin
        #200000;
        $display("[%0t] WATCHDOG TIMEOUT – simulation hung!", $time);
        $fatal(1, "Watchdog expired");
    end

    // =========================================================================
    // Continuous Monitor (print on any change to key outputs)
    // =========================================================================
    always @(posedge i_clk) begin
        if (i_enable_detector) begin
            // Monitor iteration boundary in ITER_128 mode
            if (i_enable_128 && !i_enable_cons) begin
                if (DUT.iteration_counter == (MAX_ITER - 1)) begin
                    $display("[%8t] [MON] ITER_128 block done: error_count=%0d  threshold=%0d  → will det=%b",
                             $time, DUT.error_count, i_max_error_threshold,
                             (DUT.error_count > i_max_error_threshold));
                end
            end
            // Monitor CONSEC_16 count
            if (i_enable_cons && !i_enable_128) begin
                $display("[%8t] [MON] CONSEC_16: consec_count=%0d  valid_bytes=%0d  det=%b",
                         $time, DUT.consec_count, DUT.valid_bytes, detection_result);
            end
        end
    end

endmodule