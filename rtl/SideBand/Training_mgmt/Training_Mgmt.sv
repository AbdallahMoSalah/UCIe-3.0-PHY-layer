// =============================================================================
// Module      : Training_Mgmt
// Description : Top-level for UCIe Sideband Link Management.
//               Integrates TX arbitration, packetization, and RX decoding.
//               Uses asynchronous FIFOs for Main SM clock domain crossing.
// =============================================================================

import sb_pkg::*;
import UCIe_pkg::*;

module Training_Mgmt #(
    parameter int FIFO_ADDR_WIDTH = 4  // Depth = 16 entries
)(
    // Clock and Reset
    input  logic         clk_main,     // Main SM domain (LTSM/RDI_SM)
    input  logic         clk_ltsm,
    input  logic         rst_main_n,
    input  logic         clk_sb,       // Sideband domain
    input  logic         rst_sb_n,

    // -------------------------------------------------------------------------
    // Main SM TX Interface (clk_main)
    // -------------------------------------------------------------------------
    input  logic [ 7:0]  RDI_msg_no_send,
    input  logic         stall_send,
    input  logic         RDI_vld_send,
    output logic         RDI_rdy,

    input  logic [ 7:0]  ltsm_msg_n_send,
    input  logic [63:0]  msg_data_send,
    input  logic [15:0]  msg_info_send,
    input  logic         ltsm_vld_send,
    output logic         ltsm_rdy,

    // -------------------------------------------------------------------------
    // Main SM RX Interface (clk_sb)
    // -------------------------------------------------------------------------
    output logic         RDI_vld_rcvd,
    output logic [ 7:0]  RDI_msg_no_rcvd,
    output logic         stall_rcvd,

    output logic         ltsm_vld_rcvd,
    output logic [ 7:0]  ltsm_msg_no_rcvd,
    output logic [63:0]  msg_data_rcvd,
    output logic [15:0]  msg_info_rcvd,

    // -------------------------------------------------------------------------
    // External Link Interface (clk_sb)
    // -------------------------------------------------------------------------
    output logic [127:0] trn_msg_send,
    output logic         trn_vld_send,
    input  logic         trn_rdy,       // Backpressure from Link Controller

    input  logic [127:0] trn_msg_rcvd,
    input  logic         trn_vld_rcvd
);

    // -------------------------------------------------------------------------
    // Internal Wires
    // -------------------------------------------------------------------------
    
    // LTSM TX FIFO Interface (Sideband Domain)
    logic [87:0] ltsm_msg_fifo_rd;
    logic        ltsm_fifo_not_empty;
    logic        ltsm_pop;

    // RDI TX FIFO Interface (Sideband Domain)
    logic [ 8:0] rdi_msg_fifo_rd;
    logic        rdi_fifo_not_empty;
    logic        rdi_pop;

    // Arbiter Outputs
    logic [87:0]  arb_link_data;
    logic [63:0]  arb_msg_data;
    logic [15:0]  arb_msg_info;
    logic [ 7:0]  arb_msg_n;
    logic         arb_vld;
    logic         packetizer_rdy;

    // DePacketizer Outputs
    msg_no_e     rx_msg_no_raw;
    logic [15:0] rx_msginfo_raw;
    logic [63:0] rx_payload_raw;
    logic        rx_vld_raw;
    logic        rx_stall_raw;

    // -------------------------------------------------------------------------
    // TX Path: Asynchronous FIFOs
    // -------------------------------------------------------------------------

    // LTSM FIFO: Main Domain (88 bits) -> Sideband Domain
    fifo #(
        .DATA_WIDTH (88),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH),
        .ASYNC      (1)
    ) u_ltsm_tx_fifo (
        .W_CLK   (clk_ltsm),
        .WRST_N  (rst_main_n),
        .WINC    (ltsm_vld_send),
        .WR_DATA ({msg_data_send, msg_info_send, ltsm_msg_n_send}),
        .WFULL   (),
        .WREADY  (ltsm_rdy),

        .R_CLK   (clk_sb),
        .RRST_N  (rst_sb_n),
        .RINC    (ltsm_pop),
        .RD_DATA (ltsm_msg_fifo_rd),
        .REMPTY  (),
        .RVALID  (ltsm_fifo_not_empty)
    );

    // RDI FIFO: Main Domain (9 bits) -> Sideband Domain
    // Data packed as: {stall, msg_no}
    fifo #(
        .DATA_WIDTH (9),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH),
        .ASYNC      (1)
    ) u_rdi_tx_fifo (
        .W_CLK   (clk_main),
        .WRST_N  (rst_main_n),
        .WINC    (RDI_vld_send),
        .WR_DATA ({stall_send, RDI_msg_no_send}),
        .WFULL   (),
        .WREADY  (RDI_rdy),

        .R_CLK   (clk_sb),
        .RRST_N  (rst_sb_n),
        .RINC    (rdi_pop),
        .RD_DATA (rdi_msg_fifo_rd),
        .REMPTY  (),
        .RVALID  (rdi_fifo_not_empty)
    );

    // -------------------------------------------------------------------------
    // TX Path: Arbiter & Packetizer
    // -------------------------------------------------------------------------

    // Round-Robin Arbiter Integration
    RR_arbiter #(
        .DATA_WIDTH(88)
    ) u_arbiter (
        .clk        (clk_sb),
        .rst_n      (rst_sb_n),
        
        // From LTSM FIFO
        .ltsm_valid (ltsm_fifo_not_empty),
        .ltsm_data  (ltsm_msg_fifo_rd),
        .ltsm_ready (ltsm_pop),
        
        // From RDI FIFO (Packed into 88 bits)
        .rdi_valid  (rdi_fifo_not_empty),
        .rdi_data   ({79'b0, rdi_msg_fifo_rd}),
        .rdi_ready  (rdi_pop),

        // Handshake with Packetizer
        .link_ready (packetizer_rdy),
        .link_valid (arb_vld),
        .link_data  (arb_link_data)
    );

    // Unpack Arbiter Output for Packetizer
    // Fields: [87:24] -> data, [23:8] -> info, [7:0] -> msg_no
    assign arb_msg_data = arb_link_data[87:24];
    assign arb_msg_info = arb_link_data[23:8];
    assign arb_msg_n    = arb_link_data[7:0];

    Packetizer u_packetizer (
        .clk            (clk_sb),
        .rst_n          (rst_sb_n),
        
        // Input from Arbiter
        .msg_data_send  (arb_msg_data),
        .msg_info_send  (arb_msg_info),
        .msg_no_send    (arb_msg_n),
        .valid_send     (arb_vld),
        
        // Special bit for RDI stall
        .stall_send     (arb_msg_info[0]), 

        // External Link
        .trn_rdy     (trn_rdy),
        .trn_msg_send  (trn_msg_send),
        .trn_vld_send  (trn_vld_send),
        .rdy          (packetizer_rdy)
    );

    // -------------------------------------------------------------------------
    // RX Path: DePacketizer & Demux Unit
    // -------------------------------------------------------------------------

    DePacketizer u_depacketizer (
        .clk        (clk_sb),
        .rst_n      (rst_sb_n),
        .msg_in     (trn_msg_rcvd),
        .vld_in     (trn_vld_rcvd),
        
        // Decoded Outputs
        .msg_no_out (rx_msg_no_raw),
        .msginfo_r  (rx_msginfo_raw),
        .payload_r  (rx_payload_raw),
        .vld_r      (rx_vld_raw),
        .stall_rcvd (rx_stall_raw)
    );

    // Instantiate Specialized Demux
    Training_Mgmt_Demux u_demux (
        // Inputs from DePacketizer
        .rx_msg_no_raw    (rx_msg_no_raw),
        .rx_msginfo_raw   (rx_msginfo_raw),
        .rx_payload_raw   (rx_payload_raw),
        .rx_vld_raw       (rx_vld_raw),
        .rx_stall_raw     (rx_stall_raw),

        // RDI Interface
        .RDI_vld_rcvd     (RDI_vld_rcvd),
        .RDI_msg_no_rcvd  (RDI_msg_no_rcvd),
        .stall_rcvd       (stall_rcvd),

        // LTSM Interface
        .ltsm_vld_rcvd    (ltsm_vld_rcvd),
        .ltsm_msg_no_rcvd (ltsm_msg_no_rcvd),
        .msg_data_rcvd    (msg_data_rcvd),
        .msg_info_rcvd    (msg_info_rcvd)
    );

endmodule
