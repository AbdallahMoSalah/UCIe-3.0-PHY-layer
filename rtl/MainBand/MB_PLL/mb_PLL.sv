`timescale 1ps/1ps

module MB_PLL (
    input  logic       en,         // Enable signal
    input  logic [1:0] speed_sel,  // Select speed (frequency)
    output reg         clk,        // Output clock
    output real        period      // Output period (ps)
);

    // Internal variable for timing
    real local_period;

    // =========================
    // Calculate period based on speed
    // =========================
    always @(*) begin
        case (speed_sel)
            2'b00: period = 500;    // 2 GHz
            2'b01: period = 250;    // 4 GHz
            2'b10: period = 125;    // 8 GHz
            2'b11: period = 62.5;   // 16 GHz
            default: period = 500;
        endcase
    end

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
            case (speed_sel)
                2'b00: local_period = 500;
                2'b01: local_period = 250;
                2'b10: local_period = 125;
                2'b11: local_period = 62.5;
                default: local_period = 500;
            endcase

            // Toggle clock every half period
            #(local_period/2) clk = ~clk;
        end
    end

endmodule