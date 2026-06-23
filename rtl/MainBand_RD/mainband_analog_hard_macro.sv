`timescale 1ns/1ps
// =============================================================================
// Module  : mainband_analog_hard_macro
// Project : UCIe 3.0 Main-Band Physical Layer
//
// Purpose : The Main-Band "analog hard macro" - the physical SerDes + clocking
//           front-end carved out of the Main-Band top, exactly like
//           sideband_analog_hard_macro was carved out of the Sideband top.
//
//           Contains ONLY the analog/physical blocks:
//             TX : MB_PLL, clk-divider, two clock gates,
//                  16 data serializers + 1 valid serializer, tri-state buffer.
//             RX : valid deserializer + frame detector,
//                  16 data deserializers (sampled on the forwarded RX clock).
//
//           Everything digital (mapper, lfsr_tx, valid_tx, lane-reversal,
//           clk-pattern-gen, lfsr_rx, demapper, pattern/valid comparators,
//           clk-detector) stays OUTSIDE in the digital Main-Band design and
//           connects through the parallel/control ports below.
//
//  Boundary notes
//  --------------
//   * Lane reversal is NOT here: it now lives in the digital design as an array
//     placed right after lfsr_tx (before serialization). The serializers feed
//     the tri-state buffer directly (TD_P_int -> tri_state).
//   * The clock-pattern generator stays in the digital design: its serial
//     outputs arrive here as i_tckp_p_pre / i_tckn_p_pre / i_ttrk_p_pre and are
//     passed through the tri-state buffer to the o_TCK*/o_TTRK pins.
//   * The valid comparator stays in the digital design: its done flag is fed
//     back into the valid deserializer through i_vcmp_done.
//  Simulation only.
// =============================================================================

module mainband_analog_hard_macro #(
    parameter int  DATA_WIDTH    = 32,                 // parallel lane-word width
    parameter int  NUM_LANES     = 16,                 // number of data lanes
    parameter      [DATA_WIDTH-1:0] VALID_PATTERN = 32'h0F0F0F0F
)(
    // -------------------------------------------------------------------------
    // Clocks / reset
    // -------------------------------------------------------------------------
    input  logic                    i_rst_n,               // active-low reset
    input  logic [2:0]              i_pll_speed_sel,       // 000=2G .. 11=16G
    input  logic                    lclk_g,                // debug clock-gate enable
    output logic                    lclk,                  // RDI LCLK (pll/16)
    output logic                    gated_lclk,            // gated lclk for MB TX
    output logic                    pll_clk,               // gated high-speed PLL clock

    // -------------------------------------------------------------------------
    // TX serializer parallel inputs (from lfsr_tx / valid_tx in the digital MB,
    // already lane-reversed upstream)
    // -------------------------------------------------------------------------
    input  logic                    lfsr_ser_en,           // data-lane serializer enable
    input  logic [DATA_WIDTH-1:0]   lfsr_lane [0:NUM_LANES-1], // per-lane words to serialize
    input  logic                    valid_ser_en,          // valid-lane serializer enable
    input  logic [DATA_WIDTH-1:0]   valid_word,            // 32-bit TVLD pattern word

    // -------------------------------------------------------------------------
    // TX clock-pattern pre-tri-state inputs (from clk_pattern_gen_tx, kept in
    // the digital MB)
    // -------------------------------------------------------------------------
    input  logic                    i_tckp_p_pre,          // differential clock +  pre tri-state
    input  logic                    i_tckn_p_pre,          // differential clock -  pre tri-state
    input  logic                    i_ttrk_p_pre,          // clock tracking        pre tri-state

    // -------------------------------------------------------------------------
    // TX tri-state per-group selects
    // -------------------------------------------------------------------------
    input  logic [1:0]              i_mb_tx_data_lane_sel, // data-lane tri-state enable
    input  logic [1:0]              i_mb_tx_val_lane_sel,  // valid-lane tri-state enable
    input  logic [1:0]              i_mb_tx_clk_lane_sel,  // clk_p/clk_n tri-state enable
    input  logic [1:0]              i_mb_tx_trk_lane_sel,  // track-lane tri-state enable

    // -------------------------------------------------------------------------
    // TX serialized physical outputs (DDR) - tri-stated
    // -------------------------------------------------------------------------
    output logic [NUM_LANES-1:0]    o_TD_P,                // serialized data lanes 0-15
    output logic                    o_TVLD_P,              // serialized valid lane
    output logic                    o_TCKP_P,              // differential clock +
    output logic                    o_TCKN_P,              // differential clock -
    output logic                    o_TTRK_P,              // clock tracking

    // -------------------------------------------------------------------------
    // RX clocks / control
    // -------------------------------------------------------------------------
    output real                     pll_period,            // PLL period (ps) - debug / RX timing
    input  logic [NUM_LANES-1:0]    i_rx_data_deser_en,    // per-lane data deserializer enable
    input  logic                    i_rx_valid_deser_en,   // valid deserializer enable
    input  logic                    i_vcmp_enable,         // valid-comparator enable (gates deser)
    input  logic                    i_vcmp_done,           // valid-comparator done (from digital MB)

    // -------------------------------------------------------------------------
    // RX serial physical inputs (from partner TX)
    // -------------------------------------------------------------------------
    input  logic [NUM_LANES-1:0]    i_RD_P,                // serialized data lanes
    input  logic                    i_RVLD_P,              // serialized valid lane
    input  logic                    i_RCKP_P,              // forwarded sampling clock +

    // -------------------------------------------------------------------------
    // RX recovered parallel outputs (to lfsr_rx / valid comparator in digital MB)
    // -------------------------------------------------------------------------
    output logic [DATA_WIDTH-1:0]   o_par_data [0:NUM_LANES-1], // descrambled-pending lane words
    output logic                    o_data_valid,          // any-lane deserialized word valid
    output logic [DATA_WIDTH-1:0]   valid_frame_data,      // recovered valid-frame word
    output logic                    valid_frame_vld        // recovered valid-frame strobe
);
    //===========================================================================================
    // Internal nets
    //===========================================================================================
    logic                    clk;          // high-speed serialization clock

    wire [NUM_LANES-1:0]     TD_P_int;     // data serializer outputs -> tri-state
    logic                    tvld_p_pre;   // valid serializer output -> tri-state

    logic                    sample_clk;   // forwarded RX clock, quarter-UI delayed

    logic [DATA_WIDTH-1:0]   valid_shift_reg;
    logic                    valid_count_16;
    logic                    i_valid_pulse;
    logic                    o_valid_frame_pulse;
    logic [NUM_LANES-1:0]    data_valid_lane;

    //===========================================================================================
    // MainBand
    //===========================================================================================

    // =========================================================================
    // 0a. MB_PLL  (active RTL - generates the high-speed serialization clock)
    // =========================================================================
    unit_mb_pll u_mb_pll (
        .en            (1'b1),
        .speed_sel     (i_pll_speed_sel),
        .clk           (clk),
        .local_period  (pll_period)
    );

    unit_clkdiv  u_clk_div (
        .i_ref_clk     (clk),
        .i_rst_n       (i_rst_n),
        .i_clk_en      (1'b1),
        .i_div_ratio   (8'd16),
        .o_div_clk     (lclk)
    );

    unit_clk_gate u_clk_gate (
        .CLK_EN   (lclk_g),
        .CLK      (lclk),
        .GATED_CLK(gated_lclk)
    );

    unit_clk_gate u_clk_gate_pll (
        .CLK_EN   (lclk_g),
        .CLK      (clk),
        .GATED_CLK(pll_clk)
    );

    // =========================================================================
    // 4.  Data-lane serializers  (one per lane, 16 total). Reversal is applied
    //     upstream in the digital MB, so the serializer outputs feed the
    //     tri-state buffer directly.
    // =========================================================================
    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin : gen_data_ser
            unit_mb_serializer #(
                .DATA_WIDTH (DATA_WIDTH)
            ) u_data_ser (
                .mb_clk  (gated_lclk),
                .PLL_clk (pll_clk),
                .i_rst_n (i_rst_n),
                .Ser_en  (lfsr_ser_en),
                .in_data (lfsr_lane[lane_idx]),
                .SER_out (TD_P_int[lane_idx])
            );
        end
    endgenerate

    // =========================================================================
    // 5.  Valid-lane serializer  (TVLD lane)
    // =========================================================================
    unit_mb_serializer #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_valid_ser (
        .mb_clk  (gated_lclk),
        .PLL_clk (pll_clk),
        .i_rst_n (i_rst_n),
        .Ser_en  (valid_ser_en),
        .in_data (valid_word),
        .SER_out (tvld_p_pre)
    );

    // =========================================================================
    // 6.  TX output tri-state buffers (data x16 + valid + clk_p/clk_n + track).
    //     The clk_p/clk_n/track pre-nets come from the clk-pattern generator
    //     that lives in the digital MB.
    // =========================================================================
    tri_state_buffer #(
        .NUM_LANES (NUM_LANES)
    ) u_tri_state_buffer (
        .i_TD_P                (TD_P_int),
        .i_TVLD_P              (tvld_p_pre),
        .i_TCKP_P              (i_tckp_p_pre),
        .i_TCKN_P              (i_tckn_p_pre),
        .i_TTRK_P              (i_ttrk_p_pre),
        .i_mb_tx_data_lane_sel (i_mb_tx_data_lane_sel),
        .i_mb_tx_val_lane_sel  (i_mb_tx_val_lane_sel),
        .i_mb_tx_clk_lane_sel  (i_mb_tx_clk_lane_sel),
        .i_mb_tx_trk_lane_sel  (i_mb_tx_trk_lane_sel),
        .o_TD_P                (o_TD_P),
        .o_TVLD_P              (o_TVLD_P),
        .o_TCKP_P              (o_TCKP_P),
        .o_TCKN_P              (o_TCKN_P),
        .o_TTRK_P              (o_TTRK_P)
    );

    // =========================================================================
    // 1. Recovered sampling clock : forwarded RX clock delayed a quarter UI.
    // =========================================================================
    assign #(pll_period/4000.0) sample_clk = i_RCKP_P;

    // =========================================================================
    // 2. Valid-lane deserializer + frame detector (sample_clk domain)
    // =========================================================================
    unit_valid_deserializer_s3 #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_valid_des (
        .pll_clk     (sample_clk),
        .mb_clk      (gated_lclk),
        .i_rst_n     (i_rst_n),
        .i_en        (i_rx_valid_deser_en),
        .ser_data_in (i_RVLD_P),
        .o_shift_reg (valid_shift_reg),
        .o_count_16  (valid_count_16),

        .i_vcmp_enable(i_vcmp_enable),
        .i_vcmp_done  (i_vcmp_done),

        .i_valid_pulse(i_valid_pulse),
        .o_valid_frame_data (valid_frame_data),
        .o_valid_frame_vld (valid_frame_vld)
    );

    unit_valid_frame_detector_s3 #(
        .DATA_WIDTH    (DATA_WIDTH),
        .VALID_PATTERN (VALID_PATTERN)
    ) u_frame_det (
        .i_shift_reg         (valid_shift_reg),
        .i_count_16          (valid_count_16),
        .o_valid_frame_pulse (o_valid_frame_pulse),
        .o_valid_pulse(i_valid_pulse)
    );

    // =========================================================================
    // 3. Data-lane deserializers (gated by the frame pulse)
    // =========================================================================
    genvar gi;
    generate
        for (gi = 0; gi < NUM_LANES; gi = gi + 1) begin : g_data_des
            unit_data_deserializer_s3 #(
                .DATA_WIDTH (DATA_WIDTH)
            ) u_data_des (
                .mb_clk              (gated_lclk),
                .pll_clk             (sample_clk),
                .i_rst_n             (i_rst_n),
                .i_en                (i_rx_data_deser_en[gi]),
                .ser_data_in         (i_RD_P[gi]),
                .i_valid_frame_pulse (o_valid_frame_pulse),
                .o_par_data          (o_par_data[gi]),
                .o_data_valid        (data_valid_lane[gi])
            );
        end
    endgenerate

    assign o_data_valid = |data_valid_lane;

endmodule
