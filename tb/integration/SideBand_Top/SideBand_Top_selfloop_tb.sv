`timescale 1ns/1ps

// =============================================================================
// SideBand_Top SELF-LOOP probe
//
//   Reproduces the FPGA topology at the sideband level: ONE die whose serial
//   TX pins loop straight back into its OWN serial RX pins (TXDATASB->RXDATASB,
//   TXCKSB->RXCKSB). phy_in_reset=0 (ACTIVE / normal mode), pattern_mode=0.
//
//   Goal: send an ADAPTER message (dstid = REMOTE_ADAPTER) from the adapter side
//   (lp_cfg) and verify it loops back up to this SAME die's pl_cfg, asserting
//   traffic_req (= the RDI clk-req the hardware waits on). This isolates whether
//   the ACTIVE-state adapter-message loopback works in RTL, matching the failing
//   main.c step 4 on hardware.
//
//   traffic_rdy is auto-granted (=1) so the de_aggregator delivers immediately;
//   this models "the software always acks the clk handshake".
// =============================================================================
import sb_pkg::*;
import UCIe_pkg::*;

module SideBand_Top_selfloop_tb;

    parameter DATA_WIDTH = 64;
    parameter GAP_WIDTH  = 32;
    parameter CLK_MAIN_PERIOD = 16.0;
    parameter CLK_LTSM_PERIOD = 16.0;
    parameter CLK_SB_PERIOD   = SB_CLK;

    // ---- signals (single die) ----
    logic         clk_main, clk_ltsm, rst_main_n, rst_sb_n;
    wire          clk_sb;                 // DUT-generated
    logic         phy_in_reset, pmo_en;
    wire          RXCKSB, TXCKSB, TXDATASB, RXDATASB;
    logic         pattern_mode, start_pat_req;
    logic [2:0]   req_iter_count;
    logic         iter_done, det_pat_rcvd;
    logic         traffic_req, traffic_rdy;

    logic [7:0]   RDI_msg_no_send;
    logic         stall_send, RDI_vld_send, RDI_rdy;
    logic [7:0]   ltsm_msg_n_send;
    logic [63:0]  msg_data_send;
    logic [15:0]  msg_info_send;
    logic         ltsm_vld_send, ltsm_rdy;

    logic         RDI_vld_rcvd;
    logic [7:0]   RDI_msg_no_rcvd;
    logic         stall_rcvd;
    logic         ltsm_vld_rcvd;
    logic [7:0]   ltsm_msg_no_rcvd;
    logic [63:0]  msg_data_rcvd;
    logic [15:0]  msg_info_rcvd;

    logic [31:0]  lp_cfg;
    logic         lp_cfg_vld, pl_cfg_crd, lp_cfg_crd;
    logic [31:0]  pl_cfg;
    logic         pl_cfg_vld;

    logic [24:0]  rf_addr;
    logic [7:0]   rf_be;
    logic         rf_is_64b_access;
    logic [63:0]  rf_wdata;
    logic         rd_en, wr_en;
    logic [63:0]  rf_rdata;
    logic         rdata_vld, addr_err_o;

    // ---- DUT ----
    SideBand_Top #(.DATA_WIDTH(DATA_WIDTH), .GAP_WIDTH(GAP_WIDTH)) dut (
        .clk_main(clk_main), .clk_ltsm(clk_ltsm), .rst_main_n(rst_main_n),
        .clk_sb(clk_sb), .rst_sb_n(rst_sb_n),
        .phy_in_reset(phy_in_reset), .pmo_en(pmo_en),
        .RXCKSB(RXCKSB), .TXCKSB(TXCKSB), .TXDATASB(TXDATASB), .RXDATASB(RXDATASB),
        .pattern_mode(pattern_mode), .start_pat_req(start_pat_req),
        .req_iter_count(req_iter_count), .iter_done(iter_done), .det_pat_rcvd(det_pat_rcvd),
        .traffic_req(traffic_req), .traffic_rdy(traffic_rdy),
        .RDI_msg_no_send(RDI_msg_no_send), .stall_send(stall_send),
        .RDI_vld_send(RDI_vld_send), .RDI_rdy(RDI_rdy),
        .ltsm_msg_n_send(ltsm_msg_n_send), .msg_data_send(msg_data_send),
        .msg_info_send(msg_info_send), .ltsm_vld_send(ltsm_vld_send), .ltsm_rdy(ltsm_rdy),
        .RDI_vld_rcvd(RDI_vld_rcvd), .RDI_msg_no_rcvd(RDI_msg_no_rcvd), .stall_rcvd(stall_rcvd),
        .ltsm_vld_rcvd(ltsm_vld_rcvd), .ltsm_msg_no_rcvd(ltsm_msg_no_rcvd),
        .msg_data_rcvd(msg_data_rcvd), .msg_info_rcvd(msg_info_rcvd),
        .lp_cfg(lp_cfg), .lp_cfg_vld(lp_cfg_vld),
        .pl_cfg_crd(pl_cfg_crd), .lp_cfg_crd(lp_cfg_crd),
        .pl_cfg(pl_cfg), .pl_cfg_vld(pl_cfg_vld),
        .rf_addr(rf_addr), .rf_be(rf_be), .rf_is_64b_access(rf_is_64b_access),
        .rf_wdata(rf_wdata), .rd_en(rd_en), .wr_en(wr_en),
        .rf_rdata(rf_rdata), .rdata_vld(rdata_vld), .addr_err_o(addr_err_o)
    );

    // ---- SELF-LOOP: TX pins straight back into this die's own RX pins ----
    assign RXCKSB   = TXCKSB;
    assign RXDATASB = TXDATASB;

    // ---- clocks ----
    initial clk_main = 0; always #(CLK_MAIN_PERIOD/2.0) clk_main = ~clk_main;
    initial clk_ltsm = 0; always #(CLK_LTSM_PERIOD/2.0) clk_ltsm = ~clk_ltsm;

    // ---- helpers ----
    function automatic logic [63:0] build_msg_header(sb_opcode_e op, sb_dstid_e dst,
                                                     sb_srcid_e src, logic [7:0] code);
        sb_header_u hdr;
        hdr.raw = '0;
        hdr.msg.opcode  = op;
        hdr.msg.dstid   = dst;
        hdr.msg.srcid   = src;
        hdr.msg.msgcode = msg_code_e'(code);
        hdr.msg.cp      = ^(hdr.raw[61:0]);
        return hdr.raw;
    endfunction

    task automatic send_lp_cfg_chunks(input logic [63:0] header, input logic [63:0] payload,
                                      input int num_chunks);
        @(posedge clk_sb); lp_cfg_vld = 1; lp_cfg = header[31:0];
        @(posedge clk_sb);                 lp_cfg = header[63:32];
        if (num_chunks > 2) begin
            @(posedge clk_sb);             lp_cfg = payload[31:0];
            if (num_chunks > 3) begin
                @(posedge clk_sb);         lp_cfg = payload[63:32];
            end
        end
        @(posedge clk_sb); lp_cfg_vld = 0;
    endtask

    // ---- test ----
    logic [63:0] hdr;
    int timeout;
    initial begin
        // init
        rst_main_n = 0; rst_sb_n = 0;
        phy_in_reset = 1; pmo_en = 0; pattern_mode = 0; start_pat_req = 0;
        req_iter_count = 0; traffic_rdy = 0;
        RDI_msg_no_send = 0; stall_send = 0; RDI_vld_send = 0;
        ltsm_msg_n_send = 0; msg_data_send = 0; msg_info_send = 0; ltsm_vld_send = 0;
        lp_cfg = 0; lp_cfg_vld = 0; lp_cfg_crd = 1;
        rf_rdata = 0; rdata_vld = 0; addr_err_o = 0;

        #50;
        rst_main_n = 1; rst_sb_n = 1;
        phy_in_reset = 0;      // ACTIVE / normal routing
        traffic_rdy  = 1;      // auto-grant the RDI clk handshake
        #200;

        $display("========================================================");
        $display("[%0t] [INFO] SELF-LOOP adapter-message test (dstid=REMOTE_ADAPTER)", $time);

        // Adapter message to REMOTE_ADAPTER: in self-loop it must come back to
        // this die's own pl_cfg (exactly what main.c step 4 expects).
        hdr = build_msg_header(SB_MSG_WITHOUT_DATA, REMOTE_ADAPTER, ADAPTER, 8'h01);
        send_lp_cfg_chunks(hdr, 64'h0, 2);

        // Watch traffic_req (= RDI clk-req the HW waits on) and pl_cfg delivery.
        timeout = 0;
        fork
            begin : watch_treq
                @(posedge traffic_req);
                $display("[%0t] [OBS] traffic_req asserted (message reached de_aggregator)", $time);
            end
            begin : watch_plcfg
                @(posedge pl_cfg_vld);
                $display("[%0t] \033[1;32m[SUCCESS]\033[0m adapter message looped back to OWN pl_cfg (pl_cfg=%h)", $time, pl_cfg);
            end
            begin : tmo
                repeat (4000) @(posedge clk_sb);
                $display("[%0t] \033[1;31m[FAIL]\033[0m self-loop adapter message never returned (traffic_req=%0b pl_cfg_vld=%0b)",
                         $time, traffic_req, pl_cfg_vld);
            end
        join_any
        // give pl_cfg a chance if only traffic_req fired first
        repeat (200) @(posedge clk_sb);
        $display("[%0t] [INFO] final: traffic_req=%0b pl_cfg_vld(seen)=%0b", $time, traffic_req, pl_cfg_vld);

        // =====================================================================
        // SCENARIO 2: STARVATION CHECK
        //   Hold the Link arbiter's HIGH-priority (training) input asserted, then
        //   send an adapter message. If strict priority starves the adapter
        //   (low-priority) input, the message never loops -> reproduces the HW
        //   symptom (no traffic_req, no pl_cfg).
        // =====================================================================
        $display("\n[%0t] [INFO] SCENARIO 2: sustained training traffic (force hip_vld=1)", $time);
        force dut.u_link_controller.u_Link_Arbiter.hip_vld = 1'b1;
        @(posedge clk_sb);

        hdr = build_msg_header(SB_MSG_WITHOUT_DATA, REMOTE_ADAPTER, ADAPTER, 8'h02);
        send_lp_cfg_chunks(hdr, 64'h0, 2);

        fork
            begin @(posedge pl_cfg_vld);
                  $display("[%0t] [S2] adapter msg STILL delivered (no starvation) pl_cfg=%h", $time, pl_cfg); end
            begin repeat (3000) @(posedge clk_sb);
                  $display("[%0t] \033[1;31m[S2-STARVED]\033[0m adapter msg blocked while training held priority (traffic_req=%0b)", $time, traffic_req); end
        join_any
        release dut.u_link_controller.u_Link_Arbiter.hip_vld;

        $display("========================================================");
        $finish;
    end

    // monitor the internal link demux + de_aggregator for visibility
    initial begin
        forever begin
            @(posedge clk_sb);
            if (dut.u_link_controller.u_LINK_Demux.adapter_vld_rcvd)
                $display("[%0t] [MON] LINK_Demux -> adapter_vld_rcvd=1 dstid=%h",
                         $time, dut.u_link_controller.u_LINK_Demux.msg_word_rcvd[58:56]);
        end
    end

endmodule
