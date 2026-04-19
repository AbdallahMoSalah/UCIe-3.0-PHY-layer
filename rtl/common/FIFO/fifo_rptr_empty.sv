// =============================================================================
// Module      : fifo_rptr_empty
// Description : Read-pointer and empty-flag logic.
//               - ASYNC=1 : Gray-coded pointer exposed for cross-domain sync.
//                           Empty flag uses 2-stage synced write pointer.
//               - ASYNC=0 : Single clock domain.  Binary comparison.
// =============================================================================
module fifo_rptr_empty #(
    parameter int  ADDR_WIDTH = 4
) (
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    input  logic [ADDR_WIDTH:0]   rq2_wptr,   // synced write pointer (Gray if ASYNC, Binary if SYNC)
    output logic                  rempty,
    output logic [ADDR_WIDTH-1:0] raddr,
    output logic [ADDR_WIDTH:0]   rptr_gray   // Gray-coded read pointer (used only in ASYNC mode)
);

    logic [ADDR_WIDTH:0] rptr;          // Binary read pointer
    logic [ADDR_WIDTH:0] rptr_gray_comb;

    // Binary → Gray conversion
    assign rptr_gray_comb = (rptr >> 1) ^ rptr;
    assign raddr          = rptr[ADDR_WIDTH-1:0];

    // ------------------------------------------------------------------
    // Empty flag
    //   ASYNC : Gray(rptr_comb) == synced Gray(wptr)  [2-FF sync]
    //   SYNC  : Gray(rptr_comb) == Gray(wptr)          [same domain, valid]
    //   In both modes rq2_wptr carries a Gray-coded write pointer.
    // ------------------------------------------------------------------
    assign rempty = (rptr_gray_comb == rq2_wptr);

    // ------------------------------------------------------------------
    // Read pointer register
    // ------------------------------------------------------------------
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)
            rptr <= '0;
        else if (rinc && !rempty)
            rptr <= rptr + 1'b1;
    end

    // ------------------------------------------------------------------
    // Gray-coded read pointer register (used by synchronizer in ASYNC mode)
    // ------------------------------------------------------------------
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)
            rptr_gray <= '0;
        else
            rptr_gray <= rptr_gray_comb;
    end

endmodule
