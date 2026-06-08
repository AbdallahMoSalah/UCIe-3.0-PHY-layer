`timescale 1ns/1ps
// =============================================================================
// Testbench : unit_mb_train_seq_tb
// DUT       : unit_mb_loopback_wrapper  (unit_tx_top  ->  unit_mb_rx_top)
//
//  Goal
//  ----
//  Drive the COMPLETE Main-Band link-training sequence end-to-end and prove that
//  the link only reaches the ACTIVE (DATA_TRANSFER) state when every training
//  step passes, and aborts with an error if any step fails.
//
//  Training order (single run)
//  ---------------------------
//    0. CLOCK TEST  : clk_pattern_en=1, embedded_en=0, run the clock-pattern
//                     detector until clk_p / clk_n / track all PASS. This is the
//                     ONLY time the clock lane is tested; afterwards the embedded
//                     clock is forwarded (embedded_en=1) for the rest of training
//                     so the RX deserialisers have their sampling clock.
//    1. VALID  m0   : valid lane framed, valid comparator mode 0 (16 consecutive).
//    2. DATA perlane: TX PER_LANE_IDE  vs  RX local per-lane-ID reference.
//    3. DATA lfsr   : TX PATTERN_LFSR   vs  RX local PRBS reference.
//    4. SPEED UP    : bump the PLL speed (period halves). The RX sampling delay
//                     tracks i_period automatically; the clock is NOT re-tested.
//    5. VALID  m1   : valid comparator mode 1 (bit-error threshold).
//    6. DATA perlane: repeat at the new speed.
//    7. DATA lfsr   : repeat at the new speed.
//    8. ACTIVE      : DATA_TRANSFER. Stream flits mapper->...->demapper and check
//                     the recovered flit equals the transmitted one.
//
//  The forwarded clock stays alive across the whole sequence (the clock lane is
//  tested once). Between training sub-phases the RX datapath is re-initialised
//  with a reset pulse: the lfsr_rx / lfsr_tx pattern generators only enter a
//  training state on a clean edge out of IDLE, exactly as the production LTSM
//  re-arms them per sub-state. embedded_en and the PLL speed select persist
//  across these resets.
//
//  Every step is gated: a failure prints an error and aborts the run BEFORE
//  ACTIVE is reached. The bench runs the clean sequence (must reach ACTIVE) and
//  then fault-injected sequences (clock / valid / data corruption) which must
//  each abort and never reach ACTIVE.
//
//  Run : make run CONFIG=integration_mb_train_seq TOP=unit_mb_train_seq_tb
// =============================================================================

module unit_mb_train_seq_tb;

    // ---------------------------------------------------------------- params
    localparam int DATA_WIDTH = 32;
    localparam int NUM_LANES  = 16;
    localparam int N_BYTES    = 64;
    localparam int FLITW      = 8*N_BYTES;

    localparam logic [2:0] LFSR_IDLE     = 3'b000;
    localparam logic [2:0] LFSR_PATTERN  = 3'b010;   // PATTERN_LFSR
    localparam logic [2:0] LFSR_PERLANE  = 3'b011;   // PER_LANE_IDE
    localparam logic [2:0] LFSR_DATA     = 3'b100;   // DATA_TRANSFER
    localparam logic [2:0] WIDTH_DEG_ALL = 3'b011;   // x16

    localparam logic [1:0] RXMODE_DATA    = 2'd0;
    localparam logic [1:0] RXMODE_PATTERN = 2'd1;
    localparam logic [1:0] RXMODE_PERLANE = 2'd2;

    // fault selectors
    localparam int FAULT_NONE   = 0;
    localparam int FAULT_CLK    = 1;   // corrupt the clock lane during CLOCK TEST
    localparam int FAULT_VALID  = 2;   // corrupt the valid lane during VALID m0
    localparam int FAULT_DATA   = 3;   // corrupt a data lane during DATA perlane

    // ----------------------------------------------------------------- DUT IO
    logic                  i_rst_n;
    logic [FLITW-1:0]      lp_data;
    logic                  lp_irdy, lp_valid, pl_trdy;
    logic                  i_mapper_en;
    logic [2:0]            i_width_deg;
    logic [2:0]            i_lfsr_state;
    logic                  i_reversal_en;
    logic                  i_valid_pattern_en;
    logic                  i_pll_en;
    logic [1:0]            i_pll_speed_sel;
    logic                  lclk_g;
    logic                  i_clk_pattern_en, i_clk_embedded_en;

    logic [1:0]            i_rx_mode;
    logic                  i_pcmp_enable, i_pcmp_mode, i_pcmp_pattern_mode, i_pcmp_clear;
    logic [NUM_LANES-1:0]  i_pcmp_lane_mask;
    logic [15:0]           i_pcmp_thr_per_lane, i_pcmp_thr_aggregate, i_pcmp_iter_count;
    logic                  i_vcmp_enable, i_vcmp_mode, i_vcmp_clear;
    logic [15:0]           i_vcmp_thr;
    logic                  i_clk_detector_en;

    logic                  lclk, o_pll_clk, o_rx_pll_clk;
    logic                  o_lfsr_tx_done, o_valid_done, o_clk_done;
    logic [NUM_LANES-1:0]  TD_P;
    logic                  TVLD_P, TCKP_P, TCKN_P, TTRK_P;

    logic [DATA_WIDTH-1:0] o_par_data [0:NUM_LANES-1];
    logic                  o_data_valid, o_valid_frame_pulse;
    logic [DATA_WIDTH-1:0] o_rx_lane  [0:NUM_LANES-1];
    logic                  o_rx_en, o_pattern_comp_en;
    logic [FLITW-1:0]      o_out_data;
    logic                  o_pl_valid;
    logic                  o_pcmp_done, o_pcmp_agg_error;
    logic [NUM_LANES-1:0]  o_pcmp_per_lane_pass;
    logic [15:0]           o_pcmp_agg_err_cnt;
    logic                  o_vcmp_done, o_vcmp_pass;
    logic                  o_clk_p_pass, o_clk_n_pass, o_track_pass;

    // ---------------------------------------------------------------- DUT
    unit_mb_loopback_wrapper #(
        .DATA_WIDTH    (DATA_WIDTH),
        .NUM_LANES     (NUM_LANES),
        .N_BYTES       (N_BYTES),
        .VALID_PATTERN (32'h0F0F0F0F),
        .PLL_PERIOD_NS (0.5),
        .RX_ALIGN_DELAY(2)
    ) dut (
        .i_rst_n            (i_rst_n),
        .lp_data            (lp_data),
        .lp_irdy            (lp_irdy),
        .lp_valid           (lp_valid),
        .pl_trdy            (pl_trdy),
        .i_mapper_en        (i_mapper_en),
        .i_width_deg        (i_width_deg),
        .i_lfsr_state       (i_lfsr_state),
        .i_reversal_en      (i_reversal_en),
        .i_valid_pattern_en (i_valid_pattern_en),
        .i_pll_en           (i_pll_en),
        .i_pll_speed_sel    (i_pll_speed_sel),
        .lclk_g             (lclk_g),
        .i_clk_pattern_en   (i_clk_pattern_en),
        .i_clk_embedded_en  (i_clk_embedded_en),

        .i_rx_mode            (i_rx_mode),
        .i_pcmp_enable        (i_pcmp_enable),
        .i_pcmp_mode          (i_pcmp_mode),
        .i_pcmp_lane_mask     (i_pcmp_lane_mask),
        .i_pcmp_thr_per_lane  (i_pcmp_thr_per_lane),
        .i_pcmp_thr_aggregate (i_pcmp_thr_aggregate),
        .i_pcmp_iter_count    (i_pcmp_iter_count),
        .i_pcmp_pattern_mode  (i_pcmp_pattern_mode),
        .i_pcmp_clear         (i_pcmp_clear),
        .i_vcmp_enable        (i_vcmp_enable),
        .i_vcmp_mode          (i_vcmp_mode),
        .i_vcmp_thr           (i_vcmp_thr),
        .i_vcmp_clear         (i_vcmp_clear),
        .i_clk_detector_en    (i_clk_detector_en),

        .lclk               (lclk),
        .o_pll_clk          (o_pll_clk),
        .o_rx_pll_clk       (o_rx_pll_clk),
        .o_lfsr_tx_done     (o_lfsr_tx_done),
        .o_valid_done       (o_valid_done),
        .o_clk_done         (o_clk_done),
        .TD_P               (TD_P),
        .TVLD_P             (TVLD_P),
        .TCKP_P             (TCKP_P),
        .TCKN_P             (TCKN_P),
        .TTRK_P             (TTRK_P),

        .o_par_data         (o_par_data),
        .o_data_valid       (o_data_valid),
        .o_valid_frame_pulse(o_valid_frame_pulse),
        .o_rx_lane          (o_rx_lane),
        .o_rx_en            (o_rx_en),
        .o_pattern_comp_en  (o_pattern_comp_en),

        .o_out_data           (o_out_data),
        .o_pl_valid           (o_pl_valid),
        .o_pcmp_done          (o_pcmp_done),
        .o_pcmp_per_lane_pass (o_pcmp_per_lane_pass),
        .o_pcmp_agg_err_cnt   (o_pcmp_agg_err_cnt),
        .o_pcmp_agg_error     (o_pcmp_agg_error),
        .o_vcmp_done          (o_vcmp_done),
        .o_vcmp_pass          (o_vcmp_pass),
        .o_clk_p_pass         (o_clk_p_pass),
        .o_clk_n_pass         (o_clk_n_pass),
        .o_track_pass         (o_track_pass)
    );

    // ---------------------------------------------------------------- helpers
    task automatic wait_pll(input int n); repeat (n) @(posedge o_pll_clk); endtask
    task automatic wait_mb (input int n); repeat (n) @(posedge lclk);      endtask

    int  scenarios_pass, scenarios_fail;

    // -------------------------------------------------------------------------
    // Reset/re-init the RX datapath. The PLL free-runs, so i_pll_speed_sel and
    // i_clk_embedded_en persist; embedded_clk picks whether the forwarded clock
    // is live coming out of reset (1 for every phase after the clock test).
    // -------------------------------------------------------------------------
    task automatic link_reset(input bit embedded_clk);
        @(negedge o_pll_clk); i_rst_n = 0;
        lp_data='0; lp_irdy=0; lp_valid=0; i_mapper_en=0;
        i_lfsr_state=LFSR_IDLE; i_reversal_en=0; i_valid_pattern_en=0;
        i_clk_pattern_en=0; i_clk_detector_en=0; i_clk_embedded_en=embedded_clk;
        i_rx_mode=RXMODE_DATA;
        i_pcmp_enable=0; i_pcmp_mode=0; i_pcmp_pattern_mode=0; i_pcmp_clear=0;
        i_pcmp_lane_mask='0; i_pcmp_thr_per_lane='0; i_pcmp_thr_aggregate='0;
        i_pcmp_iter_count=16'd32;
        i_vcmp_enable=0; i_vcmp_mode=0; i_vcmp_clear=0; i_vcmp_thr=16'd0;
        wait_pll(8);
        @(negedge o_pll_clk); i_rst_n = 1;
        wait_pll(20); wait_mb(4);
    endtask

    // Begin streaming: select RX mode, enable the mapper, then enter the chosen
    // TX lfsr state one cycle later (clean edge for the lfsr_rx FSM).
    task automatic start_stream(input [1:0] rxmode, input [2:0] lfsr_st);
        @(negedge lclk);
        i_rx_mode  = rxmode;
        i_mapper_en=1; lp_irdy=1; lp_valid=1; lp_data='0;
        @(negedge lclk); i_lfsr_state = lfsr_st;
    endtask

    // -------------------------------------------------------------------------
    // PHASE 0 : clock-lane test (burst pattern + clock detector). Leaves the
    // link ready to forward the embedded clock for the following phases.
    // -------------------------------------------------------------------------
    task automatic phase_clock_test(input string lbl, input int fault, output bit ok);
        int t;
        link_reset(.embedded_clk(0));                 // burst mode: embedded off
        // dead clock lane as seen by the RX clock-pattern detector
        if (fault == FAULT_CLK) force dut.u_rx_top.i_TCKP_P = 1'b0;
        @(negedge o_pll_clk); i_clk_pattern_en=1; i_clk_detector_en=1;
        t = 0;
        while (!(o_clk_p_pass && o_clk_n_pass && o_track_pass) && t < 4000) begin
            @(posedge o_rx_pll_clk); t++;
        end
        ok = (o_clk_p_pass && o_clk_n_pass && o_track_pass);
        $display("  [%s] CLOCK TEST  : clk_p=%0b clk_n=%0b track=%0b  (%0d clk)%s",
                 lbl, o_clk_p_pass, o_clk_n_pass, o_track_pass, t, ok ? "" : "  <-- FAIL");
        if (fault == FAULT_CLK) release dut.u_rx_top.i_TCKP_P;
        @(negedge o_pll_clk); i_clk_pattern_en=0; i_clk_detector_en=0;
    endtask

    // -------------------------------------------------------------------------
    // PHASE 1/5 : valid-lane comparator test. mode 0 = 16 consecutive, mode 1 =
    // bit-error threshold. Continuous valid framing comes from DATA_TRANSFER.
    // -------------------------------------------------------------------------
    task automatic phase_valid_test(input string lbl, input bit mode1, input int fault, output bit ok);
        int t;
        link_reset(.embedded_clk(1));
        // valid lane tracks the clock => recovers 0x55../0xAA.. != 0x0F0F0F0F
        if (fault == FAULT_VALID) force dut.u_rx_top.i_TVLD_P = dut.u_rx_top.i_TCKP_P;
        start_stream(RXMODE_DATA, LFSR_DATA);
        t = 0; while (!o_rx_en && t < 400) begin @(posedge lclk); t++; end

        @(negedge lclk); i_vcmp_mode = mode1; i_vcmp_thr = 16'd0; i_vcmp_clear = 1;
        @(negedge lclk); i_vcmp_clear = 0;
        @(negedge lclk); i_vcmp_enable = 1;

        t = 0; while (!o_vcmp_done && t < 2000) begin @(posedge lclk); t++; end
        ok = (o_vcmp_done && o_vcmp_pass);
        $display("  [%s] VALID  m%0d  : rx_en=%0b done=%0b pass=%0b  (%0d clk)%s",
                 lbl, mode1, o_rx_en, o_vcmp_done, o_vcmp_pass, t, ok ? "" : "  <-- FAIL");

        @(negedge lclk); i_vcmp_enable = 0;
        if (fault == FAULT_VALID) release dut.u_rx_top.i_TVLD_P;
    endtask

    // -------------------------------------------------------------------------
    // PHASE 2/3/6/7 : data-lane training-pattern comparator test.
    //   pat_mode 1 = PER_LANE_IDE   (per-lane ID reference)
    //   pat_mode 0 = PATTERN_LFSR   (PRBS reference)
    // Pass when all 16 lanes match the locally generated reference.
    // -------------------------------------------------------------------------
    task automatic phase_data_test(input string lbl,
                                    input [1:0]  rxmode,
                                    input [2:0]  lfsr_st,
                                    input bit    pat_mode,
                                    input [15:0] iter,
                                    input int    fault,
                                    output bit   ok);
        int t;
        link_reset(.embedded_clk(1));
        if (fault == FAULT_DATA) force dut.u_rx_top.i_TD_P[3] = 1'b0;  // stuck data lane 3

        @(negedge lclk);
        i_pcmp_mode         = 0;          // per-lane comparison
        i_pcmp_pattern_mode = pat_mode;
        i_pcmp_lane_mask    = '0;
        i_pcmp_thr_per_lane = 16'd0;
        i_pcmp_thr_aggregate= 16'd0;
        i_pcmp_iter_count   = iter;
        i_pcmp_enable       = 0;
        i_pcmp_clear        = 1;
        @(negedge lclk); i_pcmp_clear = 0;

        start_stream(rxmode, lfsr_st);

        t = 0; while (!o_rx_en && t < 400) begin @(posedge lclk); t++; end
        if (o_rx_en) begin
            t = 0; while (!o_pattern_comp_en && t < 400) begin @(posedge lclk); t++; end
            wait_mb(3);
            @(negedge lclk); i_pcmp_enable = 1;
            t = 0; while (!o_pcmp_done && t < 800) begin @(posedge lclk); t++; end
        end
        ok = (o_rx_en && o_pcmp_done && (o_pcmp_per_lane_pass === 16'hFFFF));
        $display("  [%s] %-12s: rx_en=%0b done=%0b per_lane=0x%04h agg_err=%0d%s",
                 lbl, (pat_mode ? "DATA perlane" : "DATA lfsr"),
                 o_rx_en, o_pcmp_done, o_pcmp_per_lane_pass, o_pcmp_agg_err_cnt,
                 ok ? "" : "  <-- FAIL");

        @(negedge lclk); i_pcmp_enable = 0;
        if (fault == FAULT_DATA) release dut.u_rx_top.i_TD_P[3];
    endtask

    // -------------------------------------------------------------------------
    // PHASE 8 : ACTIVE. Stream flits and check the recovered flit == transmitted.
    // -------------------------------------------------------------------------
    task automatic run_flit(input logic [FLITW-1:0] flit, input string nm, output bit ok);
        int t; bit got;
        @(negedge lclk); lp_data = flit;
        got = 0; t = 0;
        while (!got && t < 400) begin
            @(posedge lclk);
            if (o_pl_valid && (o_out_data === flit)) got = 1;
            t++;
        end
        ok = got;
        $display("      flit %-12s : %s (settle %0d clk)", nm, got ? "MATCH" : "MISMATCH", t);
    endtask

    task automatic phase_active(input string lbl, output bit ok);
        bit a, b, c; logic [FLITW-1:0] f;
        link_reset(.embedded_clk(1));
        start_stream(RXMODE_DATA, LFSR_DATA);
        repeat (12) @(posedge lclk);           // let DATA_TRANSFER lock
        run_flit({16{32'hDEADBEEF}}, "DEADBEEF", a);
        for (int k=0;k<N_BYTES;k++) f[k*8 +: 8] = 8'h20 + k[7:0];
        run_flit(f,                  "byte ramp", b);
        run_flit({16{32'hA5A5A5A5}}, "A5 tiles",  c);
        ok = a && b && c;
        $display("  [%s] ACTIVE      : flit round-trip %s", lbl, ok ? "OK" : "FAILED");
    endtask

    // -------------------------------------------------------------------------
    // Full training run. fault injects a single-lane corruption during the
    // matching phase. reached_active tells whether the link came up.
    // -------------------------------------------------------------------------
    task automatic run_training(input string lbl, input int fault_sel, output bit reached_active);
        bit ok;
        reached_active = 0;
        $display("\n---------------------------------------------------------------");
        $display("  TRAINING RUN : %s", lbl);
        $display("---------------------------------------------------------------");

        i_pll_speed_sel = 2'b00;          // start at the slowest speed

        // ---- PHASE 0 : clock test (once) ----
        phase_clock_test(lbl, fault_sel, ok);
        if (!ok) begin $display("  >>> ABORT (%s): clock test failed, link stays down", lbl); return; end

        // ---- PHASE 1 : valid mode 0 ----
        phase_valid_test(lbl, 1'b0, fault_sel, ok);
        if (!ok) begin $display("  >>> ABORT (%s): valid (mode0) failed, link stays down", lbl); return; end

        // ---- PHASE 2 : data per-lane-ID ----
        phase_data_test(lbl, RXMODE_PERLANE, LFSR_PERLANE, 1'b1, 16'd16, fault_sel, ok);
        if (!ok) begin $display("  >>> ABORT (%s): data per-lane failed, link stays down", lbl); return; end

        // ---- PHASE 3 : data LFSR ----
        phase_data_test(lbl, RXMODE_PATTERN, LFSR_PATTERN, 1'b0, 16'd32, FAULT_NONE, ok);
        if (!ok) begin $display("  >>> ABORT (%s): data lfsr failed, link stays down", lbl); return; end

        // ---- PHASE 4 : speed up (period halves; sampling delay tracks i_period) ----
        @(negedge lclk); i_lfsr_state=LFSR_IDLE; i_mapper_en=0; lp_irdy=0; lp_valid=0;
        @(negedge o_pll_clk); i_pll_speed_sel = 2'b01;
        $display("  [%s] SPEED UP    : pll_speed_sel=01 (period -> half)", lbl);
        wait_pll(40);

        // ---- PHASE 5 : valid mode 1 (threshold) ----
        phase_valid_test(lbl, 1'b1, FAULT_NONE, ok);
        if (!ok) begin $display("  >>> ABORT (%s): valid (mode1) failed, link stays down", lbl); return; end

        // ---- PHASE 6 : data per-lane-ID @ new speed ----
        phase_data_test(lbl, RXMODE_PERLANE, LFSR_PERLANE, 1'b1, 16'd16, FAULT_NONE, ok);
        if (!ok) begin $display("  >>> ABORT (%s): data per-lane (fast) failed, link stays down", lbl); return; end

        // ---- PHASE 7 : data LFSR @ new speed ----
        phase_data_test(lbl, RXMODE_PATTERN, LFSR_PATTERN, 1'b0, 16'd32, FAULT_NONE, ok);
        if (!ok) begin $display("  >>> ABORT (%s): data lfsr (fast) failed, link stays down", lbl); return; end

        // ---- PHASE 8 : ACTIVE ----
        phase_active(lbl, ok);
        if (!ok) begin $display("  >>> ABORT (%s): active flit round-trip failed", lbl); return; end

        reached_active = 1;
        $display("  >>> %s : reached ACTIVE state cleanly <<<", lbl);
    endtask

    task automatic expect_active(input string lbl, input int fault_sel, input bit want_active);
        bit got_active;
        run_training(lbl, fault_sel, got_active);
        if (got_active === want_active) begin
            scenarios_pass++;
            $display("  [SCENARIO PASS] %-26s expected reached_active=%0b, got %0b",
                     lbl, want_active, got_active,$time);
        end else begin
            scenarios_fail++;
            $display("  [SCENARIO FAIL] %-26s expected reached_active=%0b, got %0b",
                     lbl, want_active, got_active,$time);
        end
    endtask

    // ---------------------------------------------------------------- stimulus
    initial begin
        i_width_deg     = WIDTH_DEG_ALL;
        i_pll_en        = 1;
        i_pll_speed_sel = 2'b00;
        lclk_g          = 1;
        i_rst_n         = 1;
        i_clk_embedded_en = 0;
        scenarios_pass  = 0;
        scenarios_fail  = 0;

        $display("\n================ MB FULL TRAINING SEQUENCE ================");

        expect_active("clean (all pass)",        FAULT_NONE,  1'b1);
        expect_active("fault: dead clock lane",  FAULT_CLK,   1'b0);
        expect_active("fault: bad valid lane",   FAULT_VALID, 1'b0);
        expect_active("fault: stuck data lane",  FAULT_DATA,  1'b0);

        $display("\n=========================================================");
        $display("  unit_mb_train_seq : %0d scenarios passed, %0d failed",
                 scenarios_pass, scenarios_fail);
        if (scenarios_fail == 0)
            $display("  >>> PASS : clean run reached ACTIVE; every fault aborted training <<<");
        else
            $display("  >>> FAIL : see scenario results above <<<");
        $display("=========================================================\n");
        $stop;
    end

    // watchdog
    initial begin
        #8_000_000;
        $display("[WATCHDOG] timeout!  scenarios_pass=%0d scenarios_fail=%0d", scenarios_pass, scenarios_fail);
        $stop;
    end

endmodule
