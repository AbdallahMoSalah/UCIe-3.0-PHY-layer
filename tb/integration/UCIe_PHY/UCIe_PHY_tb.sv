`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// Testbench : UCIe_PHY_tb
// DUT       : 2x UCIe_PHY connected back-to-back.
//
// UCIe_PHY = Logical_PHY (MainBand die + SideBand + LTSM + RDI_SM) + Reg_File.
//
// The TB acts as the *adapter*.  Per the new top, the only signals it touches
// are:
//     * the physical lanes  (MainBand serial + Sideband serial)  - cross-wired
//       die0<->die1 to model the package channel
//     * the RDI interface   (lp_state_req / lp_clk_ack / lp_stallack /
//       lp_wake_req / lp_linkerror  and the pl_* status outputs)
//     * the adapter config bus (lp_cfg / pl_cfg) used to *write the Register
//       File over sideband packets*  -- there are no reg_*/phy_start strap
//       ports any more; bring-up controls (Start Training, target width/speed,
//       compare thresholds) are programmed into each die's Reg_File via local
//       SB register-write packets (dstid=LOCAL_PHY, srcid=ADAPTER).
//
// All register *observation* is done through the (.) hierarchical operator into
// each die's u_reg_file.
//
// Scenarios:
//   SC1 : Bring-up     - program regs over SB -> training -> both dies ACTIVE
//   SC2 : TrainError   - sideband blocked -> watchdog -> TRAINERROR
//   SC3 : PM mode (L1) - ACTIVE -> L1 entry -> wake -> re-train to ACTIVE
// =============================================================================

module UCIe_PHY_tb;

    localparam int  LTSM_CLK_FRQ = 200_000;   // scaled: 8ms watchdog ~1600 cyc
    localparam int  RDI_CLK_FRQ  = 200_000;   // scaled RDI timers (1us/16ms)
    localparam int  NUM_LANES    = 16;
    localparam int  N_BYTES      = 64;
    localparam int  FLITW        = 8 * N_BYTES;

    // ---- Register offsets (byte offset within space) -------------------------
    localparam logic [23:0] OFF_UCIE_LINK_CTRL = 24'h000010; // CFG  space
    localparam logic [23:0] OFF_PHY_CONTROL     = 24'h001004; // MMIO space
    localparam logic [23:0] OFF_TRAIN_SETUP4    = 24'h001050; // MMIO space

    // =========================================================================
    // Per-die signals (0 = die0, 1 = die1)
    // =========================================================================
    logic                 lclk0,  lclk1;
    state_n_e             ln0,    ln1;     // current_ltsm_state_n

    // MainBand serial
    logic [NUM_LANES-1:0] o_TD_P0, o_TD_P1, i_RD_P0, i_RD_P1;
    logic                 o_TVLD_P0, o_TVLD_P1, i_RVLD_P0, i_RVLD_P1;
    logic                 o_TCKP_P0, o_TCKP_P1, i_RCKP_P0, i_RCKP_P1;
    logic                 o_TCKN_P0, o_TCKN_P1, i_RCKN_P0, i_RCKN_P1;
    logic                 o_TTRK_P0, o_TTRK_P1, i_RTRK_P0, i_RTRK_P1;

    // Sideband serial
    logic                 TXCKSB0, TXCKSB1, RXCKSB0, RXCKSB1;
    logic                 TXDATASB0, TXDATASB1, RXDATASB0, RXDATASB1;

    // MainBand flit data
    logic [FLITW-1:0]     lp_data0, lp_data1, o_out_data0, o_out_data1;
    logic                 lp_valid0, lp_valid1, lp_irdy0, lp_irdy1;
    logic                 o_pl_valid0, o_pl_valid1;

    // Adapter config bus (register access over sideband)
    logic [31:0]          lp_cfg [2];
    logic                 lp_cfg_vld [2];
    logic                 lp_cfg_crd [2];

    // RDI adapter face
    RDI_state             lp_state_req0, lp_state_req1;
    logic                 lp_clk_ack0,   lp_clk_ack1;
    logic                 lp_stallack0,  lp_stallack1;
    logic                 lp_wake_req0,  lp_wake_req1;
    logic                 lp_linkerror0, lp_linkerror1;

    RDI_state             pl_state_sts0, pl_state_sts1;
    logic                 pl_clk_req0,   pl_clk_req1;
    logic                 pl_stallreq0,  pl_stallreq1;
    logic                 pl_trainerror0,pl_trainerror1;
    logic                 pl_wake_ack0,  pl_wake_ack1;

    // =========================================================================
    // System control / channel modeling
    // =========================================================================
    logic                 rst_n;
    logic                 block_sideband;
    logic [NUM_LANES-1:0] corrupt_0to1, corrupt_1to0;

    // Sideband cross-connect
    assign RXCKSB0   = block_sideband ? 1'b0 : TXCKSB1;
    assign RXDATASB0 = block_sideband ? 1'b0 : TXDATASB1;
    assign RXCKSB1   = block_sideband ? 1'b0 : TXCKSB0;
    assign RXDATASB1 = block_sideband ? 1'b0 : TXDATASB0;

    // MainBand data cross-connect (with optional corruption)
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            i_RD_P1[i] = corrupt_0to1[i] ? 1'b0 : o_TD_P0[i];
            i_RD_P0[i] = corrupt_1to0[i] ? 1'b0 : o_TD_P1[i];
        end
    end
    assign i_RVLD_P1 = o_TVLD_P0;  assign i_RVLD_P0 = o_TVLD_P1;
    assign i_RCKP_P1 = o_TCKP_P0;  assign i_RCKP_P0 = o_TCKP_P1;
    assign i_RCKN_P1 = o_TCKN_P0;  assign i_RCKN_P0 = o_TCKN_P1;
    assign i_RTRK_P1 = o_TTRK_P0;  assign i_RTRK_P0 = o_TTRK_P1;

    // =========================================================================
    // DUT instantiations  (only RDI + lanes + cfg bus are touched)
    // =========================================================================
    UCIe_PHY #(.CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES), .MODULE_ID(0)) u_die0 (
        .rst_n(rst_n),
        .lp_data(lp_data0), .lp_irdy(lp_irdy0), .lp_valid(lp_valid0), .pl_trdy(), .pl_error(),
        .lclk(lclk0), .pl_data(o_out_data0), .pl_valid(o_pl_valid0),
        .i_RD_P(i_RD_P0), .i_RVLD_P(i_RVLD_P0), .i_RCKP_P(i_RCKP_P0), .i_RCKN_P(i_RCKN_P0), .i_RTRK_P(i_RTRK_P0),
        .o_TD_P(o_TD_P0), .o_TVLD_P(o_TVLD_P0), .o_TCKP_P(o_TCKP_P0), .o_TCKN_P(o_TCKN_P0), .o_TTRK_P(o_TTRK_P0),
        .RXCKSB(RXCKSB0), .TXCKSB(TXCKSB0), .TXDATASB(TXDATASB0), .RXDATASB(RXDATASB0),
        .lp_cfg(lp_cfg[0]), .lp_cfg_vld(lp_cfg_vld[0]), .pl_cfg_crd(), .lp_cfg_crd(lp_cfg_crd[0]), .pl_cfg(), .pl_cfg_vld(),
        .lp_state_req(lp_state_req0), .lp_clk_ack(lp_clk_ack0), .lp_wake_req(lp_wake_req0),
        .lp_stallack(lp_stallack0), .lp_linkerror(lp_linkerror0),
        .pl_clk_req(pl_clk_req0), .pl_stallreq(pl_stallreq0), .pl_wake_ack(pl_wake_ack0),
        .pl_trainerror(pl_trainerror0), .pl_inband_pres(), .pl_phyinrecenter(),
        .pl_state_sts(pl_state_sts0), .pl_max_speedmode(), .pl_speedmode(), .pl_lnk_cfg()
    );

    UCIe_PHY #(.CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES), .MODULE_ID(1)) u_die1 (
        .rst_n(rst_n),
        .lp_data(lp_data1), .lp_irdy(lp_irdy1), .lp_valid(lp_valid1), .pl_trdy(), .pl_error(),
        .lclk(lclk1), .pl_data(o_out_data1), .pl_valid(o_pl_valid1),
        .i_RD_P(i_RD_P1), .i_RVLD_P(i_RVLD_P1), .i_RCKP_P(i_RCKP_P1), .i_RCKN_P(i_RCKN_P1), .i_RTRK_P(i_RTRK_P1),
        .o_TD_P(o_TD_P1), .o_TVLD_P(o_TVLD_P1), .o_TCKP_P(o_TCKP_P1), .o_TCKN_P(o_TCKN_P1), .o_TTRK_P(o_TTRK_P1),
        .RXCKSB(RXCKSB1), .TXCKSB(TXCKSB1), .TXDATASB(TXDATASB1), .RXDATASB(RXDATASB1),
        .lp_cfg(lp_cfg[1]), .lp_cfg_vld(lp_cfg_vld[1]), .pl_cfg_crd(), .lp_cfg_crd(lp_cfg_crd[1]), .pl_cfg(), .pl_cfg_vld(),
        .lp_state_req(lp_state_req1), .lp_clk_ack(lp_clk_ack1), .lp_wake_req(lp_wake_req1),
        .lp_stallack(lp_stallack1), .lp_linkerror(lp_linkerror1),
        .pl_clk_req(pl_clk_req1), .pl_stallreq(pl_stallreq1), .pl_wake_ack(pl_wake_ack1),
        .pl_trainerror(pl_trainerror1), .pl_inband_pres(), .pl_phyinrecenter(),
        .pl_state_sts(pl_state_sts1), .pl_max_speedmode(), .pl_speedmode(), .pl_lnk_cfg()
    );

    // Sideband register-access clock (exposed inside each die) for chunk timing.
    wire clk_sb0 = u_die0.clk_sb;
    wire clk_sb1 = u_die1.clk_sb;

    // Shrink the RDI timers (1us / 16ms) so they are simulatable.
    defparam u_die0.u_logical_phy.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die0.u_logical_phy.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;
    defparam u_die1.u_logical_phy.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die1.u_logical_phy.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;

    // LTSM macro-state observation (state_n lives inside the LTSM wrapper).
    assign ln0 = u_die0.u_logical_phy.u_ltsm_top.u_ltsm.current_ltsm_state_n;
    assign ln1 = u_die1.u_logical_phy.u_ltsm_top.u_ltsm.current_ltsm_state_n;

    // =========================================================================
    // Per-die adapter handshake responders (CLK-ack / STALL-ack follow request)
    // =========================================================================
    always @(posedge lclk0 or negedge rst_n) begin
        if (!rst_n) begin lp_clk_ack0 <= 1'b0; lp_stallack0 <= 1'b0; end
        else        begin lp_clk_ack0 <= pl_clk_req0; lp_stallack0 <= pl_stallreq0; end
    end
    always @(posedge lclk1 or negedge rst_n) begin
        if (!rst_n) begin lp_clk_ack1 <= 1'b0; lp_stallack1 <= 1'b0; end
        else        begin lp_clk_ack1 <= pl_clk_req1; lp_stallack1 <= pl_stallreq1; end
    end

    // Observability
    wire m_done  = (ln0 == LOG_ACTIVE);
    wire p_done  = (ln1 == LOG_ACTIVE);
    wire m_error = (ln0 == LOG_TRAINERROR);
    wire p_error = (ln1 == LOG_TRAINERROR);

    always @(ln0) $display("T=%0t | [DIE0] ltsm_n=%s rdi=%s", $time, ln0.name(), pl_state_sts0.name());
    always @(ln1) $display("T=%0t | [DIE1] ltsm_n=%s rdi=%s", $time, ln1.name(), pl_state_sts1.name());

    // =========================================================================
    // Scoreboard
    // =========================================================================
    int unsigned fails = 0;
    task automatic chk(bit cond, string msg);
        if (!cond) begin fails++; $error("[%0t] CHECK FAILED: %s", $time, msg); end
        else       $display("T=%0t | PASS: %s", $time, msg);
    endtask

    // =========================================================================
    // Sideband register-write helpers  (adapter -> local Reg_File)
    // -------------------------------------------------------------------------
    // Build a 64-bit register-access REQUEST header and stream it (with the
    // 64-bit payload) as four 32-bit lp_cfg chunks.  dstid=LOCAL_PHY makes the
    // RDI router deliver it to the local Reg_Access -> Reg_File.
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

    // One clk_sb edge of the selected die.
    task automatic sb_edge(input int die);
        if (die == 0) @(posedge clk_sb0); else @(posedge clk_sb1);
    endtask

    // Stream header+payload as 4 chunks (64-bit write).
    task automatic send_chunks64(input int die, input logic [63:0] header, input logic [63:0] payload);
        sb_edge(die); lp_cfg_vld[die] = 1'b1; lp_cfg[die] = header[31:0];
        sb_edge(die);                          lp_cfg[die] = header[63:32];
        sb_edge(die);                          lp_cfg[die] = payload[31:0];
        sb_edge(die);                          lp_cfg[die] = payload[63:32];
        sb_edge(die); lp_cfg_vld[die] = 1'b0;
    endtask

    // CFG-space 64-bit write (space bit = 0).
    task automatic reg_wr_cfg(input int die, input logic [23:0] addr, input logic [63:0] data);
        send_chunks64(die, build_wr_header(SB_64_CFG_WRITE, addr, 8'h0F), data);
    endtask
    // MMIO-space 64-bit write (space bit = 1).
    task automatic reg_wr_mem(input int die, input logic [23:0] addr, input logic [63:0] data);
        send_chunks64(die, build_wr_header(SB_64_MEM_WRITE, addr, 8'h0F), data);
    endtask

    // Program one die's bring-up registers and assert Start-UCIe-Link-Training.
    //   * Training Setup 4 : per-lane=10, aggregate=50 compare thresholds
    //   * PHY Control      : Rx clk mode[5]=1, Rx clk phase[6]=1, TARR[21]=1
    //   * UCIe Link Control: target width[5:2]=2, target speed[9:6]=5,
    //                        Start UCIe Link Training[10]=1
    task automatic program_die(input int die);
        reg_wr_mem(die, OFF_TRAIN_SETUP4, 64'h0000_0000_0032_00A0); // aggr=50<<16 | perlane=10<<4
        reg_wr_mem(die, OFF_PHY_CONTROL,  64'h0000_0000_0020_0060); // [5],[6],[21]
        reg_wr_cfg(die, OFF_UCIE_LINK_CTRL,64'h0000_0000_0000_0548); // w=2,s=5,start=1
    endtask

    // =========================================================================
    // Reset / init
    // =========================================================================
    task automatic reset_system();
        rst_n         = 1'b0;
        block_sideband= 1'b0;
        corrupt_0to1  = '0;   corrupt_1to0  = '0;
        lp_data0='0; lp_data1='0; lp_irdy0=1'b0; lp_irdy1=1'b0; lp_valid0=1'b0; lp_valid1=1'b0;
        lp_state_req0 = Nop; lp_state_req1 = Nop;
        lp_wake_req0  = 1'b0;  lp_wake_req1  = 1'b0;
        lp_linkerror0 = 1'b0;  lp_linkerror1 = 1'b0;
        // adapter grants config credit continuously; no cfg in flight
        lp_cfg[0]='0; lp_cfg[1]='0; lp_cfg_vld[0]=1'b0; lp_cfg_vld[1]=1'b0;
        lp_cfg_crd[0]=1'b1; lp_cfg_crd[1]=1'b1;
        #20;
        rst_n = 1'b1;
        @(posedge lclk0);
        repeat (10) @(posedge lclk0);
        $display("T=%0t | [RESET] released, clocks stable.", $time);
    endtask

    // Adapter bring-up: program both dies' Reg_Files over sideband (which sets
    // Start-UCIe-Link-Training), hold Nop through training, request Active once
    // each die reaches LINKINIT; resolve on ACTIVE / error / timeout.
    task automatic do_bringup(output bit ok, input int tmo = 300000);
        ok = 1'b0;
        lp_state_req0 = Nop; lp_state_req1 = Nop;
        fork
            program_die(0);
            program_die(1);
        join
        fork
            begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
            begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
        join_none
        fork
            begin wait (m_done && p_done &&
                        pl_state_sts0 == Active && pl_state_sts1 == Active); ok = 1'b1; end
            begin wait (m_error || p_error); ok = 1'b0; $error("[bringup] training error"); end
            begin repeat (tmo) @(posedge lclk0); ok = 1'b0; $error("[bringup] TIMEOUT"); end
        join_any
        disable fork;
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    bit ok;
    initial begin
        $display("================================================================");
        $display("  STARTING UCIe_PHY INTEGRATION TESTBENCH (Logical_PHY + Reg_File)");
        $display("  Adapter programs Reg_File over sideband; observes via (.)");
        $display("================================================================\n");

        // ----------------------------------------------------------------
        // SC1: Bring-up -> both dies ACTIVE
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC1] Bring-up (SB register programming)...", $time);
        reset_system();
        do_bringup(ok);
        chk(ok, "SC1 both dies reached LOG_ACTIVE");
        chk(pl_state_sts0 == Active, "SC1 die0 RDI in Active");
        chk(pl_state_sts1 == Active, "SC1 die1 RDI in Active");
        // Observe the register file via (.) : Start-Training got latched, and
        // the target width/speed we wrote are reflected.
        $display("T=%0t | [SC1] die0 UCIe_Link_Control=%08h  PHY_Status=%08h",
                 $time, u_die0.u_reg_file.ucie_link_ctrl_r, u_die0.phy_status_r_out);
        chk(u_die0.u_reg_file.ucie_link_ctrl_r[5:2] == 4'h2, "SC1 die0 target width programmed (=2)");
        chk(u_die0.u_reg_file.ucie_link_ctrl_r[9:6] == 4'h5, "SC1 die0 target speed programmed (=5)");

        // ----------------------------------------------------------------
        // SC2: TrainError -> watchdog with sideband blocked
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC2] TrainError (sideband blocked)...", $time);
        reset_system();
        block_sideband = 1'b1;
        // Still program Start-Training locally (sideband packets route LOCAL_PHY,
        // so the local Reg_File write succeeds even with the inter-die SB blocked).
        fork program_die(0); program_die(1); join
        fork
            begin wait (m_error); $display("T=%0t | [SC2] die0 TRAINERROR as expected.", $time); end
            begin wait (m_done);  $error("T=%0t | [SC2] reached ACTIVE with blocked SB?", $time); fails++; end
            begin repeat (8000) @(posedge lclk0);
                  $error("T=%0t | [SC2] TIMEOUT (watchdog did not fire).", $time); fails++; end
        join_any
        disable fork;
        chk(m_error, "SC2 watchdog produced TRAINERROR");

        // ----------------------------------------------------------------
        // SC3: PM mode (L1) entry then wake/re-train
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC3] PM mode (L1) entry + wake...", $time);
        reset_system();
        do_bringup(ok);
        chk(ok, "SC3 bring-up to ACTIVE");
        // L1 (PM) entry is a role-asymmetric handshake: die0 initiates, die1
        // responds once it has parked in WAIT.
        $display("T=%0t | [SC3] ACTIVE. die0 initiates L1; die1 responds...", $time);
        @(negedge lclk0);
        lp_state_req0 = L_1;
        fork
            begin wait (u_die1.u_logical_phy.u_rdi_sm.sm.u_unit_active_state.current_state == 26'h0800000);
                  @(negedge lclk1); lp_state_req1 = L_1; end
            begin repeat (8000) @(posedge lclk0); $error("[SC3] TO: die1 never reached WAIT"); fails++; end
        join_any
        disable fork;
        fork
            begin wait (ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2);
                  $display("T=%0t | [SC3] both dies in L1.", $time); end
            begin repeat (8000) @(posedge lclk0); $error("[SC3] TO entering L1"); fails++; end
        join_any
        disable fork;
        chk(ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2, "SC3 both dies entered L1 (PM)");

        // Wake: request Active again -> re-train back to ACTIVE
        @(negedge lclk0);
        lp_state_req0 = Active; lp_state_req1 = Active;
        fork
            begin wait (m_done && p_done); $display("T=%0t | [SC3] re-trained to ACTIVE after L1.", $time); end
            begin wait (m_error || p_error); $error("[SC3] err during wake"); fails++; end
            begin repeat (100000) @(posedge lclk0); $error("[SC3] TO during wake"); fails++; end
        join_any
        disable fork;
        chk(m_done && p_done, "SC3 L1 wake re-trained to ACTIVE");

        // ----------------------------------------------------------------
        $display("\n================================================================");
        if (fails == 0) $display("  RESULT: PASS  (UCIe_PHY INTEGRATION SIM PASS)");
        else            $display("  RESULT: FAIL  (%0d failing checks)", fails);
        $display("================================================================\n");
        $finish;
    end

    // Global watchdog
    initial begin
        #(80_000_000);   // 80 ms sim-time hard stop
        $error("GLOBAL TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule