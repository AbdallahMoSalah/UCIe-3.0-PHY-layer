`timescale 1ns/1ps

module MB_DESERIALIZER_TB;

/* -------------------------------------------------- */
/* Parameters                                         */
/* -------------------------------------------------- */
parameter DATA_WIDTH  = 32;
parameter PLL_PERIOD  = 2;          // 500 MHz  → period = 2ns
parameter MB_PERIOD   = PLL_PERIOD * DATA_WIDTH; // 64ns (~15.6 MHz)

/* -------------------------------------------------- */
/* DUT Signals                                        */
/* -------------------------------------------------- */
reg                    MB_clk;
reg                    pll_clk;
reg                    i_ckp;
reg                    i_ckn;
reg                    i_rst_n;
reg                    ser_valid;
reg                    ser_data_in;

wire [DATA_WIDTH-1:0]  par_data_out;
wire                   de_ser_done;

/* -------------------------------------------------- */
/* DUT Instantiation                                  */
/* -------------------------------------------------- */
MB_DESERIALIZER #(
    .DATA_WIDTH(DATA_WIDTH)
) DUT (
    .MB_clk      (MB_clk),
    .pll_clk     (pll_clk),
    .i_ckp       (i_ckp),
    .i_ckn       (i_ckn),
    .i_rst_n     (i_rst_n),
    .ser_valid   (ser_valid),
    .ser_data_in (ser_data_in),
    .par_data_out(par_data_out),
    .de_ser_done (de_ser_done)
);

/* -------------------------------------------------- */
/* Clock Generation                                   */
/* -------------------------------------------------- */
// pll_clk: 500 MHz (period = 2ns)
initial pll_clk = 0;
always #(PLL_PERIOD/2.0) pll_clk = ~pll_clk;

// MB_clk: 32x slower = period 64ns
initial MB_clk = 0;
always #(MB_PERIOD/2.0) MB_clk = ~MB_clk;

// Differential clocks
assign i_ckp = pll_clk;
assign i_ckn = ~pll_clk;

/* -------------------------------------------------- */
/* Test Data & Expected Output                        */
/* -------------------------------------------------- */
integer test_num;
integer pass_count;
integer fail_count;

reg [DATA_WIDTH-1:0] test_vectors [0:1]; // Just 2 tests

/* -------------------------------------------------- */
/* Task: Send Serial Data (DDR - LSB first)           */
/* -------------------------------------------------- */
task send_serial_word;
    input [DATA_WIDTH-1:0] data;
    integer i;
    begin
        ser_valid    = 1'b0;
        ser_data_in  = 1'b0;

        for (i = 0; i < DATA_WIDTH; i = i + 1) begin
            // To sample a bit on posedge, we set it on the preceding negedge.
            // To sample a bit on negedge, we set it on the preceding posedge.
            if (i % 2 == 0)
                @(negedge pll_clk);
            else
                @(posedge pll_clk);

            ser_data_in = data[i];  // LSB first
            #0.1; // Small delay
        end

        // Wait for the final bit (i=31) to be sampled.
        // It was set on posedge, so it will be sampled on the upcoming negedge.
        @(negedge pll_clk);
        #0.1; // Now shift_reg contains all 32 bits properly.

        // Delay ser_valid to latch data on the next posedge.
        ser_valid = 1'b1;
        @(posedge pll_clk); // save_data accurately captures the fully formed correct word here
        #0.1;
        
        ser_valid   = 1'b0;
        ser_data_in = 1'b0;
    end
endtask

/* -------------------------------------------------- */
/* Task: Check Output                                 */
/* -------------------------------------------------- */
task check_output;
    input [DATA_WIDTH-1:0] expected;
    input integer          test_id;
    begin
        // Wait for de_ser_done pulse in MB_clk domain
        @(posedge de_ser_done);
        @(posedge MB_clk); #1; // sample after posedge

        if (par_data_out === expected) begin
            $display("[PASS] Test %0d | Expected: 0x%08H | Got: 0x%08H",
                     test_id, expected, par_data_out);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test %0d | Expected: 0x%08H | Got: 0x%08H",
                     test_id, expected, par_data_out);
            fail_count = fail_count + 1;
        end
    end
endtask

/* -------------------------------------------------- */
/* Main Test Sequence                                 */
/* -------------------------------------------------- */
initial begin
    // Initialize
    i_rst_n     = 1'b0;
    ser_valid   = 1'b0;
    ser_data_in = 1'b0;
    test_num    = 0;
    pass_count  = 0;
    fail_count  = 0;

    // Load exactly two test vectors
    test_vectors[0] = 32'hA5A5A5A5; // Pattern 1
    test_vectors[1] = 32'hDEADBEEF; // Pattern 2

    $display("============================================");
    $display("  MB_DESERIALIZER Testbench");
    $display("  pll_clk = %0d MHz | MB_clk = %0.1f MHz",
             1000/PLL_PERIOD, 1000.0/MB_PERIOD);
    $display("  DATA_WIDTH = %0d", DATA_WIDTH);
    $display("============================================");

    // ---- Reset ----
    repeat(4) @(posedge MB_clk);
    i_rst_n = 1'b1;
    repeat(2) @(posedge MB_clk);

    $display("\n[INFO] Reset released. Starting tests...\n");

    /* ------ Test 1 ------ */
    test_num = 1;
    $display("[TEST %0d] Sending: 0x%08H", test_num, test_vectors[0]);
    fork
        send_serial_word(test_vectors[0]);
        check_output(test_vectors[0], test_num);
    join

    repeat(2) @(posedge MB_clk);

    /* ------ Test 2 ------ */
    test_num = 2;
    $display("[TEST %0d] Sending: 0x%08H", test_num, test_vectors[1]);
    fork
        send_serial_word(test_vectors[1]);
        check_output(test_vectors[1], test_num);
    join

    /* ------ Summary ------ */
    repeat(4) @(posedge MB_clk);
    $display("\n============================================");
    $display("  TEST SUMMARY");
    $display("  Total : %0d | PASS: %0d | FAIL: %0d",
             pass_count + fail_count, pass_count, fail_count);
    if (fail_count == 0)
        $display("  *** ALL TESTS PASSED *** ");
    else
        $display("  *** %0d TEST(S) FAILED ***", fail_count);
    $display("============================================\n");

    $finish;
end

/* -------------------------------------------------- */
/* Timeout Watchdog                                   */
/* -------------------------------------------------- */
initial begin
    #50000;
    $display("[ERROR] Simulation timeout! Check for missing de_ser_done.");
    $finish;
end

/* -------------------------------------------------- */
/* Waveform Dump                                      */
/* -------------------------------------------------- */
initial begin
    $dumpfile("MB_DESERIALIZER_tb.vcd");
    $dumpvars(0, MB_DESERIALIZER_TB);
end

endmodule
