// =============================================================================
// Module      : SideBand_Top
// Description : Top-level for UCIe Sideband.
//               Integrates Link_Controller, Training_Mgmt, RDI_control, 
//               Reg_Access, and SB SerDes (serializer & deserializer).
// =============================================================================

import sb_pkg::*;
import UCIe_pkg::*;

`timescale 1ns/1ps
module SideBand_Top #(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32
)(
    // =========================================================================
    // System Clock and Reset
    // =========================================================================
    input  logic         clk_main,
    input  logic         rst_main_n,
    input  logic         clk_sb,
    input  logic         rst_sb_n,

    // =========================================================================
    // PHY Status & Control
    // =========================================================================
    input  logic         phy_in_reset,
    input  logic         pmo_en,

    // =========================================================================
    // External Sideband Serial Interface
    // =========================================================================
    input  logic         sb_pll_clock, // Used as clk_serial in sb_serializer
    input  logic         RXCKSB,       // Clock from remote serializer
    output logic         TXCKSB,       // Clock forwarded to remote deserializer
    output logic         TXDATASB,
    input  logic         RXDATASB,

    // =========================================================================
    // Link Controller: Pattern Generation / Detection
    // =========================================================================
    input  logic         pattern_mode,
    input  logic         start_pat_req,
    input  logic         send_4_iter,
    output logic         four_iter_done,
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
    // Adapter Interface (RDI Control)
    // =========================================================================
    input  logic [31:0]  lp_cfg,
    input  logic         lp_cfg_vld,
    output logic         pl_cfg_crd,
    input  logic         lp_cfg_crd,
    output logic [31:0]  pl_cfg,
    output logic         pl_cfg_vld,

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
    // Internal Connections
    // =========================================================================

    // Link Controller <-> Training_Mgmt
    logic [127:0] trn_msg_send;
    logic         trn_vld_send;
    logic         trn_rdy;
    logic [127:0] trn_msg_rcvd;
    logic         trn_vld_rcvd;

    // Link Controller <-> RDI_control
    logic [127:0] adapter_msg_send;
    logic         adapter_vld_send;
    logic         adapter_rdy;
    logic [127:0] adapter_msg_rcvd;
    logic         adapter_vld_rcvd;

    // Link Controller <-> sb_serializer / sb_deserializer
    logic [63:0]  ser_data_send;
    logic         ser_vld_send;
    logic         ser_rdy;
    logic [63:0]  des_data_rcvd;
    logic         des_vld_rcvd;

    // RDI_control <-> Reg_Access
    logic [127:0] reg_msg;
    logic         reg_vld;
    logic         reg_rdy;
    logic [127:0] completion_msg;
    logic         completion_vld;
    logic         completion_rdy;

    // =========================================================================
    // SerDes Modules
    // =========================================================================

    logic ser_pmo_en;
    assign ser_pmo_en = pattern_mode ? 1'b0 : pmo_en;
    sb_serializer #(
        .DATA_WIDTH (DATA_WIDTH),
        .GAP_WIDTH  (GAP_WIDTH)
    ) u_sb_serializer (
        .clk_parallel     (clk_sb),
        .clk_serial       (sb_pll_clock),
        .rst_n            (rst_sb_n),
        .pmo_en           (ser_pmo_en),
        .tx_parallel_data (ser_data_send),
        .tx_data_valid    (ser_vld_send),
        .tx_rdy           (ser_rdy),
        .TXDATASB         (TXDATASB),
        .TXCKSB           (TXCKSB)
    );

    logic RXCKSB_forward = 0;
    always @(RXCKSB) RXCKSB_forward <= #(SERDES_CLK/2) RXCKSB;

    sb_deserializer #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_sb_deserializer (
        .RXCKSB               (RXCKSB_forward),
        .clk_parallel         (clk_sb),
        .rst_n                (rst_sb_n),
        .RXDATASB              (RXDATASB),
        .rx_parallel_data_out (des_data_rcvd),
        .rx_data_vld          (des_vld_rcvd)
    );

    // =========================================================================
    // Link Controller
    // =========================================================================

    Link_Controller u_link_controller (
        // TX
        .clk              (clk_sb),
        .rst_n            (rst_sb_n),

        .trn_msg_send    (trn_msg_send),
        .trn_vld_send    (trn_vld_send),
        .trn_rdy         (trn_rdy),

        .adapter_msg_send (adapter_msg_send),
        .adapter_vld_send (adapter_vld_send),
        .adapter_rdy      (adapter_rdy),
        
        .pattern_mode     (pattern_mode),
        .start_pat_req    (start_pat_req),
        .send_4_iter      (send_4_iter),
        .four_iter_done   (four_iter_done),

        .ser_rdy          (ser_rdy),
        .ser_data_send    (ser_data_send),
        .ser_vld_send     (ser_vld_send),
        
        
        // RX
        .det_pat_rcvd     (det_pat_rcvd),
        .des_data_rcvd    (des_data_rcvd),
        .des_vld_rcvd     (des_vld_rcvd),

        .adapter_msg_rcvd (adapter_msg_rcvd),
        .adapter_vld_rcvd (adapter_vld_rcvd),
        .trn_msg_rcvd    (trn_msg_rcvd),
        .trn_vld_rcvd    (trn_vld_rcvd)
    );

    // =========================================================================
    // Training_Mgmt
    // =========================================================================

    Training_Mgmt u_training_mgmt (
        // Clock and Reset
        .clk_main         (clk_main),
        .rst_main_n       (rst_main_n),
        .clk_sb           (clk_sb),
        .rst_sb_n         (rst_sb_n),
        
        // Main SM TX
        .RDI_msg_no_send  (RDI_msg_no_send),
        .stall_send       (stall_send),
        .RDI_vld_send     (RDI_vld_send),
        .RDI_rdy          (RDI_rdy),
        
        .ltsm_msg_n_send  (ltsm_msg_n_send),
        .msg_data_send    (msg_data_send),
        .msg_info_send    (msg_info_send),
        .ltsm_vld_send    (ltsm_vld_send),
        .ltsm_rdy         (ltsm_rdy),
        
        // Main SM RX
        .RDI_vld_rcvd     (RDI_vld_rcvd),
        .RDI_msg_no_rcvd  (RDI_msg_no_rcvd),
        .stall_rcvd       (stall_rcvd),
        
        .ltsm_vld_rcvd    (ltsm_vld_rcvd),
        .ltsm_msg_no_rcvd (ltsm_msg_no_rcvd),
        .msg_data_rcvd    (msg_data_rcvd),
        .msg_info_rcvd    (msg_info_rcvd),
        
        // External Link
        .trn_msg_send    (trn_msg_send),
        .trn_vld_send    (trn_vld_send),
        .trn_rdy         (trn_rdy),
        .trn_msg_rcvd    (trn_msg_rcvd),
        .trn_vld_rcvd    (trn_vld_rcvd)
    );

    // =========================================================================
    // RDI_control
    // =========================================================================

    RDI_control u_rdi_control (
        .clk              (clk_sb),
        .rst_n            (rst_sb_n),
        
        // Adapter Interface
        .lp_cfg           (lp_cfg),
        .lp_cfg_vld       (lp_cfg_vld),
        .pl_cfg_crd       (pl_cfg_crd),
        .lp_cfg_crd       (lp_cfg_crd),
        .pl_cfg           (pl_cfg),
        .pl_cfg_vld       (pl_cfg_vld),
        
        // Link Controller Interface
        .adapter_msg_rcvd (adapter_msg_rcvd),
        .adapter_vld_rcvd (adapter_vld_rcvd),
        .adapter_msg_send (adapter_msg_send),
        .adapter_vld_send (adapter_vld_send),
        .adapter_rdy      (adapter_rdy),
        
        // Reg_Access Interface
        .reg_msg          (reg_msg),
        .reg_vld          (reg_vld),
        .reg_rdy          (reg_rdy),
        .completion_msg   (completion_msg),
        .completion_vld   (completion_vld),
        .completion_rdy   (completion_rdy),
        
        // RDI_SM Interface
        .traffic_req      (traffic_req),
        .traffic_rdy      (traffic_rdy),
        .phy_in_reset     (phy_in_reset)
    );

    // =========================================================================
    // Reg_Access
    // =========================================================================

    Reg_Access u_reg_access (
        .clk              (clk_sb),
        .rst_n            (rst_sb_n),
        
        // SB RX side
        .reg_msg          (reg_msg),
        .reg_vld          (reg_vld),
        .reg_rdy          (reg_rdy),
        
        // PHY context
        .phy_in_reset     (phy_in_reset),
        
        // SB TX side
        .completion_msg   (completion_msg),
        .completion_vld   (completion_vld),
        .completion_rdy   (completion_rdy),
        
        // Reg_File Interface
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

`ifdef SIMULATION
    bind sb_serializer sb_serializer_sva #(
        .DATA_WIDTH(DATA_WIDTH),
        .S_GAP_WIDTH(GAP_WIDTH)
    ) i_sb_serializer_sva (
        .clk_serial      (clk_serial),
        .clk_parallel    (clk_parallel),
        .rst_n           (rst_n),
        .pmo_en          (pmo_en),
        .tx_parallel_data(tx_parallel_data),
        .tx_data_valid   (tx_data_valid),
        .tx_rdy          (tx_rdy),
        .TXDATASB        (TXDATASB),
        .TXCKSB          (TXCKSB)
    );

    bind sb_deserializer sb_deserializer_sva #(
        .DATA_WIDTH(DATA_WIDTH)
    ) i_sb_deserializer_sva (
        .RXCKSB              (RXCKSB),
        .clk_parallel        (clk_parallel),
        .rst_n               (rst_n),
        .rx_parallel_data_out(rx_parallel_data_out),
        .rx_data_vld         (rx_data_vld)
    );
`endif
