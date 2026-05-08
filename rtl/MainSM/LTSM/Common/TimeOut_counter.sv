module timeout_counter
#(parameter int CLK_FRQ_HZ = 800000000,
  parameter int TIME_OUT = 8
)
(
    input  logic clk , timeout_rst_n,
    input  logic enable_timeout,
    output logic timeout_expired
);


localparam int TIME_OUT_CYCLES = (CLK_FRQ_HZ/1000) * TIME_OUT;                //Time out in clock cycles.
localparam int TIMEOUT_COUNTER_WIDTH = $clog2(TIME_OUT_CYCLES + 1);    //Calc the width of the counter.

logic [TIMEOUT_COUNTER_WIDTH-1 : 0] timeout_counter ;

always_ff @( posedge clk , negedge timeout_rst_n )
 begin : TIMEOUT_LOGIC
    if(!timeout_rst_n)
        timeout_counter <= '0 ;
    else if(enable_timeout)
        timeout_counter <= timeout_counter + 1;
    else
        timeout_counter <= '0 ;
end

assign timeout_expired = (timeout_counter == TIME_OUT_CYCLES-1 );
endmodule
