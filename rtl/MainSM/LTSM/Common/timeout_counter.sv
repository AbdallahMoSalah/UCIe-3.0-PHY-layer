module timeout_counter
#(parameter int CLK_FRQ_HZ  = 125_000_000,
  parameter int TIME_OUT    = 8,          // timeout in ms
  parameter bit SPEED_AWARE = 1'b1        // 1: derive the timeout from speed_sel
                                          //    (real gated_lclk = mb_PLL/16) so it
                                          //    is a TRUE TIME_OUT ms at any speed,
                                          //    independent of a scaled CLK_FRQ_HZ.
                                          // 0: legacy fixed CLK_FRQ_HZ scaling.
)
(
    input  logic       clk , timeout_rst_n,
    input  logic       enable_timeout,
    input  logic [2:0] speed_sel,         // mb_PLL speed select (used iff SPEED_AWARE)
    output logic       timeout_expired
);

// ---------------------------------------------------------------------------
// gated_lclk = mb_PLL(speed_sel)/16  (unit_clkdiv i_div_ratio = 16)
//   speed_sel[1:0]: 00=2GHz 01=4GHz 10=8GHz 11=16GHz  (PLL 500/250/125/62.5 ps)
//   gated_lclk     :        125 /250 /500 /1000 MHz
//   timeout cycles = gated_freq_kHz * TIME_OUT(ms)
// ---------------------------------------------------------------------------
function automatic int unsigned gated_freq_khz(input logic [2:0] sel);
    case (sel)
        3'b000: gated_freq_khz = 125_000;  // 2/16 GHz
        3'b001: gated_freq_khz = 250_000;  // 4/16 GHz
        3'b010: gated_freq_khz = 375_000;  // 6/16 GHz
        3'b011: gated_freq_khz = 500_000;  // 8/16 GHz
        3'b100: gated_freq_khz = 750_000;  // 12/16 GHz
        3'b101: gated_freq_khz = 1_000_000; // 16/16 GHz
        default: gated_freq_khz = 125_000;  // 2/16 GHz (2 GHz / 16)
    endcase
endfunction

// Static (legacy) threshold from the parameterised clock frequency.
localparam int STATIC_CYCLES = (CLK_FRQ_HZ/1000) * TIME_OUT;

// Counter must hold the largest possible threshold.  For SPEED_AWARE that is
// the fastest gated clock (1 GHz); otherwise the static value.
localparam int MAX_CYCLES = SPEED_AWARE ? (1_000_000 * TIME_OUT) : STATIC_CYCLES;
localparam int TIMEOUT_COUNTER_WIDTH = $clog2(MAX_CYCLES + 1);

logic [TIMEOUT_COUNTER_WIDTH-1 : 0] timeout_counter ;

// Runtime threshold: speed-derived when SPEED_AWARE, else the static value.
wire [31:0] threshold = SPEED_AWARE ? (gated_freq_khz(speed_sel) * TIME_OUT)
                                    : STATIC_CYCLES;

always_ff @( posedge clk , negedge timeout_rst_n )
 begin : TIMEOUT_LOGIC
    if(!timeout_rst_n)
        timeout_counter <= '0 ;
    else if(enable_timeout)
        timeout_counter <= timeout_counter + 1;
    else
        timeout_counter <= '0 ;
end

assign timeout_expired = (32'(timeout_counter) == threshold - 1);
endmodule
