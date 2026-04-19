module FIFO_rptr_n_empty #(
    parameter ADDR_WIDTH = 3
) (
    input rclk,
    input rrst_n,
    input rinc,
    input [ADDR_WIDTH:0] rq2_wptr,
    output reg rempty,
    output [ADDR_WIDTH-1:0] raddr,
    output reg [ADDR_WIDTH:0] Grptr // Gray coded read pointer
);
    reg [ADDR_WIDTH:0] rptr; // Binary read pointer
    wire [ADDR_WIDTH:0] comb_Grptr;
    assign raddr = rptr[ADDR_WIDTH-1:0]; // address is lower bits of rptr

    assign comb_Grptr = (rptr>>1) ^ rptr; // Binary to Gray code conversion

    always @(*) begin
        if ( comb_Grptr == rq2_wptr ) begin
            rempty <= 1'b1;
        end else begin
            rempty <= 1'b0;
        end
    end    

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rptr <= 'b0;
        end else if (rinc && !rempty) begin
            rptr <= rptr + 1'b1;
        end
    end
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            Grptr <= 'b0;
        end else begin
            Grptr <= comb_Grptr;
        end
    end

endmodule