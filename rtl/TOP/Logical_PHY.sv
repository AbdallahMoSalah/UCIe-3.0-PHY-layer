`timescale 1ps/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// Logical_PHY
// -----------------------------------------------------------------------------
// Final system-integration wrapper: stitches together the four already-verified
// blocks of the UCIe PHY logical layer:
//
//   * unit_mb_die    (u_mb_die)        - MainBand TX/RX die
//   * SideBand_Top   (u_sideband_top)  - Sideband (messaging + reg access + RDI)
//   * LTSM_TOP       (u_ltsm_top)      - Link Training State Machine
//   * RDI_SM         (u_rdi_sm)        - RDI (Raw D2D Interface) state machine
//
// This is *not* built on top of MB_SB_LTSM; it re-instantiates the same four
// leaf designs directly (MB_SB_LTSM is used only as a wiring reference) so the
// RDI_SM can be spliced into the internal nets.
//
// Notable internal connections introduced by RDI_SM integration:
//   * RDI_SM.state_sts  <= LTSM current_ltsm_state
//   * RDI_SM.rdi_state  -> LTSM.rdi_state            (new RDI_SM output)
//   * RDI_SM.pl_error   <= mb_die.o_valid_frame_error
//   * RDI_SM.lclk_g     -> mb_die.lclk_g             (RDI owns TX clock gating)
//   * SideBand traffic_req -> RDI_SM.traffic_req
//   * RDI_SM Link_Mgmt msg path <-> SideBand RDI msg ports
//       (SB stall_send tied 0; SB RDI_rdy / stall_rcvd left open)
//   * stall_done latch & AND with LTSM mapper-enable -> mb_die.i_mapper_en
//
// NOTE: PHYRETRAIN interplay between RDI and the LTSM is intentionally left
//       untouched for this integration step.
// =============================================================================

module Logical_PHY #(
    parameter int  DATA_WIDTH_MB  = 32,
    parameter int  DATA_WIDTH_SB  = 64,
    parameter int  NUM_LANES      = 16,
    parameter int  N_BYTES        = 64,
    parameter int  GAP_WIDTH      = 32,
    parameter      [DATA_WIDTH_MB-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter real PLL_PERIOD_NS  = 0.5,
    parameter int  RX_ALIGN_DELAY = 2,
    parameter int  CLK_FRQ_HZ     = 800_000_000
)(
    // =========================================================================
    // System Reset
    // =========================================================================
    input  logic                             rst_n,

    // =========================================================================
    // MainBand Control & Data
    // =========================================================================
    input  logic [8*N_BYTES-1:0]             lp_data,
    input  logic                             lp_irdy,
    input  logic                             lp_valid,
    output logic                             pl_trdy,

    // Observability outputs
    output logic                             lclk,
    output logic [8*N_BYTES-1:0]             pl_data,
    output logic                             pl_valid,

    // =========================================================================
    // MainBand Serial Interface
    // =========================================================================
    input  logic [NUM_LANES-1:0]             i_RD_P,
    input  logic                             i_RVLD_P,
    input  logic                             i_RCKP_P,
    input  logic                             i_RCKN_P,
    input  logic                             i_RTRK_P,

    output logic [NUM_LANES-1:0]             o_TD_P,
    output logic                             o_TVLD_P,
    output logic                             o_TCKP_P,
    output logic                             o_TCKN_P,
    output logic                             o_TTRK_P,

    // =========================================================================
    // Sideband Serial Interface
    // =========================================================================
    input  logic                             RXCKSB,
    output logic                             TXCKSB,
    output logic                             TXDATASB,
    input  logic                             RXDATASB,

    // Adapter Interface (RDI Control / config over sideband)
    input  logic [31:0]                      lp_cfg,
    input  logic                             lp_cfg_vld,
    output logic                             pl_cfg_crd,
    input  logic                             lp_cfg_crd,
    output logic [31:0]                      pl_cfg,
    output logic                             pl_cfg_vld,

    // Register File Interface (Reg_Access)
    output logic [24:0]                      rf_addr,
    output logic [7:0]                       rf_be,
    output logic                             rf_is_64b_access,
    output logic [63:0]                      rf_wdata,
    output logic                             rd_en,
    output logic                             wr_en,
    input  logic [63:0]                      rf_rdata,
    input  logic                             rdata_vld,
    input  logic                             addr_err_o,

    // =========================================================================
    // LTSM Controls & Observability
    // =========================================================================
    output logic [7:0]                       log0_state_n,
    output logic                             log0_lane_reversal,
    output logic                             log0_width_degrade,
    output logic [7:0]                       log0_state_n_minus_1,
    output logic [7:0]                       log0_state_n_minus_2,
    output logic [7:0]                       log1_state_n_minus_3,

    // RESET-state triggers / strap
    input  logic                             phy_start_ucie_link_training_ctrl_out,
    input  logic                             SPMW,

    // Capability configuration (to MBINIT)
    input  logic                             reg_phy_x8_mode_ctrl,
    input  logic                             reg_TARR_support_local_cap,
    input  logic                             reg_L2SPD_support_local_cap,
    input  logic                             reg_PSPT_support_local_cap,
    input  logic                             reg_PMO_support_local_cap,
    input  logic [3:0]                       reg_Max_Link_Speed_cap,
    input  logic [4:0]                       reg_Supported_TX_Vswing,
    input  logic                             reg_so,
    input  logic                             reg_mtp,
    input  logic [1:0]                       reg_Module_ID,
    input  logic [1:0]                       reg_Clock_Phase_cap,
    input  logic [1:0]                       reg_Clock_mode_cap,
    input  logic                             reg_TARR_support_local_ctrl,
    input  logic                             reg_PMO_support_local_ctrl,
    input  logic                             reg_Clock_Phase_ctrl,
    input  logic                             reg_Clock_mode_ctrl,
    input  logic                             reg_L2SPD_support_local_ctrl,
    input  logic                             reg_PSPT_support_local_ctrl,
    input  logic [3:0]                       reg_Target_Link_Width_ctrl,
    input  logic [3:0]                       reg_Target_Link_Speed_ctrl,

    // Capability status (from MBINIT)
    output logic                             reg_Clock_Phase_enable_status,
    output logic                             reg_Clock_mode_enable_status,
    output logic                             reg_TARR_enable_status,
    output logic [3:0]                       reg_Link_Width_enable_status,
    output logic [3:0]                       reg_Link_Speed_enable_status,
    output logic                             reg_PMO_enable_status,
    output logic                             reg_L2SPD_enable_status,
    output logic                             reg_PSPT_enable_status,
    output logic                             timeout_8ms_occured,
    input  logic                             start_bit,
    output logic                             busy_flag,
    output logic                             link_training_retraining,
    output logic                             link_status,

    // D2C / comparison thresholds + per-lane compare mask
    input  logic [11:0]                      cfg_max_err_thresh_perlane,
    input  logic [15:0]                      cfg_max_err_thresh_aggr,
    input  logic [NUM_LANES-1:0]             reg_lane_mask,

    // =========================================================================
    // RDI_SM Adapter-facing Interface
    // =========================================================================
    input  RDI_state                         lp_state_req,   // shared: RDI_SM + LTSM
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
    output RDI_state                         pl_state_sts,
    output logic                             pl_max_speedmode,
    output logic [2:0]                       pl_speedmode,
    output logic [2:0]                       pl_lnk_cfg,

    // RDI_SM DVSEC status inputs
    input  logic [3:0]                       UCIe_Link_DVSEC_UCIe_Link_Capability_7to4,
    input  logic [3:0]                       UCIe_Link_DVSEC_UCIe_Link_Status_17to11,
    input  logic [3:0]                       UCIe_Link_DVSEC_UCIe_Link_Status_10to7
);

    // =========================================================================
    // 1. Clocks and Resets Generation
    // =========================================================================

    // Sideband PLL clock generator (800 MHz)
    logic sb_pll_clock;
    real  sb_pll_period;

    sb_pll u_sb_pll (
        .en           (1'b1),
        .clk          (sb_pll_clock),
        .local_period (sb_pll_period)
    );

    // Clock divider by 8 to get 100 MHz for clk_sb
    logic clk_sb;

    ClkDiv #(
        .RangeWidth (8)
    ) u_clk_div_sb (
        .i_ref_clk   (sb_pll_clock),
        .i_rst_n     (rst_n),
        .i_clk_en    (1'b1),
        .i_div_ratio (8'd8),
        .o_div_clk   (clk_sb)
    );

    // =========================================================================
    // 2. Internal Signals
    // =========================================================================

    // ---- LTSM <-> SideBand message bus ----
    logic        sb_rx_valid;
    msg_no_e     sb_rx_msg_id;
    logic [15:0] sb_rx_MsgInfo;
    logic [63:0] sb_rx_data_Field;
    logic        sb_tx_valid;
    logic        sb_lsm_rdy;
    msg_no_e     sb_tx_msg_id;
    logic [15:0] sb_tx_MsgInfo;
    logic [63:0] sb_tx_data_Field;
    logic        sb_iter_done;
    logic        sbinit_pattern_mode;
    logic        sb_det_pattern_req;
    logic [2:0]  sbinit_req_iter_count;
    logic        sb_det_pattern_rcvd;
    logic [2:0]  mb_pll_speed_sel;
    // Casting wires for SideBand_Top LTSM message IDs
    logic [7:0]  ltsm_msg_n_send;
    logic [7:0]  ltsm_msg_no_rcvd;
    assign ltsm_msg_n_send = sb_tx_msg_id;
    assign sb_rx_msg_id    = msg_no_e'(ltsm_msg_no_rcvd);

    // ---- RDI_SM <-> SideBand RDI message bus ----
    msg_no_e     rdi_msg_send;          // RDI_SM.Link_Mgmt_Msg_Send
    logic        rdi_vld_send;          // RDI_SM.valid_s
    msg_no_e     rdi_msg_rcvd;          // RDI_SM.Link_Mgmt_Msg_Receive
    logic        rdi_vld_rcvd;          // RDI_SM.valid_r
    logic [7:0]  rdi_msg_no_send_bus;   // SideBand_Top.RDI_msg_no_send
    logic [7:0]  rdi_msg_no_rcvd_bus;   // SideBand_Top.RDI_msg_no_rcvd
    assign rdi_msg_no_send_bus = rdi_msg_send;                 // msg_no_e -> [7:0]
    assign rdi_msg_rcvd        = msg_no_e'(rdi_msg_no_rcvd_bus); // [7:0] -> msg_no_e

    // ---- RDI_SM <-> LTSM / MB ----
    RDI_state    rdi_state_w;      // RDI_SM.rdi_state -> LTSM.rdi_state
    logic        traffic_req_w;    // SideBand_Top.traffic_req -> RDI_SM.traffic_req
    logic        rdi_lclk_g;       // RDI_SM.lclk_g (raw gated clock - unused)
    logic        rdi_lclk_g_en;    // RDI_SM.lclk_g_en (enable level: 1=clock on)
    logic        mb_lclk_g;        // qualified clock-enable -> mb_die.lclk_g (CLK_EN)
    logic        stall_done_w;     // RDI_SM.stall_done (latched into mapper enable)

    // ---- LTSM macro-state + gated clock ----
    // (current_ltsm_state used to be auto-declared via the LTSM status port; it was
    //  dropped from the Logical_PHY port list during the interface edit, so it must
    //  be declared explicitly here — it is a multi-bit enum compared against
    //  ACTIVE/L1/L2 and wired to typed ports, not a 1-bit implicit net.)
    LTSM_state_e          current_ltsm_state;  // LTSM_TOP.current_ltsm_state (macro state)
    logic                 gated_lclk;          // mb_die.gated_lclk -> SideBand/LTSM clock

    // ---- LTSM <-> MainBand die control/result wires ----
    logic                 ltsm_mapper_en;   // LTSM mapper enable (pre-gate)
    logic                 mb_mapper_en;      // gated enable -> mb_die.i_mapper_en
    logic [2:0]           mb_width_deg_tx;
    logic [2:0]           mb_width_deg_rx;
    logic [2:0]           mb_lfsr_state;
    logic                 mb_reversal_en;
    logic                 mb_valid_pattern_en;
    logic                 mb_clk_pattern_en;
    logic [2:0]           mb_state;
    logic                 mb_demapper_en;
    logic                 mb_pcmp_enable;
    logic                 mb_pcmp_mode;
    logic [NUM_LANES-1:0] mb_pcmp_lane_mask;
    logic [15:0]          mb_pcmp_iter_count;
    logic                 mb_pcmp_pattern_mode;
    logic                 mb_pcmp_clear;
    logic                 mb_vcmp_enable;
    logic                 mb_vcmp_mode;
    logic                 mb_vcmp_clear;
    logic                 mb_clk_detector_en;
    logic [NUM_LANES-1:0] mb_rx_data_deser_en;
    logic                 mb_rx_valid_deser_en;
    logic                 mb_clk_embedded_en;
    logic [11:0]          mb_rx_max_err_thresh_perlane;
    logic [15:0]          mb_rx_max_err_thresh_aggr;

    // MB TX per-stream tri-state lane selects (LTSM -> mb_die tri_state_buff.en):
    // 2-bit each {[1]=Hi-Z, [0]=drive data vs 0}. MUST be 2-bit explicit decls,
    // else implicit 1-bit nets would drop bit[1] and break tri-stating (en==2'b10).
    logic [1:0]           mb_tx_trk_lane_sel;
    logic [1:0]           mb_tx_clk_lane_sel;
    logic [1:0]           mb_tx_val_lane_sel;
    logic [1:0]           mb_tx_data_lane_sel;

    logic                 mb_lfsr_tx_done;
    logic                 mb_valid_done;
    logic                 mb_clk_done;
    logic                 mb_pcmp_done;
    logic [NUM_LANES-1:0] mb_pcmp_per_lane_pass;
    logic                 mb_pcmp_agg_error;
    logic                 mb_vcmp_done;
    logic                 mb_vcmp_pass;
    logic                 mb_valid_frame_error;
    logic                 mb_clk_p_pass;
    logic                 mb_clk_n_pass;
    logic                 mb_track_pass;

    // =========================================================================
    // 3. stall_done latch + mapper-enable gating
    // -------------------------------------------------------------------------
    // The RDI stall_done pulse is captured into a level (SR flop on lclk) that
    // represents "data path stalled":
    //   * set   by stall_done   (RDI stall handshake complete -> stall the path)
    //   * clear when the LTSM mapper enable falls (acts as the latch reset)
    // The mapper is enabled in ACTIVE (ltsm_mapper_en) while NOT stalled, so data
    // flows in steady ACTIVE and is held off only during an RDI stall (the stall
    // precedes an ACTIVE-exit state change).  Hence the latch output is inverted.
    // =========================================================================
    logic stall_done_latched;
    logic clk_handshake_done;
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n)
            stall_done_latched <= 1'b0;
        else if (!ltsm_mapper_en)      // enable low -> clear the latch
            stall_done_latched <= 1'b0;
        else if (stall_done_w)         // set on stall_done (stalled)
            stall_done_latched <= 1'b1;
    end

    assign mb_mapper_en = ltsm_mapper_en & ~stall_done_latched;

    // -------------------------------------------------------------------------
    // RDI PM clock-gating qualifier  [INTEGRATION ADDITION - flagged for review]
    // -------------------------------------------------------------------------
    // mb_die.lclk_g is an active-high CLK_EN into a latch-based clock gate (the
    // working MB_SB_LTSM TB tied it to 1'b1).  RDI's lclk_g output is a *gated
    // clock*, not an enable, so it cannot drive CLK_EN directly; we use RDI's
    // ungating enable level (rdi_lclk_g_en: 1=clock on) instead.
    //
    // RDI also marks the clock gateable whenever pl_state_sts is Reset, and the
    // RDI SM sits in Reset for the whole LTSM training run, so its enable would
    // stop the MB TX clock and hang training.  PM clock-gating is only
    // meaningful once trained (ACTIVE) and entering L1/L2, so honour RDI's
    // enable only in ACTIVE/L1/L2 and force the clock on while training.
    wire ltsm_pm_phase = (current_ltsm_state == ACTIVE) ||
                         (current_ltsm_state == L1)     ||
                         (current_ltsm_state == L2);
    // Active-high gate request (1 = gate/stop the MB TX clock).  RDI requests
    // gating when its enable level is low (rdi_lclk_g_en==0); honour it only in
    // the PM phase (ACTIVE/L1/L2) and never gate while the LTSM is training.
    wire mb_clk_gate = ltsm_pm_phase & ~rdi_lclk_g_en;
    assign mb_lclk_g = ~mb_clk_gate;   // mb_die clk-gate CLK_EN: 1 = clock on

    // =========================================================================
    // 4. Module Instantiations
    // =========================================================================

    unit_mb_die #(
        .DATA_WIDTH     (DATA_WIDTH_MB),
        .NUM_LANES      (NUM_LANES),
        .N_BYTES        (N_BYTES),
        .VALID_PATTERN  (VALID_PATTERN),
        .PLL_PERIOD_NS  (PLL_PERIOD_NS),
        .RX_ALIGN_DELAY (RX_ALIGN_DELAY)
    ) u_mb_die (
        .i_rst_n              (rst_n),

        // TX control
        .lp_data              (lp_data),
        .lp_irdy              (lp_irdy),
        .lp_valid             (lp_valid),
        .pl_trdy              (pl_trdy),
        .i_mapper_en          (mb_mapper_en),
        .i_width_deg_tx       (mb_width_deg_tx),
        .i_width_deg_rx       (mb_width_deg_rx),
        .i_lfsr_state         (mb_lfsr_state),
        .i_reversal_en        (mb_reversal_en),
        .i_valid_pattern_en   (mb_valid_pattern_en),
        .i_pll_en             (1'b1),
        .i_pll_speed_sel      (mb_pll_speed_sel),
        .lclk_g               (mb_lclk_g),
        .i_clk_pattern_en     (mb_clk_pattern_en),
        .i_clk_embedded_en    (mb_clk_embedded_en),
        .i_mb_tx_trk_lane_sel                  (mb_tx_trk_lane_sel),
        .i_mb_tx_clk_lane_sel                  (mb_tx_clk_lane_sel),
        .i_mb_tx_val_lane_sel                  (mb_tx_val_lane_sel),
        .i_mb_tx_data_lane_sel                 (mb_tx_data_lane_sel),

        // RX control
        .i_state              (mb_state),
        .demapper_en          (mb_demapper_en),
        .i_pcmp_enable        (mb_pcmp_enable),
        .i_pcmp_mode          (mb_pcmp_mode),
        .i_pcmp_lane_mask     (mb_pcmp_lane_mask),
        .i_pcmp_thr_per_lane  (mb_rx_max_err_thresh_perlane),
        .i_pcmp_thr_aggregate (mb_rx_max_err_thresh_aggr),
        .i_pcmp_iter_count    (mb_pcmp_iter_count),
        .i_pcmp_pattern_mode  (mb_pcmp_pattern_mode),
        .i_pcmp_clear         (mb_pcmp_clear),
        .i_vcmp_enable        (mb_vcmp_enable),
        .i_vcmp_mode          (mb_vcmp_mode),
        .i_vcmp_thr           (mb_rx_max_err_thresh_perlane),
        .i_vcmp_clear         (mb_vcmp_clear),
        .i_clk_detector_en    (mb_clk_detector_en),
        .i_rx_data_deser_en   (mb_rx_data_deser_en),
        .i_rx_valid_deser_en  (mb_rx_valid_deser_en),

        // RX serial in (partner TX)
        .i_RD_P               (i_RD_P),
        .i_RVLD_P             (i_RVLD_P),
        .i_RCKP_P             (i_RCKP_P),
        .i_RCKN_P             (i_RCKN_P),
        .i_RTRK_P             (i_RTRK_P),

        // TX serial out (partner RX)
        .o_TD_P               (o_TD_P),
        .o_TVLD_P             (o_TVLD_P),
        .o_TCKP_P             (o_TCKP_P),
        .o_TCKN_P             (o_TCKN_P),
        .o_TTRK_P             (o_TTRK_P),

        // clocks / status
        .lclk                 (lclk),
        .gated_lclk           (gated_lclk),
        .o_lfsr_tx_done       (mb_lfsr_tx_done),
        .o_valid_done         (mb_valid_done),
        .o_clk_done           (mb_clk_done),

        // RX results + observability
        .o_out_data           (pl_data),
        .o_pl_valid           (pl_valid),
        .o_pcmp_done          (mb_pcmp_done),
        .o_pcmp_per_lane_pass (mb_pcmp_per_lane_pass),
        .o_pcmp_agg_error     (mb_pcmp_agg_error),
        .o_vcmp_done          (mb_vcmp_done),
        .o_vcmp_pass          (mb_vcmp_pass),
        .o_valid_frame_error  (mb_valid_frame_error),
        .o_clk_p_pass         (mb_clk_p_pass),
        .o_clk_n_pass         (mb_clk_n_pass),
        .o_track_pass         (mb_track_pass)
    );

    SideBand_Top #(
        .DATA_WIDTH (DATA_WIDTH_SB),
        .GAP_WIDTH  (GAP_WIDTH)
    ) u_sideband_top (
        .clk_main         (lclk),
        .clk_ltsm         (gated_lclk),
        .rst_main_n       (rst_n),
        .clk_sb           (clk_sb),
        .rst_sb_n         (rst_n),
        .phy_in_reset     (1'b0),
        .pmo_en           (reg_PMO_enable_status),

        .sb_pll_clock     (sb_pll_clock),
        .RXCKSB           (RXCKSB),
        .TXCKSB           (TXCKSB),
        .TXDATASB         (TXDATASB),
        .RXDATASB         (RXDATASB),

        .pattern_mode     (sbinit_pattern_mode),
        .start_pat_req    (sb_det_pattern_req),
        .req_iter_count   (sbinit_req_iter_count),
        .iter_done        (sb_iter_done),
        .det_pat_rcvd     (sb_det_pattern_rcvd),

        .traffic_req      (traffic_req_w),
        .traffic_rdy      (clk_handshake_done),

        // RDI message path (driven by RDI_SM)
        .RDI_msg_no_send  (rdi_msg_no_send_bus),
        .stall_send       (1'b0),                 // tied per integration spec
        .RDI_vld_send     (rdi_vld_send),
        .RDI_rdy          (),                      // unconnected per integration spec
        .RDI_vld_rcvd     (rdi_vld_rcvd),
        .RDI_msg_no_rcvd  (rdi_msg_no_rcvd_bus),
        .stall_rcvd       (),                      // unconnected per integration spec

        // LTSM message path
        .ltsm_msg_n_send  (ltsm_msg_n_send),
        .msg_data_send    (sb_tx_data_Field),
        .msg_info_send    (sb_tx_MsgInfo),
        .ltsm_vld_send    (sb_tx_valid),
        .ltsm_rdy         (sb_lsm_rdy),

        .ltsm_vld_rcvd    (sb_rx_valid),
        .ltsm_msg_no_rcvd (ltsm_msg_no_rcvd),
        .msg_data_rcvd    (sb_rx_data_Field),
        .msg_info_rcvd    (sb_rx_MsgInfo),

        .lp_cfg           (lp_cfg),
        .lp_cfg_vld       (lp_cfg_vld),
        .pl_cfg_crd       (pl_cfg_crd),
        .lp_cfg_crd       (lp_cfg_crd),
        .pl_cfg           (pl_cfg),
        .pl_cfg_vld       (pl_cfg_vld),

        .rf_addr          (rf_addr),
        .rf_be            (rf_be),
        .rf_is_64b_access (rf_is_64b_access),
        .rf_wdata         (rf_wdata),
        .rd_en            (rd_en),
        .wr_en            (wr_en),
        .rf_rdata         (rf_rdata),
        .rdata_vld        (rdata_vld),
        .addr_err_o       (addr_err_o)
    );

    LTSM_TOP #(
        .CLK_FRQ_HZ (CLK_FRQ_HZ),
        .NUM_LANES  (NUM_LANES)
    ) u_ltsm_top (
        .clk                                   (gated_lclk),
        .rst_n                                 (rst_n),

        // Status
        .current_ltsm_state                    (current_ltsm_state),
        .log0_state_n                          (log0_state_n),
        .log0_lane_reversal                    (log0_lane_reversal),
        .log0_width_degrade                    (log0_width_degrade),
        .log0_state_n_minus_1                  (log0_state_n_minus_1),
        .log0_state_n_minus_2                  (log0_state_n_minus_2),
        .log1_state_n_minus_3                  (log1_state_n_minus_3),

        // RESET-state triggers / strap
        // NOTE: Adapter_training_req is now generated internally inside
        // LTSM_wrapper from the lp_state_req Nop->Active edge (in RESET), so it
        // is no longer a port here. Training is started via phy_start below.
        .phy_start_ucie_link_training_ctrl_out (phy_start_ucie_link_training_ctrl_out),
        .sb_det_pattern_rcvd                   (sb_det_pattern_rcvd),
        .SPMW                                  (SPMW),

        // Capability configuration (to MBINIT)
        .reg_phy_x8_mode_ctrl                  (reg_phy_x8_mode_ctrl),
        .reg_TARR_support_local_cap            (reg_TARR_support_local_cap),
        .reg_L2SPD_support_local_cap           (reg_L2SPD_support_local_cap),
        .reg_PSPT_support_local_cap            (reg_PSPT_support_local_cap),
        .reg_PMO_support_local_cap             (reg_PMO_support_local_cap),
        .reg_Max_Link_Speed_cap                (reg_Max_Link_Speed_cap),
        .reg_Supported_TX_Vswing               (reg_Supported_TX_Vswing),
        .reg_so                                (reg_so),
        .reg_mtp                               (reg_mtp),
        .reg_Module_ID                         (reg_Module_ID),
        .reg_Clock_Phase_cap                   (reg_Clock_Phase_cap),
        .reg_Clock_mode_cap                    (reg_Clock_mode_cap),
        .reg_TARR_support_local_ctrl           (reg_TARR_support_local_ctrl),
        .reg_PMO_support_local_ctrl            (reg_PMO_support_local_ctrl),
        .reg_Clock_Phase_ctrl                  (reg_Clock_Phase_ctrl),
        .reg_Clock_mode_ctrl                   (reg_Clock_mode_ctrl),
        .reg_L2SPD_support_local_ctrl          (reg_L2SPD_support_local_ctrl),
        .reg_PSPT_support_local_ctrl           (reg_PSPT_support_local_ctrl),
        .reg_Target_Link_Width_ctrl            (reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl            (reg_Target_Link_Speed_ctrl),

        // Capability status (from MBINIT)
        .reg_Clock_Phase_enable_status         (reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status          (reg_Clock_mode_enable_status),
        .reg_TARR_enable_status                (reg_TARR_enable_status),
        .reg_Link_Width_enable_status          (reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status          (reg_Link_Speed_enable_status),
        .reg_PMO_enable_status                 (reg_PMO_enable_status),
        .reg_L2SPD_enable_status               (reg_L2SPD_enable_status),
        .reg_PSPT_enable_status                (reg_PSPT_enable_status),

        // D2C / comparison thresholds + per-lane compare mask
        .cfg_max_err_thresh_perlane            (cfg_max_err_thresh_perlane),
        .cfg_max_err_thresh_aggr               (cfg_max_err_thresh_aggr),
        .reg_lane_mask                         (reg_lane_mask),

        // Sideband message bus
        .sb_rx_valid                           (sb_rx_valid),
        .sb_rx_msg_id                          (sb_rx_msg_id),
        .sb_rx_MsgInfo                         (sb_rx_MsgInfo),
        .sb_rx_data_Field                      (sb_rx_data_Field),
        .sb_tx_valid                           (sb_tx_valid),
        .sb_ltsm_rdy                           (sb_lsm_rdy),
        .sb_tx_msg_id                          (sb_tx_msg_id),
        .sb_tx_MsgInfo                         (sb_tx_MsgInfo),
        .sb_tx_data_Field                      (sb_tx_data_Field),
        .sb_iter_done                          (sb_iter_done),
        .sbinit_pattern_mode                   (sbinit_pattern_mode),
        .sb_det_pattern_req                    (sb_det_pattern_req),
        .sbinit_req_iter_count                 (sbinit_req_iter_count),

        // RDI status
        .rdi_state                             (rdi_state_w),
        .lp_state_req                          (lp_state_req),

        // unit_mb_die-facing CONTROL outputs
        .i_mapper_en                           (ltsm_mapper_en),
        .mb_pll_speed_sel                      (mb_pll_speed_sel),
        .i_width_deg_tx                        (mb_width_deg_tx),
        .i_width_deg_rx                        (mb_width_deg_rx),
        .i_lfsr_state                          (mb_lfsr_state),
        .i_reversal_en                         (mb_reversal_en),
        .i_valid_pattern_en                    (mb_valid_pattern_en),
        .i_clk_pattern_en                      (mb_clk_pattern_en),
        .i_state                               (mb_state),
        .demapper_en                           (mb_demapper_en),
        .i_pcmp_enable                         (mb_pcmp_enable),
        .i_pcmp_mode                           (mb_pcmp_mode),
        .i_pcmp_lane_mask                      (mb_pcmp_lane_mask),
        .i_pcmp_iter_count                     (mb_pcmp_iter_count),
        .i_pcmp_pattern_mode                   (mb_pcmp_pattern_mode),
        .i_pcmp_clear                          (mb_pcmp_clear),
        .i_vcmp_enable                         (mb_vcmp_enable),
        .i_vcmp_mode                           (mb_vcmp_mode),
        .i_vcmp_clear                          (mb_vcmp_clear),
        .i_clk_detector_en                     (mb_clk_detector_en),
        .i_rx_data_deser_en                    (mb_rx_data_deser_en),
        .i_rx_valid_deser_en                   (mb_rx_valid_deser_en),
        .i_clk_embedded_en                     (mb_clk_embedded_en),
        .mb_tx_trk_lane_sel                    (mb_tx_trk_lane_sel),
        .mb_tx_clk_lane_sel                    (mb_tx_clk_lane_sel),
        .mb_tx_val_lane_sel                    (mb_tx_val_lane_sel),
        .mb_tx_data_lane_sel                   (mb_tx_data_lane_sel),
        .busy_flag                             (busy_flag),
        .link_status                           (link_status),
        .link_training_retraining              (link_training_retraining),
        .start_bit                             (start_bit),
        .timeout_8ms_occured                   (timeout_8ms_occured),
        .mb_rx_max_err_thresh_perlane          (mb_rx_max_err_thresh_perlane),
        .mb_rx_max_err_thresh_aggr             (mb_rx_max_err_thresh_aggr),
        
        // unit_mb_die-facing RESULT inputs
        .o_lfsr_tx_done                        (mb_lfsr_tx_done),
        .o_valid_done                          (mb_valid_done),
        .o_clk_done                            (mb_clk_done),
        .o_pcmp_done                           (mb_pcmp_done),
        .o_pcmp_per_lane_pass                  (mb_pcmp_per_lane_pass),
        .o_vcmp_done                           (mb_vcmp_done),
        .o_vcmp_pass                           (mb_vcmp_pass),
        .o_valid_frame_error                   (mb_valid_frame_error),
        .o_clk_p_pass                          (mb_clk_p_pass),
        .o_clk_n_pass                          (mb_clk_n_pass),
        .i_aggr_err                            (mb_pcmp_agg_error),
        .o_track_pass                          (mb_track_pass)
    );

    RDI_SM u_rdi_sm (
        .lclk                                       (lclk),
        .rst_n                                      (rst_n),

        // Adapter interface
        .lp_clk_ack                                 (lp_clk_ack),
        .lp_wake_req                                (lp_wake_req),
        .lp_stallack                                (lp_stallack),
        .lp_state_req                               (lp_state_req),
        .lp_linkerror                               (lp_linkerror),

        .pl_clk_req                                 (pl_clk_req),
        .pl_stallreq                                (pl_stallreq),
        .pl_wake_ack                                (pl_wake_ack),
        .pl_trainerror                              (pl_trainerror),
        .pl_inband_pres                             (pl_inband_pres),
        .pl_phyinrecenter                           (pl_phyinrecenter),
        .pl_state_sts                               (pl_state_sts),
        .pl_max_speedmode                           (pl_max_speedmode),
        .pl_speedmode                               (pl_speedmode),
        .pl_lnk_cfg                                 (pl_lnk_cfg),

        // Sideband DVSEC status
        .UCIe_Link_DVSEC_UCIe_Link_Capability_7to4  (UCIe_Link_DVSEC_UCIe_Link_Capability_7to4),
        .UCIe_Link_DVSEC_UCIe_Link_Status_17to11    (UCIe_Link_DVSEC_UCIe_Link_Status_17to11),
        .UCIe_Link_DVSEC_UCIe_Link_Status_10to7     (UCIe_Link_DVSEC_UCIe_Link_Status_10to7),

        // Sideband RDI message path
        .Link_Mgmt_Msg_Receive                      (rdi_msg_rcvd),
        .valid_r                                     (rdi_vld_rcvd),
        .Link_Mgmt_Msg_Send                         (rdi_msg_send),
        .valid_s                                     (rdi_vld_send),

        // Clock handshake
        .traffic_req                                (traffic_req_w),
        .clk_handshake_done                         (clk_handshake_done),

        // MainBand interface
        .lclk_g                                     (rdi_lclk_g),
        .lclk_g_en                                  (rdi_lclk_g_en),
        .stall_done                                 (stall_done_w),
        .pl_error                                   (mb_valid_frame_error),

        // LTSM interface
        .state_sts                                  (current_ltsm_state),
        .rdi_state                                  (rdi_state_w)
    );

endmodule
