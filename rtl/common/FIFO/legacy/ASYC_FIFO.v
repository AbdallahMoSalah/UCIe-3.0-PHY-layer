module ASYC_FIFO #(
    parameter ADDR_WIDTH = 4,
    parameter DATA_WIDTH = 8
) (
    input W_CLK,
    input R_CLK,
    input WRST_N,
    input RRST_N,
    input WINC,
    input RINC,
    input [DATA_WIDTH-1:0] WR_DATA,
    output [DATA_WIDTH-1:0] RD_DATA,
    output FULL,
    output EMPTY
);
    wire [ADDR_WIDTH-1:0] waddr, raddr;
    wire [ADDR_WIDTH:0] wq2_rptr, rq2_wptr;
    wire [ADDR_WIDTH:0] Gwptr, Grptr;

    FIFO_wptr_n_full #(.ADDR_WIDTH(ADDR_WIDTH)) U1 (
        .wclk(W_CLK),
        .wrst_n(WRST_N),
        .winc(WINC),
        .wq2_rptr(wq2_rptr),
        .wfull(FULL),
        .waddr(waddr),
        .Gwptr(Gwptr)
    );
    FIFO_rptr_n_empty #(.ADDR_WIDTH(ADDR_WIDTH)) U2 (
        .rclk(R_CLK),
        .rrst_n(RRST_N),
        .rinc(RINC),
        .rq2_wptr(rq2_wptr),
        .rempty(EMPTY),
        .raddr(raddr),
        .Grptr(Grptr)
    );
    FIFO_MEM #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) U3 (
        .wclk(W_CLK),
        .wrst_n(WRST_N),
        .winc(WINC),
        .wfull(FULL),
        .waddr(waddr),
        .raddr(raddr),
        .wdata(WR_DATA),
        .rdata(RD_DATA)
    );
    // Synchronizer for read pointer in write clock domain
    synchronizer #(.ADDR_WIDTH(ADDR_WIDTH)) U4 (
        .clk(W_CLK),
        .rst_n(WRST_N),
        .sync_in(Grptr),
        .sync_reg(wq2_rptr)
    );
    // Synchronizer for write pointer in read clock domain
    synchronizer #(.ADDR_WIDTH(ADDR_WIDTH)) U5 (
        .clk(R_CLK),
        .rst_n(RRST_N),
        .sync_in(Gwptr),
        .sync_reg(rq2_wptr)
    );
endmodule
