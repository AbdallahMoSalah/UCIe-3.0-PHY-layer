// =============================================================================
// Module  : mb_die
// Project : UCIe 3.0 Main-Band Physical Layer (Integration steps)
//
// Purpose : A complete MainBand PHY "die": one TX datapath (MB_TX_TOP) AND one
//           RX datapath (MB_RX_TOP) bundled together, with the serial pads
//           BROUGHT OUT as ports so two dies can be wired back-to-back as
//           die 0 and die 1 (the MainBand counterpart of MainBand_RD's
//           unit_mb_die). This is what MB_TOP does NOT allow: MB_TOP loops the
//           TX back to its own RX internally, hiding the inter-die link.
//
//   TX side : lp_data -> mapper -> lfsr_tx -> serializers ->
//                  o_TD_P / o_TVLD_P / o_TCKP_P/o_TCKN_P/o_TTRK_P   (to partner RX)
//   RX side : i_RD_P / i_RVLD_P / i_RCKP_P/i_RCKN_P/i_RTRK_P (from partner TX)
//                  -> deserializers -> lfsr_rx -> comparator -> demapper -> o_out_data
//
//  Clocking
//  --------
//   Each die owns its PLL (inside MB_TX_TOP). Both dies share i_pll_en /
//   i_pll_speed_sel, so the two MB_PLL instances are frequency- AND phase-locked
//   (deterministic #delay from t=0). The RX deserializers sample on THIS die's
//   own o_pll_clk and the RX back-end on this die's o_mb_clk - identical to how
//   MB_TOP wires its RX, and valid because the partner's clocks are the same
//   waveform. The forwarded clock pins (i_RCKP_P/i_RCKN_P/i_RTRK_P) feed only
//   the clock-pattern detector (same as MB_TOP's w_clk_p/n/track).
//
//   width: i_width_deg_tx feeds the TX (mapper + lfsr_tx); i_width_deg_rx feeds
//   the RX (lfsr_rx + comparator + demapper). Keeping them separate lets the
//   two-die TB drive independent per-direction link widths.
//
//  Simulation only.
// =============================================================================

`timescale 1ps/1ps

module mb_die #(
    parameter DATA_WIDTH = 32,
    parameter NUM_LANES  = 16,
    parameter N_BYTES    = 64
)(
    input  logic                    i_rst_n,

    // ------------------------------------------------ PLL / clocks
    input  logic                    i_pll_en,
    input  logic [1:0]              i_pll_speed_sel,
    output logic                    o_pll_clk,
    output logic                    o_mb_clk,            // = lclk

    // ------------------------------------------------ TX control
    input  logic [8*N_BYTES-1:0]    lp_data,
    input  logic                    i_mapper_en,
    input  logic                    i_lp_irdy,
    input  logic                    i_lp_valid,
    output logic                    o_mapper_ready,      // = pl_trdy
    input  logic [2:0]              i_width_deg_tx,
    input  logic [2:0]              i_lfsr_state,
    input  logic                    i_reversal_en,
    input  logic                    i_active_state_entered,
    input  logic                    i_valid_pattern_en,
    input  logic                    i_clk_pattern_en,
    input  logic                    i_clk_embedded_en,
    output logic                    o_lfsr_tx_done,
    output logic                    o_valid_done,
    output logic                    o_clk_done,

    // ------------------------------------------------ TX serial out (to partner RX)
    output logic [NUM_LANES-1:0]    o_TD_P,
    output logic                    o_TVLD_P,
    output logic                    o_TCKP_P,
    output logic                    o_TCKN_P,
    output logic                    o_TTRK_P,

    // ------------------------------------------------ RX serial in (from partner TX)
    input  logic [NUM_LANES-1:0]    i_RD_P,
    input  logic                    i_RVLD_P,
    input  logic                    i_RCKP_P,
    input  logic                    i_RCKN_P,
    input  logic                    i_RTRK_P,

    // ------------------------------------------------ RX control
    input  logic [2:0]              i_state,
    input  logic [2:0]              i_width_deg_rx,
    input  logic                    i_descramble_en,
    input  logic                    i_enable_buffer,
    input  logic                    i_clk_detector_en,
    input  logic [11:0]             i_max_err_valid,
    input  logic                    i_enable_cons,
    input  logic                    i_enable_128,
    input  logic                    i_enable_detector,
    input  logic [1:0]              i_type_of_com,
    input  logic [15:0]             i_max_err_per_lane,
    input  logic [15:0]             i_max_err_agg,
    input  logic                    demapper_en,
    input  logic                    rx_data_valid,

    // ------------------------------------------------ RX status
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

    real w_period;   // MB_PLL period (ps); unused externally

    // =========================================================================
    // TX datapath
    // =========================================================================
    MB_TX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES),
        .N_BYTES    (N_BYTES)
    ) u_tx (
        .i_rst_n                (i_rst_n),
        .i_pll_en               (i_pll_en),
        .i_pll_speed_sel        (i_pll_speed_sel),
        .o_pll_clk              (o_pll_clk),
        .period                 (w_period),
        .i_raw_data             (lp_data),
        .i_mapper_en            (i_mapper_en),
        .i_width_deg            (i_width_deg_tx),
        .i_lp_irdy              (i_lp_irdy),
        .i_lp_valid             (i_lp_valid),
        .o_mapper_ready         (o_mapper_ready),
        .i_lfsr_state           (i_lfsr_state),
        .i_reversal_en          (i_reversal_en),
        .i_active_state_entered (i_active_state_entered),
        .o_lfsr_tx_done         (o_lfsr_tx_done),
        .i_valid_pattern_en     (i_valid_pattern_en),
        .o_valid_done           (o_valid_done),
        .o_tx_data              (o_TD_P),
        .o_tx_valid             (o_TVLD_P),
        .i_clk_pattern_en       (i_clk_pattern_en),
        .i_clk_embedded_en      (i_clk_embedded_en),
        .o_mb_clk               (o_mb_clk),
        .o_clk_p                (o_TCKP_P),
        .o_clk_n                (o_TCKN_P),
        .o_clk_track            (o_TTRK_P),
        .o_clk_done             (o_clk_done)
    );

    // =========================================================================
    // RX datapath. Deserializers sample on this die's own o_pll_clk / o_mb_clk
    // (frequency/phase-locked to the partner). The forwarded clock pins feed the
    // clock-pattern detector only.
    // =========================================================================
    MB_RX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .N_BYTES    (N_BYTES)
    ) u_rx (
        .MB_clk                             (o_mb_clk),
        .pll_clk                            (o_pll_clk),
        .i_rst_n                            (i_rst_n),

        .SER_out                            (i_RVLD_P),
        .ser_data_in                        (i_RD_P),

        .clk_detector_en                    (i_clk_detector_en),
        .clk_p                              (i_RCKP_P),
        .clk_n                              (i_RCKN_P),
        .track                              (i_RTRK_P),

        .i_state                            (i_state),
        .i_width_deg_lfsr                   (i_width_deg_rx),
        .i_active_state_entered             (i_active_state_entered),
        .i_descramble_en                    (i_descramble_en),
        .i_enable_buffer                    (i_enable_buffer),

        .i_max_error_threshold_valid        (i_max_err_valid),
        .i_enable_cons                      (i_enable_cons),
        .i_enable_128                       (i_enable_128),
        .i_enable_detector                  (i_enable_detector),

        .i_type_of_com                      (i_type_of_com),
        .i_max_error_threshold_per_lane_ID  (i_max_err_per_lane),
        .i_max_error_threshold_aggergate    (i_max_err_agg),
        .i_width_deg_comp                   (i_width_deg_rx),

        .demapper_en                        (demapper_en),
        .rx_data_valid                      (rx_data_valid),
        .i_width_deg_demap                  (i_width_deg_rx),

        .de_ser_done                        (de_ser_done),
        .de_ser_done_data_0                 (), .de_ser_done_data_1 (), .de_ser_done_data_2 (),
        .de_ser_done_data_3                 (), .de_ser_done_data_4 (), .de_ser_done_data_5 (),
        .de_ser_done_data_6                 (), .de_ser_done_data_7 (), .de_ser_done_data_8 (),
        .de_ser_done_data_9                 (), .de_ser_done_data_10(), .de_ser_done_data_11(),
        .de_ser_done_data_12                (), .de_ser_done_data_13(), .de_ser_done_data_14(),
        .de_ser_done_data_15                (),
        .detection_result                   (detection_result),
        .o_valid_frame_detect               (o_valid_frame_detect),
        .o_per_lane_error                   (o_per_lane_error),
        .o_error_counter                    (o_error_counter),
        .o_error_done                       (o_error_done),
        .clk_p_pattern_pass                 (clk_p_pattern_pass),
        .clk_n_pattern_pass                 (clk_n_pattern_pass),
        .track_pattern_pass                 (track_pattern_pass),
        .pl_valid                           (pl_valid),
        .o_out_data                         (o_out_data)
    );

endmodule
