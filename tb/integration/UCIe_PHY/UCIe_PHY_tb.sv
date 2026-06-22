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
    defparam u_die0.u_main_sm.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die0.u_main_sm.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;
    defparam u_die1.u_main_sm.u_rdi_sm.sm.u_unit_Timer.CLK_FREQ = RDI_CLK_FRQ;
    defparam u_die1.u_main_sm.u_rdi_sm.gating_logic.CLK_FREQ     = RDI_CLK_FRQ;

    // LTSM macro-state observation (state_n lives inside the LTSM wrapper).
    assign ln0 = u_die0.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state_n;
    assign ln1 = u_die1.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state_n;

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
    task automatic program_die_custom(input int die, input logic [3:0] target_width = 4'h2, input logic [3:0] target_speed = 4'h5, input bit force_x8 = 1'b0);
        logic [63:0] link_ctrl;
        link_ctrl = 64'b0;
        link_ctrl[1:0] = 2'b00;
        link_ctrl[5:2] = target_width;
        link_ctrl[9:6] = target_speed;
        link_ctrl[10]  = 1'b1; // start training
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

        tx_mask0   = u_die0.u_main_sm.u_ltsm_top.u_ltsm.mb_tx_data_lane_mask;
        rx_mask0   = u_die0.u_main_sm.u_ltsm_top.u_ltsm.mb_rx_data_lane_mask;
        tx_mask1   = u_die1.u_main_sm.u_ltsm_top.u_ltsm.mb_tx_data_lane_mask;
        rx_mask1   = u_die1.u_main_sm.u_ltsm_top.u_ltsm.mb_rx_data_lane_mask;
        width_sts0 = u_die0.ucie_link_status_r_out[10:7];
        width_sts1 = u_die1.ucie_link_status_r_out[10:7];
        // Speed: read directly from LTSM (ucie_link_status_r_out[14:11] is not wired)
        speed_sts0 = u_die0.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;
        speed_sts1 = u_die1.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status;

        $display("\n================================================================");
        $display("  ACTIVE LINK STATUS REPORT");
        $display("================================================================");
        $display("  [DIE 0] state=%s, RDI_sts=%s", ln0.name(), pl_state_sts0.name());
        $display("          Width : %s (code: %0h)",
                  (width_sts0 == 4'h2) ? "x16" : (width_sts0 == 4'h1) ? "x8" : "unknown", width_sts0);
        $display("          Speed : %s (code: %0h)", speed_str(speed_sts0), speed_sts0);
        $display("          TX Lane Mask: 3'b%b, RX Lane Mask: 3'b%b", tx_mask0, rx_mask0);
        $display("          Active Deser Lanes (RX): 16'h%h", u_die0.mb_rx_data_deser_en);
        $display("          Lane Reversal: %b  Width Degrade: %b",
                  u_die0.log0_lane_reversal, u_die0.log0_width_degrade);
        $display("  [DIE 1] state=%s, RDI_sts=%s", ln1.name(), pl_state_sts1.name());
        $display("          Width : %s (code: %0h)",
                  (width_sts1 == 4'h2) ? "x16" : (width_sts1 == 4'h1) ? "x8" : "unknown", width_sts1);
        $display("          Speed : %s (code: %0h)", speed_str(speed_sts1), speed_sts1);
        $display("          TX Lane Mask: 3'b%b, RX Lane Mask: 3'b%b", tx_mask1, rx_mask1);
        $display("          Active Deser Lanes (RX): 16'h%h", u_die1.mb_rx_data_deser_en);
        $display("          Lane Reversal: %b  Width Degrade: %b",
                  u_die1.log0_lane_reversal, u_die1.log0_width_degrade);
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
        
        ctrl0     = u_die0.u_reg_file.ucie_link_ctrl_r_out;
        phy_ctrl0 = u_die0.u_reg_file.phy_control_r_out;
        cap0      = u_die0.u_reg_file.ucie_link_cap_r_out;
        
        ctrl1     = u_die1.u_reg_file.ucie_link_ctrl_r_out;
        phy_ctrl1 = u_die1.u_reg_file.phy_control_r_out;
        cap1      = u_die1.u_reg_file.ucie_link_cap_r_out;

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
    bit data_pass;
    initial begin
        $display("================================================================");
        $display("  STARTING UCIe_PHY INTEGRATION TESTBENCH (Logical_PHY + Reg_File)");
        $display("  Adapter programs Reg_File over sideband; observes via (.)");
        $display("================================================================\n");

        // ----------------------------------------------------------------
        // Scenario 1: Happy Path -> ACTIVE + status print + data transfer
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC1] Happy Path training to ACTIVE...", $time);
        reset_system();
        // Program dies first (so print_ctrl_regs shows the written values),
        // then do_bringup will re-program and wait for ACTIVE.
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        do_bringup(ok);
        chk(ok, "SC1 both dies reached LOG_ACTIVE");
        if (ok) begin
            print_active_status();
            do_data_transfer(data_pass);
            chk(data_pass, "SC1 data transfer verified successfully");
        end

        // ----------------------------------------------------------------
        // Scenario 2: Watchdog Timeout (SB blocked)
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC2] TrainError (sideband blocked)...", $time);
        reset_system();
        block_sideband = 1'b1;
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        fork
            begin wait (m_error); $display("T=%0t | [SC2] die0 TRAINERROR as expected.", $time); end
            begin wait (m_done);  $error("T=%0t | [SC2] reached ACTIVE with blocked SB?", $time); fails++; end
            begin repeat (8000) @(posedge lclk0);
                  $error("T=%0t | [SC2] TIMEOUT (watchdog did not fire).", $time); fails++; end
        join_any
        disable fork;
        chk(m_error, "SC2 watchdog produced TRAINERROR");

        // ----------------------------------------------------------------
        // Scenario 3: Asymmetric Width Negotiation (x16 vs x8 -> x8)
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC3] Asymmetric Width: Die0 requests x16, Die1 requests x8...", $time);
        reset_system();
        fork
            program_die_custom(0, 4'h2, 4'h5, 1'b0);
            program_die_custom(1, 4'h1, 4'h5, 1'b1);
        join
        print_ctrl_regs();
        do_bringup_custom(ok, 4'h2, 4'h1, 1'b0, 1'b1); // force x8 on Die1
        chk(ok, "SC3 both dies reached LOG_ACTIVE");
        if (ok) begin
            print_active_status();
            do_data_transfer(data_pass);
            chk(data_pass, "SC3 data transfer verified successfully on negotiated x8 link");
        end

        // ----------------------------------------------------------------
        // Scenario 4: Lane Reversal + Retry (Symmetric reversal)
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC4] Symmetric Lane Reversal: Both dies reverse package routes...", $time);
        reset_system();
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        reverse_lanes_0to1 = 1'b1;
        reverse_lanes_1to0 = 1'b1;
        do_bringup(ok);
        chk(ok, "SC4 both dies reached LOG_ACTIVE");
        if (ok) begin
            print_active_status();
            do_data_transfer(data_pass);
            chk(data_pass, "SC4 data transfer verified successfully with symmetric lane reversal");
        end

        // ----------------------------------------------------------------
        // Scenario 5: Asymmetric Lane Reversal
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC5] Asymmetric Lane Reversal: Only Die0 reverses package routes...", $time);
        reset_system();
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        reverse_lanes_0to1 = 1'b1;
        reverse_lanes_1to0 = 1'b0;
        do_bringup(ok);
        chk(ok, "SC5 both dies reached LOG_ACTIVE");
        if (ok) begin
            print_active_status();
            do_data_transfer(data_pass);
            chk(data_pass, "SC5 data transfer verified successfully with asymmetric lane reversal");
        end

        // ----------------------------------------------------------------
        // Scenario 6: Width Degradation with Retry (Fault lanes 8..15 on Die 0)
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC6] Width Degradation: Fault lanes 8..15 -> degrade x16 to x8...", $time);
        reset_system();
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        corrupt_0to1 = 16'hFF00; // corrupt lanes 8..15
        do_bringup(ok);
        chk(ok, "SC6 both dies reached LOG_ACTIVE");
        if (ok) begin
            print_active_status();
            do_data_transfer(data_pass);
            chk(data_pass, "SC6 data transfer verified successfully after width degradation to x8");
        end

        // ----------------------------------------------------------------
        // Scenario 7: PM mode (L1) entry + wake
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC7] PM mode (L1) entry + wake...", $time);
        reset_system();
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        do_bringup(ok);
        chk(ok, "SC7 bring-up to ACTIVE");
        if (ok) begin
            $display("T=%0t | [SC7] ACTIVE. die0 initiates L1; die1 responds...", $time);
            @(negedge lclk0);
            lp_state_req0 = L_1;
            fork
                begin wait (u_die1.u_main_sm.u_rdi_sm.sm.u_unit_active_state.current_state == 26'h0800000);
                      @(negedge lclk1); lp_state_req1 = L_1; end
                begin repeat (8000) @(posedge lclk0); $error("[SC7] TO: die1 never reached WAIT"); fails++; end
            join_any
            disable fork;
            fork
                begin wait (ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2);
                      $display("T=%0t | [SC7] both dies in L1.", $time); end
                begin repeat (8000) @(posedge lclk0); $error("[SC7] TO entering L1"); fails++; end
            join_any
            disable fork;
            chk(ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2, "SC7 both dies entered L1 (PM)");

            // Wake: request Active again -> re-train back to ACTIVE
            @(negedge lclk0);
            lp_state_req0 = Active; lp_state_req1 = Active;
            fork
                begin wait (m_done && p_done); $display("T=%0t | [SC7] re-trained to ACTIVE after L1.", $time); end
                begin wait (m_error || p_error); $error("[SC7] err during wake"); fails++; end
                begin repeat (100000) @(posedge lclk0); $error("[SC7] TO during wake"); fails++; end
            join_any
            disable fork;
            chk(m_done && p_done, "SC7 L1 wake re-trained to ACTIVE");
            if (m_done && p_done) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "SC7 data transfer verified successfully after L1 wake");
            end
        end

        // ----------------------------------------------------------------
        // Scenario 8: L2 entry, exit to RESET, and re-train recovery
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC8] PM mode (L2) entry, exit to RESET, and recovery...", $time);
        reset_system();
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        do_bringup(ok);
        chk(ok, "SC8 bring-up to ACTIVE");
        if (ok) begin
            $display("T=%0t | [SC8] ACTIVE. Both dies request L2...", $time);
            @(negedge lclk0);
            lp_state_req0 = L_2;
            fork
                begin wait (u_die1.u_main_sm.u_rdi_sm.sm.u_unit_active_state.current_state == 26'h0800000);
                      @(negedge lclk1); lp_state_req1 = L_2; end
                begin repeat (8000) @(posedge lclk0); $error("[SC8] TO: die1 never reached WAIT"); fails++; end
            join_any
            disable fork;
            fork
                begin wait (ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2);
                      $display("T=%0t | [SC8] both dies in L2 (LOG_L1_L2).", $time); end
                begin repeat (8000) @(posedge lclk0); $error("[SC8] TO entering L2"); fails++; end
            join_any
            disable fork;
            chk(ln0 == LOG_L1_L2 && ln1 == LOG_L1_L2, "SC8 both dies entered L2");

            // Exit L2 to RESET
            @(negedge lclk0);
            lp_state_req0 = Reset; lp_state_req1 = Reset;
            fork
                begin wait (ln0 == LOG_RESET && ln1 == LOG_RESET);
                      $display("T=%0t | [SC8] both dies in RESET.", $time); end
                begin repeat (8000) @(posedge lclk0); $error("[SC8] TO entering RESET from L2"); fails++; end
            join_any
            disable fork;
            chk(ln0 == LOG_RESET && ln1 == LOG_RESET, "SC8 exited L2 to RESET successfully");

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
                begin wait (m_done && p_done); $display("T=%0t | [SC8] recovered and re-trained to ACTIVE.", $time); end
                begin wait (m_error || p_error); $error("[SC8] err during recovery"); fails++; end
                begin repeat (100000) @(posedge lclk0); $error("[SC8] TO during recovery"); fails++; end
            join_any
            disable fork;
            chk(m_done && p_done, "SC8 recovery training succeeded");
            if (m_done && p_done) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "SC8 data transfer verified successfully after L2 recovery");
            end
        end

        // ----------------------------------------------------------------
        // Scenario 9: TRAINERROR entry (rdi=LinkError), clear, recover
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC9] TRAINERROR: fault link, hold, clear, re-train...", $time);
        reset_system();
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        do_bringup(ok);
        chk(ok, "SC9 bring-up to ACTIVE");
        if (ok) begin
            $display("T=%0t | [SC9] Injecting fault (lp_state_req=LinkError)...", $time);
            @(negedge lclk0);
            lp_state_req0 = LinkError;
            lp_state_req1 = LinkError;

            fork
                begin
                    wait (m_error && p_error);
                    $display("T=%0t | [SC9] Both dies entered TRAINERROR state.", $time);
                end
                begin
                    repeat(5000) @(posedge lclk0);
                    $error("T=%0t | [SC9] TIMEOUT -- Dies did not enter TRAINERROR.", $time);
                    $finish;
                end
            join_any
            disable fork;

            // Clear fault, return to RESET
            @(negedge lclk0);
            lp_state_req0 = Reset;
            lp_state_req1 = Reset;

            fork
                begin
                    wait (ln0 == LOG_RESET && ln1 == LOG_RESET);
                    $display("T=%0t | [SC9] Both dies cleared TRAINERROR to RESET.", $time);
                end
                begin
                    repeat(5000) @(posedge lclk0);
                    $error("T=%0t | [SC9] TIMEOUT -- Dies did not reach RESET from TRAINERROR.", $time);
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
                    wait (m_done && p_done);
                    $display("T=%0t | [SC9] PASS -- Re-trained to ACTIVE after TRAINERROR.", $time);
                end
                begin
                    repeat(100000) @(posedge lclk0);
                    $error("T=%0t | [SC9] TIMEOUT -- Post-TRAINERROR re-train hung.", $time);
                    $finish;
                end
            join_any
            disable fork;
            chk(m_done && p_done, "SC9 TRAINERROR recovery succeeded");
            if (m_done && p_done) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "SC9 data transfer verified successfully after TRAINERROR recovery");
            end
        end

        // ----------------------------------------------------------------
        // Scenario 10: Valid Lane boundary error injection
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC10] Valid Lane Boundary Error Injection test...", $time);
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
        join_none

        fork
            begin
                // Wait until Die 1's valid deserializer enters compare state (o_state === 2'b10)
                wait (u_die1.u_mb_die.u_rx_top.u_valid_des.o_state === 2'b10);
                $display("T=%0t | [SC10] Die 1 valid deserializer entered compare state.", $time);
                
                // Wait for edge of sample_clk and count = 15 (end of frame)
                @(posedge u_die1.u_mb_die.u_rx_top.sample_clk);
                wait (u_die1.u_mb_die.u_rx_top.u_valid_des.o_count == 4'd15);
                
                // Pulse error injection on the next clock cycle to corrupt the boundary
                @(posedge u_die1.u_mb_die.u_rx_top.sample_clk);
                rx_vld_error_inject_0_to_1 = 1'b1;
                $display("T=%0t | [SC10] Injecting valid lane boundary error...", $time);
                
                @(posedge u_die1.u_mb_die.u_rx_top.sample_clk);
                rx_vld_error_inject_0_to_1 = 1'b0;
                $display("T=%0t | [SC10] Error injection cleared.", $time);
            end
            begin
                wait (m_done && p_done);
                $display("T=%0t | [SC10] Both dies reached ACTIVE successfully.", $time);
            end
            begin
                repeat(200000) @(posedge lclk0);
                $error("T=%0t | [SC10] TIMEOUT -- Training hung during error injection.", $time);
                $finish;
            end
        join_any
        disable fork;

        chk(m_done && p_done, "SC10 boundary error test succeeded");
        if (m_done && p_done) begin
            print_active_status();
            do_data_transfer(data_pass);
            chk(data_pass, "SC10 data transfer verified successfully after boundary error survival");
        end

        // ----------------------------------------------------------------
        // Scenario 11: MBTRAIN Lane Degradation (REPAIR triggered mid-train)
        // ----------------------------------------------------------------
        // Lanes 8..15 are injected as faulty AFTER MBINIT completes (so MBINIT
        // sees x16 OK) but DURING MBTRAIN D2C sweeps.  MBTRAIN.REPAIR should
        // detect the failing upper lanes and degrade to x8 lower.
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC11] MBTRAIN REPAIR: inject lane fault AFTER MBINIT -> degrade in MBTRAIN...", $time);
        reset_system();
        fork program_die(0); program_die(1); join
        print_ctrl_regs();
        lp_state_req0 = Nop; lp_state_req1 = Nop;
        fork
            begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
            begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
        join_none
        fork
            begin
                // Wait until MBTRAIN begins (past MBINIT), then corrupt lanes 8-15
                wait (ln0 == LOG_MBTRAIN_VALVREF);
                @(posedge lclk0);
                corrupt_0to1 = 16'hFF00;  // lanes 8-15 bad on Die0->Die1 path
                $display("T=%0t | [SC11] MBTRAIN started – injecting lanes 8-15 fault.", $time);
            end
            begin wait (m_done && p_done); ok = 1'b1; end
            begin wait (m_error || p_error); ok = 1'b0; $error("[SC11] TRAINERROR during MBTRAIN fault injection"); end
            begin repeat (600000) @(posedge lclk0); ok = 1'b0; $error("[SC11] TIMEOUT"); end
        join_any
        disable fork;
        corrupt_0to1 = 16'h0000; // remove fault after training done
        chk(ok, "SC11 MBTRAIN REPAIR degraded lanes and reached ACTIVE");
        if (ok) begin
            print_active_status();
            do_data_transfer(data_pass);
            chk(data_pass, "SC11 data transfer verified after MBTRAIN lane degradation");
        end

        // ----------------------------------------------------------------
        // Scenario 12: MBTRAIN Speed Degradation (dies have different speeds)
        // ----------------------------------------------------------------
        // MBINIT: upper 8 lanes corrupt → MBINIT degrades to x8 lower (3'b001).
        // No further width degrade is possible in MBTRAIN (neither die requested
        // explicit x8, so REPAIR sees FULL = x16 target → 3'b000 = not possible).
        // Instead the two dies have different max speeds so MBTRAIN.LINKSPEED
        // negotiates down to the lower speed. Expect ACTIVE with x8 + lower speed.
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC12] Speed Degradation: different max speeds on Die0 vs Die1...", $time);
        reset_system();
        // Die0: x16 target, Gen5 speed
        // Die1: x16 target, Gen3 speed (lower capability)
        fork
            program_die_custom(0, 4'h2, 4'h5, 1'b0);
            program_die_custom(1, 4'h2, 4'h3, 1'b0);
        join
        print_ctrl_regs();
        // Corrupt lanes 8-15 permanently so MBINIT degrades to x8
        corrupt_0to1 = 16'hFF00;
        begin : sc12_bringup
            bit ok12;
            ok12 = 1'b0;
            lp_state_req0 = Nop; lp_state_req1 = Nop;
            fork
                begin wait (ln0 == LOG_LINKINIT); @(negedge lclk0); lp_state_req0 = Active; end
                begin wait (ln1 == LOG_LINKINIT); @(negedge lclk1); lp_state_req1 = Active; end
            join_none
            fork
                begin wait (m_done && p_done && pl_state_sts0 == Active && pl_state_sts1 == Active); ok12 = 1'b1; end
                begin wait (m_error || p_error); ok12 = 1'b0; $error("[SC12] training error"); end
                begin repeat (600000) @(posedge lclk0); ok12 = 1'b0; $error("[SC12] TIMEOUT"); end
            join_any
            disable fork;
            corrupt_0to1 = 16'h0000;
            chk(ok12, "SC12 Speed-degraded link reached ACTIVE");
            if (ok12) begin
                print_active_status();
                do_data_transfer(data_pass);
                chk(data_pass, "SC12 data transfer verified after speed degradation");
            end
        end

        // ----------------------------------------------------------------
        // Scenario 13: Target settings in Control Reg > Hardware Capabilities
        // ----------------------------------------------------------------
        $display("\nT=%0t | [SC13] Capping check: program target width/speed > capabilities...", $time);
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
                begin wait (m_error || p_error); ok13 = 1'b0; $error("[SC13] training error"); end
                begin repeat (600000) @(posedge lclk0); ok13 = 1'b0; $error("[SC13] TIMEOUT"); end
            join_any
            disable fork;
            chk(ok13, "SC13 capped link reached ACTIVE successfully");
            if (ok13) begin
                print_active_status();
                // Assert that negotiated width status is x16 (code 4'h2) and speed status is 32 GT/s (code 4'h5)
                chk(u_die0.u_reg_file.ucie_link_status_r_out[10:7] == 4'h2, "SC13 Die0 negotiated width is x16 (cap capped)");
                chk(u_die1.u_reg_file.ucie_link_status_r_out[10:7] == 4'h2, "SC13 Die1 negotiated width is x16 (cap capped)");
                chk(u_die0.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == 4'h5, "SC13 Die0 negotiated speed is 32 GT/s (cap capped)");
                chk(u_die1.u_main_sm.u_ltsm_top.u_ltsm.reg_Link_Speed_enable_status == 4'h5, "SC13 Die1 negotiated speed is 32 GT/s (cap capped)");
                
                do_data_transfer(data_pass);
                chk(data_pass, "SC13 data transfer verified successfully at capped settings");
            end
        end

        // ----------------------------------------------------------------
        $display("\n================================================================");
        if (fails == 0) $display("  RESULT: PASS  (UCIe_PHY INTEGRATION SIM PASS)");
        else            $display("  RESULT: FAIL  (%0d failing checks)", fails);
        $display("================================================================\n");
        $finish;
    end

    // Global watchdog
    initial begin
        #(200_000_000);   // 200 ms sim-time hard stop (covers SC1-SC12 including repair/speed scenarios)
        $error("GLOBAL TIMEOUT - simulation did not finish");
        $finish;
    end

    initial begin
        forever begin
            @(u_die0.u_main_sm.u_ltsm_top.u_ltsm.mbinit_rx_data_lane_mask or 
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.mbinit_tx_data_lane_mask or
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.mbtrain_mb_rx_data_lane_mask or
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.mbtrain_mb_tx_data_lane_mask or
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.mb_rx_data_lane_mask or
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.mb_tx_data_lane_mask or
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state or
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.mb_rx_data_lane_mask_r or
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.mbinit_rx_data_lane_mask or
              u_die0.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.update_data_lane_mask_by_mbinit_result or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.mbinit_rx_data_lane_mask or 
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.mbinit_tx_data_lane_mask or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.mbtrain_mb_rx_data_lane_mask or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.mbtrain_mb_tx_data_lane_mask or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.mb_rx_data_lane_mask or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.mb_tx_data_lane_mask or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.mb_rx_data_lane_mask_r or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.mbinit_rx_data_lane_mask or
              u_die1.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.update_data_lane_mask_by_mbinit_result);
            $display("T=%0t | [DEBUG MONITOR] DIE0 state=%s, mbinit_rx=%b, mbtrain_rx=%b, mb_rx=%b, p_state=%s, p_mb_rx_r=%b, p_mbinit_rx=%b, p_upd=%b",
                     $time,
                     u_die0.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state.name(),
                     u_die0.u_main_sm.u_ltsm_top.u_ltsm.mbinit_rx_data_lane_mask,
                     u_die0.u_main_sm.u_ltsm_top.u_ltsm.mbtrain_mb_rx_data_lane_mask,
                     u_die0.u_main_sm.u_ltsm_top.u_ltsm.mb_rx_data_lane_mask,
                     u_die0.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.current_state.name(),
                     u_die0.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.mb_rx_data_lane_mask_r,
                     u_die0.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.mbinit_rx_data_lane_mask,
                     u_die0.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.update_data_lane_mask_by_mbinit_result);
            $display("T=%0t | [DEBUG MONITOR] DIE1 state=%s, mbinit_rx=%b, mbtrain_rx=%b, mb_rx=%b, p_state=%s, p_mb_rx_r=%b, p_mbinit_rx=%b, p_upd=%b",
                     $time,
                     u_die1.u_main_sm.u_ltsm_top.u_ltsm.current_ltsm_state.name(),
                     u_die1.u_main_sm.u_ltsm_top.u_ltsm.mbinit_rx_data_lane_mask,
                     u_die1.u_main_sm.u_ltsm_top.u_ltsm.mbtrain_mb_rx_data_lane_mask,
                     u_die1.u_main_sm.u_ltsm_top.u_ltsm.mb_rx_data_lane_mask,
                     u_die1.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.current_state.name(),
                     u_die1.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.mb_rx_data_lane_mask_r,
                     u_die1.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.mbinit_rx_data_lane_mask,
                     u_die1.u_main_sm.u_ltsm_top.u_ltsm.u_mbtrain.u_REPAIR.u_REPAIR_partner.update_data_lane_mask_by_mbinit_result);
        end
    end

endmodule