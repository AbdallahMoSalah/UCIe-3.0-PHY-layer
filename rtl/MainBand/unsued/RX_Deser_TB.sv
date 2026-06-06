`timescale 1ns/1ps
// =============================================================================
// Testbench : RX_Deser_TB
// Project   : UCIe 3.0 Main-Band Physical Layer
// Purpose   : End-to-end verification of the RX deserialization chain:
//               MB_SERIALIZER (TX) → channel → Valid_Deserializer
//                                             → Valid_Frame_Detector
//                                             → Data_Deserializer
//
//  Verifies that the data captured by the Data_Deserializer exactly matches
//  the data word sent by the TX serializer, with no bits lost or shifted
//  due to detection latency.
//
//  Test plan
//  ---------
//   TEST 1 : 0xDEADBEEF  — arbitrary data
//   TEST 2 : 0x12345678  — another arbitrary pattern
//   TEST 3 : 0xCAFEBABE  — another arbitrary pattern
//   TEST 4 : 0xFFFFFFFF  — all ones
//   TEST 5 : 0x00000000  — all zeros
//   TEST 6 : 0xAAAAAAAA  — alternating bits
//   TEST 7 : 0x0F0F0F0F  — same as valid pattern (corner case)
// =============================================================================
module RX_Deser_TB;

    // =====================================================================
    // Parameters
    // =====================================================================
    parameter DATA_WIDTH = 32;
    parameter PLL_PERIOD = 2.0;                        // pll_clk period (ns)
    parameter MB_PERIOD  = PLL_PERIOD * (DATA_WIDTH/2); // mb_clk = 16 × pll_clk

    // =====================================================================
    // Clocks & Reset
    // =====================================================================
    reg  pll_clk;
    reg  mb_clk;
    reg  rst_n;

    initial pll_clk = 0;
    always #(PLL_PERIOD / 2.0) pll_clk = ~pll_clk;

    initial mb_clk = 0;
    always #(MB_PERIOD / 2.0) mb_clk = ~mb_clk;

    // =====================================================================
    // TX-side signals
    // =====================================================================
    reg  [DATA_WIDTH-1:0] valid_tx_word;    // parallel word for valid lane
    reg  [DATA_WIDTH-1:0] data_tx_word;     // parallel word for data lane
    reg                   tx_ser_en;        // serializer load enable (1 mb_clk pulse)

    wire                  valid_serial_out; // serial valid lane
    wire                  data_serial_out;  // serial data lane

    wire                  rx_pll_clk;
    assign #0.5 rx_pll_clk = pll_clk;

    // =====================================================================
    // RX-side signals
    // =====================================================================
    wire [DATA_WIDTH-1:0] valid_shift_reg;   // from Valid_Deserializer
    wire                  valid_frame_pulse; // from Valid_Frame_Detector
    wire [DATA_WIDTH-1:0] rx_par_data;       // captured parallel data
    wire                  rx_data_valid;     // one-cycle valid pulse (mb_clk domain)

    // =====================================================================
    // TX: Valid-lane serializer  (uses existing MB_SERIALIZER from unsued/)
    // =====================================================================
    MB_SERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_tx_valid_ser (
        .mb_clk  (mb_clk),
        .PLL_clk (pll_clk),
        .i_rst_n (rst_n),
        .Ser_en  (tx_ser_en),
        .in_data (valid_tx_word),
        .SER_out (valid_serial_out)
    );

    // =====================================================================
    // TX: Data-lane serializer
    // =====================================================================
    MB_SERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) u_tx_data_ser (
        .mb_clk  (mb_clk),
        .PLL_clk (pll_clk),
        .i_rst_n (rst_n),
        .Ser_en  (tx_ser_en),
        .in_data (data_tx_word),
        .SER_out (data_serial_out)
    );

    // =====================================================================
    // RX: Valid Deserializer — free-running DDR shift register
    // =====================================================================
    Valid_Deserializer #(.DATA_WIDTH(DATA_WIDTH)) u_valid_des (
        .pll_clk     (rx_pll_clk), // Use delayed clock
        .i_rst_n     (rst_n),
        .ser_data_in (valid_serial_out),
        .o_shift_reg (valid_shift_reg)
    );

    // =====================================================================
    // RX: Valid Frame Detector — pure combinational
    // =====================================================================
    Valid_Frame_Detector #(
        .DATA_WIDTH   (DATA_WIDTH),
        .VALID_PATTERN(32'h0F0F0F0F)
    ) u_frame_det (
        .i_shift_reg         (valid_shift_reg),
        .o_valid_frame_pulse (valid_frame_pulse)
    );

    // =====================================================================
    // RX: Data Deserializer — free-running shift + capture on pulse
    // =====================================================================
    Data_Deserializer #(.DATA_WIDTH(DATA_WIDTH)) u_data_des (
        .mb_clk              (mb_clk),
        .pll_clk             (rx_pll_clk), // Use delayed clock
        .i_rst_n             (rst_n),
        .ser_data_in         (data_serial_out),
        .i_valid_frame_pulse (valid_frame_pulse),
        .o_par_data          (rx_par_data),
        .o_data_valid        (rx_data_valid)
    );

    // =====================================================================
    // Scoreboard
    // =====================================================================
    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    reg [DATA_WIDTH-1:0] expected_data;
    reg                  waiting_for_result;

    // =====================================================================
    // Monitor — valid-frame detection events
    // =====================================================================
    reg prev_valid_frame_pulse;
    always @(negedge pll_clk or negedge rst_n) begin
        if (!rst_n)
            prev_valid_frame_pulse <= 1'b0;
        else
            prev_valid_frame_pulse <= valid_frame_pulse;
    end

    wire valid_frame_edge = valid_frame_pulse & ~prev_valid_frame_pulse;

    always @(posedge valid_frame_edge) begin
        $display("  [DET]  T=%0t  Valid frame detected  shift_reg=0x%08h",
                 $time, valid_shift_reg);
    end

    // =====================================================================
    // Monitor — data capture events (mb_clk domain)
    // =====================================================================
    always @(posedge mb_clk) begin
        if (rx_data_valid && waiting_for_result) begin
            if (rx_par_data === expected_data) begin
                $display("  [PASS] T=%0t  Captured=0x%08h  Expected=0x%08h",
                         $time, rx_par_data, expected_data);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] T=%0t  Captured=0x%08h  Expected=0x%08h  << MISMATCH",
                         $time, rx_par_data, expected_data);
                fail_count = fail_count + 1;
            end
            waiting_for_result = 0;
        end
    end

    // =====================================================================
    // Task : send_frame — loads TX serializers for one mb_clk cycle
    // =====================================================================
    task send_frame(
        input [DATA_WIDTH-1:0] vld_word,
        input [DATA_WIDTH-1:0] dat_word
    );
    begin
        valid_tx_word = vld_word;
        data_tx_word  = dat_word;
        @(posedge mb_clk);
        tx_ser_en = 1;
        @(posedge mb_clk);
        tx_ser_en = 0;
    end
    endtask

    // =====================================================================
    // Task : wait_for_capture — waits for rx_data_valid or timeout
    // =====================================================================
    task wait_for_capture(input integer timeout_mb_cycles);
        integer i;
    begin
        for (i = 0; i < timeout_mb_cycles; i = i + 1) begin
            @(posedge mb_clk);
            if (!waiting_for_result) begin
                return;   // result already handled by the monitor
            end
        end
        // Timeout
        if (waiting_for_result) begin
            $display("  [FAIL] T=%0t  Timeout — no data_valid received!", $time);
            fail_count = fail_count + 1;
            waiting_for_result = 0;
        end
    end
    endtask

    // =====================================================================
    // Task : run_test — complete test sequence
    // =====================================================================
    task run_test(
        input [DATA_WIDTH-1:0] data_word,
        input [255:0]          test_name   // up to 32 chars
    );
    begin
        test_num = test_num + 1;
        $display("");
        $display("======== TEST %0d: %0s  data=0x%08h ========",
                 test_num, test_name, data_word);

        expected_data      = data_word;
        waiting_for_result = 1;

        send_frame(32'h0F0F0F0F, data_word);

        wait_for_capture(20);  // generous timeout

        // Gap between tests to flush shift registers
        #(MB_PERIOD * 3);
    end
    endtask

    // =====================================================================
    // Main stimulus
    // =====================================================================
    initial begin
        $dumpfile("rx_deser_tb.vcd");
        $dumpvars(0, RX_Deser_TB);

        // ---- Reset ----
        rst_n             = 0;
        tx_ser_en         = 0;
        valid_tx_word     = 32'h0;
        data_tx_word      = 32'h0;
        waiting_for_result = 0;

        repeat (5) @(posedge mb_clk);
        rst_n = 1;
        repeat (3) @(posedge mb_clk);

        $display("");
        $display("==========================================================");
        $display("  RX Deserializer End-to-End Testbench");
        $display("  PLL period = %0.1f ns   MB period = %0.1f ns", PLL_PERIOD, MB_PERIOD);
        $display("==========================================================");

        // ---- Run tests ----
        run_test(32'hDEADBEEF, "Arbitrary data      ");
        run_test(32'h12345678, "Sequential nibbles   ");
        run_test(32'hCAFEBABE, "CAFEBABE             ");
        run_test(32'hFFFFFFFF, "All ones             ");
        run_test(32'h00000000, "All zeros            ");
        run_test(32'hAAAAAAAA, "Alternating 10       ");
        run_test(32'h55555555, "Alternating 01       ");
        run_test(32'h0F0F0F0F, "Same as valid pattern");
        run_test(32'h80000001, "MSB+LSB set          ");
        run_test(32'hA5A5A5A5, "Checkerboard         ");

        // ---- Back-to-back Frame Test ----
        $display("");
        $display("======== TEST 11: Back-to-Back Frames ========");
        test_num = test_num + 2; // We are sending 2 frames
        expected_data = 32'h11111111;
        waiting_for_result = 1;
        
        valid_tx_word = 32'h0F0F0F0F;
        data_tx_word  = 32'h11111111;
        @(posedge mb_clk);
        tx_ser_en = 1;
        @(posedge mb_clk);
        valid_tx_word = 32'h0F0F0F0F;
        data_tx_word  = 32'h22222222;
        tx_ser_en = 1;
        @(posedge mb_clk);
        tx_ser_en = 0;

        wait_for_capture(20);

        expected_data = 32'h22222222;
        waiting_for_result = 1;
        wait_for_capture(20);

        #(MB_PERIOD * 3);

        // ---- Summary ----
        $display("");
        $display("==========================================================");
        $display("  RESULTS:  %0d PASSED   %0d FAILED   (out of %0d tests)",
                 pass_count, fail_count, test_num);
        $display("==========================================================");
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $display("");

        repeat (3) @(posedge mb_clk);
        $finish;
    end

    // =====================================================================
    // Simulation watchdog — kill if it runs too long
    // =====================================================================
    initial begin
        #(MB_PERIOD * 500);
        $display("[WATCHDOG] Simulation timeout — forcing $finish");
        $finish;
    end

endmodule
