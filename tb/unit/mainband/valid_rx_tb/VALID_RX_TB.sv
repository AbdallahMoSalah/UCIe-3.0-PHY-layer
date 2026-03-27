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
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .RVLD_L(RVLD_L),
        .i_Valid_en(i_Valid_en),
        .i_max_error_threshold(i_max_error_threshold),
        .O_result_logged_iteration(O_result_logged_iteration),
        .O_result_logged_consecutive(O_result_logged_consecutive)
    );

    // =====================================================
    // Clock Generation
    // =====================================================
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk;   // 100MHz
    end

    // =====================================================
    // Test Sequence
    // =====================================================
    initial begin
        // Reset
        i_rst_n = 0;
        i_Valid_en = 0;
        RVLD_L = 32'd0;
        i_max_error_threshold = 12'd10;

        #20;
        i_rst_n = 1;

        // Start valid test
        #10;
        i_Valid_en = 1;

        // ---------------------------
        // Send 128 correct iterations
        // ---------------------------
        repeat (128) begin
            RVLD_L = 32'hF0F0F0F0;
            #10;
        end

        // ---------------------------
        // Send 16 consecutive bytes
        // 4 per cycle → 4 cycles = 16 bytes
        // ---------------------------
        repeat (4) begin
            RVLD_L = 32'hF0F0F0F0;
            #10;
        end

        // ---------------------------
        // Introduce an error frame
        // ---------------------------
        RVLD_L = 32'hF0F0F0F0; // 1 bit wrong
        #10;

        // Stop
        RVLD_L = 32'h00000000;
        #50;

        $stop;
    end

    // =====================================================
    // Monitor for iteration and consecutive results
    // =====================================================
    always @(posedge i_clk) begin
        if (O_result_logged_iteration) begin
            $display("[%0t] Iteration Test FAILED: too many bit errors", $time);
        end
        else if (O_result_logged_iteration === 1'b0 && i_Valid_en) begin
            $display("[%0t] Iteration Test PASSED", $time);
        end

        if (O_result_logged_consecutive) begin
            $display("[%0t] Consecutive Test PASSED (16 iterations detected)", $time);
        end
    end

endmodule