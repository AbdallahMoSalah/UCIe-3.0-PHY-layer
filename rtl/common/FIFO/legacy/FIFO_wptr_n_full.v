module FIFO_wptr_n_full  #(
    parameter ADDR_WIDTH = 3
) (
    wire wclk,
    wire wrst_n,
    wire winc,
    wire [ADDR_WIDTH:0] wq2_rptr,
    output reg wfull,
    output [ADDR_WIDTH-1:0] waddr,
    output reg [ADDR_WIDTH:0] Gwptr // Gray coded write pointer
);
    reg [ADDR_WIDTH:0] wptr; // Binary write pointer
    wire [ADDR_WIDTH:0] comb_Gwptr;
    assign waddr = wptr[ADDR_WIDTH-1:0]; // address is lower bits of wptr

    assign comb_Gwptr = (wptr>>1) ^ wptr; // Binary to Gray code conversion

    always @(*) begin
    if ( {~comb_Gwptr[ADDR_WIDTH:2],comb_Gwptr[1:0]}== wq2_rptr ) begin
                wfull <= 1'b1;
            end else begin
                wfull <= 1'b0;
            end
    end  

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr <= 'b0;
        end else if (winc && !wfull) begin
            wptr <= wptr + 1'b1;
            end
    end
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            Gwptr <= 'b0;
        end else begin
            Gwptr <= comb_Gwptr;
        end
    end

endmodule