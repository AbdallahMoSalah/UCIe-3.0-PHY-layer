`timescale 1ns/1ps
// =============================================================================
// Module      : fifo
// Description : Generic parameterizable FIFO.
//
//   Parameters
//   ----------
//   DATA_WIDTH : Width of the data bus (default 8)
//   ADDR_WIDTH : Depth = 2^ADDR_WIDTH entries (default 4 → 16 entries)
//   ASYNC      : 1 = Asynchronous FIFO (independent clocks, Gray-code pointers,
//                    2-FF synchronizers)
//                0 = Synchronous FIFO  (single clock domain, no synchronizers)
//
//   Port guide when ASYNC = 0
//   --------------------------
//   - R_CLK and RRST_N are still present but are ignored internally;
//     tie them to W_CLK / WRST_N at the instantiation site to keep things
//     clean (or simply leave them unconnected — synthesis will prune them).
//
// =============================================================================
module fifo #(
    parameter int  DATA_WIDTH = 8,
    parameter int  ADDR_WIDTH = 4,
    parameter bit  ASYNC      = 1   // 1 = async, 0 = sync
) (
    // Write-clock domain
    input  logic                    W_CLK,
    input  logic                    WRST_N,
    input  logic                    WINC,
    input  logic [DATA_WIDTH-1:0]   WR_DATA,
    output logic                    WFULL,
    output logic                    WREADY,    // = ~WFULL  (handshake-friendly)

    // Read-clock domain  (tie to W_CLK / WRST_N when ASYNC=0)
    input  logic                    R_CLK,
    input  logic                    RRST_N,
    input  logic                    RINC,
    output logic [DATA_WIDTH-1:0]   RD_DATA,
    output logic                    REMPTY,
    output logic                    RVALID     // = ~REMPTY (handshake-friendly)
);

    // -----------------------------------------------------------------------
    // Internal wires
    // -----------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] waddr, raddr;
    logic [ADDR_WIDTH:0]   wptr_gray, rptr_gray;   // Gray-coded pointers

    // Wires that carry the pointer seen by each domain's full/empty logic.
    // In ASYNC mode these come from synchronizers.
    // In SYNC mode we short-circuit: wq2_rptr = rptr_gray (= binary rptr in
    //   sync mode, since we pass the binary pointer directly and the
    //   fifo_*ptr_* modules detect sync mode via their ASYNC parameter).
    logic [ADDR_WIDTH:0] wq2_rptr;   // rptr as seen in write-clock domain
    logic [ADDR_WIDTH:0] rq2_wptr;   // wptr as seen in read-clock domain

    // -----------------------------------------------------------------------
    // Write-pointer & full flag
    // -----------------------------------------------------------------------
    fifo_wptr_full #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_wptr_full (
        .wclk       (W_CLK),
        .wrst_n     (WRST_N),
        .winc       (WINC),
        .wq2_rptr   (wq2_rptr),
        .wfull      (WFULL),
        .waddr      (waddr),
        .wptr_gray  (wptr_gray)
    );

    // -----------------------------------------------------------------------
    // Read-pointer & empty flag
    // -----------------------------------------------------------------------
    fifo_rptr_empty #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_rptr_empty (
        .rclk       (R_CLK),
        .rrst_n     (RRST_N),
        .rinc       (RINC),
        .rq2_wptr   (rq2_wptr),
        .rempty     (REMPTY),
        .raddr      (raddr),
        .rptr_gray  (rptr_gray)
    );

    // -----------------------------------------------------------------------
    // Dual-port memory
    // -----------------------------------------------------------------------
    fifo_mem #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_mem (
        .wclk   (W_CLK),
        .wrst_n (WRST_N),
        .winc   (WINC),
        .wfull  (WFULL),
        .waddr  (waddr),
        .raddr  (raddr),
        .wdata  (WR_DATA),
        .rdata  (RD_DATA)
    );

    // -----------------------------------------------------------------------
    // Clock-domain-crossing synchronizers
    //   ASYNC = 1 : instantiate 2-FF synchronizers for both pointers
    //   ASYNC = 0 : wire pointers directly (no clock crossing needed)
    // -----------------------------------------------------------------------
    generate
        if (ASYNC) begin : g_async

            // Sync Gray-coded read pointer into write-clock domain
            fifo_sync_2ff #(.ADDR_WIDTH(ADDR_WIDTH)) u_sync_rptr (
                .clk      (W_CLK),
                .rst_n    (WRST_N),
                .sync_in  (rptr_gray),
                .sync_out (wq2_rptr)
            );

            // Sync Gray-coded write pointer into read-clock domain
            fifo_sync_2ff #(.ADDR_WIDTH(ADDR_WIDTH)) u_sync_wptr (
                .clk      (R_CLK),
                .rst_n    (RRST_N),
                .sync_in  (wptr_gray),
                .sync_out (rq2_wptr)
            );

        end else begin : g_sync

            // No synchronizers needed — wire Gray-coded pointers directly.
            // Both sub-modules use Gray-code comparison for full/empty,
            // which is safe here because wptr and rptr are in the same domain.
            assign wq2_rptr = rptr_gray;
            assign rq2_wptr = wptr_gray;

        end
    endgenerate

    // -----------------------------------------------------------------------
    // Handshake-friendly aliases
    // -----------------------------------------------------------------------
    assign WREADY = ~WFULL;   // writer may push  when WREADY=1
    assign RVALID = ~REMPTY;  // reader may pop   when RVALID=1

/*    // -----------------------------------------------------------------------
    // Debug Monitors
    // -----------------------------------------------------------------------
    // synthesis translate_off
    always_ff @(posedge W_CLK) begin
        if (WINC && !WFULL) begin
            $display("[%0t] [FIFO %m] WRITE waddr=%0d wdata=%h", $time, waddr, WR_DATA);
        end
    end

    always_ff @(posedge R_CLK) begin
        if (RINC && !REMPTY) begin
            $display("[%0t] [FIFO %m] READ raddr=%0d", $time, raddr);
        end
    end
    // synthesis translate_on
*/
endmodule
