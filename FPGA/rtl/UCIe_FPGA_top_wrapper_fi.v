`timescale 1ns/1ps
// =============================================================================
// Module  : UCIe_FPGA_top_wrapper_fi
// Project : UCIe 3.0 PHY - FPGA bring-up
//
// Purpose : Single-die SELF-LOOPBACK with FAULT INJECTION.  Same external face
//           as UCIe_FPGA_top_wrapper (four AXI-Stream bridges + RDI, wired to
//           GPIO/DMA), but instead of the plain internal fold, the die's own
//           exposed MainBand/SideBand parallel boundary is looped back through a
//           ucie_loopback_fault_injector.  That lets the PS corrupt / reverse /
//           flip-valid / cut-sideband on the die's own loopback at run time -
//           the same fault taps UCIe_PHY_wrapper_tb applied between two dies,
//           here folded onto one die so no partner is needed.
//
//           Internally reuses UCIe_FPGA_top_wrapper_link (parallel boundary
//           exposed) + ucie_loopback_fault_injector; i_sb_tx_rdy tied 1'b1
//           (lossless parallel channel).
//
// Clocks  : Runs synchronously with lclk (no PLL/SerDes).
// =============================================================================

module UCIe_FPGA_top_wrapper_fi #(
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
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 lclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis_mb_tx:m_axis_mb_rx:s_axis_sb_tx:m_axis_sb_rx, ASSOCIATED_RESET rst_n" *)
    input                                    lclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input                                    rst_n,

    // =========================================================================
    // Fault-injection controls (wired to GPIO/PS)
    // =========================================================================
    input  [NUM_LANES-1:0]                   corrupt,
    input                                    reverse,
    input                                    vld_err,
    input                                    block_sideband,

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

    localparam LANEW = NUM_LANES*DATA_WIDTH_MB;

    // =========================================================================
    // Die exposed parallel PHY boundary (kept internal, self-folded via injector)
    // =========================================================================
    wire             mb_tx_ser_en, mb_tx_valid_ser_en, mb_tx_ckp, mb_tx_ckn, mb_tx_trk;
    wire [LANEW-1:0] mb_tx_lane;
    wire [DATA_WIDTH_MB-1:0] mb_tx_valid_word;
    wire [63:0]      sb_tx_data;   wire sb_tx_vld;

    wire             mb_rx_data_valid, mb_rx_valid_frame_vld, mb_rx_ckp, mb_rx_ckn, mb_rx_trk;
    wire [LANEW-1:0] mb_rx_lane;
    wire [DATA_WIDTH_MB-1:0] mb_rx_valid_frame_data;
    wire [63:0]      sb_rx_data;   wire sb_rx_vld;

    // =========================================================================
    // The die (parallel boundary exposed) - bridges + digital PHY inside
    // =========================================================================
    UCIe_FPGA_top_wrapper_link #(
        .DATA_WIDTH_MB (DATA_WIDTH_MB), .DATA_WIDTH_SB (DATA_WIDTH_SB), .NUM_LANES (NUM_LANES),
        .N_BYTES (N_BYTES), .GAP_WIDTH (GAP_WIDTH), .VALID_PATTERN (VALID_PATTERN),
        .PLL_PERIOD_NS (PLL_PERIOD_NS), .RX_ALIGN_DELAY (RX_ALIGN_DELAY), .CLK_FRQ_HZ (CLK_FRQ_HZ),
        .MAX_LINK_WIDTH_CAP (MAX_LINK_WIDTH_CAP), .MAX_LINK_SPEED_CAP (MAX_LINK_SPEED_CAP),
        .SPMW_CAP (SPMW_CAP), .PMO_CAP (PMO_CAP), .PSPT_CAP (PSPT_CAP), .L2SPD_CAP (L2SPD_CAP),
        .SUPPORTEDVSWING_CAP (SUPPORTEDVSWING_CAP), .CLK_MODE_CAP (CLK_MODE_CAP),
        .CLK_PHASE_CAP (CLK_PHASE_CAP), .TARR_CAP (TARR_CAP), .ADVANCED_PKG_CAP (ADVANCED_PKG_CAP),
        .MODULE_ID (MODULE_ID),
        .MB_RX_FIFO_DEPTH (MB_RX_FIFO_DEPTH), .SB_TX_DN_CRD_INIT (SB_TX_DN_CRD_INIT), .SB_RX_FIFO_DEPTH (SB_RX_FIFO_DEPTH)
    ) u_die (
        .lclk (lclk), .rst_n (rst_n),
        // AXI MB
        .s_axis_mb_tx_tdata (s_axis_mb_tx_tdata), .s_axis_mb_tx_tkeep (s_axis_mb_tx_tkeep),
        .s_axis_mb_tx_tlast (s_axis_mb_tx_tlast), .s_axis_mb_tx_tvalid (s_axis_mb_tx_tvalid),
        .s_axis_mb_tx_tready (s_axis_mb_tx_tready),
        .m_axis_mb_rx_tdata (m_axis_mb_rx_tdata), .m_axis_mb_rx_tkeep (m_axis_mb_rx_tkeep),
        .m_axis_mb_rx_tlast (m_axis_mb_rx_tlast), .m_axis_mb_rx_tvalid (m_axis_mb_rx_tvalid),
        .m_axis_mb_rx_tready (m_axis_mb_rx_tready),
        // AXI SB
        .s_axis_sb_tx_tdata (s_axis_sb_tx_tdata), .s_axis_sb_tx_tkeep (s_axis_sb_tx_tkeep),
        .s_axis_sb_tx_tlast (s_axis_sb_tx_tlast), .s_axis_sb_tx_tvalid (s_axis_sb_tx_tvalid),
        .s_axis_sb_tx_tready (s_axis_sb_tx_tready),
        .m_axis_sb_rx_tdata (m_axis_sb_rx_tdata), .m_axis_sb_rx_tkeep (m_axis_sb_rx_tkeep),
        .m_axis_sb_rx_tlast (m_axis_sb_rx_tlast), .m_axis_sb_rx_tvalid (m_axis_sb_rx_tvalid),
        .m_axis_sb_rx_tready (m_axis_sb_rx_tready),
        // RDI
        .lp_state_req (lp_state_req), .lp_clk_ack (lp_clk_ack), .lp_wake_req (lp_wake_req),
        .lp_stallack (lp_stallack), .lp_linkerror (lp_linkerror),
        .pl_clk_req (pl_clk_req), .pl_stallreq (pl_stallreq), .pl_wake_ack (pl_wake_ack),
        .pl_trainerror (pl_trainerror), .pl_inband_pres (pl_inband_pres),
        .pl_phyinrecenter (pl_phyinrecenter), .pl_state_sts (pl_state_sts),
        .pl_max_speedmode (pl_max_speedmode), .pl_speedmode (pl_speedmode), .pl_lnk_cfg (pl_lnk_cfg),
        // Exposed parallel boundary -> internal nets (self-fold via injector)
        .o_mb_tx_ser_en (mb_tx_ser_en), .o_mb_tx_lane (mb_tx_lane),
        .o_mb_tx_valid_ser_en (mb_tx_valid_ser_en), .o_mb_tx_valid_word (mb_tx_valid_word),
        .o_mb_tx_ckp (mb_tx_ckp), .o_mb_tx_ckn (mb_tx_ckn), .o_mb_tx_trk (mb_tx_trk),
        .i_mb_rx_data_valid (mb_rx_data_valid), .i_mb_rx_lane (mb_rx_lane),
        .i_mb_rx_valid_frame_vld (mb_rx_valid_frame_vld), .i_mb_rx_valid_frame_data (mb_rx_valid_frame_data),
        .i_mb_rx_ckp (mb_rx_ckp), .i_mb_rx_ckn (mb_rx_ckn), .i_mb_rx_trk (mb_rx_trk),
        .o_sb_tx_data (sb_tx_data), .o_sb_tx_vld (sb_tx_vld),
        .i_sb_tx_rdy (1'b1), .i_sb_rx_data (sb_rx_data), .i_sb_rx_vld (sb_rx_vld),
        // Diagnostics
        .o_mb_rx_overflow (o_mb_rx_overflow), .o_sb_rx_overflow (o_sb_rx_overflow)
    );

    // =========================================================================
    // Self-loopback fold through the fault injector
    // =========================================================================
    ucie_loopback_fault_injector #(
        .NUM_LANES (NUM_LANES), .DATA_WIDTH_MB (DATA_WIDTH_MB)
    ) u_fault_inj (
        .corrupt (corrupt), .reverse (reverse), .vld_err (vld_err), .block_sideband (block_sideband),
        // TX in
        .mb_tx_ser_en (mb_tx_ser_en), .mb_tx_lane (mb_tx_lane),
        .mb_tx_valid_ser_en (mb_tx_valid_ser_en), .mb_tx_valid_word (mb_tx_valid_word),
        .mb_tx_ckp (mb_tx_ckp), .mb_tx_ckn (mb_tx_ckn), .mb_tx_trk (mb_tx_trk),
        .sb_tx_data (sb_tx_data), .sb_tx_vld (sb_tx_vld),
        // RX out
        .mb_rx_data_valid (mb_rx_data_valid), .mb_rx_lane (mb_rx_lane),
        .mb_rx_valid_frame_vld (mb_rx_valid_frame_vld), .mb_rx_valid_frame_data (mb_rx_valid_frame_data),
        .mb_rx_ckp (mb_rx_ckp), .mb_rx_ckn (mb_rx_ckn), .mb_rx_trk (mb_rx_trk),
        .sb_rx_data (sb_rx_data), .sb_rx_vld (sb_rx_vld)
    );

endmodule
