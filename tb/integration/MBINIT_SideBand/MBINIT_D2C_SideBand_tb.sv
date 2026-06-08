`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;

module MBINIT_D2C_SideBand_tb;

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
    
    // LTSM & Control
    logic        m_enable, m_done, m_error;
    logic        p_enable, p_done, p_error;
    state_n_e    m_mbinit_state_n;
    state_n_e    p_mbinit_state_n;

    logic [3:0]  m_reg_Target_Link_Width_ctrl;
    logic [3:0]  p_reg_Target_Link_Width_ctrl;

    logic [3:0]  m_reg_Target_Link_Speed_ctrl;
    logic [3:0]  p_reg_Target_Link_Speed_ctrl;

    logic        m_reg_phy_x8_mode_ctrl;
    logic        p_reg_phy_x8_mode_ctrl;

    // External Watchdog Timer Wires
    logic        m_timer_enable;
    logic        m_timer_rst_n;
    logic        m_timer_timeout_expired;

    logic        p_timer_enable;
    logic        p_timer_rst_n;
    logic        p_timer_timeout_expired;

    // Capability status registers (outputs)
    logic        m_reg_Clock_Phase_enable_status, p_reg_Clock_Phase_enable_status;
    logic        m_reg_Clock_mode_enable_status,  p_reg_Clock_mode_enable_status;
    logic        m_reg_TARR_enable_status,        p_reg_TARR_enable_status;
    logic [3:0]  m_reg_Link_Width_enable_status,  p_reg_Link_Width_enable_status;
    logic [3:0]  m_reg_Link_Speed_enable_status,  p_reg_Link_Speed_enable_status;
    logic        m_reg_PMO_enable_status,         p_reg_PMO_enable_status;
    logic        m_reg_L2SPD_enable_status,       p_reg_L2SPD_enable_status;
    logic        m_reg_PSPT_enable_status,        p_reg_PSPT_enable_status;

    // D2C Point Test interface
    logic        m_local_tx_pt_en, m_partner_tx_pt_en;
    logic        p_local_tx_pt_en, p_partner_tx_pt_en;
    logic [2:0]  m_d2c_pattern_setup, p_d2c_pattern_setup;
    logic [1:0]  m_d2c_data_pattern_sel, p_d2c_data_pattern_sel;
    logic        m_d2c_pattern_mode, p_d2c_pattern_mode;
    logic [1:0]  m_d2c_compare_setup, p_d2c_compare_setup;
    logic [15:0] m_d2c_perlane_pass, p_d2c_perlane_pass;
    logic        m_local_test_d2c_done, m_partner_test_d2c_done;
    logic        p_local_test_d2c_done, p_partner_test_d2c_done;

    // Sideband Serial interface
    logic        TXCKSB [2];
    logic        RXCKSB [2];
    logic        TXDATASB [2];
    logic        RXDATASB [2];

    // Mainband Msg Bus (Internal connections between MBINIT and SideBand)
    logic        mb_tx_valid [2];
    msg_no_e     mb_tx_msg_id [2];
    logic [15:0] mb_tx_MsgInfo [2];
    logic [63:0] mb_tx_data_Field [2];

    logic        mb_rx_valid [2];
    msg_no_e     mb_rx_msg_id [2];
    logic [15:0] mb_rx_MsgInfo [2];
    logic [63:0] mb_rx_data_Field [2];

    // MBINIT outputs before MUXing
    logic        mbinit_tx_valid [2];
    msg_no_e     mbinit_tx_msg_id [2];
    logic [15:0] mbinit_tx_MsgInfo [2];
    logic [63:0] mbinit_tx_data_Field [2];
    logic        mbinit_mb_tx_pattern_en [2];

    // D2C Point Test top wrapper instances & control signals
    logic [15:0] m_d2c_perlane_pass_from_pt;
    logic [15:0] p_d2c_perlane_pass_from_pt;
    logic        m_d2c_active;
    logic        p_d2c_active;
    logic        mb_rx_compare_done [2];
    logic        mbinit_mb_rx_compare_en [2];

    wire        u_d2c_top_0_mb_tx_pattern_en;
    wire        u_d2c_top_0_mb_rx_compare_en;
    wire        u_d2c_top_0_tx_sb_msg_valid;
    wire [7:0]  u_d2c_top_0_tx_sb_msg;
    wire [15:0] u_d2c_top_0_tx_msginfo;
    wire [63:0] u_d2c_top_0_tx_data_field;

    wire        u_d2c_top_1_mb_tx_pattern_en;
    wire        u_d2c_top_1_mb_rx_compare_en;
    wire        u_d2c_top_1_tx_sb_msg_valid;
    wire [7:0]  u_d2c_top_1_tx_sb_msg;
    wire [15:0] u_d2c_top_1_tx_msginfo;
    wire [63:0] u_d2c_top_1_tx_data_field;

    assign m_d2c_active = m_local_tx_pt_en | m_partner_tx_pt_en;
    assign p_d2c_active = p_local_tx_pt_en | p_partner_tx_pt_en;

    // Sideband control signals
    logic        ltsm_rdy [2];

    // Mainband training count / passes
    logic        mb_tx_pattern_en [2];
    logic [2:0]  mb_tx_pattern_setup [2];
    logic [1:0]  mb_tx_data_pattern_sel [2];
    logic        mb_tx_val_pattern_sel [2];
    logic        mb_rx_compare_en [2];
    logic [1:0]  mb_rx_compare_setup [2];
    logic        clear_error_req [2];
    logic [2:0]  mbinit_rx_data_lane_mask [2];
    logic [2:0]  mbinit_tx_data_lane_mask [2];

    // Inputs to MBINIT
    logic [15:0] mb_rx_perlane_pass [2];
    logic        mb_tx_pattern_count_done [2];
    logic        mb_lane_reversal_req [2];

    // Training passes
    logic        m_repairclk_rtrk_pass, p_repairclk_rtrk_pass;
    logic        m_repairclk_rckn_pass, p_repairclk_rckn_pass;
    logic        m_repairclk_rckp_pass, p_repairclk_rckp_pass;
    logic        m_repairval_RVLD_L_pass, p_repairval_RVLD_L_pass;

    // Pattern Simulation
    logic        m_pattern_done, p_pattern_done;

    // Cast helpers for sideband port compatibility
    logic [7:0] m_tx_msg_id_casted;
    logic [7:0] p_tx_msg_id_casted;
    logic [7:0] m_rx_msg_id_casted;
    logic [7:0] p_rx_msg_id_casted;

    assign m_tx_msg_id_casted  = m_d2c_active ? u_d2c_top_0_tx_sb_msg : mbinit_tx_msg_id[0];
    assign mb_tx_data_Field[0] = m_d2c_active ? u_d2c_top_0_tx_data_field : mbinit_tx_data_Field[0];
    assign mb_tx_MsgInfo[0]    = m_d2c_active ? u_d2c_top_0_tx_msginfo : mbinit_tx_MsgInfo[0];
    assign mb_tx_valid[0]      = m_d2c_active ? u_d2c_top_0_tx_sb_msg_valid : mbinit_tx_valid[0];

    assign p_tx_msg_id_casted  = p_d2c_active ? u_d2c_top_1_tx_sb_msg : mbinit_tx_msg_id[1];
    assign mb_tx_data_Field[1] = p_d2c_active ? u_d2c_top_1_tx_data_field : mbinit_tx_data_Field[1];
    assign mb_tx_MsgInfo[1]    = p_d2c_active ? u_d2c_top_1_tx_msginfo : mbinit_tx_MsgInfo[1];
    assign mb_tx_valid[1]      = p_d2c_active ? u_d2c_top_1_tx_sb_msg_valid : mbinit_tx_valid[1];

    assign mb_rx_msg_id[0]     = msg_no_e'(m_rx_msg_id_casted);
    assign mb_rx_msg_id[1]     = msg_no_e'(p_rx_msg_id_casted);

    assign mb_tx_pattern_en[0] = m_d2c_active ? u_d2c_top_0_mb_tx_pattern_en : mbinit_mb_tx_pattern_en[0];
    assign mb_tx_pattern_en[1] = p_d2c_active ? u_d2c_top_1_mb_tx_pattern_en : mbinit_mb_tx_pattern_en[1];

    assign mb_rx_compare_en[0] = m_d2c_active ? u_d2c_top_0_mb_rx_compare_en : mbinit_mb_rx_compare_en[0];
    assign mb_rx_compare_en[1] = p_d2c_active ? u_d2c_top_1_mb_rx_compare_en : mbinit_mb_rx_compare_en[1];

    assign mb_rx_compare_done[0] = mb_tx_pattern_count_done[1];
    assign mb_rx_compare_done[1] = mb_tx_pattern_count_done[0];

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

        .pattern_mode     (1'b0),
        .start_pat_req    (1'b0),
        .req_iter_count   (3'b0),
        .iter_done        (),
        .det_pat_rcvd     (),

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

        .pattern_mode     (1'b0),
        .start_pat_req    (1'b0),
        .req_iter_count   (3'b0),
        .iter_done        (),
        .det_pat_rcvd     (),

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
    // INSTANTIATION: MBINIT (DIE 0)
    // =========================================================================
    MBINIT #(
        .CLK_FRQ_HZ (100_000_000)
    ) u_mbinit_0 (
        .clk                          (clk_100),
        .rst_n                        (rst_n),

        .mbinit_enable                (m_enable),
        .mbinit_done                  (m_done),
        .mbinit_error                 (m_error),
        .mbinit_state_n               (m_mbinit_state_n),
        .SPMW                         (1'b0),

        .reg_phy_x8_mode_ctrl         (m_reg_phy_x8_mode_ctrl),
        .local_max_speed              (4'b0101), // 32GT/s
        .local_sbfe                   (1'b1),
        .reg_TARR_support_local_cap   (1'b1),
        .reg_L2SPD_support_local_cap  (1'b1),
        .reg_PSPT_support_local_cap   (1'b1),
        .local_so                     (1'b0),
        .reg_PMO_support_local_cap    (1'b1),
        .reg_Max_Link_Width_cap       (3'b000),  // x16 (0h)
        .reg_Max_Link_Speed_cap       (4'b0101), // 32GT/s (5h)
        .local_mtp                    (1'b1),

        .reg_Supported_TX_Vswing      (5'b00111),
        .reg_so                       (1'b0),
        .reg_mtp                      (1'b1),
        .reg_Module_ID                (2'b00),
        .reg_Clock_Phase_cap          (2'b01),
        .reg_Clock_mode_cap           (2'b01),
        .reg_TARR_support_local_ctrl  (1'b1),
        .reg_PMO_support_local_ctrl   (1'b1),
        .reg_Clock_Phase_ctrl         (1'b1),
        .reg_Clock_mode_ctrl          (1'b1),

        .reg_L2SPD_support_local_ctrl (1'b1),
        .reg_PSPT_support_local_ctrl  (1'b1),
        .reg_Target_Link_Width_ctrl   (m_reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl   (m_reg_Target_Link_Speed_ctrl),

        .reg_Clock_Phase_enable_status(m_reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status (m_reg_Clock_mode_enable_status),
        .reg_TARR_enable_status       (m_reg_TARR_enable_status),
        .reg_Link_Width_enable_status (m_reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status (m_reg_Link_Speed_enable_status),
        .reg_PMO_enable_status        (m_reg_PMO_enable_status),
        .reg_L2SPD_enable_status      (m_reg_L2SPD_enable_status),
        .reg_PSPT_enable_status       (m_reg_PSPT_enable_status),

        .local_tx_pt_en               (m_local_tx_pt_en),
        .partner_tx_pt_en             (m_partner_tx_pt_en),
        .d2c_pattern_setup            (m_d2c_pattern_setup),
        .d2c_data_pattern_sel         (m_d2c_data_pattern_sel),
        .d2c_pattern_mode             (m_d2c_pattern_mode),
        .d2c_compare_setup            (m_d2c_compare_setup),
        .d2c_perlane_pass             (m_d2c_perlane_pass_from_pt),
        .local_test_d2c_done          (m_local_test_d2c_done),
        .partner_test_d2c_done        (m_partner_test_d2c_done),

        // Connect Sideband Msg Bus (TX & RX)
        .sb_rx_valid                  (mb_rx_valid[0]),
        .sb_rx_msg_id                 (mb_rx_msg_id[0]),
        .sb_rx_MsgInfo                (mb_rx_MsgInfo[0]),
        .sb_rx_data_Field             (mb_rx_data_Field[0]),

        .sb_tx_valid                  (mbinit_tx_valid[0]),
        .sb_ltsm_rdy                  (ltsm_rdy[0]),
        .sb_tx_msg_id                 (mbinit_tx_msg_id[0]),
        .sb_tx_MsgInfo                (mbinit_tx_MsgInfo[0]),
        .sb_tx_data_Field             (mbinit_tx_data_Field[0]),

        // Training Control Signals
        .mb_tx_pattern_en             (mbinit_mb_tx_pattern_en[0]),
        .mb_tx_pattern_setup          (mb_tx_pattern_setup[0]),
        .mb_tx_data_pattern_sel       (mb_tx_data_pattern_sel[0]),
        .mb_tx_val_pattern_sel        (mb_tx_val_pattern_sel[0]),
        .mb_rx_compare_en             (mbinit_mb_rx_compare_en[0]),
        .mb_rx_compare_setup          (mb_rx_compare_setup[0]),
        .clear_error_req              (clear_error_req[0]),
        .mbinit_rx_data_lane_mask     (mbinit_rx_data_lane_mask[0]),
        .mbinit_tx_data_lane_mask     (mbinit_tx_data_lane_mask[0]),

        // Inputs
        .mb_rx_perlane_pass           (mb_rx_perlane_pass[0]),
        .mb_tx_pattern_count_done     (mb_tx_pattern_count_done[0]),
        
        .mb_lane_reversal_req         (mb_lane_reversal_req[0]),
        .repairclk_rtrk_pass          (m_repairclk_rtrk_pass),
        .repairclk_rckn_pass          (m_repairclk_rckn_pass),
        .repairclk_rckp_pass          (m_repairclk_rckp_pass),
        .repairval_RVLD_L_pass        (m_repairval_RVLD_L_pass),

        // Connect Watchdog
        .global_error                 (m_timer_timeout_expired)
    );

    // =========================================================================
    // INSTANTIATION: MBINIT (DIE 1)
    // =========================================================================
    MBINIT #(
        .CLK_FRQ_HZ (100_000_000)
    ) u_mbinit_1 (
        .clk                          (clk_100),
        .rst_n                        (rst_n),

        .mbinit_enable                (p_enable),
        .mbinit_done                  (p_done),
        .mbinit_error                 (p_error),
        .mbinit_state_n               (p_mbinit_state_n),
        .SPMW                         (1'b0),

        .reg_phy_x8_mode_ctrl         (p_reg_phy_x8_mode_ctrl),
        .local_max_speed              (4'b0101), // 32GT/s
        .local_sbfe                   (1'b1),
        .reg_TARR_support_local_cap   (1'b1),
        .reg_L2SPD_support_local_cap  (1'b1),
        .reg_PSPT_support_local_cap   (1'b1),
        .local_so                     (1'b0),
        .reg_PMO_support_local_cap    (1'b1),
        .reg_Max_Link_Width_cap       (3'b000),  // x16 (0h)
        .reg_Max_Link_Speed_cap       (4'b0101), // 32GT/s (5h)
        .local_mtp                    (1'b1),

        .reg_Supported_TX_Vswing      (5'b00111),
        .reg_so                       (1'b0),
        .reg_mtp                      (1'b1),
        .reg_Module_ID                (2'b00),
        .reg_Clock_Phase_cap          (2'b01),
        .reg_Clock_mode_cap           (2'b01),
        .reg_TARR_support_local_ctrl  (1'b1),
        .reg_PMO_support_local_ctrl   (1'b1),
        .reg_Clock_Phase_ctrl         (1'b1),
        .reg_Clock_mode_ctrl          (1'b1),

        .reg_L2SPD_support_local_ctrl (1'b1),
        .reg_PSPT_support_local_ctrl  (1'b1),
        .reg_Target_Link_Width_ctrl   (p_reg_Target_Link_Width_ctrl),
        .reg_Target_Link_Speed_ctrl   (p_reg_Target_Link_Speed_ctrl),

        .reg_Clock_Phase_enable_status(p_reg_Clock_Phase_enable_status),
        .reg_Clock_mode_enable_status (p_reg_Clock_mode_enable_status),
        .reg_TARR_enable_status       (p_reg_TARR_enable_status),
        .reg_Link_Width_enable_status (p_reg_Link_Width_enable_status),
        .reg_Link_Speed_enable_status (p_reg_Link_Speed_enable_status),
        .reg_PMO_enable_status        (p_reg_PMO_enable_status),
        .reg_L2SPD_enable_status      (p_reg_L2SPD_enable_status),
        .reg_PSPT_enable_status       (p_reg_PSPT_enable_status),

        .local_tx_pt_en               (p_local_tx_pt_en),
        .partner_tx_pt_en             (p_partner_tx_pt_en),
        .d2c_pattern_setup            (p_d2c_pattern_setup),
        .d2c_data_pattern_sel         (p_d2c_data_pattern_sel),
        .d2c_pattern_mode             (p_d2c_pattern_mode),
        .d2c_compare_setup            (p_d2c_compare_setup),
        .d2c_perlane_pass             (p_d2c_perlane_pass_from_pt),
        .local_test_d2c_done          (p_local_test_d2c_done),
        .partner_test_d2c_done        (p_partner_test_d2c_done),

        // Connect Sideband Msg Bus (TX & RX)
        .sb_rx_valid                  (mb_rx_valid[1]),
        .sb_rx_msg_id                 (mb_rx_msg_id[1]),
        .sb_rx_MsgInfo                (mb_rx_MsgInfo[1]),
        .sb_rx_data_Field             (mb_rx_data_Field[1]),

        .sb_tx_valid                  (mbinit_tx_valid[1]),
        .sb_ltsm_rdy                  (ltsm_rdy[1]),
        .sb_tx_msg_id                 (mbinit_tx_msg_id[1]),
        .sb_tx_MsgInfo                (mbinit_tx_MsgInfo[1]),
        .sb_tx_data_Field             (mbinit_tx_data_Field[1]),

        // Training Control Signals
        .mb_tx_pattern_en             (mbinit_mb_tx_pattern_en[1]),
        .mb_tx_pattern_setup          (mb_tx_pattern_setup[1]),
        .mb_tx_data_pattern_sel       (mb_tx_data_pattern_sel[1]),
        .mb_tx_val_pattern_sel        (mb_tx_val_pattern_sel[1]),
        .mb_rx_compare_en             (mbinit_mb_rx_compare_en[1]),
        .mb_rx_compare_setup          (mb_rx_compare_setup[1]),
        .clear_error_req              (clear_error_req[1]),
        .mbinit_rx_data_lane_mask     (mbinit_rx_data_lane_mask[1]),
        .mbinit_tx_data_lane_mask     (mbinit_tx_data_lane_mask[1]),

        // Inputs
        .mb_rx_perlane_pass           (mb_rx_perlane_pass[1]),
        .mb_tx_pattern_count_done     (mb_tx_pattern_count_done[1]),
        
        .mb_lane_reversal_req         (mb_lane_reversal_req[1]),
        .repairclk_rtrk_pass          (p_repairclk_rtrk_pass),
        .repairclk_rckn_pass          (p_repairclk_rckn_pass),
        .repairclk_rckp_pass          (p_repairclk_rckp_pass),
        .repairval_RVLD_L_pass        (p_repairval_RVLD_L_pass),

        // Connect Watchdog
        .global_error                 (p_timer_timeout_expired)
    );

    // =========================================================================
    // LOCAL WATCHDOG TIMER CONTROL DRIVERS
    // =========================================================================
    always_comb begin
        m_timer_enable = m_enable && !m_done && !m_error;
    end

    state_n_e m_mbinit_state_n_prev;
    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            m_timer_rst_n         <= 1'b0;
            m_mbinit_state_n_prev <= LOG_RESET;
        end else begin
            m_timer_rst_n         <= 1'b1;
            m_mbinit_state_n_prev <= m_mbinit_state_n;
            if (m_mbinit_state_n != m_mbinit_state_n_prev) begin
                m_timer_rst_n     <= 1'b0;
            end
        end
    end

    always_comb begin
        p_timer_enable = p_enable && !p_done && !p_error;
    end

    state_n_e p_mbinit_state_n_prev;
    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            p_timer_rst_n         <= 1'b0;
            p_mbinit_state_n_prev <= LOG_RESET;
        end else begin
            p_timer_rst_n         <= 1'b1;
            p_mbinit_state_n_prev <= p_mbinit_state_n;
            if (p_mbinit_state_n != p_mbinit_state_n_prev) begin
                p_timer_rst_n     <= 1'b0;
            end
        end
    end

    // =========================================================================
    // INSTANTIATION: TIMEOUT_COUNTER (WATCHDOG - DIE 0)
    // =========================================================================
    timeout_counter #(
        .CLK_FRQ_HZ (100_000_000), // 100 MHz
        .TIME_OUT   (8)           // 8 ms (realistic watchdog budget)
    ) u_timeout_counter_0 (
        .clk             (clk_100),
        .timeout_rst_n   (m_timer_rst_n),
        .enable_timeout  (m_timer_enable),
        .timeout_expired (m_timer_timeout_expired)
    );

    // =========================================================================
    // INSTANTIATION: TIMEOUT_COUNTER (WATCHDOG - DIE 1)
    // =========================================================================
    timeout_counter #(
        .CLK_FRQ_HZ (100_000_000), // 100 MHz
        .TIME_OUT   (8)           // 8 ms (realistic watchdog budget)
    ) u_timeout_counter_1 (
        .clk             (clk_100),
        .timeout_rst_n   (p_timer_rst_n),
        .enable_timeout  (p_timer_enable),
        .timeout_expired (p_timer_timeout_expired)
    );

    // =========================================================================
    // INSTANTIATION: D2C POINT TEST TOP WRAPPER (DIE 0)
    // =========================================================================
    wrapper_D2C_PT_top u_d2c_top_0 (
        .lclk                           (clk_100),
        .rst_n                          (rst_n),
        .mb_rx_data_lane_mask           (mbinit_rx_data_lane_mask[0]),
        .local_test_d2c_done            (m_local_test_d2c_done),
        .partner_test_d2c_done          (m_partner_test_d2c_done),
        .d2c_perlane_pass               (m_d2c_perlane_pass_from_pt),
        .d2c_aggr_pass                  (),
        .d2c_val_pass                   (),
        .mbinit_local_tx_pt_en          (m_local_tx_pt_en),
        .mbinit_partner_tx_pt_en        (m_partner_tx_pt_en),
        .mbinit_d2c_clk_sampling        (2'b00),
        .mbinit_d2c_pattern_setup       (m_d2c_pattern_setup),
        .mbinit_d2c_data_pattern_sel    (m_d2c_data_pattern_sel),
        .mbinit_d2c_val_pattern_sel     (1'b0),
        .mbinit_d2c_pattern_mode        (m_d2c_pattern_mode),
        .mbinit_d2c_burst_count         (16'd2048),
        .mbinit_d2c_idle_count          (16'd0),
        .mbinit_d2c_iter_count          (16'd1),
        .mbinit_d2c_compare_setup       (m_d2c_compare_setup),
        .mbtrain_local_tx_pt_en         (1'b0),
        .mbtrain_partner_tx_pt_en       (1'b0),
        .mbtrain_local_rx_pt_en         (1'b0),
        .mbtrain_partner_rx_pt_en       (1'b0),
        .mbtrain_d2c_clk_sampling       (2'b00),
        .mbtrain_d2c_pattern_setup      (3'b000),
        .mbtrain_d2c_data_pattern_sel   (2'b00),
        .mbtrain_d2c_val_pattern_sel    (1'b0),
        .mbtrain_d2c_pattern_mode       (1'b0),
        .mbtrain_d2c_burst_count        (16'd0),
        .mbtrain_d2c_idle_count         (16'd0),
        .mbtrain_d2c_iter_count         (16'd0),
        .mbtrain_d2c_compare_setup      (2'b00),
        .cfg_max_err_thresh_perlane     (12'd0),
        .cfg_max_err_thresh_aggr        (16'd0),
        .mb_tx_trk_lane_sel             (),
        .mb_tx_clk_lane_sel             (),
        .mb_tx_val_lane_sel             (),
        .mb_tx_data_lane_sel            (),
        .mb_rx_trk_lane_sel             (),
        .mb_rx_clk_lane_sel             (),
        .mb_rx_val_lane_sel             (),
        .mb_rx_data_lane_sel            (),
        .mb_tx_pattern_en               (u_d2c_top_0_mb_tx_pattern_en),
        .mb_tx_pattern_setup            (),
        .mb_rx_pattern_setup            (),
        .mb_tx_lfsr_en                  (),
        .mb_tx_lfsr_rst                 (),
        .mb_rx_lfsr_en                  (),
        .mb_rx_lfsr_rst                 (),
        .mb_rx_iter_count               (),
        .mb_rx_idle_count               (),
        .mb_rx_burst_count              (),
        .mb_rx_pattern_mode             (),
        .mb_rx_val_pattern_sel          (),
        .mb_rx_data_pattern_sel         (),
        .mb_rx_compare_en               (u_d2c_top_0_mb_rx_compare_en),
        .mb_rx_compare_setup            (),
        .mb_rx_max_err_thresh_perlane   (),
        .mb_rx_max_err_thresh_aggr      (),
        .mb_tx_clk_sampling_en          (),
        .mb_tx_clk_sampling             (),
        .mb_tx_pattern_mode             (),
        .mb_tx_burst_count              (),
        .mb_tx_idle_count               (),
        .mb_tx_iter_count               (),
        .mb_tx_data_pattern_sel         (),
        .mb_tx_val_pattern_sel          (),
        .mb_tx_pattern_count_done       (mb_tx_pattern_count_done[0]),
        .mb_rx_compare_done             (mb_rx_compare_done[0]),
        .mb_rx_aggr_pass                (1'b1),
        .mb_rx_perlane_pass             (m_d2c_perlane_pass),
        .mb_rx_val_pass                 (1'b1),
        .tx_sb_msg_valid                (u_d2c_top_0_tx_sb_msg_valid),
        .tx_sb_msg                      (u_d2c_top_0_tx_sb_msg),
        .tx_msginfo                     (u_d2c_top_0_tx_msginfo),
        .tx_data_field                  (u_d2c_top_0_tx_data_field),
        .rx_sb_msg_valid                (mb_rx_valid[0]),
        .rx_sb_msg                      (m_rx_msg_id_casted),
        .rx_msginfo                     (mb_rx_MsgInfo[0]),
        .rx_data_field                  (mb_rx_data_Field[0])
    );

    // =========================================================================
    // INSTANTIATION: D2C POINT TEST TOP WRAPPER (DIE 1)
    // =========================================================================
    wrapper_D2C_PT_top u_d2c_top_1 (
        .lclk                           (clk_100),
        .rst_n                          (rst_n),
        .mb_rx_data_lane_mask           (mbinit_rx_data_lane_mask[1]),
        .local_test_d2c_done            (p_local_test_d2c_done),
        .partner_test_d2c_done          (p_partner_test_d2c_done),
        .d2c_perlane_pass               (p_d2c_perlane_pass_from_pt),
        .d2c_aggr_pass                  (),
        .d2c_val_pass                   (),
        .mbinit_local_tx_pt_en          (p_local_tx_pt_en),
        .mbinit_partner_tx_pt_en        (p_partner_tx_pt_en),
        .mbinit_d2c_clk_sampling        (2'b00),
        .mbinit_d2c_pattern_setup       (p_d2c_pattern_setup),
        .mbinit_d2c_data_pattern_sel    (p_d2c_data_pattern_sel),
        .mbinit_d2c_val_pattern_sel     (1'b0),
        .mbinit_d2c_pattern_mode        (p_d2c_pattern_mode),
        .mbinit_d2c_burst_count         (16'd2048),
        .mbinit_d2c_idle_count          (16'd0),
        .mbinit_d2c_iter_count          (16'd1),
        .mbinit_d2c_compare_setup       (p_d2c_compare_setup),
        .mbtrain_local_tx_pt_en         (1'b0),
        .mbtrain_partner_tx_pt_en       (1'b0),
        .mbtrain_local_rx_pt_en         (1'b0),
        .mbtrain_partner_rx_pt_en       (1'b0),
        .mbtrain_d2c_clk_sampling       (2'b00),
        .mbtrain_d2c_pattern_setup      (3'b000),
        .mbtrain_d2c_data_pattern_sel   (2'b00),
        .mbtrain_d2c_val_pattern_sel    (1'b0),
        .mbtrain_d2c_pattern_mode       (1'b0),
        .mbtrain_d2c_burst_count        (16'd0),
        .mbtrain_d2c_idle_count         (16'd0),
        .mbtrain_d2c_iter_count         (16'd0),
        .mbtrain_d2c_compare_setup      (2'b00),
        .cfg_max_err_thresh_perlane     (12'd0),
        .cfg_max_err_thresh_aggr        (16'd0),
        .mb_tx_trk_lane_sel             (),
        .mb_tx_clk_lane_sel             (),
        .mb_tx_val_lane_sel             (),
        .mb_tx_data_lane_sel            (),
        .mb_rx_trk_lane_sel             (),
        .mb_rx_clk_lane_sel             (),
        .mb_rx_val_lane_sel             (),
        .mb_rx_data_lane_sel            (),
        .mb_tx_pattern_en               (u_d2c_top_1_mb_tx_pattern_en),
        .mb_tx_pattern_setup            (),
        .mb_rx_pattern_setup            (),
        .mb_tx_lfsr_en                  (),
        .mb_tx_lfsr_rst                 (),
        .mb_rx_lfsr_en                  (),
        .mb_rx_lfsr_rst                 (),
        .mb_rx_iter_count               (),
        .mb_rx_idle_count               (),
        .mb_rx_burst_count              (),
        .mb_rx_pattern_mode             (),
        .mb_rx_val_pattern_sel          (),
        .mb_rx_data_pattern_sel         (),
        .mb_rx_compare_en               (u_d2c_top_1_mb_rx_compare_en),
        .mb_rx_compare_setup            (),
        .mb_rx_max_err_thresh_perlane   (),
        .mb_rx_max_err_thresh_aggr      (),
        .mb_tx_clk_sampling_en          (),
        .mb_tx_clk_sampling             (),
        .mb_tx_pattern_mode             (),
        .mb_tx_burst_count              (),
        .mb_tx_idle_count               (),
        .mb_tx_iter_count               (),
        .mb_tx_data_pattern_sel         (),
        .mb_tx_val_pattern_sel          (),
        .mb_tx_pattern_count_done       (mb_tx_pattern_count_done[1]),
        .mb_rx_compare_done             (mb_rx_compare_done[1]),
        .mb_rx_aggr_pass                (1'b1),
        .mb_rx_perlane_pass             (p_d2c_perlane_pass),
        .mb_rx_val_pass                 (1'b1),
        .tx_sb_msg_valid                (u_d2c_top_1_tx_sb_msg_valid),
        .tx_sb_msg                      (u_d2c_top_1_tx_sb_msg),
        .tx_msginfo                     (u_d2c_top_1_tx_msginfo),
        .tx_data_field                  (u_d2c_top_1_tx_data_field),
        .rx_sb_msg_valid                (mb_rx_valid[1]),
        .rx_sb_msg                      (p_rx_msg_id_casted),
        .rx_msginfo                     (mb_rx_MsgInfo[1]),
        .rx_data_field                  (mb_rx_data_Field[1])
    );

    // =========================================================================
    // PATTERN DONE AUTOMATION (REPAIRCLK, REPAIRVAL, REVERSALMB)
    // =========================================================================
    // Automatically trigger count done after pattern transmission is enabled
    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            mb_tx_pattern_count_done[0] <= 1'b0;
            m_pattern_done              <= 1'b0;
        end else if (mb_tx_pattern_en[0] && !m_pattern_done) begin
            repeat(20) @(posedge clk_100); // Wait for pattern transmission duration
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
            repeat(20) @(posedge clk_100); // Wait for pattern transmission duration
            mb_tx_pattern_count_done[1] <= 1'b1;
            p_pattern_done              <= 1'b1;
            @(posedge clk_100);
            mb_tx_pattern_count_done[1] <= 1'b0;
        end else if (!mb_tx_pattern_en[1]) begin
            p_pattern_done              <= 1'b0;
        end
    end

    // =========================================================================
    // STATE TRANSITION LOGGER
    // =========================================================================
    always @(m_mbinit_state_n) begin
        $display("T=%0t | [DIE 0 mbinit_state_n] %s", $time, m_mbinit_state_n.name());
    end

    always @(p_mbinit_state_n) begin
        $display("T=%0t | [DIE 1 mbinit_state_n] %s", $time, p_mbinit_state_n.name());
    end

    // =========================================================================
    // SYSTEM RESET & HELPER TASKS
    // =========================================================================
    task reset_system();
        $display("T=%0t | [RESET] Starting System Reset...", $time);
        rst_n    = 1'b0;
        m_enable = 1'b0;
        p_enable = 1'b0;

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

        m_d2c_perlane_pass    = 16'hFFFF;
        p_d2c_perlane_pass    = 16'hFFFF;

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
        $display("  STARTING MBINIT & SIDEBAND TOP REAL-TIME INTEGRATION SIMULATION ");
        $display("==================================================================\n");

        // ---------------------------------------------------------------------
        // SCENARIO 1: HAPPY PATH Loopback Training
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCENARIO 1] Starting Happy Path loopback training...", $time);
        reset_system();
        block_sideband = 1'b0;

        $display("T=%0t | [TEST - SCENARIO 1] Enabling MBINIT on both dies concurrently...", $time);
        @(posedge clk_100);
        m_enable = 1'b1;
        p_enable = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                 $display("\n==================================================================");
                 $display("T=%0t | [SUCCESS - SCENARIO 1] Real-time loopback training completed successfully!", $time);
                 $display("            Module final Tx mask = %b, Rx mask = %b", u_mbinit_0.mbinit_tx_data_lane_mask, u_mbinit_0.mbinit_rx_data_lane_mask);
                 $display("            Partner final Tx mask = %b, Rx mask = %b", u_mbinit_1.mbinit_tx_data_lane_mask, u_mbinit_1.mbinit_rx_data_lane_mask);
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
                #8_500_000; // 8.5ms simulation timeout safety budget
                $error("T=%0t | [TIMEOUT - SCENARIO 1] Watchdog expired or simulation hung!", $time);
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

        $display("T=%0t | [TEST - SCENARIO 2] Enabling MBINIT on both dies with BLOCKED sideband...", $time);
        @(posedge clk_100);
        m_enable = 1'b1;
        p_enable = 1'b1;

        fork
            begin
                // Wait for watchdog to trigger errors
                wait (m_error && p_error);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 2] Watchdog timer successfully expired!", $time);
                $display("            m_timer_timeout_expired = %b, m_error = %b", m_timer_timeout_expired, m_error);
                $display("            p_timer_timeout_expired = %b, p_error = %b", p_timer_timeout_expired, p_error);
                $display("==================================================================\n");
            end
            begin
                wait (m_done || p_done);
                $error("T=%0t | [FAILURE - SCENARIO 2] MBINIT reported done but sideband was blocked!", $time);
                $finish;
            end
            begin
                #9_000_000; // 9ms simulation timeout safety budget
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

        $display("T=%0t | [TEST - SCENARIO 3] Enabling MBINIT with asymmetric width targets...", $time);
        @(posedge clk_100);
        m_enable = 1'b1;
        p_enable = 1'b1;

        fork
            begin
                wait (m_done && p_done);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 3] Successfully negotiated and completed at x8 width!", $time);
                $display("            Module final Tx mask = %b, Rx mask = %b", u_mbinit_0.mbinit_tx_data_lane_mask, u_mbinit_0.mbinit_rx_data_lane_mask);
                $display("            Partner final Tx mask = %b, Rx mask = %b", u_mbinit_1.mbinit_tx_data_lane_mask, u_mbinit_1.mbinit_rx_data_lane_mask);
                $display("            Module negotiated Link Width = 4'h%h, Speed = 4'h%h", m_reg_Link_Width_enable_status, m_reg_Link_Speed_enable_status);
                $display("            Partner negotiated Link Width = 4'h%h, Speed = 4'h%h", p_reg_Link_Width_enable_status, p_reg_Link_Speed_enable_status);
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
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCENARIO 3] Watchdog expired!", $time);
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

        // Force clock lane failure on Master
        m_repairclk_rckp_pass = 1'b0;

        $display("T=%0t | [TEST - SCENARIO 4] Enabling MBINIT with forced clock failure on Master...", $time);
        @(posedge clk_100);
        m_enable = 1'b1;
        p_enable = 1'b1;

        fork
            begin
                wait (m_error && p_error);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 4] Clock lane failure detected and errored out correctly!", $time);
                $display("            m_error = %b, p_error = %b", m_error, p_error);
                $display("==================================================================\n");
            end
            begin
                wait (m_done || p_done);
                $error("T=%0t | [FAILURE - SCENARIO 4] MBINIT reported done despite clock lane failure!", $time);
                $finish;
            end
            begin
                #8_500_000;
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

        // Force valid lane failure on Partner
        p_repairval_RVLD_L_pass = 1'b0;

        $display("T=%0t | [TEST - SCENARIO 5] Enabling MBINIT with forced valid failure on Partner...", $time);
        @(posedge clk_100);
        m_enable = 1'b1;
        p_enable = 1'b1;

        fork
            begin
                wait (m_error && p_error);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 5] Valid lane failure detected and errored out correctly!", $time);
                $display("            m_error = %b, p_error = %b", m_error, p_error);
                $display("==================================================================\n");
            end
            begin
                wait (m_done || p_done);
                $error("T=%0t | [FAILURE - SCENARIO 5] MBINIT reported done despite valid lane failure!", $time);
                $finish;
            end
            begin
                #8_500_000;
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

        $display("T=%0t | [TEST - SCENARIO 6] Enabling MBINIT to trigger lane reversal...", $time);
        @(posedge clk_100);
        m_enable = 1'b1;
        p_enable = 1'b1;

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
                #5_000_000;
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
                $display("            Module final Tx mask = %b, Rx mask = %b", u_mbinit_0.mbinit_tx_data_lane_mask, u_mbinit_0.mbinit_rx_data_lane_mask);
                $display("            Partner final Tx mask = %b, Rx mask = %b", u_mbinit_1.mbinit_tx_data_lane_mask, u_mbinit_1.mbinit_rx_data_lane_mask);
                $display("==================================================================\n");
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCENARIO 6] Training errored out after reversal retry!", $time);
                $finish;
            end
            begin
                #8_500_000;
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

        // S2 Point Test 1: PASS lower 8 lanes, FAIL upper 8 lanes (causes degrade to lower x8)
        m_d2c_perlane_pass = 16'h00FF;
        p_d2c_perlane_pass = 16'h00FF;

        $display("T=%0t | [TEST - SCENARIO 7] Enabling MBINIT to trigger first degradation...", $time);
        @(posedge clk_100);
        m_enable = 1'b1;
        p_enable = 1'b1;

        // Wait until they enter point test S2 of REPAIRMB
        wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        
        // Wait for retry start (when current_state goes back to point test S2 on retry)
        wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state != u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        $display("T=%0t | [TEST - SCENARIO 7] Retry detected! Injecting complete data lane failure...", $time);

        // Retry Point Test: Fail completely (all 0) -> no further degrade possible
        m_d2c_perlane_pass = 16'h0000;
        p_d2c_perlane_pass = 16'h0000;

        fork
            begin
                wait (m_error && p_error);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCENARIO 7] Double failure correctly errored out!", $time);
                $display("            m_error = %b, p_error = %b", m_error, p_error);
                $display("==================================================================\n");
            end
            begin
                wait (m_done || p_done);
                $error("T=%0t | [FAILURE - SCENARIO 7] MBINIT reported done despite double failure!", $time);
                $finish;
            end
            begin
                #8_500_000;
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
        // Module has lanes 0:3 passing (16'h000F)
        // Partner has lanes 4:15 passing (16'hFFF0)
        m_d2c_perlane_pass = 16'h000F;
        p_d2c_perlane_pass = 16'hFFF0;

        $display("T=%0t | [TEST - SCENARIO 8] Enabling MBINIT with asymmetric width and lane maps...", $time);
        @(posedge clk_100);
        m_enable = 1'b1;
        p_enable = 1'b1;

        // Wait until they enter point test S2 of REPAIRMB for the first time
        wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        
        // Wait for retry start (when current_state goes back to point test S2 on retry)
        fork
            begin
                wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state != u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCENARIO 8] Retry detected! Injecting passing lanes for retry point test...", $time);
                
                // For the retry, we make all lanes pass (which guarantees that the negotiated lanes pass)
                m_d2c_perlane_pass = 16'hFFFF;
                p_d2c_perlane_pass = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCENARIO 8] Training errored out before retry!", $time);
                $finish;
            end
            begin
                #5_000_000;
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
                $display("            Module final Tx mask = %b, Rx mask = %b (Expected: Tx = 100, Rx = 101)", u_mbinit_0.mbinit_tx_data_lane_mask, u_mbinit_0.mbinit_rx_data_lane_mask);
                $display("            Partner final Tx mask = %b, Rx mask = %b (Expected: Tx = 101, Rx = 100)", u_mbinit_1.mbinit_tx_data_lane_mask, u_mbinit_1.mbinit_rx_data_lane_mask);
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
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCENARIO 8] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCENARIO 9: DYNAMIC CAPABILITY & FORCE X8 CONTROL NEGOTIATION TESTS
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCENARIO 9] Starting Dynamic Capability Sweep & Force x8 overrides...", $time);
        $display("==================================================================\n");

        // ---------------------------------------------------------------------
        // SCN 9A: Forced x8 on Die 0 only
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCN 9A] Force x8 on Die 0 only...", $time);
        reset_system();
        block_sideband = 1'b0;

        m_reg_phy_x8_mode_ctrl = 1'b1; // Force x8 on Die 0
        p_reg_phy_x8_mode_ctrl = 1'b0; // Default on Die 1

        m_reg_Target_Link_Width_ctrl = 4'h2; // Wants x16
        p_reg_Target_Link_Width_ctrl = 4'h2; // Wants x16

        m_enable = 1'b1;
        p_enable = 1'b1;

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
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCN 9A] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCN 9B: Forced x8 on Die 1 only
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCN 9B] Force x8 on Die 1 only...", $time);
        reset_system();
        block_sideband = 1'b0;

        m_reg_phy_x8_mode_ctrl = 1'b0; // Default on Die 0
        p_reg_phy_x8_mode_ctrl = 1'b1; // Force x8 on Die 1

        m_enable = 1'b1;
        p_enable = 1'b1;

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
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCN 9B] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCN 9C: Forced x8 on Both dies
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCN 9C] Force x8 on both dies...", $time);
        reset_system();
        block_sideband = 1'b0;

        m_reg_phy_x8_mode_ctrl = 1'b1; // Force x8 on Die 0
        p_reg_phy_x8_mode_ctrl = 1'b1; // Force x8 on Die 1

        m_enable = 1'b1;
        p_enable = 1'b1;

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
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCN 9C] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCN 9D: Target Link Width Mismatch (Die 0 target = x16, Die 1 target = x8)
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCN 9D] Target Link Width Mismatch (x16 vs x8)...", $time);
        reset_system();
        block_sideband = 1'b0;

        m_reg_Target_Link_Width_ctrl = 4'h2; // Wants x16
        p_reg_Target_Link_Width_ctrl = 4'h1; // Wants x8

        m_enable = 1'b1;
        p_enable = 1'b1;

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
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCN 9D] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCN 9E: Target Link Speed Mismatch (Die 0 target = 32 GT/s, Die 1 target = 16 GT/s)
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCN 9E] Target Link Speed Mismatch (32 GT/s vs 16 GT/s)...", $time);
        reset_system();
        block_sideband = 1'b0;

        m_reg_Target_Link_Speed_ctrl = 4'h5; // Wants 32 GT/s (5h)
        p_reg_Target_Link_Speed_ctrl = 4'h3; // Wants 16 GT/s (3h)

        m_enable = 1'b1;
        p_enable = 1'b1;

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
                $error("T=%0t | [FAILURE - SCN 9E] Training failed!", $time);
                $finish;
            end
            begin
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCN 9E] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCN 9F-1: x16 with 1-Lane Failure (Degrade to upper x8)
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCN 9F-1] x16 capability with forced 1-lane failure on lane 7 (lower x8 fail -> degrade to upper x8)...", $time);
        reset_system();
        block_sideband = 1'b0;

        // Point Test inputs for Run 1:
        // Local has lane 7 failed (16'hFF7F)
        // Partner has lane 7 failed (16'hFF7F)
        m_d2c_perlane_pass = 16'hFF7F;
        p_d2c_perlane_pass = 16'hFF7F;

        m_enable = 1'b1;
        p_enable = 1'b1;

        // Wait until they enter point test S2 of REPAIRMB for the first time
        wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        
        fork
            begin
                // Wait for retry point test S2
                wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state != u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCN 9F-1] Retry detected! Setting passing lanes for retry point test...", $time);
                // Make retry pass for upper x8 operational width
                m_d2c_perlane_pass = 16'hFFFF;
                p_d2c_perlane_pass = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9F-1] Training errored out before retry!", $time);
                $finish;
            end
            begin
                #5_000_000;
                $error("T=%0t | [TIMEOUT - SCN 9F-1] Retry not detected in time!", $time);
                $finish;
            end
        join_any
        disable fork;

        // Wait for successful completion
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9F-1] Completed successfully!", $time);
                $display("            Module final Tx mask = %b, Rx mask = %b (Expected: 010 - upper x8)", u_mbinit_0.mbinit_tx_data_lane_mask, u_mbinit_0.mbinit_rx_data_lane_mask);
                if (u_mbinit_0.mbinit_tx_data_lane_mask !== 3'b010) begin
                    $error("T=%0t | [FAILURE - SCN 9F-1] Expected upper x8 mask (3'b010)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9F-1] Training errored out after retry!", $time);
                $finish;
            end
            begin
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCN 9F-1] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCN 9F-2: Forced x8 with 1-Lane Failure (Degrade to lower x4)
        // ---------------------------------------------------------------------
        $display("T=%0t | [TEST - SCN 9F-2] Forced x8 with 1-lane failure on lane 5 (lower x8 fail -> degrade to lower x4)...", $time);
        reset_system();
        block_sideband = 1'b0;

        m_reg_phy_x8_mode_ctrl = 1'b1; // Force x8

        // Point Test inputs for Run 1:
        // Local has lane 5 and lane 12 failed (16'hEFDF)
        // Partner has lane 5 and lane 12 failed (16'hEFDF)
        m_d2c_perlane_pass = 16'hEFDF;
        p_d2c_perlane_pass = 16'hEFDF;

        m_enable = 1'b1;
        p_enable = 1'b1;

        // Wait until they enter point test S2 of REPAIRMB for the first time
        wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        
        fork
            begin
                // Wait for retry point test S2
                wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state != u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCN 9F-2] Retry detected! Setting passing lanes for retry point test...", $time);
                // Make retry pass for lower x4 operational width
                m_d2c_perlane_pass = 16'hFFFF;
                p_d2c_perlane_pass = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9F-2] Training errored out before retry!", $time);
                $finish;
            end
            begin
                #5_000_000;
                $error("T=%0t | [TIMEOUT - SCN 9F-2] Retry not detected in time!", $time);
                $finish;
            end
        join_any
        disable fork;

        // Wait for successful completion
        fork
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SUCCESS - SCN 9F-2] Completed successfully!", $time);
                $display("            Module final Tx mask = %b, Rx mask = %b (Expected: 100 - lower x4)", u_mbinit_0.mbinit_tx_data_lane_mask, u_mbinit_0.mbinit_rx_data_lane_mask);
                if (u_mbinit_0.mbinit_tx_data_lane_mask !== 3'b100) begin
                    $error("T=%0t | [FAILURE - SCN 9F-2] Expected lower x4 mask (3'b100)!", $time);
                    $finish;
                end
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9F-2] Training errored out after retry!", $time);
                $finish;
            end
            begin
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCN 9F-2] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // SCN 9F-3: Asymmetric Lane Degradation (Master lower x8 fail -> upper x8; Partner x16 -> lower x8)
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("T=%0t | [TEST - SCN 9F-3] Starting Asymmetric Lane Degradation (Master lower x8 fail -> upper x8; Partner x16 -> lower x8)...", $time);
        $display("==================================================================\n");
        reset_system();
        block_sideband = 1'b0;

        // Negotiate x16 in PARAM (default)
        m_reg_Target_Link_Width_ctrl = 4'h2;
        p_reg_Target_Link_Width_ctrl = 4'h2;

        // Point Test inputs for Run 1:
        // Master (local) has all passing (16'hFFFF)
        // Partner (remote) has lane 5 failed in lower 8 lanes (16'hFFDF)
        m_d2c_perlane_pass = 16'hFFFF;
        p_d2c_perlane_pass = 16'hFFDF;

        m_enable = 1'b1;
        p_enable = 1'b1;

        // Wait until they enter point test S2 of REPAIRMB for the first time
        wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
        
        fork
            begin
                // Wait for retry point test S2
                wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state != u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                wait (u_mbinit_0.u_mbinit_wrapper.u_repairmb.current_state == u_mbinit_0.u_mbinit_wrapper.u_repairmb.MB_S2_D2C_POINT_TEST);
                $display("T=%0t | [TEST - SCN 9F-3] Retry detected! Setting passing lanes for retry point test (Master=16'hFFFF, Partner=16'hFFFF)...", $time);
                m_d2c_perlane_pass = 16'hFFFF;
                p_d2c_perlane_pass = 16'hFFFF;
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9F-3] Training errored out before retry!", $time);
                $finish;
            end
            begin
                #5_000_000;
                $error("T=%0t | [TIMEOUT - SCN 9F-3] Retry not detected in time!", $time);
                $finish;
            end
        join_any
        disable fork;

        // Wait for successful completion
        fork
            begin
                wait (m_done && p_done);
                $display("\n==================================================================");
                $display("T=%0t | [SUCCESS - SCN 9F-3] Asymmetric Lane Degradation completed successfully!", $time);
                $display("            Module final Tx mask = %b, Rx mask = %b (Expected: Tx = 010 - upper x8, Rx = 001 - lower x8)", u_mbinit_0.mbinit_tx_data_lane_mask, u_mbinit_0.mbinit_rx_data_lane_mask);
                $display("            Partner final Tx mask = %b, Rx mask = %b (Expected: Tx = 001 - lower x8, Rx = 010 - upper x8)", u_mbinit_1.mbinit_tx_data_lane_mask, u_mbinit_1.mbinit_rx_data_lane_mask);
                $display("T=%0t | [SUCCESS - SCN 9F-3] Completed. Negotiated Width: m=%0h, p=%0h (Expected: 1)", $time, m_reg_Link_Width_enable_status, p_reg_Link_Width_enable_status);
                
                // Assertions to verify correct asymmetric x8 mask
                if (u_mbinit_0.mbinit_tx_data_lane_mask !== 3'b010 || u_mbinit_0.mbinit_rx_data_lane_mask !== 3'b001) begin
                    $error("T=%0t | [FAILURE - SCN 9F-3] Expected Master Tx mask 3'b010 and Rx mask 3'b001!", $time);
                    $finish;
                end
                if (u_mbinit_1.mbinit_tx_data_lane_mask !== 3'b001 || u_mbinit_1.mbinit_rx_data_lane_mask !== 3'b010) begin
                    $error("T=%0t | [FAILURE - SCN 9F-3] Expected Partner Tx mask 3'b001 and Rx mask 3'b010!", $time);
                    $finish;
                end
                $display("==================================================================\n");
            end
            begin
                wait (m_error || p_error);
                $error("T=%0t | [FAILURE - SCN 9F-3] Training errored out after retry!", $time);
                $finish;
            end
            begin
                #8_500_000;
                $error("T=%0t | [TIMEOUT - SCN 9F-3] Watchdog expired!", $time);
                $finish;
            end
        join_any
        disable fork;


        $display("\n==================================================================");
        $display("T=%0t | [ALL INTEGRATION SCENARIOS PASSED SUCCESSFULLY]", $time);
        $display("==================================================================\n");
        $finish;
    end

    // =========================================================================
    // WAVEFORM DUMPING
    // =========================================================================
    initial begin
        $dumpfile("MBINIT_D2C_SideBand_Integration_tb.vcd");
        $dumpvars(0, MBINIT_D2C_SideBand_tb);
    end

endmodule
