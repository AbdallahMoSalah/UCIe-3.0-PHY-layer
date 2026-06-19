`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// Testbench : MB_SB_LTSM_tb
// DUT       : 2x MB_SB_LTSM modules connected back-to-back
//             This integration testbench tests the full UCIe PHY logic:
//             LTSM, SideBand, and MainBand connected back-to-back.
// =============================================================================

module MB_SB_LTSM_tb;

    // Parameters scaled to speed up simulation watchdog/timer
    localparam int  LTSM_CLK_FRQ  = 125_000; // 8ms timer = 1000 lclk cycles = 8µs real time
    localparam int  NUM_LANES     = 16;
    localparam int  N_BYTES       = 64;
    localparam int  FLITW         = 8 * N_BYTES;

    // =========================================================================
    // Die 0 signals
    // =========================================================================
    logic [FLITW-1:0] lp_data0;
    logic             lp_irdy0;
    logic             lp_valid0;
    logic             pl_trdy0;
    logic [1:0]       i_pll_speed_sel0;
    logic             lclk_g0;
    logic [15:0]      i_pcmp_thr_per_lane0;
    logic [15:0]      i_pcmp_thr_aggregate0;
    logic [15:0]      i_vcmp_thr0;
    logic             lclk0;
    logic             o_pll_clk0;
    logic [FLITW-1:0] o_out_data0;
    logic             o_pl_valid0;
    logic [15:0]      o_pcmp_agg_err_cnt0;

    logic [NUM_LANES-1:0] i_RD_P0;
    logic             i_RVLD_P0;
    logic             i_RCKP_P0;
    logic             i_RCKN_P0;
    logic             i_RTRK_P0;
    logic [NUM_LANES-1:0] o_TD_P0;
    logic             o_TVLD_P0;
    logic             o_TCKP_P0;
    logic             o_TCKN_P0;
    logic             o_TTRK_P0;

    logic             RXCKSB0;
    logic             TXCKSB0;
    logic             TXDATASB0;
    logic             RXDATASB0;

    logic             traffic_req0;
    logic             traffic_rdy0;
    logic [7:0]       RDI_msg_no_send0;
    logic             stall_send0;
    logic             RDI_vld_send0;
    logic             RDI_rdy0;
    logic             RDI_vld_rcvd0;
    logic [7:0]       RDI_msg_no_rcvd0;
    logic             stall_rcvd0;

    logic [31:0]      lp_cfg0;
    logic             lp_cfg_vld0;
    logic             pl_cfg_crd0;
    logic             lp_cfg_crd0;
    logic [31:0]      pl_cfg0;
    logic             pl_cfg_vld0;

    logic [24:0]      rf_addr0;
    logic [7:0]       rf_be0;
    logic             rf_is_64b_access0;
    logic [63:0]      rf_wdata0;
    logic             rd_en0;
    logic             wr_en0;
    logic [63:0]      rf_rdata0;
    logic             rdata_vld0;
    logic             addr_err_o0;

    LTSM_state_e      current_ltsm_state0;
    state_n_e         current_ltsm_state_n0;
    logic             timeout_8ms_occured0;
    logic [7:0]       log0_state_n0;
    logic             log0_lane_reversal0;
    logic             log0_width_degrade0;
    logic [7:0]       log0_state_n_minus_10;
    logic [7:0]       log0_state_n_minus_20;
    logic [7:0]       log1_state_n_minus_30;

    logic             phy_start0;
    logic             Adapter_training_req0;
    logic             SPMW0;

    logic             reg_phy_x8_mode_ctrl0;
    logic             reg_TARR_support_local_cap0;
    logic             reg_L2SPD_support_local_cap0;
    logic             reg_PSPT_support_local_cap0;
    logic             reg_PMO_support_local_cap0;
    logic [3:0]       reg_Max_Link_Speed_cap0;
    logic [4:0]       reg_Supported_TX_Vswing0;
    logic             reg_so0;
    logic             reg_mtp0;
    logic [1:0]       reg_Module_ID0;
    logic [1:0]       reg_Clock_Phase_cap0;
    logic [1:0]       reg_Clock_mode_cap0;
    logic             reg_TARR_support_local_ctrl0;
    logic             reg_PMO_support_local_ctrl0;
    logic             reg_Clock_Phase_ctrl0;
    logic             reg_Clock_mode_ctrl0;
    logic             reg_L2SPD_support_local_ctrl0;
    logic             reg_PSPT_support_local_ctrl0;
    logic [3:0]       reg_Target_Link_Width_ctrl0;
    logic [3:0]       reg_Target_Link_Speed_ctrl0;

    logic             reg_Clock_Phase_enable_status0;
    logic             reg_Clock_mode_enable_status0;
    logic             reg_TARR_enable_status0;
    logic [3:0]       reg_Link_Width_enable_status0;
    logic [3:0]       reg_Link_Speed_enable_status0;
    logic             reg_PMO_enable_status0;
    logic             reg_L2SPD_enable_status0;
    logic             reg_PSPT_enable_status0;

    logic [11:0]      cfg_max_err_thresh_perlane0;
    logic [15:0]      cfg_max_err_thresh_aggr0;
    logic [NUM_LANES-1:0] reg_lane_mask0;
    RDI_state         rdi_state0;

    // =========================================================================
    // Die 1 signals
    // =========================================================================
    logic [FLITW-1:0] lp_data1;
    logic             lp_irdy1;
    logic             lp_valid1;
    logic             pl_trdy1;
    logic [1:0]       i_pll_speed_sel1;
    logic             lclk_g1;
    logic [15:0]      i_pcmp_thr_per_lane1;
    logic [15:0]      i_pcmp_thr_aggregate1;
    logic [15:0]      i_vcmp_thr1;
    logic             lclk1;
    logic             o_pll_clk1;
    logic [FLITW-1:0] o_out_data1;
    logic             o_pl_valid1;
    logic [15:0]      o_pcmp_agg_err_cnt1;

    logic [NUM_LANES-1:0] i_RD_P1;
    logic             i_RVLD_P1;
    logic             i_RCKP_P1;
    logic             i_RCKN_P1;
    logic             i_RTRK_P1;
    logic [NUM_LANES-1:0] o_TD_P1;
    logic             o_TVLD_P1;
    logic             o_TCKP_P1;
    logic             o_TCKN_P1;
    logic             o_TTRK_P1;

    logic             RXCKSB1;
    logic             TXCKSB1;
    logic             TXDATASB1;
    logic             RXDATASB1;

    logic             traffic_req1;
    logic             traffic_rdy1;
    logic [7:0]       RDI_msg_no_send1;
    logic             stall_send1;
    logic             RDI_vld_send1;
    logic             RDI_rdy1;
    logic             RDI_vld_rcvd1;
    logic [7:0]       RDI_msg_no_rcvd1;
    logic             stall_rcvd1;

    logic [31:0]      lp_cfg1;
    logic             lp_cfg_vld1;
    logic             pl_cfg_crd1;
    logic             lp_cfg_crd1;
    logic [31:0]      pl_cfg1;
    logic             pl_cfg_vld1;

    logic [24:0]      rf_addr1;
    logic [7:0]       rf_be1;
    logic             rf_is_64b_access1;
    logic [63:0]      rf_wdata1;
    logic             rd_en1;
    logic             wr_en1;
    logic [63:0]      rf_rdata1;
    logic             rdata_vld1;
    logic             addr_err_o1;

    LTSM_state_e      current_ltsm_state1;
    state_n_e         current_ltsm_state_n1;
    logic             timeout_8ms_occured1;
    logic [7:0]       log0_state_n1;
    logic             log0_lane_reversal1;
    logic             log0_width_degrade1;
    logic [7:0]       log0_state_n_minus_11;
    logic [7:0]       log0_state_n_minus_21;
    logic [7:0]       log1_state_n_minus_31;

    logic             phy_start1;
    logic             Adapter_training_req1;
    logic             SPMW1;

    logic             reg_phy_x8_mode_ctrl1;
    logic             reg_TARR_support_local_cap1;
    logic             reg_L2SPD_support_local_cap1;
    logic             reg_PSPT_support_local_cap1;
    logic             reg_PMO_support_local_cap1;
    logic [3:0]       reg_Max_Link_Speed_cap1;
    logic [4:0]       reg_Supported_TX_Vswing1;
    logic             reg_so1;
    logic             reg_mtp1;
    logic [1:0]       reg_Module_ID1;
    logic [1:0]       reg_Clock_Phase_cap1;
    logic [1:0]       reg_Clock_mode_cap1;
    logic             reg_TARR_support_local_ctrl1;
    logic             reg_PMO_support_local_ctrl1;
    logic             reg_Clock_Phase_ctrl1;
    logic             reg_Clock_mode_ctrl1;
    logic             reg_L2SPD_support_local_ctrl1;
    logic             reg_PSPT_support_local_ctrl1;
    logic [3:0]       reg_Target_Link_Width_ctrl1;
    logic [3:0]       reg_Target_Link_Speed_ctrl1;

    logic             reg_Clock_Phase_enable_status1;
    logic             reg_Clock_mode_enable_status1;
    logic             reg_TARR_enable_status1;
    logic [3:0]       reg_Link_Width_enable_status1;
    logic [3:0]       reg_Link_Speed_enable_status1;
    logic             reg_PMO_enable_status1;
    logic             reg_L2SPD_enable_status1;
    logic             reg_PSPT_enable_status1;

    logic [11:0]      cfg_max_err_thresh_perlane1;
    logic [15:0]      cfg_max_err_thresh_aggr1;
    logic [NUM_LANES-1:0] reg_lane_mask1;
    RDI_state         rdi_state1;

    // =========================================================================
    // System control / Channel modeling
    // =========================================================================
    logic             rst_n;
    logic             block_sideband;
    logic             reverse_lanes_0to1;
    logic             reverse_lanes_1to0;
    logic [NUM_LANES-1:0] die0_to_die1_corrupt_mask;
    logic [NUM_LANES-1:0] die1_to_die0_corrupt_mask;

    // SideBand Cross-Connections
    assign RXCKSB0   = block_sideband ? 1'b0 : TXCKSB1;
    assign RXDATASB0 = block_sideband ? 1'b0 : TXDATASB1;
    assign RXCKSB1   = block_sideband ? 1'b0 : TXCKSB0;
    assign RXDATASB1 = block_sideband ? 1'b0 : TXDATASB0;

    // MainBand Cross-Connections (Data lanes with reversal/corruption)
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            // Die 0 -> Die 1
            if (die0_to_die1_corrupt_mask[i]) begin
                i_RD_P1[i] = 1'b0;
            end else begin
                i_RD_P1[i] = reverse_lanes_0to1 ? o_TD_P0[NUM_LANES-1-i] : o_TD_P0[i];
            end

            // Die 1 -> Die 0
            if (die1_to_die0_corrupt_mask[i]) begin
                i_RD_P0[i] = 1'b0;
            end else begin
                i_RD_P0[i] = reverse_lanes_1to0 ? o_TD_P1[NUM_LANES-1-i] : o_TD_P1[i];
            end
        end
    end

    // Clock, Valid, Track lanes are directly cross-connected (no reversal)
    assign i_RVLD_P1 = o_TVLD_P0;
    assign i_RCKP_P1 = o_TCKP_P0;
    assign i_RCKN_P1 = o_TCKN_P0;
    assign i_RTRK_P1 = o_TTRK_P0;

    assign i_RVLD_P0 = o_TVLD_P1;
    assign i_RCKP_P0 = o_TCKP_P1;
    assign i_RCKN_P0 = o_TCKN_P1;
    assign i_RTRK_P0 = o_TTRK_P1;

    // =========================================================================
    // DUT Instantiations
    // =========================================================================

    MB_SB_LTSM #(
        .CLK_FRQ_HZ     (LTSM_CLK_FRQ),
        .NUM_LANES      (NUM_LANES)
    ) u_die0 (
        .rst_n                                 (rst_n),
        .lp_data                               (lp_data0),
        .lp_irdy                               (lp_irdy0),
        .lp_valid                              (lp_valid0),
        .pl_trdy                               (pl_trdy0),
        .i_pll_speed_sel                       (i_pll_speed_sel0),
        .lclk_g                                (lclk_g0),
        .i_pcmp_thr_per_lane                   (i_pcmp_thr_per_lane0),
        .i_pcmp_thr_aggregate                  (i_pcmp_thr_aggregate0),
        .i_vcmp_thr                            (i_vcmp_thr0),
        .lclk                                  (lclk0),
        .o_pll_clk                             (o_pll_clk0),
        .o_out_data                            (o_out_data0),
        .o_pl_valid                            (o_pl_valid0),
        .o_pcmp_agg_err_cnt                    (o_pcmp_agg_err_cnt0),
        .i_RD_P                                (i_RD_P0),
        .i_RVLD_P                              (i_RVLD_P0),
        .i_RCKP_P                              (i_RCKP_P0),
        .i_RCKN_P                              (i_RCKN_P0),
        .i_RTRK_P                              (i_RTRK_P0),
        .o_TD_P                                (o_TD_P0),
        .o_TVLD_P                              (o_TVLD_P0),
        .o_TCKP_P                              (o_TCKP_P0),
        .o_TCKN_P                              (o_TCKN_P0),
        .o_TTRK_P                              (o_TTRK_P0),
        .RXCKSB                                (RXCKSB0),
        .TXCKSB                                (TXCKSB0),
        .TXDATASB                              (TXDATASB0),
        .RXDATASB                              (RXDATASB0),
        .traffic_req                           (traffic_req0),
        .traffic_rdy                           (traffic_rdy0),
        .RDI_msg_no_send                       (RDI_msg_no_send0),
        .stall_send                            (stall_send0),
        .RDI_vld_send                          (RDI_vld_send0),
        .RDI_rdy                               (RDI_rdy0),
        .RDI_vld_rcvd                          (RDI_vld_rcvd0),
        .RDI_msg_no_rcvd                       (RDI_msg_no_rcvd0),
        .stall_rcvd                            (stall_rcvd0),
        .lp_cfg                                (lp_cfg0),
        .lp_cfg_vld                            (lp_cfg_vld0),
        .pl_cfg_crd                            (pl_cfg_crd0),
        .lp_cfg_crd                            (lp_cfg_crd0),
        .pl_cfg                                (pl_cfg0),
        .pl_cfg_vld                            (pl_cfg_vld0),
        .rf_addr                               (rf_addr0),
        .rf_be                                 (rf_be0),
        .rf_is_64b_access                      (rf_is_64b_access0),
        .rf_wdata                              (rf_wdata0),
        .rd_en                                 (rd_en0),
        .wr_en                                 (wr_en0),
        .rf_rdata                              (rf_rdata0),
        .rdata_vld                             (rdata_vld0),
        .addr_err_o                            (addr_err_o0),
        .current_ltsm_state                    (current_ltsm_state0),
        .current_ltsm_state_n                  (current_ltsm_state_n0),
        .timeout_8ms_occured                   (timeout_8ms_occured0),
        .log0_state_n                          (log0_state_n0),
        .log0_lane_reversal                    (log0_lane_reversal0),
        .log0_width_degrade                    (log0_width_degrade0),
        .log0_state_n_minus_1                  (log0_state_n_minus_10),
        .log0_state_n_minus_2                  (log0_state_n_minus_20),
        .log1_state_n_minus_3                  (log1_state_n_minus_30),
        .phy_start_ucie_link_training_ctrl_out (phy_start0),
        .Adapter_training_req                  (Adapter_training_req0),
        .SPMW                                  (SPMW0),
        .reg_phy_x8_mode_ctrl                  (reg_phy_x8_mode_ctrl0),
        .reg_TARR_support_local_cap            (reg_TARR_support_local_cap0),
        .reg_L2SPD_support_local_cap           (reg_L2SPD_support_local_cap0),
        .reg_PSPT_support_local_cap            (reg_PSPT_support_local_cap0),
        .reg_PMO_support_local_cap             (reg_PMO_support_local_cap0),
        .reg_Max_Link_Speed_cap                (reg_Max_Link_Speed_cap0),
        .reg_Supported_TX_Vswing               (reg_Supported_TX_Vswing0),
        .reg_so                                (reg_so0),
        .reg_mtp                               (reg_mtp0),
        .reg_Module_ID                         (reg_Module_ID0),
        .reg_Clock_Phase_cap                   (reg_Clock_Phase_cap0),
        .reg_Clock_mode_cap                    (reg_Clock_mode_cap0),
        .reg_TARR_support_local_ctrl           (reg_TARR_support_local_ctrl0),
        .reg_PMO_support_local_ctrl            (reg_PMO_support_local_ctrl0),
        .reg_Clock_Phase_ctrl                  (reg_Clock_Phase_ctrl0),
        .reg_Clock_mode_ctrl                   (reg_Clock_mode_ctrl0),
        .reg_L2SPD_support_local_ctrl          (reg_L2SPD_support_local_ctrl0),
        .reg_PSPT_support_local_ctrl           (reg_PSPT_support_local_ctrl0),
        .reg_Target_Link_Width_ctrl            (reg_Target_Link_Width_ctrl0),
        .reg_Target_Link_Speed_ctrl            (reg_Target_Link_Speed_ctrl0),
        .reg_Clock_Phase_enable_status         (reg_Clock_Phase_enable_status0),
        .reg_Clock_mode_enable_status          (reg_Clock_mode_enable_status0),
        .reg_TARR_enable_status                (reg_TARR_enable_status0),
        .reg_Link_Width_enable_status          (reg_Link_Width_enable_status0),
        .reg_Link_Speed_enable_status          (reg_Link_Speed_enable_status0),
        .reg_PMO_enable_status                 (reg_PMO_enable_status0),
        .reg_L2SPD_enable_status               (reg_L2SPD_enable_status0),
        .reg_PSPT_enable_status                (reg_PSPT_enable_status0),
        .cfg_max_err_thresh_perlane            (cfg_max_err_thresh_perlane0),
        .cfg_max_err_thresh_aggr               (cfg_max_err_thresh_aggr0),
        .reg_lane_mask                         (reg_lane_mask0),
        .rdi_state                             (rdi_state0)
    );

    MB_SB_LTSM #(
        .CLK_FRQ_HZ     (LTSM_CLK_FRQ),
        .NUM_LANES      (NUM_LANES)
    ) u_die1 (
        .rst_n                                 (rst_n),
        .lp_data                               (lp_data1),
        .lp_irdy                               (lp_irdy1),
        .lp_valid                              (lp_valid1),
        .pl_trdy                               (pl_trdy1),
        .i_pll_speed_sel                       (i_pll_speed_sel1),
        .lclk_g                                (lclk_g1),
        .i_pcmp_thr_per_lane                   (i_pcmp_thr_per_lane1),
        .i_pcmp_thr_aggregate                  (i_pcmp_thr_aggregate1),
        .i_vcmp_thr                            (i_vcmp_thr1),
        .lclk                                  (lclk1),
        .o_pll_clk                             (o_pll_clk1),
        .o_out_data                            (o_out_data1),
        .o_pl_valid                            (o_pl_valid1),
        .o_pcmp_agg_err_cnt                    (o_pcmp_agg_err_cnt1),
        .i_RD_P                                (i_RD_P1),
        .i_RVLD_P                              (i_RVLD_P1),
        .i_RCKP_P                              (i_RCKP_P1),
        .i_RCKN_P                              (i_RCKN_P1),
        .i_RTRK_P                              (i_RTRK_P1),
        .o_TD_P                                (o_TD_P1),
        .o_TVLD_P                              (o_TVLD_P1),
        .o_TCKP_P                              (o_TCKP_P1),
        .o_TCKN_P                              (o_TCKN_P1),
        .o_TTRK_P                              (o_TTRK_P1),
        .RXCKSB                                (RXCKSB1),
        .TXCKSB                                (TXCKSB1),
        .TXDATASB                              (TXDATASB1),
        .RXDATASB                              (RXDATASB1),
        .traffic_req                           (traffic_req1),
        .traffic_rdy                           (traffic_rdy1),
        .RDI_msg_no_send                       (RDI_msg_no_send1),
        .stall_send                            (stall_send1),
        .RDI_vld_send                          (RDI_vld_send1),
        .RDI_rdy                               (RDI_rdy1),
        .RDI_vld_rcvd                          (RDI_vld_rcvd1),
        .RDI_msg_no_rcvd                       (RDI_msg_no_rcvd1),
        .stall_rcvd                            (stall_rcvd1),
        .lp_cfg                                (lp_cfg1),
        .lp_cfg_vld                            (lp_cfg_vld1),
        .pl_cfg_crd                            (pl_cfg_crd1),
        .lp_cfg_crd                            (lp_cfg_crd1),
        .pl_cfg                                (pl_cfg1),
        .pl_cfg_vld                            (pl_cfg_vld1),
        .rf_addr                               (rf_addr1),
        .rf_be                                 (rf_be1),
        .rf_is_64b_access                      (rf_is_64b_access1),
        .rf_wdata                              (rf_wdata1),
        .rd_en                                 (rd_en1),
        .wr_en                                 (wr_en1),
        .rf_rdata                              (rf_rdata1),
        .rdata_vld                             (rdata_vld1),
        .addr_err_o                            (addr_err_o1),
        .current_ltsm_state                    (current_ltsm_state1),
        .current_ltsm_state_n                  (current_ltsm_state_n1),
        .timeout_8ms_occured                   (timeout_8ms_occured1),
        .log0_state_n                          (log0_state_n1),
        .log0_lane_reversal                    (log0_lane_reversal1),
        .log0_width_degrade                    (log0_width_degrade1),
        .log0_state_n_minus_1                  (log0_state_n_minus_11),
        .log0_state_n_minus_2                  (log0_state_n_minus_21),
        .log1_state_n_minus_3                  (log1_state_n_minus_31),
        .phy_start_ucie_link_training_ctrl_out (phy_start1),
        .Adapter_training_req                  (Adapter_training_req1),
        .SPMW                                  (SPMW1),
        .reg_phy_x8_mode_ctrl                  (reg_phy_x8_mode_ctrl1),
        .reg_TARR_support_local_cap            (reg_TARR_support_local_cap1),
        .reg_L2SPD_support_local_cap           (reg_L2SPD_support_local_cap1),
        .reg_PSPT_support_local_cap            (reg_PSPT_support_local_cap1),
        .reg_PMO_support_local_cap             (reg_PMO_support_local_cap1),
        .reg_Max_Link_Speed_cap                (reg_Max_Link_Speed_cap1),
        .reg_Supported_TX_Vswing               (reg_Supported_TX_Vswing1),
        .reg_so                                (reg_so1),
        .reg_mtp                               (reg_mtp1),
        .reg_Module_ID                         (reg_Module_ID1),
        .reg_Clock_Phase_cap                   (reg_Clock_Phase_cap1),
        .reg_Clock_mode_cap                    (reg_Clock_mode_cap1),
        .reg_TARR_support_local_ctrl           (reg_TARR_support_local_ctrl1),
        .reg_PMO_support_local_ctrl            (reg_PMO_support_local_ctrl1),
        .reg_Clock_Phase_ctrl                  (reg_Clock_Phase_ctrl1),
        .reg_Clock_mode_ctrl                   (reg_Clock_mode_ctrl1),
        .reg_L2SPD_support_local_ctrl          (reg_L2SPD_support_local_ctrl1),
        .reg_PSPT_support_local_ctrl           (reg_PSPT_support_local_ctrl1),
        .reg_Target_Link_Width_ctrl            (reg_Target_Link_Width_ctrl1),
        .reg_Target_Link_Speed_ctrl            (reg_Target_Link_Speed_ctrl1),
        .reg_Clock_Phase_enable_status         (reg_Clock_Phase_enable_status1),
        .reg_Clock_mode_enable_status          (reg_Clock_mode_enable_status1),
        .reg_TARR_enable_status                (reg_TARR_enable_status1),
        .reg_Link_Width_enable_status          (reg_Link_Width_enable_status1),
        .reg_Link_Speed_enable_status          (reg_Link_Speed_enable_status1),
        .reg_PMO_enable_status                 (reg_PMO_enable_status1),
        .reg_L2SPD_enable_status               (reg_L2SPD_enable_status1),
        .reg_PSPT_enable_status                (reg_PSPT_enable_status1),
        .cfg_max_err_thresh_perlane            (cfg_max_err_thresh_perlane1),
        .cfg_max_err_thresh_aggr               (cfg_max_err_thresh_aggr1),
        .reg_lane_mask                         (reg_lane_mask1),
        .rdi_state                             (rdi_state1)
    );

    // =========================================================================
    // Auto-drivers
    // =========================================================================

    // RDI state driver (auto-transits to Active when in LOG_LINKINIT)
    always @(posedge lclk0 or negedge rst_n) begin
        if (!rst_n) rdi_state0 <= Reset;
        else if (current_ltsm_state_n0 == LOG_LINKINIT) begin
            repeat(20) @(posedge lclk0);
            rdi_state0 <= Active;
        end else if (current_ltsm_state_n0 == LOG_RESET)
            rdi_state0 <= Reset;
    end

    always @(posedge lclk1 or negedge rst_n) begin
        if (!rst_n) rdi_state1 <= Reset;
        else if (current_ltsm_state_n1 == LOG_LINKINIT) begin
            repeat(20) @(posedge lclk1);
            rdi_state1 <= Active;
        end else if (current_ltsm_state_n1 == LOG_RESET)
            rdi_state1 <= Reset;
    end

    // Training trigger auto-clear
    always @(posedge lclk0) begin
        if (current_ltsm_state_n0 != LOG_RESET && current_ltsm_state_n0 != LOG_NOP)
            phy_start0 <= 1'b0;
    end
    always @(posedge lclk1) begin
        if (current_ltsm_state_n1 != LOG_RESET && current_ltsm_state_n1 != LOG_NOP)
            phy_start1 <= 1'b0;
    end

    // Observability signals
    logic m_done, p_done, m_error, p_error;
    assign m_done  = (current_ltsm_state_n0 == LOG_ACTIVE);
    assign p_done  = (current_ltsm_state_n1 == LOG_ACTIVE);
    assign m_error = (current_ltsm_state_n0 == LOG_TRAINERROR);
    assign p_error = (current_ltsm_state_n1 == LOG_TRAINERROR);

    // Transition printing
    always @(current_ltsm_state_n0)
        $display("T=%0t | [DIE 0] state=%s", $time, current_ltsm_state_n0.name());
    always @(current_ltsm_state_n1)
        $display("T=%0t | [DIE 1] state=%s", $time, current_ltsm_state_n1.name());

    // =========================================================================
    // Reset helper task
    // =========================================================================
    task automatic reset_system();
        rst_n = 1'b0;
        phy_start0 = 1'b0;
        phy_start1 = 1'b0;
        Adapter_training_req0 = 1'b0;
        Adapter_training_req1 = 1'b0;
        SPMW0 = 1'b0;
        SPMW1 = 1'b0;

        reverse_lanes_0to1 = 1'b0;
        reverse_lanes_1to0 = 1'b0;
        die0_to_die1_corrupt_mask = 16'h0000;
        die1_to_die0_corrupt_mask = 16'h0000;
        block_sideband = 1'b0;

        lp_data0 = '0;
        lp_data1 = '0;
        lp_irdy0 = 1'b0;
        lp_irdy1 = 1'b0;
        lp_valid0 = 1'b0;
        lp_valid1 = 1'b0;

        // Default configurations
        reg_Target_Link_Width_ctrl0 = 4'h2; // x16
        reg_Target_Link_Width_ctrl1 = 4'h2; // x16
        reg_Target_Link_Speed_ctrl0 = 4'h5; // 32 GT/s
        reg_Target_Link_Speed_ctrl1 = 4'h5; // 32 GT/s
        reg_phy_x8_mode_ctrl0 = 1'b0;
        reg_phy_x8_mode_ctrl1 = 1'b0;

        // Reversal capability enabled by default
        reg_TARR_support_local_ctrl0 = 1'b1;
        reg_TARR_support_local_ctrl1 = 1'b1;

        #20;
        rst_n = 1'b1;
        
        // Wait for PLLs to start (stable lclk0)
        @(posedge lclk0);
        repeat(10) @(posedge lclk0);
        $display("T=%0t | [RESET] Reset released, clocks stable.", $time);
    endtask

    // =========================================================================
    // Scenario Executor
    // =========================================================================
    initial begin
        // Shared inputs defaults
        traffic_rdy0 = 1'b1;
        traffic_rdy1 = 1'b1;
        RDI_msg_no_send0 = 8'h0;
        RDI_msg_no_send1 = 8'h0;
        stall_send0 = 1'b0;
        stall_send1 = 1'b0;
        RDI_vld_send0 = 1'b0;
        RDI_vld_send1 = 1'b0;

        lp_cfg0 = 32'h0;
        lp_cfg1 = 32'h0;
        lp_cfg_vld0 = 1'b0;
        lp_cfg_vld1 = 1'b0;
        lp_cfg_crd0 = 1'b1;
        lp_cfg_crd1 = 1'b1;

        rf_rdata0 = 64'h0;
        rf_rdata1 = 64'h0;
        rdata_vld0 = 1'b0;
        rdata_vld1 = 1'b0;
        addr_err_o0 = 1'b0;
        addr_err_o1 = 1'b0;

        i_pll_speed_sel0 = 2'b00;
        i_pll_speed_sel1 = 2'b00;
        lclk_g0 = 1'b1; // keep ungated
        lclk_g1 = 1'b1;

        i_pcmp_thr_per_lane0 = 16'd100;
        i_pcmp_thr_per_lane1 = 16'd100;
        i_pcmp_thr_aggregate0 = 16'd1000;
        i_pcmp_thr_aggregate1 = 16'd1000;
        i_vcmp_thr0 = 16'd50;
        i_vcmp_thr1 = 16'd50;

        cfg_max_err_thresh_perlane0 = 12'd10;
        cfg_max_err_thresh_perlane1 = 12'd10;
        cfg_max_err_thresh_aggr0 = 16'd50;
        cfg_max_err_thresh_aggr1 = 16'd50;

        reg_lane_mask0 = 16'h0000;
        reg_lane_mask1 = 16'h0000;

        // Straps and support
        reg_TARR_support_local_cap0 = 1'b1;
        reg_TARR_support_local_cap1 = 1'b1;
        reg_L2SPD_support_local_cap0 = 1'b1;
        reg_L2SPD_support_local_cap1 = 1'b1;
        reg_PSPT_support_local_cap0 = 1'b1;
        reg_PSPT_support_local_cap1 = 1'b1;
        reg_PMO_support_local_cap0 = 1'b0; // No PMO
        reg_PMO_support_local_cap1 = 1'b0; // No PMO
        reg_Max_Link_Speed_cap0 = 4'b0101;
        reg_Max_Link_Speed_cap1 = 4'b0101;
        reg_Supported_TX_Vswing0 = 5'b00111;
        reg_Supported_TX_Vswing1 = 5'b00111;
        reg_so0 = 1'b0;
        reg_so1 = 1'b0;
        reg_mtp0 = 1'b1;
        reg_mtp1 = 1'b1;
        reg_Module_ID0 = 2'b00;
        reg_Module_ID1 = 2'b01;
        reg_Clock_Phase_cap0 = 2'b01;
        reg_Clock_Phase_cap1 = 2'b01;
        reg_Clock_mode_cap0 = 2'b01;
        reg_Clock_mode_cap1 = 2'b01;
        reg_TARR_support_local_ctrl0 = 1'b1;
        reg_TARR_support_local_ctrl1 = 1'b1;
        reg_PMO_support_local_ctrl0 = 1'b0; // No PMO
        reg_PMO_support_local_ctrl1 = 1'b0; // No PMO
        reg_Clock_Phase_ctrl0 = 1'b1;
        reg_Clock_Phase_ctrl1 = 1'b1;
        reg_Clock_mode_ctrl0 = 1'b1;
        reg_Clock_mode_ctrl1 = 1'b1;
        reg_L2SPD_support_local_ctrl0 = 1'b1;
        reg_L2SPD_support_local_ctrl1 = 1'b1;
        reg_PSPT_support_local_ctrl0 = 1'b1;
        reg_PSPT_support_local_ctrl1 = 1'b1;

        $display("================================================================");
        $display("  STARTING MB_SB_LTSM INTEGRATION TESTBENCH");
        $display("================================================================\n");

        // ----------------------------------------------------------------
        // SCENARIO 1: Happy Path Training -> ACTIVE
        // ----------------------------------------------------------------
        $display("T=%0t | [SC1] Happy Path: Reset and start training...", $time);
        reset_system();
        phy_start0 = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SC1] PASS -- Both dies reached ACTIVE successfully.", $time);
                $display("        Die0 Negotiated Width = %0h, Speed = %0h", reg_Link_Width_enable_status0, reg_Link_Speed_enable_status0);
                $display("        Die1 Negotiated Width = %0h, Speed = %0h", reg_Link_Width_enable_status1, reg_Link_Speed_enable_status1);
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [SC1] FAIL -- Training error on Die0=%0b, Die1=%0b", $time, m_error, p_error);
                $finish;
            end
            begin
                repeat(100000) @(posedge lclk0);
                $error("T=%0t | [SC1] TIMEOUT -- Simulation hung", $time);
                $finish;
            end
        join_any
        disable fork;

        // ----------------------------------------------------------------
        // SCENARIO 2: Watchdog Timeout
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC2] Watchdog: Block sideband, training should fail...", $time);
        reset_system();
        block_sideband = 1'b1;
        phy_start0 = 1'b1;

        fork
            begin
                wait (m_error);
                $display("T=%0t | [SC2] PASS -- Watchdog expired and Die0 errored out correctly.", $time);
            end
            begin
                wait (m_done);
                $error("T=%0t | [SC2] FAIL -- Reached ACTIVE with blocked sideband?", $time);
                $finish;
            end
            begin
                repeat(3000) @(posedge lclk0);
                $error("T=%0t | [SC2] TIMEOUT -- Watchdog did not fire within 3000 cycles.", $time);
                $finish;
            end
        join_any
        disable fork;

        // ----------------------------------------------------------------
        // SCENARIO 3: Asymmetric Width Negotiation (x16 vs x8 -> x8)
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC3] Asymmetric Width: Die0 requests x16, Die1 requests x8...", $time);
        reset_system();
        reg_Target_Link_Width_ctrl0 = 4'h2; // x16
        reg_Target_Link_Width_ctrl1 = 4'h1; // x8
        phy_start0 = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                if (reg_Link_Width_enable_status0 == 4'h1 && reg_Link_Width_enable_status1 == 4'h1) begin
                    $display("T=%0t | [SC3] PASS -- Both agreed on x8 width.", $time);
                end else begin
                    $error("T=%0t | [SC3] FAIL -- Mismatched width negotiation. Die0=%0h, Die1=%0h", $time, reg_Link_Width_enable_status0, reg_Link_Width_enable_status1);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [SC3] FAIL -- Training errored out.", $time);
                $finish;
            end
            begin
                repeat(100000) @(posedge lclk0);
                $error("T=%0t | [SC3] TIMEOUT -- Simulation hung", $time);
                $finish;
            end
        join_any
        disable fork;

        // ----------------------------------------------------------------
        // SCENARIO 4: Lane Reversal + Retry (Symmetric)
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC4] Symmetric Lane Reversal: Reverse physical channel, verify retry pass...", $time);
        reset_system();
        reverse_lanes_0to1 = 1'b1;
        reverse_lanes_1to0 = 1'b1;
        phy_start0 = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SC4] PASS -- Reversal resolved and reached ACTIVE.", $time);
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [SC4] FAIL -- Training errored out.", $time);
                $finish;
            end
            begin
                repeat(15000) @(posedge lclk0);
                $error("T=%0t | [SC4] TIMEOUT -- Simulation hung", $time);
                $finish;
            end
        join_any
        disable fork;

        // ----------------------------------------------------------------
        // SCENARIO 5: Asymmetric Lane Reversal
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC5] Asymmetric Lane Reversal: Reverse 0->1 only, verify retry pass...", $time);
        reset_system();
        reverse_lanes_0to1 = 1'b1;
        reverse_lanes_1to0 = 1'b0;
        phy_start0 = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SC5] PASS -- Asymmetric reversal resolved and reached ACTIVE.", $time);
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [SC5] FAIL -- Training errored out.\n" , $time);
                $display("  Die0 LTSM: %s, Reversal FSM: %s, retry_done: %b, majority_success: %b, success_count: %d, local_rx_success_count: %d, local_needs_retry: %b, remote_needs_retry: %b",
                    u_die0.current_ltsm_state_n.name(),
                    u_die0.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.current_state.name(),
                    u_die0.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.retry_done,
                    u_die0.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.majority_success,
                    u_die0.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.success_count,
                    u_die0.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.local_rx_success_count,
                    u_die0.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.local_needs_retry,
                    u_die0.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.remote_needs_retry
                );
                $display("  Die1 LTSM: %s, Reversal FSM: %s, retry_done: %b, majority_success: %b, success_count: %d, local_rx_success_count: %d, local_needs_retry: %b, remote_needs_retry: %b",
                    u_die1.current_ltsm_state_n.name(),
                    u_die1.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.current_state.name(),
                    u_die1.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.retry_done,
                    u_die1.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.majority_success,
                    u_die1.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.success_count,
                    u_die1.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.local_rx_success_count,
                    u_die1.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.local_needs_retry,
                    u_die1.u_ltsm_top.u_ltsm.u_mbinit.u_mbinit_wrapper.u_reversalmb.remote_needs_retry
                );
                $finish;
            end
            begin
                repeat(15000) @(posedge lclk0);
                $error("T=%0t | [SC5] TIMEOUT -- Simulation hung", $time);
                $finish;
            end
        join_any
        disable fork;

        // ----------------------------------------------------------------
        // SCENARIO 6: Width Degradation with Retry
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC6] Width Degradation: Corrupt upper 8 lanes (8-15), verify degrade to lower x8...", $time);
        reset_system();
        die0_to_die1_corrupt_mask = 16'hFF00; // Corrupt lanes 8-15
        die1_to_die0_corrupt_mask = 16'hFF00;
        phy_start0 = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                if (reg_Link_Width_enable_status0 == 4'h1 && reg_Link_Width_enable_status1 == 4'h1) begin
                    $display("T=%0t | [SC6] PASS -- Degraded to lower x8 width successfully.", $time);
                end else begin
                    $error("T=%0t | [SC6] FAIL -- Did not negotiate x8. Width0=%0h, Width1=%0h", $time, reg_Link_Width_enable_status0, reg_Link_Width_enable_status1);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [SC6] FAIL -- Training errored out.", $time);
                $finish;
            end
            begin
                repeat(15000) @(posedge lclk0);
                $error("T=%0t | [SC6] TIMEOUT -- Simulation hung", $time);
                $finish;
            end
        join_any
        disable fork;

        // ----------------------------------------------------------------
        // SCENARIO 7: Bidirectional Data Transfer After ACTIVE
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC7] Data Transfer: Train happy path, then send flits...", $time);
        reset_system();
        phy_start0 = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SC7] Reached ACTIVE. Starting bidirectional data transfers.", $time);
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [SC7] FAIL -- Training errored out.", $time);
                $finish;
            end
            begin
                repeat(100000) @(posedge lclk0);
                $error("T=%0t | [SC7] TIMEOUT -- Training hung", $time);
                $finish;
            end
        join_any
        disable fork;

        // Wait a few cycles in ACTIVE state
        repeat(20) @(posedge lclk0);

        // Drive valid and irdy
        lp_valid0 = 1'b1;
        lp_irdy0 = 1'b1;
        lp_valid1 = 1'b1;
        lp_irdy1 = 1'b1;

        // Send pair 1
        @(negedge lclk0);
        lp_data0 = {16{32'hDEADBEEF}};
        lp_data1 = {16{32'hCAFEBABE}};

        fork
            begin : pair1_recv
                // Require BOTH dies. wait is level-sensitive, so the order the two
                // o_pl_valid pulses arrive in does not matter.
                wait (o_pl_valid0 && o_out_data0 === {16{32'hCAFEBABE}});
                $display("T=%0t | [SC7] Die0 received CAFEBABE correctly.", $time);
                wait (o_pl_valid1 && o_out_data1 === {16{32'hDEADBEEF}});
                $display("T=%0t | [SC7] Die1 received DEADBEEF correctly.", $time);
            end
            begin
                repeat (200) @(posedge lclk0);
                $error("T=%0t | [SC7] TIMEOUT -- Data transfer did not complete within 200 cycles.", $time);
                $finish;
            end
        join_any
        disable fork;

        // Send pair 2
        @(negedge lclk0);
        lp_data0 = {16{32'h12345678}};
        lp_data1 = {16{32'h87654321}};

        fork
            begin : pair2_recv
                wait (o_pl_valid0 && o_out_data0 === {16{32'h87654321}});
                $display("T=%0t | [SC7] Die0 received 87654321 correctly.", $time);
                wait (o_pl_valid1 && o_out_data1 === {16{32'h12345678}});
                $display("T=%0t | [SC7] Die1 received 12345678 correctly.", $time);
            end
            begin
                repeat (200) @(posedge lclk0);
                $error("T=%0t | [SC7] TIMEOUT -- Data transfer did not complete within 200 cycles.", $time);
                $finish;
            end
        join_any
        disable fork;

        @(negedge lclk0);
        lp_valid0 = 1'b0;
        lp_valid1 = 1'b0;

        $display("\n================================================================");
        $display("  ALL SCENARIOS PASSED!");
        $display("  MB_SB_LTSM INTEGRATION SIM PASS");
        $display("================================================================\n");
        $finish;
    end

endmodule
