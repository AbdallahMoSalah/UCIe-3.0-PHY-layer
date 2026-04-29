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

    // ============================================================
    // Instantiate DUT
    // ============================================================
    VALID_TX DUT (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .valid_pattern_en(valid_pattern_en),
        .valid_frame_en(valid_frame_en),
        .O_done(O_done),
        .o_TVLD_L(o_TVLD_L)
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
        // Test 1: VALID_PATTERN Mode
        // =====================================================
        $display("---- Test VALID_PATTERN ----");

        @(posedge i_clk);
        valid_pattern_en = 1;

        @(posedge i_clk);
        valid_pattern_en = 0 ;

        // Wait for O_done
        wait (O_done == 1);

        @(posedge i_clk);  // observe done pulse

        // =====================================================
        // Test 2: VALID_FRAME Mode
        // =====================================================
        $display("---- Test VALID_FRAME ----");
        valid_frame_en = 1;

        repeat (10) @(posedge i_clk);

        valid_frame_en = 0;

        repeat (5) @(posedge i_clk);

        // Finish simulation
        $display("Simulation Finished");
        $stop;
    end

    // ============================================================
    // Monitor
    // ============================================================
    initial begin
        $monitor("Time=%0t | State Signals: pattern_en=%b frame_en=%b | TVLD=%h | Done=%b",
                  $time, valid_pattern_en, valid_frame_en,
                  o_TVLD_L, O_done);
    end

endmodule