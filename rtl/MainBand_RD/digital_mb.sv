`timescale 1ns/1ps
// =============================================================================
// Module  : digital_mb
// Project : UCIe 3.0 Main-Band Physical Layer
//
// Purpose : The digital half of the Main-Band PHY - every block of the Main-Band
//           top EXCEPT the analog hard macro (mainband_analog_hard_macro). It is
//           the structural counterpart that pairs with the hard macro: the hard
//           macro owns the PLL/clocking + SerDes + tri-state, this module owns all
//           the digital processing.
//
//  Blocks contained (all digital)
//  ------------------------------
//    TX : mapper -> lfsr_tx -> tx-reversal(array) -> [to hard-macro serializers]
//         valid_tx           -> [to hard-macro valid serializer]
//         clk_pattern_gen_tx -> [to hard-macro tri-state clk/track pins]
//    RX : lfsr_rx -> demapper          (recovers the protocol bus)
//         pattern_comparator           (training pattern check)
//         valid_comparator             (valid-frame check, feeds vcmp_done back
//                                       into the hard-macro valid deserializer)
//         clk_pattern_detector_rx      (samples the raw forwarded clock/track)
//
//  Boundary with the analog hard macro
//  -----------------------------------
//   * Lane reversal moved here, placed right after lfsr_tx and BEFORE the output
//     (parallel array reversal, unit_mb_tx_reversal_array). The reversed lane
//     words leave on o_lfsr_lane and feed the hard-macro data serializers.
//   * The clock-pattern generator stays here; its serial outputs leave on
//     o_tckp_p_pre / o_tckn_p_pre / o_ttrk_p_pre and drive the hard-macro
//     tri-state clk/track pins.
//   * The valid comparator stays here; its done flag (o_vcmp_done) is fed back
//     into the hard-macro valid deserializer as well as exposed as status.
//   * The clock detector stays here and samples the raw forwarded clock/track
//     (i_RCKP_P / i_RCKN_P / i_RTRK_P) directly - i_RCKN_P / i_RTRK_P are not
//     wired into the hard macro for that reason.
//   * Clocks (i_gated_lclk, i_pll_clk, i_pll_period) and the recovered parallel
//     RX words (i_par_data, i_data_valid, i_valid_frame_*) come from the hard
//     macro.
//
//  Pure analog controls (i_pll_speed_sel, lclk_g, the four tri-state lane
//  selects, i_rx_*_deser_en, i_vcmp_enable's deser-gating use) do NOT touch any
//  digital block and so are routed by the top straight to the hard macro - they
//  are intentionally absent here (except i_vcmp_enable, which the valid
//  comparator also needs).
//  Simulation only.
// =============================================================================

module digital_mb #(
    parameter int  DATA_WIDTH    = 32,    // parallel lane-word width
    parameter int  NUM_LANES     = 16,    // number of data lanes
    parameter int  N_BYTES       = 64,    // byte width of the raw protocol bus
    parameter      [DATA_WIDTH-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter int  RX_ALIGN_DELAY = 2
)(
    // =========================================================================
    // Clocks / reset (reset external; clocks from the hard macro)
    // =========================================================================
    input  logic                    i_rst_n,                // active-low reset
    input  logic                    i_gated_lclk,           // gated lclk (hard macro)
    input  logic                    i_pll_clk,              // gated PLL clock (hard macro)

    // =========================================================================
    // TX - adapter interface
    // =========================================================================
    input  logic [8*N_BYTES-1:0]    lp_data,                // raw protocol data
    input  logic                    lp_irdy,                // adapter: data ready
    input  logic                    lp_valid,               // adapter: data valid
    output logic                    pl_trdy,                // mapper accepted data

    // =========================================================================
    // TX - configuration
    // =========================================================================
    input  logic                    i_mapper_en,            // enable the mapper
    input  logic [2:0]              i_width_deg,            // TX lane-width degrade code
    input  logic [2:0]              i_lfsr_state,           // requested LFSR state
    input  logic                    i_reversal_en,          // physical lane reversal
    input  logic                    i_valid_pattern_en,     // trigger 32-cycle TVLD pattern
    input  logic                    i_clk_pattern_en,       // trigger 128-UI clock burst
    input  logic                    i_clk_embedded_en,      // continuous embedded-clock mode

    // =========================================================================
    // TX -> analog hard macro (parallel datapath, pre-serializer)
    // =========================================================================
    output logic                    o_lfsr_ser_en,          // data-lane serializer enable
    output logic [DATA_WIDTH-1:0]   o_lfsr_lane [0:NUM_LANES-1], // reversed lane words
    output logic                    o_valid_ser_en,         // valid-lane serializer enable
    output logic [DATA_WIDTH-1:0]   o_valid_word,           // 32-bit TVLD pattern word
    output logic                    o_tckp_p_pre,           // clock + pre tri-state
    output logic                    o_tckn_p_pre,           // clock - pre tri-state
    output logic                    o_ttrk_p_pre,           // track   pre tri-state

    // =========================================================================
    // TX - status / handshake
    // =========================================================================
    output logic                    o_lfsr_tx_done,         // LFSR / ID phase complete
    output logic                    o_valid_done,           // valid-pattern done
    output logic                    o_clk_done,             // clock-pattern burst complete

    // =========================================================================
    // RX - datapath / comparator configuration
    // =========================================================================
    input  logic [2:0]              i_state,                // RX LFSR / datapath state
    input  logic [2:0]              i_width_deg_rx,         // RX lane-width degrade code
    input  logic                    demapper_en,            // demapper enable

    input  logic                    i_pcmp_enable,
    input  logic                    i_pcmp_mode,            // 0 per-lane, 1 aggregate
    input  logic [NUM_LANES-1:0]    i_pcmp_lane_mask,
    input  logic [11:0]             i_pcmp_thr_per_lane,
    input  logic [15:0]             i_pcmp_thr_aggregate,
    input  logic [15:0]             i_pcmp_iter_count,
    input  logic                    i_pcmp_pattern_mode,    // 1 per-lane ID, 0 LFSR
    input  logic                    i_pcmp_clear,

    input  logic                    i_vcmp_enable,
    input  logic                    i_vcmp_mode,            // 0 = 16 consec, 1 = threshold
    input  logic [11:0]             i_vcmp_thr,
    input  logic                    i_vcmp_clear,

    input  logic                    i_clk_detector_en,

    // =========================================================================
    // RX <- analog hard macro (recovered parallel words)
    // =========================================================================
    input  logic [DATA_WIDTH-1:0]   i_par_data [0:NUM_LANES-1], // descrambled-pending words
    input  logic                    i_data_valid,           // any-lane deserialized word valid
    input  logic [DATA_WIDTH-1:0]   i_valid_frame_data,     // recovered valid-frame word
    input  logic                    i_valid_frame_vld,      // recovered valid-frame strobe

    // =========================================================================
    // RX - raw forwarded clock/track (clk detector samples these directly)
    // =========================================================================
    input  logic                    i_RCKP_P,               // differential clock +
    input  logic                    i_RCKN_P,               // differential clock -
    input  logic                    i_RTRK_P,               // clock tracking

    // =========================================================================
    // RX - recovered protocol bus + comparator results
    // =========================================================================
    output logic [8*N_BYTES-1:0]    o_out_data,
    output logic                    o_pl_valid,

    output logic                    o_pcmp_done,
    output logic [NUM_LANES-1:0]    o_pcmp_per_lane_pass,
    output logic                    o_pcmp_agg_error,

    output logic                    o_vcmp_done,            // also feeds hard-macro deser
    output logic                    o_vcmp_pass,
    output logic                    o_valid_frame_error,

    output logic                    o_clk_p_pass,
    output logic                    o_clk_n_pass,
    output logic                    o_track_pass
);

    // =========================================================================
    // Internal nets
    // =========================================================================
    // ----- Mapper -> LFSR_TX (16 parallel lane words) ------------------------
    logic [DATA_WIDTH-1:0] mapper_lane_0,  mapper_lane_1,  mapper_lane_2,  mapper_lane_3;
    logic [DATA_WIDTH-1:0] mapper_lane_4,  mapper_lane_5,  mapper_lane_6,  mapper_lane_7;
    logic [DATA_WIDTH-1:0] mapper_lane_8,  mapper_lane_9,  mapper_lane_10, mapper_lane_11;
    logic [DATA_WIDTH-1:0] mapper_lane_12, mapper_lane_13, mapper_lane_14, mapper_lane_15;

    logic [DATA_WIDTH-1:0] mapper_lane [0:NUM_LANES-1];
    assign mapper_lane[0]  = mapper_lane_0;
    assign mapper_lane[1]  = mapper_lane_1;
    assign mapper_lane[2]  = mapper_lane_2;
    assign mapper_lane[3]  = mapper_lane_3;
    assign mapper_lane[4]  = mapper_lane_4;
    assign mapper_lane[5]  = mapper_lane_5;
    assign mapper_lane[6]  = mapper_lane_6;
    assign mapper_lane[7]  = mapper_lane_7;
    assign mapper_lane[8]  = mapper_lane_8;
    assign mapper_lane[9]  = mapper_lane_9;
    assign mapper_lane[10] = mapper_lane_10;
    assign mapper_lane[11] = mapper_lane_11;
    assign mapper_lane[12] = mapper_lane_12;
    assign mapper_lane[13] = mapper_lane_13;
    assign mapper_lane[14] = mapper_lane_14;
    assign mapper_lane[15] = mapper_lane_15;

    logic                  mapper_scramble_en;          // Mapper -> LFSR_TX: enable scrambling

    // ----- LFSR_TX -> tx-reversal (pre-reversal lane words) ------------------
    logic [DATA_WIDTH-1:0] lfsr_lane [0:NUM_LANES-1];   // scrambled lane words

    // ----- RX recovered/descrambled nets -------------------------------------
    logic [DATA_WIDTH-1:0] o_rx_lane       [0:NUM_LANES-1];
    logic [DATA_WIDTH-1:0] lfsr_final_gene [0:NUM_LANES-1];
    logic                  o_pattern_comp_en;           // lfsr_rx: training pattern valid
    logic                  i_data_valid_rx;             // lfsr_rx -> demapper word valid

    // =========================================================================
    // 0. CLK_PATTERN_GEN_TX  (clocked by the hard-macro PLL clock)
    // =========================================================================
    unit_clk_pattern_gen_tx u_clk_pattern_gen (
        .i_clk           (i_pll_clk),
        .i_rst_n         (i_rst_n),
        .clk_pattern_en  (i_clk_pattern_en),
        .clk_embedded_en (i_clk_embedded_en),
        .o_clk_p         (o_tckp_p_pre),
        .o_clk_n         (o_tckn_p_pre),
        .track           (o_ttrk_p_pre),
        .o_done          (o_clk_done)
    );

    // =========================================================================
    // 1. Mapper
    // =========================================================================
    unit_mapper #(
        .WIDTH     (DATA_WIDTH),
        .NUM_LANES (NUM_LANES),
        .N_BYTES   (N_BYTES)
    ) u_mapper (
        .i_clk           (i_gated_lclk),
        .i_rst_n         (i_rst_n),
        .i_in_data       (lp_data),
        .mapper_en       (i_mapper_en),
        .i_width_deg_map (i_width_deg),
        .lp_irdy         (lp_irdy),
        .lp_valid        (lp_valid),

        .o_lane_0        (mapper_lane_0),
        .o_lane_1        (mapper_lane_1),
        .o_lane_2        (mapper_lane_2),
        .o_lane_3        (mapper_lane_3),
        .o_lane_4        (mapper_lane_4),
        .o_lane_5        (mapper_lane_5),
        .o_lane_6        (mapper_lane_6),
        .o_lane_7        (mapper_lane_7),
        .o_lane_8        (mapper_lane_8),
        .o_lane_9        (mapper_lane_9),
        .o_lane_10       (mapper_lane_10),
        .o_lane_11       (mapper_lane_11),
        .o_lane_12       (mapper_lane_12),
        .o_lane_13       (mapper_lane_13),
        .o_lane_14       (mapper_lane_14),
        .o_lane_15       (mapper_lane_15),

        .out_scramble_en (mapper_scramble_en),
        .mapper_ready    (pl_trdy)
    );

    // =========================================================================
    // 2. LFSR_TX
    // =========================================================================
    unit_lfsr_tx #(
        .WIDTH (DATA_WIDTH)
    ) u_lfsr_tx (
        .i_clk            (i_gated_lclk),
        .i_rst_n          (i_rst_n),
        .i_state          (i_lfsr_state),
        .i_scramble_en    (mapper_scramble_en),
        .i_width_deg_lfsr (i_width_deg),

        .i_lane           (mapper_lane),
        .o_lane           (lfsr_lane),

        .o_ser_en_lfsr    (o_lfsr_ser_en),
        .o_Lfsr_tx_done   (o_lfsr_tx_done)
    );

    // =========================================================================
    // 3. TX reversal (array) - placed right after lfsr_tx, before the output.
    //    Drives the hard-macro data serializers.
    // =========================================================================
    unit_mb_tx_reversal_array #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES)
    ) u_tx_reversal (
        .i_reversal_en (i_reversal_en),
        .i_lane        (lfsr_lane),
        .o_lane        (o_lfsr_lane)
    );

    // =========================================================================
    // 4. VALID_TX  (frame gating driven by the LFSR serializer-enable)
    // =========================================================================
    unit_valid_tx u_valid_tx (
        .i_clk            (i_gated_lclk),
        .i_rst_n          (i_rst_n),
        .valid_pattern_en (i_valid_pattern_en),
        .ser_en_lfsr_i    (o_lfsr_ser_en),

        .ser_en_o         (o_valid_ser_en),
        .O_done           (o_valid_done),
        .o_TVLD_L         (o_valid_word)
    );

    // =========================================================================
    // 5. LFSR_RX : descramble + locally-generated reference (o_final_gene)
    // =========================================================================
    unit_lfsr_rx #(
        .WIDTH (DATA_WIDTH)
    ) u_lfsr_rx (
        .i_clk            (i_gated_lclk),
        .i_rst_n          (i_rst_n),
        .i_state          (i_state),
        .i_width_deg_lfsr (i_width_deg_rx),
        .i_enable_buffer  (i_data_valid),
        .i_data_in        (i_par_data),
        .o_Data_by        (o_rx_lane),
        .o_final_gene     (lfsr_final_gene),
        .pattern_comp_en  (o_pattern_comp_en),
        .o_data_valid     (i_data_valid_rx)
    );

    // =========================================================================
    // 6. Demapper : reconstruct the protocol bus
    // =========================================================================
    unit_demapper #(
        .N_BYTES   (N_BYTES),
        .NUM_LANES (NUM_LANES),
        .WIDTH     (DATA_WIDTH)
    ) u_demap (
        .i_clk             (i_gated_lclk),
        .i_rst_n           (i_rst_n),
        .i_lane_0 (o_rx_lane[0]),  .i_lane_1 (o_rx_lane[1]),  .i_lane_2 (o_rx_lane[2]),  .i_lane_3 (o_rx_lane[3]),
        .i_lane_4 (o_rx_lane[4]),  .i_lane_5 (o_rx_lane[5]),  .i_lane_6 (o_rx_lane[6]),  .i_lane_7 (o_rx_lane[7]),
        .i_lane_8 (o_rx_lane[8]),  .i_lane_9 (o_rx_lane[9]),  .i_lane_10(o_rx_lane[10]), .i_lane_11(o_rx_lane[11]),
        .i_lane_12(o_rx_lane[12]), .i_lane_13(o_rx_lane[13]), .i_lane_14(o_rx_lane[14]), .i_lane_15(o_rx_lane[15]),
        .demapper_en       (demapper_en),
        .rx_data_valid     (i_data_valid_rx),
        .i_width_deg_demap (i_width_deg_rx),
        .pl_valid          (o_pl_valid),
        .o_out_data        (o_out_data)
    );

    // =========================================================================
    // 7. Pattern comparator (training): local reference vs descrambled lanes
    // =========================================================================
    unit_mb_pattern_comparator #(
        .NUM_LANES (NUM_LANES),
        .WIDTH     (DATA_WIDTH)
    ) u_pat_cmp (
        .i_clk                          (i_gated_lclk),
        .i_rst_n                        (i_rst_n),
        .i_enable                       (i_pcmp_enable),
        .i_comparison_mode              (i_pcmp_mode),
        .i_lane_mask                    (i_pcmp_lane_mask),
        .i_max_error_threshold_per_lane (i_pcmp_thr_per_lane),
        .i_max_error_threshold_aggregate(i_pcmp_thr_aggregate),
        .i_iteration_count              (i_pcmp_iter_count),
        .i_pattern_mode                 (i_pcmp_pattern_mode),
        .i_clear_error                  (i_pcmp_clear),
        .i_local_pattern                (lfsr_final_gene),
        .i_rx_pattern                   (o_rx_lane),
        .i_pcmp_enable                  (o_pattern_comp_en),
        .o_done                         (o_pcmp_done),
        .o_per_lane_pass                (o_pcmp_per_lane_pass),
        .o_aggregate_error              (o_pcmp_agg_error)
    );

    // =========================================================================
    // 8. Valid comparator : check the recovered valid frame stream. o_vcmp_done
    //    also feeds back into the hard-macro valid deserializer.
    // =========================================================================
    unit_valid_comparator #(
        .WIDTH      (DATA_WIDTH),
        .VALID_BYTE (VALID_PATTERN[7:0])
    ) u_valid_cmp (
        .i_clk                 (i_gated_lclk),
        .i_rst_n               (i_rst_n),
        .i_enable              (i_vcmp_enable),
        .i_mode                (i_vcmp_mode),
        .i_max_error_threshold (i_vcmp_thr),
        .i_clear_error         (i_vcmp_clear),
        .i_valid_frame_data    (i_valid_frame_data),
        .i_valid_frame_vld     (i_valid_frame_vld),
        .o_done                (o_vcmp_done),
        .o_pass                (o_vcmp_pass),
        .o_valid_frame_error   (o_valid_frame_error)
    );

    // =========================================================================
    // 9. Clock pattern detector (samples the raw forwarded clock/track)
    // =========================================================================
    unit_clk_pattern_detector_rx u_clk_det (
        .i_clk              (i_pll_clk),
        .i_rst_n            (i_rst_n),
        .clk_detector_en    (i_clk_detector_en),
        .clk_p              (i_RCKP_P),
        .clk_n              (i_RCKN_P),
        .track              (i_RTRK_P),
        .clk_p_pattern_pass (o_clk_p_pass),
        .clk_n_pattern_pass (o_clk_n_pass),
        .track_pattern_pass (o_track_pass)
    );

endmodule
