// =============================================================================
// Module      : fifo_wptr_full
// Description : Write-pointer and full-flag logic.
//               - ASYNC=1 : Gray-coded pointer is exposed for cross-domain
//                           synchronization.  Full flag uses 2-stage synced
//                           read pointer (wq2_rptr).
//               - ASYNC=0 : Single clock domain.  Binary comparison against
//                           the binary read pointer (wq2_rptr carries rptr).
//                           Gray outputs are unused (tied to '0 externally).
// =============================================================================
module fifo_wptr_full #(
    parameter int  ADDR_WIDTH = 4
) (
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [ADDR_WIDTH:0]   wq2_rptr,   // synced read pointer (Gray if ASYNC, Binary if SYNC)
    output logic                  wfull,
    output logic [ADDR_WIDTH-1:0] waddr,
    output logic [ADDR_WIDTH:0]   wptr_gray   // Gray-coded write pointer (used only in ASYNC mode)
);

    logic [ADDR_WIDTH:0] wptr;          // Binary write pointer
    logic [ADDR_WIDTH:0] wptr_gray_comb;

    // Binary → Gray conversion
    assign wptr_gray_comb = (wptr >> 1) ^ wptr;
    assign waddr          = wptr[ADDR_WIDTH-1:0];

    // ------------------------------------------------------------------
    // Full flag
    //   ASYNC : compare ~Gray(wptr)[MSBs] vs synced Gray(rptr)  [2-FF sync]
    //   SYNC  : same comparison, wq2_rptr = Gray(rptr) from same domain
    //   The top two bits of the next Gray-coded write pointer are inverted
    //   vs. the wrapped read pointer when the FIFO is full.
    // ------------------------------------------------------------------
    assign wfull = ({~wptr_gray_comb[ADDR_WIDTH : ADDR_WIDTH-1],
                      wptr_gray_comb[ADDR_WIDTH-2 : 0]} == wq2_rptr);

    // ------------------------------------------------------------------
    // Write pointer register
    // ------------------------------------------------------------------
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n)
            wptr <= '0;
        else if (winc && !wfull)
            wptr <= wptr + 1'b1;
    end

    // ------------------------------------------------------------------
    // Gray-coded write pointer register (used by synchronizer in ASYNC mode)
    // ------------------------------------------------------------------
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n)
            wptr_gray <= '0;
        else
            wptr_gray <= wptr_gray_comb;
    end

endmodule
