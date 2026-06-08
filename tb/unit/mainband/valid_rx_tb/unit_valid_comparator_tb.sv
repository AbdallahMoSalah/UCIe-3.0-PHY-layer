`timescale 1ns/1ps

module unit_valid_comparator_tb;

    parameter WIDTH = 32;
    parameter TOTAL_BYTES = 128;
    parameter CONSEC_PASS = 16;
    parameter [7:0] VALID_BYTE = 8'b00001111;

    // Inputs
    reg              i_clk;
    reg              i_rst_n;
    reg              i_enable;
    reg              i_mode;
    reg [15:0]       i_max_error_threshold;
    reg              i_clear_error;
    reg [WIDTH-1:0]  i_valid_frame_data;
    reg              i_valid_frame_vld;

    // Outputs
    wire             o_done;
    wire             o_pass;

    // Instantiate DUT
    unit_valid_comparator #(
        .WIDTH(WIDTH),
        .TOTAL_BYTES(TOTAL_BYTES),
        .CONSEC_PASS(CONSEC_PASS),
        .VALID_BYTE(VALID_BYTE)
    ) DUT (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_enable(i_enable),
        .i_mode(i_mode),
        .i_max_error_threshold(i_max_error_threshold),
        .i_clear_error(i_clear_error),
        .i_valid_frame_data(i_valid_frame_data),
        .i_valid_frame_vld(i_valid_frame_vld),
        .o_done(o_done),
        .o_pass(o_pass)
    );

    // Clock Generation: 100MHz (10ns period)
    always #5 i_clk = ~i_clk;

    integer iter;

    initial begin
        // Initialize inputs
        i_clk = 0;
        i_rst_n = 0;
        i_enable = 0;
        i_mode = 0;
        i_max_error_threshold = 0;
        i_clear_error = 0;
        i_valid_frame_data = 0;
        i_valid_frame_vld = 0;

        // Reset Asserted
        #20;
        i_rst_n = 1;
        #20;

        // =====================================================================
        // TEST 1: Mode 0 (Consecutive Match) - Gated Valid
        // Expected behavior: Matches only count when i_valid_frame_vld is high.
        // Needs 16 consecutive matching bytes (4 cycles of 32-bit words).
        // =====================================================================
        $display("[%0t] ==== TEST 1: Mode 0 (Consecutive Match) - Gated Valid ====", $time);
        i_mode = 1'b0;
        i_enable = 1;
        i_valid_frame_data = 32'h0F0F0F0F; // Expected matching word

        // Transitions to S_COMPARE
        i_valid_frame_vld = 1'b1;
        @(posedge i_clk);
        #1;

        // 1st valid cycle (compared here)
        @(posedge i_clk);
        #1;
        $display("[%0t] Cycle 1 (vld=1): consecutive_ctr = %d, o_pass = %b", $time, DUT.consecutive_ctr, o_pass);
        if (DUT.consecutive_ctr !== 5'd4) begin
            $display("ERROR: consecutive_ctr mismatch at cycle 1!");
            $stop;
        end

        // Gated cycle: vld=0, should be ignored
        i_valid_frame_vld = 1'b0;
        @(posedge i_clk);
        #1;
        $display("[%0t] Cycle 2 (vld=0): consecutive_ctr = %d, o_pass = %b", $time, DUT.consecutive_ctr, o_pass);
        if (DUT.consecutive_ctr !== 5'd4) begin
            $display("ERROR: consecutive_ctr changed during gated cycle!");
            $stop;
        end

        // 2nd valid cycle
        i_valid_frame_vld = 1'b1;
        @(posedge i_clk);
        #1;
        $display("[%0t] Cycle 3 (vld=1): consecutive_ctr = %d, o_pass = %b", $time, DUT.consecutive_ctr, o_pass);
        if (DUT.consecutive_ctr !== 5'd8) begin
            $display("ERROR: consecutive_ctr mismatch at cycle 3!");
            $stop;
        end

        // Gated cycle again
        i_valid_frame_vld = 1'b0;
        @(posedge i_clk);
        #1;

        // 3rd valid cycle
        i_valid_frame_vld = 1'b1;
        @(posedge i_clk);
        #1;
        if (DUT.consecutive_ctr !== 5'd12) begin
            $display("ERROR: consecutive_ctr mismatch at cycle 5!");
            $stop;
        end

        // 4th valid cycle -> should reach 16 consecutive bytes and PASS
        i_valid_frame_vld = 1'b1;
        @(posedge i_clk);
        #1;
        $display("[%0t] Cycle 6 (vld=1): consecutive_ctr = %d, o_pass = %b", $time, DUT.consecutive_ctr, o_pass);
        if (o_pass !== 1'b1) begin
            $display("ERROR: o_pass should be asserted after 16 consecutive matching bytes!");
            $stop;
        end

        // Finish the test (needs total of 32 cycles of valid frames to complete)
        i_valid_frame_vld = 1'b1;
        for (iter = 4; iter < 32; iter = iter + 1) begin
            @(posedge i_clk);
        end
        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        i_valid_frame_vld = 0;
        #50;

        // =====================================================================
        // TEST 2: Mode 1 (Bit Error Threshold) - Gated Valid
        // Expected behavior: Error accumulation occurs only when i_valid_frame_vld is high.
        // We will inject errors during vld=1 and vld=0, and verify threshold PASS.
        // =====================================================================
        $display("[%0t] ==== TEST 2: Mode 1 (Bit Error Threshold) - Gated Valid ====", $time);
        i_clear_error = 1;
        @(posedge i_clk);
        i_clear_error = 0;
        @(posedge i_clk);

        i_mode = 1'b1;
        i_max_error_threshold = 16'd10; // Allow up to 10 errors
        i_enable = 1;

        // Transitions to S_COMPARE
        i_valid_frame_vld = 1'b1;
        i_valid_frame_data = 32'h0F0F0F0F ^ 32'h0000003F; // 6 bits flipped
        @(posedge i_clk);
        #1;

        // 1st valid cycle (compared here)
        @(posedge i_clk);
        #1;
        $display("[%0t] Valid cycle: err_accum = %d (expected 6)", $time, DUT.err_accum);
        if (DUT.err_accum !== 16'd6) begin
            $display("ERROR: err_accum mismatch!");
            $stop;
        end

        // 2. Inject 8 errors on a gated cycle (vld=0)
        i_valid_frame_vld = 1'b0;
        i_valid_frame_data = 32'h0F0F0F0F ^ 32'h000000FF; // 8 bits flipped
        @(posedge i_clk);
        #1;
        $display("[%0t] Gated cycle (vld=0): err_accum = %d (expected 6)", $time, DUT.err_accum);
        if (DUT.err_accum !== 16'd6) begin
            $display("ERROR: err_accum changed on gated cycle!");
            $stop;
        end

        // 3. Inject 4 errors on a valid cycle (total valid errors = 10)
        i_valid_frame_vld = 1'b1;
        i_valid_frame_data = 32'h0F0F0F0F ^ 32'h0000000F; // 4 bits flipped
        @(posedge i_clk);
        #1;
        $display("[%0t] Valid cycle: err_accum = %d (expected 10)", $time, DUT.err_accum);

        // 4. Drive perfect matching data for remaining 30 valid cycles
        i_valid_frame_data = 32'h0F0F0F0F;
        i_valid_frame_vld = 1'b1;
        for (iter = 2; iter < 32; iter = iter + 1) begin
            @(posedge i_clk);
        end
        wait(o_done);
        #1;
        $display("[%0t] Test complete: o_done = %b, o_pass = %b (expected pass=1)", $time, o_done, o_pass);
        if (o_pass !== 1'b1) begin
            $display("ERROR: Test should have passed!");
            $stop;
        end

        i_enable = 0;
        i_valid_frame_vld = 0;
        #50;

        // =====================================================================
        // TEST 3: Mode 0 (Consecutive Match) - Continuous Valid
        // Expected behavior: vld is held high continuously, matches evaluated every cycle.
        // =====================================================================
        $display("[%0t] ==== TEST 3: Mode 0 (Consecutive Match) - Continuous Valid ====", $time);
        i_clear_error = 1;
        @(posedge i_clk);
        i_clear_error = 0;
        @(posedge i_clk);

        i_mode = 1'b0;
        i_enable = 1;
        i_valid_frame_vld = 1'b1; // Held high
        i_valid_frame_data = 32'h0F0F0F0F; // Matching word

        // Transitions to S_COMPARE
        @(posedge i_clk);
        #1;

        // 4 cycles = 16 bytes. Check at 4th cycle.
        @(posedge i_clk); // Cycle 1 (4 bytes)
        @(posedge i_clk); // Cycle 2 (8 bytes)
        @(posedge i_clk); // Cycle 3 (12 bytes)
        @(posedge i_clk); // Cycle 4 (16 bytes)
        #1;
        $display("[%0t] Cycle 4: consecutive_ctr = %d, o_pass = %b (expected pass=1)", $time, DUT.consecutive_ctr, o_pass);
        if (o_pass !== 1'b1) begin
            $display("ERROR: o_pass should be asserted after 4 consecutive cycles of matching data!");
            $stop;
        end

        // Run remaining cycles to finish test
        for (iter = 4; iter < 32; iter = iter + 1) begin
            @(posedge i_clk);
        end
        wait(o_done);
        @(posedge i_clk);
        i_enable = 0;
        i_valid_frame_vld = 0;
        #50;

        // =====================================================================
        // TEST 4: Mode 1 (Bit Error Threshold) - Continuous Valid
        // Expected behavior: vld is held high continuously, error threshold fails.
        // =====================================================================
        $display("[%0t] ==== TEST 4: Mode 1 (Bit Error Threshold) - Continuous Valid ====", $time);
        i_clear_error = 1;
        @(posedge i_clk);
        i_clear_error = 0;
        @(posedge i_clk);

        i_mode = 1'b1;
        i_max_error_threshold = 16'd10; // Threshold = 10
        i_enable = 1;
        i_valid_frame_vld = 1'b1; // Held high

        // Transitions to S_COMPARE
        @(posedge i_clk);
        #1;

        // Inject 12 errors continuously over two cycles
        i_valid_frame_data = 32'h0F0F0F0F ^ 32'h0000003F; // 6 errors
        @(posedge i_clk); // Cycle 1
        i_valid_frame_data = 32'h0F0F0F0F ^ 32'h0000003F; // 6 errors
        @(posedge i_clk); // Cycle 2

        // Remaining 30 cycles clean
        i_valid_frame_data = 32'h0F0F0F0F;
        for (iter = 2; iter < 32; iter = iter + 1) begin
            @(posedge i_clk);
        end
        wait(o_done);
        #1;
        $display("[%0t] Test complete: o_done = %b, o_pass = %b (expected pass=0)", $time, o_done, o_pass);
        if (o_pass !== 1'b0) begin
            $display("ERROR: Test should have failed due to exceeding error threshold!");
            $stop;
        end

        i_enable = 0;
        i_valid_frame_vld = 0;
        #50;

        $display("\n[%0t] ==== ALL TESTS PASSED SUCCESSFULLY ====", $time);
        $finish;
    end

endmodule
