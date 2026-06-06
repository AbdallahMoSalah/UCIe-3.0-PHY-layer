module CLK_PATTERN_GEN_TX_tb;

    // -----------------------------
    // DUT signals
    // -----------------------------
    logic i_clk;
    logic i_rst_n;
    logic clk_pattern_en;
    logic clk_embedded_en;

    logic o_clk_p;
    logic o_clk_n;
    logic track;
    logic o_done;

    // -----------------------------
    // Instantiate DUT
    // -----------------------------
    unit_clk_pattern_gen_tx dut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .clk_pattern_en(clk_pattern_en),
        .clk_embedded_en(clk_embedded_en),
        .o_clk_p(o_clk_p),
        .o_clk_n(o_clk_n),
        .track(track),
        .o_done(o_done)
    );

    // -----------------------------
    // Clock generation (100 MHz)
    // -----------------------------
    initial i_clk = 0;
    always #5 i_clk = ~i_clk;   // 10ns period

    // -----------------------------
    // Stimulus
    // -----------------------------
    initial begin
        i_rst_n = 0;
        clk_pattern_en = 0;
        clk_embedded_en = 0;
        @(posedge i_clk);
        i_rst_n = 1;clk_pattern_en = 1;
        repeat(3500) @(negedge i_clk);
        $display("done");
        @(negedge i_clk);
         clk_pattern_en = 0;
        clk_embedded_en = 0;
        @(posedge i_clk);
        i_rst_n = 1;clk_pattern_en = 1;
        repeat(3500) @(negedge i_clk);
        $display("done");
        @(negedge i_clk);
        i_rst_n = 0;
        clk_pattern_en = 0;
        clk_embedded_en = 0;
        @(posedge i_clk);
        i_rst_n = 1;clk_embedded_en = 1;
        repeat(6000) @(negedge i_clk);
        $display("done");
        @(negedge i_clk);
        $stop;
    end

    // -----------------------------
    // Monitor signals
    // -----------------------------



endmodule