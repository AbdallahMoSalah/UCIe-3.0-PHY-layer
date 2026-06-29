`timescale 1ns/1ps

module unit_valid_tx_tb;

    // Inputs
    reg        i_clk;
    reg        i_rst_n;
    reg        valid_pattern_en;
    reg        ser_en_lfsr_i;

    // Outputs
    wire       ser_en_o;
    wire       O_done;
    wire [31:0] o_TVLD_L;

    // Instantiate the Unit Under Test (UUT)
    unit_valid_tx uut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .valid_pattern_en(valid_pattern_en),
        .ser_en_lfsr_i(ser_en_lfsr_i),
        .ser_en_o(ser_en_o),
        .O_done(O_done),
        .o_TVLD_L(o_TVLD_L)
    );

    // Clock generation (100MHz / 10ns period)
    always #5 i_clk = ~i_clk;

    initial begin
        // Initialize Inputs
        i_clk = 0;
        i_rst_n = 0;
        valid_pattern_en = 0;
        ser_en_lfsr_i = 0;

        // Wait 100 ns for global reset to finish
        #100;
        @(posedge i_clk);
        #1;
        i_rst_n = 1;
        
        $display("[TB] Reset released.");

        // ==========================================
        // Test 1: VALID_FRAME state default behavior
        // ==========================================
        $display("[TB] Test 1: Testing VALID_FRAME behavior...");
        
        // In VALID_FRAME state, ser_en_o should track ser_en_lfsr_i
        ser_en_lfsr_i = 1'b0;
        @(posedge i_clk);
        #1;
        if (ser_en_o !== 1'b0) begin
            $display("[ERROR] Test 1 failed: ser_en_o is %b, expected 0", ser_en_o);
            $finish;
        end

        ser_en_lfsr_i = 1'b1;
        @(posedge i_clk);
        #1;
        if (ser_en_o !== 1'b1) begin
            $display("[ERROR] Test 1 failed: ser_en_o is %b, expected 1", ser_en_o);
            $finish;
        end

        ser_en_lfsr_i = 1'b0;
        @(posedge i_clk);
        #1;
        
        // Check static o_TVLD_L value
        if (o_TVLD_L !== 32'h0F0F0F0F) begin
            $display("[ERROR] Test 1 failed: o_TVLD_L is %h, expected 32'h0F0F0F0F", o_TVLD_L);
            $finish;
        end

        $display("[TB] Test 1 passed.");

        valid_pattern_en = 1'b1;
        @(posedge i_clk);
        #1;
        // Now current_state has transitioned to VALID_PATTERN.
        // Since output logic is combinational (always_comb), ser_en_o is 1 and O_done is 0 immediately.

        // The counter starts at 0 and counts up to 31 (32 cycles total where ser_en_o is 1)
        for (int i = 0; i < 32; i = i + 1) begin
            if (ser_en_o !== 1'b1) begin
                $display("[ERROR] Test 2 failed at cycle %0d: ser_en_o is %b, expected 1", i, ser_en_o);
                $finish;
            end
            if (O_done !== 1'b0) begin
                $display("[ERROR] Test 2 failed at cycle %0d: O_done is %b, expected 0", i, O_done);
                $finish;
            end
            @(posedge i_clk);
            #1;
        end

        // At counter = 32, O_done should pulse to 1 and ser_en_o should drop to 0
        if (O_done !== 1'b1) begin
            $display("[ERROR] Test 2 failed: O_done is %b at cycle 32, expected 1", O_done);
            $finish;
        end
        if (ser_en_o !== 1'b0) begin
            $display("[ERROR] Test 2 failed: ser_en_o is %b at cycle 32, expected 0", ser_en_o);
            $finish;
        end

        $display("[TB] Test 2 passed.");

        // ==========================================
        // Test 3: Returning to VALID_FRAME
        // ==========================================
        $display("[TB] Test 3: Testing transition back to VALID_FRAME...");
        repeat(5) @(posedge i_clk);
        valid_pattern_en = 1'b0;
        @(posedge i_clk);
        #1;
        
        // We should be back in VALID_FRAME. Verify ser_en_o tracks ser_en_lfsr_i again.
        ser_en_lfsr_i = 1'b1;
        @(posedge i_clk);
        #1;
        if (ser_en_o !== 1'b1) begin
            $display("[ERROR] Test 3 failed: ser_en_o is %b, expected 1", ser_en_o);
            $finish;
        end

        ser_en_lfsr_i = 1'b0;
        @(posedge i_clk);
        #1;
        if (ser_en_o !== 1'b0) begin
            $display("[ERROR] Test 3 failed: ser_en_o is %b, expected 0", ser_en_o);
            $finish;
        end

        $display("[TB] Test 3 passed.");
        $display("[TB] All tests completed successfully!");
        $stop;
    end

endmodule
