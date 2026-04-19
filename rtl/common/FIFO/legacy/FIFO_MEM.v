module FIFO_MEM #( 
    parameter   DATA_WIDTH = 8,
                ADDR_WIDTH = 3
) (
    input                          wclk,
    input                          wrst_n,
    input                          winc,
    input                          wfull,
    input      [ADDR_WIDTH-1:0]    waddr,
    input      [ADDR_WIDTH-1:0]    raddr, 
    input      [DATA_WIDTH-1:0]    wdata,
    output reg [DATA_WIDTH-1:0]    rdata 
);

    // Declare the memory array
    reg [DATA_WIDTH-1:0] mem [(1<<ADDR_WIDTH)-1:0];
    
    integer i;
    // Write operation
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            for (i = 0; i <(1<<ADDR_WIDTH) ; i=i+1 ) begin
                mem [i] <= 'b0;
            end
        end
        else if (winc && !wfull) begin
            mem[waddr] <= wdata;
        end
    end

    // Read operation
    always @(*) begin
        rdata = mem[raddr];
    end
endmodule
