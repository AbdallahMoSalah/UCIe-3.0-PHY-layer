`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// Testbench : ucie_phy_loopback_tb
// DUT       : ucie_phy_loopback = ONE UCIe_PHY_wrapper with its own TX lanes
//             folded back into its own RX lanes (MainBand + Sideband).
//
// Goal      : Prove that a single SELF-LOOPED PHY can train to ACTIVE (the
//             two-party-handshake question) and loop MainBand flit data back.
//             The adapter face is driven exactly like the back-to-back
//             UCIe_PHY_wrapper_tb (register-config over sideband + RDI), but
//             for a single die.
//
// Scenarios :
//   SC1 : Bring-up  - program regs over SB -> training -> ACTIVE
//   SC2 : Data loop - send a flit, expect the same flit back (self-loopback)
// =============================================================================

module ucie_phy_loopback_tb;

    localparam int  LTSM_CLK_FRQ = 200_000;   // scaled watchdog
    localparam int  RDI_CLK_FRQ  = 200_000;   // scaled RDI timers
    localparam int  NUM_LANES    = 16;
    localparam int  N_BYTES      = 64;
    localparam int  FLITW        = 8 * N_BYTES;

    // ---- Register offsets ----
    localparam logic [23:0] OFF_UCIE_LINK_CTRL = 24'h000010; // CFG  space
    localparam logic [23:0] OFF_PHY_CONTROL    = 24'h001004; // MMIO space
    localparam logic [23:0] OFF_TRAIN_SETUP4   = 24'h001050; // MMIO space

    // =========================================================================
    // DUT I/O
    // =========================================================================
    logic                 rst_n;
    logic                 lclk;

    logic [FLITW-1:0]     lp_data, pl_data;
    logic                 lp_irdy, lp_valid;
    logic                 pl_trdy, pl_error, pl_valid;

    logic [31:0]          lp_cfg;
    logic                 lp_cfg_vld, lp_cfg_crd, pl_cfg_crd, pl_cfg_vld;
    logic [31:0]          pl_cfg;

    RDI_state             lp_state_req;
    logic                 lp_clk_ack, lp_stallack, lp_wake_req, lp_linkerror;
    RDI_state             pl_state_sts;
    logic                 pl_clk_req, pl_stallreq, pl_wake_ack, pl_trainerror;

    // =========================================================================
    // DUT
    // =========================================================================
    ucie_phy_loopback #(
        .CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES), .MODULE_ID(0)
    ) u_lb (
        .rst_n        (rst_n),
        .lp_data      (lp_data),  .lp_irdy(lp_irdy), .lp_valid(lp_valid),
        .pl_trdy      (pl_trdy),  .pl_error(pl_error),
        .lclk         (lclk),     .pl_data(pl_data), .pl_valid(pl_valid),
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

    // Sideband register-access clock (for chunk timing).
    wire clk_sb = u_lb.u_phy.clk_sb;

    // Shrink the RDI timers so they are simulatable.
    defparam u_lb.u_phy.u_digital_ucie.u_main_sm.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_lb.u_phy.u_digital_ucie.u_main_sm.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;

    // LTSM macro-state observation.
    state_n_e ln;
    assign ln = u_lb.u_phy.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state_n;

    RDI_state rdi_sts;
    assign rdi_sts = u_lb.u_phy.u_digital_ucie.u_main_sm.u_rdi_sm.sm.rdi_state_sts;

    wire m_done  = (ln == LOG_ACTIVE);
    wire m_error = (ln == LOG_TRAINERROR);

    always @(ln or rdi_sts or pl_state_sts)
        $display("T=%0t | [DIE] ltsm_n=%s rdi_sts=%s pl_state_sts=%s",
                 $time, ln.name(), rdi_sts.name(), pl_state_sts.name());

    // =========================================================================
    // Adapter handshake responder (CLK-ack / STALL-ack follow request)
    // =========================================================================
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin lp_clk_ack <= 1'b0; lp_stallack <= 1'b0; end
        else        begin lp_clk_ack <= pl_clk_req; lp_stallack <= pl_stallreq; end
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

    // Program bring-up registers and assert Start-UCIe-Link-Training.
    task automatic program_die(input logic [3:0] target_width = 4'h2,
                               input logic [3:0] target_speed = 4'h5,
                               input bit force_x8 = 1'b0);
        logic [63:0] link_ctrl;
        link_ctrl       = 64'b0;
        link_ctrl[1:0]  = 2'b00;
        link_ctrl[5:2]  = target_width;
        link_ctrl[9:6]  = target_speed;
        link_ctrl[10]   = 1'b1;   // start training (single die starts itself)
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

    // Single-die bring-up to ACTIVE.
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

    // Self-loopback data transfer : send a flit, expect the SAME flit back.
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
        $display("  UCIe_PHY SELF-LOOPBACK TESTBENCH (single instance)");
        $display("================================================================\n");

        // ---- SC1 : bring-up to ACTIVE ----
        $display("\nT=%0t | [SC1] Self-loopback training to ACTIVE...", $time);
        reset_system();
        do_bringup(ok);
        chk(ok, "self-looped die reached LOG_ACTIVE", 1);

        // ---- SC2 : data loopback ----
        if (ok) begin
            $display("\nT=%0t | [SC2] Self-loopback MainBand data transfer...", $time);
            do_data_transfer(data_pass);
            chk(data_pass, "MainBand flit looped back successfully", 2);
        end else begin
            $display("T=%0t | [SC2] Skipped (no ACTIVE).", $time);
        end

        $display("\n================================================================");
        if (fails == 0) $display("  RESULT: PASS  (UCIe_PHY SELF-LOOPBACK SIM PASS)");
        else            $display("  RESULT: FAIL  (%0d failing checks)", fails);
        $display("================================================================\n");
        $finish;
    end

    // Global watchdog
    initial begin
        #(200_000_000);
        $error("GLOBAL TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule
