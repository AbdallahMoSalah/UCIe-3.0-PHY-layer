`timescale 1ns/1ps

module VALID_RX_TB;

    // =====================================================
    // Signals
    // =====================================================
    reg         i_clk;
    reg         i_rst_n;
    reg [31:0]  RVLD_L;
    reg [11:0]  i_max_error_threshold;
    reg         i_enable_cons;
    reg         i_enable_128;
    reg         i_enable_detector;

    wire        detection_result;
    wire        o_valid_frame_detect;

    // =====================================================
    // DUT Instantiation
    // =====================================================
    VALID_DETECTOR DUT (
        .i_clk                    (i_clk),
        .i_rst_n                  (i_rst_n),
        .RVLD_L                   (RVLD_L),
        .i_max_error_threshold    (i_max_error_threshold),
        .i_enable_cons            (i_enable_cons),
        .i_enable_128             (i_enable_128),
        .i_enable_detector        (i_enable_detector),
        .detection_result         (detection_result),
        .o_valid_frame_detect     (o_valid_frame_detect)
    );

    // =====================================================
    // Clock Generation
    // =====================================================
    initial i_clk = 0;
    always #5 i_clk = ~i_clk; // 100MHz

    // =====================================================
    // Test Sequence
    // =====================================================
    initial begin
        // Reset
        i_rst_n               = 0;
        RVLD_L                = 32'd0;
        i_max_error_threshold = 12'd10;
        i_enable_cons         = 0;
        i_enable_128          = 0;
        i_enable_detector     = 0;
        repeat(4) @(posedge i_clk);
        i_rst_n = 1;
        @(posedge i_clk);

        // Enable detector
        i_enable_detector = 1;

        // --------------------------------------------------
        // PHASE 1: CONSECUTIVE_16
        // --------------------------------------------------
        $display("\n[%0t] >> PHASE 1: CONSECUTIVE_16 Phase Start", $time);
        i_enable_cons = 1;
        i_enable_128  = 0;
        
        // Feed valid patterns to pass the 16 bytes requirement
        repeat (5) begin
            RVLD_L = 32'hF0F0F0F0;
            @(posedge i_clk);
        end

        // --------------------------------------------------
        // IDLE between phases to reset counters
        // --------------------------------------------------
        $display("\n[%0t] >> IDLE Phase to clear counters", $time);
        i_enable_cons = 0;
        i_enable_128  = 0;
        @(posedge i_clk);

        // --------------------------------------------------
        // PHASE 2.A: ITERATIONS_128 (Clean block)
        // --------------------------------------------------
        $display("\n[%0t] >> PHASE 2.A: ITERATIONS_128 (Clean block)", $time);
        i_enable_cons = 0;
        i_enable_128  = 1;
        repeat (128) begin
            RVLD_L = 32'hF0F0F0F0;
            @(posedge i_clk);
        end

        // --------------------------------------------------
        // PHASE 2.B: ITERATIONS_128 (Errors under threshold)
        // --------------------------------------------------
        $display("\n[%0t] >> PHASE 2.B: ITERATIONS_128 (Errors under threshold)", $time);
        // Inject 5 errors (1 bit mismatch per cycle for 5 cycles)
        repeat (5) begin
            RVLD_L = 32'hF0F0F0F1; // 1 bit error
            @(posedge i_clk);
        end
        // Rest of the block clean (128 - 5 = 123 cycles)
        repeat (123) begin
            RVLD_L = 32'hF0F0F0F0;
            @(posedge i_clk);
        end

        // --------------------------------------------------
        // PHASE 2.C: ITERATIONS_128 (Errors exceed threshold)
        // --------------------------------------------------
        $display("\n[%0t] >> PHASE 2.C: ITERATIONS_128 (Errors exceed threshold)", $time);
        // Inject a huge error to cross the threshold of 10 instantly
        RVLD_L = 32'hFFFFFFFF; // 32 errors in one cycle
        @(posedge i_clk);
        
        // Return to normal, but it should have failed already
        repeat(10) begin
            RVLD_L = 32'hF0F0F0F0;
            @(posedge i_clk);
        end

        // Stop
        i_enable_detector = 0;
        i_enable_cons     = 0;
        i_enable_128      = 0;
        RVLD_L            = 32'h0;
        repeat(5) @(posedge i_clk);

        $display("\n[%0t] >> All tests done!", $time);
        $stop;
    end

    // =====================================================
    // Monitor
    // =====================================================
    reg prev_detection_result;
    reg prev_valid_frame_detect;

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            prev_detection_result   <= 1;
            prev_valid_frame_detect <= 0;
        end else begin
            prev_detection_result   <= detection_result;
            prev_valid_frame_detect <= o_valid_frame_detect;
        end
    end
    
    always @(posedge i_clk) begin
        if (i_enable_detector) begin
            
            // Consecutive Phase Success
            if (i_enable_cons && detection_result && !prev_detection_result)
                $display("[%0t] ---> Consecutive Test PASSED (Reached >= 16 bytes)", $time);
            
            // Iteration Phase - Block completion check (using hierarchical reference)
            if (i_enable_128 && (DUT.iteration_counter == 127)) begin
                if (detection_result == 1'b1)
                    $display("[%0t] ---> Iteration Block 128 PASSED (Errors: %0d <= %0d)", 
                             $time, DUT.error_count, i_max_error_threshold);
            end

            // Iteration Phase - Failure detection (immediate drop)
            if (i_enable_128 && !detection_result && prev_detection_result)
                $display("[%0t] ---> Iteration Test FAILED: Error threshold exceeded! (Errors: %0d > %0d)", 
                         $time, DUT.error_count, i_max_error_threshold);
        end

        // Detect frame errors (e.g., when injected errors match invalid frames)
        if (o_valid_frame_detect && !prev_valid_frame_detect)
            $display("[%0t] ---> Frame Error Detected! (Data mismatch with VALID_PATTERN)", $time);
    end

endmodule