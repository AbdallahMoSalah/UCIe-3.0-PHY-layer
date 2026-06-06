// =============================================================================
// Module  : unit_tx_top
// Project : UCIe 3.0 Main-Band Physical Layer
// Purpose : Fresh top-level wrapper for the Main-Band Transmit (TX) datapath,
//           built on the alternate sub-modules kept in this "unsued" folder.
//           (Independent of the rtl/MainBand/MB_TX_TOP version.)
//
//  Block diagram (TX)
//  ------------------
//        lclk / lp_irdy / lp_valid / lp_data ──► mapper ──► pl_trdy
//                                                  │
//                                 ┌────────────────┼───────────────┐
//                                 ▼                ▼               ▼
//                               lfsr            valid             clk
//                                 │                │               │
//                                 ▼                ▼          TCKP_P/TCKN_P/TTRK_P
//                          ser (x16) ──► TD_P[15:0]   ser ──► TVLD_P
//
//  Sub-modules (all from rtl/MainBand/unsued/ unless noted)
//  --------------------------------------------------------
//   mapper : Mapper             – maps protocol bus onto 16 lanes   (active RTL,
//                                  no unsued variant exists)
//   lfsr   : LFSR_TX            – scrambles / patterns each lane
//   valid  : VALID_TX           – generates the 32-bit valid word (TVLD)
//   ser    : MB_SERIALIZER      – one per data lane (16) + one for the valid lane
//   clk    : CLK_PATTERN_GEN_TX – differential clock pattern (no i_period port,
//                                  bundles its own phase_delay)
//   (pll)  : MB_PLL             – high-speed serialization clock   (active RTL,
//                                  no unsued variant exists)
//
//  Clock domains
//  -------------
//   lclk      : main-band functional clock (mapper, lfsr, valid, slow side of
//               every serializer)
//   pll_clk   : unit_mb_pll high-speed output (fast side of every serializer and the
//               clock-pattern generator)
// =============================================================================

module unit_tx_top #(
    parameter DATA_WIDTH = 32,   // width of each parallel lane word
    parameter NUM_LANES  = 16,   // number of data lanes
    parameter N_BYTES    = 64    // byte width of the raw protocol bus
)(
    // -------------------------------------------------------------------------
    // Clocks / reset
    // -------------------------------------------------------------------------
    input  logic                    i_rst_n,                // active-low reset

    // -------------------------------------------------------------------------
    // Mapper / adapter interface  (diagram: lp_* in, pl_trdy out)
    // -------------------------------------------------------------------------
    input  logic [8*N_BYTES-1:0]    lp_data,                // raw protocol data
    input  logic                    lp_irdy,                // adapter: data ready
    input  logic                    lp_valid,               // adapter: data valid
    output logic                    pl_trdy,                // unit_mapper accepted data

    // -------------------------------------------------------------------------
    // unit_mapper configuration
    // -------------------------------------------------------------------------
    input  logic                    i_mapper_en,            // enable the unit_mapper
    input  logic [2:0]              i_width_deg,            // lane-width degradation code

    // -------------------------------------------------------------------------
    // unit_lfsr_tx control
    // -------------------------------------------------------------------------
    input  logic [2:0]              i_lfsr_state,           // requested LFSR state
    input  logic                    i_reversal_en,          // physical lane reversal
    input  logic                    i_active_state_entered, // pulse: DATA_TRANSFER entered

    // -------------------------------------------------------------------------
    // unit_valid_tx control
    // -------------------------------------------------------------------------
    input  logic                    i_valid_pattern_en,     // trigger 32-cycle TVLD pattern

    // -------------------------------------------------------------------------
    // unit_mb_pll control
    // -------------------------------------------------------------------------
    input  logic                    i_pll_en,               // enable the PLL
    input  logic [1:0]              i_pll_speed_sel,        // 00=2G 01=4G 10=8G 11=16G
    input  logic                    lclk_g,                 // debug clock gate enable
    // -------------------------------------------------------------------------
    // unit_clk_pattern_gen_tx control
    // -------------------------------------------------------------------------
    input  logic                    i_clk_pattern_en,       // trigger 128-UI clock burst
    input  logic                    i_clk_embedded_en,      // continuous embedded-clock mode

    // -------------------------------------------------------------------------
    // Serialized physical outputs (DDR)  (diagram names)
    // -------------------------------------------------------------------------
    output logic                    lclk,                   //  RDI LCLK
    output logic [NUM_LANES-1:0]    TD_P,                   // serialized data lanes 0-15
    output logic                    TVLD_P,                 // serialized valid lane
    output logic                    TCKP_P,                 // differential clock +
    output logic                    TCKN_P,                 // differential clock -
    output logic                    TTRK_P,                 // clock tracking

    // -------------------------------------------------------------------------
    // Status / handshake
    // -------------------------------------------------------------------------
    output logic                    o_lfsr_tx_done,         // LFSR / ID phase complete pulse
    output logic                    o_valid_done,           // unit_valid_tx pattern-done pulse
    output logic                    o_clk_done              // clock-pattern burst complete pulse
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // ----- unit_mb_pll high-speed clock -------------------------------------------
    logic       gated_lclk;         // gated lclk for MB TX
    logic       pll_clk;            // high-speed serialization clock
    real        pll_period;         // PLL period (ps) – debug only, unused downstream

    // ----- Mapper → LFSR_TX (16 parallel lane words) -------------------------
    // unit_mapper has flat per-lane ports; unit_lfsr_tx takes an unpacked array.
    logic [DATA_WIDTH-1:0] mapper_lane_0,  mapper_lane_1,  mapper_lane_2,  mapper_lane_3;
    logic [DATA_WIDTH-1:0] mapper_lane_4,  mapper_lane_5,  mapper_lane_6,  mapper_lane_7;
    logic [DATA_WIDTH-1:0] mapper_lane_8,  mapper_lane_9,  mapper_lane_10, mapper_lane_11;
    logic [DATA_WIDTH-1:0] mapper_lane_12, mapper_lane_13, mapper_lane_14, mapper_lane_15;
    
    logic [DATA_WIDTH-1:0] mapper_lane [0:15];
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

    logic        mapper_scramble_en;   // Mapper → LFSR_TX: enable scrambling

    // ----- LFSR_TX → data serializers ----------------------------------------
    logic [DATA_WIDTH-1:0] lfsr_lane [0:15];   // scrambled lane words
    logic        lfsr_ser_en;          // LFSR serializer-enable (data lanes + valid gating)
    logic        lfsr_valid_frame_en;  // active-frame flag (unused by the unsued VALID_TX)

    // ----- VALID_TX → valid-lane serializer ----------------------------------
    logic [31:0] valid_word;           // 32-bit TVLD pattern word
    logic        valid_ser_en;         // unit_valid_tx serializer-enable

    // =========================================================================
    // 0a. MB_PLL  (active RTL – generates the high-speed serialization clock)
    // =========================================================================
    unit_mb_pll u_mb_pll (
        .en            (1'b1),
        .speed_sel     (i_pll_speed_sel),
        .clk           (pll_clk),
        .local_period  (pll_period)
    );

    unit_clkdiv  u_clk_div (
        .i_ref_clk     (pll_clk),
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

    // =========================================================================
    // 0b. CLK_PATTERN_GEN_TX  (unsued – clocked by the PLL output)
    // =========================================================================
    unit_clk_pattern_gen_tx u_clk_pattern_gen (
        .i_clk           (pll_clk),
        .i_rst_n         (i_rst_n),
        .clk_pattern_en  (i_clk_pattern_en),
        .clk_embedded_en (i_clk_embedded_en),
        .o_clk_p         (TCKP_P),
        .o_clk_n         (TCKN_P),
        .track           (TTRK_P),
        .o_done          (o_clk_done)
    );

    // =========================================================================
    // 1.  Mapper  (active RTL)
    // =========================================================================
    unit_mapper #(
        .WIDTH     (DATA_WIDTH),
        .NUM_LANES (NUM_LANES),
        .N_BYTES   (N_BYTES)
    ) u_mapper (
        .i_clk           (gated_lclk),
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
    // 2.  LFSR_TX  (unsued)
    // =========================================================================
    unit_lfsr_tx #(
        .WIDTH (DATA_WIDTH)
    ) u_lfsr_tx (
        .i_clk                  (gated_lclk),
        .i_rst_n                (i_rst_n),
        .i_state                (i_lfsr_state),
        .i_scramble_en          (mapper_scramble_en),
        .i_width_deg_lfsr       (i_width_deg),
        .i_reversal_en          (i_reversal_en),
        .i_active_state_entered (i_active_state_entered),

        .i_lane                 (mapper_lane),
        .o_lane                 (lfsr_lane),

        .o_ser_en_lfsr          (lfsr_ser_en),
        .o_Lfsr_tx_done         (o_lfsr_tx_done),
        .o_valid_frame_en       (lfsr_valid_frame_en)
    );

    // =========================================================================
    // 3.  VALID_TX  (unsued – frame gating driven by the LFSR serializer-enable)
    // =========================================================================
    unit_valid_tx u_valid_tx (
        .i_clk            (gated_lclk),
        .i_rst_n          (i_rst_n),
        .valid_pattern_en (i_valid_pattern_en),
        .ser_en_lfsr_i    (lfsr_ser_en),

        .ser_en_o         (valid_ser_en),
        .O_done           (o_valid_done),
        .o_TVLD_L         (valid_word)
    );

    // =========================================================================
    // 4.  Data-lane serializers  (unsued MB_SERIALIZER, one per lane, 16 total)
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
                .SER_out (TD_P[lane_idx])
            );
        end
    endgenerate

    // =========================================================================
    // 5.  Valid-lane serializer  (unsued MB_SERIALIZER, TVLD lane)
    // =========================================================================
    unit_mb_serializer #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_valid_ser (
        .mb_clk  (gated_lclk),
        .PLL_clk (pll_clk),
        .i_rst_n (i_rst_n),
        .Ser_en  (valid_ser_en),
        .in_data (valid_word),
        .SER_out (TVLD_P)
    );

endmodule
