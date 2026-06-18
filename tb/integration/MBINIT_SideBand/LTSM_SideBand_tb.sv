`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

module LTSM_SideBand_tb;

    // =========================================================================
    // PARAMETERS
    // =========================================================================
    parameter DATA_WIDTH = 64;
    parameter GAP_WIDTH  = 32;
    parameter CLK_100_PERIOD = 10.0;  // 100 MHz (10ns period) for FSM & Parallel SB
    parameter CLK_800_PERIOD = 1.25;  // 800 MHz (1.25ns period) for SB Serial clock

    // =========================================================================
    // SYSTEM CLOCKS & RESET
    // =========================================================================
    logic clk_100;
    logic clk_800;
    logic rst_n;

    initial clk_100 = 0;
    always #(CLK_100_PERIOD/2.0) clk_100 = ~clk_100;

    initial clk_800 = 0;
    always #(CLK_800_PERIOD/2.0) clk_800 = ~clk_800;

    // =========================================================================
    // DIE 0 (MODULE/LOCAL) & DIE 1 (PARTNER/REMOTE) SIGNALS
    // =========================================================================
    
    // LTSM & Control States
    state_n_e    m_ltsm_state_n;
    state_n_e    p_ltsm_state_n;

    logic        m_done, m_error;
    logic        p_done, p_error;

    assign m_done = (m_ltsm_state_n == LOG_ACTIVE);
    assign p_done = (p_ltsm_state_n == LOG_ACTIVE);
    assign m_error = (m_ltsm_state_n == LOG_TRAINERROR);
    assign p_error = (p_ltsm_state_n == LOG_TRAINERROR);

    // Latched error signals for Scenario 7
    logic        m_error_seen;
    logic        p_error_seen;

    always_ff @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            m_error_seen <= 1'b0;
        end else if (m_error) begin
            m_error_seen <= 1'b1;
        end
    end

    always_ff @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            p_error_seen <= 1'b0;
        end else if (p_error) begin
            p_error_seen <= 1'b1;
        end
    end

    // Watchdog Timers
    logic        m_timeout_8ms_occured;
    logic        p_timeout_8ms_occured;

    // RESET Triggers
    logic        m_phy_start_ucie_link_training_ctrl_out;
    logic        m_Adapter_training_req;
    logic        m_sb_det_pattern_rcvd;

    logic        p_phy_start_ucie_link_training_ctrl_out;
    logic        p_Adapter_training_req;
    logic        p_sb_det_pattern_rcvd;

    // Log registers
    logic [7:0]  m_log0_state_n, p_log0_state_n;
    logic        m_log0_lane_reversal, p_log0_lane_reversal;
    logic        m_log0_width_degrade, p_log0_width_degrade;

    // Capability overrides
    logic [3:0]  m_reg_Target_Link_Width_ctrl;
    logic [3:0]  p_reg_Target_Link_Width_ctrl;

    logic [3:0]  m_reg_Target_Link_Speed_ctrl;
    logic [3:0]  p_reg_Target_Link_Speed_ctrl;

    logic        m_reg_phy_x8_mode_ctrl;
    logic        p_reg_phy_x8_mode_ctrl;

    // Capability status registers (outputs)
    logic        m_reg_Clock_Phase_enable_status, p_reg_Clock_Phase_enable_status;
    logic        m_reg_Clock_mode_enable_status,  p_reg_Clock_mode_enable_status;
    logic        m_reg_TARR_enable_status,        p_reg_TARR_enable_status;
    logic [3:0]  m_reg_Link_Width_enable_status,  p_reg_Link_Width_enable_status;
    logic [3:0]  m_reg_Link_Speed_enable_status,  p_reg_Link_Speed_enable_status;
    logic        m_reg_PMO_enable_status,         p_reg_PMO_enable_status;
    logic        m_reg_L2SPD_enable_status,       p_reg_L2SPD_enable_status;
    logic        m_reg_PSPT_enable_status,        p_reg_PSPT_enable_status;

    // Sideband Serial interface
    logic        TXCKSB [2];
    logic        RXCKSB [2];
    logic        TXDATASB [2];
    logic        RXDATASB [2];

    // Mainband Msg Bus (Connections between LTSM_wrapper and SideBand_Top)
    logic        mb_tx_valid [2];
    msg_no_e     mb_tx_msg_id [2];
    logic [15:0] mb_tx_MsgInfo [2];
    logic [63:0] mb_tx_data_Field [2];

    logic        mb_rx_valid [2];
    msg_no_e     mb_rx_msg_id [2];
    logic [15:0] mb_rx_MsgInfo [2];
    logic [63:0] mb_rx_data_Field [2];

    // Sideband control signals
    logic        ltsm_rdy [2];

    // SBINIT handshake signals
    logic        sb_iter_done [2];
    logic        sb_pattern_mode [2];
    logic        sb_det_pattern_req [2];
    logic [2:0]  sbinit_req_iter_count [2];

    // Mainband training count / passes
    logic        mb_tx_pattern_en [2];
    logic        mb_rx_compare_en [2];
    logic [2:0]  mb_rx_data_lane_mask [2];
    logic [2:0]  mb_tx_data_lane_mask [2];
    logic        mb_lane_reversal_req [2];

    // Inputs to LTSM_wrapper
    logic [15:0] mb_rx_perlane_pass [2];
    logic        mb_tx_pattern_count_done [2];
    logic        mb_rx_compare_done [2];

    // Training passes
    logic        m_repairclk_rtrk_pass, p_repairclk_rtrk_pass;
    logic        m_repairclk_rckn_pass, p_repairclk_rckn_pass;
    logic        m_repairclk_rckp_pass, p_repairclk_rckp_pass;
    logic        m_repairval_RVLD_L_pass, p_repairval_RVLD_L_pass;

    // RDI States
    RDI_state    m_rdi_state;
    RDI_state    p_rdi_state;

    // Helper variables for tests
    logic        m_pattern_done, p_pattern_done;

    // Cast helpers for sideband port compatibility
    logic [7:0] m_tx_msg_id_casted;
    logic [7:0] p_tx_msg_id_casted;
    logic [7:0] m_rx_msg_id_casted;
    logic [7:0] p_rx_msg_id_casted;

    assign m_tx_msg_id_casted = mb_tx_msg_id[0];
    assign p_tx_msg_id_casted = mb_tx_msg_id[1];
    assign mb_rx_msg_id[0]    = msg_no_e'(m_rx_msg_id_casted);
    assign mb_rx_msg_id[1]    = msg_no_e'(p_rx_msg_id_casted);

    // =========================================================================
    // LOOPBACK SERIAL CONNECTION (WITH DYNAMIC BLOCKING FOR WATCHDOG TESTING)
    // =========================================================================
    logic block_sideband;
    initial block_sideband = 1'b0;

    assign RXCKSB[0]   = block_sideband ? 1'b0 : TXCKSB[1];
    assign RXDATASB[0] = block_sideband ? 1'b0 : TXDATASB[1];

    assign RXCKSB[1]   = block_sideband ? 1'b0 : TXCKSB[0];
    assign RXDATASB[1] = block_sideband ? 1'b0 : TXDATASB[0];

    // =========================================================================
    // INSTANTIATION: SIDEBAND TOP (DIE 0)
    // =========================================================================
    SideBand_Top #(
        .DATA_WIDTH (DATA_WIDTH),
        .GAP_WIDTH  (GAP_WIDTH)
    ) u_sideband_0 (
        .clk_main         (clk_100),
        .rst_main_n       (rst_n),
        .clk_sb           (clk_100),
        .rst_sb_n         (rst_n),
        .phy_in_reset     (!rst_n),
        .pmo_en           (1'b1),
        
        .sb_pll_clock     (clk_800),
        .RXCKSB           (RXCKSB[0]),
        .TXCKSB           (TXCKSB[0]),
        .TXDATASB         (TXDATASB[0]),
        .RXDATASB         (RXDATASB[0]),

        .pattern_mode     (sb_pattern_mode[0]),
        .start_pat_req    (sb_det_pattern_req[0]),
        .req_iter_count   (sbinit_req_iter_count[0]),
        .iter_done        (sb_iter_done[0]),
        .det_pat_rcvd     (m_sb_det_pattern_rcvd),

        .traffic_req      (),
        .traffic_rdy      (1'b1),

        .RDI_msg_no_send  (8'b0),
        .stall_send       (1'b0),
        .RDI_vld_send     (1'b0),
        .RDI_rdy          (),

        // Connect FSM TX Msg Highway
        .ltsm_msg_n_send  (m_tx_msg_id_casted),
        .msg_data_send    (mb_tx_data_Field[0]),
        .msg_info_send    (mb_tx_MsgInfo[0]),
        .ltsm_vld_send    (mb_tx_valid[0]),
        .ltsm_rdy         (ltsm_rdy[0]),

        // Connect FSM RX Msg Highway
        .RDI_vld_rcvd     (),
        .RDI_msg_no_rcvd  (),
        .stall_rcvd       (),

        .ltsm_vld_rcvd    (mb_rx_valid[0]),
        .ltsm_msg_no_rcvd (m_rx_msg_id_casted),
        .msg_data_rcvd    (mb_rx_data_Field[0]),
        .msg_info_rcvd    (mb_rx_MsgInfo[0]),

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
    // INSTANTIATION: SIDEBAND TOP (DIE 1)
    // =========================================================================
    SideBand_Top #(
        .DATA_WIDTH (DATA_WIDTH),
        .GAP_WIDTH  (GAP_WIDTH)
    ) u_sideband_1 (
        .clk_main         (clk_100),
        .rst_main_n       (rst_n),
        .clk_sb           (clk_100),
        .rst_sb_n         (rst_n),
        .phy_in_reset     (!rst_n),
        .pmo_en           (1'b1),
        
        .sb_pll_clock     (clk_800),
        .RXCKSB           (RXCKSB[1]),
        .TXCKSB           (TXCKSB[1]),
        .TXDATASB         (TXDATASB[1]),
        .RXDATASB         (RXDATASB[1]),

        .pattern_mode     (sb_pattern_mode[1]),
        .start_pat_req    (sb_det_pattern_req[1]),
        .req_iter_count   (sbinit_req_iter_count[1]),
        .iter_done        (sb_iter_done[1]),
        .det_pat_rcvd     (p_sb_det_pattern_rcvd),

        .traffic_req      (),
        .traffic_rdy      (1'b1),

        .RDI_msg_no_send  (8'b0),
        .stall_send       (1'b0),
        .RDI_vld_send     (1'b0),
        .RDI_rdy          (),

        // Connect FSM TX Msg Highway
        .ltsm_msg_n_send  (p_tx_msg_id_casted),
        .msg_data_send    (mb_tx_data_Field[1]),
        .msg_info_send    (mb_tx_MsgInfo[1]),
        .ltsm_vld_send    (mb_tx_valid[1]),
        .ltsm_rdy         (ltsm_rdy[1]),

        // Connect FSM RX Msg Highway
        .RDI_vld_rcvd     (),
        .RDI_msg_no_rcvd  (),
        .stall_rcvd       (),

        .ltsm_vld_rcvd    (mb_rx_valid[1]),
        .ltsm_msg_no_rcvd (p_rx_msg_id_casted),
        .msg_data_rcvd    (mb_rx_data_Field[1]),
        .msg_info_rcvd    (mb_rx_MsgInfo[1]),

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
    // INSTANTIATION: LTSM_wrapper (DIE 0)
    // =========================================================================
    LTSM_wrapper #(
        .CLK_FRQ_HZ (100_000) // 100 kHz virtual clock to speed up 4ms/8ms timers in simulation
    ) u_ltsm_0 (
        .clk                                   (clk_100),
        .rst_n                                 (rst_n),

        .current_ltsm_state                    (),
        .current_ltsm_state_n                  (m_ltsm_state_n),
        .timeout_8ms_occured                   (m_timeout_8ms_occured),
        .log0_state_n                          (m_log0_state_n),
        .log0_lane_reversal                    (m_log0_lane_reversal),
        .log0_width_degrade                    (m_log0_width_degrade),
        .log0_state_n_minus_1                  (),
        .log0_state_n_minus_2                  (),
        .log1_state_n_minus_3                  (),

        .phy_start_ucie_link_training_ctrl_out (m_phy_start_ucie_link_training_ctrl_out),
        .Adapter_training_req                  (m_Adapter_training_req),
        .sb_det_pattern_rcvd                   (m_sb_det_pattern_rcvd),

        .SPMW                                  (1'b0),

        .reg_phy_x8_mode_ctrl                  (m_reg_phy_x8_mode_ctrl),
        .reg_TARR_support_local_cap            (1'b1),
        .reg_L2SPD_support_local_cap           (1'b1),
        .reg_PSPT_support_local_cap            (1'b1),
        .reg_PMO_support_local_cap             (1'b1),
        .reg_Max_Link_Speed_cap                (4'b0101),
        .reg_Supported_TX_Vswing               (5'b00111),
        .reg_so                                (1'b0),
        .reg_mtp                               (1'b1),
        .reg_Module_ID                         (2'b00),
        .reg_Clock_Phase_cap                   (2'b01),
        .reg_Clock_mode_cap                    (2'b01),
        .reg_TARR_support_local_ctrl           (1'b1),
        .reg_PMO_support_local_ctrl            (1'b1),
        .reg_Clock_Phase_ctrl                  (1'b1),
        .reg_Clock_mode_ctrl                   (1'b1),
        .reg_L2SPD_support_local_ctrl          (1'b1),
        .reg_PSPT_support_local_ctrl           (1'b1),
        .reg_Target_Link_Width_ctrl            (m_reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl            (m_reg_Target_Link_Speed_ctrl),

        .reg_Clock_Phase_enable_status         (m_reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status          (m_reg_Clock_mode_enable_status),
        .reg_TARR_enable_status                (m_reg_TARR_enable_status),
        .reg_Link_Width_enable_status          (m_reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status          (m_reg_Link_Speed_enable_status),
        .reg_PMO_enable_status                 (m_reg_PMO_enable_status),
        .reg_L2SPD_enable_status               (m_reg_L2SPD_enable_status),
        .reg_PSPT_enable_status                (m_reg_PSPT_enable_status),

        .cfg_max_err_thresh_perlane            (12'd10),
        .cfg_max_err_thresh_aggr               (16'd50),

        .sb_rx_valid                           (mb_rx_valid[0]),
        .sb_rx_msg_id                          (mb_rx_msg_id[0]),
        .sb_rx_MsgInfo                         (mb_rx_MsgInfo[0]),
        .sb_rx_data_Field                      (mb_rx_data_Field[0]),

        .sb_tx_valid                           (mb_tx_valid[0]),
        .sb_ltsm_rdy                           (ltsm_rdy[0]),
        .sb_tx_msg_id                          (mb_tx_msg_id[0]),
        .sb_tx_MsgInfo                         (mb_tx_MsgInfo[0]),
        .sb_tx_data_Field                      (mb_tx_data_Field[0]),

        .sb_iter_done                          (sb_iter_done[0]),
        .sb_pattern_mode                       (sb_pattern_mode[0]),
        .sb_det_pattern_req                    (sb_det_pattern_req[0]),
        .sbinit_req_iter_count                 (sbinit_req_iter_count[0]),

        .mb_tx_pattern_en                      (mb_tx_pattern_en[0]),
        .mb_tx_pattern_setup                   (),
        .mb_tx_data_pattern_sel                (),
        .mb_tx_val_pattern_sel                 (),
        .mb_tx_clk_pattern_sel                 (),
        .mb_rx_compare_en                      (mb_rx_compare_en[0]),
        .mb_rx_compare_setup                   (),
        .clear_error_req                       (),
        .mb_rx_data_lane_mask                  (mb_rx_data_lane_mask[0]),
        .mb_tx_data_lane_mask                  (mb_tx_data_lane_mask[0]),
        .mb_lane_reversal_req                  (mb_lane_reversal_req[0]),

        .mb_tx_trk_lane_sel                    (),
        .mb_tx_clk_lane_sel                    (),
        .mb_tx_val_lane_sel                    (),
        .mb_tx_data_lane_sel                   (),
        .mb_rx_trk_lane_sel                    (),
        .mb_rx_clk_lane_sel                    (),
        .mb_rx_val_lane_sel                    (),
        .mb_rx_data_lane_sel                   (),
        .mb_tx_lfsr_en                         (),
        .mb_tx_lfsr_rst                        (),
        .mb_rx_lfsr_en                         (),
        .mb_rx_lfsr_rst                        (),
        .mb_rx_pattern_setup                   (),
        .mb_rx_data_pattern_sel                (),
        .mb_rx_val_pattern_sel                 (),
        .mb_rx_pattern_mode                    (),
        .mb_rx_burst_count                     (),
        .mb_rx_idle_count                      (),
        .mb_rx_iter_count                      (),
        .mb_tx_pattern_mode                    (),
        .mb_tx_burst_count                     (),
        .mb_tx_idle_count                      (),
        .mb_tx_iter_count                      (),
        .mb_tx_clk_sampling_en                 (),
        .mb_tx_clk_sampling                    (),
        .mb_rx_max_err_thresh_perlane          (),
        .mb_rx_max_err_thresh_aggr             (),

        .mb_rx_perlane_pass                    (mb_rx_perlane_pass[0]),
        .mb_tx_pattern_count_done              (mb_tx_pattern_count_done[0]),
        .mb_rx_compare_done                    (mb_rx_compare_done[0]),
        .mb_rx_aggr_pass                       (1'b1),
        .mb_rx_val_pass                        (1'b1),
        .repairclk_rtrk_pass                   (m_repairclk_rtrk_pass),
        .repairclk_rckn_pass                   (m_repairclk_rckn_pass),
        .repairclk_rckp_pass                   (m_repairclk_rckp_pass),
        .repairval_RVLD_L_pass                 (m_repairval_RVLD_L_pass),

        .rdi_state                             (m_rdi_state)
    );

    // =========================================================================
    // INSTANTIATION: LTSM_wrapper (DIE 1)
    // =========================================================================
    LTSM_wrapper #(
        .CLK_FRQ_HZ (100_000)
    ) u_ltsm_1 (
        .clk                                   (clk_100),
        .rst_n                                 (rst_n),

        .current_ltsm_state                    (),
        .current_ltsm_state_n                  (p_ltsm_state_n),
        .timeout_8ms_occured                   (p_timeout_8ms_occured),
        .log0_state_n                          (p_log0_state_n),
        .log0_lane_reversal                    (p_log0_lane_reversal),
        .log0_width_degrade                    (p_log0_width_degrade),
        .log0_state_n_minus_1                  (),
        .log0_state_n_minus_2                  (),
        .log1_state_n_minus_3                  (),

        .phy_start_ucie_link_training_ctrl_out (p_phy_start_ucie_link_training_ctrl_out),
        .Adapter_training_req                  (p_Adapter_training_req),
        .sb_det_pattern_rcvd                   (p_sb_det_pattern_rcvd),

        .SPMW                                  (1'b0),

        .reg_phy_x8_mode_ctrl                  (p_reg_phy_x8_mode_ctrl),
        .reg_TARR_support_local_cap            (1'b1),
        .reg_L2SPD_support_local_cap           (1'b1),
        .reg_PSPT_support_local_cap            (1'b1),
        .reg_PMO_support_local_cap             (1'b1),
        .reg_Max_Link_Speed_cap                (4'b0101),
        .reg_Supported_TX_Vswing               (5'b00111),
        .reg_so                                (1'b0),
        .reg_mtp                               (1'b1),
        .reg_Module_ID                         (2'b00),
        .reg_Clock_Phase_cap                   (2'b01),
        .reg_Clock_mode_cap                    (2'b01),
        .reg_TARR_support_local_ctrl           (1'b1),
        .reg_PMO_support_local_ctrl            (1'b1),
        .reg_Clock_Phase_ctrl                  (1'b1),
        .reg_Clock_mode_ctrl                   (1'b1),
        .reg_L2SPD_support_local_ctrl          (1'b1),
        .reg_PSPT_support_local_ctrl           (1'b1),
        .reg_Target_Link_Width_ctrl            (p_reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl            (p_reg_Target_Link_Speed_ctrl),

        .reg_Clock_Phase_enable_status         (p_reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status          (p_reg_Clock_mode_enable_status),
        .reg_TARR_enable_status                (p_reg_TARR_enable_status),
        .reg_Link_Width_enable_status          (p_reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status          (p_reg_Link_Speed_enable_status),
        .reg_PMO_enable_status                 (p_reg_PMO_enable_status),
        .reg_L2SPD_enable_status               (p_reg_L2SPD_enable_status),
        .reg_PSPT_enable_status                (p_reg_PSPT_enable_status),

        .cfg_max_err_thresh_perlane            (12'd10),
        .cfg_max_err_thresh_aggr               (16'd50),

        .sb_rx_valid                           (mb_rx_valid[1]),
        .sb_rx_msg_id                          (mb_rx_msg_id[1]),
        .sb_rx_MsgInfo                         (mb_rx_MsgInfo[1]),
        .sb_rx_data_Field                      (mb_rx_data_Field[1]),

        .sb_tx_valid                           (mb_tx_valid[1]),
        .sb_ltsm_rdy                           (ltsm_rdy[1]),
        .sb_tx_msg_id                          (mb_tx_msg_id[1]),
        .sb_tx_MsgInfo                         (mb_tx_MsgInfo[1]),
        .sb_tx_data_Field                      (mb_tx_data_Field[1]),

        .sb_iter_done                          (sb_iter_done[1]),
        .sb_pattern_mode                       (sb_pattern_mode[1]),
        .sb_det_pattern_req                    (sb_det_pattern_req[1]),
        .sbinit_req_iter_count                 (sbinit_req_iter_count[1]),

        .mb_tx_pattern_en                      (mb_tx_pattern_en[1]),
        .mb_tx_pattern_setup                   (),
        .mb_tx_data_pattern_sel                (),
        .mb_tx_val_pattern_sel                 (),
        .mb_tx_clk_pattern_sel                 (),
        .mb_rx_compare_en                      (mb_rx_compare_en[1]),
        .mb_rx_compare_setup                   (),
        .clear_error_req                       (),
        .mb_rx_data_lane_mask                  (mb_rx_data_lane_mask[1]),
        .mb_tx_data_lane_mask                  (mb_tx_data_lane_mask[1]),
        .mb_lane_reversal_req                  (mb_lane_reversal_req[1]),

        .mb_tx_trk_lane_sel                    (),
        .mb_tx_clk_lane_sel                    (),
        .mb_tx_val_lane_sel                    (),
        .mb_tx_data_lane_sel                   (),
        .mb_rx_trk_lane_sel                    (),
        .mb_rx_clk_lane_sel                    (),
        .mb_rx_val_lane_sel                    (),
        .mb_rx_data_lane_sel                   (),
        .mb_tx_lfsr_en                         (),
        .mb_tx_lfsr_rst                        (),
        .mb_rx_lfsr_en                         (),
        .mb_rx_lfsr_rst                        (),
        .mb_rx_pattern_setup                   (),
        .mb_rx_data_pattern_sel                (),
        .mb_rx_val_pattern_sel                 (),
        .mb_rx_pattern_mode                    (),
        .mb_rx_burst_count                     (),
        .mb_rx_idle_count                      (),
        .mb_rx_iter_count                      (),
        .mb_tx_pattern_mode                    (),
        .mb_tx_burst_count                     (),
        .mb_tx_idle_count                      (),
        .mb_tx_iter_count                      (),
        .mb_tx_clk_sampling_en                 (),
        .mb_tx_clk_sampling                    (),
        .mb_rx_max_err_thresh_perlane          (),
        .mb_rx_max_err_thresh_aggr             (),

        .mb_rx_perlane_pass                    (mb_rx_perlane_pass[1]),
        .mb_tx_pattern_count_done              (mb_tx_pattern_count_done[1]),
        .mb_rx_compare_done                    (mb_rx_compare_done[1]),
        .mb_rx_aggr_pass                       (1'b1),
        .mb_rx_val_pass                        (1'b1),
        .repairclk_rtrk_pass                   (p_repairclk_rtrk_pass),
        .repairclk_rckn_pass                   (p_repairclk_rckn_pass),
        .repairclk_rckp_pass                   (p_repairclk_rckp_pass),
        .repairval_RVLD_L_pass                 (p_repairval_RVLD_L_pass),

        .rdi_state                             (p_rdi_state)
    );

    // =========================================================================
    // RDI STATE AUTO-DRIVER (Simulates RDI SM behavior)
    // =========================================================================
    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            m_rdi_state <= Reset;
        end else if (m_ltsm_state_n == LOG_LINKINIT) begin
            repeat(20) @(posedge clk_100);
            m_rdi_state <= Active;
        end else if (m_ltsm_state_n == LOG_RESET) begin
            m_rdi_state <= Reset;
        end
    end

    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            p_rdi_state <= Reset;
        end else if (p_ltsm_state_n == LOG_LINKINIT) begin
            repeat(20) @(posedge clk_100);
            p_rdi_state <= Active;
        end else if (p_ltsm_state_n == LOG_RESET) begin
            p_rdi_state <= Reset;
        end
    end

    // =========================================================================
    // RX COMPARE DONE HANDSHAKE
    // =========================================================================
    assign mb_rx_compare_done[0] = mb_tx_pattern_count_done[1];
    assign mb_rx_compare_done[1] = mb_tx_pattern_count_done[0];

    // =========================================================================
    // PATTERN DONE AUTOMATION (REPAIRCLK, REPAIRVAL, REVERSALMB)
    // =========================================================================
    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            mb_tx_pattern_count_done[0] <= 1'b0;
            m_pattern_done              <= 1'b0;
        end else if (mb_tx_pattern_en[0] && !m_pattern_done) begin
            repeat(20) @(posedge clk_100);
            mb_tx_pattern_count_done[0] <= 1'b1;
            m_pattern_done              <= 1'b1;
            @(posedge clk_100);
            mb_tx_pattern_count_done[0] <= 1'b0;
        end else if (!mb_tx_pattern_en[0]) begin
            m_pattern_done              <= 1'b0;
        end
    end

    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            mb_tx_pattern_count_done[1] <= 1'b0;
            p_pattern_done              <= 1'b0;
        end else if (mb_tx_pattern_en[1] && !p_pattern_done) begin
            repeat(20) @(posedge clk_100);
            mb_tx_pattern_count_done[1] <= 1'b1;
            p_pattern_done              <= 1'b1;
            @(posedge clk_100);
            mb_tx_pattern_count_done[1] <= 1'b0;
        end else if (!mb_tx_pattern_en[1]) begin
            p_pattern_done              <= 1'b0;
        end
    end

    // =========================================================================
    // AUTOMATIC RETRAINING TRIGGER CLEARING (Avoids LINKINIT false errors)
    // =========================================================================
    always @(posedge clk_100) begin
        if (m_ltsm_state_n != LOG_RESET && m_ltsm_state_n != LOG_NOP) begin
            m_phy_start_ucie_link_training_ctrl_out <= 1'b0;
        end
        if (p_ltsm_state_n != LOG_RESET && p_ltsm_state_n != LOG_NOP) begin
            p_phy_start_ucie_link_training_ctrl_out <= 1'b0;
        end
    end

    // =========================================================================
    // STATE TRANSITION LOGGER
    // =========================================================================
    always @(m_ltsm_state_n) begin
        $display("T=%0t | [DIE 0 LTSM] State changed to: %s", $time, m_ltsm_state_n.name());
    end

    always @(p_ltsm_state_n) begin
        $display("T=%0t | [DIE 1 LTSM] State changed to: %s", $time, p_ltsm_state_n.name());
    end

    // =========================================================================
    // SYSTEM RESET & HELPER TASKS
    // =========================================================================
    task reset_system();
        $display("T=%0t | [RESET] Starting System Reset...", $time);
        rst_n                                   = 1'b0;
        m_phy_start_ucie_link_training_ctrl_out = 1'b0;
        m_Adapter_training_req                  = 1'b0;
        p_phy_start_ucie_link_training_ctrl_out = 1'b0;
        p_Adapter_training_req                  = 1'b0;

        // Reset inputs
        mb_rx_perlane_pass[0] = 16'hFFFF; // Happy Path: all lanes pass
        mb_rx_perlane_pass[1] = 16'hFFFF;
        m_repairclk_rtrk_pass = 1'b1;
        m_repairclk_rckn_pass = 1'b1;
        m_repairclk_rckp_pass = 1'b1;
        m_repairval_RVLD_L_pass = 1'b1;

        p_repairclk_rtrk_pass = 1'b1;
        p_repairclk_rckn_pass = 1'b1;
        p_repairclk_rckp_pass = 1'b1;
        p_repairval_RVLD_L_pass = 1'b1;

        m_reg_Target_Link_Width_ctrl = 4'h2; // Default: x16
        p_reg_Target_Link_Width_ctrl = 4'h2;

        m_reg_Target_Link_Speed_ctrl = 4'h5; // Default: 32 GT/s (5h)
        p_reg_Target_Link_Speed_ctrl = 4'h5;

        m_reg_phy_x8_mode_ctrl = 1'b0;
        p_reg_phy_x8_mode_ctrl = 1'b0;

        repeat(20) @(posedge clk_100);
        rst_n    = 1'b1;
        repeat(5) @(posedge clk_100);
        $display("T=%0t | [RESET] Reset completed successfully.", $time);
    endtask

    // =========================================================================
    // TEST BENCH INITIAL FLOW
    // =========================================================================
    initial begin
        $display("\n==================================================================");
        $display("  STARTING LTSM WRAPPER & SIDEBAND INTEGRATION SIMULATION         ");
        $display("==================================================================\n");

        // ---------------------------------------------------------------------
        // SCENARIO 1: HAPPY PATH Loopback Training (Die 0 trigger, Die 1 wakes on SB)
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCENARIO 1] Starting Happy Path training...", $time);
        reset_system();
        block_sideband = 1'b0;

        $display("T=%0t | [TEST - SCENARIO 1] Triggering Die 0 (Die 1 should stay asleep/RESET until Sideband pattern is received)...", $time);
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                 $display("\n==================================================================");
                 $display("T=%0t | [SUCCESS - SCENARIO 1] Training completed successfully for both dies!", $time);
                 $display("            Module negotiated Link Width = 4'h%h, Speed = 4'h%h", m_reg_Link_Width_enable_status, m_reg_Link_Speed_enable_status);
                 $display("            Partner negotiated Link Width = 4'h%h, Speed = 4'h%h", p_reg_Link_Width_enable_status, p_reg_Link_Speed_enable_status);
                 if (m_reg_Link_Width_enable_status !== 4'h2 || p_reg_Link_Width_enable_status !== 4'h2) begin
                     $error("T=%0t | [ERROR] Negotiated Link Width mismatch (Expected x16 = 4'h2)!", $time);
                     $finish;
                 end
                 if (m_reg_Link_Speed_enable_status !== 4'h5 || p_reg_Link_Speed_enable_status !== 4'h5) begin
                     $error("T=%0t | [ERROR] Negotiated Link Speed mismatch (Expected 32 GT/s = 4'h5)!", $time);
                     $finish;
                 end
                 $display("==================================================================\n");
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCENARIO 1] Training encountered an error!", $time);
                $finish;
            end
            begin
                // With CLK_FRQ_HZ = 100_000, 8 ms is 800 clock cycles.
                // We give 5,000 cycles simulation safety budget
                repeat(5000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 1] Simulation hung!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 2: WATCHDOG TIMER EXPIRATION Testcase
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 2] Starting Watchdog Timer Expiration test...", $time);
        $display("==================================================================\n");
        reset_system();
        
        // Block sideband loops to simulate packet loss / hang
        block_sideband = 1'b1;

        $display("T=%0t | [TEST - SCENARIO 2] Triggering Die 0 with BLOCKED sideband...", $time);
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;

        fork
            begin
                // Wait for watchdog to trigger error on local die (since partner will never wake up)
                wait (m_error);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 2] Watchdog timer successfully expired on Die 0!", $time);
                $display("            m_timeout_8ms_occured = %b, m_error = %b", m_timeout_8ms_occured, m_error);
                $display("==================================================================\n");
            end
            begin
                wait (m_done);
                $error("T=%0t | [FAILURE - SCENARIO 2] Die 0 reported done but sideband was blocked!", $time);
                $finish;
            end
            begin
                repeat(2000) @(posedge clk_100);
                $error("T=%0t | [FAILURE - SCENARIO 2] Watchdog timer did not trigger in time!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 3: ASYMMETRIC WIDTH NEGOTIATION (x16 and x8 -> Agree on x8)
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 3] Starting Asymmetric Width Negotiation...", $time);
        $display("==================================================================\n");
        reset_system();
        block_sideband = 1'b0;

        // Die 0 wants x16 (4'h2), Die 1 wants x8 (4'h1)
        m_reg_Target_Link_Width_ctrl = 4'h2;
        p_reg_Target_Link_Width_ctrl = 4'h1;

        $display("T=%0t | [TEST - SCENARIO 3] Triggering training...", $time);
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 3] Successfully negotiated and completed at x8 width!", $time);
                $display("            Module final negotiated Link Width = 4'h%h, Speed = 4'h%h", m_reg_Link_Width_enable_status, m_reg_Link_Speed_enable_status);
                $display("            Partner final negotiated Link Width = 4'h%h, Speed = 4'h%h", p_reg_Link_Width_enable_status, p_reg_Link_Speed_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h1 || p_reg_Link_Width_enable_status !== 4'h1) begin
                     $error("T=%0t | [ERROR] Negotiated Link Width mismatch (Expected x8 = 4'h1)!", $time);
                     $finish;
                end
                $display("==================================================================\n");
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCENARIO 3] Training encountered an error!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 3] Simulation hung!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 4: TRAINING FAILURE IN CLOCK LANE REPAIR (Clock error)
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 4] Starting Clock Lane Repair Failure test...", $time);
        $display("==================================================================\n");
        reset_system();
        block_sideband = 1'b0;

        // Force clock lane failure on Die 0
        m_repairclk_rckp_pass = 1'b0;

        $display("T=%0t | [TEST - SCENARIO 4] Triggering training with forced clock failure on Die 0...", $time);
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;

        fork
            begin
                wait (m_error);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 4] Clock lane failure detected and errored out correctly!", $time);
                $display("            m_error = %b", m_error);
                $display("==================================================================\n");
            end
            begin
                wait (m_done);
                $error("T=%0t | [FAILURE - SCENARIO 4] Die 0 reported done despite clock lane failure!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 4] Watchdog expired instead of clean error exit!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 5: TRAINING FAILURE IN VALID LANE REPAIR (Valid error)
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 5] Starting Valid Lane Repair Failure test...", $time);
        $display("==================================================================\n");
        reset_system();
        block_sideband = 1'b0;

        // Force valid lane failure on Die 1
        p_repairval_RVLD_L_pass = 1'b0;

        $display("T=%0t | [TEST - SCENARIO 5] Triggering training with forced valid failure on Die 1...", $time);
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;

        fork
            begin
                wait (m_error || p_error);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 5] Valid lane failure detected and errored out correctly!", $time);
                $display("            m_error = %b, p_error = %b", m_error, p_error);
                $display("==================================================================\n");
            end
            begin
                wait (m_done && p_done);
                $error("T=%0t | [FAILURE - SCENARIO 5] Reported done despite valid lane failure!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 5] Watchdog expired instead of clean error exit!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 6: REVERSAL MB NEEDED & RETRY PASS (With Lane Reversal)
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 6] Starting Lane Reversal + Retry Pass test...", $time);
        $display("==================================================================\n");
        reset_system();
        block_sideband = 1'b0;

        // Force lane reversal by failing all lanes on the first run of REVERSALMB
        mb_rx_perlane_pass[0] = 16'h0000;
        mb_rx_perlane_pass[1] = 16'h0000;

        $display("T=%0t | [TEST - SCENARIO 6] Triggering training to trigger lane reversal...", $time);
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;

        // Wait for lane reversal request
        fork
            begin
                wait (mb_lane_reversal_req[0] || mb_lane_reversal_req[1]);
                $display("T=%0t | [TEST - SCENARIO 6] Lane Reversal request detected! Injecting passing lanes for retry...", $time);
                
                // Once reversal is requested, we make all lanes pass for the retry
                mb_rx_perlane_pass[0] = 16'hFFFF;
                mb_rx_perlane_pass[1] = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCENARIO 6] Training errored out before reversal request!", $time);
                $finish;
            end
            begin
                repeat(3000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 6] Reversal request not detected in time!", $time);
                $finish;
            end
        join_any
        disable fork;

        // Now wait for successful completion
        fork
            begin
                wait (m_done && p_done);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 6] Reversal training completed successfully!", $time);
                $display("==================================================================\n");
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCENARIO 6] Training errored out after reversal retry!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 6] Watchdog expired during retry!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 7: MAINBAND REPAIR DEGRADATION DOUBLE FAILURE (Retry FAIL)
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 7] Starting Mainband Repair Double Failure test...", $time);
        $display("==================================================================\n");
        reset_system();
        block_sideband = 1'b0;

        // First point test run: PASS lower 8 lanes, FAIL upper 8 lanes (causes degrade to lower x8)
        mb_rx_perlane_pass[0] = 16'h00FF;
        mb_rx_perlane_pass[1] = 16'h00FF;

        $display("T=%0t | [TEST - SCENARIO 7] Triggering training to trigger first degradation...", $time);
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;

        // Wait until they enter point test S2 of REPAIRMB
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        
        // Wait for retry start (when current_state goes back to point test S2 on retry)
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state != u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        $display("T=%0t | [TEST - SCENARIO 7] Retry detected! Injecting complete data lane failure...", $time);

        // Retry Point Test: Fail completely (all 0) -> no further degrade possible
        mb_rx_perlane_pass[0] = 16'h0000;
        mb_rx_perlane_pass[1] = 16'h0000;

        fork
            begin
                wait (m_error_seen && p_error_seen);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 7] Double failure correctly errored out!", $time);
                $display("            m_error = %b, p_error = %b", m_error, p_error);
                $display("==================================================================\n");
            end
            begin
                wait (m_done || p_done);
                $error("T=%0t | [FAILURE - SCENARIO 7] Reported done despite double failure!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 7] Watchdog expired instead of clean error exit!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 8: ASYMMETRIC REPAIR DEGRADATION (Module x8 & Lanes 0:3; Partner default & Lanes 4:15 -> Aligned to x4)
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 8] Starting Asymmetric Repair Degradation to x4...", $time);
        $display("==================================================================\n");
        reset_system();
        block_sideband = 1'b0;

        // Die 0 requests x8, Die 1 requests default (x16)
        m_reg_Target_Link_Width_ctrl = 4'h1; // x8
        p_reg_Target_Link_Width_ctrl = 4'h2; // x16

        // Point Test inputs for Run 1:
        // Die 0 has lanes 0:3 passing (16'h000F)
        // Die 1 has lanes 4:15 passing (16'hFFF0)
        mb_rx_perlane_pass[0] = 16'h000F;
        mb_rx_perlane_pass[1] = 16'hFFF0;

        $display("T=%0t | [TEST - SCENARIO 8] Triggering training with asymmetric width and lane maps...", $time);
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;

        // Wait until they enter point test S2 of REPAIRMB for the first time
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        
        // Wait for retry start
        fork
            begin
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state != u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCENARIO 8] Retry detected! Injecting passing lanes for retry point test...", $time);
                
                mb_rx_perlane_pass[0] = 16'hFFFF;
                mb_rx_perlane_pass[1] = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCENARIO 8] Training errored out before retry!", $time);
                $finish;
            end
            begin
                repeat(3000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 8] Retry not detected in time!", $time);
                $finish;
            end
        join_any
        disable fork;

        // Wait for successful completion
        fork
            begin
                wait (m_done && p_done);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 8] Successfully completed training with asymmetric maps aligned to x4!", $time);
                $display("            Module negotiated Link Width = 4'h%h, Speed = 4'h%h", m_reg_Link_Width_enable_status, m_reg_Link_Speed_enable_status);
                $display("            Partner negotiated Link Width = 4'h%h, Speed = 4'h%h", p_reg_Link_Width_enable_status, p_reg_Link_Speed_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h0 || p_reg_Link_Width_enable_status !== 4'h0) begin
                    $error("T=%0t | [ERROR] Negotiated Link Width mismatch (Expected x4 = 4'h0)!", $time);
                    $finish;
                end
                $display("==================================================================\n");
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCENARIO 8] Training encountered an error after retry!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $error("T=%0t | [TIMEOUT - SCENARIO 8] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 9: DYNAMIC CAPABILITY SWEEP & OVERRIDES
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 9] Starting Dynamic Capability Sweep & Force x8 overrides...", $time);
        $display("==================================================================\n");

        // 9A: Forced x8 on Die 0 only
        $display("T=%0t | [TEST - SCN 9A] Force x8 on Die 0 only...", $time);
        reset_system();
        block_sideband = 1'b0;
        m_reg_phy_x8_mode_ctrl = 1'b1;
        p_reg_phy_x8_mode_ctrl = 1'b0;
        m_reg_Target_Link_Width_ctrl = 4'h2;
        p_reg_Target_Link_Width_ctrl = 4'h2;
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9A] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 1)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h1 || p_reg_Link_Width_enable_status !== 4'h1) begin
                    $error("T=%0t | [FAILURE - SCN 9A] Expected width 4'h1 (x8)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9A] Training failed!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // 9B: Forced x8 on Die 1 only
        $display("T=%0t | [TEST - SCN 9B] Force x8 on Die 1 only...", $time);
        reset_system();
        block_sideband = 1'b0;
        m_reg_phy_x8_mode_ctrl = 1'b0;
        p_reg_phy_x8_mode_ctrl = 1'b1;
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9B] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 1)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h1 || p_reg_Link_Width_enable_status !== 4'h1) begin
                    $error("T=%0t | [FAILURE - SCN 9B] Expected width 4'h1 (x8)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9B] Training failed!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // 9C: Forced x8 on Both dies
        $display("T=%0t | [TEST - SCN 9C] Force x8 on both dies...", $time);
        reset_system();
        block_sideband = 1'b0;
        m_reg_phy_x8_mode_ctrl = 1'b1;
        p_reg_phy_x8_mode_ctrl = 1'b1;
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9C] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 1)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h1 || p_reg_Link_Width_enable_status !== 4'h1) begin
                    $error("T=%0t | [FAILURE - SCN 9C] Expected width 4'h1 (x8)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9C] Training failed!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // 9D: Target width mismatch
        $display("T=%0t | [TEST - SCN 9D] Target width mismatch...", $time);
        reset_system();
        block_sideband = 1'b0;
        m_reg_Target_Link_Width_ctrl = 4'h2; // wants x16
        p_reg_Target_Link_Width_ctrl = 4'h1; // wants x8
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9D] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 1)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h1 || p_reg_Link_Width_enable_status !== 4'h1) begin
                    $error("T=%0t | [FAILURE - SCN 9D] Expected width 4'h1 (x8)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9D] Training failed!", $time);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // 9E: Target speed mismatch
        $display("T=%0t | [TEST - SCN 9E] Target Link Speed Mismatch (32 vs 16 GT/s)...", $time);
        reset_system();
        block_sideband = 1'b0;
        m_reg_Target_Link_Speed_ctrl = 4'h5; // 32 GT/s
        p_reg_Target_Link_Speed_ctrl = 4'h3; // 16 GT/s
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9E] Completed. Negotiated Speed: m=%0h, p=%0h (Expected: 3)", $time, m_reg_Link_Speed_enable_status, p_reg_Link_Speed_enable_status);
                if (m_reg_Link_Speed_enable_status !== 4'h3 || p_reg_Link_Speed_enable_status !== 4'h3) begin
                    $error("T=%0t | [FAILURE - SCN 9E] Expected speed 4'h3 (16 GT/s)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // 9F-1: x16 with forced lane 7 failure (lower x8 fail -> degrade to upper x8)
        $display("T=%0t | [TEST - SCN 9F-1] x16 capability with forced lane 7 failure...", $time);
        reset_system();
        block_sideband = 1'b0;
        mb_rx_perlane_pass[0] = 16'hFF7F; // lane 7 fails
        mb_rx_perlane_pass[1] = 16'hFFFF;
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        fork
            begin
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state != u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCN 9F-1] Retry detected! Setting passing lanes for retry point test...", $time);
                mb_rx_perlane_pass[0] = 16'hFFFF;
                mb_rx_perlane_pass[1] = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(3000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9F-1] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 1)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h1 || p_reg_Link_Width_enable_status !== 4'h1) begin
                    $error("T=%0t | [FAILURE - SCN 9F-1] Expected width 4'h1 (x8)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // 9F-2: Forced x8 with forced lane 5 failure (lower x8 fail -> degrade to lower x4)
        $display("T=%0t | [TEST - SCN 9F-2] Forced x8 with lane 5 failure...", $time);
        reset_system();
        block_sideband = 1'b0;
        m_reg_phy_x8_mode_ctrl = 1'b1;
        p_reg_phy_x8_mode_ctrl = 1'b1;
        m_reg_Target_Link_Width_ctrl = 4'h1; // target x8
        p_reg_Target_Link_Width_ctrl = 4'h1;
        mb_rx_perlane_pass[0] = 16'hEFDF; // lane 5 fails
        mb_rx_perlane_pass[1] = 16'hFFFF;
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        fork
            begin
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state != u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCN 9F-2] Retry detected! Setting passing lanes for retry point test...", $time);
                mb_rx_perlane_pass[0] = 16'hFFFF;
                mb_rx_perlane_pass[1] = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(3000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9F-2] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 0)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h0 || p_reg_Link_Width_enable_status !== 4'h0) begin
                    $error("T=%0t | [FAILURE - SCN 9F-2] Expected width 4'h0 (x4)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // 9F-3: Asymmetric Lane Degradation
        $display("T=%0t | [TEST - SCN 9F-3] Asymmetric Lane Degradation (Master lower x8 fail -> upper x8; Partner -> lower x8)...", $time);
        reset_system();
        block_sideband = 1'b0;
        mb_rx_perlane_pass[0] = 16'hFFDF; // Master lane 5 fails
        mb_rx_perlane_pass[1] = 16'hFFFF;
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        fork
            begin
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state != u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCN 9F-3] Retry detected! Setting passing lanes for retry point test...", $time);
                mb_rx_perlane_pass[0] = 16'hFFFF;
                mb_rx_perlane_pass[1] = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(3000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9F-3] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 1)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h1 || p_reg_Link_Width_enable_status !== 4'h1) begin
                    $error("T=%0t | [FAILURE - SCN 9F-3] Expected width 4'h1 (x8)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // Scenario 10: Asymmetric initial capacities
        $display("T=%0t | [TEST - SCENARIO 10] Asymmetric Initial capacity training...", $time);
        reset_system();
        block_sideband = 1'b0;
        m_reg_phy_x8_mode_ctrl = 1'b1;
        p_reg_phy_x8_mode_ctrl = 1'b1;
        m_reg_Target_Link_Width_ctrl = 4'h1; // x8
        p_reg_Target_Link_Width_ctrl = 4'h1; // x8
        mb_rx_perlane_pass[0] = 16'h00FF; // lower x8
        mb_rx_perlane_pass[1] = 16'h000F; // lower x4
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        fork
            begin
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state != u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCENARIO 10] Retry detected! Setting passing lanes for retry point test...", $time);
                mb_rx_perlane_pass[0] = 16'hFFFF;
                mb_rx_perlane_pass[1] = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(3000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCENARIO 10] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 0)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h0 || p_reg_Link_Width_enable_status !== 4'h0) begin
                    $error("T=%0t | [FAILURE - SCENARIO 10] Expected width 4'h0 (x4)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        // Scenario 11: User scenario
        $display("T=%0t | [TEST - SCENARIO 11] User scenario (Master lower x4, Partner upper x8 + lower x4)...", $time);
        reset_system();
        block_sideband = 1'b0;
        m_reg_phy_x8_mode_ctrl = 1'b1;
        p_reg_phy_x8_mode_ctrl = 1'b1;
        m_reg_Target_Link_Width_ctrl = 4'h1; // target x8
        p_reg_Target_Link_Width_ctrl = 4'h1;
        mb_rx_perlane_pass[0] = 16'h000F; // lanes 0-3 pass
        mb_rx_perlane_pass[1] = 16'hFF0F; // lanes 4-7 fail
        @(posedge clk_100);
        m_phy_start_ucie_link_training_ctrl_out = 1'b1;
        wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        fork
            begin
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state != u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.current_state == u_ltsm_0.u_mbinit.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCENARIO 11] Retry detected! Setting passing lanes for retry point test...", $time);
                mb_rx_perlane_pass[0] = 16'hFFFF;
                mb_rx_perlane_pass[1] = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(3000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCENARIO 11] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 0)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                if (m_reg_Link_Width_enable_status !== 4'h0 || p_reg_Link_Width_enable_status !== 4'h0) begin
                    $error("T=%0t | [FAILURE - SCENARIO 11] Expected width 4'h0 (x4)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $finish;
            end
            begin
                repeat(5000) @(posedge clk_100);
                $finish;
            end
        join_any
        disable fork;

        $display("\n==================================================================");
        $display("  ALL TEST SCENARIOS COMPLETED SUCCESSFULLY!");
        $display("==================================================================\n");
        $finish;
    end

endmodule
