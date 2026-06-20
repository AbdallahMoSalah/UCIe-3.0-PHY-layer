`timescale 1ns/1ps

import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;
import RDI_SM_pkg::*;

// =============================================================================
// Testbench : Logical_PHY_tb
// DUT       : 2x Logical_PHY connected back-to-back (full UCIe PHY logical layer:
//             MainBand die + SideBand + LTSM + RDI_SM).
//
// Versus MB_SB_LTSM_tb, the RDI state machine is now in-loop: rdi_state is
// produced internally by each die's RDI_SM (no longer forced by the TB).  The
// TB instead drives the RDI adapter face (lp_state_req / lp_clk_ack /
// lp_stallack / lp_wake_req / lp_linkerror) and provides per-die auto
// CLK-ack / STALL-ack responders.
//
// Scenarios:
//   SC1 : happy-path training -> both dies ACTIVE
//   SC2 : watchdog (sideband blocked) -> TRAINERROR
//   SC3 : L1 entry (lp_state_req=L_1) then wake (lp_state_req=Active) re-train
//   SC4 : LinkError injection (lp_linkerror) -> RDI LinkError / LTSM TRAINERROR
// =============================================================================

module Logical_PHY_tb;

    localparam int  LTSM_CLK_FRQ = 200_000;   // scaled: 8ms watchdog ~1600 cyc
    localparam int  RDI_CLK_FRQ  = 200_000;   // scaled RDI timers (1us/16ms)
    localparam int  NUM_LANES    = 16;
    localparam int  N_BYTES      = 64;
    localparam int  FLITW        = 8 * N_BYTES;

    // =========================================================================
    // Per-die signals (0 = die0, 1 = die1)
    // =========================================================================
    // Clocks / LTSM observability
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

    // Training trigger
    logic                 phy_start0, phy_start1;

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
    // DUT instantiations
    // =========================================================================
    Logical_PHY #(.CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES)) u_die0 (
        .rst_n(rst_n),
        .lp_data(lp_data0), .lp_irdy(lp_irdy0), .lp_valid(lp_valid0), .pl_trdy(),
        .lclk(lclk0), .pl_data(o_out_data0), .pl_valid(o_pl_valid0),
        .i_RD_P(i_RD_P0), .i_RVLD_P(i_RVLD_P0), .i_RCKP_P(i_RCKP_P0), .i_RCKN_P(i_RCKN_P0), .i_RTRK_P(i_RTRK_P0),
        .o_TD_P(o_TD_P0), .o_TVLD_P(o_TVLD_P0), .o_TCKP_P(o_TCKP_P0), .o_TCKN_P(o_TCKN_P0), .o_TTRK_P(o_TTRK_P0),
        .RXCKSB(RXCKSB0), .TXCKSB(TXCKSB0), .TXDATASB(TXDATASB0), .RXDATASB(RXDATASB0),
        .lp_cfg(32'h0), .lp_cfg_vld(1'b0), .pl_cfg_crd(), .lp_cfg_crd(1'b1), .pl_cfg(), .pl_cfg_vld(),
        .rf_addr(), .rf_be(), .rf_is_64b_access(), .rf_wdata(), .rd_en(), .wr_en(),
        .rf_rdata(64'h0), .rdata_vld(1'b0), .addr_err_o(1'b0),
        .log0_state_n(), .log0_lane_reversal(), .log0_width_degrade(),
        .log0_state_n_minus_1(), .log0_state_n_minus_2(), .log1_state_n_minus_3(),
        .phy_start_ucie_link_training_ctrl_out(phy_start0), .SPMW(1'b0),
        .reg_phy_x8_mode_ctrl(1'b0),
        .reg_TARR_support_local_cap(1'b1), .reg_L2SPD_support_local_cap(1'b1),
        .reg_PSPT_support_local_cap(1'b1), .reg_PMO_support_local_cap(1'b0),
        .reg_Max_Link_Speed_cap(4'b0101), .reg_Supported_TX_Vswing(5'b00111),
        .reg_so(1'b0), .reg_mtp(1'b1), .reg_Module_ID(2'b00),
        .reg_Clock_Phase_cap(2'b01), .reg_Clock_mode_cap(2'b01),
        .reg_TARR_support_local_ctrl(1'b1), .reg_PMO_support_local_ctrl(1'b0),
        .reg_Clock_Phase_ctrl(1'b1), .reg_Clock_mode_ctrl(1'b1),
        .reg_L2SPD_support_local_ctrl(1'b1), .reg_PSPT_support_local_ctrl(1'b1),
        .reg_Target_Link_Width_ctrl(4'h2), .reg_Target_Link_Speed_ctrl(4'h5),
        .reg_Clock_Phase_enable_status(), .reg_Clock_mode_enable_status(), .reg_TARR_enable_status(),
        .reg_Link_Width_enable_status(), .reg_Link_Speed_enable_status(),
        .reg_PMO_enable_status(), .reg_L2SPD_enable_status(), .reg_PSPT_enable_status(),
        .cfg_max_err_thresh_perlane(12'd10), .cfg_max_err_thresh_aggr(16'd50), .reg_lane_mask(16'h0000),
        .lp_state_req(lp_state_req0), .lp_clk_ack(lp_clk_ack0), .lp_wake_req(lp_wake_req0),
        .lp_stallack(lp_stallack0), .lp_linkerror(lp_linkerror0),
        .pl_clk_req(pl_clk_req0), .pl_stallreq(pl_stallreq0), .pl_wake_ack(pl_wake_ack0),
        .pl_trainerror(pl_trainerror0), .pl_inband_pres(), .pl_phyinrecenter(),
        .pl_state_sts(pl_state_sts0), .pl_max_speedmode(), .pl_speedmode(), .pl_lnk_cfg(),
        .UCIe_Link_DVSEC_UCIe_Link_Capability_7to4(4'h0),
        .UCIe_Link_DVSEC_UCIe_Link_Status_17to11(4'h0),
        .UCIe_Link_DVSEC_UCIe_Link_Status_10to7(4'h0)
    );

    Logical_PHY #(.CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES)) u_die1 (
        .rst_n(rst_n),
        .lp_data(lp_data1), .lp_irdy(lp_irdy1), .lp_valid(lp_valid1), .pl_trdy(),
        .lclk(lclk1), .pl_data(o_out_data1), .pl_valid(o_pl_valid1),
        .i_RD_P(i_RD_P1), .i_RVLD_P(i_RVLD_P1), .i_RCKP_P(i_RCKP_P1), .i_RCKN_P(i_RCKN_P1), .i_RTRK_P(i_RTRK_P1),
        .o_TD_P(o_TD_P1), .o_TVLD_P(o_TVLD_P1), .o_TCKP_P(o_TCKP_P1), .o_TCKN_P(o_TCKN_P1), .o_TTRK_P(o_TTRK_P1),
        .RXCKSB(RXCKSB1), .TXCKSB(TXCKSB1), .TXDATASB(TXDATASB1), .RXDATASB(RXDATASB1),
        .lp_cfg(32'h0), .lp_cfg_vld(1'b0), .pl_cfg_crd(), .lp_cfg_crd(1'b1), .pl_cfg(), .pl_cfg_vld(),
        .rf_addr(), .rf_be(), .rf_is_64b_access(), .rf_wdata(), .rd_en(), .wr_en(),
        .rf_rdata(64'h0), .rdata_vld(1'b0), .addr_err_o(1'b0),
        .log0_state_n(), .log0_lane_reversal(), .log0_width_degrade(),
        .log0_state_n_minus_1(), .log0_state_n_minus_2(), .log1_state_n_minus_3(),
        .phy_start_ucie_link_training_ctrl_out(phy_start1), .SPMW(1'b0),
        .reg_phy_x8_mode_ctrl(1'b0),
        .reg_TARR_support_local_cap(1'b1), .reg_L2SPD_support_local_cap(1'b1),
        .reg_PSPT_support_local_cap(1'b1), .reg_PMO_support_local_cap(1'b0),
        .reg_Max_Link_Speed_cap(4'b0101), .reg_Supported_TX_Vswing(5'b00111),
        .reg_so(1'b0), .reg_mtp(1'b1), .reg_Module_ID(2'b01),
        .reg_Clock_Phase_cap(2'b01), .reg_Clock_mode_cap(2'b01),
        .reg_TARR_support_local_ctrl(1'b1), .reg_PMO_support_local_ctrl(1'b0),
        .reg_Clock_Phase_ctrl(1'b1), .reg_Clock_mode_ctrl(1'b1),
        .reg_L2SPD_support_local_ctrl(1'b1), .reg_PSPT_support_local_ctrl(1'b1),
        .reg_Target_Link_Width_ctrl(4'h2), .reg_Target_Link_Speed_ctrl(4'h5),
        .reg_Clock_Phase_enable_status(), .reg_Clock_mode_enable_status(), .reg_TARR_enable_status(),
        .reg_Link_Width_enable_status(), .reg_Link_Speed_enable_status(),
        .reg_PMO_enable_status(), .reg_L2SPD_enable_status(), .reg_PSPT_enable_status(),
        .cfg_max_err_thresh_perlane(12'd10), .cfg_max_err_thresh_aggr(16'd50), .reg_lane_mask(16'h0000),
        .lp_state_req(lp_state_req1), .lp_clk_ack(lp_clk_ack1), .lp_wake_req(lp_wake_req1),
        .lp_stallack(lp_stallack1), .lp_linkerror(lp_linkerror1),
        .pl_clk_req(pl_clk_req1), .pl_stallreq(pl_stallreq1), .pl_wake_ack(pl_wake_ack1),
        .pl_trainerror(pl_trainerror1), .pl_inband_pres(), .pl_phyinrecenter(),
        .pl_state_sts(pl_state_sts1), .pl_max_speedmode(), .pl_speedmode(), .pl_lnk_cfg(),
        .UCIe_Link_DVSEC_UCIe_Link_Capability_7to4(4'h0),
        .UCIe_Link_DVSEC_UCIe_Link_Status_17to11(4'h0),
        .UCIe_Link_DVSEC_UCIe_Link_Status_10to7(4'h0)
    );

    // Shrink the RDI timers (1us / 16ms) so they are simulatable.
    defparam u_die0.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die0.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;
    defparam u_die1.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die1.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;

    // LTSM macro-state observation.  current_ltsm_state_n was dropped from the
    // Logical_PHY port list during the interface edit; it still lives inside the
    // LTSM wrapper, so observe it hierarchically (same state_n_e type, so all the
    // LOG_* comparisons below are unchanged).
    assign ln0 = u_die0.u_ltsm_top.u_ltsm.current_ltsm_state_n;
    assign ln1 = u_die1.u_ltsm_top.u_ltsm.current_ltsm_state_n;

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

    // Auto-clear the training trigger once out of RESET/NOP
    always @(posedge lclk0) if (ln0 != LOG_RESET && ln0 != LOG_NOP) phy_start0 <= 1'b0;
    always @(posedge lclk1) if (ln1 != LOG_RESET && ln1 != LOG_NOP) phy_start1 <= 1'b0;

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
    // Reset / init
    // =========================================================================
    task automatic reset_system();
        rst_n         = 1'b0;
        phy_start0    = 1'b0; phy_start1    = 1'b0;
        block_sideband= 1'b0;
        corrupt_0to1  = '0;   corrupt_1to0  = '0;
        lp_data0='0; lp_data1='0; lp_irdy0=1'b0; lp_irdy1=1'b0; lp_valid0=1'b0; lp_valid1=1'b0;
        // Adapter holds Nop through training; Active is requested at LINKINIT
        // (the RDI reset FSM needs the Nop->Active edge to start the handshake).
        lp_state_req0 = Nop; lp_state_req1 = Nop;
        lp_wake_req0  = 1'b0;  lp_wake_req1  = 1'b0;
        lp_linkerror0 = 1'b0;  lp_linkerror1 = 1'b0;
        #20;
        rst_n = 1'b1;
        @(posedge lclk0);
        repeat (10) @(posedge lclk0);
        $display("T=%0t | [RESET] released, clocks stable.", $time);
    endtask

    // Adapter bring-up: pulse training, hold Nop through training, request
    // Active once each die reaches LINKINIT; resolve on ACTIVE / error / timeout.
    task automatic do_bringup(output bit ok, input int tmo = 200000);
        ok = 1'b0;
        lp_state_req0 = Nop; lp_state_req1 = Nop;
        phy_start0 = 1'b1;
        fork
            begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
            begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
        join_none
        fork
            // Bring-up is complete when both LTSMs are in ACTIVE *and* both RDI
            // official status outputs (pl_state_sts) have caught up to Active.
            // The LTSM enters ACTIVE off the RDI's internal rdi_state (linkinit_done);
            // that internal state leads pl_state_sts (produced via the
            // signal_transition_detector) by a few cycles, so the post-bringup
            // checks must wait for pl_state_sts too or they race the official state.
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
        $display("  STARTING Logical_PHY INTEGRATION TESTBENCH");
        $display("================================================================\n");

        // ----------------------------------------------------------------
        // SC1: Happy-path training -> both dies ACTIVE
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC1] Happy path bring-up...", $time);
        reset_system();
        do_bringup(ok);
        chk(ok, "SC1 both dies reached LOG_ACTIVE");
        chk(pl_state_sts0 == Active, "SC1 die0 RDI in Active");
        chk(pl_state_sts1 == Active, "SC1 die1 RDI in Active");

        // ----------------------------------------------------------------
        // SC2: Watchdog -> TRAINERROR with sideband blocked
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC2] Watchdog (sideband blocked)...", $time);
        reset_system();
        block_sideband = 1'b1;
        phy_start0 = 1'b1;
        fork
            begin wait (m_error); $display("T=%0t | [SC2] die0 TRAINERROR as expected.", $time); end
            begin wait (m_done);  $error("T=%0t | [SC2] reached ACTIVE with blocked SB?", $time); fails++; end
            begin repeat (5000) @(posedge lclk0);
                  $error("T=%0t | [SC2] TIMEOUT (watchdog did not fire).", $time); fails++; end
        join_any
        disable fork;
        chk(m_error, "SC2 watchdog produced TRAINERROR");

        // ----------------------------------------------------------------
        // SC3: L1 entry then wake/re-train
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC3] L1 entry + wake...", $time);
        reset_system();
        do_bringup(ok);
        chk(ok, "SC3 bring-up to ACTIVE");
        // L1 (PM) entry is a role-asymmetric handshake: one die must be the
        // LP-initiator (lp_state_req=L_1 first -> sends RDI_L1_REQ) and the peer
        // the responder, which has to receive that REQ while still in its active
        // IDLE so it parks in WAIT (FLOW_L1_FROM_ADAPTER) before its own adapter
        // agrees. Driving L_1 on both dies in the same cycle makes both
        // LP-initiators and deadlocks (each waits for an RDI_L1_RSP neither sends).
        // So we stagger: die0 initiates, then die1 agrees once it is parked in WAIT.
        // (timeout_1us never fires at this scaled CLK_FREQ and no LTSM watchdog runs
        // in ACTIVE, so the staggering window is effectively unbounded.)
        $display("T=%0t | [SC3] ACTIVE. die0 initiates L1; die1 responds...", $time);
        @(negedge lclk0);
        lp_state_req0 = L_1;
        // Wait until die1's RDI active SM has received the REQ and parked in WAIT
        // (one-hot WAIT = 26'h0800000 in unit_active_state) before die1 agrees.
        fork
            begin wait (u_die1.u_rdi_sm.sm.u_unit_active_state.current_state == 26'h0800000);
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
        chk(ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2, "SC3 both dies entered L1");

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
        // SC4: LinkError injection
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC4] LinkError injection...", $time);
        reset_system();
        do_bringup(ok);
        chk(ok, "SC4 bring-up to ACTIVE");
        $display("T=%0t | [SC4] ACTIVE. Asserting lp_linkerror on die0...", $time);
        @(negedge lclk0);
        lp_linkerror0 = 1'b1;
        fork
            begin wait (pl_trainerror0); $display("T=%0t | [SC4] die0 RDI asserted pl_trainerror.", $time); end
            begin repeat (8000) @(posedge lclk0); $error("[SC4] TO waiting pl_trainerror"); fails++; end
        join_any
        disable fork;
        chk(pl_trainerror0, "SC4 lp_linkerror -> pl_trainerror");
        chk(pl_state_sts0 == LinkError, "SC4 die0 RDI in LinkError");

        // ----------------------------------------------------------------
        $display("\n================================================================");
        if (fails == 0) $display("  RESULT: PASS  (Logical_PHY INTEGRATION SIM PASS)");
        else            $display("  RESULT: FAIL  (%0d failing checks)", fails);
        $display("================================================================\n");
        $finish;
    end

    // Global watchdog
    initial begin
        #(50_000_000);   // 50 ms sim-time hard stop
        $error("GLOBAL TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule
