// =============================================================================
// Module  : tri_state_buffer
// Project : UCIe 3.0 Main-Band Physical Layer
// Purpose : Wrapper bundling all Main-Band TX output tri-state buffers
//           (16 data lanes + valid + clk_p + clk_n + track) into a single
//           block. Each output is driven through a tri_state_buff cell whose
//           2-bit enable selects {Hi-Z, drive, 0}.
//
//           This is a pure structural grouping of the tri_state_buff cells
//           that previously lived directly in unit_mb_die; the per-cell wiring
//           is unchanged.
// =============================================================================

module tri_state_buffer #(
    parameter int NUM_LANES = 16
)(
    // ---- pre-tri-state serial inputs (from the TX serializers / clk gen) ----
    input  logic [NUM_LANES-1:0] i_TD_P,
    input  logic                 i_TVLD_P,
    input  logic                 i_TCKP_P,
    input  logic                 i_TCKN_P,
    input  logic                 i_TTRK_P,

    // ---- per-group tri-state enables ----------------------------------------
    input  logic [1:0]           i_mb_tx_data_lane_sel,
    input  logic [1:0]           i_mb_tx_val_lane_sel,
    input  logic [1:0]           i_mb_tx_clk_lane_sel,
    input  logic [1:0]           i_mb_tx_trk_lane_sel,

    // ---- tri-stated serial outputs (to the partner RX) ----------------------
    output logic [NUM_LANES-1:0] o_TD_P,
    output logic                 o_TVLD_P,
    output logic                 o_TCKP_P,
    output logic                 o_TCKN_P,
    output logic                 o_TTRK_P
);

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin : gen_data_ser
            tri_state_buff u_tri_state_buff_data (
                .data_in (i_TD_P[lane_idx]),
                .en      (i_mb_tx_data_lane_sel),
                .data_out(o_TD_P[lane_idx])
            );
        end
    endgenerate

    tri_state_buff u_tri_state_buff_valid (
        .data_in (i_TVLD_P),
        .en      (i_mb_tx_val_lane_sel),
        .data_out(o_TVLD_P)
    );

    tri_state_buff u_tri_state_buff_clk_p (
        .data_in (i_TCKP_P),
        .en      (i_mb_tx_clk_lane_sel),
        .data_out(o_TCKP_P)
    );

    tri_state_buff u_tri_state_buff_clk_n (
        .data_in (i_TCKN_P),
        .en      (i_mb_tx_clk_lane_sel),
        .data_out(o_TCKN_P)
    );

    tri_state_buff u_tri_state_buff_track (
        .data_in (i_TTRK_P),
        .en      (i_mb_tx_trk_lane_sel),
        .data_out(o_TTRK_P)
    );

endmodule
