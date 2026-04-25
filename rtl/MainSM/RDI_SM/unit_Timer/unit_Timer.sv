//-----------------------------------------------------------------------------
// Module      : unit_Timer
// Description : Dual-purpose timer for UCIe PHY layer. Provides 16ms and 1us 
//               timeout signals used for handshake synchronization and power 
//               state transitions (L1/L2 entry).
//-----------------------------------------------------------------------------

module unit_Timer #(
    parameter int CLK_FREQ = 2_000_000_000  // Default clock frequency: 2GHz
) (
    input  logic lclk,              // Local clock
    input  logic rst_n,             // Asynchronous active-low reset
    input  logic start_time_16ms,   // Start/Enable 16ms timer (held high to run)
    input  logic start_time_1us,    // Start/Enable 1us timer (held high to run)

    output logic time_16ms,         // High when 16ms have elapsed
    output logic time_1us           // High when 1us has elapsed
);

    // Calculate cycle counts based on clock frequency
    // Using real arithmetic for precision before casting to integer
    localparam int T16MS_LIMIT = int'(16e-3*real'(CLK_FREQ))-1;
    localparam int T1US_LIMIT  = int'(1e-6*real'(CLK_FREQ))-1;

    // Internal counters
    logic [31:0] counter_16ms;
    logic [31:0] counter_1us;

    // --- 16ms Timer Logic ---
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            counter_16ms <= T16MS_LIMIT;
        end else if (!start_time_16ms) begin
            // Reset counter when start signal is low
            counter_16ms <= T16MS_LIMIT;
        end else if (counter_16ms > 0) begin
            // Down-count until zero
            counter_16ms <= counter_16ms - 1;
        end
    end

    // --- 1us Timer Logic ---
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            counter_1us <= T1US_LIMIT;
        end
        else if (!start_time_1us) begin
            // Reset counter when start signal is low
            counter_1us <= T1US_LIMIT;
        end
        else if (counter_1us > 0) begin
            // Down-count until zero
            counter_1us <= counter_1us - 1;
        end
    end

    // Output assignment: high when counter reached zero
    assign time_16ms = (counter_16ms == 0);
    assign time_1us  = (counter_1us == 0);

endmodule