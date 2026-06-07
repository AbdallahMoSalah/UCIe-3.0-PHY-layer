`timescale 1ns/1ps
// =============================================================================
// Module  : unit_tx_demap_wrapper
// Project : UCIe 3.0 Main-Band Physical Layer  (Integration steps)
//
// Purpose : Full TX->RX loopback wrapper. Closes the complete Main-Band datapath
//           around the frozen TX top and the "Solution 2" RX chain, all the way
//           back to the de-mapped protocol bus:
//
//   lp_data ─►[ unit_tx_top: mapper ─► lfsr_tx(scramble) ─► serializer x16 ]─► TD_P[15:0]
//                                    └─ valid_tx ─► serializer ───────────────► TVLD_P
//
//   TD_P[15:0] ─► unit_data_deserializer_s2 x16 ─► o_par_data[15:0] (scrambled)
//   TVLD_P     ─► unit_valid_deserializer_s2 ─► unit_valid_frame_detector_s2
//                                              └► valid_frame_pulse (FIFO WINC + clear)
//
//   o_par_data ─►[align delay]─► unit_lfsr_rx (descramble) ─► o_Data_by[15:0]
//                                                          ─► unit_demapper ─► o_out_data
//
//           The TB then checks o_out_data against the ORIGINAL lp_data. NOTE the
//           mapper and demapper use opposite byte orderings, so the recovered
//           flit is the BYTE-REVERSE of lp_data (demap o_out byte k == flit byte
//           63-k). This is the established behaviour of these blocks (the proven
//           unit_mb_path_tb compares the demapper against a demap *model* of the
//           mapper lanes for the same reason). The TB compares accordingly.
//
//  LFSR lockstep (the crux)
//  ------------------------
//   unit_lfsr_rx advances its LFSR EVERY clock while in DATA_TRANSFER (there is
//   no per-word enable) and descrambles with prbs32(current state). unit_lfsr_tx
//   does exactly the same on the TX side from the SAME seeds. They therefore stay
//   bit-aligned iff the RX is fed one fresh recovered word per clock with no
//   bubbles, starting from the word the TX scrambled with the seed (W0).
//     * The s2 data FIFO has matched write/read rates (one 32-bit frame per lclk)
//       so, after a constant 2-FF fill latency, o_data_valid is gap-free.
//     * This wrapper enters DATA_TRANSFER on the first o_data_valid and delays
//       o_par_data into unit_lfsr_rx by RX_ALIGN_DELAY clocks so the first
//       descramble (seed state) lands exactly on W0. From then on both LFSRs
//       advance 1:1 with the gap-free recovered stream and stay locked.
//
//  Clocking : identical to unit_tx_deser_wrapper - pll_clk tapped hierarchically
//             from unit_tx_top, rx_pll_clk is a quarter-period-delayed sampling
//             clock, lclk (pll/16) clocks the whole RX back-end. Simulation only.
// =============================================================================

module unit_tx_demap_wrapper #(
    parameter int  DATA_WIDTH      = 32,
    parameter int  NUM_LANES       = 16,
    parameter int  N_BYTES         = 64,
    parameter      [DATA_WIDTH-1:0] VALID_PATTERN  = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS   = 0.5,         // speed_sel=00 -> 500 ps
    parameter int  RX_ALIGN_DELAY  = 2            // o_par_data -> lfsr_rx input delay (lclk)
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
    output logic [DATA_WIDTH-1:0]   o_par_data   [0:NUM_LANES-1], // after deser (scrambled)
    output logic                    o_data_valid,
    output logic                    o_valid_frame_pulse,
    output logic [DATA_WIDTH-1:0]   o_rx_lane    [0:NUM_LANES-1], // after descramble (lfsr_rx)
    output logic                    o_rx_en,                      // RX back-end armed

    // ----------------------------------------------- final recovered flit
    output logic [8*N_BYTES-1:0]    o_out_data,                   // after demapper
    output logic                    o_pl_valid
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
    assign #(PLL_PERIOD_NS/4.0) rx_pll_clk = pll_clk_int;
    assign o_rx_pll_clk = rx_pll_clk;

    // =========================================================================
    // 2. Valid-lane deserializer + frame detector (Solution 2)
    // =========================================================================
    wire [DATA_WIDTH-1:0] valid_shift_reg;

    unit_valid_deserializer_s2 #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_valid_des (
        .pll_clk     (rx_pll_clk),
        .i_rst_n     (i_rst_n),
        .ser_data_in (TVLD_P),
        .i_clear     (o_valid_frame_pulse),
        .o_shift_reg (valid_shift_reg)
    );

    unit_valid_frame_detector_s2 #(
        .DATA_WIDTH    (DATA_WIDTH),
        .VALID_PATTERN (VALID_PATTERN)
    ) u_frame_det (
        .i_shift_reg         (valid_shift_reg),
        .o_valid_frame_pulse (o_valid_frame_pulse)
    );

    // =========================================================================
    // 3. Data-lane deserializers (gated by the frame pulse)
    // =========================================================================
    wire [NUM_LANES-1:0] data_valid_lane;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_LANES; gi = gi + 1) begin : g_data_des
            unit_data_deserializer_s2 #(
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

    assign o_data_valid = data_valid_lane[0];

    // =========================================================================
    // 4. RX back-end alignment : arm on first recovered word, delay the data
    //    so unit_lfsr_rx's first (seed) descramble lands on W0.
    // =========================================================================
    logic rx_en;
    always @(posedge lclk or negedge i_rst_n) begin
        if (!i_rst_n) rx_en <= 1'b0;
        else if (o_data_valid) rx_en <= 1'b1;
    end
    assign o_rx_en = rx_en;

    // RX_ALIGN_DELAY-deep per-lane pipeline on the recovered (scrambled) words.
    logic [DATA_WIDTH-1:0] rx_pipe [0:RX_ALIGN_DELAY-1][0:NUM_LANES-1];
    integer di, li;
    always @(posedge lclk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (di = 0; di < RX_ALIGN_DELAY; di = di + 1)
                for (li = 0; li < NUM_LANES; li = li + 1)
                    rx_pipe[di][li] <= {DATA_WIDTH{1'b0}};
        end else begin
            for (li = 0; li < NUM_LANES; li = li + 1)
                rx_pipe[0][li] <= o_par_data[li];
            for (di = 1; di < RX_ALIGN_DELAY; di = di + 1)
                for (li = 0; li < NUM_LANES; li = li + 1)
                    rx_pipe[di][li] <= rx_pipe[di-1][li];
        end
    end

    logic [DATA_WIDTH-1:0] rx_in [0:NUM_LANES-1];
    always @(*)
        for (li = 0; li < NUM_LANES; li = li + 1)
            rx_in[li] = rx_pipe[RX_ALIGN_DELAY-1][li];

    // unit_lfsr_rx control codes
    localparam logic [2:0] LFSR_IDLE = 3'b000;
    localparam logic [2:0] LFSR_DATA = 3'b100;
    wire [2:0] rx_state = rx_en ? LFSR_DATA : LFSR_IDLE;

    // =========================================================================
    // 5. LFSR_RX : descramble
    // =========================================================================
    unit_lfsr_rx #(
        .WIDTH (DATA_WIDTH)
    ) u_lfsr_rx (
        .i_clk            (lclk),
        .i_rst_n          (i_rst_n),
        .i_state          (rx_state),
        .i_width_deg_lfsr (i_width_deg),
        .i_descramble_en  (rx_en),
        .i_enable_buffer  (1'b0),
        .i_data_in        (rx_in),
        .o_Data_by        (o_rx_lane),
        .o_final_gene     (/* unused */),
        .pattern_comp_en  (/* unused */)
    );

    // =========================================================================
    // 6. Demapper : reconstruct the protocol bus
    // =========================================================================
    unit_demapper #(
        .N_BYTES   (N_BYTES),
        .NUM_LANES (NUM_LANES),
        .WIDTH     (DATA_WIDTH)
    ) u_demap (
        .i_clk             (lclk),
        .i_rst_n           (i_rst_n),
        .i_lane_0 (o_rx_lane[0]),  .i_lane_1 (o_rx_lane[1]),  .i_lane_2 (o_rx_lane[2]),  .i_lane_3 (o_rx_lane[3]),
        .i_lane_4 (o_rx_lane[4]),  .i_lane_5 (o_rx_lane[5]),  .i_lane_6 (o_rx_lane[6]),  .i_lane_7 (o_rx_lane[7]),
        .i_lane_8 (o_rx_lane[8]),  .i_lane_9 (o_rx_lane[9]),  .i_lane_10(o_rx_lane[10]), .i_lane_11(o_rx_lane[11]),
        .i_lane_12(o_rx_lane[12]), .i_lane_13(o_rx_lane[13]), .i_lane_14(o_rx_lane[14]), .i_lane_15(o_rx_lane[15]),
        .demapper_en       (1'b1),
        .rx_data_valid     (rx_en),
        .i_width_deg_demap (i_width_deg),
        .pl_valid          (o_pl_valid),
        .o_out_data        (o_out_data)
    );

endmodule
