`timescale 1ps/1ps
// =============================================================================
// Module  : mb_die
// Project : UCIe 3.0 Main-Band Physical Layer
// Purpose : Single-die wrapper exposing separate TX and RX pad interfaces.
//
//   Unlike MB_TOP (which loops TX back to RX internally), mb_die exposes
//   all TX pads as outputs and all RX pads as inputs.  Two mb_die instances
//   wired back-to-back model a full die-to-die link:
//
//     die0.o_TD_P  → die1.i_RD_P      (die0 TX data → die1 RX)
//     die1.o_TD_P  → die0.i_RD_P      (die1 TX data → die0 RX)
//     (same for VLD, CKP, CKN, TRK lanes)
//
//  Internally the die has one PLL + ClkDiv (inside MB_TX_TOP), one MB_TX_TOP,
//  and one MB_RX_TOP.  Both share the same pll_clk and mb_clk.
//
//  RX pipeline compensation
//  ------------------------
//   i_active_state_entered is delayed by RX_ACTIVE_DELAY mb_clk cycles before
//   being presented to MB_RX_TOP, accounting for serialization + CDC latency.
//   rx_data_valid is similarly delayed by RX_VALID_DELAY cycles when
//   i_descramble_en is asserted.
// =============================================================================

module mb_die #(
    parameter DATA_WIDTH = 32,
    parameter NUM_LANES  = 16,
    parameter N_BYTES    = 64
)(
    // ── Global ─────────────────────────────────────────────────────────────
    input  logic                    i_rst_n,
    input  logic                    i_pll_en,
    input  logic [1:0]              i_pll_speed_sel,

    // ── Clock outputs ───────────────────────────────────────────────────────
    output logic                    o_pll_clk,
    output logic                    o_mb_clk,

    // ── TX Mapper ───────────────────────────────────────────────────────────
    input  logic [8*N_BYTES-1:0]    lp_data,
    input  logic                    i_mapper_en,
    input  logic                    i_lp_irdy,
    input  logic                    i_lp_valid,
    output logic                    o_mapper_ready,

    // ── TX LFSR / Training ──────────────────────────────────────────────────
    input  logic [2:0]              i_width_deg_tx,
    input  logic [2:0]              i_lfsr_state,        // LTSM state for TX LFSR
    input  logic                    i_reversal_en,
    input  logic                    i_active_state_entered,
    output logic                    o_lfsr_tx_done,

    // ── TX Valid ────────────────────────────────────────────────────────────
    input  logic                    i_valid_pattern_en,
    output logic                    o_valid_done,

    // ── TX CLK pattern ──────────────────────────────────────────────────────
    input  logic                    i_clk_pattern_en,
    input  logic                    i_clk_embedded_en,
    output logic                    o_clk_done,

    // ── TX Pad outputs (to partner die RX) ─────────────────────────────────
    output logic [NUM_LANES-1:0]    o_TD_P,      // Data lanes
    output logic                    o_TVLD_P,    // Valid lane
    output logic                    o_TCKP_P,    // Clock +
    output logic                    o_TCKN_P,    // Clock −
    output logic                    o_TTRK_P,    // Track

    // ── RX Pad inputs (from partner die TX) ────────────────────────────────
    input  logic [NUM_LANES-1:0]    i_RD_P,      // Data lanes
    input  logic                    i_RVLD_P,    // Valid lane
    input  logic                    i_RCKP_P,    // Clock +
    input  logic                    i_RCKN_P,    // Clock −
    input  logic                    i_RTRK_P,    // Track

    // ── RX LFSR / Training ──────────────────────────────────────────────────
    input  logic [2:0]              i_state,             // LTSM state for RX LFSR
    input  logic [2:0]              i_width_deg_rx,
    input  logic                    i_descramble_en,
    input  logic                    i_enable_buffer,

    // ── RX CLK detector ─────────────────────────────────────────────────────
    input  logic                    i_clk_detector_en,

    // ── RX Valid detector ───────────────────────────────────────────────────
    input  logic [11:0]             i_max_err_valid,
    input  logic                    i_enable_cons,
    input  logic                    i_enable_128,
    input  logic                    i_enable_detector,

    // ── RX Pattern comparator ───────────────────────────────────────────────
    input  logic [1:0]              i_type_of_com,
    input  logic [15:0]             i_max_err_per_lane,
    input  logic [15:0]             i_max_err_agg,

    // ── RX Demapper ─────────────────────────────────────────────────────────
    input  logic                    demapper_en,
    input  logic                    rx_data_valid,

    // ── RX Status outputs ───────────────────────────────────────────────────
    output logic                    de_ser_done,
    output logic                    detection_result,
    output logic                    o_valid_frame_detect,
    output logic [15:0]             o_per_lane_error,
    output logic [31:0]             o_error_counter,
    output logic                    o_error_done,
    output logic                    clk_p_pattern_pass,
    output logic                    clk_n_pattern_pass,
    output logic                    track_pattern_pass,
    output logic                    pl_valid,
    output logic [8*N_BYTES-1:0]    o_out_data
);

    // =========================================================================
    // Internal PLL period wire
    // =========================================================================
    real w_period;

    // =========================================================================
    // RX pipeline compensation
    //   RX_ACTIVE_DELAY : MB_clk cycles from TX asserting active_state_entered
    //                     to when the first serialised flit word reaches the RX
    //                     deserialiser output — accounts for:
    //                       1 MB_clk serialisation pipeline +
    //                       ~3 MB_clk CDC + deserialiser latency.
    //   RX_VALID_DELAY  : Additional delay on rx_data_valid to let the
    //                     descrambled output settle before the Demapper reads it.
    // =========================================================================
    localparam int RX_ACTIVE_DELAY = 3;
    localparam int RX_VALID_DELAY  = 5;

    logic [7:0] active_delay_reg;
    logic       rx_active_gated;

    always_ff @(posedge o_mb_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            active_delay_reg <= 8'd0;
        else
            active_delay_reg <= {active_delay_reg[6:0], i_active_state_entered};
    end
    assign rx_active_gated = active_delay_reg[RX_ACTIVE_DELAY];

    logic [7:0] rx_dv_delay_reg;
    logic       rx_data_valid_gated;

    always_ff @(posedge o_mb_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            rx_dv_delay_reg <= 8'd0;
        else
            rx_dv_delay_reg <= {rx_dv_delay_reg[6:0], rx_data_valid};
    end
    assign rx_data_valid_gated =
        i_descramble_en ? rx_dv_delay_reg[RX_VALID_DELAY] : rx_data_valid;

    // =========================================================================
    // MB_TX_TOP  (includes MB_PLL + ClkDiv internally)
    // =========================================================================
    MB_TX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES),
        .N_BYTES    (N_BYTES)
    ) u_tx (
        .i_rst_n                (i_rst_n),

        // PLL
        .i_pll_en               (i_pll_en),
        .i_pll_speed_sel        (i_pll_speed_sel),
        .o_pll_clk              (o_pll_clk),
        .period                 (w_period),

        // Mapper
        .i_raw_data             (lp_data),
        .i_mapper_en            (i_mapper_en),
        .i_width_deg            (i_width_deg_tx),
        .i_lp_irdy              (i_lp_irdy),
        .i_lp_valid             (i_lp_valid),
        .o_mapper_ready         (o_mapper_ready),

        // LFSR_TX
        .i_lfsr_state           (i_lfsr_state),
        .i_reversal_en          (i_reversal_en),
        .i_active_state_entered (i_active_state_entered),
        .o_lfsr_tx_done         (o_lfsr_tx_done),

        // VALID_TX
        .i_valid_pattern_en     (i_valid_pattern_en),
        .o_valid_done           (o_valid_done),

        // TX pad outputs
        .o_tx_data              (o_TD_P),
        .o_tx_valid             (o_TVLD_P),

        // CLK_PATTERN_GEN_TX
        .i_clk_pattern_en       (i_clk_pattern_en),
        .i_clk_embedded_en      (i_clk_embedded_en),
        .o_mb_clk               (o_mb_clk),
        .o_clk_p                (o_TCKP_P),
        .o_clk_n                (o_TCKN_P),
        .o_clk_track            (o_TTRK_P),
        .o_clk_done             (o_clk_done)
    );

    // Lane Reversal Swapping
    wire [15:0] rx_data_swapped;
    assign rx_data_swapped = i_reversal_en ? {
        i_RD_P[0],  i_RD_P[1],  i_RD_P[2],  i_RD_P[3],
        i_RD_P[4],  i_RD_P[5],  i_RD_P[6],  i_RD_P[7],
        i_RD_P[8],  i_RD_P[9],  i_RD_P[10], i_RD_P[11],
        i_RD_P[12], i_RD_P[13], i_RD_P[14], i_RD_P[15]
    } : i_RD_P;

    // =========================================================================
    // MB_RX_TOP  (shares o_pll_clk and o_mb_clk from TX side)
    // =========================================================================
    MB_RX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .N_BYTES    (N_BYTES)
    ) u_rx (
        .MB_clk                            (o_mb_clk),
        .pll_clk                           (o_pll_clk),
        .i_rst_n                           (i_rst_n),

        // RX pad inputs (from partner die TX)
        .SER_out                           (i_RVLD_P),
        .ser_data_in                       (rx_data_swapped),

        // CLK detector
        .clk_detector_en                   (i_clk_detector_en),
        .clk_p                             (i_RCKP_P),
        .clk_n                             (i_RCKN_P),
        .track                             (i_RTRK_P),

        // LFSR_RX / Training
        .i_state                           (i_state),
        .i_width_deg_lfsr                  (i_width_deg_rx),
        .i_active_state_entered            (rx_active_gated),
        .i_descramble_en                   (i_descramble_en),
        .i_enable_buffer                   (i_enable_buffer),

        // Valid detector
        .i_max_error_threshold_valid       (i_max_err_valid),
        .i_enable_cons                     (i_enable_cons),
        .i_enable_128                      (i_enable_128),
        .i_enable_detector                 (i_enable_detector),

        // Pattern comparator
        .i_type_of_com                     (i_type_of_com),
        .i_max_error_threshold_per_lane_ID (i_max_err_per_lane),
        .i_max_error_threshold_aggergate   (i_max_err_agg),
        .i_width_deg_comp                  (i_width_deg_rx),

        // Demapper
        .demapper_en                       (demapper_en),
        .rx_data_valid                     (rx_data_valid_gated),
        .i_width_deg_demap                 (i_width_deg_rx),

        // RX status
        .de_ser_done                       (de_ser_done),
        .de_ser_done_data_0                (),
        .de_ser_done_data_1                (),
        .de_ser_done_data_2                (),
        .de_ser_done_data_3                (),
        .de_ser_done_data_4                (),
        .de_ser_done_data_5                (),
        .de_ser_done_data_6                (),
        .de_ser_done_data_7                (),
        .de_ser_done_data_8                (),
        .de_ser_done_data_9                (),
        .de_ser_done_data_10               (),
        .de_ser_done_data_11               (),
        .de_ser_done_data_12               (),
        .de_ser_done_data_13               (),
        .de_ser_done_data_14               (),
        .de_ser_done_data_15               (),
        .detection_result                  (detection_result),
        .o_valid_frame_detect              (o_valid_frame_detect),
        .o_per_lane_error                  (o_per_lane_error),
        .o_error_counter                   (o_error_counter),
        .o_error_done                      (o_error_done),
        .clk_p_pattern_pass                (clk_p_pattern_pass),
        .clk_n_pattern_pass                (clk_n_pattern_pass),
        .track_pattern_pass                (track_pattern_pass),
        .pl_valid                          (pl_valid),
        .o_out_data                        (o_out_data)
    );

endmodule
