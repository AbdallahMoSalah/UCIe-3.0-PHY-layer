`timescale 1ns/1ps

module VALID_RX_TB;

    // =====================================================
    // Signals
    // =====================================================
    reg         i_clk;
    reg         i_rst_n;
    reg [31:0]  RVLD_L;
    reg         i_Valid_en;
    reg [11:0]  i_max_error_threshold;

    wire        O_result_logged_iteration;
    wire        O_result_logged_consecutive;

    // =====================================================
    // DUT Instantiation
    // =====================================================
    VALID_DETECTOR DUT (
        .i_clk                    (i_clk),
        .i_rst_n                  (i_rst_n),
        .RVLD_L                   (RVLD_L),
        .i_Valid_en               (i_Valid_en),
        .i_max_error_threshold    (i_max_error_threshold),
        .O_result_logged_iteration   (O_result_logged_iteration),
        .O_result_logged_consecutive (O_result_logged_consecutive)
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
        i_Valid_en            = 0;
        RVLD_L                = 32'd0;
        i_max_error_threshold = 12'd10;
        repeat(4) @(posedge i_clk);
        i_rst_n = 1;
        @(posedge i_clk);

        // Enable
        i_Valid_en = 1;

        // --------------------------------------------------
        // PHASE 1: CONSECUTIVE_16
        // محتاج 16 byte صح = 4 cycles (كل cycle = 4 bytes)
        // --------------------------------------------------
        $display("[%0t] >> CONSECUTIVE_16 Phase Start", $time);
        repeat (4) begin
            RVLD_L = 32'hF0F0F0F0;
            @(posedge i_clk);
        end

        // --------------------------------------------------
        // PHASE 2: ITERATIONS_128
        // محتاج 128 iteration صح
        // --------------------------------------------------
        $display("[%0t] >> ITERATIONS_128 Phase Start", $time);
        repeat (128) begin
            RVLD_L = 32'hF0F0F0F0;
            @(posedge i_clk);
        end

        // --------------------------------------------------
        // Test error frame في ITERATIONS_128
        // --------------------------------------------------
        $display("[%0t] >> Injecting error frame", $time);
        RVLD_L = 32'hF0F0F0F1; // bit error
        @(posedge i_clk);

        // Stop
        i_Valid_en = 0;
        RVLD_L     = 32'h0;
        repeat(10) @(posedge i_clk);

        $display("[%0t] >> All tests done!", $time);
        $stop;
    end

    // =====================================================
    // Monitor
    // =====================================================
    always @(posedge i_clk) begin

        if (O_result_logged_consecutive)
            $display("[%0t] Consecutive Test PASSED", $time);

        if (O_result_logged_iteration === 1'b1)
            $display("[%0t] Iteration Test FAILED: too many errors", $time);
        else if (O_result_logged_iteration === 1'b0 && i_Valid_en)
            $display("[%0t] Iteration Test PASSED", $time);
    end

endmodule