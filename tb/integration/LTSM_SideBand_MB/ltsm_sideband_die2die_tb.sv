`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// Testbench : ltsm_sideband_die2die_tb
// DUT       : 2x LTSM_TOP  +  2x SideBand_Top  +  2x unit_mb_die
//             all three pairs fully cross-connected:
//               * SB serial    : TXCKSB/TXDATASB cross-connected
//               * SB msg bus   : ltsm_vld/rdy/msg lifted from LTSM_SideBand_tb
//               * MB serial    : TD/TVLD/TCKP/TCKN/TTRK cross-connected
//               * LTSM<->MB    : LTSM_TOP die-facing i_*/o_* <-> unit_mb_die
//
// Clocking
// --------
//   * Each unit_mb_die runs its own PLL (PLL_PERIOD_NS=0.5ns -> 2 GHz bit clk,
//     lclk = pll/16 = 125 MHz).  lclk drives that die's LTSM_TOP.clk.
//   * External SB clocks:
//       clk_sb     = 100 MHz  (clk_main / clk_sb of SideBand_Top)
//       clk_sbser  = 800 MHz  (sb_pll_clock serial bit clock)
//     Both are slower than the PLL bit rate (2 GHz).
//   * LTSM_TOP CLK_FRQ_HZ = 100_000 (timer-shrink trick: 8ms fires in ~800
//     lclk cycles instead of 1,000,000 -- same approach as LTSM_SideBand_tb).
//
// Reset sequencing
// ----------------
//   1. mb_rst_n released -> PLL starts, lclk begins toggling.
//   2. Wait for lclk0 stable (a few edges).
//   3. ltsm_rst_n + sb_rst_n released together.
// =============================================================================

module ltsm_sideband_die2die_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int  NUM_LANES      = 16;
    localparam int  DATA_WIDTH     = 32;
    localparam int  N_BYTES        = 64;
    localparam int  FLITW          = 8 * N_BYTES;
    localparam int  SB_DATA_WIDTH  = 64;
    localparam int  SB_GAP_WIDTH   = 32;
    localparam real PLL_PERIOD_NS  = 0.5;   // 2 GHz -> lclk = 8 ns (125 MHz)
    // CLK_FRQ_HZ is scaled to lclk (125 MHz) so that 8ms = 1000 cycles = 8µs real time,
    // matching the working LTSM_SideBand_tb (100 MHz, CLK_FRQ_HZ=100_000 → 800 cycles = 8µs).
    localparam int  LTSM_CLK_FRQ  = 125_000; // 8ms timer = 1000 lclk cycles = 8µs real time

    // External SB clocks (independent of mb_die PLL)
    localparam real CLK_SB_PERIOD    = 10.0;  // 100 MHz
    localparam real CLK_SBSER_PERIOD = 1.25;  // 800 MHz serial

    // =========================================================================
    // External SB clocks
    // =========================================================================
    logic clk_sb, clk_sbser;
    initial clk_sb    = 0; always #(CLK_SB_PERIOD   / 2.0) clk_sb    = ~clk_sb;
    initial clk_sbser = 0; always #(CLK_SBSER_PERIOD / 2.0) clk_sbser = ~clk_sbser;

    // =========================================================================
    // Resets (three separate domains)
    // =========================================================================
    logic mb_rst_n;    // unit_mb_die  (released first so PLL can start)
    logic ltsm_rst_n;  // LTSM_TOP    (released after lclk is stable)
    logic sb_rst_n;    // SideBand_Top (released with ltsm_rst_n)

    // =========================================================================
    // lclk from each mb_die -> used as LTSM_TOP.clk
    // lclk_g = gated lclk input to mb_die: loop back from die's own lclk output
    // =========================================================================
    logic lclk0, lclk1;
    wire  lclk_g0 = lclk0;
    wire  lclk_g1 = lclk1;

    // =========================================================================
    // Sideband serial cross-connect
    // =========================================================================
    logic TXCKSB  [2];
    logic RXCKSB  [2];
    logic TXDATASB[2];
    logic RXDATASB[2];

    logic block_sideband;
    initial block_sideband = 1'b0;

    assign RXCKSB[0]   = block_sideband ? 1'b0 : TXCKSB[1];
    assign RXDATASB[0] = block_sideband ? 1'b0 : TXDATASB[1];
    assign RXCKSB[1]   = block_sideband ? 1'b0 : TXCKSB[0];
    assign RXDATASB[1] = block_sideband ? 1'b0 : TXDATASB[0];

    // =========================================================================
    // LTSM <-> SideBand message bus  (index 0 = die 0, index 1 = die 1)
    // =========================================================================
    // TX path: LTSM_TOP -> SideBand_Top
    logic        sb_tx_valid     [2];
    msg_no_e     sb_tx_msg_id    [2];
    logic [15:0] sb_tx_MsgInfo   [2];
    logic [63:0] sb_tx_data_Field[2];
    logic        sb_ltsm_rdy     [2];

    // RX path: SideBand_Top -> LTSM_TOP
    logic        sb_rx_valid     [2];
    msg_no_e     sb_rx_msg_id    [2];
    logic [15:0] sb_rx_MsgInfo   [2];
    logic [63:0] sb_rx_data_Field[2];

    // SB pattern / iter signals
    logic        sb_iter_done          [2];
    logic        sbinit_pattern_mode   [2];
    logic        sb_det_pattern_req    [2];
    logic [2:0]  sbinit_req_iter_count [2];
    logic        sb_det_pattern_rcvd   [2];

    // msg_no_e <-> 8-bit cast (SideBand_Top uses plain logic[7:0])
    logic [7:0] tx_msg_id_cast[2];
    logic [7:0] rx_msg_id_cast[2];
    assign tx_msg_id_cast[0] = sb_tx_msg_id[0];
    assign tx_msg_id_cast[1] = sb_tx_msg_id[1];
    assign sb_rx_msg_id[0]   = msg_no_e'(rx_msg_id_cast[0]);
    assign sb_rx_msg_id[1]   = msg_no_e'(rx_msg_id_cast[1]);

    // =========================================================================
    // LTSM state observability
    // =========================================================================
    LTSM_state_e current_ltsm_state  [2];
    state_n_e    current_ltsm_state_n[2];
    logic        mbinit_error        [2];
    logic        active_error        [2];
    logic        timeout_8ms_occured [2];
    logic [7:0]  log0_state_n        [2];
    logic        log0_lane_reversal  [2];
    logic        log0_width_degrade  [2];

    logic m_done, p_done, m_error, p_error;
    assign m_done  = (current_ltsm_state_n[0] == LOG_ACTIVE);
    assign p_done  = (current_ltsm_state_n[1] == LOG_ACTIVE);
    assign m_error = (current_ltsm_state_n[0] == LOG_TRAINERROR);
    assign p_error = (current_ltsm_state_n[1] == LOG_TRAINERROR);

    // =========================================================================
    // LTSM capability registers (per die, TB-driven)
    // =========================================================================
    logic        phy_start              [2];
    logic        adapter_training_req   [2];
    logic [3:0]  reg_Target_Link_Width_ctrl[2];
    logic [3:0]  reg_Target_Link_Speed_ctrl[2];
    logic        reg_phy_x8_mode_ctrl   [2];

    // Capability status outputs
    logic        reg_Clock_Phase_enable_status[2];
    logic        reg_Clock_mode_enable_status [2];
    logic        reg_TARR_enable_status       [2];
    logic [3:0]  reg_Link_Width_enable_status [2];
    logic [3:0]  reg_Link_Speed_enable_status [2];
    logic        reg_PMO_enable_status        [2];
    logic        reg_L2SPD_enable_status      [2];
    logic        reg_PSPT_enable_status       [2];

    RDI_state    rdi_state[2];

    // =========================================================================
    // LTSM_TOP die-facing CONTROL outputs -> unit_mb_die inputs
    // =========================================================================
    logic                  i_mapper_en        [2];
    logic [2:0]            i_width_deg_tx     [2];
    logic [2:0]            i_width_deg_rx     [2];
    logic [2:0]            i_lfsr_state       [2];
    logic                  i_reversal_en      [2];
    logic                  i_valid_pattern_en [2];
    logic                  i_clk_pattern_en   [2];
    logic [2:0]            i_state            [2];
    logic                  demapper_en        [2];
    logic                  i_pcmp_enable      [2];
    logic                  i_pcmp_mode        [2];
    logic [NUM_LANES-1:0]  i_pcmp_lane_mask   [2];
    logic [15:0]           i_pcmp_iter_count  [2];
    logic                  i_pcmp_pattern_mode[2];
    logic                  i_pcmp_clear       [2];
    logic                  i_vcmp_enable      [2];
    logic                  i_vcmp_mode        [2];
    logic                  i_vcmp_clear       [2];
    logic                  i_clk_detector_en  [2];
    logic [NUM_LANES-1:0]  i_rx_data_deser_en [2];
    logic                  i_rx_valid_deser_en[2];
    logic                  i_clk_embedded_en  [2];

    // =========================================================================
    // LTSM_TOP die-facing RESULT inputs <- unit_mb_die outputs
    // =========================================================================
    logic                  o_lfsr_tx_done     [2];
    logic                  o_valid_done       [2];
    logic                  o_clk_done         [2];
    logic                  o_pcmp_done        [2];
    logic [NUM_LANES-1:0]  o_pcmp_per_lane_pass[2];
    logic                  o_vcmp_done        [2];
    logic                  o_vcmp_pass        [2];
    logic                  o_valid_frame_error[2];
    logic                  o_clk_p_pass       [2];
    logic                  o_clk_n_pass       [2];
    logic                  o_track_pass       [2];
    logic                  i_aggr_err         [2]; // <- mb_die.o_pcmp_agg_error

    // =========================================================================
    // MB serial cross-connect
    // =========================================================================
    logic [NUM_LANES-1:0] d0_TD_P;  logic d0_TVLD_P, d0_TCKP_P, d0_TCKN_P, d0_TTRK_P;
    logic [NUM_LANES-1:0] d1_TD_P;  logic d1_TVLD_P, d1_TCKP_P, d1_TCKN_P, d1_TTRK_P;

    logic                  reverse_lanes;
    logic [NUM_LANES-1:0]  d1_to_d0_data, d0_to_d1_data;

    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            d1_to_d0_data[i] = reverse_lanes ? d1_TD_P[NUM_LANES-1-i] : d1_TD_P[i];
            d0_to_d1_data[i] = reverse_lanes ? d0_TD_P[NUM_LANES-1-i] : d0_TD_P[i];
        end
    end

    // =========================================================================
    // Non-interface mb_die TB inputs (shared both dies)
    // =========================================================================
    logic [FLITW-1:0] lp_data       [2];
    logic             i_pll_en;
    logic [1:0]       i_pll_speed_sel;
    logic [15:0]      i_pcmp_thr_per_lane;
    logic [15:0]      i_pcmp_thr_aggregate;
    logic [15:0]      i_vcmp_thr;

    // mb_die observability outputs
    logic [FLITW-1:0] o_out_data [2];
    logic             o_pl_valid [2];
    logic             pl_trdy    [2];
    logic             o_pll_clk  [2];

    // =========================================================================
    // DUT : SideBand_Top[0]
    // =========================================================================
    SideBand_Top #(
        .DATA_WIDTH (SB_DATA_WIDTH),
        .GAP_WIDTH  (SB_GAP_WIDTH)
    ) u_sideband_0 (
        .clk_main         (lclk0),
        .rst_main_n       (sb_rst_n),
        .clk_sb           (clk_sb),
        .rst_sb_n         (sb_rst_n),
        .phy_in_reset     (!sb_rst_n),
        .pmo_en           (1'b1),
        .sb_pll_clock     (clk_sbser),
        .RXCKSB           (RXCKSB  [0]),
        .TXCKSB           (TXCKSB  [0]),
        .TXDATASB         (TXDATASB[0]),
        .RXDATASB         (RXDATASB[0]),
        .pattern_mode     (sbinit_pattern_mode  [0]),
        .start_pat_req    (sb_det_pattern_req   [0]),
        .req_iter_count   (sbinit_req_iter_count[0]),
        .iter_done        (sb_iter_done         [0]),
        .det_pat_rcvd     (sb_det_pattern_rcvd  [0]),
        .traffic_req      (),
        .traffic_rdy      (1'b1),
        .RDI_msg_no_send  (8'b0),
        .stall_send       (1'b0),
        .RDI_vld_send     (1'b0),
        .RDI_rdy          (),
        .ltsm_msg_n_send  (tx_msg_id_cast   [0]),
        .msg_data_send    (sb_tx_data_Field [0]),
        .msg_info_send    (sb_tx_MsgInfo    [0]),
        .ltsm_vld_send    (sb_tx_valid      [0]),
        .ltsm_rdy         (sb_ltsm_rdy      [0]),
        .RDI_vld_rcvd     (),
        .RDI_msg_no_rcvd  (),
        .stall_rcvd       (),
        .ltsm_vld_rcvd    (sb_rx_valid      [0]),
        .ltsm_msg_no_rcvd (rx_msg_id_cast   [0]),
        .msg_data_rcvd    (sb_rx_data_Field [0]),
        .msg_info_rcvd    (sb_rx_MsgInfo    [0]),
        .lp_cfg           (32'b0),
        .lp_cfg_vld       (1'b0),
        .pl_cfg_crd       (),
        .lp_cfg_crd       (1'b1),
        .pl_cfg           (),
        .pl_cfg_vld       (),
        .rf_addr          (),
        .rf_be            (),
        .rf_is_64b_access (),
        .rf_wdata         (),
        .rd_en            (),
        .wr_en            (),
        .rf_rdata         (64'b0),
        .rdata_vld        (1'b0),
        .addr_err_o       (1'b0)
    );

    // =========================================================================
    // DUT : SideBand_Top[1]
    // =========================================================================
    SideBand_Top #(
        .DATA_WIDTH (SB_DATA_WIDTH),
        .GAP_WIDTH  (SB_GAP_WIDTH)
    ) u_sideband_1 (
        .clk_main         (lclk1),
        .rst_main_n       (sb_rst_n),
        .clk_sb           (clk_sb),
        .rst_sb_n         (sb_rst_n),
        .phy_in_reset     (!sb_rst_n),
        .pmo_en           (1'b1),
        .sb_pll_clock     (clk_sbser),
        .RXCKSB           (RXCKSB  [1]),
        .TXCKSB           (TXCKSB  [1]),
        .TXDATASB         (TXDATASB[1]),
        .RXDATASB         (RXDATASB[1]),
        .pattern_mode     (sbinit_pattern_mode  [1]),
        .start_pat_req    (sb_det_pattern_req   [1]),
        .req_iter_count   (sbinit_req_iter_count[1]),
        .iter_done        (sb_iter_done         [1]),
        .det_pat_rcvd     (sb_det_pattern_rcvd  [1]),
        .traffic_req      (),
        .traffic_rdy      (1'b1),
        .RDI_msg_no_send  (8'b0),
        .stall_send       (1'b0),
        .RDI_vld_send     (1'b0),
        .RDI_rdy          (),
        .ltsm_msg_n_send  (tx_msg_id_cast   [1]),
        .msg_data_send    (sb_tx_data_Field [1]),
        .msg_info_send    (sb_tx_MsgInfo    [1]),
        .ltsm_vld_send    (sb_tx_valid      [1]),
        .ltsm_rdy         (sb_ltsm_rdy      [1]),
        .RDI_vld_rcvd     (),
        .RDI_msg_no_rcvd  (),
        .stall_rcvd       (),
        .ltsm_vld_rcvd    (sb_rx_valid      [1]),
        .ltsm_msg_no_rcvd (rx_msg_id_cast   [1]),
        .msg_data_rcvd    (sb_rx_data_Field [1]),
        .msg_info_rcvd    (sb_rx_MsgInfo    [1]),
        .lp_cfg           (32'b0),
        .lp_cfg_vld       (1'b0),
        .pl_cfg_crd       (),
        .lp_cfg_crd       (1'b1),
        .pl_cfg           (),
        .pl_cfg_vld       (),
        .rf_addr          (),
        .rf_be            (),
        .rf_is_64b_access (),
        .rf_wdata         (),
        .rd_en            (),
        .wr_en            (),
        .rf_rdata         (64'b0),
        .rdata_vld        (1'b0),
        .addr_err_o       (1'b0)
    );

    // =========================================================================
    // DUT : LTSM_TOP[0]   (clocked from lclk0 -- die 0's PLL-derived clock)
    // =========================================================================
    LTSM_TOP #(
        .CLK_FRQ_HZ (LTSM_CLK_FRQ),
        .NUM_LANES  (NUM_LANES)
    ) u_ltsm_top_0 (
        .clk   (lclk0),
        .rst_n (ltsm_rst_n),

        .current_ltsm_state       (current_ltsm_state  [0]),
        .current_ltsm_state_n     (current_ltsm_state_n[0]),
        .mbinit_error             (mbinit_error        [0]),
        .active_error             (active_error        [0]),
        .timeout_8ms_occured      (timeout_8ms_occured [0]),
        .log0_state_n             (log0_state_n        [0]),
        .log0_lane_reversal       (log0_lane_reversal  [0]),
        .log0_width_degrade       (log0_width_degrade  [0]),
        .log0_state_n_minus_1     (),
        .log0_state_n_minus_2     (),
        .log1_state_n_minus_3     (),

        .phy_start_ucie_link_training_ctrl_out (phy_start           [0]),
        .Adapter_training_req                  (adapter_training_req[0]),
        .sb_det_pattern_rcvd                   (sb_det_pattern_rcvd [0]),
        .SPMW                                  (1'b0),

        .reg_phy_x8_mode_ctrl        (reg_phy_x8_mode_ctrl       [0]),
        .reg_TARR_support_local_cap  (1'b1),
        .reg_L2SPD_support_local_cap (1'b1),
        .reg_PSPT_support_local_cap  (1'b1),
        .reg_PMO_support_local_cap   (1'b1),
        .reg_Max_Link_Speed_cap      (4'b0101),
        .reg_Supported_TX_Vswing     (5'b00111),
        .reg_so                      (1'b0),
        .reg_mtp                     (1'b1),
        .reg_Module_ID               (2'b00),
        .reg_Clock_Phase_cap         (2'b01),
        .reg_Clock_mode_cap          (2'b01),
        .reg_TARR_support_local_ctrl (1'b1),
        .reg_PMO_support_local_ctrl  (1'b1),
        .reg_Clock_Phase_ctrl        (1'b1),
        .reg_Clock_mode_ctrl         (1'b1),
        .reg_L2SPD_support_local_ctrl(1'b1),
        .reg_PSPT_support_local_ctrl (1'b1),
        .reg_Target_Link_Width_ctrl  (reg_Target_Link_Width_ctrl[0]),
        .reg_Target_Link_Speed_ctrl  (reg_Target_Link_Speed_ctrl[0]),

        .reg_Clock_Phase_enable_status (reg_Clock_Phase_enable_status[0]),
        .reg_Clock_mode_enable_status  (reg_Clock_mode_enable_status [0]),
        .reg_TARR_enable_status        (reg_TARR_enable_status       [0]),
        .reg_Link_Width_enable_status  (reg_Link_Width_enable_status [0]),
        .reg_Link_Speed_enable_status  (reg_Link_Speed_enable_status [0]),
        .reg_PMO_enable_status         (reg_PMO_enable_status        [0]),
        .reg_L2SPD_enable_status       (reg_L2SPD_enable_status      [0]),
        .reg_PSPT_enable_status        (reg_PSPT_enable_status       [0]),

        .cfg_max_err_thresh_perlane (12'd10),
        .cfg_max_err_thresh_aggr    (16'd50),
        .reg_lane_mask              ('0),

        .sb_rx_valid          (sb_rx_valid      [0]),
        .sb_rx_msg_id         (sb_rx_msg_id     [0]),
        .sb_rx_MsgInfo        (sb_rx_MsgInfo    [0]),
        .sb_rx_data_Field     (sb_rx_data_Field [0]),
        .sb_tx_valid          (sb_tx_valid      [0]),
        .sb_ltsm_rdy          (sb_ltsm_rdy      [0]),
        .sb_tx_msg_id         (sb_tx_msg_id     [0]),
        .sb_tx_MsgInfo        (sb_tx_MsgInfo    [0]),
        .sb_tx_data_Field     (sb_tx_data_Field [0]),
        .sb_iter_done         (sb_iter_done         [0]),
        .sbinit_pattern_mode  (sbinit_pattern_mode  [0]),
        .sb_det_pattern_req   (sb_det_pattern_req   [0]),
        .sbinit_req_iter_count(sbinit_req_iter_count[0]),

        .rdi_state (rdi_state[0]),

        // Die-facing CONTROL outputs -> u_mb_die_0
        .i_mapper_en         (i_mapper_en        [0]),
        .i_width_deg_tx      (i_width_deg_tx     [0]),
        .i_width_deg_rx      (i_width_deg_rx     [0]),
        .i_lfsr_state        (i_lfsr_state       [0]),
        .i_reversal_en       (i_reversal_en      [0]),
        .i_valid_pattern_en  (i_valid_pattern_en [0]),
        .i_clk_pattern_en    (i_clk_pattern_en   [0]),
        .i_state             (i_state            [0]),
        .demapper_en         (demapper_en        [0]),
        .i_pcmp_enable       (i_pcmp_enable      [0]),
        .i_pcmp_mode         (i_pcmp_mode        [0]),
        .i_pcmp_lane_mask    (i_pcmp_lane_mask   [0]),
        .i_pcmp_iter_count   (i_pcmp_iter_count  [0]),
        .i_pcmp_pattern_mode (i_pcmp_pattern_mode[0]),
        .i_pcmp_clear        (i_pcmp_clear       [0]),
        .i_vcmp_enable       (i_vcmp_enable      [0]),
        .i_vcmp_mode         (i_vcmp_mode        [0]),
        .i_vcmp_clear        (i_vcmp_clear       [0]),
        .i_clk_detector_en   (i_clk_detector_en  [0]),
        .i_rx_data_deser_en  (i_rx_data_deser_en [0]),
        .i_rx_valid_deser_en (i_rx_valid_deser_en[0]),
        .i_clk_embedded_en   (i_clk_embedded_en  [0]),

        // Die-facing RESULT inputs <- u_mb_die_0
        .o_lfsr_tx_done       (o_lfsr_tx_done     [0]),
        .o_valid_done         (o_valid_done       [0]),
        .o_clk_done           (o_clk_done         [0]),
        .o_pcmp_done          (o_pcmp_done        [0]),
        .o_pcmp_per_lane_pass (o_pcmp_per_lane_pass[0]),
        .o_vcmp_done          (o_vcmp_done        [0]),
        .o_vcmp_pass          (o_vcmp_pass        [0]),
        .o_valid_frame_error  (o_valid_frame_error[0]),
        .o_clk_p_pass         (o_clk_p_pass       [0]),
        .o_clk_n_pass         (o_clk_n_pass       [0]),
        .o_track_pass         (o_track_pass       [0]),
        .i_aggr_err           (i_aggr_err         [0])
    );

    // =========================================================================
    // DUT : LTSM_TOP[1]   (clocked from lclk1 -- die 1's PLL-derived clock)
    // =========================================================================
    LTSM_TOP #(
        .CLK_FRQ_HZ (LTSM_CLK_FRQ),
        .NUM_LANES  (NUM_LANES)
    ) u_ltsm_top_1 (
        .clk   (lclk1),
        .rst_n (ltsm_rst_n),

        .current_ltsm_state       (current_ltsm_state  [1]),
        .current_ltsm_state_n     (current_ltsm_state_n[1]),
        .mbinit_error             (mbinit_error        [1]),
        .active_error             (active_error        [1]),
        .timeout_8ms_occured      (timeout_8ms_occured [1]),
        .log0_state_n             (log0_state_n        [1]),
        .log0_lane_reversal       (log0_lane_reversal  [1]),
        .log0_width_degrade       (log0_width_degrade  [1]),
        .log0_state_n_minus_1     (),
        .log0_state_n_minus_2     (),
        .log1_state_n_minus_3     (),

        .phy_start_ucie_link_training_ctrl_out (phy_start           [1]),
        .Adapter_training_req                  (adapter_training_req[1]),
        .sb_det_pattern_rcvd                   (sb_det_pattern_rcvd [1]),
        .SPMW                                  (1'b0),

        .reg_phy_x8_mode_ctrl        (reg_phy_x8_mode_ctrl       [1]),
        .reg_TARR_support_local_cap  (1'b1),
        .reg_L2SPD_support_local_cap (1'b1),
        .reg_PSPT_support_local_cap  (1'b1),
        .reg_PMO_support_local_cap   (1'b1),
        .reg_Max_Link_Speed_cap      (4'b0101),
        .reg_Supported_TX_Vswing     (5'b00111),
        .reg_so                      (1'b0),
        .reg_mtp                     (1'b1),
        .reg_Module_ID               (2'b00),
        .reg_Clock_Phase_cap         (2'b01),
        .reg_Clock_mode_cap          (2'b01),
        .reg_TARR_support_local_ctrl (1'b1),
        .reg_PMO_support_local_ctrl  (1'b1),
        .reg_Clock_Phase_ctrl        (1'b1),
        .reg_Clock_mode_ctrl         (1'b1),
        .reg_L2SPD_support_local_ctrl(1'b1),
        .reg_PSPT_support_local_ctrl (1'b1),
        .reg_Target_Link_Width_ctrl  (reg_Target_Link_Width_ctrl[1]),
        .reg_Target_Link_Speed_ctrl  (reg_Target_Link_Speed_ctrl[1]),

        .reg_Clock_Phase_enable_status (reg_Clock_Phase_enable_status[1]),
        .reg_Clock_mode_enable_status  (reg_Clock_mode_enable_status [1]),
        .reg_TARR_enable_status        (reg_TARR_enable_status       [1]),
        .reg_Link_Width_enable_status  (reg_Link_Width_enable_status [1]),
        .reg_Link_Speed_enable_status  (reg_Link_Speed_enable_status [1]),
        .reg_PMO_enable_status         (reg_PMO_enable_status        [1]),
        .reg_L2SPD_enable_status       (reg_L2SPD_enable_status      [1]),
        .reg_PSPT_enable_status        (reg_PSPT_enable_status       [1]),

        .cfg_max_err_thresh_perlane (12'd10),
        .cfg_max_err_thresh_aggr    (16'd50),
        .reg_lane_mask              ('0),

        .sb_rx_valid          (sb_rx_valid      [1]),
        .sb_rx_msg_id         (sb_rx_msg_id     [1]),
        .sb_rx_MsgInfo        (sb_rx_MsgInfo    [1]),
        .sb_rx_data_Field     (sb_rx_data_Field [1]),
        .sb_tx_valid          (sb_tx_valid      [1]),
        .sb_ltsm_rdy          (sb_ltsm_rdy      [1]),
        .sb_tx_msg_id         (sb_tx_msg_id     [1]),
        .sb_tx_MsgInfo        (sb_tx_MsgInfo    [1]),
        .sb_tx_data_Field     (sb_tx_data_Field [1]),
        .sb_iter_done         (sb_iter_done         [1]),
        .sbinit_pattern_mode  (sbinit_pattern_mode  [1]),
        .sb_det_pattern_req   (sb_det_pattern_req   [1]),
        .sbinit_req_iter_count(sbinit_req_iter_count[1]),

        .rdi_state (rdi_state[1]),

        // Die-facing CONTROL outputs -> u_mb_die_1
        .i_mapper_en         (i_mapper_en        [1]),
        .i_width_deg_tx      (i_width_deg_tx     [1]),
        .i_width_deg_rx      (i_width_deg_rx     [1]),
        .i_lfsr_state        (i_lfsr_state       [1]),
        .i_reversal_en       (i_reversal_en      [1]),
        .i_valid_pattern_en  (i_valid_pattern_en [1]),
        .i_clk_pattern_en    (i_clk_pattern_en   [1]),
        .i_state             (i_state            [1]),
        .demapper_en         (demapper_en        [1]),
        .i_pcmp_enable       (i_pcmp_enable      [1]),
        .i_pcmp_mode         (i_pcmp_mode        [1]),
        .i_pcmp_lane_mask    (i_pcmp_lane_mask   [1]),
        .i_pcmp_iter_count   (i_pcmp_iter_count  [1]),
        .i_pcmp_pattern_mode (i_pcmp_pattern_mode[1]),
        .i_pcmp_clear        (i_pcmp_clear       [1]),
        .i_vcmp_enable       (i_vcmp_enable      [1]),
        .i_vcmp_mode         (i_vcmp_mode        [1]),
        .i_vcmp_clear        (i_vcmp_clear       [1]),
        .i_clk_detector_en   (i_clk_detector_en  [1]),
        .i_rx_data_deser_en  (i_rx_data_deser_en [1]),
        .i_rx_valid_deser_en (i_rx_valid_deser_en[1]),
        .i_clk_embedded_en   (i_clk_embedded_en  [1]),

        // Die-facing RESULT inputs <- u_mb_die_1
        .o_lfsr_tx_done       (o_lfsr_tx_done     [1]),
        .o_valid_done         (o_valid_done       [1]),
        .o_clk_done           (o_clk_done         [1]),
        .o_pcmp_done          (o_pcmp_done        [1]),
        .o_pcmp_per_lane_pass (o_pcmp_per_lane_pass[1]),
        .o_vcmp_done          (o_vcmp_done        [1]),
        .o_vcmp_pass          (o_vcmp_pass        [1]),
        .o_valid_frame_error  (o_valid_frame_error[1]),
        .o_clk_p_pass         (o_clk_p_pass       [1]),
        .o_clk_n_pass         (o_clk_n_pass       [1]),
        .o_track_pass         (o_track_pass       [1]),
        .i_aggr_err           (i_aggr_err         [1])
    );

    // =========================================================================
    // DUT : unit_mb_die[0]
    // lclk0 output feeds back as lclk_g0 (gated lclk input) and as LTSM_TOP[0].clk
    // =========================================================================
    unit_mb_die #(
        .DATA_WIDTH   (DATA_WIDTH),
        .NUM_LANES    (NUM_LANES),
        .N_BYTES      (N_BYTES),
        .PLL_PERIOD_NS(PLL_PERIOD_NS)
    ) u_mb_die_0 (
        .i_rst_n              (mb_rst_n),
        .lp_data              (lp_data[0]),
        .lp_irdy              (1'b0),
        .lp_valid             (1'b0),
        .pl_trdy              (pl_trdy[0]),

        // TX control <- LTSM_TOP[0]
        .i_mapper_en         (i_mapper_en        [0]),
        .i_width_deg_tx      (i_width_deg_tx     [0]),
        .i_width_deg_rx      (i_width_deg_rx     [0]),
        .i_lfsr_state        (i_lfsr_state       [0]),
        .i_reversal_en       (i_reversal_en      [0]),
        .i_valid_pattern_en  (i_valid_pattern_en [0]),
        .i_pll_en            (i_pll_en),
        .i_pll_speed_sel     (i_pll_speed_sel),
        .lclk_g              (lclk_g0),
        .i_clk_pattern_en    (i_clk_pattern_en   [0]),
        .i_clk_embedded_en   (i_clk_embedded_en  [0]),

        // RX control <- LTSM_TOP[0]
        .i_state             (i_state            [0]),
        .demapper_en         (demapper_en        [0]),
        .i_pcmp_enable       (i_pcmp_enable      [0]),
        .i_pcmp_mode         (i_pcmp_mode        [0]),
        .i_pcmp_lane_mask    (i_pcmp_lane_mask   [0]),
        .i_pcmp_thr_per_lane (i_pcmp_thr_per_lane),
        .i_pcmp_thr_aggregate(i_pcmp_thr_aggregate),
        .i_pcmp_iter_count   (i_pcmp_iter_count  [0]),
        .i_pcmp_pattern_mode (i_pcmp_pattern_mode[0]),
        .i_pcmp_clear        (i_pcmp_clear       [0]),
        .i_vcmp_enable       (i_vcmp_enable      [0]),
        .i_vcmp_mode         (i_vcmp_mode        [0]),
        .i_vcmp_thr          (i_vcmp_thr),
        .i_vcmp_clear        (i_vcmp_clear       [0]),
        .i_clk_detector_en   (i_clk_detector_en  [0]),
        .i_rx_data_deser_en  (i_rx_data_deser_en [0]),
        .i_rx_valid_deser_en (i_rx_valid_deser_en[0]),

        // RX serial in: from die 1 TX
        .i_RD_P   (d1_to_d0_data),
        .i_RVLD_P (d1_TVLD_P),
        .i_RCKP_P (d1_TCKP_P),
        .i_RCKN_P (d1_TCKN_P),
        .i_RTRK_P (d1_TTRK_P),

        // TX serial out: to die 1 RX
        .o_TD_P   (d0_TD_P),
        .o_TVLD_P (d0_TVLD_P),
        .o_TCKP_P (d0_TCKP_P),
        .o_TCKN_P (d0_TCKN_P),
        .o_TTRK_P (d0_TTRK_P),

        // Clocks
        .lclk      (lclk0),
        .o_pll_clk (o_pll_clk[0]),

        // TX done signals -> LTSM_TOP[0] result inputs
        .o_lfsr_tx_done (o_lfsr_tx_done[0]),
        .o_valid_done   (o_valid_done  [0]),
        .o_clk_done     (o_clk_done    [0]),

        // RX results -> LTSM_TOP[0] result inputs
        .o_out_data          (o_out_data         [0]),
        .o_pl_valid          (o_pl_valid         [0]),
        .o_pcmp_done         (o_pcmp_done        [0]),
        .o_pcmp_per_lane_pass(o_pcmp_per_lane_pass[0]),
        .o_pcmp_agg_err_cnt  (),
        .o_pcmp_agg_error    (i_aggr_err         [0]),  // -> LTSM_TOP.i_aggr_err
        .o_vcmp_done         (o_vcmp_done        [0]),
        .o_vcmp_pass         (o_vcmp_pass        [0]),
        .o_valid_frame_error (o_valid_frame_error[0]),
        .o_clk_p_pass        (o_clk_p_pass       [0]),
        .o_clk_n_pass        (o_clk_n_pass       [0]),
        .o_track_pass        (o_track_pass       [0])
    );

    // =========================================================================
    // DUT : unit_mb_die[1]
    // =========================================================================
    unit_mb_die #(
        .DATA_WIDTH   (DATA_WIDTH),
        .NUM_LANES    (NUM_LANES),
        .N_BYTES      (N_BYTES),
        .PLL_PERIOD_NS(PLL_PERIOD_NS)
    ) u_mb_die_1 (
        .i_rst_n              (mb_rst_n),
        .lp_data              (lp_data[1]),
        .lp_irdy              (1'b0),
        .lp_valid             (1'b0),
        .pl_trdy              (pl_trdy[1]),

        // TX control <- LTSM_TOP[1]
        .i_mapper_en         (i_mapper_en        [1]),
        .i_width_deg_tx      (i_width_deg_tx     [1]),
        .i_width_deg_rx      (i_width_deg_rx     [1]),
        .i_lfsr_state        (i_lfsr_state       [1]),
        .i_reversal_en       (i_reversal_en      [1]),
        .i_valid_pattern_en  (i_valid_pattern_en [1]),
        .i_pll_en            (i_pll_en),
        .i_pll_speed_sel     (i_pll_speed_sel),
        .lclk_g              (lclk_g1),
        .i_clk_pattern_en    (i_clk_pattern_en   [1]),
        .i_clk_embedded_en   (i_clk_embedded_en  [1]),

        // RX control <- LTSM_TOP[1]
        .i_state             (i_state            [1]),
        .demapper_en         (demapper_en        [1]),
        .i_pcmp_enable       (i_pcmp_enable      [1]),
        .i_pcmp_mode         (i_pcmp_mode        [1]),
        .i_pcmp_lane_mask    (i_pcmp_lane_mask   [1]),
        .i_pcmp_thr_per_lane (i_pcmp_thr_per_lane),
        .i_pcmp_thr_aggregate(i_pcmp_thr_aggregate),
        .i_pcmp_iter_count   (i_pcmp_iter_count  [1]),
        .i_pcmp_pattern_mode (i_pcmp_pattern_mode[1]),
        .i_pcmp_clear        (i_pcmp_clear       [1]),
        .i_vcmp_enable       (i_vcmp_enable      [1]),
        .i_vcmp_mode         (i_vcmp_mode        [1]),
        .i_vcmp_thr          (i_vcmp_thr),
        .i_vcmp_clear        (i_vcmp_clear       [1]),
        .i_clk_detector_en   (i_clk_detector_en  [1]),
        .i_rx_data_deser_en  (i_rx_data_deser_en [1]),
        .i_rx_valid_deser_en (i_rx_valid_deser_en[1]),

        // RX serial in: from die 0 TX
        .i_RD_P   (d0_to_d1_data),
        .i_RVLD_P (d0_TVLD_P),
        .i_RCKP_P (d0_TCKP_P),
        .i_RCKN_P (d0_TCKN_P),
        .i_RTRK_P (d0_TTRK_P),

        // TX serial out: to die 0 RX
        .o_TD_P   (d1_TD_P),
        .o_TVLD_P (d1_TVLD_P),
        .o_TCKP_P (d1_TCKP_P),
        .o_TCKN_P (d1_TCKN_P),
        .o_TTRK_P (d1_TTRK_P),

        // Clocks
        .lclk      (lclk1),
        .o_pll_clk (o_pll_clk[1]),

        // TX done signals -> LTSM_TOP[1] result inputs
        .o_lfsr_tx_done (o_lfsr_tx_done[1]),
        .o_valid_done   (o_valid_done  [1]),
        .o_clk_done     (o_clk_done    [1]),

        // RX results -> LTSM_TOP[1] result inputs
        .o_out_data          (o_out_data         [1]),
        .o_pl_valid          (o_pl_valid         [1]),
        .o_pcmp_done         (o_pcmp_done        [1]),
        .o_pcmp_per_lane_pass(o_pcmp_per_lane_pass[1]),
        .o_pcmp_agg_err_cnt  (),
        .o_pcmp_agg_error    (i_aggr_err         [1]),  // -> LTSM_TOP.i_aggr_err
        .o_vcmp_done         (o_vcmp_done        [1]),
        .o_vcmp_pass         (o_vcmp_pass        [1]),
        .o_valid_frame_error (o_valid_frame_error[1]),
        .o_clk_p_pass        (o_clk_p_pass       [1]),
        .o_clk_n_pass        (o_clk_n_pass       [1]),
        .o_track_pass        (o_track_pass       [1])
    );

    // =========================================================================
    // RDI state auto-driver (each die on its own lclk domain)
    // =========================================================================
    always @(posedge lclk0 or negedge ltsm_rst_n) begin
        if (!ltsm_rst_n) rdi_state[0] <= Reset;
        else if (current_ltsm_state_n[0] == LOG_LINKINIT) begin
            repeat(20) @(posedge lclk0);
            rdi_state[0] <= Active;
        end else if (current_ltsm_state_n[0] == LOG_RESET)
            rdi_state[0] <= Reset;
    end

    always @(posedge lclk1 or negedge ltsm_rst_n) begin
        if (!ltsm_rst_n) rdi_state[1] <= Reset;
        else if (current_ltsm_state_n[1] == LOG_LINKINIT) begin
            repeat(20) @(posedge lclk1);
            rdi_state[1] <= Active;
        end else if (current_ltsm_state_n[1] == LOG_RESET)
            rdi_state[1] <= Reset;
    end

    // =========================================================================
    // Training trigger auto-clear (once LTSM leaves RESET)
    // =========================================================================
    always @(posedge lclk0) begin
        if (current_ltsm_state_n[0] != LOG_RESET && current_ltsm_state_n[0] != LOG_NOP)
            phy_start[0] <= 1'b0;
    end
    always @(posedge lclk1) begin
        if (current_ltsm_state_n[1] != LOG_RESET && current_ltsm_state_n[1] != LOG_NOP)
            phy_start[1] <= 1'b0;
    end

    // =========================================================================
    // State transition logger
    // =========================================================================
    always @(current_ltsm_state_n[0])
        $display("T=%0t | [DIE 0] %s", $time, current_ltsm_state_n[0].name());
    always @(current_ltsm_state_n[1])
        $display("T=%0t | [DIE 1] %s", $time, current_ltsm_state_n[1].name());

    // =========================================================================
    // Debug: SBINIT[0] state machine trace (gated to 6.9µs–7.3µs window)
    // =========================================================================
    always @(u_ltsm_top_0.u_ltsm.u_sbinit.current_state,
             u_ltsm_top_0.u_ltsm.u_sbinit.out_of_reset_rcvd,
             u_ltsm_top_0.u_ltsm.u_sbinit.done_req_rcvd,
             u_ltsm_top_0.u_ltsm.u_sbinit.done_resp_rcvd,
             u_ltsm_top_0.u_ltsm.sb_ltsm_rdy,
             u_ltsm_top_0.u_ltsm.sb_rx_valid)
        $display("T=%0t | [SBINIT0] state=%s oor=%b dreq=%b drsp=%b ltsm_rdy=%b sb_rx_vld=%b",
            $time,
            u_ltsm_top_0.u_ltsm.u_sbinit.current_state,
            u_ltsm_top_0.u_ltsm.u_sbinit.out_of_reset_rcvd,
            u_ltsm_top_0.u_ltsm.u_sbinit.done_req_rcvd,
            u_ltsm_top_0.u_ltsm.u_sbinit.done_resp_rcvd,
            u_ltsm_top_0.u_ltsm.sb_ltsm_rdy,
            u_ltsm_top_0.u_ltsm.sb_rx_valid);
    always @(u_ltsm_top_1.u_ltsm.u_sbinit.current_state,
             u_ltsm_top_1.u_ltsm.u_sbinit.out_of_reset_rcvd,
             u_ltsm_top_1.u_ltsm.u_sbinit.done_req_rcvd,
             u_ltsm_top_1.u_ltsm.u_sbinit.done_resp_rcvd,
             u_ltsm_top_1.u_ltsm.sb_ltsm_rdy,
             u_ltsm_top_1.u_ltsm.sb_rx_valid)
        $display("T=%0t | [SBINIT1] state=%s oor=%b dreq=%b drsp=%b ltsm_rdy=%b sb_rx_vld=%b",
            $time,
            u_ltsm_top_1.u_ltsm.u_sbinit.current_state,
            u_ltsm_top_1.u_ltsm.u_sbinit.out_of_reset_rcvd,
            u_ltsm_top_1.u_ltsm.u_sbinit.done_req_rcvd,
            u_ltsm_top_1.u_ltsm.u_sbinit.done_resp_rcvd,
            u_ltsm_top_1.u_ltsm.sb_ltsm_rdy,
            u_ltsm_top_1.u_ltsm.sb_rx_valid);

    // =========================================================================
    // Reset task
    // =========================================================================
    task automatic reset_system();
        mb_rst_n   = 1'b0;
        ltsm_rst_n = 1'b0;
        sb_rst_n   = 1'b0;

        phy_start           [0] = 1'b0;
        phy_start           [1] = 1'b0;
        adapter_training_req[0] = 1'b0;
        adapter_training_req[1] = 1'b0;
        reverse_lanes           = 1'b0;
        block_sideband          = 1'b0;
        lp_data             [0] = '0;
        lp_data             [1] = '0;

        reg_Target_Link_Width_ctrl[0] = 4'h2;  // x16
        reg_Target_Link_Width_ctrl[1] = 4'h2;
        reg_Target_Link_Speed_ctrl[0] = 4'h5;  // 32 GT/s
        reg_Target_Link_Speed_ctrl[1] = 4'h5;
        reg_phy_x8_mode_ctrl      [0] = 1'b0;
        reg_phy_x8_mode_ctrl      [1] = 1'b0;

        // Release mb_die reset first so PLL can start generating lclk
        #20;
        mb_rst_n = 1'b1;

        // Wait until lclk0 is toggling (PLL locked)
        @(posedge lclk0);
        repeat(5) @(posedge lclk0);

        // Now release LTSM and SideBand resets together
        ltsm_rst_n = 1'b1;
        sb_rst_n   = 1'b1;

        // Let LTSM and SB settle
        repeat(20) @(posedge clk_sb);
        $display("T=%0t | [RESET] System reset complete. lclk0 running.", $time);
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        // Shared non-interface defaults
        i_pll_en            = 1'b1;
        i_pll_speed_sel     = 2'b00;
        i_pcmp_thr_per_lane  = 16'd100;
        i_pcmp_thr_aggregate = 16'd1000;
        i_vcmp_thr           = 16'd50;

        $display("\n================================================================");
        $display("  UCIe LTSM + SideBand + MB Die-to-Die Integration TB");
        $display("  PLL=2GHz | lclk=125MHz | clk_sb=100MHz | clk_sbser=800MHz");
        $display("  CLK_FRQ_HZ=%0d (8ms timer fires in ~800 lclk cycles)", LTSM_CLK_FRQ);
        $display("================================================================\n");

        // ----------------------------------------------------------------
        // SCENARIO 1: Happy Path
        // Die 0 triggers training; Die 1 wakes on SB pattern detect.
        // Both should reach LOG_ACTIVE.
        // ----------------------------------------------------------------
        $display("T=%0t | [SC1] Happy Path: die0 triggers, both reach ACTIVE", $time);
        reset_system();

        @(posedge lclk0);
        phy_start[0] = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                $display("\nT=%0t | [SC1] PASS -- both dies reached ACTIVE", $time);
                $display("        Die0: Width=4'h%h  Speed=4'h%h",
                    reg_Link_Width_enable_status[0], reg_Link_Speed_enable_status[0]);
                $display("        Die1: Width=4'h%h  Speed=4'h%h",
                    reg_Link_Width_enable_status[1], reg_Link_Speed_enable_status[1]);
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [SC1] FAIL: training error on die%0s",
                    $time, m_error ? "0" : "1");
                $finish;
            end
            begin
                repeat(5000) @(posedge lclk0);
                $error("T=%0t | [SC1] TIMEOUT (5000 lclk cycles)", $time);
                $finish;
            end
        join_any
        disable fork;

        // ----------------------------------------------------------------
        // SCENARIO 2: Watchdog -- blocked sideband
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC2] Watchdog: sideband blocked, die0 should hit error", $time);
        reset_system();
        block_sideband = 1'b1;

        @(posedge lclk0);
        phy_start[0] = 1'b1;

        fork
            begin
                wait (m_error);
                $display("T=%0t | [SC2] PASS -- watchdog expired correctly", $time);
            end
            begin
                wait (m_done);
                $error("T=%0t | [SC2] FAIL: done with blocked sideband?", $time);
                $finish;
            end
            begin
                repeat(2000) @(posedge lclk0);
                $error("T=%0t | [SC2] TIMEOUT: watchdog did not fire in 2000 cycles", $time);
                $finish;
            end
        join_any
        disable fork;

        $display("\n================================================================");
        $display("  ALL SCENARIOS PASSED");
        $display("  LTSM_SB_MB_DIE2DIE SIM PASS");
        $display("================================================================\n");
        $finish;
    end

endmodule
