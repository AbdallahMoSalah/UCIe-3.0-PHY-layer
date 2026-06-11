`timescale 1ns/1ps
// =============================================================================
// Module  : unit_mb_rx_top
// Project : UCIe 3.0 Main-Band Physical Layer (RX side)
// Purpose : Top-level wrapper for the Main-Band Receive (RX) datapath. Bundles
//           every RX leaf block built so far into one DUT so it can be driven by
//           a loopback against unit_tx_top.
//
//  Block diagram (RX)
//  ------------------
//   i_TVLD_P ─► valid_deser ─► (shift_reg,count_16) ─► valid_frame_detector
//                                                       │  ├─► valid_frame_pulse ──┐
//                                                       │  └─► frame_data/vld ─► valid_comparator
//                                                       │                           (NEW)
//   i_TD_P[15:0] ─► data_deser x16 (gated by valid_frame_pulse) ─► o_par_data[15:0]
//                                                                  (scrambled words)
//   o_par_data ─►[align delay]─► lfsr_rx (descramble) ─► o_rx_lane[15:0]
//                                       │                  └─► demapper ─► o_out_data (flit)
//                                       └─► o_final_gene ─► pattern_comparator (vs o_rx_lane)
//
//   i_TCKP_P / i_TCKN_P / i_TTRK_P ─► clk_pattern_detector_rx ─► clk/track pass flags
//
//  Clock domains
//  -------------
//   sample_clk : the DDR sampling clock for EVERY deserializer (valid + data).
//               It is the forwarded clock from the far-end TX (i_TCKP_P, i.e. the
//               clk-pattern generator output while i_clk_embedded_en=1) delayed by
//               a quarter UI so each DDR bit is latched mid-eye. The delay is built
//               here from i_period (the PLL period in ps, supplied by the same die
//               that drives the forwarded clock), so both sides share one clock.
//               Also clocks the valid frame detector and the valid comparator.
//   i_pll_clk : RX die's own PLL clock (quarter-shifted), used ONLY by the clock
//               pattern detector to sample the incoming clock burst during the
//               clock test (when no embedded clock is forwarded yet).
//   i_mb_clk  : recovered parallel-domain clock (PLL/16), also forwarded from the
//               far-end die. Clocks the data deserializer read side, lfsr_rx,
//               demapper and pattern comparator.
//
//  LFSR lockstep : identical scheme to unit_tx_demap_wrapper. lfsr_rx advances
//  every i_mb_clk while in DATA_TRANSFER, so it must be fed a gap-free recovered
//  word stream starting on W0. We arm on the first o_data_valid and delay
//  o_par_data into lfsr_rx by RX_ALIGN_DELAY clocks so the first (seed)
//  descramble lands exactly on W0.
// =============================================================================

module unit_mb_rx_top #(
    parameter int  DATA_WIDTH     = 32,
    parameter int  NUM_LANES      = 16,
    parameter int  N_BYTES        = 64,
    parameter      [DATA_WIDTH-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter int  RX_ALIGN_DELAY = 2
)(
    // ----------------------------------------------------------- clocks/reset
    input  logic                    i_rst_n,
    input  logic                    i_pll_clk,        // RX-local PLL clock (clk detector only)
    input  logic                    i_mb_clk,         // recovered parallel clock (pll/16)
    input  real                     i_period,         // UI/PLL period in ps (quarter-UI sampling delay)

    // ----------------------------------------------------- serial phy inputs
    input  logic [NUM_LANES-1:0]    i_RD_P,           // serialized data lanes
    input  logic                    i_RVLD_P,         // serialized valid lane
    input  logic                    i_RCKP_P,         // differential clock +
    input  logic                    i_RCKN_P,         // differential clock -
    input  logic                    i_RTRK_P,         // clock tracking

    // ----------------------------------------- datapath / lfsr_rx control
    input  logic [2:0]              i_width_deg_rx,      // lane-width degrade code
    input  logic [2:0]              i_state,        
    input  logic                    demapper_en,      // demapper enable (from data control)
    // --------------------------------------------- pattern comparator control
    input  logic                    i_pcmp_enable,
    input  logic                    i_pcmp_mode,            // 0 per-lane, 1 aggregate
    input  logic [NUM_LANES-1:0]    i_pcmp_lane_mask,
    input  logic [15:0]             i_pcmp_thr_per_lane,
    input  logic [15:0]             i_pcmp_thr_aggregate,
    input  logic [15:0]             i_pcmp_iter_count,
    input  logic                    i_pcmp_pattern_mode,    // 1 per-lane ID, 0 LFSR
    input  logic                    i_pcmp_clear,

    // ----------------------------------------------- valid comparator control
    input  logic                    i_vcmp_enable,
    input  logic                    i_vcmp_mode,            // 0 = 16 consec, 1 = threshold
    input  logic [15:0]             i_vcmp_thr,
    input  logic                    i_vcmp_clear,

    // ----------------------------------------------- clock detector control
    input  logic                    i_clk_detector_en,

    // ----------------------------------------------- recovered protocol bus
    output logic [8*N_BYTES-1:0]    o_out_data,
    output logic                    o_pl_valid,
    

    // ----------------------------------------------- pattern comparator results
    output logic                    o_pcmp_done,
    output logic [NUM_LANES-1:0]    o_pcmp_per_lane_pass,
    output logic [15:0]             o_pcmp_agg_err_cnt,
    output logic                    o_pcmp_agg_error,

    // ----------------------------------------------- valid comparator results
    output logic                    o_vcmp_done,
    output logic                    o_vcmp_pass,
    output logic                    o_valid_frame_error,

    // ----------------------------------------------- clk detector results
    output logic                    o_clk_p_pass,
    output logic                    o_clk_n_pass,
    output logic                    o_track_pass
);

    // =========================================================================
    // 0. Recovered sampling clock : forwarded TX clock (i_TCKP_P) delayed by a
    //    quarter UI so each DDR bit is latched in the eye centre. i_period is the
    //    PLL period in ps; with this module's 1ns/1ps timescale a delay value of 1
    //    means 1 ns, so the quarter-UI in ps is i_period/4 and we scale by /1000 to
    //    express it in ns:  delay_ns = (i_period/4)/1000 = i_period/4000.
    //    Driving every deserializer from this one clock means the valid lane and
    //    the 16 data lanes are sampled with identical phase (mid-eye), exactly as
    //    the ser/des loopback bench does. The clock follows the runtime period, so
    //    a mid-test PLL speed change is tracked automatically.
    // =========================================================================
    logic sample_clk;
    assign #(i_period/4000.0) sample_clk = i_RCKP_P;

    // =========================================================================
    // 1. Valid-lane deserializer + frame detector (sample_clk domain)
    // =========================================================================


    logic                    o_pattern_comp_en;           // lfsr_rx: training pattern valid


    logic [DATA_WIDTH-1:0]  o_par_data [0:NUM_LANES-1];
    logic                   o_data_valid;
    logic                   o_valid_frame_pulse;
    logic [DATA_WIDTH-1:0]  o_rx_lane [0:NUM_LANES-1];
    logic                   o_rx_en;
    assign o_rx_en = o_data_valid;

    logic i_valid_pulse;
    wire [DATA_WIDTH-1:0] valid_shift_reg;
    wire                  valid_count_16;
    wire [DATA_WIDTH-1:0] valid_frame_data;
    wire                  valid_frame_vld;

    unit_valid_deserializer_s3 #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_valid_des (
        .pll_clk     (sample_clk),
        .mb_clk      (i_mb_clk),
        .i_rst_n     (i_rst_n),
        .ser_data_in (i_RVLD_P),
        .o_shift_reg (valid_shift_reg),
        .o_count_16  (valid_count_16),
        
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
    // 2. Data-lane deserializers (gated by the frame pulse)
    // =========================================================================
    wire [NUM_LANES-1:0] data_valid_lane;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_LANES; gi = gi + 1) begin : g_data_des
            unit_data_deserializer_s3 #(
                .DATA_WIDTH (DATA_WIDTH)
            ) u_data_des (
                .mb_clk              (i_mb_clk),
                .pll_clk             (sample_clk),
                .i_rst_n             (i_rst_n),
                .ser_data_in         (i_RD_P[gi]),
                .i_valid_frame_pulse (o_valid_frame_pulse),
                .o_par_data          (o_par_data[gi]),
                .o_data_valid        (data_valid_lane[gi])
            );
        end
    endgenerate

    assign o_data_valid = data_valid_lane[0];

    // =========================================================================
    // 4. LFSR_RX : descramble + locally-generated reference (o_final_gene)
    // =========================================================================
    wire [DATA_WIDTH-1:0] lfsr_final_gene [0:NUM_LANES-1];
    logic i_data_valid;

    unit_lfsr_rx #(
        .WIDTH (DATA_WIDTH)
    ) u_lfsr_rx (
        .i_clk            (i_mb_clk),
        .i_rst_n          (i_rst_n),
        .i_state          (i_state),
        .i_width_deg_lfsr (i_width_deg_rx),
        .i_enable_buffer  (o_data_valid),
        .i_data_in        (o_par_data),
        .o_Data_by        (o_rx_lane),
        .o_final_gene     (lfsr_final_gene),
        .pattern_comp_en  (o_pattern_comp_en),
        .o_data_valid     (i_data_valid)
    );

    // =========================================================================
    // 5. Demapper : reconstruct the protocol bus
    // =========================================================================
    unit_demapper #(
        .N_BYTES   (N_BYTES),
        .NUM_LANES (NUM_LANES),
        .WIDTH     (DATA_WIDTH)
    ) u_demap (
        .i_clk             (i_mb_clk),
        .i_rst_n           (i_rst_n),
        .i_lane_0 (o_rx_lane[0]),  .i_lane_1 (o_rx_lane[1]),  .i_lane_2 (o_rx_lane[2]),  .i_lane_3 (o_rx_lane[3]),
        .i_lane_4 (o_rx_lane[4]),  .i_lane_5 (o_rx_lane[5]),  .i_lane_6 (o_rx_lane[6]),  .i_lane_7 (o_rx_lane[7]),
        .i_lane_8 (o_rx_lane[8]),  .i_lane_9 (o_rx_lane[9]),  .i_lane_10(o_rx_lane[10]), .i_lane_11(o_rx_lane[11]),
        .i_lane_12(o_rx_lane[12]), .i_lane_13(o_rx_lane[13]), .i_lane_14(o_rx_lane[14]), .i_lane_15(o_rx_lane[15]),
        .demapper_en       (demapper_en),
        .rx_data_valid     (i_data_valid),
        .i_width_deg_demap (i_width_deg_rx),
        .pl_valid          (o_pl_valid),
        .o_out_data        (o_out_data)
    );

    // =========================================================================
    // 6. Pattern comparator (training): local reference vs descrambled lanes
    // =========================================================================
    unit_mb_pattern_comparator #(
        .NUM_LANES (NUM_LANES),
        .WIDTH     (DATA_WIDTH)
    ) u_pat_cmp (
        .i_clk                          (i_mb_clk),
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
        .o_aggregate_error_counter      (o_pcmp_agg_err_cnt),
        .o_aggregate_error              (o_pcmp_agg_error)
    );

    // =========================================================================
    // 7. Valid comparator (NEW): check the recovered valid frame stream
    // =========================================================================
    unit_valid_comparator #(
        .WIDTH      (DATA_WIDTH),
        .VALID_BYTE (VALID_PATTERN[7:0])
    ) u_valid_cmp (
        .i_clk                 (i_mb_clk),
        .i_rst_n               (i_rst_n),
        .i_enable              (i_vcmp_enable),
        .i_mode                (i_vcmp_mode),
        .i_max_error_threshold (i_vcmp_thr),
        .i_clear_error         (i_vcmp_clear),
        .i_valid_frame_data    (valid_frame_data),
        .i_valid_frame_vld     (valid_frame_vld),
        .o_done                (o_vcmp_done),
        .o_pass                (o_vcmp_pass),
        .o_valid_frame_error   (o_valid_frame_error)
    );

    // =========================================================================
    // 8. Clock pattern detector
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
