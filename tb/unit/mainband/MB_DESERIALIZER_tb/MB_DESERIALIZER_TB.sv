`timescale 1ns/1ps

module MB_DESERIALIZER_TB;

/* -------------------------------------------------- */
/* Parameters                                         */
/* -------------------------------------------------- */
parameter DATA_WIDTH  = 32;
parameter PLL_PERIOD  = 2;          // 500 MHz  → period = 2ns
parameter MB_PERIOD   = 64;         // 64ns

/* -------------------------------------------------- */
/* DUT Signals                                        */
/* -------------------------------------------------- */
reg                    MB_clk;
reg                    pll_clk;
reg                    i_rst_n;
reg                    ser_data_en;
reg                    ser_data_in;
reg                    enable_des_valid_frame;

wire [DATA_WIDTH-1:0]  par_data_out;
wire                   de_ser_done;

/* -------------------------------------------------- */
/* DUT Instantiation                                  */
/* -------------------------------------------------- */
MB_DESERIALIZER #(
    .DATA_WIDTH(DATA_WIDTH)
) DUT (
    .MB_clk                (MB_clk),
    .pll_clk               (pll_clk),
    .i_rst_n               (i_rst_n),
    .ser_data_en           (ser_data_en),
    .ser_data_in           (ser_data_in),
    .enable_des_valid_frame(enable_des_valid_frame),
    .par_data_out          (par_data_out),
    .de_ser_done           (de_ser_done)
);

/* -------------------------------------------------- */
/* Clock Generation                                   */
/* -------------------------------------------------- */
initial pll_clk = 0;
always #(PLL_PERIOD/2.0) pll_clk = ~pll_clk;

initial MB_clk = 0;
always #(MB_PERIOD/2.0) MB_clk = ~MB_clk;

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
        @(posedge pll_clk);
        #0.1;
        ser_data_en = 1'b1;

        for (i = 0; i < DATA_WIDTH; i = i + 1) begin
            ser_data_in = data[i];  // LSB first
            @(pll_clk); // Wait for the next edge
            #0.1; // Small delay to drive after edge
        end
        
        ser_data_en = 1'b0;
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
        @(posedge MB_clk); #0.1; // sample after posedge

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
/* Task: Check No Output                              */
/* -------------------------------------------------- */
task check_no_output;
    input integer test_id;
    reg failed;
    begin
        failed = 0;
        fork
            begin
                @(posedge de_ser_done);
                failed = 1;
            end
            begin
                repeat(10) @(posedge MB_clk);
            end
        join_any
        disable fork;

        if (failed) begin
            $display("[FAIL] Test %0d | Expected: NO OUTPUT | Got: de_ser_done pulsed", test_id);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Test %0d | Expected: NO OUTPUT | Got: NO OUTPUT", test_id);
            pass_count = pass_count + 1;
        end
    end
endtask

/* -------------------------------------------------- */
/* Main Test Sequence                                 */
/* -------------------------------------------------- */
initial begin
    // Initialize
    i_rst_n                = 1'b0;
    ser_data_en            = 1'b0;
    ser_data_in            = 1'b0;
    enable_des_valid_frame = 1'b1;
    test_num               = 0;
    pass_count             = 0;
    fail_count             = 0;

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
    enable_des_valid_frame = 1'b1;
    $display("[TEST %0d] Sending: 0x%08H with enable_des_valid_frame = 1", test_num, test_vectors[0]);
    fork
        send_serial_word(test_vectors[0]);
        check_output(test_vectors[0], test_num);
    join

    repeat(2) @(posedge MB_clk);

    /* ------ Test 2 ------ */
    test_num = 2;
    enable_des_valid_frame = 1'b1;
    $display("[TEST %0d] Sending: 0x%08H with enable_des_valid_frame = 1", test_num, test_vectors[1]);
    fork
        send_serial_word(test_vectors[1]);
        check_output(test_vectors[1], test_num);
    join

    repeat(2) @(posedge MB_clk);

    /* ------ Test 3 ------ */
    test_num = 3;
    enable_des_valid_frame = 1'b0;
    $display("[TEST %0d] Sending: 0x%08H with enable_des_valid_frame = 0", test_num, test_vectors[1]);
    fork
        send_serial_word(test_vectors[1]);
        check_no_output(test_num);
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
