`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;

module SideBand_Top_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_WIDTH = 64;
    parameter GAP_WIDTH  = 32;
    parameter CLK_MAIN_PERIOD = 10;
    parameter CLK_SB_PERIOD = 2.5; // 400 MHz for SB
    parameter PLL_CLK_PERIOD = 0.625; // 1.6 GHz for SerDes

    // =========================================================================
    // Signals
    // =========================================================================
    logic         clk_main;
    logic         rst_main_n;
    logic         clk_sb;
    logic         rst_sb_n;
    
    logic         phy_in_reset;
    logic         pmo_en;

    logic         sb_pll_clock;
    logic         RXCKSB;
    logic         TXCKSB;
    logic         tx_serial_out;
    logic         rx_serial_in;

    logic         pattern_mode;
    logic         start_pat_req;
    logic         send_4_iter;
    logic         four_iter_done;
    logic         det_pat_rcvd;

    logic         traffic_req;
    logic         traffic_rdy;

    logic [ 7:0]  RDI_msg_no_send;
    logic         stall_send;
    logic         RDI_vld_send;
    logic         RDI_rdy;

    logic [ 7:0]  ltsm_msg_n_send;
    logic [63:0]  msg_data_send;
    logic [15:0]  msg_info_send;
    logic         ltsm_vld_send;
    logic         ltsm_rdy;

    logic         RDI_vld_rcvd;
    logic [ 7:0]  RDI_msg_no_rcvd;
    logic         stall_rcvd;

    logic         ltsm_vld_rcvd;
    logic [ 7:0]  ltsm_msg_no_rcvd;
    logic [63:0]  msg_data_rcvd;
    logic [15:0]  msg_info_rcvd;

    logic [31:0]  lp_cfg;
    logic         lp_cfg_vld;
    logic         pl_cfg_crd;
    logic         lp_cfg_crd;
    logic [31:0]  pl_cfg;
    logic         pl_cfg_vld;

    logic [24:0]  rf_addr;
    logic [7:0]   rf_be;
    logic         rf_is_64b_access;
    logic [63:0]  rf_wdata;
    logic         rd_en;
    logic         wr_en;
    logic [63:0]  rf_rdata;
    logic         rdata_vld;
    logic         addr_err_o;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    SideBand_Top #(
        .DATA_WIDTH(DATA_WIDTH),
        .GAP_WIDTH(GAP_WIDTH)
    ) dut (
        .clk_main(clk_main),
        .rst_main_n(rst_main_n),
        .clk_sb(clk_sb),
        .rst_sb_n(rst_sb_n),
        .phy_in_reset(phy_in_reset),
        .pmo_en(pmo_en),
        .sb_pll_clock(sb_pll_clock),
        .RXCKSB(RXCKSB),
        .TXCKSB(TXCKSB),
        .tx_serial_out(tx_serial_out),
        .rx_serial_in(rx_serial_in),
        .pattern_mode(pattern_mode),
        .start_pat_req(start_pat_req),
        .send_4_iter(send_4_iter),
        .four_iter_done(four_iter_done),
        .det_pat_rcvd(det_pat_rcvd),
        .traffic_req(traffic_req),
        .traffic_rdy(traffic_rdy),
        .RDI_msg_no_send(RDI_msg_no_send),
        .stall_send(stall_send),
        .RDI_vld_send(RDI_vld_send),
        .RDI_rdy(RDI_rdy),
        .ltsm_msg_n_send(ltsm_msg_n_send),
        .msg_data_send(msg_data_send),
        .msg_info_send(msg_info_send),
        .ltsm_vld_send(ltsm_vld_send),
        .ltsm_rdy(ltsm_rdy),
        .RDI_vld_rcvd(RDI_vld_rcvd),
        .RDI_msg_no_rcvd(RDI_msg_no_rcvd),
        .stall_rcvd(stall_rcvd),
        .ltsm_vld_rcvd(ltsm_vld_rcvd),
        .ltsm_msg_no_rcvd(ltsm_msg_no_rcvd),
        .msg_data_rcvd(msg_data_rcvd),
        .msg_info_rcvd(msg_info_rcvd),
        .lp_cfg(lp_cfg),
        .lp_cfg_vld(lp_cfg_vld),
        .pl_cfg_crd(pl_cfg_crd),
        .lp_cfg_crd(lp_cfg_crd),
        .pl_cfg(pl_cfg),
        .pl_cfg_vld(pl_cfg_vld),
        .rf_addr(rf_addr),
        .rf_be(rf_be),
        .rf_is_64b_access(rf_is_64b_access),
        .rf_wdata(rf_wdata),
        .rd_en(rd_en),
        .wr_en(wr_en),
        .rf_rdata(rf_rdata),
        .rdata_vld(rdata_vld),
        .addr_err_o(addr_err_o)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk_main = 0;
    always #(CLK_MAIN_PERIOD/2) clk_main = ~clk_main;

    initial clk_sb = 0;
    always #(CLK_SB_PERIOD/2) clk_sb = ~clk_sb;

    initial sb_pll_clock = 0;
    always #(PLL_CLK_PERIOD/2) sb_pll_clock = ~sb_pll_clock;

    // Connect remote clock to our forwarded clock for loopback (or generate separately)
    assign RXCKSB = TXCKSB;
    assign rx_serial_in = tx_serial_out;

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        // Initialize inputs
        rst_main_n = 0;
        rst_sb_n = 0;
        phy_in_reset = 1;
        pmo_en = 0;

        pattern_mode = 0;
        start_pat_req = 0;
        send_4_iter = 0;
        traffic_rdy = 0;
        RDI_msg_no_send = 0;
        stall_send = 0;
        RDI_vld_send = 0;
        ltsm_msg_n_send = 0;
        msg_data_send = 0;
        msg_info_send = 0;
        ltsm_vld_send = 0;
        lp_cfg = 0;
        lp_cfg_vld = 0;
        lp_cfg_crd = 1;
        rf_rdata = 0;
        rdata_vld = 0;

        // Reset Deassertion
        #50;
        rst_main_n = 1;
        rst_sb_n = 1;
        phy_in_reset = 0;
        
        #50;
        $display("----------------------------------------");
        $display("Reset completed. Starting test...");
        
        // Let clocks align and logic settle
        #100;
        
        // Very basic test: Enable Pattern Mode
        @(posedge clk_sb);
        pattern_mode = 1;
        start_pat_req =1;
        send_4_iter = 0;
    
        #(CLK_SB_PERIOD*100);   
        start_pat_req = 0;
        
        // Wait to see if det_pat_rcvd goes high due to loopback
        #(CLK_SB_PERIOD*500);
        
        if (det_pat_rcvd) begin
            $display("SUCCESS: Pattern detected in loopback mode.");
        end else begin
            $display("WARNING: Pattern not detected within timeout. Check loopback / serialization.");
        end

        // Another simple test: trigger an LTSM message to send
        @(posedge clk_main);
        ltsm_vld_send = 1;
        ltsm_msg_n_send = 8'hA5; // dummy msg
        msg_data_send = 64'hDEADBEEF_01234567;
        
        @(posedge clk_main);
        ltsm_vld_send = 0;
        
        repeat(100) @(posedge clk_main);
        
        $display("Test finished.");
        $display("----------------------------------------");
        $finish;
    end

    // =========================================================================
    // Waveform Dumping
    // =========================================================================
    initial begin
        $dumpfile("SideBand_Top_tb.vcd");
        $dumpvars(0, SideBand_Top_tb);
    end

endmodule
