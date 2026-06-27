`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;

module SideBand_AXIS_Top_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_WIDTH = 64;
    parameter GAP_WIDTH  = 32;
    parameter CLK_MAIN_PERIOD = 16.0; // 62.5 MHz (RDI / Main-SM domain)
    parameter CLK_LTSM_PERIOD = 16.0; // LTSM-domain clock (async to clk_sb)
    parameter CLK_SB_PERIOD = SB_CLK; // 100 MHz from sb_pkg (10ns)

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

    // AXIS Slave (SideBand TX)
    logic [31:0]  s_axis_sb_tx_tdata [2];
    logic [3:0]   s_axis_sb_tx_tkeep [2];
    logic         s_axis_sb_tx_tlast [2];
    logic         s_axis_sb_tx_tvalid [2];
    logic         s_axis_sb_tx_tready [2];

    // AXIS Master (SideBand RX)
    logic [31:0]  m_axis_sb_rx_tdata [2];
    logic [3:0]   m_axis_sb_rx_tkeep [2];
    logic         m_axis_sb_rx_tlast [2];
    logic         m_axis_sb_rx_tvalid [2];
    logic         m_axis_sb_rx_tready [2];
    logic         o_sb_rx_overflow [2];

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
            SideBand_AXIS_Top #(
                .DATA_WIDTH(DATA_WIDTH),
                .GAP_WIDTH(GAP_WIDTH),
                .SB_TX_DN_CRD_INIT(32),
                .SB_RX_FIFO_DEPTH(16)
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
                
                // AXIS Slave (SideBand TX)
                .s_axis_sb_tx_tdata(s_axis_sb_tx_tdata[i]),
                .s_axis_sb_tx_tkeep(s_axis_sb_tx_tkeep[i]),
                .s_axis_sb_tx_tlast(s_axis_sb_tx_tlast[i]),
                .s_axis_sb_tx_tvalid(s_axis_sb_tx_tvalid[i]),
                .s_axis_sb_tx_tready(s_axis_sb_tx_tready[i]),
                
                // AXIS Master (SideBand RX)
                .m_axis_sb_rx_tdata(m_axis_sb_rx_tdata[i]),
                .m_axis_sb_rx_tkeep(m_axis_sb_rx_tkeep[i]),
                .m_axis_sb_rx_tlast(m_axis_sb_rx_tlast[i]),
                .m_axis_sb_rx_tvalid(m_axis_sb_rx_tvalid[i]),
                .m_axis_sb_rx_tready(m_axis_sb_rx_tready[i]),
                .o_sb_rx_overflow(o_sb_rx_overflow[i]),
                
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

    assign clk_sb = clk_sb_die[0];

    // Connect remote clock to our forwarded clock for loopback
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
            
            s_axis_sb_tx_tdata[j] = 0;
            s_axis_sb_tx_tkeep[j] = 0;
            s_axis_sb_tx_tlast[j] = 0;
            s_axis_sb_tx_tvalid[j] = 0;
            m_axis_sb_rx_tready[j] = 0;

            rf_rdata[j] = 0;
            rdata_vld[j] = 0;
            addr_err_o[j] = 0;
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
        
        #100;
    endtask

    initial begin
        forever begin
            @(posedge clk_sb);
            if (dut_inst[1].dut.u_sb_top.des_vld_rcvd)
                $display("[%0t] \033[1;35m[MONITOR]\033[0m Die 1 des_vld_rcvd = 1, des_data_rcvd = %h", $time, dut_inst[1].dut.u_sb_top.des_data_rcvd);
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

        fork
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
                @(posedge det_pat_rcvd[1]);
                $display("[%0t] Die 1 detected pattern! Asserting start_pat_req", $time);
                @(posedge clk_sb);
                start_pat_req[1] = 1;

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
        hdr.req.cp     = ^(hdr.raw[61:0]);
        return hdr.raw;
    endfunction

    function automatic logic [63:0] build_msg_header(sb_opcode_e op, sb_dstid_e dst, sb_srcid_e src, msg_code_e code);
        sb_header_u hdr;
        hdr.raw = '0;
        hdr.msg.opcode = op;
        hdr.msg.dstid  = dst;
        hdr.msg.srcid  = src;
        hdr.msg.msgcode = code;
        hdr.msg.cp     = ^(hdr.raw[61:0]);
        return hdr.raw;
    endfunction

    task send_axis_chunks(input logic [63:0] header, input logic [63:0] payload, input int num_chunks, input int die);
        logic [31:0] chunks[4];
        chunks[0] = header[31:0];
        chunks[1] = header[63:32];
        chunks[2] = payload[31:0];
        chunks[3] = payload[63:32];

        for (int c = 0; c < num_chunks; c++) begin
            @(posedge clk_sb);
            s_axis_sb_tx_tvalid[die] = 1;
            s_axis_sb_tx_tdata[die] = chunks[c];
            s_axis_sb_tx_tkeep[die] = 4'hF;
            s_axis_sb_tx_tlast[die] = (c == num_chunks - 1);
            
            // Wait until ready is asserted
            while (!s_axis_sb_tx_tready[die]) begin
                @(posedge clk_sb);
            end
        end
        @(posedge clk_sb);
        s_axis_sb_tx_tvalid[die] = 0;
        s_axis_sb_tx_tlast[die] = 0;
    endtask

    task automatic receive_axis_packet(
        input int die,
        output logic [127:0] packet,
        output bit success
    );
        int timeout = 0;
        int c = 0;
        success = 0;
        packet = '0;

        // Assert ready so master can send
        m_axis_sb_rx_tready[die] = 1;

        while (c < 4) begin
            @(posedge clk_sb);
            if (m_axis_sb_rx_tvalid[die] && m_axis_sb_rx_tready[die]) begin
                case(c)
                    0: packet[31:0]   = m_axis_sb_rx_tdata[die];
                    1: packet[63:32]  = m_axis_sb_rx_tdata[die];
                    2: packet[95:64]  = m_axis_sb_rx_tdata[die];
                    3: packet[127:96] = m_axis_sb_rx_tdata[die];
                endcase
                
                $display("[%0t] [RX_TASK] Die %0d: Captured chunk %0d = %h, tlast = %b", 
                         $time, die, c, m_axis_sb_rx_tdata[die], m_axis_sb_rx_tlast[die]);
                
                c++;
                if (m_axis_sb_rx_tlast[die]) begin
                    break;
                end
            end else begin
                timeout++;
                if (timeout > 2000) begin
                    break;
                end
            end
        end
        
        m_axis_sb_rx_tready[die] = 0;
        success = (c > 0 && timeout <= 2000);
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
                repeat(2) begin
                    fork
                        begin
                            wait(ltsm_vld_rcvd[1] == 1'b1);
                        end
                        begin
                            #(CLK_SB_PERIOD*5000);
                            $error("[%0t] \033[1;31m[ERROR]\033[0m Timeout in Link Synchronization Phase", $time);
                            $stop;
                        end
                    join_any
                    disable fork;
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
                    fork
                        begin
                            @(posedge ltsm_vld_rcvd[1]);
                        end
                        begin
                            #(CLK_SB_PERIOD*5000);
                            $error("[%0t] \033[1;31m[ERROR]\033[0m Timeout waiting for LTSM %0d in test_training_mgmt_path", $time, i);
                            $stop;
                        end
                    join_any
                    disable fork;
                    
                    $display("[%0t] \033[1;36m[DEBUG]\033[0m Die 1 received LTSM message (msg_no=%h)", $time, ltsm_msg_no_rcvd[1]);
                    if (ltsm_msg_no_rcvd[1] != MBINIT_PARAM_configuration_req + i) begin
                        $error("[%0t] \033[1;31m[ERROR]\033[0m LTSM mismatch on Die 1: expected %h, got %h", $time, MBINIT_PARAM_configuration_req+i, ltsm_msg_no_rcvd[1]);
                        $stop;
                    end else
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
                    fork
                        begin
                            @(posedge RDI_vld_rcvd[1]);
                        end
                        begin
                            #(CLK_SB_PERIOD*5000);
                            $error("[%0t] \033[1;31m[ERROR]\033[0m Timeout waiting for RDI_vld_rcvd[1] in test_training_mgmt_path", $time);
                            $stop;
                        end
                    join_any
                    disable fork;
                    
                    @(posedge clk_sb);
                    if (RDI_msg_no_rcvd[1] != 8'h03 + i) begin
                        $error("[%0t] \033[1;31m[ERROR]\033[0m RDI mismatch on Die 1: expected %h, got %h", $time, 8'h03+i, RDI_msg_no_rcvd[1]);
                        $stop;
                    end else
                        $display("[%0t] \033[1;32m[SUCCESS]\033[0m RDI Burst Msg %0d received correctly", $time, i);
                end
            end
        join
        
        repeat(50) @(posedge clk_sb);
    endtask

    task automatic test_rdi_remote_msgs();
        logic [63:0] hdr;
        logic [127:0] cpl_pkt;
        bit success;
        $display("\n========================================================");
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting test_rdi_remote_msgs", $time);
        
        // Remote register read message
        hdr = build_req_header(SB_32_CFG_READ, LOCAL_PHY, ADAPTER, 24'h102030);
        
        fork
            begin
                send_axis_chunks(hdr, 64'h0, 2, 0); // die 0
            end
            begin
                receive_axis_packet(0, cpl_pkt, success);
            end
        join

        if(!success) begin
            $error("[%0t] \033[1;31m[ERROR]\033[0m Remote RDI message not received on Die 0 via AXIS", $time);
            $stop;
        end else
            $display("[%0t] \033[1;32m[SUCCESS]\033[0m Remote RDI message received on Die 0 via AXIS", $time);
        
        repeat(50) @(posedge clk_sb);
    endtask

    task test_rdi_local_reg_msgs();
        logic [63:0] hdr;
        logic [63:0] payload;
        logic [127:0] dummy_pkt;
        bit dummy_success;
        
        $display("\n========================================================");
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting test_rdi_local_reg_msgs", $time);
        
        hdr = build_req_header(SB_64_MEM_WRITE, LOCAL_PHY, ADAPTER, 24'h00AABB);
        payload = 64'hFEEDFACECAFEBEEF;
        
        fork
            begin
                send_axis_chunks(hdr, payload, 4, 0);
            end
            begin
                fork
                    begin
                        wait(wr_en[0] == 1'b1);
                    end
                    begin
                        #(CLK_SB_PERIOD*1000);
                        $error("[%0t] \033[1;31m[ERROR]\033[0m Timeout waiting for wr_en[0] in test_rdi_local_reg_msgs", $time);
                        $stop;
                    end
                join_any
                disable fork;

                @(posedge clk_sb);
                if (rf_addr[0] == 25'h100AABB && rf_wdata[0] == payload)
                    $display("[%0t] \033[1;32m[SUCCESS]\033[0m Local register write successfully routed to Reg_Access on Die 0", $time);
                else begin
                    $error("[%0t] \033[1;31m[ERROR]\033[0m Local register write mismatch: addr=%h, data=%h", $time, rf_addr[0], rf_wdata[0]);
                    $stop;
                end
            end
        join

        // Drain the write completion generated by this request
        receive_axis_packet(0, dummy_pkt, dummy_success);
        if (dummy_success)
            $display("[%0t] \033[1;32m[SUCCESS]\033[0m Drained write completion for local register write test", $time);
        else
            $error("[%0t] \033[1;31m[ERROR]\033[0m Failed to drain write completion for local register write test", $time);
        
        repeat(50) @(posedge clk_sb);
    endtask

    task automatic test_rdi_local_reg_completion();
        logic [63:0] hdr;
        logic [63:0] payload;
        logic [127:0] cpl_pkt;
        bit success;
        sb_header_u cpl_hdr_dec;
        
        $display("\n========================================================");
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting test_rdi_local_reg_completion", $time);
        
        // ------------------------------------------------------------
        // SCENARIO 1: Local Register WRITE (64-bit MEM WRITE)
        // ------------------------------------------------------------
        $display("[%0t] \033[1;34m[INFO]\033[0m Scenario 1: Sending Local Write Request", $time);
        hdr = build_req_header(SB_64_MEM_WRITE, LOCAL_PHY, ADAPTER, 24'h00ABCD);
        payload = 64'hFEEDFACECAFEBEEF;
        
        fork
            begin
                send_axis_chunks(hdr, payload, 4, 0); // 4 chunks to Die 0
            end
            begin
                receive_axis_packet(0, cpl_pkt, success);
            end
        join

        if (!success) begin
            $error("[%0t] \033[1;31m[ERROR]\033[0m Timeout: No completion received for local WRITE", $time);
            $stop;
        end else begin
            cpl_hdr_dec.raw = cpl_pkt[63:0];
            $display("[%0t] [DEBUG] Captured completion packet: %h", $time, cpl_pkt);
            $display("[%0t] [DEBUG] Decoded Opcode: %b, Status: %b", $time, cpl_hdr_dec.cpl.opcode, cpl_hdr_dec.cpl.status);
            
            if (cpl_hdr_dec.cpl.opcode != SB_COMPLETION_WITHOUT_DATA) begin
                $error("[%0t] \033[1;31m[ERROR]\033[0m Expected SB_COMPLETION_WITHOUT_DATA (%b), got %b", 
                       $time, SB_COMPLETION_WITHOUT_DATA, cpl_hdr_dec.cpl.opcode);
                $stop;
            end else if (cpl_hdr_dec.cpl.status != 3'b000) begin
                $error("[%0t] \033[1;31m[ERROR]\033[0m Write completion status error: expected SC (000), got %b", 
                       $time, cpl_hdr_dec.cpl.status);
                $stop;
            end else begin
                $display("[%0t] \033[1;32m[SUCCESS]\033[0m Local WRITE completed successfully!", $time);
            end
        end

        repeat(10) @(posedge clk_sb);

        // ------------------------------------------------------------
        // SCENARIO 2: Local Register READ (64-bit MEM READ)
        // ------------------------------------------------------------
        $display("\n[%0t] \033[1;34m[INFO]\033[0m Scenario 2: Sending Local Read Request", $time);
        hdr = build_req_header(SB_64_MEM_READ, LOCAL_PHY, ADAPTER, 24'h00ABCD);
        
        send_axis_chunks(hdr, 64'h0, 2, 0); // Read request is 2 chunks
        receive_axis_packet(0, cpl_pkt, success);

        if (!success) begin
            $error("[%0t] \033[1;31m[ERROR]\033[0m Timeout: No completion received for local READ", $time);
            $stop;
        end else begin
            cpl_hdr_dec.raw = cpl_pkt[63:0];
            $display("[%0t] [DEBUG] Captured completion packet: %h", $time, cpl_pkt);
            $display("[%0t] [DEBUG] Decoded Opcode: %b, Status: %b, Data: %h", 
                     $time, cpl_hdr_dec.cpl.opcode, cpl_hdr_dec.cpl.status, cpl_pkt[127:64]);
            
            if (cpl_hdr_dec.cpl.opcode != SB_COMPLETION_WITH_64_DATA) begin
                $error("[%0t] \033[1;31m[ERROR]\033[0m Expected SB_COMPLETION_WITH_64_DATA (%b), got %b", 
                       $time, SB_COMPLETION_WITH_64_DATA, cpl_hdr_dec.cpl.opcode);
                $stop;
            end else if (cpl_hdr_dec.cpl.status != 3'b000) begin
                $error("[%0t] \033[1;31m[ERROR]\033[0m Read completion status error: expected SC (000), got %b", 
                       $time, cpl_hdr_dec.cpl.status);
                $stop;
            end else if (cpl_pkt[127:64] != 64'hFEEDFACECAFEBEEF) begin
                $error("[%0t] \033[1;31m[ERROR]\033[0m Read data mismatch: expected 64'hFEEDFACECAFEBEEF, got %h", 
                       $time, cpl_pkt[127:64]);
                $stop;
            end else begin
                $display("[%0t] \033[1;32m[SUCCESS]\033[0m Local READ completed successfully with correct data!", $time);
            end
        end
        
        repeat(50) @(posedge clk_sb);
    endtask

    task test_link_controller_arbitration();
        logic [63:0] hdr;
        logic [127:0] rx_cpl;
        bit rx_success;
        
        $display("\n========================================================");
        $display("[%0t] \033[1;34m[INFO]\033[0m Starting test_link_controller_arbitration", $time);
        
        hdr = build_msg_header(SB_MSG_WITHOUT_DATA, REMOTE_ADAPTER, ADAPTER, TEST_REQ_DOMAIN);
        
        fork
            begin
                @(posedge clk_ltsm);
                ltsm_vld_send[0] = 1;
                ltsm_msg_n_send[0] = 8'h00;
                @(posedge clk_ltsm);
                ltsm_vld_send[0] = 0;
            end
            begin
                send_axis_chunks(hdr, 64'h0, 2, 0);
            end
        join
        
        fork
            begin
                fork
                    begin
                        wait(ltsm_vld_rcvd[1] == 1'b1);
                        $display("[%0t] \033[1;32m[SUCCESS]\033[0m LTSM message received post-arbitration", $time);
                    end
                    begin
                        #(CLK_SB_PERIOD*2000);
                        $error("[%0t] \033[1;31m[ERROR]\033[0m Timeout waiting for LTSM message in test_link_controller_arbitration", $time);
                        $stop;
                    end
                join_any
                disable fork;
            end
            begin
                receive_axis_packet(1, rx_cpl, rx_success);
                if (rx_success)
                    $display("[%0t] \033[1;32m[SUCCESS]\033[0m Adapter remote message received post-arbitration", $time);
                else begin
                    $error("[%0t] \033[1;31m[ERROR]\033[0m Timeout waiting for AXIS message in test_link_controller_arbitration", $time);
                    $stop;
                end
            end
        join
        
        repeat(50) @(posedge clk_sb);
    endtask

    // =========================================================================
    // Watchdog and Register File Mocking
    // =========================================================================
    initial begin
        #1000000; // 1 ms watchdog timeout
        $error("GLOBAL WATCHDOG TIMEOUT: Simulation hung!");
        $stop;
    end

    initial begin
        logic [63:0] reg_mem [2][logic [24:0]]; // memory per die
        fork
            // Die 0 memory responder
            forever begin
                @(posedge clk_sb);
                if (wr_en[0]) begin
                    reg_mem[0][rf_addr[0]] = rf_wdata[0];
                end
                if (rd_en[0]) begin
                    repeat(1) @(posedge clk_sb);
                    if (reg_mem[0].exists(rf_addr[0])) begin
                        rf_rdata[0] = reg_mem[0][rf_addr[0]];
                    end else begin
                        rf_rdata[0] = 64'hDECAFBADDECAFBAD;
                    end
                    rdata_vld[0] = 1;
                    @(posedge clk_sb);
                    rdata_vld[0] = 0;
                end
            end
            // Die 1 memory responder
            forever begin
                @(posedge clk_sb);
                if (wr_en[1]) begin
                    reg_mem[1][rf_addr[1]] = rf_wdata[1];
                end
                if (rd_en[1]) begin
                    repeat(1) @(posedge clk_sb);
                    if (reg_mem[1].exists(rf_addr[1])) begin
                        rf_rdata[1] = reg_mem[1][rf_addr[1]];
                    end else begin
                        rf_rdata[1] = 64'hDECAFBADDECAFBAD;
                    end
                    rdata_vld[1] = 1;
                    @(posedge clk_sb);
                    rdata_vld[1] = 0;
                end
            end
        join
    end

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        reset_and_init();
        run_pattern_sequence();

        @(posedge clk_sb);
        pattern_mode[0] = 0; pattern_mode[1] = 0;
        pmo_en[0] = 1; pmo_en[1] = 1;

        test_training_mgmt_path();
        test_rdi_remote_msgs();
        test_rdi_local_reg_msgs();
        test_rdi_local_reg_completion();
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
        $dumpfile("SideBand_AXIS_Top_tb.vcd");
        $dumpvars(0, SideBand_AXIS_Top_tb);
    end

endmodule
