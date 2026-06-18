`timescale 1ps/1ps

// =============================================================================
// Helper Module: sb_pll 
// =============================================================================
module sb_pll (
    input  logic       en,          // Enable signal
    output reg         clk,         // Output PLL clock (800 MHz)
    output real        local_period // Output period (ps)
);
    // =========================
    // Initialize clock
    // =========================
    initial clk = 0;

    // =========================
    // Clock generation process
    // =========================
    always begin
        // If PLL is disabled
        if (!en) begin
            clk = 0;                // Force clock to 0
            @(posedge en);          // Wait until enable becomes 1
        end
        else begin
            // 800 MHz corresponds to a period of 1.25 ns = 1250 ps
            local_period = 1250.0;
            // Toggle clock every half period
            #(local_period/2.0) clk = ~clk;
        end
    end
endmodule
