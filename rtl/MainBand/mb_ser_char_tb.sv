// =============================================================================
// Testbench : mb_ser_char_tb
// Purpose   : Ground-truth proof of MB_SERIALIZER's DDR output phase. Mid-eye
//             samples SER_out (race-free: +0.5 ns into each half phase) over one
//             word and reconstructs it two ways:
//               NATURAL : high-phase bit = word[2n], low-phase bit = word[2n+1]
//                         (same cycle)  -> what a mid-eye deserializer must do.
//               PROD    : pair high[n] with the PREVIOUS low[n-1]
//                         -> what the production MB_DESERIALIZER actually does.
//             NATURAL == in_data, PROD != in_data, which is exactly why the
//             production deserializer is off by one bit (see unsued/mb_deserializer.sv).
// =============================================================================
`timescale 1ns/1ps
module mb_ser_char_tb;
    localparam int W = 32;
    logic MB_clk, pll_clk, i_rst_n;
    initial begin pll_clk = 0; forever #1 pll_clk = ~pll_clk; end
    initial begin MB_clk  = 0; forever #(W/2) MB_clk = ~MB_clk; end

    logic Ser_en; logic [W-1:0] in_data; wire SER_out;
    MB_SERIALIZER #(.DATA_WIDTH(W)) u_ser (
        .mb_clk(MB_clk), .PLL_clk(pll_clk), .i_rst_n(i_rst_n),
        .Ser_en(Ser_en), .in_data(in_data), .SER_out(SER_out));

    logic hi [0:W/2-1];
    logic lo [0:W/2-1];
    integer n;
    logic [W-1:0] word, rec_natural, rec_prod;

    initial begin
        i_rst_n = 0; Ser_en = 0; in_data = 0;
        repeat (3) @(posedge MB_clk); i_rst_n = 1; repeat (2) @(posedge MB_clk);

        word = 32'h1234_5678;
        @(posedge MB_clk); in_data = word; Ser_en = 1;
        @(posedge MB_clk); Ser_en = 0;

        @(posedge pll_clk);
        while (!u_ser.rising_ser_en_pll) @(posedge pll_clk);
        // at the load posedge bit0 is driven into the current high phase
        for (n = 0; n < W/2; n = n + 1) begin
            #0.5;  hi[n] = SER_out;   // mid high phase
            #1.0;  lo[n] = SER_out;   // mid low  phase
            #0.5;  ;                  // to next posedge
        end

        rec_natural = 0;
        for (n = 0; n < W/2; n = n + 1) begin
            rec_natural[2*n]   = hi[n];
            rec_natural[2*n+1] = lo[n];
        end
        rec_prod = 0;
        for (n = 0; n < W/2; n = n + 1) begin
            rec_prod[2*n+1] = hi[n];
            rec_prod[2*n]   = (n==0) ? 1'b0 : lo[n-1];
        end

        $display("SER char: word=0x%08h", word);
        $write("  high-phase bits (cyc0..15): "); for(n=0;n<W/2;n=n+1) $write("%0b",hi[n]); $write("\n");
        $write("  low-phase  bits (cyc0..15): "); for(n=0;n<W/2;n=n+1) $write("%0b",lo[n]); $write("\n");
        $display("  reconstruct NATURAL (hi=even,lo=odd)      = 0x%08h  %s",
                 rec_natural, (rec_natural===word)?"== in_data (correct)":"!= in_data");
        $display("  reconstruct PROD    (hi=odd,prev-lo=even) = 0x%08h  %s",
                 rec_prod, (rec_prod===word)?"== in_data":"!= in_data (off-by-one)");
        $stop;
    end
    initial begin #50000; $display("timeout"); $stop; end
endmodule