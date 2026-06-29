`timescale 1ns/1ps
// =============================================================================
// Module  : unit_mb_die
// Project : UCIe 3.0 Main-Band Physical Layer  (Integration steps)
//
// Purpose : A complete Main-Band PHY "die": one TX datapath (unit_tx_top) AND
//           one RX datapath (unit_mb_rx_top) bundled together so two of them can
//           be wired back-to-back as die 0 and die 1.
//
//   TX side  : lp_data ─► mapper ─► lfsr_tx ─► serializers ─►
//                     o_TD_P / o_TVLD_P / o_TCKP_P/o_TCKN_P/o_TTRK_P   (to partner RX)
//   RX side  : i_RD_P / i_RVLD_P / i_RCKP_P/i_RCKN_P/i_RTRK_P (from partner TX)
//                     ─► deserializers ─► lfsr_rx ─► demapper ─► o_out_data
//
//  Clocking
//  --------
//   * Each die has its own PLL (inside unit_tx_top). The RX deserialisers sample
//     on the clock FORWARDED by the partner die (i_RCKP_P) delayed a quarter UI,
//     built inside unit_mb_rx_top from i_period. Both dies run the same speed
//     (i_pll_speed_sel is driven identically), so they are frequency-locked and
//     this die's own pll_period equals the partner's forwarded period -> we feed
//     the RX i_period from this die's own u_tx_top.pll_period.
//   * i_pll_clk (RX-local, quarter-shifted own PLL clock) is used ONLY by the
//     clock-pattern detector to sample the partner's clock burst during the
//     clock test (before any embedded clock is forwarded).
//   * i_mb_clk (= this die's lclk = pll/16) clocks the RX parallel back-end.
//  Simulation only.
// =============================================================================

module unit_mb_die #(
    parameter int  DATA_WIDTH     = 32,
    parameter int  NUM_LANES      = 16,
    parameter int  N_BYTES        = 64,
    parameter      [DATA_WIDTH-1:0] VALID_PATTERN  = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS  = 0.5,
    parameter int  RX_ALIGN_DELAY = 2
)(
    input  logic                    i_rst_n,

    // ------------------------------------------------ TX control
    input  logic [8*N_BYTES-1:0]    lp_data,
    input  logic                    lp_irdy,
    input  logic                    lp_valid,
    output logic                    pl_trdy,
    input  logic                    i_mapper_en,
    input  logic [2:0]              i_width_deg_tx,
    input  logic [2:0]              i_width_deg_rx,
    input  logic [2:0]              i_lfsr_state,
    input  logic                    i_reversal_en,
    input  logic                    i_valid_pattern_en,
    input  logic                    i_pll_en,
    input  logic [2:0]              i_pll_speed_sel,
    input  logic                    lclk_g,
    input  logic                    i_clk_pattern_en,
    input  logic                    i_clk_embedded_en,

    // ------------------------------------------------ RX control
    input  logic [2:0]              i_state,
    input  logic                    demapper_en,
    input  logic                    i_pcmp_enable,
    input  logic                    i_pcmp_mode,
    input  logic [NUM_LANES-1:0]    i_pcmp_lane_mask,
    input  logic [11:0]             i_pcmp_thr_per_lane,
    input  logic [15:0]             i_pcmp_thr_aggregate,
    input  logic [15:0]             i_pcmp_iter_count,
    input  logic                    i_pcmp_pattern_mode,
    input  logic                    i_pcmp_clear,
    input  logic                    i_vcmp_enable,
    input  logic                    i_vcmp_mode,
    input  logic [11:0]             i_vcmp_thr,
    input  logic                    i_vcmp_clear,
    input  logic                    i_clk_detector_en,
    input  logic [NUM_LANES-1:0]    i_rx_data_deser_en,
    input  logic                    i_rx_valid_deser_en,
    input  logic [1:0]              i_mb_tx_trk_lane_sel,
    input  logic [1:0]              i_mb_tx_clk_lane_sel,
    input  logic [1:0]              i_mb_tx_val_lane_sel,
    input  logic [1:0]              i_mb_tx_data_lane_sel,

    // ------------------------------------------------ RX serial in (partner TX)
    input  logic [NUM_LANES-1:0]    i_RD_P,
    input  logic                    i_RVLD_P,
    input  logic                    i_RCKP_P,
    input  logic                    i_RCKN_P,
    input  logic                    i_RTRK_P,

    // ------------------------------------------------ TX serial out (partner RX)
    output logic [NUM_LANES-1:0]    o_TD_P,
    output logic                    o_TVLD_P,
    output logic                    o_TCKP_P,
    output logic                    o_TCKN_P,
    output logic                    o_TTRK_P,

    // ------------------------------------------------ clocks / status
    output logic                    lclk,
    output logic                    gated_lclk,
    output logic                    o_lfsr_tx_done,
    output logic                    o_valid_done,
    output logic                    o_clk_done,

    // ------------------------------------------------ RX results + observability
    output logic [8*N_BYTES-1:0]    o_out_data,
    output logic                    o_pl_valid,
    output logic                    o_pcmp_done,
    output logic [NUM_LANES-1:0]    o_pcmp_per_lane_pass,
    output logic                    o_pcmp_agg_error,
    output logic                    o_vcmp_done,
    output logic                    o_vcmp_pass,
    output logic                    o_valid_frame_error,
    output logic                    o_clk_p_pass,
    output logic                    o_clk_n_pass,
    output logic                    o_track_pass
);

    wire pll_clk;

    // =========================================================================
    // 1. TX datapath (now contains the output tri-state buffers internally)
    // =========================================================================
    unit_tx_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES),
        .N_BYTES    (N_BYTES)
    ) u_tx_top (
        .i_rst_n            (i_rst_n),
        .lp_data            (lp_data),
        .lp_irdy            (lp_irdy),
        .lp_valid           (lp_valid),
        .pl_trdy            (pl_trdy),
        .i_mapper_en        (i_mapper_en),
        .i_width_deg        (i_width_deg_tx),
        .i_lfsr_state       (i_lfsr_state),
        .i_reversal_en      (i_reversal_en),
        .i_valid_pattern_en (i_valid_pattern_en),
        .i_pll_en           (i_pll_en),
        .i_pll_speed_sel    (i_pll_speed_sel),
        .lclk_g             (lclk_g),
        .i_clk_pattern_en   (i_clk_pattern_en),
        .i_clk_embedded_en  (i_clk_embedded_en),
        .i_mb_tx_data_lane_sel (i_mb_tx_data_lane_sel),
        .i_mb_tx_val_lane_sel  (i_mb_tx_val_lane_sel),
        .i_mb_tx_clk_lane_sel  (i_mb_tx_clk_lane_sel),
        .i_mb_tx_trk_lane_sel  (i_mb_tx_trk_lane_sel),
        .lclk               (lclk),
        .gated_lclk         (gated_lclk),
        .pll_clk            (pll_clk),
        .TD_P               (o_TD_P),
        .TVLD_P             (o_TVLD_P),
        .TCKP_P             (o_TCKP_P),
        .TCKN_P             (o_TCKN_P),
        .TTRK_P             (o_TTRK_P),
        .o_lfsr_tx_done     (o_lfsr_tx_done),
        .o_valid_done       (o_valid_done),
        .o_clk_done         (o_clk_done)
    );

    // =========================================================================
    // 2. RX datapath. Samples the partner's forwarded clock (i_RCKP_P) delayed a
    //    quarter UI; both dies share i_pll_speed_sel, so this die's own period
    //    equals the partner's forwarded period.
    // =========================================================================
    unit_mb_rx_top #(
        .DATA_WIDTH     (DATA_WIDTH),
        .NUM_LANES      (NUM_LANES),
        .N_BYTES        (N_BYTES),
        .VALID_PATTERN  (VALID_PATTERN),
        .RX_ALIGN_DELAY (RX_ALIGN_DELAY)
    ) u_rx_top (
        .i_rst_n              (i_rst_n),
        .i_pll_clk            (pll_clk),
        .i_mb_clk             (gated_lclk),
        .i_period             (u_tx_top.pll_period),

        .i_RD_P               (i_RD_P),
        .i_RVLD_P             (i_RVLD_P),
        .i_RCKP_P             (i_RCKP_P),
        .i_RCKN_P             (i_RCKN_P),
        .i_RTRK_P             (i_RTRK_P),

        .i_width_deg_rx       (i_width_deg_rx),
        .i_state              (i_state),
        .demapper_en          (demapper_en),

        .i_pcmp_enable        (i_pcmp_enable),
        .i_pcmp_mode          (i_pcmp_mode),
        .i_pcmp_lane_mask     (i_pcmp_lane_mask),
        .i_pcmp_thr_per_lane  (i_pcmp_thr_per_lane),
        .i_pcmp_thr_aggregate (i_pcmp_thr_aggregate),
        .i_pcmp_iter_count    (i_pcmp_iter_count),
        .i_pcmp_pattern_mode  (i_pcmp_pattern_mode),
        .i_pcmp_clear         (i_pcmp_clear),

        .i_vcmp_enable        (i_vcmp_enable),
        .i_vcmp_mode          (i_vcmp_mode),
        .i_vcmp_thr           (i_vcmp_thr),
        .i_vcmp_clear         (i_vcmp_clear),

        .i_clk_detector_en    (i_clk_detector_en),
        .i_rx_data_deser_en   (i_rx_data_deser_en),
        .i_rx_valid_deser_en  (i_rx_valid_deser_en),

        .o_out_data           (o_out_data),
        .o_pl_valid           (o_pl_valid),

        .o_pcmp_done          (o_pcmp_done),
        .o_pcmp_per_lane_pass (o_pcmp_per_lane_pass),
        .o_pcmp_agg_error     (o_pcmp_agg_error),

        .o_vcmp_done          (o_vcmp_done),
        .o_vcmp_pass          (o_vcmp_pass),
        .o_valid_frame_error  (o_valid_frame_error),

        .o_clk_p_pass         (o_clk_p_pass),
        .o_clk_n_pass         (o_clk_n_pass),
        .o_track_pass         (o_track_pass)
    );
endmodule
