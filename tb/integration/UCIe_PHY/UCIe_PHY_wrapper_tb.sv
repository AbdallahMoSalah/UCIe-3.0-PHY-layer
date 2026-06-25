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

module UCIe_PHY_wrapper_tb;

    localparam int  LTSM_CLK_FRQ = 200_000;   // scaled: 8ms watchdog ~1600 cyc
    localparam int  RDI_CLK_FRQ  = 200_000;   // scaled RDI timers (1us/16ms)
    localparam bit  RUN_SC2      = 1'b0;       // SC2 needs a real 8 ms watchdog fire (~8 ms sim); off to save time
    localparam int  NUM_LANES    = 16;
    localparam int  N_BYTES      = 64;
    localparam int  FLITW        = 8 * N_BYTES;

    // ---- Register offsets (byte offset within space) -------------------------
    localparam logic [23:0] OFF_UCIE_LINK_CTRL = 24'h000010; // CFG  space
    localparam logic [23:0] OFF_PHY_CONTROL     = 24'h001004; // MMIO space
    localparam logic [23:0] OFF_TRAIN_SETUP4    = 24'h001050; // MMIO space
    //---------------------------------------------------------------------------
    //
    //---------------------------------------------------------------------------
    bit [30:1] enabled_scenarios = 30'b0;
    localparam sc = 8; // SC1
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
    logic                 reverse_lanes_0to1;
    logic                 reverse_lanes_1to0;
    logic                 rx_vld_error_inject_0_to_1;

    // Sideband cross-connect
    assign RXCKSB0   = block_sideband ? 1'b0 : TXCKSB1;
    assign RXDATASB0 = block_sideband ? 1'b0 : TXDATASB1;
    assign RXCKSB1   = block_sideband ? 1'b0 : TXCKSB0;
    assign RXDATASB1 = block_sideband ? 1'b0 : TXDATASB0;

    // MainBand data cross-connect (with optional corruption and reversal)
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            i_RD_P1[i] = corrupt_0to1[i] ? 1'b0 : (reverse_lanes_0to1 ? o_TD_P0[NUM_LANES-1-i] : o_TD_P0[i]);
            i_RD_P0[i] = corrupt_1to0[i] ? 1'b0 : (reverse_lanes_1to0 ? o_TD_P1[NUM_LANES-1-i] : o_TD_P1[i]);
        end
    end
    assign i_RVLD_P1 = o_TVLD_P0 ^ rx_vld_error_inject_0_to_1;  assign i_RVLD_P0 = o_TVLD_P1;
    assign i_RCKP_P1 = o_TCKP_P0;  assign i_RCKP_P0 = o_TCKP_P1;
    assign i_RCKN_P1 = o_TCKN_P0;  assign i_RCKN_P0 = o_TCKN_P1;
    assign i_RTRK_P1 = o_TTRK_P0;  assign i_RTRK_P0 = o_TTRK_P1;

    // =========================================================================
    // DUT instantiations  (only RDI + lanes + cfg bus are touched)
    // =========================================================================
    UCIe_PHY_wrapper #(.CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES), .MODULE_ID(0)) u_die0 (
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

    UCIe_PHY_wrapper #(.CLK_FRQ_HZ(LTSM_CLK_FRQ), .NUM_LANES(NUM_LANES), .MODULE_ID(1)) u_die1 (
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
    defparam u_die0.u_digital_ucie.u_main_sm.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die0.u_digital_ucie.u_main_sm.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;
    defparam u_die1.u_digital_ucie.u_main_sm.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die1.u_digital_ucie.u_main_sm.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;

    // The 8 ms LTSM watchdog is now SPEED_AWARE in RTL (timeout_counter derives
    // its cycle count from mb_pll_speed_sel, gated_lclk = mb_PLL/16), so it is a
    // true 8 ms at any negotiated speed without any TB override.

    // LTSM macro-state observation (state_n lives inside the LTSM wrapper).
    assign ln0 = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state_n;
    assign ln1 = u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state_n;

    // Internal RDI state that drives the LTSM (wrapper_sm.rdi_state_sts).  This
    // is distinct from pl_state_sts, which is the *lagging* RDI status output.
    RDI_state rdi_sts0, rdi_sts1;
    assign rdi_sts0 = u_die0.u_digital_ucie.u_main_sm.u_rdi_sm.sm.rdi_state_sts;
    assign rdi_sts1 = u_die1.u_digital_ucie.u_main_sm.u_rdi_sm.sm.rdi_state_sts;

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

    // Print a full snapshot whenever any of the three observed states changes:
    //   ltsm_n        : LTSM macro state
    //   rdi_sts       : internal RDI state (drives the LTSM)
    //   pl_state_sts  : pl_state_sts, the lagging RDI status output
    always @(ln0 or rdi_sts0 or pl_state_sts0)
        $display("T=%0t | [DIE0] ltsm_n=%s rdi_sts=%s pl_state_sts=%s",
                 $time, ln0.name(), rdi_sts0.name(), pl_state_sts0.name());
    always @(ln1 or rdi_sts1 or pl_state_sts1)
        $display("T=%0t | [DIE1] ltsm_n=%s rdi_sts=%s pl_state_sts=%s",
                 $time, ln1.name(), rdi_sts1.name(), pl_state_sts1.name());

    // =========================================================================
    // Scoreboard
    // =========================================================================
    int unsigned fails = 0;
    task automatic chk(bit cond, string msg, int sc);
        if (!cond) begin fails++; $error("[%0t] [SC%0d] CHECK FAILED: %s", $time, sc, msg); end
        else       $display("T=%0t | [SC%0d] PASS: %s", $time, sc, msg);
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
    task automatic program_die_custom(input int die, input logic [3:0] target_width = 4'h2, input logic [3:0] target_speed = 4'h5, input bit force_x8 = 1'b0);
        logic [63:0] link_ctrl;
        link_ctrl = 64'b0;
        link_ctrl[1:0] = 2'b00;
        link_ctrl[5:2] = target_width;
        link_ctrl[9:6] = target_speed;
        // Start UCIe Link Training is asserted on ONE die only (die0).  The
        // other die follows via the sideband bring-up handshake.  Applied here
        // so it holds for every scenario that programs the dies.
        link_ctrl[10]  = (die == 0) ? 1'b1 : 1'b0; // start training (die0 only)
        reg_wr_mem(die, OFF_TRAIN_SETUP4, 64'h0000_0000_0032_00A0); // aggr=50<<16 | perlane=10<<4
        reg_wr_mem(die, OFF_PHY_CONTROL,  force_x8 ? 64'h0000_0000_0020_0160 : 64'h0000_0000_0020_0060);
        reg_wr_cfg(die, OFF_UCIE_LINK_CTRL, link_ctrl);
    endtask

    task automatic program_die(input int die);
        program_die_custom(die, 4'h2, 4'h5, 1'b0);
    endtask

    // =========================================================================
    // Reset / init
    // =========================================================================
    task automatic reset_system();
        rst_n         = 1'b0;
        block_sideband= 1'b0;
        corrupt_0to1  = '0;   corrupt_1to0  = '0;
        reverse_lanes_0to1 = 1'b0;
        reverse_lanes_1to0 = 1'b0;
        rx_vld_error_inject_0_to_1 = 1'b0;
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

    // Adapter bring-up: program both dies' Reg_Files over sideband
    task automatic do_bringup_custom(
        output bit ok,
        input logic [3:0] target_width0 = 4'h2,
        input logic [3:0] target_width1 = 4'h2,
        input bit force_x8_0 = 1'b0,
        input bit force_x8_1 = 1'b0,
        input logic [3:0] target_speed0 = 4'h5,
        input logic [3:0] target_speed1 = 4'h5,
        input int tmo = 300000
    );
        ok = 1'b0;
        lp_state_req0 = Nop; lp_state_req1 = Nop;
        fork
            program_die_custom(0, target_width0, target_speed0, force_x8_0);
            program_die_custom(1, target_width1, target_speed1, force_x8_1);
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

    task automatic do_bringup(output bit ok, input int tmo = 300000);
        do_bringup_custom(ok, 4'h2, 4'h2, 1'b0, 1'b0, 4'h5, 4'h5, tmo);
    endtask

    // =========================================================================
    // Diagnostic print and data transfer helper tasks
    // =========================================================================
    // =========================================================================
    // Speed-code → human-readable helper
    // =========================================================================
    function automatic string speed_str(logic [3:0] code);
        case (code)
            4'h0: return "Gen1  (4 GT/s)";
            4'h1: return "Gen2  (8 GT/s)";
            4'h2: return "Gen3  (12 GT/s)";
            4'h3: return "Gen4  (16 GT/s)";
            4'h4: return "Gen5  (24 GT/s)";
            4'h5: return "Gen6  (32 GT/s)";
            4'h6: return "Gen7  (48 GT/s)";
            4'h7: return "Gen8  (64 GT/s)";
            default: return "Unknown";
        endcase
    endfunction

    task automatic print_active_status();
        logic [2:0] tx_mask0, rx_mask0;
        logic [2:0] tx_mask1, rx_mask1;
        logic [3:0] width_sts0, width_sts1;
        logic [3:0] speed_sts0, speed_sts1;

        tx_mask0   = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.mb_tx_data_lane_mask;
        rx_mask0   = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.mb_rx_data_lane_mask;
        tx_mask1   = u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.mb_tx_data_lane_mask;
        rx_mask1   = u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.mb_rx_data_lane_mask;
        width_sts0 = u_die0.u_digital_ucie.ucie_link_status_r_out[10:7];
        width_sts1 = u_die1.u_digital_ucie.ucie_link_status_r_out[10:7];
        // Speed: read directly from LTSM (ucie_link_status_r_out[14:11] is not wired)
        speed_sts0 = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
        speed_sts1 = u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;

        $display("\n================================================================");
        $display("  ACTIVE LINK STATUS REPORT");
        $display("================================================================");
        $display("  [DIE 0] state=%s, RDI_sts=%s", ln0.name(), pl_state_sts0.name());
        $display("          Width : %s (code: %0h)",
                  (width_sts0 == 4'h2) ? "x16" : (width_sts0 == 4'h1) ? "x8" : (width_sts0 == 4'h0) ? "x4" : "unknown", width_sts0);
        $display("          Speed : %s (code: %0h)", speed_str(speed_sts0), speed_sts0);
        $display("          TX Lane Mask: 3'b%b, RX Lane Mask: 3'b%b", tx_mask0, rx_mask0);
        $display("          Active Deser Lanes (RX): 16'h%h", u_die0.mb_rx_data_deser_en);
        $display("          Lane Reversal: %b  Width Degrade: %b",
                  u_die0.u_digital_ucie.log0_lane_reversal, u_die0.u_digital_ucie.log0_width_degrade);
        $display("  [DIE 1] state=%s, RDI_sts=%s", ln1.name(), pl_state_sts1.name());
        $display("          Width : %s (code: %0h)",
                  (width_sts1 == 4'h2) ? "x16" : (width_sts1 == 4'h1) ? "x8" : (width_sts1 == 4'h0) ? "x4" : "unknown", width_sts1);
        $display("          Speed : %s (code: %0h)", speed_str(speed_sts1), speed_sts1);
        $display("          TX Lane Mask: 3'b%b, RX Lane Mask: 3'b%b", tx_mask1, rx_mask1);
        $display("          Active Deser Lanes (RX): 16'h%h", u_die1.mb_rx_data_deser_en);
        $display("          Lane Reversal: %b  Width Degrade: %b",
                  u_die1.u_digital_ucie.log0_lane_reversal, u_die1.u_digital_ucie.log0_width_degrade);
        $display("================================================================\n");
    endtask

    // =========================================================================
    // Width-code decoders for human-readable output
    // =========================================================================
    function automatic string width_ctrl_str(logic [3:0] code);
        case (code)
            4'h1: return "x8";
            4'h2: return "x16";
            4'h3: return "x32";
            4'h4: return "x64";
            4'h5: return "x128";
            4'h6: return "x256";
            default: return "Reserved/Unknown";
        endcase
    endfunction

    function automatic string width_cap_str(logic [2:0] code);
        case (code)
            3'h0: return "x16";
            3'h1: return "x32";
            3'h2: return "x64";
            3'h3: return "x128";
            3'h4: return "x256";
            3'h7: return "x8";
            default: return "Reserved/Unknown";
        endcase
    endfunction

    // =========================================================================
    // Print the programmed control parameters read from Reg_File.
    // Waits 100 cycles to allow the Sideband transactions to complete.
    // =========================================================================
    task automatic print_ctrl_regs();
        logic [31:0] ctrl0, ctrl1;
        logic [31:0] phy_ctrl0, phy_ctrl1;
        logic [31:0] cap0, cap1;
        
        // Wait for sideband writes to propagate to Reg_File
        repeat (100) @(posedge lclk0);
        
        ctrl0     = u_die0.u_digital_ucie.u_reg_file.ucie_link_ctrl_r_out;
        phy_ctrl0 = u_die0.u_digital_ucie.u_reg_file.phy_control_r_out;
        cap0      = u_die0.u_digital_ucie.u_reg_file.ucie_link_cap_r_out;
        
        ctrl1     = u_die1.u_digital_ucie.u_reg_file.ucie_link_ctrl_r_out;
        phy_ctrl1 = u_die1.u_digital_ucie.u_reg_file.phy_control_r_out;
        cap1      = u_die1.u_digital_ucie.u_reg_file.ucie_link_cap_r_out;

        $display("  ================ REGFILE VALUES (Read Hierarchically) ================");
        $display("  [DIE 0] Link Control Reg: 32'h%h", ctrl0);
        $display("          - Target Width [5:2]: 4'h%0h (%s)", ctrl0[5:2], width_ctrl_str(ctrl0[5:2]));
        $display("          - Target Speed [9:6]: 4'h%0h (%s)", ctrl0[9:6], speed_str(ctrl0[9:6]));
        $display("          - Start Training[10]: %b", ctrl0[10]);
        $display("          PHY Control Reg : 32'h%h", phy_ctrl0);
        $display("          - Force x8 Mode  [8]: %b", phy_ctrl0[8]);
        $display("          Link Capability : 32'h%h", cap0);
        $display("          - Max Width    [3:1]: 3'h%0h (%s)", cap0[3:1], width_cap_str(cap0[3:1]));
        $display("          - Max Speed    [7:4]: 4'h%0h (%s)", cap0[7:4], speed_str(cap0[7:4]));
        $display("  ----------------------------------------------------------------------");
        $display("  [DIE 1] Link Control Reg: 32'h%h", ctrl1);
        $display("          - Target Width [5:2]: 4'h%0h (%s)", ctrl1[5:2], width_ctrl_str(ctrl1[5:2]));
        $display("          - Target Speed [9:6]: 4'h%0h (%s)", ctrl1[9:6], speed_str(ctrl1[9:6]));
        $display("          - Start Training[10]: %b", ctrl1[10]);
        $display("          PHY Control Reg : 32'h%h", phy_ctrl1);
        $display("          - Force x8 Mode  [8]: %b", phy_ctrl1[8]);
        $display("          Link Capability : 32'h%h", cap1);
        $display("          - Max Width    [3:1]: 3'h%0h (%s)", cap1[3:1], width_cap_str(cap1[3:1]));
        $display("          - Max Speed    [7:4]: 4'h%0h (%s)", cap1[7:4], speed_str(cap1[7:4]));
        $display("  ======================================================================\n");
    endtask

    task automatic do_data_transfer(output bit pass);
        pass = 1'b0;
        repeat(20) @(posedge lclk0);
        
        lp_valid0 = 1'b1;
        lp_irdy0 = 1'b1;
        lp_valid1 = 1'b1;
        lp_irdy1 = 1'b1;
        
        lp_data0 = {16{32'hDEADBEEF}};
        lp_data1 = {16{32'hCAFEBABE}};
        
        fork
            begin
                wait (o_pl_valid0 && o_out_data0 === {16{32'hCAFEBABE}});
                $display("T=%0t | [DATA] Die0 received CAFEBABE correctly.", $time);
                wait (o_pl_valid1 && o_out_data1 === {16{32'hDEADBEEF}});
                $display("T=%0t | [DATA] Die1 received DEADBEEF correctly.", $time);
                pass = 1'b1;
            end
            begin
                repeat (800) @(posedge lclk0);
                $error("T=%0t | [DATA] TIMEOUT -- Data transfer failed.", $time);
                pass = 1'b0;
            end
        join_any
        disable fork;
        
        @(negedge lclk0);
        lp_valid0 = 1'b0;
        lp_irdy0 = 1'b0;
        lp_valid1 = 1'b0;
        lp_irdy1 = 1'b0;
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    bit ok;
    int scenario_num=1;
    bit data_pass;
    initial begin
        
        enabled_scenarios[1] = 1'b1;
       /* enabled_scenarios[2] = 1'b0;
        enabled_scenarios[3] = 1'b1;
        enabled_scenarios[4] = 1'b1;
        enabled_scenarios[5] = 1'b1;
        enabled_scenarios[6] = 1'b1;
        enabled_scenarios[7] = 1'b1;
        enabled_scenarios[8] = 1'b1;
        enabled_scenarios[9] = 1'b1;
        enabled_scenarios[10] = 1'b1;
        enabled_scenarios[11] = 1'b1;
        enabled_scenarios[12] = 1'b1;
        enabled_scenarios[13] = 1'b1;
        enabled_scenarios[14] = 1'b1;
        enabled_scenarios[15] = 1'b1;
        enabled_scenarios[16] = 1'b1;
        enabled_scenarios[17] = 1'b1;
        enabled_scenarios[18] = 1'b1;
        enabled_scenarios[19] = 1'b1;
        enabled_scenarios[20] = 1'b1;
        enabled_scenarios[21] = 1'b1;
        enabled_scenarios[22] = 1'b1;
        enabled_scenarios[23] = 1'b1;
        enabled_scenarios[24] = 1'b1;
        enabled_scenarios[25] = 1'b1;
        enabled_scenarios[26] = 1'b1;
        enabled_scenarios[27] = 1'b1;*/
        enabled_scenarios[28] = 1'b1;
        enabled_scenarios[29] = 1'b1;
        enabled_scenarios[30] = 1'b1;
    
        $display("================================================================");
        $display("  STARTING UCIe_PHY INTEGRATION TESTBENCH (Logical_PHY + Reg_File)");
        $display("  Adapter programs Reg_File over sideband; observes via (.)");
        $display("================================================================\n");
        // ----------------------------------------------------------------
        // Scenario 1: Happy Path -> ACTIVE + status print + data transfer
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Happy Path training to ACTIVE...", $time, scenario_num);
            reset_system();
            // Program dies first (so print_ctrl_regs shows the written values),
            // then do_bringup will re-program and wait for ACTIVE.
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            do_bringup(ok);
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully", scenario_num);
            end
        end else begin 
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 2: Watchdog Timeout (SB blocked)
        // DISABLED: relies on the true 8 ms watchdog firing, which costs ~8 ms
        // of sim time (dominates runtime). Set RUN_SC2=1'b1 to re-enable.
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] TrainError (sideband blocked)...", $time, scenario_num);
            reset_system();
            block_sideband = 1'b1;
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            fork
                begin wait (m_error); $display("T=%0t | [SC%0d] die0 TRAINERROR as expected.", $time, scenario_num); end
                begin wait (m_done);  $error("T=%0t | [SC%0d] reached ACTIVE with blocked SB?", $time, scenario_num); fails++; end
                begin #(40_000_000); // 40 ms: must exceed the true 8 ms watchdog at the slow pre-speed clock
                      $error("T=%0t | [SC%0d] TIMEOUT (watchdog did not fire).", $time, scenario_num); fails++; end
            join_any
            disable fork;
            chk(m_error, "watchdog produced TRAINERROR", scenario_num);
        end else begin
            $display("\nT=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 3: Asymmetric Width Negotiation (x16 vs x8 -> x8)
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Asymmetric Width: Die0 requests x16, Die1 requests x8...", $time, scenario_num);
            reset_system();
            fork
                program_die_custom(0, 4'h2, 4'h5, 1'b0);
                program_die_custom(1, 4'h1, 4'h5, 1'b1);
            join
            print_ctrl_regs();
            do_bringup_custom(ok, 4'h2, 4'h1, 1'b0, 1'b1); // force x8 on Die1
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully on negotiated x8 link", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 4: Lane Reversal + Retry (Symmetric reversal)
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Symmetric Lane Reversal: Both dies reverse package routes...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            reverse_lanes_0to1 = 1'b1;
            reverse_lanes_1to0 = 1'b1;
            do_bringup(ok);
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully with symmetric lane reversal", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 5: Asymmetric Lane Reversal
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Asymmetric Lane Reversal: Only Die0 reverses package routes...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            reverse_lanes_0to1 = 1'b1;
            reverse_lanes_1to0 = 1'b0;
            do_bringup(ok);
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully with asymmetric lane reversal", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 6: Asymmetric Width Degradation with Retry (Fault lanes 8..15 on Die 0)
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Width Degradation: Fault lanes 8..15 -> degrade x16 to x8...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            corrupt_0to1 = 16'hFF00; // corrupt lanes 8..15
            do_bringup(ok);
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully after width degradation to x8", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 7: Asymmetric Width Degradation with Retry (Fault lanes 0..7 on Die 1)
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Asymmetric Width Degradation: Fault lanes 0..7 -> degrade x16 to x8...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            corrupt_1to0 = 16'h00FF; // corrupt lanes 0..7
            do_bringup(ok);
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully after width degradation to x8", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 8: Asymmetric Width Degradation with Retry (Fault lanes 0..7 on Die 0) (Fault lanes 8..15 on Die 1)
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Asymmetric Width Degradation: Fault lanes 0..7 -> degrade x16 to x8...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            corrupt_0to1 = 16'h00FF; // corrupt lanes 0..7
            corrupt_1to0 = 16'hFF00; // corrupt lanes 8..15
            do_bringup(ok);
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully after width degradation to x8", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 9: Both Dies set Link Speed to 20 GT/s & 16 GT/s respectively
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Both Dies set Link Speed to 20 GT/s & 16 GT/s respectively...", $time, scenario_num);
            reset_system();
            fork
                program_die_custom(0, 4'h2, 4'h4, 1'b0);
                program_die_custom(1, 4'h2, 4'h3, 1'b0);
            join
            print_ctrl_regs();
            do_bringup_custom(ok, 4'h2, 4'h2, 1'b0, 1'b0, 4'h4, 4'h3);
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully after both dies set Link Speed to 20 GT/s & 16 GT/s respectively", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 10: PM mode (L1) entry + wake
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] PM mode (L1) entry + wake...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            do_bringup(ok);
            chk(ok, "bring-up to ACTIVE", scenario_num);
            if (ok) begin
                $display("T=%0t | [SC%0d] ACTIVE. die0 initiates L1; die1 responds...", $time, scenario_num);
                @(negedge lclk0);
                lp_state_req0 = L_1;
                fork
                    begin wait (u_die1.u_digital_ucie.u_main_sm.u_rdi_sm.sm.u_unit_active_state.current_state == 26'h0800000);
                          @(negedge lclk1); lp_state_req1 = L_1; end
                    begin repeat (8000) @(posedge lclk0); $error("[SC7] TO: die1 never reached WAIT"); fails++; end
                join_any
                disable fork;
                fork
                    begin wait (ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2 &&
                                pl_state_sts0 == L_1 && pl_state_sts1 == L_1);
                          $display("T=%0t | [SC%0d] both dies in L1.", $time, scenario_num); end
                    begin repeat (8000) @(posedge lclk0); $error("[SC%0d] TO entering L1", $time, scenario_num); fails++; end
                join_any
                disable fork;
                chk(ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2 &&
                    pl_state_sts0 == L_1 && pl_state_sts1 == L_1,
                    "both dies entered L1 (PM): ltsm=LOG_L1_L2 && rdi=L_1",scenario_num);

            // Wake: request Active again -> L1 exits via Retrain -> back to ACTIVE.
            // The Retrain sub-SM runs the *symmetric* Active handshake. Holding
            // lp_state_req=Active on both dies takes the Retrain "direct" path,
            // which starts that handshake at the very start of Retrain (early
            // MBTRAIN) on both dies at once -> collision (one die hangs in
            // Retrain forever).  Instead mirror RDI_SM_tb's seq_exit_to_active:
            // kick L1->Retrain with Active, drop to Nop while the PHY retrains,
            // then re-assert Active at LINKINIT so the handshake runs in the
            // freshly-trained LINKINIT context (the same path bring-up uses).
                @(negedge lclk0);
                lp_state_req0 = Active; lp_state_req1 = Active;   // kick L1 -> Retrain
                fork
                    begin wait (ln0 != LOG_L1_L2); @(negedge lclk0); lp_state_req0 = Nop;
                          wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 != LOG_L1_L2); @(negedge lclk1); lp_state_req1 = Nop;
                          wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                join_none
                fork
                    begin wait (m_done && p_done &&
                                pl_state_sts0 == Active && pl_state_sts1 == Active);
                          $display("T=%0t | [SC%0d] re-trained to ACTIVE after L1.", $time, scenario_num); end
                    begin wait (m_error || p_error); $error("[SC] err during wake", scenario_num); fails++; end
                    begin repeat (1000000) @(posedge lclk0); $error("[SC] TO during wake", scenario_num); fails++; end
                join_any
                disable fork;
                chk(m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active,
                    "L1 wake re-trained to ACTIVE: ltsm=LOG_ACTIVE && rdi=Active",scenario_num);
                if (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active) begin
                    print_active_status();
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully after L1 wake",scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 11: L2 entry, exit to RESET, and re-train recovery
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] PM mode (L2) entry, exit to RESET, and recovery...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            do_bringup(ok);
            chk(ok, "bring-up to ACTIVE",scenario_num);
            if (ok) begin
                $display("T=%0t | [SC%0d] ACTIVE. Both dies request L2...", $time, scenario_num);
                @(negedge lclk0);
                lp_state_req0 = L_2;
                fork
                    begin wait (u_die1.u_digital_ucie.u_main_sm.u_rdi_sm.sm.u_unit_active_state.current_state == 26'h0800000);
                      @(negedge lclk1); lp_state_req1 = L_2; end
                    begin repeat (8000) @(posedge lclk0); $error("[SC%0d] TO: die1 never reached WAIT", scenario_num); fails++; end
                join_any
                disable fork;
                fork
                    begin wait (ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2 &&
                                pl_state_sts0 == L_2 && pl_state_sts1 == L_2);
                          $display("T=%0t | [SC%0d] both dies in L2 (LOG_L1_L2).", $time, scenario_num); end
                    begin repeat (8000) @(posedge lclk0); $error("[SC%0d] TO entering L2",scenario_num); fails++; end
                join_any
                disable fork;
                chk(ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2 &&
                    pl_state_sts0 == L_2 && pl_state_sts1 == L_2,
                    "both dies entered L2: ltsm=LOG_L1_L2 && rdi=L_2",scenario_num);

                // Exit L2 to RESET.  Per UCIe spec / the RDI_SM (unit_L2_state) and
                // the RDI_SM_tb reference (sc07_l2_exit / TC-05.2), L2 PM-exit is
                // triggered by requesting *Active* -- the L2 sub-SM then moves
                // L2 -> Reset and the link is fully re-brought-up.  (There is no
                // lp_state_req==Reset request in the protocol; the old code drove
                // Reset, which the L2 idle FSM ignores -> timeout.)
                @(negedge lclk0);
                lp_state_req0 = Active; lp_state_req1 = Active;
                fork
                    begin wait (ln0 == LOG_RESET && ln1 == LOG_RESET &&
                                pl_state_sts0 == Reset && pl_state_sts1 == Reset);
                          $display("T=%0t | [SC%0d] both dies in RESET.", $time, scenario_num); end
                    begin repeat (80000) @(posedge lclk0); $error("[SC%0d] TO entering RESET from L2",scenario_num); fails++; end
                join_any
                disable fork;
                chk(ln0 == LOG_RESET && ln1 == LOG_RESET &&
                    pl_state_sts0 == Reset && pl_state_sts1 == Reset,
                    "exited L2 to RESET successfully: ltsm=LOG_RESET && rdi=Reset",scenario_num);

                // Re-train to ACTIVE
                @(negedge lclk0);
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
                                pl_state_sts0 == Active && pl_state_sts1 == Active);
                          $display("T=%0t | [SC%0d] recovered and re-trained to ACTIVE.", $time, scenario_num); end
                    begin wait (m_error || p_error); $error("[SC%0d] err during recovery",scenario_num); fails++; end
                    // Recovery is a *full* re-train (SBINIT->MBINIT->MBTRAIN->ACTIVE),
                    // so it needs the same budget as do_bringup (300000), not 100000.
                    begin repeat (300000) @(posedge lclk0); $error("[SC%0d] TO during recovery",scenario_num); fails++; end
                join_any
                disable fork;
                chk(m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active,
                    "recovery training succeeded: ltsm=LOG_ACTIVE && rdi=Active",scenario_num);
                if (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active) begin
                    print_active_status();
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully after L2 recovery",scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 12: TRAINERROR entry (rdi=LinkError), clear, recover
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] TRAINERROR: fault link, hold, clear, re-train...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            do_bringup(ok);
            chk(ok, "bring-up to ACTIVE",scenario_num);
            if (ok) begin
                // Inject a link error the way the RDI_SM expects it (and the way
                // RDI_SM_tb seq_linkerror_recovery drives it): assert the
                // lp_linkerror *flag* -- NOT lp_state_req.  unit_active_state IDLE
                // has no lp_state_req==LinkError case; instead lp_linkerror feeds
                // message_timeout_handler, which makes die0 the INITIATOR (sends
                // RDI_LINK_ERROR_REQ over SB) and die1 the RESPONDER, driving both
                // RDI SMs to LinkError -> pl_trainerror -> LTSM TRAINERROR.
                // Drop lp_state_req to Nop during the residency so neither die
                // satisfies the LinkError->Reset exit (lp_state_req==Active) early.
                $display("T=%0t | [SC%0d] Injecting fault (lp_linkerror on die0)...", $time,scenario_num);
                @(negedge lclk0);
                lp_linkerror0 = 1'b1;
                lp_state_req0 = Nop; lp_state_req1 = Nop;

                fork
                    begin
                        wait (m_error && p_error &&
                              pl_state_sts0 == LinkError && pl_state_sts1 == LinkError);
                        $display("T=%0t | [SC%0d] Both dies entered TRAINERROR state (ltsm=LOG_TRAINERROR && rdi=LinkError).", $time,scenario_num);
                    end
                    begin
                        repeat(20000) @(posedge lclk0);
                        $error("T=%0t | [SC%0d] TIMEOUT -- Dies did not enter TRAINERROR.", $time,scenario_num);
                        $finish;
                    end
                join_any
                disable fork;

                // Clear fault, return to RESET.  Per unit_linkerror_state the
                // LinkError->Reset exit requires  !lp_linkerror && lp_state_req==Active
                // && the 16 ms residency timer  (RDI_SM_tb: lp_linkerror=0;
                // lp_state_req=Active; wait_state(Reset)).  The RTL holds both dies
                // in LinkError until their 16 ms timer fires, then releases to Reset.
                @(negedge lclk0);
                lp_linkerror0 = 1'b0;
                lp_state_req0 = Active;
                lp_state_req1 = Active;

                fork
                    begin
                        wait (ln0 == LOG_RESET && ln1 == LOG_RESET &&
                              pl_state_sts0 == Reset && pl_state_sts1 == Reset);
                        $display("T=%0t | [SC%0d] Both dies cleared TRAINERROR to RESET (ltsm=LOG_RESET && rdi=Reset).", $time,scenario_num);
                    end
                    begin
                        // 16 ms residency (scaled) must elapse before exit; allow margin.
                        repeat(20000) @(posedge lclk0);
                        $error("T=%0t | [SC%0d] TIMEOUT -- Dies did not reach RESET from TRAINERROR.", $time,scenario_num);
                        $finish;
                    end
                join_any
                disable fork;

                // Recover: program and start training
                @(negedge lclk0);
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
                    begin
                        wait (m_done && p_done &&
                              pl_state_sts0 == Active && pl_state_sts1 == Active);
                        $display("T=%0t | [SC%0d] PASS -- Re-trained to ACTIVE after TRAINERROR (ltsm=LOG_ACTIVE && rdi=Active).", $time,scenario_num);
                    end
                    begin
                        // Recovery is a *full* re-train, so it needs the same budget
                        // as do_bringup (300000), not 100000.
                        repeat(300000) @(posedge lclk0);
                        $error("T=%0t | [SC%0d] TIMEOUT -- Post-TRAINERROR re-train hung.", $time,scenario_num);
                        $finish;
                    end
                join_any
                disable fork;
                chk(m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active,
                    "TRAINERROR recovery succeeded: ltsm=LOG_ACTIVE && rdi=Active",scenario_num);
                if (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active) begin
                    print_active_status();
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully after TRAINERROR recovery",scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 13: Valid Lane boundary error injection
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Valid Lane Boundary Error Injection test...", $time, scenario_num);
            reset_system();
            lp_state_req0 = Nop; lp_state_req1 = Nop;
            fork
                program_die(0);
                program_die(1);
            join
            print_ctrl_regs();
            fork
                begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                begin
                    // Wait until Die 1's valid deserializer enters compare state (o_state === 2'b10)
                    wait (u_die1.u_analog_hard_macro.u_mainband.u_valid_des.o_state === 2'b10);
                    $display("T=%0t | [SC%0d] Die 1 valid deserializer entered compare state.", $time,scenario_num);
                
                    // Wait for edge of sample_clk and count = 15 (end of frame)
                    @(posedge u_die1.u_analog_hard_macro.u_mainband.sample_clk);
                    wait (u_die1.u_analog_hard_macro.u_mainband.u_valid_des.o_count == 4'd15);
                
                    // Pulse error injection on the next clock cycle to corrupt the boundary
                    @(posedge u_die1.u_analog_hard_macro.u_mainband.sample_clk);
                    rx_vld_error_inject_0_to_1 = 1'b1;
                    $display("T=%0t | [SC%0d] Injecting valid lane boundary error...", $time,scenario_num);
                
                    @(posedge u_die1.u_analog_hard_macro.u_mainband.sample_clk);
                    rx_vld_error_inject_0_to_1 = 1'b0;
                    $display("T=%0t | [SC%0d] Error injection cleared.", $time,scenario_num);
                end
            join_none

            fork
                begin
                    wait (m_done && p_done &&
                          pl_state_sts0 == Active && pl_state_sts1 == Active);
                    $display("T=%0t | [SC%0d] Both dies reached ACTIVE successfully (ltsm=LOG_ACTIVE && rdi=Active).", $time,scenario_num);
                end
                begin
                    repeat(200000) @(posedge lclk0);
                    $error("T=%0t | [SC%0d] TIMEOUT -- Training hung during error injection.", $time,scenario_num);
                    $finish;
                end
            join_any
            disable fork;

            chk(m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active,
                "boundary error test succeeded: ltsm=LOG_ACTIVE && rdi=Active",scenario_num);
            if (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully after boundary error survival",scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 14: MBTRAIN Lane Degradation (REPAIR triggered mid-train)
        // ----------------------------------------------------------------
        // Lanes 8..15 are injected as faulty AFTER MBINIT completes (so MBINIT
        // sees x16 OK) but DURING MBTRAIN D2C sweeps.  MBTRAIN.REPAIR should
        // detect the failing upper lanes and degrade to x8 lower.
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] MBTRAIN REPAIR: inject lane fault AFTER MBINIT -> degrade in MBTRAIN...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            lp_state_req0 = Nop; lp_state_req1 = Nop;
            fork
                begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                begin
                    // Wait until MBTRAIN begins (past MBINIT), then corrupt lanes 8-15
                    wait (ln0 == LOG_MBTRAIN_VALVREF);
                    @(posedge lclk0);
                    // A physical lane fault is bidirectional (a broken bump fails
                    // both TX and RX on that lane). Corrupt BOTH directions so the
                    // two dies see the same failing lanes and agree on the x8-low
                    // degrade in MBTRAIN.REPAIR. A one-directional fault makes the
                    // dies disagree (one wants x16, the other x8) and desync the
                    // REPAIR sideband handshake -> TRAINERROR.
                    corrupt_0to1 = 16'hFF00;  // lanes 8-15 bad on Die0->Die1 path
                    corrupt_1to0 = 16'hFF00;  // lanes 8-15 bad on Die1->Die0 path
                    $display("T=%0t | [SC%0d] MBTRAIN started – injecting lanes 8-15 fault.", $time,scenario_num);
                end
            join_none
            fork
                begin wait (m_done && p_done &&
                            pl_state_sts0 == Active && pl_state_sts1 == Active); ok = 1'b1; end
                begin wait (m_error || p_error); ok = 1'b0; $error("[SC%0d] TRAINERROR during MBTRAIN fault injection",scenario_num); end
                begin repeat (600000) @(posedge lclk0); ok = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
            join_any
            disable fork;
            corrupt_0to1 = 16'h0000; // remove fault after training done
            corrupt_1to0 = 16'h0000;
            chk(ok, "MBTRAIN REPAIR degraded lanes and reached ACTIVE: ltsm=LOG_ACTIVE && rdi=Active",scenario_num);
            if (ok) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified after MBTRAIN lane degradation",scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 15: MBTRAIN Speed Degradation (speed-dependent all-lane fault)
        // ----------------------------------------------------------------
        // Two stacked faults exercise the LINKSPEED error -> speed-degrade path:
        //
        //   1) MBINIT upper-half fault: lanes 8-15 are broken (both directions)
        //      from reset.  Both dies target x16, so MBINIT.REPAIRMB sees only the
        //      lower 8 lanes pass and degrades the link to x8-low (mask 3'b001).
        //
        //   2) MBTRAIN speed-dependent all-lane fault: once MBTRAIN.SPEEDIDLE has
        //      raised the link to its negotiated max speed, ALL lanes are broken
        //      (16'hFFFF, both directions) to model a fault that only manifests at
        //      the high speed.  When training reaches MBTRAIN.LINKSPEED the D2C test
        //      fails on every active (lower-8) lane.  Because the target is still
        //      x16, no fully-good 8-lane half exists -> width_degrade_feasible = 0
        //      -> REPAIR (width degrade) is impossible, so LINKSPEED takes the
        //      SPEED-DEGRADE path back to SPEEDIDLE (one speed step down).
        //
        //   3) Recovery: the fault is speed-dependent, so as soon as SPEEDIDLE is
        //      re-entered (now one step slower) the all-lane fault is cleared,
        //      leaving only the original upper-half break (16'hFF00).  The healthy
        //      lower 8 lanes pass at the lower speed and the link reaches ACTIVE at
        //      x8-low + degraded speed.
        //
        // Both dies are programmed with the SAME target width/speed and the faults
        // are symmetric (both directions), so the two dies always agree on the
        // x8-low degrade and the speed-degrade decision (a one-directional fault
        // would desync the REPAIR/LINKSPEED handshake -> TRAINERROR, see SC11).
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Speed Degradation: speed-dependent all-lane fault forces LINKSPEED speed-degrade...", $time, scenario_num);
            reset_system();
            fork
                program_die_custom(0, 4'h2, 4'h5, 1'b0);
                program_die_custom(1, 4'h2, 4'h5, 1'b0);
            join
            print_ctrl_regs();
            begin : sc12_bringup
                bit         ok12;
                logic [3:0] speed_at_max;   // speed code captured after the first SPEEDIDLE (= max)
                ok12         = 1'b0;
                speed_at_max = 4'h0;
                // Fault 1: upper-half break present from reset (both directions) so
                // MBINIT degrades to x8-low.
                corrupt_0to1 = 16'hFF00;
                corrupt_1to0 = 16'hFF00;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc12_fault_mgr
                        // Wait for the FIRST SPEEDIDLE (speed raised to max), then leave it.
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
                        // Fault 2: break ALL lanes at the high speed -> LINKSPEED sees
                        // no good 8-lane half -> width-degrade infeasible -> speed-degrade.
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting all-lane fault.", $time, scenario_num, speed_at_max);
                        // Wait for LINKSPEED to speed-degrade -> SPEEDIDLE re-entry.
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        // Speed-dependent fault clears at the lower speed: restore the
                        // original upper-half-only break so the lower 8 lanes recover.
                        corrupt_0to1 = 16'hFF00;
                        corrupt_1to0 = 16'hFF00;
                        $display("T=%0t | [SC%0d] Speed degraded - clearing all-lane fault (lower 8 lanes recover).", $time, scenario_num);
                    end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok12 = 1'b1; end
                    begin wait (m_error || p_error); ok12 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (600000) @(posedge lclk0); ok12 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok12, "speed-degraded link reached ACTIVE",scenario_num);
                if (ok12) begin
                    print_active_status();
                    // Width degraded to x8 (MBINIT upper-half break) and speed one
                    // step below the captured max (LINKSPEED speed-degrade).
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die0 negotiated width is x8 (MBINIT upper-half degrade)",scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die1 negotiated width is x8 (MBINIT upper-half degrade)",scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h1), "Die0 speed degraded one step below max",scenario_num);
                    chk(u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h1), "Die1 speed degraded one step below max",scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified after speed degradation",scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;
        // ----------------------------------------------------------------
        // Scenario 16: Target settings in Control Reg > Hardware Capabilities
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Capping check: program target width/speed > capabilities...", $time, scenario_num);
            reset_system();
            // Program target width = x32 (4'h3) > capability x16
            // Program target speed = 48 GT/s (4'h6) > capability 32 GT/s (4'h5)
            fork
                program_die_custom(0, 4'h3, 4'h6, 1'b0);
                program_die_custom(1, 4'h3, 4'h6, 1'b0);
            join
            print_ctrl_regs();
            begin : sc13_bringup
                bit ok13;
                ok13 = 1'b0;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok13 = 1'b1; end
                    begin wait (m_error || p_error); ok13 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (600000) @(posedge lclk0); ok13 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                chk(ok13, "[SC%0d] capped link reached ACTIVE successfully",scenario_num);
                if (ok13) begin
                    print_active_status();
                    // Assert that negotiated width status is x16 (code 4'h2) and speed status is 32 GT/s (code 4'h5)
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h2, "Die0 negotiated width is x16 (cap capped)",scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h2, "Die1 negotiated width is x16 (cap capped)",scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == 4'h5, "Die0 negotiated speed is 32 GT/s (cap capped)",scenario_num);
                    chk(u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == 4'h5, "Die1 negotiated speed is 32 GT/s (cap capped)",scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully at capped settings",scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 17: Lane reversal with asymmetric width degrade (negotiate x16 -> degrade x8)
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Lane Reversal + Width Degradation: Fault lanes 8..15 & symmetric lane reversal...", $time, scenario_num);
            reset_system();
            fork program_die(0); program_die(1); join
            print_ctrl_regs();
            reverse_lanes_0to1 = 1'b1;
            reverse_lanes_1to0 = 1'b1;
            corrupt_0to1 = 16'hFF00; // corrupt lanes 8..15 Die0 -> Die1
            do_bringup(ok);
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                // Check that width degraded to x8 (code 4'h1) and lane reversal is active
                chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die0 negotiated width is x8", scenario_num);
                chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die1 negotiated width is x8", scenario_num);
                chk(u_die0.u_digital_ucie.log0_lane_reversal == 1'b1, "Die0 lane reversal active", scenario_num);
                chk(u_die1.u_digital_ucie.log0_lane_reversal == 1'b1, "Die1 lane reversal active", scenario_num);
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 18: Asymmetric width negotiation (x16 vs x8 -> x8) and degrade to x4 with lane reversal
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] x8 target -> degrade to x4 with Lane Reversal...", $time, scenario_num);
            reset_system();
            // Program target width to x8 (4'h1)
            fork
                program_die_custom(0, 4'h1, 4'h5, 1'b1);
                program_die_custom(1, 4'h1, 4'h5, 1'b1);
            join
            print_ctrl_regs();
            reverse_lanes_0to1 = 1'b1;
            reverse_lanes_1to0 = 1'b1;
            corrupt_0to1 = 16'hFF0F; // fail lanes 0..3, pass lanes 4..7
            do_bringup_custom(ok, 4'h1, 4'h1, 1'b1, 1'b1); // force x8 bringup
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                // Check that width degraded to x4 (code 4'h0) and lane reversal is active
                chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h0, "Die0 negotiated width is x4", scenario_num);
                chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h0, "Die1 negotiated width is x4", scenario_num);
                chk(u_die0.u_digital_ucie.log0_lane_reversal == 1'b1, "Die0 lane reversal active", scenario_num);
                chk(u_die1.u_digital_ucie.log0_lane_reversal == 1'b1, "Die1 lane reversal active", scenario_num);
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 19: Asymmetric width negotiation (x16 vs x8 -> x8) and degrade to x4 without lane reversal
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] x8 target -> degrade to x4 without Lane Reversal...", $time, scenario_num);
            reset_system();
            // Program target width to x8 (4'h1)
            fork
                program_die_custom(0, 4'h1, 4'h5, 1'b1);
                program_die_custom(1, 4'h1, 4'h5, 1'b1);
            join
            print_ctrl_regs();
            corrupt_0to1 = 16'hFF0F; // fail lanes 0..3, pass lanes 4..7
            do_bringup_custom(ok, 4'h1, 4'h1, 1'b1, 1'b1); // force x8 bringup
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            if (ok) begin
                print_active_status();
                // Check that width degraded to x4 (code 4'h0) and lane reversal is not active
                chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h0, "Die0 negotiated width is x4", scenario_num);
                chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h0, "Die1 negotiated width is x4", scenario_num);
                chk(u_die0.u_digital_ucie.log0_lane_reversal == 1'b0, "Die0 lane reversal inactive", scenario_num);
                chk(u_die1.u_digital_ucie.log0_lane_reversal == 1'b0, "Die1 lane reversal inactive", scenario_num);
                do_data_transfer(data_pass);
                chk(data_pass, "data transfer verified successfully", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 20: Speed degradation (1 step) on degraded x4-upper link
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Speed Degradation (1 step) on degraded x4-upper link...", $time, scenario_num);
            reset_system();
            // Program both dies to target x8 (4'h1) and target speed Gen6 (4'h5)
            fork
                program_die_custom(0, 4'h1, 4'h5, 1'b1);
                program_die_custom(1, 4'h1, 4'h5, 1'b1);
            join
            print_ctrl_regs();
            begin : sc19_bringup
                bit         ok19;
                logic [3:0] speed_at_max;
                ok19         = 1'b0;
                speed_at_max = 4'h0;
                // Fault 1: lanes 0..3 are broken from reset (both directions), so MBINIT degrades to x4-upper (lanes 4..7)
                corrupt_0to1 = 16'hFF0F;
                corrupt_1to0 = 16'hFF0F;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc19_fault_mgr
                        // Wait for the FIRST SPEEDIDLE (speed raised to max), then leave it.
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
                        // Fault 2: break upper lanes 4..7 at the high speed too -> LINKSPEED sees all active lanes fail -> speed degrade
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting speed-dependent fault on lanes 4-7.", $time, scenario_num, speed_at_max);
                        // Wait for LINKSPEED to speed-degrade -> SPEEDIDLE re-entry
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        // Speed-dependent fault clears at the lower speed: restore original lanes 0..3 fault
                        corrupt_0to1 = 16'hFF0F;
                        corrupt_1to0 = 16'hFF0F;
                        $display("T=%0t | [SC%0d] Speed degraded - clearing high-speed fault (lanes 4-7 recover).", $time, scenario_num);
                    end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok19 = 1'b1; end
                    begin wait (m_error || p_error); ok19 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (600000) @(posedge lclk0); ok19 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok19, "speed-degraded link reached ACTIVE", scenario_num);
                if (ok19) begin
                    print_active_status();
                    // Width degraded to x4 (code 4'h0) and speed degraded by one step
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h0, "Die0 negotiated width is x4", scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h0, "Die1 negotiated width is x4", scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h1), "Die0 speed degraded one step below max", scenario_num);
                    chk(u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h1), "Die1 speed degraded one step below max", scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully after 1-step speed degradation", scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 21: Speed degradation (2 steps) on degraded x4-upper link
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Speed Degradation (2 steps) on degraded x4-upper link...", $time, scenario_num);
            reset_system();
            // Program both dies to target x8 (4'h1) and target speed Gen6 (4'h5)
            fork
                program_die_custom(0, 4'h1, 4'h5, 1'b1);
                program_die_custom(1, 4'h1, 4'h5, 1'b1);
            join
            print_ctrl_regs();
            begin : sc20_bringup
                bit         ok20;
                logic [3:0] speed_at_max;
                ok20         = 1'b0;
                speed_at_max = 4'h0;
                // Fault 1: lanes 0..3 are broken from reset (both directions), so MBINIT degrades to x4-upper (lanes 4..7)
                corrupt_0to1 = 16'hFF0F;
                corrupt_1to0 = 16'hFF0F;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc20_fault_mgr
                        // Wait for the FIRST SPEEDIDLE (speed raised to max Gen6 / code 5), then leave it
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
                        
                        // Fault at speed_at_max (Gen6): corrupt lanes 4..7
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting speed-dependent fault on lanes 4-7.", $time, scenario_num, speed_at_max);
                        
                        // Wait for first speed-degrade to complete (back to SPEEDIDLE) and exit it again
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        
                        // Now we are at Gen5 (code 4). Keep lanes 4..7 corrupted.
                        $display("T=%0t | [SC%0d] First speed degrade complete (speed code %0h) - keeping lanes 4-7 fault active.", $time, scenario_num, u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status);
                        
                        // Wait for second speed-degrade to complete (back to SPEEDIDLE)
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        // Now we are at Gen4 (code 3). Speed-dependent fault clears. Restore original lanes 0..3 fault
                        corrupt_0to1 = 16'hFF0F;
                        corrupt_1to0 = 16'hFF0F;
                        $display("T=%0t | [SC%0d] Second speed degrade complete - clearing high-speed fault (lanes 4-7 recover at speed code %0h).", $time, scenario_num, u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status);
                    end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok20 = 1'b1; end
                    begin wait (m_error || p_error); ok20 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (800000) @(posedge lclk0); ok20 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok20, "speed-degraded link reached ACTIVE", scenario_num);
                if (ok20) begin
                    print_active_status();
                    // Width degraded to x4 (code 4'h0) and speed degraded by two steps
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h0, "Die0 negotiated width is x4", scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h0, "Die1 negotiated width is x4", scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h2), "Die0 speed degraded two steps below max", scenario_num);
                    chk(u_die1.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h2), "Die1 speed degraded two steps below max", scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully after 2-step speed degradation", scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 22: Lane Reversal + 1-Step Speed degradation
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Lane Reversal + 1-Step Speed Degradation...", $time, scenario_num);
            reset_system();
            fork
                program_die_custom(0, 4'h2, 4'h5, 1'b0);
                program_die_custom(1, 4'h2, 4'h5, 1'b0);
            join
            print_ctrl_regs();
            begin : sc21_bringup
                bit         ok21;
                logic [3:0] speed_at_max;
                ok21         = 1'b0;
                speed_at_max = 4'h0;
                reverse_lanes_0to1 = 1'b1;
                reverse_lanes_1to0 = 1'b1;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc21_fault_mgr
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting all-lane fault with reversal active.", $time, scenario_num, speed_at_max);
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        corrupt_0to1 = 16'h0000;
                        corrupt_1to0 = 16'h0000;
                        $display("T=%0t | [SC%0d] Speed degraded - clearing all-lane fault.", $time, scenario_num);
                    end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok21 = 1'b1; end
                    begin wait (m_error || p_error); ok21 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (600000) @(posedge lclk0); ok21 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok21, "link reached ACTIVE with lane reversal and speed degrade", scenario_num);
                if (ok21) begin
                    print_active_status();
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h2, "Die0 negotiated width is x16", scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h2, "Die1 negotiated width is x16", scenario_num);
                    chk(u_die0.u_digital_ucie.log0_lane_reversal == 1'b1, "Die0 lane reversal active", scenario_num);
                    chk(u_die1.u_digital_ucie.log0_lane_reversal == 1'b1, "Die1 lane reversal active", scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h1), "Die0 speed degraded one step", scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully", scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 23: Asymmetric Width degrade (x16 -> x8) + 1-Step Speed degradation
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Asymmetric Width Degrade (x16->x8) + 1-Step Speed Degradation...", $time, scenario_num);
            reset_system();
            fork
                program_die_custom(0, 4'h2, 4'h5, 1'b0);
                program_die_custom(1, 4'h2, 4'h5, 1'b0);
            join
            print_ctrl_regs();
            begin : sc22_bringup
                bit         ok22;
                logic [3:0] speed_at_max;
                ok22         = 1'b0;
                speed_at_max = 4'h0;
                corrupt_0to1 = 16'hFF00;
                corrupt_1to0 = 16'h00FF;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc22_fault_mgr
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting speed-dependent fault on active x8 lanes.", $time, scenario_num, speed_at_max);
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        corrupt_0to1 = 16'hFF00;
                        corrupt_1to0 = 16'h00FF;
                        $display("T=%0t | [SC%0d] Speed degraded - clearing high-speed fault (lower 8 lanes recover).", $time, scenario_num);
                    end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok22 = 1'b1; end
                    begin wait (m_error || p_error); ok22 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (600000) @(posedge lclk0); ok22 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok22, "link reached ACTIVE with width degrade and speed degrade", scenario_num);
                if (ok22) begin
                    print_active_status();
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die0 negotiated width is x8", scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die1 negotiated width is x8", scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h1), "Die0 speed degraded one step", scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully", scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 24: Asymmetric Width degrade (x16 -> x8) + 2-Step Speed degradation
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Asymmetric Width Degrade (x16->x8) + 2-Step Speed Degradation...", $time, scenario_num);
            reset_system();
            fork
                program_die_custom(0, 4'h2, 4'h5, 1'b0);
                program_die_custom(1, 4'h2, 4'h5, 1'b0);
            join
            print_ctrl_regs();
            begin : sc23_bringup
                bit         ok23;
                logic [3:0] speed_at_max;
                ok23         = 1'b0;
                speed_at_max = 4'h0;
                corrupt_0to1 = 16'h00FF;
                corrupt_1to0 = 16'hFF00;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc23_fault_mgr
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting speed-dependent fault on active x8 lanes.", $time, scenario_num, speed_at_max);
                        
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        $display("T=%0t | [SC%0d] First speed degrade complete (speed code %0h) - keeping lower lanes fault active.", $time, scenario_num, u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status);
                        
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        corrupt_0to1 = 16'h00FF;
                        corrupt_1to0 = 16'hFF00;
                        $display("T=%0t | [SC%0d] Second speed degrade complete - clearing high-speed fault (lower 8 lanes recover at speed code %0h).", $time, scenario_num, u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status);
                    end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok23 = 1'b1; end
                    begin wait (m_error || p_error); ok23 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (800000) @(posedge lclk0); ok23 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok23, "link reached ACTIVE with width degrade and 2-step speed degrade", scenario_num);
                if (ok23) begin
                    print_active_status();
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die0 negotiated width is x8", scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die1 negotiated width is x8", scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h2), "Die0 speed degraded two steps", scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully", scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 25: Lane Reversal + Asymmetric Width degrade (x16 -> x8) + 1-Step Speed degradation
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Lane Reversal + Asymmetric Width Degrade + 1-Step Speed Degradation...", $time, scenario_num);
            reset_system();
            fork
                program_die_custom(0, 4'h2, 4'h5, 1'b0);
                program_die_custom(1, 4'h2, 4'h5, 1'b0);
            join
            print_ctrl_regs();
            begin : sc24_bringup
                bit         ok24;
                logic [3:0] speed_at_max;
                ok24         = 1'b0;
                speed_at_max = 4'h0;
                reverse_lanes_0to1 = 1'b1;
                reverse_lanes_1to0 = 1'b1;
                corrupt_0to1 = 16'hFF00;
                corrupt_1to0 = 16'h00FF;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc24_fault_mgr
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting speed-dependent fault on active x8 lanes with reversal active.", $time, scenario_num, speed_at_max);
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        corrupt_0to1 = 16'hFF00;
                        corrupt_1to0 = 16'h00FF;
                        $display("T=%0t | [SC%0d] Speed degraded - clearing high-speed fault (lower 8 lanes recover).", $time, scenario_num);
                    end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok24 = 1'b1; end
                    begin wait (m_error || p_error); ok24 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (600000) @(posedge lclk0); ok24 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok24, "link reached ACTIVE with lane reversal, width degrade and speed degrade", scenario_num);
                if (ok24) begin
                    print_active_status();
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die0 negotiated width is x8", scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die1 negotiated width is x8", scenario_num);
                    chk(u_die0.u_digital_ucie.log0_lane_reversal == 1'b1, "Die0 lane reversal active", scenario_num);
                    chk(u_die1.u_digital_ucie.log0_lane_reversal == 1'b1, "Die1 lane reversal active", scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h1), "Die0 speed degraded one step", scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully", scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 26: Lane Reversal + Asymmetric Width degrade (x16 -> x8) + 1-Step Speed degradation
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Asymmetric Lane Reversal + Asymmetric Width Degrade + 1-Step Speed Degradation...", $time, scenario_num);
            reset_system();
            fork
                program_die_custom(0, 4'h2, 4'h5, 1'b0);
                program_die_custom(1, 4'h2, 4'h5, 1'b0);
            join
            print_ctrl_regs();
            begin : sc26_bringup
                bit         ok26;
                logic [3:0] speed_at_max;
                ok26         = 1'b0;
                speed_at_max = 4'h0;
                reverse_lanes_0to1 = 1'b1;
                reverse_lanes_1to0 = 1'b0;
                corrupt_0to1 = 16'hFF00;
                corrupt_1to0 = 16'h00FF;
                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc26_fault_mgr
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting speed-dependent fault on active x8 lanes with reversal active.", $time, scenario_num, speed_at_max);
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        corrupt_0to1 = 16'hFF00;
                        corrupt_1to0 = 16'h00FF;
                        $display("T=%0t | [SC%0d] Speed degraded - clearing high-speed fault (lower 8 lanes recover).", $time, scenario_num);
                    end
                join_none
                fork
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok26 = 1'b1; end
                    begin wait (m_error || p_error); ok26 = 1'b0; $error("[SC%0d] training error",scenario_num); end
                    begin repeat (600000) @(posedge lclk0); ok26 = 1'b0; $error("[SC%0d] TIMEOUT",scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok26, "link reached ACTIVE with lane reversal, width degrade and speed degrade", scenario_num);
                if (ok26) begin
                    print_active_status();
                    chk(u_die0.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die0 negotiated width is x8", scenario_num);
                    chk(u_die1.u_digital_ucie.u_reg_file.ucie_link_status_r_out[10:7] == 4'h1, "Die1 negotiated width is x8", scenario_num);
                    chk(u_die0.u_digital_ucie.log0_lane_reversal == 1'b1, "Die0 lane reversal active", scenario_num);
                    chk(u_die1.u_digital_ucie.log0_lane_reversal == 1'b0, "Die1 lane reversal active", scenario_num);
                    chk(u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == (speed_at_max - 4'h1), "Die0 speed degraded one step", scenario_num);
                    do_data_transfer(data_pass);
                    chk(data_pass, "data transfer verified successfully", scenario_num);
                end
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;


        // ----------------------------------------------------------------
        // Scenario 27: Speed degradation until TRAINERROR
        // Lanes work normally during MBINIT. Once MBTRAIN begins (first
        // SPEEDIDLE), ALL lanes are permanently corrupted in both
        // directions.  The corruption is never cleared, so every speed-
        // degrade retry also fails, and the link eventually reaches
        // TRAINERROR.
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Speed Degradation until TRAINERROR (permanent all-lane fault at MBTRAIN)...", $time, scenario_num);
            reset_system();
            // Program both dies to target x16 (4'h2) and target speed Gen6 (4'h5)
            fork
                program_die_custom(0, 4'h2, 4'h5, 1'b0);
                program_die_custom(1, 4'h2, 4'h5, 1'b0);
            join
            print_ctrl_regs();
            begin : sc27_bringup
                bit         ok27;
                logic [3:0] speed_at_max;
                ok27         = 1'b0;
                speed_at_max = 4'h0;    

                lp_state_req0 = Nop; lp_state_req1 = Nop;
                fork
                    begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                    begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
                    begin : sc27_fault_mgr
                        // Lanes are clean during MBINIT.  Wait for MBTRAIN
                        // to begin (first SPEEDIDLE = speed raised to max).
                        wait (ln0 == LOG_MBTRAIN_SPEEDIDLE);
                        @(posedge lclk0);
                        wait (ln0 != LOG_MBTRAIN_SPEEDIDLE);
                        speed_at_max = u_die0.u_digital_ucie.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;

                        // Permanently corrupt ALL lanes in both directions.
                        // This fault is NEVER cleared, so every speed-degrade
                        // retry will also fail training, eventually exhausting
                        // all speed levels and reaching TRAINERROR.
                        corrupt_0to1 = 16'hFFFF;
                        corrupt_1to0 = 16'hFFFF;
                        $display("T=%0t | [SC%0d] SPEEDIDLE raised speed to code %0h - injecting PERMANENT all-lane fault (never cleared).", $time, scenario_num, speed_at_max);
                    end
                join_none
                fork
                    begin wait (m_error || p_error); ok27 = 1'b1;
                          $display("T=%0t | [SC%0d] TRAINERROR reached as expected after exhausting all speed-degrade attempts.", $time, scenario_num); end
                    begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok27 = 1'b0;
                          $error("[SC%0d] unexpectedly reached ACTIVE despite permanent all-lane fault!", scenario_num); end
                    begin repeat (800000) @(posedge lclk0); ok27 = 1'b0; $error("[SC%0d] TIMEOUT waiting for TRAINERROR", scenario_num); end
                join_any
                disable fork;
                corrupt_0to1 = 16'h0000;
                corrupt_1to0 = 16'h0000;
                chk(ok27, "permanent all-lane fault led to TRAINERROR after exhausting speed-degrade", scenario_num);
                chk(m_error || p_error, "at least one die reached LOG_TRAINERROR", scenario_num);
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        // Scenario 28: Valid frame error injection during ACTIVE -> PHYRETRAIN -> TXSELFCAL
        // ----------------------------------------------------------------
        if (enabled_scenarios[scenario_num]) begin
            $display("\nT=%0t | [SC%0d] Valid Frame Error Injection during ACTIVE -> PHYRETRAIN -> TXSELFCAL...", $time, scenario_num);
            reset_system();
            // Program both dies
            fork
                program_die(0);
                program_die(1);
            join
            print_ctrl_regs();
            
            // Bringup link to ACTIVE
            lp_state_req0 = Nop; lp_state_req1 = Nop;
            fork
                begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
            join_none
            
            // Wait for both dies to reach LOG_ACTIVE
            fork
                begin
                    wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active);
                    ok = 1'b1;
                end
                begin
                    repeat (600000) @(posedge lclk0);
                    ok = 1'b0;
                    $error("[SC%0d] TIMEOUT waiting for ACTIVE", scenario_num);
                end
            join_any
            disable fork;
            
            chk(ok, "both dies reached LOG_ACTIVE", scenario_num);
            
            if (ok) begin
                print_active_status();
                
                $display("T=%0t | [SC%0d] Initiating data transfer in ACTIVE...", $time, scenario_num);
                
                // Stabilize in ACTIVE
                repeat(20) @(posedge lclk0);
                
                lp_valid0 = 1'b1;
                lp_irdy0 = 1'b1;
                lp_valid1 = 1'b1;
                lp_irdy1 = 1'b1;
                
                lp_data0 = {16{32'hDEADBEEF}};
                lp_data1 = {16{32'hCAFEBABE}};
                
                // Wait 5 cycles of lclk0, then inject valid frame error on Die0 -> Die1 path
                repeat(5) @(posedge lclk0);
                rx_vld_error_inject_0_to_1 = 1'b1;
                $display("T=%0t | [SC%0d] Injected valid frame error on Die0 -> Die1 path.", $time, scenario_num);
                
                // Wait for the design to exit ACTIVE and go to PHYRETRAIN
                fork
                    begin
                        wait (ln0 == LOG_PHYRETRAIN);
                        $display("T=%0t | [SC%0d] Die0 successfully exited ACTIVE and entered PHYRETRAIN.", $time, scenario_num);
                    end
                    begin
                        repeat(10000) @(posedge lclk0);
                        $error("T=%0t | [SC%0d] TIMEOUT waiting for LOG_PHYRETRAIN state.", $time, scenario_num);
                        fails++;
                    end
                join_any
                disable fork;
                
                // Clear the error injection so that retrain handshake can succeed
                rx_vld_error_inject_0_to_1 = 1'b0;
                $display("T=%0t | [SC%0d] Error injection cleared for retraining.", $time, scenario_num);
                
                // Set lp_state_req to Nop for both dies as required for retraining RDI Active request
                lp_state_req0 = Nop;
                lp_state_req1 = Nop;
                
                // Wait for them to transition from PHYRETRAIN to TXSELFCAL
                fork
                    begin
                        wait (ln0 == LOG_MBTRAIN_TXSELFCAL);
                        $display("T=%0t | [SC%0d] Die0 reached LOG_MBTRAIN_TXSELFCAL.", $time, scenario_num);
                    end
                    begin
                        repeat(30000) @(posedge lclk0);
                        $error("T=%0t | [SC%0d] TIMEOUT waiting for LOG_MBTRAIN_TXSELFCAL.", $time, scenario_num);
                        fails++;
                    end
                join_any
                disable fork;
                
                chk(ln0 == LOG_MBTRAIN_TXSELFCAL, "Die0 transitioned from PHYRETRAIN to TXSELFCAL", scenario_num);
                
                // Wait for them to reach LOG_LINKINIT during retraining, then request Active state again
                fork
                    begin
                        wait (ln0 == LOG_LINKINIT);
                        @(negedge lclk0);
                        lp_state_req0 = Active;
                        $display("T=%0t | [SC%0d] Die0 reached LOG_LINKINIT during retrain, setting lp_state_req0 to Active.", $time, scenario_num);
                    end
                    begin
                        wait (ln1 == LOG_LINKINIT);
                        @(negedge lclk1);
                        lp_state_req1 = Active;
                        $display("T=%0t | [SC%0d] Die1 reached LOG_LINKINIT during retrain, setting lp_state_req1 to Active.", $time, scenario_num);
                    end
                join

                // Wait for retraining to complete and reach LOG_ACTIVE / Active again
                $display("T=%0t | [SC%0d] Retraining. Waiting for both dies to reach LOG_ACTIVE again...", $time, scenario_num);
                fork
                    begin
                        wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active);
                        ok = 1'b1;
                    end
                    begin
                        repeat (600000) @(posedge lclk0);
                        ok = 1'b0;
                        $error("T=%0t | [SC%0d] TIMEOUT waiting for LOG_ACTIVE after retrain.", $time, scenario_num);
                    end
                join_any
                disable fork;

                chk(ok, "both dies successfully retrained and reached LOG_ACTIVE / Active again", scenario_num);
                
                if (ok) begin
                    print_active_status();
                end

                // Stop driving lp_valid, lp_irdy
                lp_valid0 = 1'b0;
                lp_irdy0 = 1'b0;
                lp_valid1 = 1'b0;
                lp_irdy1 = 1'b0;
            end
        end else begin
            $display("T=%0t | [SC%0d] Skipped (disabled).", $time, scenario_num);
        end
        scenario_num++;

        // ----------------------------------------------------------------
        $display("\n================================================================");
        if (fails == 0) $display("  RESULT: PASS  (UCIe_PHY INTEGRATION SIM PASS)");
        else            $display("  RESULT: FAIL  (%0d failing checks)", fails);
        $display("================================================================\n");
        $finish;
    end

    // Global watchdog
    initial begin
        #(500_000_000);   // 500 ms sim-time hard stop (true 8 ms LTSM watchdog makes SC2 ~tens of ms)
        $error("GLOBAL TIMEOUT - simulation did not finish");
        $finish;
    end

endmodule