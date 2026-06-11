`timescale 1ns/1ps

module MB_SERIALIZER_TB;

parameter DATA_WIDTH = 32;

reg i_clk;
reg PLL_clk;
reg i_rst_n;
reg Ser_en;
reg [DATA_WIDTH-1:0] in_data;

wire SER_out;

integer i;
reg [DATA_WIDTH-1:0] expected_data;

// DUT
MB_SERIALIZER #(
    .DATA_WIDTH(DATA_WIDTH)
) DUT (
    .mb_clk(i_clk),
    .PLL_clk(PLL_clk),
    .i_rst_n(i_rst_n),
    .Ser_en(Ser_en),
    .in_data(in_data),
    .SER_out(SER_out)
);

// ============================================================
// CLOCKS
// mb_clk  : period = 16ns  (half = 8ns)
// PLL_clk : period = 0.5ns (half = 0.25ns)
// ============================================================
initial begin
    i_clk = 0;
    forever #4 i_clk = ~i_clk;
end

initial begin
    PLL_clk = 0;
    forever #0.25 PLL_clk = ~PLL_clk;  // 2 GHz
end

// ============================================================
// TASK: sample SER_out in the middle of current half-cycle
// half_period = 0.25ns  →  mid = 0.125ns after edge
// ============================================================
task sample_bit;
    input integer bit_idx;
    begin
        #0.125;   // wait to middle of this half-cycle
        if (SER_out !== expected_data[0]) begin
            $display("[%0t] Bit %0d ERROR : expected=%b got=%b",
                     $time, bit_idx, expected_data[0], SER_out);
        end else begin
            $display("[%0t] Bit %0d OK    : %b", $time, bit_idx, SER_out);
        end
        expected_data = expected_data >> 1;
    end
endtask

// ============================================================
// TEST
// ============================================================
initial begin
    $display("===== SERIALIZER TEST START =====");

    i_rst_n = 0;
    Ser_en  = 0;
    in_data = 0;
    #20;
    i_rst_n = 1;

    // Wait for a clean mb_clk edge before driving stimulus
    @(posedge i_clk);

    // --------------- Drive input ---------------
    in_data       = 32'hA5A5F0F0;
    expected_data = in_data;
    Ser_en        = 1;

    fork
        begin
            // Deassert Ser_en on the next posedge of i_clk so it is synchronous to i_clk
            @(posedge i_clk);
            #1;
            Ser_en        = 0;
        end
        begin
            // --------------- Wait for serialization start ---------------
            // rising_ser_en_pll is a COMBINATIONAL pulse:
            //   (sync2_toggle != sync3_toggle)
            // It goes high for exactly 1 PLL cycle coinciding with a posedge.
            // We wait for that posedge so we are at the clock edge where
            // load_condition is true and the registers are about to be loaded.
            @(posedge PLL_clk iff (DUT.rising_ser_en_pll === 1'b1));

            $display("[%0t] load_condition detected — serialization starts", $time);

            // Glitch-free DDR output adds one PLL cycle of startup latency:
            // the load cycle drives the (stale) reset value, the first real
            // even bit appears on the NEXT posedge. Skip that startup cycle.
            @(posedge PLL_clk);

            // The registers (SER_pos_reg, SER_neg_prep) are loaded on THIS posedge.
            // SER_out is a combinational mux:
            //   PLL_clk=1  → SER_pos_reg  (bit 0)
            //   PLL_clk=0  → SER_neg_reg  (bit 1, registered on negedge)
            //
            // We are currently AT the posedge (PLL_clk=1).
            // Bit 0 is valid after the FF propagation delta.
            // Sample each bit in the middle of its half-cycle.

            for (i = 0; i < DATA_WIDTH; i = i + 1) begin
                if (i % 2 == 0) begin
                    // ---- Even bit: positive half-cycle (PLL_clk = 1) ----
                    // We arrive here at the START of the positive half.
                    sample_bit(i);
                    // Wait for the negedge to enter the negative half-cycle.
                    @(negedge PLL_clk);
                end else begin
                    // ---- Odd bit: negative half-cycle (PLL_clk = 0) ----
                    // SER_neg_reg was just loaded from SER_neg_prep on this negedge.
                    // SER_out is now SER_neg_reg.
                    sample_bit(i);
                    // Wait for the next posedge to start the next even bit.
                    @(posedge PLL_clk);
                end
            end
        end
    join

    // --------------- End of test ---------------
    #10;
    $display("===== TEST FINISHED =====");
    $stop;
end
endmodule