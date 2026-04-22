// =============================================================================
// Module      : Link_Mgmt
// Description : Top-level for UCIe Sideband Link Management.
//               Integrates TX arbitration, packetization, and RX decoding.
//               Uses asynchronous FIFOs for Main SM clock domain crossing.
// =============================================================================

import sb_pkg::*;
import UCIe_pkg::*;

module Link_Mgmt #(
    parameter int FIFO_ADDR_WIDTH = 4  // Depth = 16 entries
)(
    // Clock and Reset
    input  logic         clk_main,     // Main SM domain (LTSM/RDI_SM)
    input  logic         rst_main_n,
    input  logic         clk_sb,       // Sideband domain
    input  logic         rst_sb_n,

    // -------------------------------------------------------------------------
    // Main SM TX Interface (clk_main)
    // -------------------------------------------------------------------------
    input  logic [ 7:0]  RDI_msg_no_send,
    input  logic         stall_send,
    input  logic         RDI_vld_send,
    output logic         RDI_ready,

    input  logic [87:0]  LTSM_msg,
    input  logic         LTSM_vld,
    output logic         LTSM_ready,

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
    output logic [127:0] Link_msg_send,
    output logic         Link_vld_send,
    input  logic         Link_ready,       // Backpressure from Link Controller

    input  logic [127:0] Link_msg_rcvd,
    input  logic         Link_vld_rcvd
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
    logic [63:0] arb_msg_data;
    logic [15:0] arb_msg_info;
    logic [ 7:0] arb_msg_n;
    logic        arb_vld;
    logic        packetizer_ready;

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
        .W_CLK   (clk_main),
        .WRST_N  (rst_main_n),
        .WINC    (LTSM_vld),
        .WR_DATA (LTSM_msg),
        .WFULL   (),
        .WREADY  (LTSM_ready),

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
        .WREADY  (RDI_ready),

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

    arbiter u_arbiter (
        .clk            (clk_sb),
        .rst_n          (rst_sb_n),
        
        // From FIFOs
        .rdi_msg_fifo   (rdi_msg_fifo_rd),
        .rdi_not_empty  (rdi_fifo_not_empty),
        .rdi_pop        (rdi_pop),
        
        .ltsm_msg_fifo  (ltsm_msg_fifo_rd),
        .ltsm_not_empty (ltsm_fifo_not_empty),
        .ltsm_pop       (ltsm_pop),

        // Handshake
        .LINK_ready     (packetizer_ready),
        
        // To Packetizer
        .msg_data       (arb_msg_data),
        .msg_info       (arb_msg_info),
        .msg_n          (arb_msg_n),
        .vld            (arb_vld)
    );

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
        .Link_ready     (Link_ready),
        .Link_msg_send  (Link_msg_send),
        .Link_vld_send  (Link_vld_send),
        .ready          (packetizer_ready)
    );

    // -------------------------------------------------------------------------
    // RX Path: DePacketizer & Demux Unit
    // -------------------------------------------------------------------------

    DePacketizer u_depacketizer (
        .clk        (clk_sb),
        .rst_n      (rst_sb_n),
        .msg_in     (Link_msg_rcvd),
        .vld_in     (Link_vld_rcvd),
        
        // Decoded Outputs
        .msg_no_out (rx_msg_no_raw),
        .msginfo_r  (rx_msginfo_raw),
        .payload_r  (rx_payload_raw),
        .vld_r      (rx_vld_raw),
        .stall_rcvd (rx_stall_raw)
    );

    // Instantiate Specialized Demux
    Link_Mgmt_Demux u_demux (
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
