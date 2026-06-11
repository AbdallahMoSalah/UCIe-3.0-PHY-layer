`timescale 1ns/1ps
// =============================================================================
// Module  : unit_mb_loopback_wrapper
// Project : UCIe 3.0 Main-Band Physical Layer  (Integration steps)
//
// Purpose : Closes a full Main-Band TX -> RX loopback by wiring unit_tx_top's
//           serialized outputs straight into unit_mb_rx_top:
//
//     lp_data ─►[ unit_tx_top ]─► TD_P[15:0] / TVLD_P / TCKP_P/TCKN_P/TTRK_P
//                                        │
//                                        ▼
//                              [ unit_mb_rx_top ]─► o_out_data (recovered flit)
//                                                   o_vcmp_pass / o_pcmp_* / clk pass
//
//  Clocking : the TX PLL clock is tapped hierarchically from unit_tx_top
//  (u_tx_top.pll_clk). The RX samples on rx_pll_clk, a quarter-period delayed
//  copy of that clock (so each DDR bit is sampled mid-eye). lclk (pll/16) comes
//  straight off the TX top and clocks the RX parallel back-end. Simulation only.
// =============================================================================

module unit_mb_loopback_wrapper #(
    parameter int  DATA_WIDTH     = 32,
    parameter int  NUM_LANES      = 16,
    parameter int  N_BYTES        = 64,
    parameter      [DATA_WIDTH-1:0] VALID_PATTERN  = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS  = 0.5,          // speed_sel=00 -> 500 ps
    parameter int  RX_ALIGN_DELAY = 2
)(
    // ----------------------------------------------------------------- reset
    input  logic                    i_rst_n,

    // ----------------------------------------------- unit_tx_top control in
    input  logic [8*N_BYTES-1:0]    lp_data,
    input  logic                    lp_irdy,
    input  logic                    lp_valid,
    output logic                    pl_trdy,
    input  logic                    i_mapper_en,
    input  logic [2:0]              i_width_deg,
    input  logic [2:0]              i_lfsr_state,
    input  logic                    i_reversal_en,
    input  logic                    i_valid_pattern_en,
    input  logic                    i_pll_en,
    input  logic [1:0]              i_pll_speed_sel,
    input  logic                    lclk_g,
    input  logic                    i_clk_pattern_en,
    input  logic                    i_clk_embedded_en,

    // ----------------------------------------------- RX control in
    input  logic [1:0]              i_rx_mode,
    input  logic                    i_pcmp_enable,
    input  logic                    i_pcmp_mode,
    input  logic [NUM_LANES-1:0]    i_pcmp_lane_mask,
    input  logic [15:0]             i_pcmp_thr_per_lane,
    input  logic [15:0]             i_pcmp_thr_aggregate,
    input  logic [15:0]             i_pcmp_iter_count,
    input  logic                    i_pcmp_pattern_mode,
    input  logic                    i_pcmp_clear,
    input  logic                    i_vcmp_enable,
    input  logic                    i_vcmp_mode,
    input  logic [15:0]             i_vcmp_thr,
    input  logic                    i_vcmp_clear,
    input  logic                    i_clk_detector_en,

    // ----------------------------------------------- TX status / clocks out
    output logic                    lclk,
    output logic                    o_pll_clk,
    output logic                    o_rx_pll_clk,
    output logic                    o_lfsr_tx_done,
    output logic                    o_valid_done,
    output logic                    o_clk_done,

    // ----------------------------------------------- serial physical lanes
    output logic [NUM_LANES-1:0]    TD_P,
    output logic                    TVLD_P,
    output logic                    TCKP_P,
    output logic                    TCKN_P,
    output logic                    TTRK_P,

    // ----------------------------------------------- RX observability
    output logic [DATA_WIDTH-1:0]   o_par_data   [0:NUM_LANES-1],
    output logic                    o_data_valid,
    output logic                    o_valid_frame_pulse,
    output logic [DATA_WIDTH-1:0]   o_rx_lane    [0:NUM_LANES-1],
    output logic                    o_rx_en,
    output logic                    o_pattern_comp_en,

    // ----------------------------------------------- recovered flit + results
    output logic [8*N_BYTES-1:0]    o_out_data,
    output logic                    o_pl_valid,
    output logic                    o_pcmp_done,
    output logic [NUM_LANES-1:0]    o_pcmp_per_lane_pass,
    output logic [15:0]             o_pcmp_agg_err_cnt,
    output logic                    o_pcmp_agg_error,
    output logic                    o_vcmp_done,
    output logic                    o_vcmp_pass,
    output logic                    o_valid_frame_error,
    output logic                    o_clk_p_pass,
    output logic                    o_clk_n_pass,
    output logic                    o_track_pass
);

    // =========================================================================
    // Internal clocks
    // =========================================================================
    wire pll_clk_int;
    wire rx_pll_clk;

    // =========================================================================
    // 1. Frozen Main-Band TX top
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
        .i_width_deg        (i_width_deg),
        .i_lfsr_state       (i_lfsr_state),
        .i_reversal_en      (i_reversal_en),
        .i_valid_pattern_en (i_valid_pattern_en),
        .i_pll_en           (i_pll_en),
        .i_pll_speed_sel    (i_pll_speed_sel),
        .lclk_g             (lclk_g),
        .i_clk_pattern_en   (i_clk_pattern_en),
        .i_clk_embedded_en  (i_clk_embedded_en),
        .lclk               (lclk),
        .TD_P               (TD_P),
        .TVLD_P             (TVLD_P),
        .TCKP_P             (TCKP_P),
        .TCKN_P             (TCKN_P),
        .TTRK_P             (TTRK_P),
        .o_lfsr_tx_done     (o_lfsr_tx_done),
        .o_valid_done       (o_valid_done),
        .o_clk_done         (o_clk_done)
    );

    assign pll_clk_int  = u_tx_top.pll_clk;
    assign o_pll_clk    = pll_clk_int;
    // RX-local clock for the clk-pattern detector: quarter-period shift of the TX
    // PLL clock. Fixed at the elaboration speed (the clock test only runs once, at
    // the slowest speed, before any PLL speed change) so a parameter delay is fine.
    assign #(PLL_PERIOD_NS/4.0) rx_pll_clk = pll_clk_int;
    assign o_rx_pll_clk = rx_pll_clk;

    // =========================================================================
    // 2. Main-Band RX top (DUT)
    // =========================================================================
    unit_mb_rx_top #(
        .DATA_WIDTH     (DATA_WIDTH),
        .NUM_LANES      (NUM_LANES),
        .N_BYTES        (N_BYTES),
        .VALID_PATTERN  (VALID_PATTERN),
        .RX_ALIGN_DELAY (RX_ALIGN_DELAY)
    ) u_rx_top (
        .i_rst_n              (i_rst_n),
        .i_pll_clk            (rx_pll_clk),
        .i_mb_clk             (lclk),
        .i_period             (u_tx_top.pll_period),   // forwarded UI period (ps)

        .i_RD_P               (TD_P),
        .i_RVLD_P             (TVLD_P),
        .i_RCKP_P             (TCKP_P),
        .i_RCKN_P             (TCKN_P),
        .i_RTRK_P             (TTRK_P),

        .i_width_deg_rx       (i_width_deg),
        .i_state              (i_lfsr_state),
        .demapper_en          (i_lfsr_state == 3'b100),

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

        .o_out_data           (o_out_data),
        .o_pl_valid           (o_pl_valid),

        .o_pcmp_done          (o_pcmp_done),
        .o_pcmp_per_lane_pass (o_pcmp_per_lane_pass),
        .o_pcmp_agg_err_cnt   (o_pcmp_agg_err_cnt),
        .o_pcmp_agg_error     (o_pcmp_agg_error),

        .o_vcmp_done          (o_vcmp_done),
        .o_vcmp_pass          (o_vcmp_pass),
        .o_valid_frame_error  (o_valid_frame_error),

        .o_clk_p_pass         (o_clk_p_pass),
        .o_clk_n_pass         (o_clk_n_pass),
        .o_track_pass         (o_track_pass)
    );

    assign o_par_data          = u_rx_top.o_par_data;
    assign o_data_valid        = u_rx_top.o_data_valid;
    assign o_valid_frame_pulse = u_rx_top.o_valid_frame_pulse;
    assign o_rx_lane           = u_rx_top.o_rx_lane;
    assign o_rx_en             = u_rx_top.o_rx_en;
    assign o_pattern_comp_en   = u_rx_top.o_pattern_comp_en;

endmodule
