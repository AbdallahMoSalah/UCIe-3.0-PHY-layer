`timescale 1ns/1ps
// =============================================================================
// Debug TB v3 — find what pattern the valid frame actually assembles to
// =============================================================================
module unit_rx_debug_tb;

    parameter DATA_WIDTH = 32;
    parameter PLL_PERIOD = 2.0;
    parameter MB_PERIOD  = PLL_PERIOD * (DATA_WIDTH/2); // 32ns

    reg  pll_clk, mb_clk, rst_n;
    initial pll_clk = 0;
    always #(PLL_PERIOD / 2.0) pll_clk = ~pll_clk;
    initial mb_clk = 0;
    always #(MB_PERIOD / 2.0) mb_clk = ~mb_clk;

    // TX: 2 serializers (valid + data), SAME timing
    reg  [DATA_WIDTH-1:0] valid_tx_word, data_tx_word;
    reg                   tx_ser_en;
    wire                  valid_serial, data_serial;

    unit_mb_serializer #(.DATA_WIDTH(DATA_WIDTH)) u_tx_valid (
        .mb_clk(mb_clk), .PLL_clk(pll_clk), .i_rst_n(rst_n),
        .Ser_en(tx_ser_en), .in_data(valid_tx_word), .SER_out(valid_serial)
    );
    unit_mb_serializer #(.DATA_WIDTH(DATA_WIDTH)) u_tx_data (
        .mb_clk(mb_clk), .PLL_clk(pll_clk), .i_rst_n(rst_n),
        .Ser_en(tx_ser_en), .in_data(data_tx_word), .SER_out(data_serial)
    );

    // RX: 2 free-running deserializers (valid + data)
    wire [DATA_WIDTH-1:0] valid_shift, data_shift;

    unit_valid_deserializer #(.DATA_WIDTH(DATA_WIDTH)) u_valid_des (
        .pll_clk(pll_clk), .i_rst_n(rst_n),
        .ser_data_in(valid_serial), .o_shift_reg(valid_shift)
    );
    unit_valid_deserializer #(.DATA_WIDTH(DATA_WIDTH)) u_data_des (
        .pll_clk(pll_clk), .i_rst_n(rst_n),
        .ser_data_in(data_serial), .o_shift_reg(data_shift)
    );

    // Track when the valid pattern appears
    integer neg_cnt;
    initial neg_cnt = 0;
    reg found;
    initial found = 0;

    always @(negedge pll_clk) begin
        neg_cnt = neg_cnt + 1;
        // Look for the exact word that assembles from 0x0F0F0F0F
        // Also show what 0xDEADBEEF assembles to at the same instant
        if (neg_cnt > 130 && neg_cnt < 180) begin
            $display("  neg%-4d valid_shift=0x%08h  data_shift=0x%08h",
                     neg_cnt, valid_shift, data_shift);
        end
    end

    // Also try: use the existing unit_mb_deserializer with counter to see what it gets
    wire [DATA_WIDTH-1:0] ref_valid_out, ref_data_out;
    wire ref_valid_done, ref_data_done;

    unit_mb_deserializer #(.DATA_WIDTH(DATA_WIDTH)) u_ref_valid (
        .MB_clk(mb_clk), .pll_clk(pll_clk), .i_rst_n(rst_n),
        .ser_data_en(1'b1), .ser_data_in(valid_serial),
        .enable_des_valid_frame(1'b1),
        .par_data_out(ref_valid_out), .de_ser_done(ref_valid_done)
    );
    unit_mb_deserializer #(.DATA_WIDTH(DATA_WIDTH)) u_ref_data (
        .MB_clk(mb_clk), .pll_clk(pll_clk), .i_rst_n(rst_n),
        .ser_data_en(1'b1), .ser_data_in(data_serial),
        .enable_des_valid_frame(1'b1),
        .par_data_out(ref_data_out), .de_ser_done(ref_data_done)
    );

    always @(posedge mb_clk) begin
        if (ref_valid_done)
            $display("  [REF VALID] T=%0t  par_data=0x%08h", $time, ref_valid_out);
        if (ref_data_done)
            $display("  [REF DATA]  T=%0t  par_data=0x%08h", $time, ref_data_out);
    end

    initial begin
        rst_n = 0;
        tx_ser_en = 0;
        valid_tx_word = 32'h0F0F0F0F;
        data_tx_word  = 32'hDEADBEEF;

        repeat (5) @(posedge mb_clk);
        rst_n = 1;
        repeat (2) @(posedge mb_clk);

        $display("\n=== Loading: valid=0x0F0F0F0F  data=0xDEADBEEF ===");
        @(posedge mb_clk);
        tx_ser_en = 1;
        @(posedge mb_clk);
        tx_ser_en = 0;

        // Wait long enough
        repeat (10) @(posedge mb_clk);

        $display("\n=== SUMMARY ===");
        $display("  Final valid_shift = 0x%08h", valid_shift);
        $display("  Final data_shift  = 0x%08h", data_shift);

        #10;
        $finish;
    end

endmodule
