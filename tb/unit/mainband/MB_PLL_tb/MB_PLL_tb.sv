`timescale 1ps/1ps

module MB_PLL_tb;

    // =========================
    // Signals
    // =========================
    reg en;
    reg [1:0] speed_sel;

    wire clk;
    real period;

    // =========================
    // Instantiate DUT
    // =========================
    unit_mb_pll dut (
        .en(en),
        .speed_sel(speed_sel),
        .clk(clk),
        .period(period)
    );

    // =========================
    // Monitor (print values)
    // =========================
    initial begin
        $monitor("Time=%0t | en=%0b | speed=%0b | period=%0f | clk=%0b",
                  $time, en, speed_sel, period, clk);
    end

    // =========================
    // Dump waveform 
    // =========================
    initial begin
        $dumpfile("pll.vcd");
        $dumpvars(0, MB_PLL_tb);
    end

    // =========================
    // Stimulus
    // =========================
    initial begin
        $display("===== PLL Test Start =====");

        en = 0;
        speed_sel = 2'b00;

        #100;
        en = 1;  

        #1000;
        speed_sel = 2'b00; // 4 GHz

        #1000;
        speed_sel = 2'b01; // 8 GHz

        #1000;
        speed_sel = 2'b10; // 12 GHz

        #1000;
        speed_sel = 2'b11; // 16 GHz

        #1000;
        en = 0; 

        #500;
        $display("===== Test End =====");
        $stop;
    end

endmodule