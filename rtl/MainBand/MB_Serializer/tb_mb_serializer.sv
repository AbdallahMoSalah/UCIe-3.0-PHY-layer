`timescale 1ns/1ps

module tb_mb_serializer;

    // Parameters
    parameter DATA_WIDTH = 32;

    // Signals
    reg                   mb_clk;
    reg                   PLL_clk;
    reg                   i_rst_n;
    reg                   Ser_en;
    reg  [DATA_WIDTH-1:0] in_data;
    wire                  SER_out;

    // Instantiate the Unit Under Test (UUT)
    MB_SERIALIZER #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .mb_clk(mb_clk),
        .PLL_clk(PLL_clk),
        .i_rst_n(i_rst_n),
        .Ser_en(Ser_en),
        .in_data(in_data),
        .SER_out(SER_out)
    );

    // ======================================================
    // Clock generation
    // ======================================================
    // PLL_clk is the fast clock (e.g., the serializer clock). 
    // Toggles every 1ns -> 2ns period (500 MHz)
    initial begin
        PLL_clk = 0;
        forever #1 PLL_clk = ~PLL_clk; 
    end

    // mb_clk is the slow parallel data clock.
    // For DATA_WIDTH = 32, its frequency is typically 1/32 of PLL_clk.
    // Toggles every 32ns -> 64ns period (~15.625 MHz)
    initial begin
        mb_clk = 0;
        forever #(DATA_WIDTH) mb_clk = ~mb_clk;
    end

    // ======================================================
    // Stimulus process
    // ======================================================
    initial begin
        // Initialize Inputs
        i_rst_n = 0;
        Ser_en  = 0;
        in_data = 0;

        // Note: You can enable waveform dumping if using Icarus/Verilator
        // $dumpfile("tb_mb_serializer.vcd");
        // $dumpvars(0, tb_mb_serializer);

        // Wait for global reset
        #50;
        i_rst_n = 1;
        
        // Wait a couple of mb_clk cycles to stabilize
        @(posedge mb_clk);
        @(posedge mb_clk);

        // ------------------------------------------------------
        // Test Case 1: Send a specific pattern (Alternating bits)
        // ------------------------------------------------------
        @(posedge mb_clk);
        in_data = 32'hA5A5_5A5A; 
        Ser_en  = 1;
        
        // Hold Ser_en high for one mb_clk cycle
        @(posedge mb_clk);
        Ser_en  = 0; 
        
        // Wait enough time to ensure the 32 bits have shifted out
        // (1 mb_clk cycle is exact time it takes to shift 32 bits)
        // We'll wait 2 mb_clk cycles just to give some buffer
        repeat (2) @(posedge mb_clk);

        // ------------------------------------------------------
        // Test Case 2: Send another data pattern
        // ------------------------------------------------------
        @(posedge mb_clk);
        in_data = 32'hDEAD_BEEF; 
        Ser_en  = 1;
        
        @(posedge mb_clk);
        // Ser_en remaining high shouldn't re-trigger because of the edge 
        // detection, but we pull it down here anyway
        Ser_en  = 0;

        // Wait for serialization to finish
        repeat (2) @(posedge mb_clk);

        // ------------------------------------------------------
        // End simulation
        // ------------------------------------------------------
        #100;
        $display("Simulation finished successfully.");
        $finish;
    end

endmodule
