`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;

module SideBand_Top_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_WIDTH = 64;
    parameter GAP_WIDTH  = 32;
    parameter CLK_MAIN_PERIOD = 16.0; // 62.5 MHz
    parameter CLK_SB_PERIOD = SB_CLK; // 100 MHz from sb_pkg (10ns)
    parameter PLL_CLK_PERIOD = SERDES_CLK; // 800 MHz from sb_pkg (1.25ns)

    // =========================================================================
    // Signals
    // =========================================================================
    logic         clk_main;
    logic         rst_main_n;
    logic         clk_sb;
    logic         rst_sb_n;
    
    logic         phy_in_reset [2];
    logic         pmo_en [2];

    logic         sb_pll_clock;
    
    logic         RXCKSB [2];
    logic         TXCKSB [2];
    logic         tx_serial_out [2];
    logic         rx_serial_in [2];

    logic         pattern_mode [2];
    logic         start_pat_req [2];
    logic         send_4_iter [2];
    logic         four_iter_done [2];
    logic         det_pat_rcvd [2];

    logic         traffic_req [2];
    logic         traffic_rdy [2];

    logic [ 7:0]  RDI_msg_no_send [2];
    logic         stall_send [2];
    logic         RDI_vld_send [2];
    logic         RDI_rdy [2];

    logic [ 7:0]  ltsm_msg_n_send [2];
    logic [63:0]  msg_data_send [2];
    logic [15:0]  msg_info_send [2];
    logic         ltsm_vld_send [2];
    logic         ltsm_rdy [2];

    logic         RDI_vld_rcvd [2];
    logic [ 7:0]  RDI_msg_no_rcvd [2];
    logic         stall_rcvd [2];

    logic         ltsm_vld_rcvd [2];
    logic [ 7:0]  ltsm_msg_no_rcvd [2];
    logic [63:0]  msg_data_rcvd [2];
    logic [15:0]  msg_info_rcvd [2];

    logic [31:0]  lp_cfg [2];
    logic         lp_cfg_vld [2];
    logic         pl_cfg_crd [2];
    logic         lp_cfg_crd [2];
    logic [31:0]  pl_cfg [2];
    logic         pl_cfg_vld [2];

    logic [24:0]  rf_addr [2];
    logic [7:0]   rf_be [2];
    logic         rf_is_64b_access [2];
    logic [63:0]  rf_wdata [2];
    logic         rd_en [2];
    logic         wr_en [2];
    logic [63:0]  rf_rdata [2];
    logic         rdata_vld [2];
    logic         addr_err_o [2];

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < 2; i++) begin : dut_inst
            SideBand_Top #(
                .DATA_WIDTH(DATA_WIDTH),
                .GAP_WIDTH(GAP_WIDTH)
            ) dut (
                .clk_main(clk_main),
                .rst_main_n(rst_main_n),
                .clk_sb(clk_sb),
                .rst_sb_n(rst_sb_n),
                .phy_in_reset(phy_in_reset[i]),
                .pmo_en(pmo_en[i]),
                .sb_pll_clock(sb_pll_clock),
                .RXCKSB(RXCKSB[i]),
                .TXCKSB(TXCKSB[i]),
                .tx_serial_out(tx_serial_out[i]),
                .rx_serial_in(rx_serial_in[i]),
                .pattern_mode(pattern_mode[i]),
                .start_pat_req(start_pat_req[i]),
                .send_4_iter(send_4_iter[i]),
                .four_iter_done(four_iter_done[i]),
                .det_pat_rcvd(det_pat_rcvd[i]),
                .traffic_req(traffic_req[i]),
                .traffic_rdy(traffic_rdy[i]),
                .RDI_msg_no_send(RDI_msg_no_send[i]),
                .stall_send(stall_send[i]),
                .RDI_vld_send(RDI_vld_send[i]),
                .RDI_rdy(RDI_rdy[i]),
                .ltsm_msg_n_send(ltsm_msg_n_send[i]),
                .msg_data_send(msg_data_send[i]),
                .msg_info_send(msg_info_send[i]),
                .ltsm_vld_send(ltsm_vld_send[i]),
                .ltsm_rdy(ltsm_rdy[i]),
                .RDI_vld_rcvd(RDI_vld_rcvd[i]),
                .RDI_msg_no_rcvd(RDI_msg_no_rcvd[i]),
                .stall_rcvd(stall_rcvd[i]),
                .ltsm_vld_rcvd(ltsm_vld_rcvd[i]),
                .ltsm_msg_no_rcvd(ltsm_msg_no_rcvd[i]),
                .msg_data_rcvd(msg_data_rcvd[i]),
                .msg_info_rcvd(msg_info_rcvd[i]),
                .lp_cfg(lp_cfg[i]),
                .lp_cfg_vld(lp_cfg_vld[i]),
                .pl_cfg_crd(pl_cfg_crd[i]),
                .lp_cfg_crd(lp_cfg_crd[i]),
                .pl_cfg(pl_cfg[i]),
                .pl_cfg_vld(pl_cfg_vld[i]),
                .rf_addr(rf_addr[i]),
                .rf_be(rf_be[i]),
                .rf_is_64b_access(rf_is_64b_access[i]),
                .rf_wdata(rf_wdata[i]),
                .rd_en(rd_en[i]),
                .wr_en(wr_en[i]),
                .rf_rdata(rf_rdata[i]),
                .rdata_vld(rdata_vld[i]),
                .addr_err_o(addr_err_o[i])
            );
        end
    endgenerate

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk_main = 0;
    always #(CLK_MAIN_PERIOD/2.0) clk_main = ~clk_main;

    initial clk_sb = 0;
    always #(CLK_SB_PERIOD/2.0) clk_sb = ~clk_sb;

    initial sb_pll_clock = 0;
    always #(PLL_CLK_PERIOD/2.0) sb_pll_clock = ~sb_pll_clock;

    // Connect remote clock to our forwarded clock for loopback (or generate separately)
    assign RXCKSB[0] = TXCKSB[1];
    assign rx_serial_in[0] = tx_serial_out[1];

    assign RXCKSB[1] = TXCKSB[0];
    assign rx_serial_in[1] = tx_serial_out[0];

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        // Initialize inputs
        rst_main_n = 0;
        rst_sb_n = 0;

        for (int j = 0; j < 2; j++) begin
            phy_in_reset[j] = 1;
            pmo_en[j] = 0;
            pattern_mode[j] = 0;
            start_pat_req[j] = 0;
            send_4_iter[j] = 0;
            traffic_rdy[j] = 0;
            RDI_msg_no_send[j] = 0;
            stall_send[j] = 0;
            RDI_vld_send[j] = 0;
            ltsm_msg_n_send[j] = 0;
            msg_data_send[j] = 0;
            msg_info_send[j] = 0;
            ltsm_vld_send[j] = 0;
            lp_cfg[j] = 0;
            lp_cfg_vld[j] = 0;
            lp_cfg_crd[j] = 1;
            rf_rdata[j] = 0;
            rdata_vld[j] = 0;
        end

        // Reset Deassertion
        #50;
        rst_main_n = 1;
        rst_sb_n = 1;
        phy_in_reset[0] = 0; phy_in_reset[1] = 0;
        
        #50;
        $display("----------------------------------------");
        $display("Reset completed. Starting test...");
        
        // Let clocks align and logic settle
        #100;
        
        // =========================================================
        // Pattern Sequence Test (Realistic Scenario)
        // =========================================================
        $display("[%0t] TEST: Starting realistic pattern test sequence", $time);

        @(posedge clk_sb);
        pattern_mode[0] = 1; pattern_mode[1] = 1;
        start_pat_req[0] = 1; start_pat_req[1] = 0; // Only Die 0 starts
        send_4_iter[0] = 0; send_4_iter[1] = 0;
        pmo_en[0] = 0; pmo_en[1] = 0;
        $display("[%0t] Die 0 starts pattern generation, Die 1 is waiting", $time);

        // Now both dies will run concurrently to finish their sequence
        fork : die_flows
            // Die 0 flow
            begin
                fork : die0_wait
                    begin
                        @(posedge det_pat_rcvd[0]);
                    end
                    begin
                        #(CLK_SB_PERIOD*100000);
                        $display("[%0t] TIMEOUT: Die 0 did not receive pattern back!", $time);
                        $stop;
                    end
                join_any
                disable die0_wait;

                $display("[%0t] Die 0 detected pattern back! Switching to 4-iter", $time);
                @(posedge clk_sb);
                start_pat_req[0] = 0;
                send_4_iter[0] = 1;

                wait(four_iter_done[0] == 1'b1);
                @(posedge clk_sb);
                $display("[%0t] Die 0 4-iter done! Switching to mapper", $time);
                send_4_iter[0] = 0;
                pattern_mode[0] = 0;
                pmo_en[0] = 1;
            end
            
            // Die 1 flow
            begin
                // Die 1 waits idly for the FIRST pattern (no timeout)
                @(posedge det_pat_rcvd[1]);
                $display("[%0t] Die 1 detected pattern! Asserting start_pat_req", $time);
                @(posedge clk_sb);
                start_pat_req[1] = 1;

                // Die 1 waits for SECOND pattern (WITH timeout)
                fork : die1_wait
                    begin
                        @(posedge det_pat_rcvd[1]);
                    end
                    begin
                        #(CLK_SB_PERIOD*100000);
                        $display("[%0t] TIMEOUT: Die 1 did not receive second pattern!", $time);
                        $stop;
                    end
                join_any
                disable die1_wait;

                $display("[%0t] Die 1 detected pattern second time! Switching to 4-iter", $time);
                @(posedge clk_sb);
                start_pat_req[1] = 0;
                send_4_iter[1] = 1;

                wait(four_iter_done[1] == 1'b1);
                @(posedge clk_sb);
                $display("[%0t] Die 1 4-iter done! Switching to mapper", $time);
                send_4_iter[1] = 0;
                pattern_mode[1] = 0;
                pmo_en[1] = 1;
            end
        join

        // Wait a few clocks to ensure stable transition
        repeat(50) @(posedge clk_sb);

        $display("----------------------------------------");
        $display("TEST PASSED");
        $display("----------------------------------------");
        $stop;
    end

    // =========================================================================
    // Waveform Dumping
    // =========================================================================
    initial begin
        $dumpfile("SideBand_Top_tb.vcd");
        $dumpvars(0, SideBand_Top_tb);
    end

endmodule