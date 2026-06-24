`timescale 1ns/1ps
// =============================================================================
// Module  : axis_slave_to_mb_tx
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : AXI4-Stream SLAVE (sink) that feeds the MainBand TX flit interface
//           (the digital_ucie / digital_mb mapper face).  A DMA's MM2S channel
//           streams flits in here; each AXIS beat is one MainBand flit.
//
// MainBand TX handshake (unit_mapper):
//     a flit is accepted when  lp_valid && lp_irdy && pl_trdy
//   which is a plain VALID/READY handshake:
//     lp_valid , lp_irdy  <- producer side (AXIS tvalid)
//     pl_trdy             -> consumer ready (AXIS tready)
//
// Mapping (1 AXIS beat == 1 flit, equal widths):
//     lp_data  = s_axis_tdata
//     lp_valid = s_axis_tvalid
//     lp_irdy  = s_axis_tvalid
//     s_axis_tready = pl_trdy
//
//   => transfer occurs on (s_axis_tvalid && pl_trdy), identical to the mapper's
//      push condition.  Purely combinational; s_axis_tready does not depend on
//      s_axis_tvalid, so there is no combinational handshake loop.
//
// TLAST/TKEEP are accepted for DMA compatibility but unused: the MainBand flit
// is a fixed-width (FLIT_W) word with no partial-beat / framing concept here.
// If you later need a registered boundary for timing, drop a standard AXIS skid
// buffer in front of this module.
// =============================================================================

module axis_slave_to_mb_tx #(
    parameter int FLIT_W   = 512,            // MainBand flit width (8*N_BYTES)
    parameter int TDATA_W  = FLIT_W,         // AXIS data width (must equal FLIT_W)
    parameter int TKEEP_W  = TDATA_W/8
)(
    input  logic                 clk,        // MainBand word clock (lclk)
    input  logic                 rst_n,

    // ---- AXI4-Stream slave (from DMA MM2S) ----
    input  logic [TDATA_W-1:0]   s_axis_tdata,
    input  logic [TKEEP_W-1:0]   s_axis_tkeep,   // accepted, unused
    input  logic                 s_axis_tlast,   // accepted, unused
    input  logic                 s_axis_tvalid,
    output logic                 s_axis_tready,

    // ---- MainBand TX flit interface (-> digital_ucie lp_* face) ----
    output logic [FLIT_W-1:0]    lp_data,
    output logic                 lp_valid,
    output logic                 lp_irdy,
    input  logic                 pl_trdy
);

    // Compile-time guard: this bridge does no width conversion.
    initial begin
        if (TDATA_W != FLIT_W)
            $error("axis_slave_to_mb_tx: TDATA_W (%0d) must equal FLIT_W (%0d)",
                   TDATA_W, FLIT_W);
    end

    // Unused inputs (kept on the port list for DMA/AXIS compatibility).
    wire _unused_ok = &{1'b0, s_axis_tkeep, s_axis_tlast, rst_n};

    assign lp_data       = s_axis_tdata;
    assign lp_valid      = s_axis_tvalid;
    assign lp_irdy       = s_axis_tvalid;
    assign s_axis_tready = pl_trdy;

endmodule
