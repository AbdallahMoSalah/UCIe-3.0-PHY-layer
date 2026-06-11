`timescale 1ns/1ps
// =============================================================================
// Module  : unit_tx_deser_wrapper
// Project : UCIe 3.0 Main-Band Physical Layer  (Integration steps)
//
// Purpose : Integration wrapper that closes a SER/DES loop around the frozen
//           Main-Band TX top (unit_tx_top) and the "Solution 2" RX
//           deserializer chain:
//
//               unit_tx_top  ──TD_P[15:0]──►  unit_data_deserializer_s2 x16 ─► o_par_data[15:0]
//                            ──TVLD_P──────►  unit_valid_deserializer_s2  ─► o_shift_reg
//                                                       │                       │
//                                                       ▼                       ▼
//                                          unit_valid_frame_detector_s2 ─► valid_frame_pulse
//                                                       │  (i_clear feedback) │  (FIFO WINC)
//                                                       └─────────────────────┘
//
//           The valid lane carries the canonical 0x0F0F0F0F frame; the frame
//           detector pulse (a) clears the valid shift-register history and
//           (b) latches every data deserializer's 32-bit window into its FIFO.
//           Because the data and valid serializers load on the same mb_clk edge
//           with identical DDR phase, the 30-bit history clear locks detection
//           to the 32-bit frame boundary, so each FIFO write captures one whole
//           serializer-input word (see the TB header for the bit-level proof).
//
//  Clocking
//  --------
//   * unit_tx_top owns the only oscillator: unit_mb_pll (.en hardwired to 1)
//     produces pll_clk INTERNALLY and divides it by 16 into lclk (an output).
//     pll_clk is NOT on unit_tx_top's port list, so this wrapper taps it with a
//     downward hierarchical reference (u_tx_top.pll_clk) - a simulation-only
//     integration block, exactly as the existing unit_tx_top_tb does.
//   * rx_pll_clk : pll_clk delayed by a QUARTER period so the RX samples the
//     centre of each serial bit-eye (matches unit_rx_deser_tb_s2's `#0.5` on a
//     2 ns PLL). PLL_PERIOD_NS must track i_pll_speed_sel (0.5 ns => speed=00).
//
//  NOTE: this wrapper is a verification/integration vehicle only (hierarchical
//        taps + transport-delayed clock); it is not intended for synthesis.
// =============================================================================

module unit_tx_deser_wrapper #(
    parameter int  DATA_WIDTH    = 32,            // bits per lane word
    parameter int  NUM_LANES     = 16,            // number of data lanes
    parameter int  N_BYTES       = 64,            // protocol-bus byte width
    parameter      [DATA_WIDTH-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS = 0.5            // PLL period (speed_sel=00 -> 500 ps)
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
    input  logic                    i_pll_en,           // no-op (PLL .en tied to 1) - kept for parity
    input  logic [1:0]              i_pll_speed_sel,
    input  logic                    lclk_g,
    input  logic                    i_clk_pattern_en,
    input  logic                    i_clk_embedded_en,

    // ----------------------------------------------- TX status / clocks out
    output logic                    lclk,               // mb_clk (= pll_clk / 16)
    output logic                    o_pll_clk,          // tapped internal PLL clock
    output logic                    o_rx_pll_clk,       // quarter-delayed RX sampling clock
    output logic                    o_lfsr_tx_done,
    output logic                    o_valid_done,
    output logic                    o_clk_done,

    // ----------------------------------------------- serial physical lanes
    output logic [NUM_LANES-1:0]    TD_P,
    output logic                    TVLD_P,
    output logic                    TCKP_P,
    output logic                    TCKN_P,
    output logic                    TTRK_P,

    // ----------------------------- "before serializer" tap (unit_tx_top input
    //                                to every MB serializer = scrambled lane word)
    output logic [DATA_WIDTH-1:0]   o_ser_in [0:NUM_LANES-1],
    output logic                    o_ser_en,           // serializer load-enable (lfsr_ser_en)

    // ----------------------------- "after deserializer" recovered words
    output logic [DATA_WIDTH-1:0]   o_par_data [0:NUM_LANES-1],
    output logic                    o_data_valid,
    output logic [DATA_WIDTH-1:0]   o_valid_shift_reg,
    output logic                    o_valid_frame_pulse
);

    // =========================================================================
    // Internal clocks
    // =========================================================================
    wire pll_clk_int;                       // tapped from unit_tx_top (internal net)
    wire rx_pll_clk;                        // quarter-delayed sampling clock

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

    // -------------------------------------------------------------------------
    // Downward hierarchical taps (unit_tx_top keeps these internal)
    //   pll_clk      : the high-speed serialization clock
    //   lfsr_lane[]  : the 32-bit word fed into each MB serializer ("before ser")
    //   lfsr_ser_en  : the serializer load-enable
    // -------------------------------------------------------------------------
    assign pll_clk_int = u_tx_top.pll_clk;
    assign o_pll_clk   = pll_clk_int;
    assign o_ser_en    = u_tx_top.lfsr_ser_en;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_LANES; gi = gi + 1) begin : g_serin_tap
            assign o_ser_in[gi] = u_tx_top.lfsr_lane[gi];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // RX sampling clock : pll_clk delayed by a quarter period (centre the eye)
    // -------------------------------------------------------------------------
    assign #(PLL_PERIOD_NS/4.0) rx_pll_clk = pll_clk_int;
    assign o_rx_pll_clk = rx_pll_clk;

    // =========================================================================
    // 2. Valid-lane deserializer + frame detector (Solution 3, gated count)
    // =========================================================================
    wire                  valid_count_16;

    unit_valid_deserializer_s3 #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_valid_des (
        .pll_clk     (rx_pll_clk),
        .i_rst_n     (i_rst_n),
        .ser_data_in (TVLD_P),
        .o_shift_reg (o_valid_shift_reg),
        .o_count_16  (valid_count_16)
    );

    unit_valid_frame_detector_s3 #(
        .DATA_WIDTH    (DATA_WIDTH),
        .VALID_PATTERN (VALID_PATTERN)
    ) u_frame_det (
        .i_rst_n             (i_rst_n),
        .i_clk               (rx_pll_clk),
        .i_shift_reg         (o_valid_shift_reg),
        .i_count_16          (valid_count_16),
        .o_valid_frame_pulse (o_valid_frame_pulse),
        .o_valid_frame_data  (),
        .o_valid_frame_vld   ()
    );

    // =========================================================================
    // 3. Data-lane deserializers (one per data lane, gated by the frame pulse)
    // =========================================================================
    wire [NUM_LANES-1:0] data_valid_lane;

    generate
        for (gi = 0; gi < NUM_LANES; gi = gi + 1) begin : g_data_des
            unit_data_deserializer_s3 #(
                .DATA_WIDTH (DATA_WIDTH)
            ) u_data_des (
                .mb_clk              (lclk),
                .pll_clk             (rx_pll_clk),
                .i_rst_n             (i_rst_n),
                .ser_data_in         (TD_P[gi]),
                .i_valid_frame_pulse (o_valid_frame_pulse),
                .o_par_data          (o_par_data[gi]),
                .o_data_valid        (data_valid_lane[gi])
            );
        end
    endgenerate

    // All 16 data deserializers share clocks + frame pulse, so they assert
    // o_data_valid on the same mb_clk edge. Expose lane 0's strobe as the
    // aggregate (the TB also self-checks the lanes stay in lock-step).
    assign o_data_valid = data_valid_lane[0];

endmodule
