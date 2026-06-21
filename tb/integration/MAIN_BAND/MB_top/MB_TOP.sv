// =============================================================================
// Module  : MB_TOP
// Project : UCIe 3.0 Main-Band Physical Layer
// Purpose : Full Main-Band top-level: MB_TX_TOP looped back to MB_RX_TOP.
//
//  Signal flow
//  -----------
//   MB_PLL (in TX)    → o_pll_clk  (2 / 4 / 8 / 16 GHz, speed_sel-dependent)
//   ClkDiv (in TX)    → o_mb_clk   = o_pll_clk / 16  (functional clock)
//
//   TX → RX connections (all zero-latency in simulation):
//     o_tx_data[15:0]  → ser_data_in[15:0]   (16 DDR data lanes)
//     o_tx_valid       → SER_out              (DDR valid lane)
//     o_clk_p          → clk_p               (differential clock +)
//     o_clk_n          → clk_n               (differential clock −)
//     o_clk_track      → track               (tracking signal)
//     o_pll_clk        → pll_clk             (fast clock for RX desers)
//     o_mb_clk         → MB_clk              (slow clock for RX logic)
//
//  Control philosophy
//  ------------------
//   i_ltsm_state  is shared between TX (i_lfsr_state) and RX (i_state) so
//   that both sides advance their LFSRs and pattern engines in lockstep.
//   i_width_deg   is shared across Mapper, LFSR_TX, LFSR_RX, comparator,
//   and Demapper.
// =============================================================================

`timescale 1ps/1ps

module MB_TOP #(
    parameter DATA_WIDTH = 32,
    parameter NUM_LANES  = 16,
    parameter N_BYTES    = 64
)(
    // ── Global reset ──────────────────────────────────────────────────────
    input  logic                    i_rst_n,

    // ── PLL ──────────────────────────────────────────────────────────────
    input  logic                    i_pll_en,
    input  logic [1:0]              i_pll_speed_sel,  // 00=2G 01=4G 10=8G 11=16G

    // ── Shared LTSM state (drives both TX LFSR and RX LFSR/comparator) ───
    input  logic [2:0]              i_ltsm_state,
    // 000=IDLE  001=CLEAR_LFSR  010=PATTERN_LFSR
    // 011=PER_LANE_ID  100=DATA_TRANSFER
    input  logic                    i_active_state_entered,
    input  logic [2:0]              i_width_deg,
    // 000=none  001=lanes 0-7  010=lanes 8-15
    // 011=all 16  100=lanes 0-3  101=lanes 4-7

    // ── TX: clock pattern ─────────────────────────────────────────────────
    input  logic                    i_clk_pattern_en,
    input  logic                    i_clk_embedded_en,

    // ── TX: valid pattern ─────────────────────────────────────────────────
    input  logic                    i_valid_pattern_en,

    // ── TX: lane reversal ─────────────────────────────────────────────────
    input  logic                    i_reversal_en,

    // ── TX: Mapper data ───────────────────────────────────────────────────
    input  logic [8*N_BYTES-1:0]    i_raw_data,
    input  logic                    i_mapper_en,
    input  logic                    i_lp_irdy,
    input  logic                    i_lp_valid,

    // ── RX: clock detector ────────────────────────────────────────────────
    input  logic                    clk_detector_en,

    // ── RX: LFSR / descrambling ───────────────────────────────────────────
    input  logic                    i_descramble_en,
    input  logic                    i_enable_buffer,

    // ── RX: valid detector ────────────────────────────────────────────────
    input  logic [11:0]             i_max_err_valid,
    input  logic                    i_enable_cons,
    input  logic                    i_enable_128,
    input  logic                    i_enable_detector,

    // ── RX: pattern comparator ────────────────────────────────────────────
    input  logic [1:0]              i_type_of_com,
    input  logic [15:0]             i_max_err_per_lane,
    input  logic [15:0]             i_max_err_agg,

    // ── RX: demapper ──────────────────────────────────────────────────────
    input  logic                    demapper_en,
    input  logic                    rx_data_valid,

    // ── Clock outputs (observable by TB / upper layers) ───────────────────
    output logic                    o_pll_clk,
    output logic                    o_mb_clk,

    // ── TX status ─────────────────────────────────────────────────────────
    output logic                    o_clk_done,
    output logic                    o_valid_done,
    output logic                    o_lfsr_tx_done,
    output logic                    o_mapper_ready,

    // ── RX status ─────────────────────────────────────────────────────────
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
    output logic [8*N_BYTES-1:0]    o_out_data,
    output logic                    de_ser_done_data_0,
    output logic                    de_ser_done_data_1,
    output logic                    de_ser_done_data_2,
    output logic                    de_ser_done_data_3,
    output logic                    de_ser_done_data_4,
    output logic                    de_ser_done_data_5,
    output logic                    de_ser_done_data_6,
    output logic                    de_ser_done_data_7,
    output logic                    de_ser_done_data_8,
    output logic                    de_ser_done_data_9,
    output logic                    de_ser_done_data_10,
    output logic                    de_ser_done_data_11,
    output logic                    de_ser_done_data_12,
    output logic                    de_ser_done_data_13,
    output logic                    de_ser_done_data_14,
    output logic                    de_ser_done_data_15
);

    // ─────────────────────────────────────────────────────────────────────
    // Internal TX → RX wires
    // ─────────────────────────────────────────────────────────────────────
    logic [NUM_LANES-1:0]  w_tx_data;
    logic                  w_tx_valid;
    logic                  w_clk_p, w_clk_n, w_clk_track;
    real                   w_period;

    // ─────────────────────────────────────────────────────────────────────
    // MB_TX_TOP
    // ─────────────────────────────────────────────────────────────────────
    MB_TX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES),
        .N_BYTES    (N_BYTES)
    ) u_tx (
        .i_rst_n                (i_rst_n),

        //pll
        .i_pll_en               (i_pll_en),
        .i_pll_speed_sel        (i_pll_speed_sel),
        .o_pll_clk              (o_pll_clk),
        .period                 (w_period),

        //Mapper
        .i_raw_data             (i_raw_data),
        .i_mapper_en            (i_mapper_en),
        .i_width_deg            (i_width_deg),
        .i_lp_irdy              (i_lp_irdy),
        .i_lp_valid             (i_lp_valid),
        .o_mapper_ready         (o_mapper_ready),

        //lfsr
        .i_lfsr_state           (i_ltsm_state),
        .i_reversal_en          (i_reversal_en),
        .i_active_state_entered (i_active_state_entered),
        .o_lfsr_tx_done         (o_lfsr_tx_done),

        //valid
        .i_valid_pattern_en     (i_valid_pattern_en),
        .o_valid_done           (o_valid_done),

        //serial output 
        .o_tx_data              (w_tx_data),
        .o_tx_valid             (w_tx_valid),

        //clk pattern
        .i_clk_pattern_en       (i_clk_pattern_en),
        .i_clk_embedded_en      (i_clk_embedded_en),
        .o_clk_p                (w_clk_p),
        .o_clk_n                (w_clk_n),
        .o_clk_track            (w_clk_track),
        .o_clk_done             (o_clk_done),

        //clk div
        .o_mb_clk               (o_mb_clk)
    );

    // ─────────────────────────────────────────────────────────────────────
    // MB_RX_TOP  — shares pll_clk and mb_clk generated by TX side
    // ─────────────────────────────────────────────────────────────────────
    MB_RX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .N_BYTES    (N_BYTES)
    ) u_rx (
        .MB_clk                          (o_mb_clk),
        .pll_clk                         (o_pll_clk), //elmafrod o_clk_p
        .i_rst_n                         (i_rst_n),

        // Serial inputs from TX
        .SER_out                         (w_tx_valid),
        .ser_data_in                     (w_tx_data),

        // Clock pattern
        .clk_detector_en                 (clk_detector_en),
        .clk_p                           (w_clk_p),
        .clk_n                           (w_clk_n),
        .track                           (w_clk_track),

        // LTSM / LFSR control
        .i_state                         (i_ltsm_state),
        .i_width_deg_lfsr                (i_width_deg),
        .i_active_state_entered          (i_active_state_entered),
        .i_descramble_en                 (i_descramble_en),
        .i_enable_buffer                 (i_enable_buffer),

        // Valid detector
        .i_max_error_threshold_valid     (i_max_err_valid),
        .i_enable_cons                   (i_enable_cons),
        .i_enable_128                    (i_enable_128),
        .i_enable_detector               (i_enable_detector),

        // Pattern comparator
        .i_type_of_com                   (i_type_of_com),
        .i_max_error_threshold_per_lane_ID (i_max_err_per_lane),
        .i_max_error_threshold_aggergate (i_max_err_agg),
        .i_width_deg_comp                (i_width_deg),

        // Demapper
        .demapper_en                     (demapper_en),
        .rx_data_valid                   (rx_data_valid),
        .i_width_deg_demap               (i_width_deg),

        // RX status outputs
        .de_ser_done                     (de_ser_done),
        .de_ser_done_data_0              (),
        .de_ser_done_data_1              (),
        .de_ser_done_data_2              (),
        .de_ser_done_data_3              (),
        .de_ser_done_data_4              (),
        .de_ser_done_data_5              (),
        .de_ser_done_data_6              (),
        .de_ser_done_data_7              (),
        .de_ser_done_data_8              (),
        .de_ser_done_data_9              (),
        .de_ser_done_data_10             (),
        .de_ser_done_data_11             (),
        .de_ser_done_data_12             (),
        .de_ser_done_data_13             (),
        .de_ser_done_data_14             (),
        .de_ser_done_data_15             (),
        .detection_result                (detection_result),
        .o_valid_frame_detect            (o_valid_frame_detect),
        .o_per_lane_error                (o_per_lane_error),
        .o_error_counter                 (o_error_counter),
        .o_error_done                    (o_error_done),
        .clk_p_pattern_pass              (clk_p_pattern_pass),
        .clk_n_pattern_pass              (clk_n_pattern_pass),
        .track_pattern_pass              (track_pattern_pass),
        .pl_valid                        (pl_valid),
        .o_out_data                      (o_out_data)
    );

endmodule
