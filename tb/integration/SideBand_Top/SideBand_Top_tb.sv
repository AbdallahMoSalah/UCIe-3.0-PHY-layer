`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;

module SideBand_Top_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_WIDTH = 64;
    parameter GAP_WIDTH  = 32;
    parameter CLK_MAIN_PERIOD = 16.0; // 62.5 MHz (RDI / Main-SM domain)
    parameter CLK_LTSM_PERIOD = 16.0; // LTSM-domain clock (async to clk_sb)
    parameter CLK_SB_PERIOD = SB_CLK; // 100 MHz from sb_pkg (10ns); clk_sb is now
                                      // DUT-generated - this is used only for TB
                                      // timeout/spacing math, not to drive a clock.

    // =========================================================================
    // Signals
    // =========================================================================
    logic         clk_main;
    logic         clk_ltsm;
    logic         rst_main_n;
    wire          clk_sb;             // TB sync reference (= die 0's generated clk_sb)
    wire          clk_sb_die [2];     // each DUT now GENERATES its own clk_sb (output)
    logic         rst_sb_n;

    logic         phy_in_reset [2];
    logic         pmo_en [2];

    logic         RXCKSB [2];
    logic         TXCKSB [2];
    logic         TXDATASB [2];
    logic         RXDATASB [2];

    logic         pattern_mode [2];
    logic         start_pat_req [2];
    logic [2:0]   req_iter_count [2];
    logic         iter_done [2];
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
                .clk_ltsm(clk_ltsm),
                .rst_main_n(rst_main_n),
                .clk_sb(clk_sb_die[i]),
                .rst_sb_n(rst_sb_n),
                .phy_in_reset(phy_in_reset[i]),
                .pmo_en(pmo_en[i]),
                .RXCKSB(RXCKSB[i]),
                .TXCKSB(TXCKSB[i]),
                .TXDATASB(TXDATASB[i]),
                .RXDATASB(RXDATASB[i]),
                .pattern_mode(pattern_mode[i]),
                .start_pat_req(start_pat_req[i]),
                .req_iter_count(req_iter_count[i]),
                .iter_done(iter_done[i]),
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

    initial clk_ltsm = 0;
    always #(CLK_LTSM_PERIOD/2.0) clk_ltsm = ~clk_ltsm;

    // clk_sb is GENERATED inside each SideBand_Top (internal sb_pll -> ClkDiv ÷8).
    // Both dies' sb_pll instances are identical free-running oscillators, so the
    // two generated clocks are phase-aligned in simulation; use die 0's as the
    // TB synchronization reference.
    assign clk_sb = clk_sb_die[0];

    // Connect remote clock to our forwarded clock for loopback (or generate separately)
    assign RXCKSB[0] = TXCKSB[1];
    assign RXDATASB[0] = TXDATASB[1];

    assign RXCKSB[1] = TXCKSB[0];
    assign RXDATASB[1] = TXDATASB[0];

    // =========================================================================
    // Test Tasks
    // =========================================================================
    task reset_and_init();
        // Initialize inputs
        rst_main_n = 0;
        rst_sb_n = 0;

        for (int j = 0; j < 2; j++) begin
            phy_in_reset[j] = 1;
            pmo_en[j] = 0;
            pattern_mode[j] = 0;
            start_pat_req[j] = 0;
            req_iter_count[j] = 3'd0;
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
        traffic_rdy[0] = 1; traffic_rdy[1] = 1;
        
        #50;
        $display("----------------------------------------");
        $display("Reset completed. Starting test...");
        
        // Let clocks align and logic settle
        #100;
    endtask

    initial begin
        forever begin
            @(posedge clk_sb);
            if (dut_inst[1].dut.des_vld_rcvd)
                $display("[%0t] \033[1;35m[MONITOR]\033[0m Die 1 des_vld_rcvd = 1, des_data_rcvd = %h", $time, dut_inst[1].dut.des_data_rcvd);
            if (ltsm_vld_rcvd[1])
                $display("[%0t] \033[1;35m[MONITOR]\033[0m Die 1 ltsm_vld_rcvd = 1", $time);
        end
    end

    task run_pattern_sequence();
        $display("[%0t] TEST: Starting realistic pattern test sequence", $time);

        @(posedge clk_sb);
        pattern_mode[0] = 1; pattern_mode[1] = 1;
        start_pat_req[0] = 1; start_pat_req[1] = 0; // Only Die 0 starts
        req_iter_count[0] = 3'd0; req_iter_count[1] = 3'd0;
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
                req_iter_count[0] = 3'd4;

                wait(iter_done[0] == 1'b1);
                @(posedge clk_sb);
                $display("[%0t] Die 0 4-iter done! Switching to mapper", $time);
                req_iter_count[0] = 3'd0;
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
                req_iter_count[1] = 3'd4;

                wait(iter_done[1] == 1'b1);
                @(posedge clk_sb);
                $display("[%0t] Die 1 4-iter done! Switching to mapper", $time);
                req_iter_count[1] = 3'd0;
                pattern_mode[1] = 0;
                pmo_en[1] = 1;
            end
        join

        // Wait a few clocks to ensure stable transition
        repeat(50) @(posedge clk_sb);
    endtask

    // =========================================================================
    // Helper Functions & Tasks
    // =========================================================================
    function automatic logic [63:0] build_req_header(sb_opcode_e op, sb_dstid_e dst, sb_srcid_e src, logic [23:0] address);
        sb_header_u hdr;
        hdr.raw = '0;
        hdr.req.opcode = op;
        hdr.req.dstid  = dst;
        hdr.req.srcid  = src;
        hdr.req.addr   = address;
        return hdr.raw;
    endfunction

    function automatic logic [63:0] build_msg_header(sb_opcode_e op, sb_dstid_e dst, sb_srcid_e src, msg_code_e code);
        sb_header_u hdr;
        hdr.raw = '0;
        hdr.msg.opcode = op;
        hdr.msg.dstid  = dst;
        hdr.msg.srcid  = src;
        hdr.msg.msgcode = code;
        return hdr.raw;
    endfunction

    task send_lp_cfg_chunks(input logic [63:0] header, input logic [63:0] payload, input int num_chunks, input int die);
        @(posedge clk_sb);
        lp_cfg_vld[die] = 1;
        lp_cfg[die] = header[31:0];
        @(posedge clk_sb);
        lp_cfg[die] = header[63:32];
        if (num_chunks > 2) begin
            @(posedge clk_sb);
            lp_cfg[die] = payload[31:0];
            if (num_chunks > 3) begin
                @(posedge clk_sb);
                lp_cfg[die] = payload[63:32];
            end
        end
        @(posedge clk_sb);
        lp_cfg_vld[die] = 0;
    endtask

    // =========================================================================
    // Verification Sequences
    // =========================================================================

    task test_training_mgmt_path();
        $display("\n========================================================");
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting test_training_mgmt_path", $time);
        
        // ========================================================
        // Link Synchronization Phase (Flush garbage words)
        // ========================================================
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting Link Synchronization Phase", $time);
        fork : sync_phase
            begin
                // Send 2 dummy 64-bit messages to align sb_demapper on Die 1
                // (LTSM TX FIFO write port is clocked by clk_ltsm)
                for (int i=0; i<2; i++) begin
                    @(posedge clk_ltsm);
                    ltsm_vld_send[0] = 1;
                    ltsm_msg_n_send[0] = MBINIT_CAL_Done_req; // 64-bit msg
                    msg_data_send[0] = '0;
                    msg_info_send[0] = 16'h4234;
                    @(posedge clk_ltsm);
                    ltsm_vld_send[0] = 0;
                    repeat(20) @(posedge clk_ltsm);
                end
            end
            begin
                // Ignore the received dummy messages or corrupted garbage
                repeat(2) begin
                    wait(ltsm_vld_rcvd[1] == 1'b1);
                    $display("[%0t] \033[1;36m[DEBUG]\033[0m Link Sync: Discarding dummy msg on Die 1 (msg_no=%h)", $time, ltsm_msg_no_rcvd[1]);
                    @(posedge clk_main);
                end
            end
        join_any
        disable sync_phase;
        
        repeat(50) @(posedge clk_main);

        // Scenario A: Heavy Load LTSM
        $display("[%0t] \033[1;34m[INFO]\033[0m Sending Burst LTSM Messages", $time);
        fork
            begin
                for (int i=0; i<4; i++) begin
                    @(posedge clk_ltsm);
                    $display("[%0t] [DIE 0] Sending LTSM %0d", $time, i);
                    ltsm_vld_send[0] = 1;
                    ltsm_msg_n_send[0] = msg_no_e'(MBINIT_PARAM_configuration_req + i);
                    msg_data_send[0] = {32'hDEADBEEF, i[31:0]};
                    msg_info_send[0] = 16'h4234 + i; // dst_id = 2 (REMOTE_PHY)
                    @(posedge clk_ltsm);
                    ltsm_vld_send[0] = 0;
                    @(posedge clk_ltsm); // spacing
                end
            end
            begin
                for (int i=0; i<4; i++) begin
                    $display("[%0t] [DIE 1] Waiting for LTSM %0d", $time, i);
                    @(posedge ltsm_vld_rcvd[1]);
                    $display("[%0t] \033[1;36m[DEBUG]\033[0m Die 1 received LTSM message (msg_no=%h)", $time, ltsm_msg_no_rcvd[1]);
                    if (ltsm_msg_no_rcvd[1] != MBINIT_PARAM_configuration_req + i)
                        $error("[%0t] \033[1;31m[ERROR]\033[0m LTSM mismatch on Die 1: expected %h, got %h", $time, MBINIT_PARAM_configuration_req+i, ltsm_msg_no_rcvd[1]);
                    else
                        $display("[%0t] \033[1;32m[SUCCESS]\033[0m LTSM Burst Msg %0d received correctly", $time, i);
                    @(posedge clk_main);
                end
            end
        join

        // Scenario B: Heavy Load RDI
        $display("[%0t] \033[1;34m[INFO]\033[0m Sending Burst RDI Messages", $time);
        fork
            begin
                for (int i=0; i<5; i++) begin
                    @(posedge clk_main);
                    RDI_vld_send[0] = 1;
                    RDI_msg_no_send[0] = 8'h03 + i;
                    @(posedge clk_main);
                    RDI_vld_send[0] = 0;
                    @(posedge clk_sb); // spacing
                end
            end
            begin
                for (int i=0; i<5; i++) begin
                    @(posedge RDI_vld_rcvd[1]);
                    @(posedge clk_sb);
                    if (RDI_msg_no_rcvd[1] != 8'h03 + i)
                        $error("[%0t] \033[1;31m[ERROR]\033[0m RDI mismatch on Die 1: expected %h, got %h", $time, 8'h01+i, RDI_msg_no_rcvd[1]);
                    else
                        $display("[%0t] \033[1;32m[SUCCESS]\033[0m RDI Burst Msg %0d received correctly", $time, i);
                end
            end
        join

        repeat(50) @(posedge clk_sb);
    endtask

    task test_rdi_remote_msgs();
        logic [63:0] hdr;
        int timeout = 0;
        $display("\n========================================================");
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting test_rdi_remote_msgs", $time);
        
        // Remote register read message
        hdr = build_req_header(SB_32_CFG_READ, LOCAL_PHY, ADAPTER, 24'h102030);
        
        send_lp_cfg_chunks(hdr, 64'h0, 2, 0); // die 0
        
        // Wait for pl_cfg_vld on Die 1
        @(posedge clk_sb);
        while(pl_cfg_vld[0] != 1'b1 && timeout < 1000) begin
            @(posedge clk_sb);
            timeout++;
        end

        if(timeout == 1000)
            $error("[%0t] \033[1;31m[ERROR]\033[0m Remote RDI message not received on Die 1 via pl_cfg", $time);
        else
            $display("[%0t] \033[1;32m[SUCCESS]\033[0m Remote RDI message received on Die 1 via pl_cfg", $time);
        
        repeat(50) @(posedge clk_sb);
    endtask

    task test_rdi_local_reg_msgs();
        logic [63:0] hdr;
        logic [63:0] payload;
        
        $display("\n========================================================");
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting test_rdi_local_reg_msgs", $time);
        
        // Local register write message (64-bit mem write)
        hdr = build_req_header(SB_64_MEM_WRITE, LOCAL_PHY, ADAPTER, 24'h00AABB);
        payload = 64'hFEEDFACECAFEBEEF;
        
        fork
            begin
                send_lp_cfg_chunks(hdr, payload, 4, 0); // 4 chunks for 64-bit payload
            end
            begin
                // Monitor rf_* interface on Die 0
                wait(wr_en[0] == 1'b1);
                @(posedge clk_sb);
                if (rf_addr[0] == 25'h100AABB && rf_wdata[0] == payload)
                    $display("[%0t] \033[1;32m[SUCCESS]\033[0m Local register write successfully routed to Reg_Access on Die 0", $time);
                else
                    $error("[%0t] \033[1;31m[ERROR]\033[0m Local register write mismatch: addr=%h, data=%h", $time, rf_addr[0], rf_wdata[0]);
            end
        join
        
        repeat(50) @(posedge clk_sb);
    endtask

    task test_link_controller_arbitration();
        logic [63:0] hdr;
        
        $display("\n========================================================");
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting test_link_controller_arbitration", $time);
        
        hdr = build_msg_header(SB_MSG_WITHOUT_DATA, REMOTE_ADAPTER, ADAPTER, TEST_REQ_DOMAIN);
        
        // Send concurrent LTSM and RDI Control Messages from Die 0
        fork
            begin
                // LTSM Message (LTSM TX FIFO write port is clocked by clk_ltsm)
                @(posedge clk_ltsm);
                ltsm_vld_send[0] = 1;
                ltsm_msg_n_send[0] = 8'h00;
                @(posedge clk_ltsm);
                ltsm_vld_send[0] = 0;
            end
            begin
                // Remote Message from Adapter
                send_lp_cfg_chunks(hdr, 64'h0, 2, 0);
            end
        join
        
        // Wait for both to arrive on Die 1
        fork
            begin
                wait(ltsm_vld_rcvd[1] == 1'b1);
                $display("[%0t] \033[1;32m[SUCCESS]\033[0m LTSM message received post-arbitration", $time);
            end
            begin
                wait(pl_cfg_vld[1] == 1'b1);
                $display("[%0t] \033[1;32m[SUCCESS]\033[0m Adapter remote message received post-arbitration", $time);
            end
        join
        
        repeat(50) @(posedge clk_sb);
    endtask

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        reset_and_init();
        run_pattern_sequence();

        // Reset pattern mode after scenario
        @(posedge clk_sb);
        pattern_mode[0] = 0; pattern_mode[1] = 0;
        pmo_en[0] = 1; pmo_en[1] = 1;

        test_training_mgmt_path();
        test_rdi_remote_msgs();
        test_rdi_local_reg_msgs();
        test_link_controller_arbitration();

        $display("----------------------------------------");
        $display("\033[1;32mTEST PASSED\033[0m");
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