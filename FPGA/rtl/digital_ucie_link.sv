`timescale 1ns/1ps
// =============================================================================
// Module  : digital_ucie_link
// Project : UCIe 3.0 PHY - FPGA bring-up (NO ANALOG, NOT LOOPED BACK)
//
// Purpose : Non-loopback sibling of digital_ucie_loopback.  Wraps digital_ucie
//           ALONE (no analog hard macro: no PLL, no SerDes, no tri-state) but,
//           instead of folding the MainBand/SideBand parallel boundary back on
//           itself, EXPOSES that boundary as top-level ports so two instances
//           (or a partner die / channel) can be cross-connected die-to-die.
//
//           The exposed boundary mirrors the internal loopback fold that
//           digital_ucie_loopback performs:
//
//             This die TX out           Partner die RX in (cross-wire)
//             ----------------          -------------------------------
//               o_mb_tx_ser_en       -> i_mb_rx_data_valid
//               o_mb_tx_lane[]       -> i_mb_rx_lane[]
//               o_mb_tx_valid_ser_en -> i_mb_rx_valid_frame_vld
//               o_mb_tx_valid_word   -> i_mb_rx_valid_frame_data
//               o_mb_tx_ckp/ckn/trk  -> i_mb_rx_ckp / i_mb_rx_ckn / i_mb_rx_trk
//               o_sb_tx_data         -> i_sb_rx_data
//               o_sb_tx_vld          -> i_sb_rx_vld
//               (i_sb_tx_rdy : partner "channel ready"; tie 1'b1 for a lossless
//                              parallel link, same as the loopback fold.)
//
//           The per-lane MainBand word array (o_mb_lfsr_lane / i_mb_par_data,
//           unpacked [0:NUM_LANES-1] of DATA_WIDTH_MB) is FLATTENED here into a
//           single packed vector [NUM_LANES*DATA_WIDTH_MB-1:0] so the boundary
//           is friendly to plain-Verilog wrappers and Vivado block designs.
//           Lane i occupies bits [i*DATA_WIDTH_MB +: DATA_WIDTH_MB].
//
//  Clocks  : supplied as inputs (no PLL; from MMCM / clock-enable tree on FPGA,
//            or driven by the testbench in simulation).
//              gated_lclk / lclk : MainBand word clock (= analog pll/16)
//              pll_clk           : fast clock for clk-pattern gen/detector
//              clk_sb            : Sideband parallel clock (= analog sb_pll/8)
//
//  NOTE   : Analog-only MainSM controls (PLL speed, tri-state lane selects, RX
//           deserializer enables, vcmp) are left open exactly as in the loopback
//           build - there is no hard macro to consume them.
// =============================================================================

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

module digital_ucie_link #(
    parameter int  DATA_WIDTH_MB  = 32,
    parameter int  DATA_WIDTH_SB  = 64,
    parameter int  NUM_LANES      = 16,
    parameter int  N_BYTES        = 64,
    parameter int  GAP_WIDTH      = 32,
    parameter      [DATA_WIDTH_MB-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS  = 0.5,
    parameter int  RX_ALIGN_DELAY = 2,
    parameter int  CLK_FRQ_HZ     = 800_000_000,
    parameter logic [2:0] MAX_LINK_WIDTH_CAP  = 3'd0,
    parameter logic [3:0] MAX_LINK_SPEED_CAP  = 4'h5,
    parameter logic       SPMW_CAP            = 1'b0,
    parameter logic       PMO_CAP             = 1'b1,
    parameter logic       PSPT_CAP            = 1'b0,
    parameter logic       L2SPD_CAP           = 1'b0,
    parameter logic [4:0] SUPPORTEDVSWING_CAP = 5'h01,
    parameter logic [1:0] CLK_MODE_CAP        = 2'b10,
    parameter logic [1:0] CLK_PHASE_CAP       = 2'b00,
    parameter logic       TARR_CAP            = 1'b0,
    parameter logic       ADVANCED_PKG_CAP    = 1'b0,
    parameter logic [1:0] MODULE_ID           = 2'b0
)(
    input  logic                             rst_n,

    // ---- Clocks (no PLL; from MMCM/clock-enables on FPGA) ----
    input  logic                             lclk,
    input  logic                             gated_lclk,
    input  logic                             pll_clk,
    input  logic                             clk_sb,

    // ---- MainBand flit data (adapter face) ----
    input  logic [8*N_BYTES-1:0]             lp_data,
    input  logic                             lp_irdy,
    input  logic                             lp_valid,
    output logic                             pl_trdy,
    output logic                             pl_error,
    output logic [8*N_BYTES-1:0]             pl_data,
    output logic                             pl_valid,

    // ---- Register access / config over sideband ----
    input  logic [31:0]                      lp_cfg,
    input  logic                             lp_cfg_vld,
    output logic                             pl_cfg_crd,
    input  logic                             lp_cfg_crd,
    output logic [31:0]                      pl_cfg,
    output logic                             pl_cfg_vld,

    // ---- RDI adapter-facing interface ----
    input  logic [3:0]                       lp_state_req,
    input  logic                             lp_clk_ack,
    input  logic                             lp_wake_req,
    input  logic                             lp_stallack,
    input  logic                             lp_linkerror,

    output logic                             pl_clk_req,
    output logic                             pl_stallreq,
    output logic                             pl_wake_ack,
    output logic                             pl_trainerror,
    output logic                             pl_inband_pres,
    output logic                             pl_phyinrecenter,
    output logic [3:0]                       pl_state_sts,
    output logic                             pl_max_speedmode,
    output logic [2:0]                       pl_speedmode,
    output logic [2:0]                       pl_lnk_cfg,

    // =========================================================================
    // Exposed MainBand parallel boundary (NOT looped back)
    // =========================================================================
    // -- TX out : cross-wire to the partner die's i_mb_rx_* inputs --
    output logic                             o_mb_tx_ser_en,
    output logic [NUM_LANES*DATA_WIDTH_MB-1:0] o_mb_tx_lane,
    output logic                             o_mb_tx_valid_ser_en,
    output logic [DATA_WIDTH_MB-1:0]         o_mb_tx_valid_word,
    output logic                             o_mb_tx_ckp,
    output logic                             o_mb_tx_ckn,
    output logic                             o_mb_tx_trk,
    // -- RX in : cross-wire from the partner die's o_mb_tx_* outputs --
    input  logic                             i_mb_rx_data_valid,
    input  logic [NUM_LANES*DATA_WIDTH_MB-1:0] i_mb_rx_lane,
    input  logic                             i_mb_rx_valid_frame_vld,
    input  logic [DATA_WIDTH_MB-1:0]         i_mb_rx_valid_frame_data,
    input  logic                             i_mb_rx_ckp,
    input  logic                             i_mb_rx_ckn,
    input  logic                             i_mb_rx_trk,

    // =========================================================================
    // Exposed SideBand parallel boundary (NOT looped back)
    // =========================================================================
    output logic [63:0]                      o_sb_tx_data,
    output logic                             o_sb_tx_vld,
    input  logic                             i_sb_tx_rdy,   // partner/channel ready (tie 1'b1)
    input  logic [63:0]                      i_sb_rx_data,
    input  logic                             i_sb_rx_vld,

    // ---- MainBand clock-gate enable (to top-level clock gate) ----
    output logic                             o_mb_lclk_g
);

    // =========================================================================
    // Boundary nets between the flat top ports and digital_ucie's native
    // unpacked/enum boundary.
    // =========================================================================
    logic [DATA_WIDTH_MB-1:0] mb_tx_lane_arr [0:NUM_LANES-1];  // digital_ucie TX out
    logic [DATA_WIDTH_MB-1:0] mb_rx_lane_arr [0:NUM_LANES-1];  // -> digital_ucie RX in

    RDI_state                 lp_state_req_int, pl_state_sts_int;
    assign lp_state_req_int = RDI_state'(lp_state_req);  // input  : 4-bit -> enum (into DUT)
    assign pl_state_sts     = pl_state_sts_int;          // output : enum (from DUT) -> 4-bit

    // Flatten TX lane array -> packed vector, and unpack RX vector -> lane array.
    // Lane i occupies bits [i*DATA_WIDTH_MB +: DATA_WIDTH_MB].
    genvar gi;
    generate
        for (gi = 0; gi < NUM_LANES; gi = gi + 1) begin : g_lane_pack
            assign o_mb_tx_lane[gi*DATA_WIDTH_MB +: DATA_WIDTH_MB] = mb_tx_lane_arr[gi];
            assign mb_rx_lane_arr[gi] = i_mb_rx_lane[gi*DATA_WIDTH_MB +: DATA_WIDTH_MB];
        end
    endgenerate

    // =========================================================================
    // The digital PHY - parallel boundary brought out to ports (no fold)
    // =========================================================================
    digital_ucie #(
        .DATA_WIDTH_MB       (DATA_WIDTH_MB),
        .DATA_WIDTH_SB       (DATA_WIDTH_SB),
        .NUM_LANES           (NUM_LANES),
        .N_BYTES             (N_BYTES),
        .GAP_WIDTH           (GAP_WIDTH),
        .VALID_PATTERN       (VALID_PATTERN),
        .PLL_PERIOD_NS       (PLL_PERIOD_NS),
        .RX_ALIGN_DELAY      (RX_ALIGN_DELAY),
        .CLK_FRQ_HZ          (CLK_FRQ_HZ),
        .MAX_LINK_WIDTH_CAP  (MAX_LINK_WIDTH_CAP),
        .MAX_LINK_SPEED_CAP  (MAX_LINK_SPEED_CAP),
        .SPMW_CAP            (SPMW_CAP),
        .PMO_CAP             (PMO_CAP),
        .PSPT_CAP            (PSPT_CAP),
        .L2SPD_CAP           (L2SPD_CAP),
        .SUPPORTEDVSWING_CAP (SUPPORTEDVSWING_CAP),
        .CLK_MODE_CAP        (CLK_MODE_CAP),
        .CLK_PHASE_CAP       (CLK_PHASE_CAP),
        .TARR_CAP            (TARR_CAP),
        .ADVANCED_PKG_CAP    (ADVANCED_PKG_CAP),
        .MODULE_ID           (MODULE_ID)
    ) u_digital_ucie (
        .rst_n                  (rst_n),

        // Clocks
        .lclk                   (lclk),
        .gated_lclk             (gated_lclk),
        .pll_clk                (pll_clk),
        .clk_sb                 (clk_sb),

        // MainBand control & data
        .lp_data                (lp_data),
        .lp_irdy                (lp_irdy),
        .lp_valid               (lp_valid),
        .pl_trdy                (pl_trdy),
        .pl_error               (pl_error),
        .pl_data                (pl_data),
        .pl_valid               (pl_valid),

        // ---- MainBand TX boundary -> exposed on top-level ports ----
        .o_mb_lfsr_ser_en       (o_mb_tx_ser_en),
        .o_mb_lfsr_lane         (mb_tx_lane_arr),
        .o_mb_valid_ser_en      (o_mb_tx_valid_ser_en),
        .o_mb_valid_word        (o_mb_tx_valid_word),
        .o_mb_tckp_p_pre        (o_mb_tx_ckp),
        .o_mb_tckn_p_pre        (o_mb_tx_ckn),
        .o_mb_ttrk_p_pre        (o_mb_tx_trk),
        // analog-only controls left open (no hard macro)
        .o_mb_pll_speed_sel     (),
        .o_mb_lclk_g            (o_mb_lclk_g),
        .o_mb_tx_data_lane_sel  (),
        .o_mb_tx_val_lane_sel   (),
        .o_mb_tx_clk_lane_sel   (),
        .o_mb_tx_trk_lane_sel   (),
        .o_mb_rx_data_deser_en  (),
        .o_mb_rx_valid_deser_en (),
        .o_mb_vcmp_enable       (),
        .o_mb_vcmp_done         (),

        // ---- RX recovered parallel words : from top-level ports ----
        .i_mb_par_data          (mb_rx_lane_arr),
        .i_mb_data_valid        (i_mb_rx_data_valid),
        .i_mb_valid_frame_data  (i_mb_rx_valid_frame_data),
        .i_mb_valid_frame_vld   (i_mb_rx_valid_frame_vld),

        // ---- Raw forwarded RX clock/track : from top-level ports ----
        .i_RCKP_P               (i_mb_rx_ckp),
        .i_RCKN_P               (i_mb_rx_ckn),
        .i_RTRK_P               (i_mb_rx_trk),

        // ---- Sideband parallel boundary : exposed on top-level ports ----
        .o_sb_pattern_mode      (),
        .o_sb_pmo_en            (),
        .o_sb_ser_data_send     (o_sb_tx_data),
        .o_sb_ser_vld_send      (o_sb_tx_vld),
        .i_sb_ser_rdy           (i_sb_tx_rdy),
        .i_sb_des_data_rcvd     (i_sb_rx_data),
        .i_sb_des_vld_rcvd      (i_sb_rx_vld),

        // ---- Adapter interface ----
        .lp_cfg                 (lp_cfg),
        .lp_cfg_vld             (lp_cfg_vld),
        .pl_cfg_crd             (pl_cfg_crd),
        .lp_cfg_crd             (lp_cfg_crd),
        .pl_cfg                 (pl_cfg),
        .pl_cfg_vld             (pl_cfg_vld),

        // ---- RDI adapter face ----
        .lp_state_req           (lp_state_req_int),
        .lp_clk_ack             (lp_clk_ack),
        .lp_wake_req            (lp_wake_req),
        .lp_stallack            (lp_stallack),
        .lp_linkerror           (lp_linkerror),
        .pl_clk_req             (pl_clk_req),
        .pl_stallreq            (pl_stallreq),
        .pl_wake_ack            (pl_wake_ack),
        .pl_trainerror          (pl_trainerror),
        .pl_inband_pres         (pl_inband_pres),
        .pl_phyinrecenter       (pl_phyinrecenter),
        .pl_state_sts           (pl_state_sts_int),
        .pl_max_speedmode       (pl_max_speedmode),
        .pl_speedmode           (pl_speedmode),
        .pl_lnk_cfg             (pl_lnk_cfg)
    );

endmodule
