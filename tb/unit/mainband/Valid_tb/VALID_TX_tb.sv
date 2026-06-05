`timescale 1ns/1ps

module VALID_TX_tb;

    // ============================================================
    // DUT Signals
    // ============================================================
    reg         i_clk;
    reg         i_rst_n;
    reg         valid_pattern_en;
    reg         valid_frame_en;

    wire        O_done;
    wire [31:0] o_TVLD_L;
    wire        ser_en_o;

    // ============================================================
    // Instantiate DUT
    // ============================================================
    VALID_TX DUT (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .valid_pattern_en(valid_pattern_en),
        .valid_frame_en(valid_frame_en),
        .O_done(O_done),
        .o_TVLD_L(o_TVLD_L),
        .ser_en_o(ser_en_o)
    );

    // ============================================================
    // Clock Generation (100 MHz -> 10ns period)
    // ============================================================
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk;
    end

    // ============================================================
    // Test Sequence
    // ============================================================
    initial begin

        // Initialize
        i_rst_n          = 0;
        valid_pattern_en = 0;
        valid_frame_en   = 0;

        // Reset
        #20;
        i_rst_n = 1;

        // =====================================================
        // Test 1: VALID_PATTERN Mode (exactly 32 cycles)
        // =====================================================
        $display("---- Test VALID_PATTERN ----");

        @(posedge i_clk);
        valid_pattern_en = 1;

        @(posedge i_clk);
        valid_pattern_en = 0 ;

        // Assertions during pattern transmission:
        // First 31 cycles: TVLD = 32'hf0f0f0f0, Done = 0, ser_en = 1.
        repeat (31) begin
            @(posedge i_clk);
            #1; // small delay after clock edge to sample stable outputs
            assert(o_TVLD_L === 32'hf0f0f0f0) else $fatal("ERROR: TVLD mismatch during pattern! Expected 32'hf0f0f0f0, Got %h", o_TVLD_L);
            assert(O_done === 1'b0) else $fatal("ERROR: O_done should be 0 during pattern!");
            assert(ser_en_o === 1'b0) else $fatal("ERROR: ser_en_o should be 1 during pattern!");
        end

        // 32nd cycle (completion): O_done = 1, ser_en_o = 0, TVLD = 32'hf0f0f0f0
        @(posedge i_clk);
        #1;
        assert(o_TVLD_L === 32'hf0f0f0f0) else $fatal("ERROR: TVLD mismatch on final pattern cycle!");
        assert(O_done === 1'b1) else $fatal("ERROR: O_done should be 1 on completion cycle!");
        assert(ser_en_o === 1'b1) else $fatal("ERROR: ser_en_o should be 0 on completion cycle!");

        // 33rd cycle (transition to IDLE): FSM is IDLE, but registered outputs still show VALID_PATTERN
        @(posedge i_clk);
        #1;
        assert(o_TVLD_L === 32'hf0f0f0f0) else $fatal("ERROR: TVLD mismatch during transition to IDLE!");
        assert(O_done === 1'b1) else $fatal("ERROR: O_done should still be 1 during transition to IDLE!");
        assert(ser_en_o === 1'b1) else $fatal("ERROR: ser_en_o should still be 0 during transition to IDLE!");

        // Set valid_frame_en = 1 for the next test
        valid_frame_en = 1;

        // 34th cycle (IDLE outputs): FSM goes to VALID_FRAME, but registered outputs show IDLE
        @(posedge i_clk);
        #1;
        assert(o_TVLD_L === 32'b0) else $fatal("ERROR: TVLD should be 0 during IDLE cycle!");
        assert(O_done === 1'b0) else $fatal("ERROR: O_done should be 0 during IDLE cycle!");
        assert(ser_en_o === 1'b0) else $fatal("ERROR: ser_en_o should be 0 during IDLE cycle!");
        $display("VALID_PATTERN Test: PASSED");

        // =====================================================
        // Test 2: VALID_FRAME Mode (continuous)
        // =====================================================
        $display("---- Test VALID_FRAME ----");

        // First cycle of VALID_FRAME outputs
        @(posedge i_clk);
        #1;

        repeat (10) begin
            assert(o_TVLD_L === 32'hf0f0f0f0) else $fatal("ERROR: TVLD mismatch during frame!");
            assert(O_done === 1'b0) else $fatal("ERROR: O_done should be 0 during frame!");
            assert(ser_en_o === 1'b1) else $fatal("ERROR: ser_en_o should be 1 during frame!");
            @(posedge i_clk);
            #1;
        end

        valid_frame_en = 0;

        // Next cycle (FSM goes to IDLE, but outputs are still VALID_FRAME)
        @(posedge i_clk);
        #1;
        assert(o_TVLD_L === 32'hf0f0f0f0) else $fatal("ERROR: TVLD mismatch during frame disable transition!");
        assert(O_done === 1'b0) else $fatal("ERROR: O_done should be 0 during frame disable transition!");
        assert(ser_en_o === 1'b1) else $fatal("ERROR: ser_en_o should be 1 during frame disable transition!");

        // Next-next cycle: should transition back to IDLE outputs
        @(posedge i_clk);
        #1;
        assert(o_TVLD_L === 32'b0) else $fatal("ERROR: TVLD should be 0 after frame disable!");
        assert(O_done === 1'b0) else $fatal("ERROR: O_done should be 0 after frame disable!");
        assert(ser_en_o === 1'b0) else $fatal("ERROR: ser_en_o should be 0 after frame disable!");
        $display("VALID_FRAME Test: PASSED");

        // Finish simulation
        $display("Simulation Finished: ALL TESTS PASSED");
        $stop;
    end

    // ============================================================
    // Monitor
    // ============================================================
    initial begin
        $monitor("Time=%0t | State Signals: pattern_en=%b frame_en=%b | TVLD=%h | Done=%b | ser_en_o=%b",
                  $time, valid_pattern_en, valid_frame_en,
                  o_TVLD_L, O_done, ser_en_o);
    end

endmodule