`timescale 1ns/1ps
// =============================================================================
// Module  : axis_master_from_mb_rx
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : AXI4-Stream MASTER (source) driven by the MainBand RX flit interface
//           (the digital_ucie / digital_mb demapper face).  Received flits are
//           streamed out to a DMA's S2MM channel; each AXIS beat is one flit.
//
// MainBand RX behaviour (unit_demapper):
//     pl_valid is a SINGLE-CYCLE pulse carrying pl_data for one received flit,
//     and the PHY RX CANNOT be back-pressured (there is no "rx_ready").
//     Therefore this module buffers incoming flits in a small synchronous FIFO
//     and drains them onto AXIS at the DMA's pace.
//
//   NOTE: pl_error is intentionally NOT handled here - it is an RDI_SM signal,
//   not part of the MainBand datapath.  The RDI interface is brought out on GPIO
//   directly to the processor (for SW link-management during training), so it
//   does not travel on the data stream.
//
//   o_overflow is a STICKY flag: it sets if a flit arrives while the FIFO is
//   full (i.e. the DMA could not keep up and a flit was dropped).  Surface it to
//   software / an LED so silent data loss is visible.
//
// AXIS mapping:
//     m_axis_tdata  = flit data        (FLIT_W == TDATA_W, no width conversion)
//     m_axis_tkeep  = all ones         (full-width beats only)
//     m_axis_tlast  = 1 per flit       (when TLAST_PER_FLIT=1) so each flit is a
//                                       self-contained AXIS packet/descriptor
//     m_axis_tvalid = FIFO not empty
//   pop on (m_axis_tvalid && m_axis_tready).
// =============================================================================

module axis_master_from_mb_rx #(
    parameter int FLIT_W         = 512,          // MainBand flit width (8*N_BYTES)
    parameter int TDATA_W        = FLIT_W,       // AXIS data width (must equal FLIT_W)
    parameter int TKEEP_W        = TDATA_W/8,
    parameter int FIFO_DEPTH     = 8,            // power of 2, absorbs RX bursts
    parameter bit TLAST_PER_FLIT = 1'b1
)(
    input  logic                 clk,            // MainBand word clock (lclk)
    input  logic                 rst_n,

    // ---- MainBand RX flit interface (<- digital_ucie pl_* face) ----
    input  logic [FLIT_W-1:0]    pl_data,
    input  logic                 pl_valid,

    // ---- AXI4-Stream master (to DMA S2MM) ----
    output logic [TDATA_W-1:0]   m_axis_tdata,
    output logic [TKEEP_W-1:0]   m_axis_tkeep,
    output logic                 m_axis_tlast,
    output logic                 m_axis_tvalid,
    input  logic                 m_axis_tready,

    // ---- Status ----
    output logic                 o_overflow      // sticky: a flit was dropped
);

    localparam int AW = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

    // Compile-time guard: this bridge does no width conversion.
    initial begin
        if (TDATA_W != FLIT_W)
            $error("axis_master_from_mb_rx: TDATA_W (%0d) must equal FLIT_W (%0d)",
                   TDATA_W, FLIT_W);
    end

    // -------------------------------------------------------------------------
    // Small synchronous FIFO
    // -------------------------------------------------------------------------
    logic [FLIT_W-1:0]  mem [0:FIFO_DEPTH-1];
    logic [AW-1:0]      wr_ptr, rd_ptr;
    logic [AW:0]        count;                   // 0 .. FIFO_DEPTH

    wire full  = (count == FIFO_DEPTH);
    wire empty = (count == 0);

    wire do_push = pl_valid && !full;
    wire do_pop  = m_axis_tvalid && m_axis_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= '0;
            rd_ptr     <= '0;
            count      <= '0;
            o_overflow <= 1'b0;
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= pl_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (do_pop) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            // count update (push and pop can happen in the same cycle)
            case ({do_push, do_pop})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;        // 00 or 11: no net change
            endcase

            // sticky overflow: flit arrived while full (dropped)
            if (pl_valid && full)
                o_overflow <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // AXIS master outputs (drain side)
    // -------------------------------------------------------------------------
    assign m_axis_tvalid = !empty;
    assign m_axis_tdata  = mem[rd_ptr];
    assign m_axis_tkeep  = {TKEEP_W{1'b1}};
    assign m_axis_tlast  = TLAST_PER_FLIT;

endmodule
