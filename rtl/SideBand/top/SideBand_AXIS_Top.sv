// =============================================================================
// Module      : SideBand_AXIS_Top
// Description : Top-level wrapper for UCIe Sideband with AXI-Stream Interfaces.
//               Integrates SideBand_Top with axis_slave_to_sb_cfg (TX) and
//               axis_master_from_sb_cfg (RX) bridges.
// =============================================================================

import sb_pkg::*;
import UCIe_pkg::*;

`timescale 1ns/1ps
module SideBand_AXIS_Top #(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32,
    parameter SB_TX_DN_CRD_INIT = 32,
    parameter SB_RX_FIFO_DEPTH  = 16
)(
    // =========================================================================
    // System Clock and Reset
    // =========================================================================
    input  logic         clk_main,
    input  logic         clk_ltsm,
    input  logic         rst_main_n,
    output logic         clk_sb,       // 100 MHz derived from sb_pll (÷8); fed to Reg_File
    input  logic         rst_sb_n,

    // =========================================================================
    // PHY Status & Control
    // =========================================================================
    input  logic         phy_in_reset,
    input  logic         pmo_en,

    // =========================================================================
    // External Sideband Serial Interface
    // =========================================================================
    input  logic         RXCKSB,       // Clock from remote serializer
    output logic         TXCKSB,       // Clock forwarded to remote deserializer
    output logic         TXDATASB,
    input  logic         RXDATASB,

    // =========================================================================
    // Link Controller: Pattern Generation / Detection
    // =========================================================================
    input  logic         pattern_mode,
    input  logic         start_pat_req,
    input  logic [2:0]   req_iter_count,
    output logic         iter_done,
    output logic         det_pat_rcvd,

    // =========================================================================
    // Main Band / Main Controller Interface
    // =========================================================================
    // -- RDI SM Traffic Control
    output logic         traffic_req,
    input  logic         traffic_rdy,

    // -- RDI SM TX Interface (From Main Controller)
    input  logic [ 7:0]  RDI_msg_no_send,
    input  logic         stall_send,
    input  logic         RDI_vld_send,
    output logic         RDI_rdy,

    // -- LTSM TX Interface (From Main Controller)
    input  logic [ 7:0]  ltsm_msg_n_send,
    input  logic [63:0]  msg_data_send,
    input  logic [15:0]  msg_info_send,
    input  logic         ltsm_vld_send,
    output logic         ltsm_rdy,

    // -- RDI SM RX Interface (To Main Controller)
    output logic         RDI_vld_rcvd,
    output logic [ 7:0]  RDI_msg_no_rcvd,
    output logic         stall_rcvd,

    // -- LTSM RX Interface (To Main Controller)
    output logic         ltsm_vld_rcvd,
    output logic [ 7:0]  ltsm_msg_no_rcvd,
    output logic [63:0]  msg_data_rcvd,
    output logic [15:0]  msg_info_rcvd,

    // =========================================================================
    // AXI-Stream SideBand TX Interface (Slave)
    // =========================================================================
    input  logic [31:0]  s_axis_sb_tx_tdata,
    input  logic [3:0]   s_axis_sb_tx_tkeep,
    input  logic         s_axis_sb_tx_tlast,
    input  logic         s_axis_sb_tx_tvalid,
    output logic         s_axis_sb_tx_tready,

    // =========================================================================
    // AXI-Stream SideBand RX Interface (Master)
    // =========================================================================
    output logic [31:0]  m_axis_sb_rx_tdata,
    output logic [3:0]   m_axis_sb_rx_tkeep,
    output logic         m_axis_sb_rx_tlast,
    output logic         m_axis_sb_rx_tvalid,
    input  logic         m_axis_sb_rx_tready,
    output logic         o_sb_rx_overflow,

    // =========================================================================
    // Register File Interface (Reg_Access)
    // =========================================================================
    output logic [24:0]  rf_addr,
    output logic [7:0]   rf_be,
    output logic         rf_is_64b_access,
    output logic [63:0]  rf_wdata,
    output logic         rd_en,
    output logic         wr_en,
    input  logic [63:0]  rf_rdata,
    input  logic         rdata_vld,
    input  logic         addr_err_o
);

    // =========================================================================
    // Intermediate nets for connecting the core with AXI bridges
    // =========================================================================
    logic [31:0] lp_cfg;
    logic        lp_cfg_vld;
    logic        pl_cfg_crd;
    logic        lp_cfg_crd;
    logic [31:0] pl_cfg;
    logic        pl_cfg_vld;

    // =========================================================================
    // Sideband core clock reference for bridges
    // =========================================================================
    wire clk_sb_int;
    assign clk_sb = clk_sb_int;

    // =========================================================================
    // SideBand TX Bridge: AXI-Stream Slave -> lp_cfg/lp_cfg_vld
    // =========================================================================
    axis_slave_to_sb_cfg #(
        .CFG_W       (32),
        .TDATA_W     (32),
        .DN_CRD_INIT (SB_TX_DN_CRD_INIT)
    ) u_sb_tx_bridge (
        .clk           (clk_sb_int),
        .rst_n         (rst_sb_n),
        .s_axis_tdata  (s_axis_sb_tx_tdata),
        .s_axis_tkeep  (s_axis_sb_tx_tkeep),
        .s_axis_tlast  (s_axis_sb_tx_tlast),
        .s_axis_tvalid (s_axis_sb_tx_tvalid),
        .s_axis_tready (s_axis_sb_tx_tready),
        .lp_cfg        (lp_cfg),
        .lp_cfg_vld    (lp_cfg_vld),
        .pl_cfg_crd    (pl_cfg_crd)
    );

    // =========================================================================
    // SideBand RX Bridge: pl_cfg/pl_cfg_vld -> AXI-Stream Master
    // =========================================================================
    axis_master_from_sb_cfg #(
        .CFG_W       (32),
        .TDATA_W     (32),
        .FIFO_DEPTH  (SB_RX_FIFO_DEPTH)
    ) u_sb_rx_bridge (
        .clk           (clk_sb_int),
        .rst_n         (rst_sb_n),
        .pl_cfg        (pl_cfg),
        .pl_cfg_vld    (pl_cfg_vld),
        .lp_cfg_crd    (lp_cfg_crd),
        .m_axis_tdata  (m_axis_sb_rx_tdata),
        .m_axis_tkeep  (m_axis_sb_rx_tkeep),
        .m_axis_tlast  (m_axis_sb_rx_tlast),
        .m_axis_tvalid (m_axis_sb_rx_tvalid),
        .m_axis_tready (m_axis_sb_rx_tready),
        .o_overflow    (o_sb_rx_overflow)
    );

    // =========================================================================
    // Instantiate SideBand_Top core
    // =========================================================================
    SideBand_Top #(
        .DATA_WIDTH (DATA_WIDTH),
        .GAP_WIDTH  (GAP_WIDTH)
    ) u_sb_top (
        .clk_main         (clk_main),
        .clk_ltsm         (clk_ltsm),
        .rst_main_n       (rst_main_n),
        .clk_sb           (clk_sb_int),
        .rst_sb_n         (rst_sb_n),
        .phy_in_reset     (phy_in_reset),
        .pmo_en           (pmo_en),
        .RXCKSB           (RXCKSB),
        .TXCKSB           (TXCKSB),
        .TXDATASB         (TXDATASB),
        .RXDATASB         (RXDATASB),
        .pattern_mode     (pattern_mode),
        .start_pat_req    (start_pat_req),
        .req_iter_count   (req_iter_count),
        .iter_done        (iter_done),
        .det_pat_rcvd     (det_pat_rcvd),
        .traffic_req      (traffic_req),
        .traffic_rdy      (traffic_rdy),
        .RDI_msg_no_send  (RDI_msg_no_send),
        .stall_send       (stall_send),
        .RDI_vld_send     (RDI_vld_send),
        .RDI_rdy          (RDI_rdy),
        .ltsm_msg_n_send  (ltsm_msg_n_send),
        .msg_data_send    (msg_data_send),
        .msg_info_send    (msg_info_send),
        .ltsm_vld_send    (ltsm_vld_send),
        .ltsm_rdy         (ltsm_rdy),
        .RDI_vld_rcvd     (RDI_vld_rcvd),
        .RDI_msg_no_rcvd  (RDI_msg_no_rcvd),
        .stall_rcvd       (stall_rcvd),
        .ltsm_vld_rcvd    (ltsm_vld_rcvd),
        .ltsm_msg_no_rcvd (ltsm_msg_no_rcvd),
        .msg_data_rcvd    (msg_data_rcvd),
        .msg_info_rcvd    (msg_info_rcvd),
        .lp_cfg           (lp_cfg),
        .lp_cfg_vld       (lp_cfg_vld),
        .pl_cfg_crd       (pl_cfg_crd),
        .lp_cfg_crd       (1'b1), // Always grant credit to bypass RDI_control credit consumption bug
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

endmodule
