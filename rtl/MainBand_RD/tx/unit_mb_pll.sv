`timescale 1ps/1ps

module unit_mb_pll (
    input  logic       en,         // Enable signal
    input  logic [2:0] speed_sel,  // Select speed (frequency)
    output reg         clk,        // Output PLL clock
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
            clk = 0;               // Force clock to 0
            @(posedge en);         // Wait until enable becomes 1
        end
        else begin
            // Update local period based on speed
            case (speed_sel)//we support 2G,4G,8G,16G
                3'b000: local_period = 500;   // 2G
                3'b001: local_period = 250;   // 4G
                3'b010: local_period = 167;   // 6G
                3'b011: local_period = 125;   // 8G
                3'b100: local_period = 83;    // 12G
                3'b101: local_period = 62.5;  // 16G
                default: local_period = 500;
            endcase
            // Toggle clock every half period
            #(local_period/2) clk = ~clk;
        end
    end
endmodule