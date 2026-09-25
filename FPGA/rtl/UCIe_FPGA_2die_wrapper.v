`timescale 1ns/1ps
// =============================================================================
// Module  : UCIe_FPGA_2die_wrapper
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : Two UCIe_FPGA_top_wrapper_link dies, cross-connected die-to-die
//           ("mated") through a ucie_link_fault_injector channel model.  Only
//           the AXI-Stream datapaths, the RDI interfaces and the fault-injection
//           controls leave this module - they are what gets wired to the PS via
//           EMIO/GPIO and the DMA/FIFO datapath.  The MainBand/SideBand parallel
//           PHY boundary stays INTERNAL, joined through the fault injector, so
//           the pair behaves like a real two-die link on a single FPGA.
//
//           Boundary handoff (mirrors UCIe_FPGA_loopback's fold, but split
//           across the two dies via the injector):
//             die0.o_mb_tx_* / o_sb_tx_*  -> injector -> die1.i_mb_rx_* / i_sb_rx_*
//             die1.o_mb_tx_* / o_sb_tx_*  -> injector -> die0.i_mb_rx_* / i_sb_rx_*
//             i_sb_tx_rdy tied 1'b1 on both dies (lossless parallel channel).
//
//           Both dies share lclk: the parallel handoff has no SerDes latency, so
//           die-N TX words are consumed by die-M RX in the same word-clock domain
//           (see UCIe_FPGA_loopback header).  MODULE_ID = 0 (die0) / 1 (die1),
//           matching UCIe_PHY_wrapper_tb.
// =============================================================================

module UCIe_FPGA_2die_wrapper #(
    parameter DATA_WIDTH_MB  = 32,
    parameter DATA_WIDTH_SB  = 64,
    parameter NUM_LANES      = 16,
    parameter N_BYTES        = 64,
    parameter GAP_WIDTH      = 32,
    parameter [DATA_WIDTH_MB-1:0] VALID_PATTERN = 32'h0F0F0F0F,
    parameter PLL_PERIOD_NS  = 0.5,
    parameter RX_ALIGN_DELAY = 2,
    parameter CLK_FRQ_HZ     = 800000000,
    parameter [2:0] MAX_LINK_WIDTH_CAP  = 3'd0,
    parameter [3:0] MAX_LINK_SPEED_CAP  = 4'h5,
    parameter       SPMW_CAP            = 1'b0,
    parameter       PMO_CAP             = 1'b1,
    parameter       PSPT_CAP            = 1'b0,
    parameter       L2SPD_CAP           = 1'b0,
    parameter [4:0] SUPPORTEDVSWING_CAP = 5'h01,
    parameter [1:0] CLK_MODE_CAP        = 2'b10,
    parameter [1:0] CLK_PHASE_CAP       = 2'b00,
    parameter       TARR_CAP            = 1'b0,
    parameter       ADVANCED_PKG_CAP    = 1'b0,

    // Bridge parameters (applied to both dies)
    parameter MB_RX_FIFO_DEPTH   = 8,
    parameter SB_TX_DN_CRD_INIT  = 32,
    parameter SB_RX_FIFO_DEPTH   = 16
)(
    // lclk clocks ALL AXI-Stream interfaces of BOTH dies.
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 lclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF d0_s_axis_mb_tx:d0_m_axis_mb_rx:d0_s_axis_sb_tx:d0_m_axis_sb_rx:d1_s_axis_mb_tx:d1_m_axis_mb_rx:d1_s_axis_sb_tx:d1_m_axis_sb_rx, ASSOCIATED_RESET rst_n" *)
    input                                    lclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input                                    rst_n,

    // =========================================================================
    // Fault-injection controls (wired to GPIO/PS)
    // =========================================================================
    input  [NUM_LANES-1:0]                   corrupt_0to1,
    input  [NUM_LANES-1:0]                   corrupt_1to0,
    input                                    reverse_0to1,
    input                                    reverse_1to0,
    input                                    vld_err_0to1,
    input                                    vld_err_1to0,
    input                                    block_sideband,

    // =========================================================================
    // ============================  DIE 0  ====================================
    // =========================================================================
    // ---- MainBand TX (AXI-Stream Slave) ----
    input  [8*N_BYTES-1:0]                   d0_s_axis_mb_tx_tdata,
    input  [(8*N_BYTES)/8-1:0]               d0_s_axis_mb_tx_tkeep,
    input                                    d0_s_axis_mb_tx_tlast,
    input                                    d0_s_axis_mb_tx_tvalid,
    output                                   d0_s_axis_mb_tx_tready,
    // ---- MainBand RX (AXI-Stream Master) ----
    output [8*N_BYTES-1:0]                   d0_m_axis_mb_rx_tdata,
    output [(8*N_BYTES)/8-1:0]               d0_m_axis_mb_rx_tkeep,
    output                                   d0_m_axis_mb_rx_tlast,
    output                                   d0_m_axis_mb_rx_tvalid,
    input                                    d0_m_axis_mb_rx_tready,
    // ---- SideBand TX (AXI-Stream Slave) ----
    input  [31:0]                            d0_s_axis_sb_tx_tdata,
    input  [3:0]                             d0_s_axis_sb_tx_tkeep,
    input                                    d0_s_axis_sb_tx_tlast,
    input                                    d0_s_axis_sb_tx_tvalid,
    output                                   d0_s_axis_sb_tx_tready,
    // ---- SideBand RX (AXI-Stream Master) ----
    output [31:0]                            d0_m_axis_sb_rx_tdata,
    output [3:0]                             d0_m_axis_sb_rx_tkeep,
    output                                   d0_m_axis_sb_rx_tlast,
    output                                   d0_m_axis_sb_rx_tvalid,
    input                                    d0_m_axis_sb_rx_tready,
    // ---- RDI Interface ----
    input  [3:0]                             d0_lp_state_req,
    input                                    d0_lp_clk_ack,
    input                                    d0_lp_wake_req,
    input                                    d0_lp_stallack,
    input                                    d0_lp_linkerror,
    output                                   d0_pl_clk_req,
    output                                   d0_pl_stallreq,
    output                                   d0_pl_wake_ack,
    output                                   d0_pl_trainerror,
    output                                   d0_pl_inband_pres,
    output                                   d0_pl_phyinrecenter,
    output [3:0]                             d0_pl_state_sts,
    output                                   d0_pl_max_speedmode,
    output [2:0]                             d0_pl_speedmode,
    output [2:0]                             d0_pl_lnk_cfg,
    // ---- Diagnostics ----
    output                                   d0_o_mb_rx_overflow,
    output                                   d0_o_sb_rx_overflow,

    // =========================================================================
    // ============================  DIE 1  ====================================
    // =========================================================================
    // ---- MainBand TX (AXI-Stream Slave) ----
    input  [8*N_BYTES-1:0]                   d1_s_axis_mb_tx_tdata,
    input  [(8*N_BYTES)/8-1:0]               d1_s_axis_mb_tx_tkeep,
    input                                    d1_s_axis_mb_tx_tlast,
    input                                    d1_s_axis_mb_tx_tvalid,
    output                                   d1_s_axis_mb_tx_tready,
    // ---- MainBand RX (AXI-Stream Master) ----
    output [8*N_BYTES-1:0]                   d1_m_axis_mb_rx_tdata,
    output [(8*N_BYTES)/8-1:0]               d1_m_axis_mb_rx_tkeep,
    output                                   d1_m_axis_mb_rx_tlast,
    output                                   d1_m_axis_mb_rx_tvalid,
    input                                    d1_m_axis_mb_rx_tready,
    // ---- SideBand TX (AXI-Stream Slave) ----
    input  [31:0]                            d1_s_axis_sb_tx_tdata,
    input  [3:0]                             d1_s_axis_sb_tx_tkeep,
    input                                    d1_s_axis_sb_tx_tlast,
    input                                    d1_s_axis_sb_tx_tvalid,
    output                                   d1_s_axis_sb_tx_tready,
    // ---- SideBand RX (AXI-Stream Master) ----
    output [31:0]                            d1_m_axis_sb_rx_tdata,
    output [3:0]                             d1_m_axis_sb_rx_tkeep,
    output                                   d1_m_axis_sb_rx_tlast,
    output                                   d1_m_axis_sb_rx_tvalid,
    input                                    d1_m_axis_sb_rx_tready,
    // ---- RDI Interface ----
    input  [3:0]                             d1_lp_state_req,
    input                                    d1_lp_clk_ack,
    input                                    d1_lp_wake_req,
    input                                    d1_lp_stallack,
    input                                    d1_lp_linkerror,
    output                                   d1_pl_clk_req,
    output                                   d1_pl_stallreq,
    output                                   d1_pl_wake_ack,
    output                                   d1_pl_trainerror,
    output                                   d1_pl_inband_pres,
    output                                   d1_pl_phyinrecenter,
    output [3:0]                             d1_pl_state_sts,
    output                                   d1_pl_max_speedmode,
    output [2:0]                             d1_pl_speedmode,
    output [2:0]                             d1_pl_lnk_cfg,
    // ---- Diagnostics ----
    output                                   d1_o_mb_rx_overflow,
    output                                   d1_o_sb_rx_overflow
);

    localparam LANEW = NUM_LANES*DATA_WIDTH_MB;

    // =========================================================================
    // Internal parallel PHY boundary of each die (kept inside this wrapper)
    // =========================================================================
    // Die 0 TX out / RX in
    wire             d0_mb_tx_ser_en, d0_mb_tx_valid_ser_en, d0_mb_tx_ckp, d0_mb_tx_ckn, d0_mb_tx_trk;
    wire [LANEW-1:0] d0_mb_tx_lane;
    wire [DATA_WIDTH_MB-1:0] d0_mb_tx_valid_word;
    wire [63:0]      d0_sb_tx_data;   wire d0_sb_tx_vld;
    wire             d0_mb_rx_data_valid, d0_mb_rx_valid_frame_vld, d0_mb_rx_ckp, d0_mb_rx_ckn, d0_mb_rx_trk;
    wire [LANEW-1:0] d0_mb_rx_lane;
    wire [DATA_WIDTH_MB-1:0] d0_mb_rx_valid_frame_data;
    wire [63:0]      d0_sb_rx_data;   wire d0_sb_rx_vld;

    // Die 1 TX out / RX in
    wire             d1_mb_tx_ser_en, d1_mb_tx_valid_ser_en, d1_mb_tx_ckp, d1_mb_tx_ckn, d1_mb_tx_trk;
    wire [LANEW-1:0] d1_mb_tx_lane;
    wire [DATA_WIDTH_MB-1:0] d1_mb_tx_valid_word;
    wire [63:0]      d1_sb_tx_data;   wire d1_sb_tx_vld;
    wire             d1_mb_rx_data_valid, d1_mb_rx_valid_frame_vld, d1_mb_rx_ckp, d1_mb_rx_ckn, d1_mb_rx_trk;
    wire [LANEW-1:0] d1_mb_rx_lane;
    wire [DATA_WIDTH_MB-1:0] d1_mb_rx_valid_frame_data;
    wire [63:0]      d1_sb_rx_data;   wire d1_sb_rx_vld;

    // =========================================================================
    // DIE 0  (MODULE_ID = 0)
    // =========================================================================
    UCIe_FPGA_top_wrapper_link #(
        .DATA_WIDTH_MB (DATA_WIDTH_MB), .DATA_WIDTH_SB (DATA_WIDTH_SB), .NUM_LANES (NUM_LANES),
        .N_BYTES (N_BYTES), .GAP_WIDTH (GAP_WIDTH), .VALID_PATTERN (VALID_PATTERN),
        .PLL_PERIOD_NS (PLL_PERIOD_NS), .RX_ALIGN_DELAY (RX_ALIGN_DELAY), .CLK_FRQ_HZ (CLK_FRQ_HZ),
        .MAX_LINK_WIDTH_CAP (MAX_LINK_WIDTH_CAP), .MAX_LINK_SPEED_CAP (MAX_LINK_SPEED_CAP),
        .SPMW_CAP (SPMW_CAP), .PMO_CAP (PMO_CAP), .PSPT_CAP (PSPT_CAP), .L2SPD_CAP (L2SPD_CAP),
        .SUPPORTEDVSWING_CAP (SUPPORTEDVSWING_CAP), .CLK_MODE_CAP (CLK_MODE_CAP),
        .CLK_PHASE_CAP (CLK_PHASE_CAP), .TARR_CAP (TARR_CAP), .ADVANCED_PKG_CAP (ADVANCED_PKG_CAP),
        .MODULE_ID (2'b0),
        .MB_RX_FIFO_DEPTH (MB_RX_FIFO_DEPTH), .SB_TX_DN_CRD_INIT (SB_TX_DN_CRD_INIT), .SB_RX_FIFO_DEPTH (SB_RX_FIFO_DEPTH)
    ) u_die0 (
        .lclk (lclk), .rst_n (rst_n),
        // AXI MB
        .s_axis_mb_tx_tdata (d0_s_axis_mb_tx_tdata), .s_axis_mb_tx_tkeep (d0_s_axis_mb_tx_tkeep),
        .s_axis_mb_tx_tlast (d0_s_axis_mb_tx_tlast), .s_axis_mb_tx_tvalid (d0_s_axis_mb_tx_tvalid),
        .s_axis_mb_tx_tready (d0_s_axis_mb_tx_tready),
        .m_axis_mb_rx_tdata (d0_m_axis_mb_rx_tdata), .m_axis_mb_rx_tkeep (d0_m_axis_mb_rx_tkeep),
        .m_axis_mb_rx_tlast (d0_m_axis_mb_rx_tlast), .m_axis_mb_rx_tvalid (d0_m_axis_mb_rx_tvalid),
        .m_axis_mb_rx_tready (d0_m_axis_mb_rx_tready),
        // AXI SB
        .s_axis_sb_tx_tdata (d0_s_axis_sb_tx_tdata), .s_axis_sb_tx_tkeep (d0_s_axis_sb_tx_tkeep),
        .s_axis_sb_tx_tlast (d0_s_axis_sb_tx_tlast), .s_axis_sb_tx_tvalid (d0_s_axis_sb_tx_tvalid),
        .s_axis_sb_tx_tready (d0_s_axis_sb_tx_tready),
        .m_axis_sb_rx_tdata (d0_m_axis_sb_rx_tdata), .m_axis_sb_rx_tkeep (d0_m_axis_sb_rx_tkeep),
        .m_axis_sb_rx_tlast (d0_m_axis_sb_rx_tlast), .m_axis_sb_rx_tvalid (d0_m_axis_sb_rx_tvalid),
        .m_axis_sb_rx_tready (d0_m_axis_sb_rx_tready),
        // RDI
        .lp_state_req (d0_lp_state_req), .lp_clk_ack (d0_lp_clk_ack), .lp_wake_req (d0_lp_wake_req),
        .lp_stallack (d0_lp_stallack), .lp_linkerror (d0_lp_linkerror),
        .pl_clk_req (d0_pl_clk_req), .pl_stallreq (d0_pl_stallreq), .pl_wake_ack (d0_pl_wake_ack),
        .pl_trainerror (d0_pl_trainerror), .pl_inband_pres (d0_pl_inband_pres),
        .pl_phyinrecenter (d0_pl_phyinrecenter), .pl_state_sts (d0_pl_state_sts),
        .pl_max_speedmode (d0_pl_max_speedmode), .pl_speedmode (d0_pl_speedmode), .pl_lnk_cfg (d0_pl_lnk_cfg),
        // Exposed parallel boundary -> internal nets
        .o_mb_tx_ser_en (d0_mb_tx_ser_en), .o_mb_tx_lane (d0_mb_tx_lane),
        .o_mb_tx_valid_ser_en (d0_mb_tx_valid_ser_en), .o_mb_tx_valid_word (d0_mb_tx_valid_word),
        .o_mb_tx_ckp (d0_mb_tx_ckp), .o_mb_tx_ckn (d0_mb_tx_ckn), .o_mb_tx_trk (d0_mb_tx_trk),
        .i_mb_rx_data_valid (d0_mb_rx_data_valid), .i_mb_rx_lane (d0_mb_rx_lane),
        .i_mb_rx_valid_frame_vld (d0_mb_rx_valid_frame_vld), .i_mb_rx_valid_frame_data (d0_mb_rx_valid_frame_data),
        .i_mb_rx_ckp (d0_mb_rx_ckp), .i_mb_rx_ckn (d0_mb_rx_ckn), .i_mb_rx_trk (d0_mb_rx_trk),
        .o_sb_tx_data (d0_sb_tx_data), .o_sb_tx_vld (d0_sb_tx_vld),
        .i_sb_tx_rdy (1'b1), .i_sb_rx_data (d0_sb_rx_data), .i_sb_rx_vld (d0_sb_rx_vld),
        // Diagnostics
        .o_mb_rx_overflow (d0_o_mb_rx_overflow), .o_sb_rx_overflow (d0_o_sb_rx_overflow)
    );

    // =========================================================================
    // DIE 1  (MODULE_ID = 1)
    // =========================================================================
    UCIe_FPGA_top_wrapper_link #(
        .DATA_WIDTH_MB (DATA_WIDTH_MB), .DATA_WIDTH_SB (DATA_WIDTH_SB), .NUM_LANES (NUM_LANES),
        .N_BYTES (N_BYTES), .GAP_WIDTH (GAP_WIDTH), .VALID_PATTERN (VALID_PATTERN),
        .PLL_PERIOD_NS (PLL_PERIOD_NS), .RX_ALIGN_DELAY (RX_ALIGN_DELAY), .CLK_FRQ_HZ (CLK_FRQ_HZ),
        .MAX_LINK_WIDTH_CAP (MAX_LINK_WIDTH_CAP), .MAX_LINK_SPEED_CAP (MAX_LINK_SPEED_CAP),
        .SPMW_CAP (SPMW_CAP), .PMO_CAP (PMO_CAP), .PSPT_CAP (PSPT_CAP), .L2SPD_CAP (L2SPD_CAP),
        .SUPPORTEDVSWING_CAP (SUPPORTEDVSWING_CAP), .CLK_MODE_CAP (CLK_MODE_CAP),
        .CLK_PHASE_CAP (CLK_PHASE_CAP), .TARR_CAP (TARR_CAP), .ADVANCED_PKG_CAP (ADVANCED_PKG_CAP),
        .MODULE_ID (2'b1),
        .MB_RX_FIFO_DEPTH (MB_RX_FIFO_DEPTH), .SB_TX_DN_CRD_INIT (SB_TX_DN_CRD_INIT), .SB_RX_FIFO_DEPTH (SB_RX_FIFO_DEPTH)
    ) u_die1 (
        .lclk (lclk), .rst_n (rst_n),
        // AXI MB
        .s_axis_mb_tx_tdata (d1_s_axis_mb_tx_tdata), .s_axis_mb_tx_tkeep (d1_s_axis_mb_tx_tkeep),
        .s_axis_mb_tx_tlast (d1_s_axis_mb_tx_tlast), .s_axis_mb_tx_tvalid (d1_s_axis_mb_tx_tvalid),
        .s_axis_mb_tx_tready (d1_s_axis_mb_tx_tready),
        .m_axis_mb_rx_tdata (d1_m_axis_mb_rx_tdata), .m_axis_mb_rx_tkeep (d1_m_axis_mb_rx_tkeep),
        .m_axis_mb_rx_tlast (d1_m_axis_mb_rx_tlast), .m_axis_mb_rx_tvalid (d1_m_axis_mb_rx_tvalid),
        .m_axis_mb_rx_tready (d1_m_axis_mb_rx_tready),
        // AXI SB
        .s_axis_sb_tx_tdata (d1_s_axis_sb_tx_tdata), .s_axis_sb_tx_tkeep (d1_s_axis_sb_tx_tkeep),
        .s_axis_sb_tx_tlast (d1_s_axis_sb_tx_tlast), .s_axis_sb_tx_tvalid (d1_s_axis_sb_tx_tvalid),
        .s_axis_sb_tx_tready (d1_s_axis_sb_tx_tready),
        .m_axis_sb_rx_tdata (d1_m_axis_sb_rx_tdata), .m_axis_sb_rx_tkeep (d1_m_axis_sb_rx_tkeep),
        .m_axis_sb_rx_tlast (d1_m_axis_sb_rx_tlast), .m_axis_sb_rx_tvalid (d1_m_axis_sb_rx_tvalid),
        .m_axis_sb_rx_tready (d1_m_axis_sb_rx_tready),
        // RDI
        .lp_state_req (d1_lp_state_req), .lp_clk_ack (d1_lp_clk_ack), .lp_wake_req (d1_lp_wake_req),
        .lp_stallack (d1_lp_stallack), .lp_linkerror (d1_lp_linkerror),
        .pl_clk_req (d1_pl_clk_req), .pl_stallreq (d1_pl_stallreq), .pl_wake_ack (d1_pl_wake_ack),
        .pl_trainerror (d1_pl_trainerror), .pl_inband_pres (d1_pl_inband_pres),
        .pl_phyinrecenter (d1_pl_phyinrecenter), .pl_state_sts (d1_pl_state_sts),
        .pl_max_speedmode (d1_pl_max_speedmode), .pl_speedmode (d1_pl_speedmode), .pl_lnk_cfg (d1_pl_lnk_cfg),
        // Exposed parallel boundary -> internal nets
        .o_mb_tx_ser_en (d1_mb_tx_ser_en), .o_mb_tx_lane (d1_mb_tx_lane),
        .o_mb_tx_valid_ser_en (d1_mb_tx_valid_ser_en), .o_mb_tx_valid_word (d1_mb_tx_valid_word),
        .o_mb_tx_ckp (d1_mb_tx_ckp), .o_mb_tx_ckn (d1_mb_tx_ckn), .o_mb_tx_trk (d1_mb_tx_trk),
        .i_mb_rx_data_valid (d1_mb_rx_data_valid), .i_mb_rx_lane (d1_mb_rx_lane),
        .i_mb_rx_valid_frame_vld (d1_mb_rx_valid_frame_vld), .i_mb_rx_valid_frame_data (d1_mb_rx_valid_frame_data),
        .i_mb_rx_ckp (d1_mb_rx_ckp), .i_mb_rx_ckn (d1_mb_rx_ckn), .i_mb_rx_trk (d1_mb_rx_trk),
        .o_sb_tx_data (d1_sb_tx_data), .o_sb_tx_vld (d1_sb_tx_vld),
        .i_sb_tx_rdy (1'b1), .i_sb_rx_data (d1_sb_rx_data), .i_sb_rx_vld (d1_sb_rx_vld),
        // Diagnostics
        .o_mb_rx_overflow (d1_o_mb_rx_overflow), .o_sb_rx_overflow (d1_o_sb_rx_overflow)
    );

    // =========================================================================
    // Fault-injection channel model between the two dies
    // =========================================================================
    ucie_link_fault_injector #(
        .NUM_LANES (NUM_LANES), .DATA_WIDTH_MB (DATA_WIDTH_MB)
    ) u_fault_inj (
        .corrupt_0to1 (corrupt_0to1), .corrupt_1to0 (corrupt_1to0),
        .reverse_0to1 (reverse_0to1), .reverse_1to0 (reverse_1to0),
        .vld_err_0to1 (vld_err_0to1), .vld_err_1to0 (vld_err_1to0),
        .block_sideband (block_sideband),

        // Die-0 TX in
        .d0_mb_tx_ser_en (d0_mb_tx_ser_en), .d0_mb_tx_lane (d0_mb_tx_lane),
        .d0_mb_tx_valid_ser_en (d0_mb_tx_valid_ser_en), .d0_mb_tx_valid_word (d0_mb_tx_valid_word),
        .d0_mb_tx_ckp (d0_mb_tx_ckp), .d0_mb_tx_ckn (d0_mb_tx_ckn), .d0_mb_tx_trk (d0_mb_tx_trk),
        .d0_sb_tx_data (d0_sb_tx_data), .d0_sb_tx_vld (d0_sb_tx_vld),
        // Die-1 TX in
        .d1_mb_tx_ser_en (d1_mb_tx_ser_en), .d1_mb_tx_lane (d1_mb_tx_lane),
        .d1_mb_tx_valid_ser_en (d1_mb_tx_valid_ser_en), .d1_mb_tx_valid_word (d1_mb_tx_valid_word),
        .d1_mb_tx_ckp (d1_mb_tx_ckp), .d1_mb_tx_ckn (d1_mb_tx_ckn), .d1_mb_tx_trk (d1_mb_tx_trk),
        .d1_sb_tx_data (d1_sb_tx_data), .d1_sb_tx_vld (d1_sb_tx_vld),

        // Die-0 RX out (<- die1 TX)
        .d0_mb_rx_data_valid (d0_mb_rx_data_valid), .d0_mb_rx_lane (d0_mb_rx_lane),
        .d0_mb_rx_valid_frame_vld (d0_mb_rx_valid_frame_vld), .d0_mb_rx_valid_frame_data (d0_mb_rx_valid_frame_data),
        .d0_mb_rx_ckp (d0_mb_rx_ckp), .d0_mb_rx_ckn (d0_mb_rx_ckn), .d0_mb_rx_trk (d0_mb_rx_trk),
        .d0_sb_rx_data (d0_sb_rx_data), .d0_sb_rx_vld (d0_sb_rx_vld),
        // Die-1 RX out (<- die0 TX)
        .d1_mb_rx_data_valid (d1_mb_rx_data_valid), .d1_mb_rx_lane (d1_mb_rx_lane),
        .d1_mb_rx_valid_frame_vld (d1_mb_rx_valid_frame_vld), .d1_mb_rx_valid_frame_data (d1_mb_rx_valid_frame_data),
        .d1_mb_rx_ckp (d1_mb_rx_ckp), .d1_mb_rx_ckn (d1_mb_rx_ckn), .d1_mb_rx_trk (d1_mb_rx_trk),
        .d1_sb_rx_data (d1_sb_rx_data), .d1_sb_rx_vld (d1_sb_rx_vld)
    );

endmodule
