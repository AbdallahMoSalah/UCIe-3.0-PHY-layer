`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// Testbench : digital_ucie_loopback_tb
// DUT       : digital_ucie_loopback = ONE digital_ucie (NO ANALOG) with its
//             MainBand + Sideband parallel boundary folded back on itself.
//
// Clocks    : generated here (no PLL in the design).  On FPGA these map to one
//             MMCM / clock-enable tree.
//               pll_clk    500 ps  (matches analog mb_pll speed_sel=0 = 2G)
//               gated_lclk pll_clk/16 = 8 ns  (MainBand word clock)
//               clk_sb     10 ns    (matches analog sb_pll/8)
//
// Scenarios :
//   SC1 : Bring-up  - program regs over SB -> training -> ACTIVE
//   SC2 : Data loop - send a flit, expect the same flit back
// =============================================================================

module digital_ucie_loopback_tb;

    localparam int  LTSM_CLK_FRQ = 200_000;
    localparam int  RDI_CLK_FRQ  = 200_000;
    localparam int  NUM_LANES    = 16;
    localparam int  N_BYTES      = 64;
    localparam int  FLITW        = 8 * N_BYTES;

    localparam logic [23:0] OFF_UCIE_LINK_CTRL = 24'h000010;
    localparam logic [23:0] OFF_PHY_CONTROL    = 24'h001004;
    localparam logic [23:0] OFF_TRAIN_SETUP4   = 24'h001050;

    // =========================================================================
    // Clock generation (no PLL in the design)
    // =========================================================================
    logic pll_clk   = 1'b0;
    logic gated_lclk= 1'b0;
    logic lclk;
    logic clk_sb    = 1'b0;

    always #0.25 pll_clk = ~pll_clk;   // 500 ps period
    always #5    clk_sb  = ~clk_sb;    // 10 ns period

    // gated_lclk = pll_clk / 16  (toggle every 8 posedges)
    logic [3:0] div_cnt = 4'd0;
    always @(posedge pll_clk) begin
        if (div_cnt == 4'd7) begin div_cnt <= 4'd0; gated_lclk <= ~gated_lclk; end
        else                      div_cnt <= div_cnt + 4'd1;
    end
    assign lclk = gated_lclk;

    // =========================================================================
    // DUT I/O
    // =========================================================================
    logic                 rst_n;

    logic [FLITW-1:0]     lp_data, pl_data;
    logic                 lp_irdy, lp_valid;
    logic                 pl_trdy, pl_error, pl_valid;

    logic [31:0]          lp_cfg, pl_cfg;
    logic                 lp_cfg_vld, lp_cfg_crd, pl_cfg_crd, pl_cfg_vld;

    logic [3:0]           lp_state_req;
    logic                 lp_clk_ack, lp_stallack, lp_wake_req, lp_linkerror;
    logic [3:0]           pl_state_sts;
    logic                 pl_clk_req, pl_stallreq, pl_wake_ack, pl_trainerror;

    // =========================================================================
    // DUT
    // =========================================================================
    digital_ucie_loopback #(
        .CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES), .MODULE_ID(0)
    ) u_dut (
        .rst_n        (rst_n),
        .lclk         (lclk), .gated_lclk(gated_lclk), .pll_clk(pll_clk),
        .clk_sb       (clk_sb),

        .lp_data      (lp_data),  .lp_irdy(lp_irdy), .lp_valid(lp_valid),
        .pl_trdy      (pl_trdy),  .pl_error(pl_error),
        .pl_data      (pl_data),  .pl_valid(pl_valid),

        .lp_cfg       (lp_cfg),   .lp_cfg_vld(lp_cfg_vld),
        .pl_cfg_crd   (pl_cfg_crd), .lp_cfg_crd(lp_cfg_crd),
        .pl_cfg       (pl_cfg),   .pl_cfg_vld(pl_cfg_vld),

        .lp_state_req (lp_state_req), .lp_clk_ack(lp_clk_ack),
        .lp_wake_req  (lp_wake_req),  .lp_stallack(lp_stallack),
        .lp_linkerror (lp_linkerror),
        .pl_clk_req   (pl_clk_req), .pl_stallreq(pl_stallreq),
        .pl_wake_ack  (pl_wake_ack), .pl_trainerror(pl_trainerror),
        .pl_inband_pres(), .pl_phyinrecenter(),
        .pl_state_sts (pl_state_sts), .pl_max_speedmode(),
        .pl_speedmode (), .pl_lnk_cfg()
    );

    // Shrink the RDI timers so they are simulatable.
    defparam u_dut.u_digital_ucie.u_main_sm.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_dut.u_digital_ucie.u_main_sm.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;

    // LTSM macro-state observation.
    state_n_e ln;
    assign ln = u_dut.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state_n;

    RDI_state rdi_sts;
    assign rdi_sts = u_dut.u_digital_ucie.u_main_sm.u_rdi_sm.sm.rdi_state_sts;

    // Enum mirror of the 4-bit pl_state_sts port, for .name() printing.
    RDI_state pl_state_sts_e;
    assign pl_state_sts_e = RDI_state'(pl_state_sts);

    wire m_done  = (ln == LOG_ACTIVE);
    wire m_error = (ln == LOG_TRAINERROR);

    always @(ln or rdi_sts or pl_state_sts)
        $display("T=%0t | [DIE] ltsm_n=%s rdi_sts=%s pl_state_sts=%s",
                 $time, ln.name(), rdi_sts.name(), pl_state_sts_e.name());

    // =========================================================================
    // Adapter handshake responder (CLK-ack / STALL-ack follow request).
    //   manual_ack_mode=1 hands lp_clk_ack over to the test so it can emulate the
    //   C driver's SLOW GPIO polling (ack only after a delay) and probe whether
    //   pl_clk_req is a held req/ack level or a short self-clearing pulse.
    // =========================================================================
    logic manual_ack_mode = 1'b0;
    logic manual_clk_ack   = 1'b0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin lp_clk_ack <= 1'b0; lp_stallack <= 1'b0; end
        else begin
            lp_clk_ack  <= manual_ack_mode ? manual_clk_ack : pl_clk_req;
            lp_stallack <= pl_stallreq;
        end
    end

    // =========================================================================
    // Scoreboard
    // =========================================================================
    int unsigned fails = 0;
    task automatic chk(bit cond, string msg, int sc);
        if (!cond) begin fails++; $error("[%0t] [SC%0d] CHECK FAILED: %s", $time, sc, msg); end
        else       $display("T=%0t | [SC%0d] PASS: %s", $time, sc, msg);
    endtask

    // =========================================================================
    // Sideband register-write helpers (adapter -> local Reg_File)
    // =========================================================================
    function automatic logic [63:0] build_wr_header(sb_opcode_e op, logic [23:0] addr, logic [7:0] be);
        sb_header_u hdr;
        hdr.raw        = '0;
        hdr.req.opcode = op;
        hdr.req.dstid  = LOCAL_PHY;
        hdr.req.srcid  = ADAPTER;
        hdr.req.addr   = addr;
        hdr.req.be     = be;
        return hdr.raw;
    endfunction

    task automatic send_chunks64(input logic [63:0] header, input logic [63:0] payload);
        @(posedge clk_sb); lp_cfg_vld = 1'b1; lp_cfg = header[31:0];
        @(posedge clk_sb);                    lp_cfg = header[63:32];
        @(posedge clk_sb);                    lp_cfg = payload[31:0];
        @(posedge clk_sb);                    lp_cfg = payload[63:32];
        @(posedge clk_sb); lp_cfg_vld = 1'b0;
    endtask

    task automatic reg_wr_cfg(input logic [23:0] addr, input logic [63:0] data);
        send_chunks64(build_wr_header(SB_64_CFG_WRITE, addr, 8'h0F), data);
    endtask
    task automatic reg_wr_mem(input logic [23:0] addr, input logic [63:0] data);
        send_chunks64(build_wr_header(SB_64_MEM_WRITE, addr, 8'h0F), data);
    endtask

    // Message header (NOT a request) to the REMOTE adapter = main.c step 4.
    function automatic logic [63:0] build_msg_header(sb_opcode_e op, sb_dstid_e dst);
        sb_header_u hdr;
        hdr.raw         = '0;
        hdr.msg.opcode  = op;
        hdr.msg.dstid   = dst;
        hdr.msg.srcid   = ADAPTER;
        hdr.msg.msgcode = msg_code_e'(8'h00);
        hdr.msg.cp      = ^(hdr.raw[61:0]);
        return hdr.raw;
    endfunction

    task automatic program_die(input logic [3:0] target_width = 4'h2,
                               input logic [3:0] target_speed = 4'h5,
                               input bit force_x8 = 1'b0);
        logic [63:0] link_ctrl;
        link_ctrl       = 64'b0;
        link_ctrl[1:0]  = 2'b00;
        link_ctrl[5:2]  = target_width;
        link_ctrl[9:6]  = target_speed;
        link_ctrl[10]   = 1'b1;   // start training (single die)
        reg_wr_mem(OFF_TRAIN_SETUP4, 64'h0000_0000_0032_00A0);
        reg_wr_mem(OFF_PHY_CONTROL,  force_x8 ? 64'h0000_0000_0020_0160 : 64'h0000_0000_0020_0060);
        reg_wr_cfg(OFF_UCIE_LINK_CTRL, link_ctrl);
    endtask

    // =========================================================================
    // Reset / init
    // =========================================================================
    task automatic reset_system();
        rst_n        = 1'b0;
        lp_data='0; lp_irdy=1'b0; lp_valid=1'b0;
        lp_state_req = Nop;
        lp_wake_req  = 1'b0; lp_linkerror = 1'b0;
        lp_cfg='0; lp_cfg_vld=1'b0; lp_cfg_crd=1'b1;
        #20;
        rst_n = 1'b1;
        @(posedge lclk);
        repeat (10) @(posedge lclk);
        $display("T=%0t | [RESET] released, clocks stable.", $time);
    endtask

    task automatic do_bringup(output bit ok, input int tmo = 400000);
        ok = 1'b0;
        lp_state_req = Nop;
        program_die(4'h2, 4'h5, 1'b0);
        fork
            begin wait (ln == LOG_LINKINIT); @(negedge lclk); lp_state_req = Active; end
        join_none
        fork
            begin wait (m_done && pl_state_sts == Active); ok = 1'b1; end
            begin wait (m_error); ok = 1'b0; $error("[bringup] training error"); end
            begin repeat (tmo) @(posedge lclk); ok = 1'b0; $error("[bringup] TIMEOUT (ltsm=%s)", ln.name()); end
        join_any
        disable fork;
    endtask

    task automatic do_data_transfer(output bit pass);
        pass = 1'b0;
        repeat(20) @(posedge lclk);
        lp_valid = 1'b1;
        lp_irdy  = 1'b1;
        lp_data  = {16{32'hDEADBEEF}};
        fork
            begin
                wait (pl_valid && pl_data === {16{32'hDEADBEEF}});
                $display("T=%0t | [DATA] looped DEADBEEF back correctly.", $time);
                pass = 1'b1;
            end
            begin
                repeat (1500) @(posedge lclk);
                $error("T=%0t | [DATA] TIMEOUT -- self-loopback data failed.", $time);
                pass = 1'b0;
            end
        join_any
        disable fork;
        @(negedge lclk);
        lp_valid = 1'b0;
        lp_irdy  = 1'b0;
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    bit ok, data_pass;
    initial begin
        $display("================================================================");
        $display("  digital_ucie SELF-LOOPBACK TESTBENCH (NO ANALOG)");
        $display("================================================================\n");

        $display("\nT=%0t | [SC1] Self-loopback training to ACTIVE...", $time);
        reset_system();
        do_bringup(ok);
        chk(ok, "self-looped digital_ucie reached LOG_ACTIVE", 1);

        if (ok) begin
            $display("\nT=%0t | [SC2] Self-loopback MainBand data transfer...", $time);
            do_data_transfer(data_pass);
            chk(data_pass, "MainBand flit looped back successfully", 2);
        end else begin
            $display("T=%0t | [SC2] Skipped (no ACTIVE).", $time);
        end

        // ---- SC3 : POST-ACTIVE sideband remote-message loopback (PARALLEL bypass = FPGA) ----
        //   Emulates the C driver EXACTLY: after sending, DON'T ack immediately.
        //   Take manual control of lp_clk_ack and probe how long pl_clk_req stays
        //   high with NO ack. The C polls pl_clk_req via EMIO GPIO at ~µs
        //   granularity (~100+ clk_sb cycles). If pl_clk_req is a HELD req/ack
        //   level, the C catches it (not the bug). If it drops on its own before
        //   we ack, a slow poll MISSES it -> reproduces the HW timeout.
        if (ok) begin
            bit sb_msg_back;
            int hi_cycles;
            sb_msg_back = 1'b0;
            hi_cycles   = 0;
            $display("\nT=%0t | [SC3] POST-ACTIVE sideband remote-message loopback (slow-ack probe)...", $time);

            // hand ack control to the test, ack held LOW (like C right after ClkAckClear)
            manual_ack_mode = 1'b1;
            manual_clk_ack  = 1'b0;

            send_chunks64(build_msg_header(SB_MSG_WITH_64_DATA, REMOTE_ADAPTER),
                          64'hDEADBEEF_CAFEF00D);

            // wait for pl_clk_req, then measure how long it stays high WITHOUT ack
            fork
                begin
                    wait (pl_clk_req);
                    $display("T=%0t | [SC3] pl_clk_req asserted; measuring hold WITHOUT ack...", $time);
                    while (pl_clk_req && hi_cycles < 2000) begin
                        @(posedge clk_sb); hi_cycles++;
                    end
                    if (!pl_clk_req)
                        $display("T=%0t | [SC3-PROBE] pl_clk_req DROPPED after %0d clk_sb cycles with NO ack -> PULSE (slow GPIO poll would MISS it)", $time, hi_cycles);
                    else
                        $display("T=%0t | [SC3-PROBE] pl_clk_req still HIGH after %0d cycles with no ack -> HELD req/ack (C would catch it)", $time, hi_cycles);
                end
                begin repeat (3000) @(posedge clk_sb); end
            join_any
            disable fork;

            // now emulate the C finally getting around to acking (slow poll caught it, or forced)
            @(posedge lclk); manual_clk_ack = 1'b1;
            fork
                begin wait (pl_cfg_vld);
                      $display("T=%0t | [SC3] pl_cfg returned: 0x%08h", $time, pl_cfg);
                      sb_msg_back = 1'b1; end
                begin repeat (8000) @(posedge clk_sb);
                      $error("T=%0t | [SC3] TIMEOUT: remote msg never delivered (pl_clk_req=%0b pl_cfg_vld=%0b)",
                             $time, pl_clk_req, pl_cfg_vld); end
            join_any
            disable fork;
            @(posedge lclk); manual_clk_ack = 1'b0; manual_ack_mode = 1'b0;

            chk(sb_msg_back, "sideband remote message looped back to pl_cfg", 3);
        end else begin
            $display("T=%0t | [SC3] Skipped (no ACTIVE).", $time);
        end

        $display("\n================================================================");
        if (fails == 0) $display("  RESULT: PASS  (digital_ucie SELF-LOOPBACK SIM PASS)");
        else            $display("  RESULT: FAIL  (%0d failing checks)", fails);
        $display("================================================================\n");
        $finish;
    end

    initial begin
        #(200_000_000);
        $error("GLOBAL TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule
