`timescale 1ns/1ps
// =============================================================================
// Module  : UCIe_FPGA_top_wrapper
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : Top-level wrapper integrating the four AXI-Stream bridges and the
//           UCIe_FPGA_loopback core into a single module for Vivado block designs.
//
// Clocks  : Runs synchronously with clk_sb = lclk.
// =============================================================================

module UCIe_FPGA_top_wrapper #(
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
    parameter [1:0] MODULE_ID           = 2'b0,

    // Bridge parameters
    parameter MB_RX_FIFO_DEPTH   = 8,
    parameter SB_TX_DN_CRD_INIT  = 32,
    parameter SB_RX_FIFO_DEPTH   = 16
)(
    input                                    lclk,
    input                                    rst_n,

    // ---- MainBand TX (AXI-Stream Slave) ----
    input  [8*N_BYTES-1:0]                   s_axis_mb_tx_tdata,
    input  [(8*N_BYTES)/8-1:0]               s_axis_mb_tx_tkeep,
    input                                    s_axis_mb_tx_tlast,
    input                                    s_axis_mb_tx_tvalid,
    output                                   s_axis_mb_tx_tready,

    // ---- MainBand RX (AXI-Stream Master) ----
    output [8*N_BYTES-1:0]                   m_axis_mb_rx_tdata,
    output [(8*N_BYTES)/8-1:0]               m_axis_mb_rx_tkeep,
    output                                   m_axis_mb_rx_tlast,
    output                                   m_axis_mb_rx_tvalid,
    input                                    m_axis_mb_rx_tready,

    // ---- SideBand TX (AXI-Stream Slave) ----
    input  [31:0]                            s_axis_sb_tx_tdata,
    input  [3:0]                             s_axis_sb_tx_tkeep,
    input                                    s_axis_sb_tx_tlast,
    input                                    s_axis_sb_tx_tvalid,
    output                                   s_axis_sb_tx_tready,

    // ---- SideBand RX (AXI-Stream Master) ----
    output [31:0]                            m_axis_sb_rx_tdata,
    output [3:0]                             m_axis_sb_rx_tkeep,
    output                                   m_axis_sb_rx_tlast,
    output                                   m_axis_sb_rx_tvalid,
    input                                    m_axis_sb_rx_tready,

    // ---- RDI Interface ----
    input  [3:0]                             lp_state_req,
    input                                    lp_clk_ack,
    input                                    lp_wake_req,
    input                                    lp_stallack,
    input                                    lp_linkerror,

    output                                   pl_clk_req,
    output                                   pl_stallreq,
    output                                   pl_wake_ack,
    output                                   pl_trainerror,
    output                                   pl_inband_pres,
    output                                   pl_phyinrecenter,
    output [3:0]                             pl_state_sts,
    output                                   pl_max_speedmode,
    output [2:0]                             pl_speedmode,
    output [2:0]                             pl_lnk_cfg,

    // ---- Diagnostic Status Outputs ----
    output                                   o_mb_rx_overflow,
    output                                   o_sb_rx_overflow
);

    // =========================================================================
    // Synchronous clock setup
    // =========================================================================
    wire clk_sb = lclk;

    // =========================================================================
    // Intermediate Core Interconnect Nets
    // =========================================================================
    // MainBand core-facing interfaces
    wire [8*N_BYTES-1:0] lp_data;
    wire                 lp_irdy;
    wire                 lp_valid;
    wire                 pl_trdy;
    wire [8*N_BYTES-1:0] pl_data;
    wire                 pl_valid;
    wire                 pl_error; // Unused in bridges, but connected to core

    // SideBand core-facing interfaces
    wire [31:0]          lp_cfg;
    wire                 lp_cfg_vld;
    wire                 pl_cfg_crd;
    wire                 lp_cfg_crd;
    wire [31:0]          pl_cfg;
    wire                 pl_cfg_vld;

    // =========================================================================
    // MainBand TX Bridge: AXI-Stream Slave -> MainBand flit
    // =========================================================================
    axis_slave_to_mb_tx #(
        .FLIT_W  (8 * N_BYTES),
        .TDATA_W (8 * N_BYTES)
    ) u_mb_tx_bridge (
        .clk           (lclk),
        .rst_n         (rst_n),
        .s_axis_tdata  (s_axis_mb_tx_tdata),
        .s_axis_tkeep  (s_axis_mb_tx_tkeep),
        .s_axis_tlast  (s_axis_mb_tx_tlast),
        .s_axis_tvalid (s_axis_mb_tx_tvalid),
        .s_axis_tready (s_axis_mb_tx_tready),
        .lp_data       (lp_data),
        .lp_valid      (lp_valid),
        .lp_irdy       (lp_irdy),
        .pl_trdy       (pl_trdy)
    );

    // =========================================================================
    // MainBand RX Bridge: MainBand flit -> AXI-Stream Master
    // =========================================================================
    axis_master_from_mb_rx #(
        .FLIT_W     (8 * N_BYTES),
        .TDATA_W    (8 * N_BYTES),
        .FIFO_DEPTH (MB_RX_FIFO_DEPTH)
    ) u_mb_rx_bridge (
        .clk           (lclk),
        .rst_n         (rst_n),
        .pl_data       (pl_data),
        .pl_valid      (pl_valid),
        .m_axis_tdata  (m_axis_mb_rx_tdata),
        .m_axis_tkeep  (m_axis_mb_rx_tkeep),
        .m_axis_tlast  (m_axis_mb_rx_tlast),
        .m_axis_tvalid (m_axis_mb_rx_tvalid),
        .m_axis_tready (m_axis_mb_rx_tready),
        .o_overflow    (o_mb_rx_overflow)
    );

    // =========================================================================
    // SideBand TX Bridge: AXI-Stream Slave -> SideBand config downstream
    // =========================================================================
    axis_slave_to_sb_cfg #(
        .CFG_W       (32),
        .TDATA_W      (32),
        .DN_CRD_INIT (SB_TX_DN_CRD_INIT)
    ) u_sb_tx_bridge (
        .clk           (clk_sb),
        .rst_n         (rst_n),
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
    // SideBand RX Bridge: SideBand config upstream -> AXI-Stream Master
    // =========================================================================
    axis_master_from_sb_cfg #(
        .CFG_W      (32),
        .TDATA_W     (32),
        .FIFO_DEPTH (SB_RX_FIFO_DEPTH)
    ) u_sb_rx_bridge (
        .clk           (clk_sb),
        .rst_n         (rst_n),
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
    // UCIe Core under self-loopback (FPGA Target)
    // =========================================================================
    UCIe_FPGA_loopback #(
        .DATA_WIDTH_MB       (DATA_WIDTH_MB),
        .DATA_WIDTH_SB       (DATA_WIDTH_SB),
        .NUM_LANES           (NUM_LANES),
        .N_BYTES             (N_BYTES),
        .GAP_WIDTH           (GAP_WIDTH),
        .VALID_PATTERN       (VALID_PATTERN),
        .PLL_PERIOD_NS       (PLL_PERIOD_NS),
        .RX_ALIGN_DELAY      (RX_ALIGN_DELAY),
        .CLK_FRQ_HZ          (CLK_FRQ_HZ),
        .MAX_LINK_WIDTH_CAP  (MAX_LINK_WIDTH_CAP),
        .MAX_LINK_SPEED_CAP  (MAX_LINK_SPEED_CAP),
        .SPMW_CAP            (SPMW_CAP),
        .PMO_CAP             (PMO_CAP),
        .PSPT_CAP            (PSPT_CAP),
        .L2SPD_CAP           (L2SPD_CAP),
        .SUPPORTEDVSWING_CAP (SUPPORTEDVSWING_CAP),
        .CLK_MODE_CAP        (CLK_MODE_CAP),
        .CLK_PHASE_CAP       (CLK_PHASE_CAP),
        .TARR_CAP            (TARR_CAP),
        .ADVANCED_PKG_CAP    (ADVANCED_PKG_CAP),
        .MODULE_ID           (MODULE_ID)
    ) u_ucie_core (
        .rst_n            (rst_n),
        .lclk             (lclk),
        .gated_lclk       (lclk),
        .clk_sb           (clk_sb),

        // MainBand Flit Data (Adapter face)
        .lp_data          (lp_data),
        .lp_irdy          (lp_irdy),
        .lp_valid         (lp_valid),
        .pl_trdy          (pl_trdy),
        .pl_error         (pl_error),
        .pl_data          (pl_data),
        .pl_valid         (pl_valid),

        // Register access / config over sideband
        .lp_cfg           (lp_cfg),
        .lp_cfg_vld       (lp_cfg_vld),
        .pl_cfg_crd       (pl_cfg_crd),
        .lp_cfg_crd       (lp_cfg_crd),
        .pl_cfg           (pl_cfg),
        .pl_cfg_vld       (pl_cfg_vld),

        // RDI adapter-facing interface
        .lp_state_req     (lp_state_req),
        .lp_clk_ack       (lp_clk_ack),
        .lp_wake_req      (lp_wake_req),
        .lp_stallack      (lp_stallack),
        .lp_linkerror     (lp_linkerror),
        .pl_clk_req       (pl_clk_req),
        .pl_stallreq      (pl_stallreq),
        .pl_wake_ack      (pl_wake_ack),
        .pl_trainerror    (pl_trainerror),
        .pl_inband_pres   (pl_inband_pres),
        .pl_phyinrecenter (pl_phyinrecenter),
        .pl_state_sts     (pl_state_sts),
        .pl_max_speedmode (pl_max_speedmode),
        .pl_speedmode     (pl_speedmode),
        .pl_lnk_cfg       (pl_lnk_cfg)
    );

endmodule
