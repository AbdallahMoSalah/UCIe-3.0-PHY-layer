`timescale 1ns/1ps
// =============================================================================
// Testbench : unit_mb_die2die_tb
// DUT       : two unit_mb_die instances wired back-to-back (die 0 <-> die 1)
//
//                 ┌────────── die 0 ──────────┐        ┌────────── die 1 ──────────┐
//   lp_data0 ─►   │ TX ─► o_TD/VLD/CK ─────────┼───────►│ i_RD/VLD/CK ─► RX ─► o_out │ ─► o_out_data1
//                 │ RX ◄─ i_RD/VLD/CK ◄────────┼────────│ o_TD/VLD/CK ◄─ TX          │ ◄─ lp_data1
//                 └───────────────────────────┘        └───────────────────────────┘
//
//  Each die owns a full TX + RX (unit_mb_die). die0.TX drives die1.RX and
//  die1.TX drives die0.RX, so both link directions train at once. Both dies are
//  driven with identical control (shared nets) and run the same PLL speed, i.e.
//  they are frequency-locked - exactly the "tx and rx on the same clock" model.
//
//  Runs the FULL link-training sequence (same steps as unit_mb_train_seq_tb) but
//  on the two-die topology, requiring BOTH dies' RX to pass each step:
//    clock test -> valid m0 -> data per-lane -> data lfsr -> speed-up ->
//    valid m1 -> data per-lane -> data lfsr -> ACTIVE (each die recovers the
//    OTHER die's flit). Any step failing on either die aborts before ACTIVE.
//
//  Scenarios: clean (both reach ACTIVE) + fault-injected runs that corrupt the
//  die1->die0 link (dead clock / bad valid / stuck data lane) and must abort.
//
//  Run : make run CONFIG=integration_mb_die2die TOP=unit_mb_die2die_tb
// =============================================================================

module unit_mb_die2die_tb;

    // ---------------------------------------------------------------- params
    localparam int DATA_WIDTH = 32;
    localparam int NUM_LANES  = 16;
    localparam int N_BYTES    = 64;
    localparam int FLITW      = 8*N_BYTES;

    localparam logic [2:0] LFSR_IDLE     = 3'b000;
    localparam logic [2:0] LFSR_CLEAR    = 3'b001;   // CLEAR_LFSR
    localparam logic [2:0] LFSR_PATTERN  = 3'b010;   // PATTERN_LFSR
    localparam logic [2:0] LFSR_PERLANE  = 3'b011;   // PER_LANE_IDE
    localparam logic [2:0] LFSR_DATA     = 3'b100;   // DATA_TRANSFER
    localparam logic [2:0] WIDTH_DEG_ALL = 3'b011;   // x16

    localparam logic [1:0] RXMODE_DATA    = 2'd0;
    localparam logic [1:0] RXMODE_PATTERN = 2'd1;
    localparam logic [1:0] RXMODE_PERLANE = 2'd2;

    localparam int FAULT_NONE  = 0;
    localparam int FAULT_CLK   = 1;   // dead clock lane on the die1 -> die0 link
    localparam int FAULT_VALID = 2;   // bad valid lane on the die1 -> die0 link
    localparam int FAULT_DATA  = 3;   // stuck data lane on the die1 -> die0 link

    // ---------------------------------------------------------- shared control
    logic                  i_rst_n;
    logic                  lp_irdy, lp_valid;
    logic                  i_mapper_en;
    logic [2:0]            i_width_deg_tx;
    logic [2:0]            i_width_deg_rx;
    logic [2:0]            i_lfsr_state;
    logic                  i_reversal_en;
    logic                  i_valid_pattern_en;
    logic                  i_pll_en;
    logic [1:0]            i_pll_speed_sel;
    logic                  lclk_g;
    logic                  i_clk_pattern_en, i_clk_embedded_en;
    logic [1:0]            i_rx_mode;
    logic                  demapper_en;
    assign demapper_en = (i_lfsr_state == LFSR_DATA);
    logic                  i_pcmp_enable, i_pcmp_mode, i_pcmp_pattern_mode, i_pcmp_clear;
    logic [NUM_LANES-1:0]  i_pcmp_lane_mask;
    logic [15:0]           i_pcmp_thr_per_lane, i_pcmp_thr_aggregate, i_pcmp_iter_count;
    logic                  i_vcmp_enable, i_vcmp_mode, i_vcmp_clear;
    logic [15:0]           i_vcmp_thr;
    logic                  i_clk_detector_en;

    // per-die protocol input
    logic [FLITW-1:0]      lp_data0, lp_data1;

    // ---------------------------------------------------------- die 0 outputs
    logic                  pl_trdy0, lclk0, o_pll_clk0;
    logic                  o_lfsr_tx_done0, o_valid_done0, o_clk_done0;
    logic [NUM_LANES-1:0]  d0_TD_P;  logic d0_TVLD_P, d0_TCKP_P, d0_TCKN_P, d0_TTRK_P;
    logic [FLITW-1:0]      o_out_data0;  logic o_pl_valid0;
    logic [DATA_WIDTH-1:0] o_par_data0 [0:NUM_LANES-1];
    logic                  o_data_valid0, o_valid_frame_pulse0;
    logic [DATA_WIDTH-1:0] o_rx_lane0  [0:NUM_LANES-1];
    logic                  o_rx_en0, o_pattern_comp_en0;
    logic                  o_pcmp_done0, o_pcmp_agg_error0;
    logic [NUM_LANES-1:0]  o_pcmp_per_lane_pass0;  logic [15:0] o_pcmp_agg_err_cnt0;
    logic                  o_vcmp_done0, o_vcmp_pass0;
    logic                  o_valid_frame_error0;
    logic                  o_clk_p_pass0, o_clk_n_pass0, o_track_pass0;

    // ---------------------------------------------------------- die 1 outputs
    logic                  pl_trdy1, lclk1, o_pll_clk1;
    logic                  o_lfsr_tx_done1, o_valid_done1, o_clk_done1;
    logic [NUM_LANES-1:0]  d1_TD_P;  logic d1_TVLD_P, d1_TCKP_P, d1_TCKN_P, d1_TTRK_P;
    logic [FLITW-1:0]      o_out_data1;  logic o_pl_valid1;
    logic [DATA_WIDTH-1:0] o_par_data1 [0:NUM_LANES-1];
    logic                  o_data_valid1, o_valid_frame_pulse1;
    logic [DATA_WIDTH-1:0] o_rx_lane1  [0:NUM_LANES-1];
    logic                  o_rx_en1, o_pattern_comp_en1;
    logic                  o_pcmp_done1, o_pcmp_agg_error1;
    logic [NUM_LANES-1:0]  o_pcmp_per_lane_pass1;  logic [15:0] o_pcmp_agg_err_cnt1;
    logic                  o_vcmp_done1, o_vcmp_pass1;
    logic                  o_valid_frame_error1;
    logic                  o_clk_p_pass1, o_clk_n_pass1, o_track_pass1;

    // ============================================================== die 0
    unit_mb_die #(
        .DATA_WIDTH(DATA_WIDTH), .NUM_LANES(NUM_LANES), .N_BYTES(N_BYTES),
        .VALID_PATTERN(32'h0F0F0F0F), .PLL_PERIOD_NS(0.5), .RX_ALIGN_DELAY(2)
    ) die0 (
        .i_rst_n(i_rst_n),
        .lp_data(lp_data0), .lp_irdy(lp_irdy), .lp_valid(lp_valid), .pl_trdy(pl_trdy0),
        .i_mapper_en(i_mapper_en), .i_width_deg_tx(i_width_deg_tx), .i_width_deg_rx(i_width_deg_rx), .i_lfsr_state(i_lfsr_state),
        .i_reversal_en(i_reversal_en), .i_valid_pattern_en(i_valid_pattern_en),
        .i_pll_en(i_pll_en), .i_pll_speed_sel(i_pll_speed_sel), .lclk_g(lclk_g),
        .i_clk_pattern_en(i_clk_pattern_en), .i_clk_embedded_en(i_clk_embedded_en),
        .i_state(i_lfsr_state), .demapper_en(demapper_en),
        .i_pcmp_enable(i_pcmp_enable), .i_pcmp_mode(i_pcmp_mode), .i_pcmp_lane_mask(i_pcmp_lane_mask),
        .i_pcmp_thr_per_lane(i_pcmp_thr_per_lane), .i_pcmp_thr_aggregate(i_pcmp_thr_aggregate),
        .i_pcmp_iter_count(i_pcmp_iter_count), .i_pcmp_pattern_mode(i_pcmp_pattern_mode),
        .i_pcmp_clear(i_pcmp_clear),
        .i_vcmp_enable(i_vcmp_enable), .i_vcmp_mode(i_vcmp_mode), .i_vcmp_thr(i_vcmp_thr),
        .i_vcmp_clear(i_vcmp_clear), .i_clk_detector_en(i_clk_detector_en),
        // RX in <- die1 TX
        .i_RD_P(d1_TD_P), .i_RVLD_P(d1_TVLD_P), .i_RCKP_P(d1_TCKP_P), .i_RCKN_P(d1_TCKN_P), .i_RTRK_P(d1_TTRK_P),
        // TX out -> die1 RX
        .o_TD_P(d0_TD_P), .o_TVLD_P(d0_TVLD_P), .o_TCKP_P(d0_TCKP_P), .o_TCKN_P(d0_TCKN_P), .o_TTRK_P(d0_TTRK_P),
        .lclk(lclk0), .o_pll_clk(o_pll_clk0),
        .o_lfsr_tx_done(o_lfsr_tx_done0), .o_valid_done(o_valid_done0), .o_clk_done(o_clk_done0),
        .o_out_data(o_out_data0), .o_pl_valid(o_pl_valid0),
        .o_pcmp_done(o_pcmp_done0), .o_pcmp_per_lane_pass(o_pcmp_per_lane_pass0),
        .o_pcmp_agg_err_cnt(o_pcmp_agg_err_cnt0), .o_pcmp_agg_error(o_pcmp_agg_error0),
        .o_vcmp_done(o_vcmp_done0), .o_vcmp_pass(o_vcmp_pass0), .o_valid_frame_error(o_valid_frame_error0),
        .o_clk_p_pass(o_clk_p_pass0), .o_clk_n_pass(o_clk_n_pass0), .o_track_pass(o_track_pass0)
    );

    // ============================================================== die 1
    unit_mb_die #(
        .DATA_WIDTH(DATA_WIDTH), .NUM_LANES(NUM_LANES), .N_BYTES(N_BYTES),
        .VALID_PATTERN(32'h0F0F0F0F), .PLL_PERIOD_NS(0.5), .RX_ALIGN_DELAY(2)
    ) die1 (
        .i_rst_n(i_rst_n),
        .lp_data(lp_data1), .lp_irdy(lp_irdy), .lp_valid(lp_valid), .pl_trdy(pl_trdy1),
        .i_mapper_en(i_mapper_en), .i_width_deg_tx(i_width_deg_tx), .i_width_deg_rx(i_width_deg_rx), .i_lfsr_state(i_lfsr_state),
        .i_reversal_en(i_reversal_en), .i_valid_pattern_en(i_valid_pattern_en),
        .i_pll_en(i_pll_en), .i_pll_speed_sel(i_pll_speed_sel), .lclk_g(lclk_g),
        .i_clk_pattern_en(i_clk_pattern_en), .i_clk_embedded_en(i_clk_embedded_en),
        .i_state(i_lfsr_state), .demapper_en(demapper_en),
        .i_pcmp_enable(i_pcmp_enable), .i_pcmp_mode(i_pcmp_mode), .i_pcmp_lane_mask(i_pcmp_lane_mask),
        .i_pcmp_thr_per_lane(i_pcmp_thr_per_lane), .i_pcmp_thr_aggregate(i_pcmp_thr_aggregate),
        .i_pcmp_iter_count(i_pcmp_iter_count), .i_pcmp_pattern_mode(i_pcmp_pattern_mode),
        .i_pcmp_clear(i_pcmp_clear),
        .i_vcmp_enable(i_vcmp_enable), .i_vcmp_mode(i_vcmp_mode), .i_vcmp_thr(i_vcmp_thr),
        .i_vcmp_clear(i_vcmp_clear), .i_clk_detector_en(i_clk_detector_en),
        // RX in <- die0 TX
        .i_RD_P(d0_TD_P), .i_RVLD_P(d0_TVLD_P), .i_RCKP_P(d0_TCKP_P), .i_RCKN_P(d0_TCKN_P), .i_RTRK_P(d0_TTRK_P),
        // TX out -> die0 RX
        .o_TD_P(d1_TD_P), .o_TVLD_P(d1_TVLD_P), .o_TCKP_P(d1_TCKP_P), .o_TCKN_P(d1_TCKN_P), .o_TTRK_P(d1_TTRK_P),
        .lclk(lclk1), .o_pll_clk(o_pll_clk1),
        .o_lfsr_tx_done(o_lfsr_tx_done1), .o_valid_done(o_valid_done1), .o_clk_done(o_clk_done1),
        .o_out_data(o_out_data1), .o_pl_valid(o_pl_valid1),
        .o_pcmp_done(o_pcmp_done1), .o_pcmp_per_lane_pass(o_pcmp_per_lane_pass1),
        .o_pcmp_agg_err_cnt(o_pcmp_agg_err_cnt1), .o_pcmp_agg_error(o_pcmp_agg_error1),
        .o_vcmp_done(o_vcmp_done1), .o_vcmp_pass(o_vcmp_pass1), .o_valid_frame_error(o_valid_frame_error1),
        .o_clk_p_pass(o_clk_p_pass1), .o_clk_n_pass(o_clk_n_pass1), .o_track_pass(o_track_pass1)
    );

    // ---------------------------------------------------------------- helpers
    // die0 is the timing reference (both dies are frequency-locked / identical).
    task automatic wait_pll(input int n); repeat (n) @(posedge o_pll_clk0); endtask
    task automatic wait_mb (input int n); repeat (n) @(posedge lclk0);      endtask

    function automatic bit both_clk_pass();
        return (o_clk_p_pass0 && o_clk_n_pass0 && o_track_pass0 &&
                o_clk_p_pass1 && o_clk_n_pass1 && o_track_pass1);
    endfunction
    function automatic bit both_rx_en();    return (die0.u_rx_top.o_rx_en && die1.u_rx_top.o_rx_en);             endfunction
    function automatic bit both_pcomp_en(); return (die0.u_rx_top.o_pattern_comp_en && die1.u_rx_top.o_pattern_comp_en); endfunction
    function automatic bit both_vcmp_done();return (o_vcmp_done0 && o_vcmp_done1);      endfunction
    function automatic bit both_pcmp_done();return (o_pcmp_done0 && o_pcmp_done1);       endfunction

    int  scenarios_pass, scenarios_fail;

    // -------------------------------------------------------------------------
    // Reset/re-init both dies. PLL free-runs, so i_pll_speed_sel persists;
    // embedded_clk picks whether the forwarded clock is live out of reset.
    // -------------------------------------------------------------------------
    task automatic link_reset(input bit embedded_clk);
        @(negedge o_pll_clk0); i_rst_n = 0;
        lp_data0='0; lp_data1='0; lp_irdy=0; lp_valid=0; i_mapper_en=0;
        i_lfsr_state=LFSR_IDLE; i_reversal_en=0; i_valid_pattern_en=0;
        i_clk_pattern_en=0; i_clk_detector_en=0; i_clk_embedded_en=embedded_clk;
        i_rx_mode=RXMODE_DATA;
        i_pcmp_enable=0; i_pcmp_mode=0; i_pcmp_pattern_mode=0; i_pcmp_clear=0;
        i_pcmp_lane_mask='0; i_pcmp_thr_per_lane='0; i_pcmp_thr_aggregate='0;
        i_pcmp_iter_count=16'd32;
        i_vcmp_enable=0; i_vcmp_mode=0; i_vcmp_clear=0; i_vcmp_thr=16'd0;
        wait_pll(8);
        @(negedge o_pll_clk0); i_rst_n = 1;
        wait_pll(20); wait_mb(4);
    endtask

    task automatic rx_reset();
        wait_mb(5);
    endtask

    task automatic start_stream(input [1:0] rxmode, input [2:0] lfsr_st);
        @(negedge lclk0);
        i_rx_mode  = rxmode;
        if (lfsr_st == LFSR_DATA) begin
            i_mapper_en = 1; lp_irdy = 1; lp_valid = 1;
        end else begin
            i_mapper_en = 0; lp_irdy = 0; lp_valid = 0;
        end
        lp_data0='0; lp_data1='0;
        @(negedge lclk0); i_lfsr_state = lfsr_st;
    endtask

    // Fault helpers: corrupt the die1->die0 link as seen by die0's RX inputs.
    task automatic inject(input int fault);
        case (fault)
            FAULT_CLK  : force die0.u_rx_top.i_RCKP_P = 1'b0;
            FAULT_VALID: force die0.u_rx_top.i_RVLD_P = die0.u_rx_top.i_RCKP_P;
            FAULT_DATA : force die0.u_rx_top.i_RD_P[3] = 1'b0;
            default    : ;
        endcase
    endtask
    task automatic uninject(input int fault);
        case (fault)
            FAULT_CLK  : release die0.u_rx_top.i_RCKP_P;
            FAULT_VALID: release die0.u_rx_top.i_RVLD_P;
            FAULT_DATA : release die0.u_rx_top.i_RD_P[3];
            default    : ;
        endcase
    endtask

    // -------------------------------------------------------------------------
    // PHASE 0 : clock test on both links.
    // -------------------------------------------------------------------------
    task automatic phase_clock_test(input string lbl, input int fault, output bit ok);
        int t;
        link_reset(.embedded_clk(0));
        if (fault == FAULT_CLK) inject(FAULT_CLK);
        @(negedge o_pll_clk0); i_clk_pattern_en=1; i_clk_detector_en=1;
        t = 0;
        while (!(both_clk_pass() && o_clk_done0 && o_clk_done1) && t < 4000) begin @(posedge o_pll_clk0); t++; end
        ok = both_clk_pass() && o_clk_done0 && o_clk_done1;
        if (ok) begin
            repeat (20) @(posedge o_pll_clk0);
            if (!(both_clk_pass() && o_clk_done0 && o_clk_done1)) begin
                ok = 0;
            end
        end
        $display("  [%s] CLOCK TEST  : d0(p/n/t)=%0b%0b%0b d1(p/n/t)=%0b%0b%0b (%0d)%s",
                 lbl, o_clk_p_pass0,o_clk_n_pass0,o_track_pass0,
                 o_clk_p_pass1,o_clk_n_pass1,o_track_pass1, t, ok ? "" : "  <-- FAIL");
        if (fault == FAULT_CLK) uninject(FAULT_CLK);
        @(negedge o_pll_clk0); i_clk_pattern_en=0; i_clk_detector_en=0;
    endtask

    // -------------------------------------------------------------------------
    // PHASE 1/5 : valid comparator test (both dies). mode1 selects threshold.
    // -------------------------------------------------------------------------
    task automatic phase_valid_test(input string lbl, input bit mode1, input int fault, output bit ok);
        int t;
        link_reset(.embedded_clk(1));
        if (fault == FAULT_VALID) inject(FAULT_VALID);
        start_stream(RXMODE_DATA, LFSR_DATA);
        t = 0; while (!both_rx_en() && t < 400) begin @(posedge lclk0); t++; end

        @(negedge lclk0); i_vcmp_mode=mode1; i_vcmp_thr=16'd0; i_vcmp_clear=1;
        @(negedge lclk0); i_vcmp_clear=0;
        @(negedge lclk0); i_vcmp_enable=1; i_valid_pattern_en=1;

        t = 0; while (!(both_vcmp_done() && o_valid_done0 && o_valid_done1) && t < 2000) begin @(posedge lclk0); t++; end
        ok = (both_vcmp_done() && o_vcmp_pass0 && o_vcmp_pass1 && o_valid_done0 && o_valid_done1);
        if (ok) begin
            repeat (20) @(posedge lclk0);
            if (!(both_vcmp_done() && o_vcmp_pass0 && o_vcmp_pass1 && o_valid_done0 && o_valid_done1)) begin
                ok = 0;
            end
        end
        $display("  [%s] VALID  m%0d  : d0(done/pass)=%0b/%0b d1(done/pass)=%0b/%0b (%0d)%s",
                 lbl, mode1, o_vcmp_done0,o_vcmp_pass0, o_vcmp_done1,o_vcmp_pass1, t, ok ? "" : "  <-- FAIL");

        @(negedge lclk0); i_vcmp_enable=0; i_valid_pattern_en=0;
        if (fault == FAULT_VALID) uninject(FAULT_VALID);
    endtask

    // -------------------------------------------------------------------------
    // PHASE 2/3/6/7 : data-lane training-pattern comparator test (both dies).
    // -------------------------------------------------------------------------
    task automatic phase_data_test(input string lbl, input [1:0] rxmode, input [2:0] lfsr_st,
                                    input bit pat_mode, input [15:0] iter, input int fault, output bit ok);
        int t;
        link_reset(.embedded_clk(1));
        if (fault == FAULT_DATA) inject(FAULT_DATA);

        @(negedge lclk0);
        i_pcmp_mode=0; i_pcmp_pattern_mode=pat_mode; i_pcmp_lane_mask='0;
        i_pcmp_thr_per_lane=16'd0; i_pcmp_thr_aggregate=16'd0; i_pcmp_iter_count=iter;
        i_pcmp_enable=0; i_pcmp_clear=1;
        @(negedge lclk0); i_pcmp_clear=0;

        start_stream(rxmode, lfsr_st);

        t = 0; while (!both_rx_en() && t < 400) begin @(posedge lclk0); t++; end
        if (both_rx_en()) begin
            t = 0; while (!both_pcomp_en() && t < 400) begin @(posedge lclk0); t++; end
            wait_mb(3);
            @(negedge lclk0); i_pcmp_enable=1;
            t = 0; while (!(both_pcmp_done() && o_lfsr_tx_done0 && o_lfsr_tx_done1) && t < 800) begin @(posedge lclk0); t++; end
        end
        ok = (both_pcmp_done() && o_lfsr_tx_done0 && o_lfsr_tx_done1 &&
              (o_pcmp_per_lane_pass0 === 16'hFFFF) && (o_pcmp_per_lane_pass1 === 16'hFFFF));
        if (ok) begin
            repeat (20) @(posedge lclk0);
            if (!(both_pcmp_done() && o_lfsr_tx_done0 && o_lfsr_tx_done1 &&
                  (o_pcmp_per_lane_pass0 === 16'hFFFF) && (o_pcmp_per_lane_pass1 === 16'hFFFF))) begin
                ok = 0;
            end
        end
        $display("  [%s] %-12s: d0 per_lane=0x%04h d1 per_lane=0x%04h%s",
                 lbl, (pat_mode ? "DATA perlane" : "DATA lfsr"),
                 o_pcmp_per_lane_pass0, o_pcmp_per_lane_pass1, ok ? "" : "  <-- FAIL");

        @(negedge lclk0); i_pcmp_enable=0;
        if (fault == FAULT_DATA) uninject(FAULT_DATA);
    endtask

    // -------------------------------------------------------------------------
    // PHASE 8 : ACTIVE. Each die transmits its own flit; each die's RX must
    // recover the OTHER die's flit (die0 RX <- die1 TX, die1 RX <- die0 TX).
    // -------------------------------------------------------------------------
    task automatic run_flit_pair(input logic [FLITW-1:0] f0, input logic [FLITW-1:0] f1,
                                 input string nm, output bit ok);
        int t; bit got0, got1;
        @(negedge lclk0); lp_data0 = f0; lp_data1 = f1;
        got0=0; got1=0; t=0;
        while (!(got0 && got1) && t < 400) begin
            @(posedge lclk0);
            if (o_pl_valid0 && (o_out_data0 === f1)) got0 = 1;   // die0 received die1's flit
            if (o_pl_valid1 && (o_out_data1 === f0)) got1 = 1;   // die1 received die0's flit
            t++;
        end
        ok = got0 && got1;
        $display("      flit %-12s : die0<=die1 %s, die1<=die0 %s (settle %0d)",
                 nm, got0?"MATCH":"MISS", got1?"MATCH":"MISS", t);
    endtask

    task automatic phase_active(input string lbl, output bit ok);
        bit a, b, c; logic [FLITW-1:0] f0, f1;
        link_reset(.embedded_clk(1));
        start_stream(RXMODE_DATA, LFSR_DATA);
        repeat (12) @(posedge lclk0);
        run_flit_pair({16{32'hDEADBEEF}}, {16{32'hCAFEBABE}}, "DEAD/CAFE", a);
        for (int k=0;k<N_BYTES;k++) begin f0[k*8+:8]=8'h20+k[7:0]; f1[k*8+:8]=8'h80-k[7:0]; end
        run_flit_pair(f0, f1,                "ramps",     b);
        run_flit_pair({16{32'hA5A5A5A5}}, {16{32'h5A5A5A5A}}, "A5/5A",   c);
        ok = a && b && c;
        $display("  [%s] ACTIVE      : bidirectional flit round-trip %s", lbl, ok ? "OK" : "FAILED");
    endtask

    // -------------------------------------------------------------------------
    // Full two-die training run.
    // -------------------------------------------------------------------------
    task automatic run_training(input string lbl, input int fault_sel, output bit reached_active);
        bit ok;
        reached_active = 0;
        $display("\n---------------------------------------------------------------");
        $display("  TWO-DIE TRAINING RUN : %s", lbl);
        $display("---------------------------------------------------------------");
        i_pll_speed_sel = 2'b00;

        phase_clock_test(lbl, fault_sel, ok);
        if (!ok) begin $display("  >>> ABORT (%s): clock test failed, link stays down", lbl); return; end

        phase_valid_test(lbl, 1'b0, fault_sel, ok);
        if (!ok) begin $display("  >>> ABORT (%s): valid (mode0) failed, link stays down", lbl); return; end

        phase_data_test(lbl, RXMODE_PERLANE, LFSR_PERLANE, 1'b1, 16'd16, fault_sel, ok);
        if (!ok) begin $display("  >>> ABORT (%s): data per-lane failed, link stays down", lbl); return; end

        phase_data_test(lbl, RXMODE_PATTERN, LFSR_PATTERN, 1'b0, 16'd32, FAULT_NONE, ok);
        if (!ok) begin $display("  >>> ABORT (%s): data lfsr failed, link stays down", lbl); return; end

        @(negedge lclk0); i_lfsr_state=LFSR_IDLE; i_mapper_en=0; lp_irdy=0; lp_valid=0;
        @(negedge o_pll_clk0); i_pll_speed_sel = 2'b01;
        $display("  [%s] SPEED UP    : pll_speed_sel=01 (both dies, period -> half)", lbl);
        wait_pll(40);

        phase_valid_test(lbl, 1'b1, FAULT_NONE, ok);
        if (!ok) begin $display("  >>> ABORT (%s): valid (mode1) failed, link stays down", lbl); return; end

        phase_data_test(lbl, RXMODE_PERLANE, LFSR_PERLANE, 1'b1, 16'd16, FAULT_NONE, ok);
        if (!ok) begin $display("  >>> ABORT (%s): data per-lane (fast) failed, link stays down", lbl); return; end

        phase_data_test(lbl, RXMODE_PATTERN, LFSR_PATTERN, 1'b0, 16'd32, FAULT_NONE, ok);
        if (!ok) begin $display("  >>> ABORT (%s): data lfsr (fast) failed, link stays down", lbl); return; end

        phase_active(lbl, ok);
        if (!ok) begin $display("  >>> ABORT (%s): active flit round-trip failed", lbl); return; end

        reached_active = 1;
        $display("  >>> %s : BOTH dies reached ACTIVE cleanly <<<", lbl);
    endtask

    // -------------------------------------------------------------------------
    // Scenario: fulltraining_happy_scenario
    // -------------------------------------------------------------------------
    task automatic run_fulltraining_happy_scenario(output bit ok);
        int t;
        bit step_ok;
        logic [FLITW-1:0] f0, f1;
        ok = 1;
        $display("\n===============================================================");
        $display("  RUNNING SCENARIO: fulltraining_happy_scenario");
        $display("===============================================================");

        // 1. Reset
        $display("Step 1: System Reset");
        link_reset(.embedded_clk(0));
        i_pll_speed_sel = 2'b00; // lowest speed
        wait_pll(10);

        // 2. Clock Pattern Test (lowest speed)
        $display("Step 2: Clock Pattern Test at lowest speed (full-duplex)");
        @(negedge o_pll_clk0);
        i_clk_pattern_en = 1;
        i_clk_detector_en = 1;
        t = 0;
        while (!(both_clk_pass() && o_clk_done0 && o_clk_done1) && t < 4000) begin
            @(posedge o_pll_clk0);
            t++;
        end
        step_ok = both_clk_pass() && o_clk_done0 && o_clk_done1;
        if (!step_ok) begin
            $display("  [FAIL] Clock pattern test failed or timed out. d0(p/n/t)=%0b%0b%0b d1(p/n/t)=%0b%0b%0b, t=%0d",
                     o_clk_p_pass0, o_clk_n_pass0, o_track_pass0,
                     o_clk_p_pass1, o_clk_n_pass1, o_track_pass1, t);
            ok = 0; return;
        end
        $display("  [PASS] Clock pattern test complete. t=%0d", t);

        // Verify clock stays locked and done stays high (wait 20 cycles)
        repeat (20) @(posedge o_pll_clk0);
        if (!(both_clk_pass() && o_clk_done0 && o_clk_done1)) begin
            $display("  [FAIL] Clock lock dropped after completion.");
            ok = 0; return;
        end

        // Disable clock pattern test
        @(negedge o_pll_clk0);
        i_clk_pattern_en = 0;
        i_clk_detector_en = 0;
        wait_pll(5);

        // 3. Valid Pattern Test (lowest speed, 16 consecutive iter)
        $display("Step 3: Valid Pattern Test at lowest speed (consecutive iter, no reset)");
        rx_reset();
        @(negedge lclk0);
        i_clk_embedded_en = 1; // embedded clock free-running
        i_rx_mode = RXMODE_DATA;
        i_vcmp_mode = 1'b0; // 16 consecutive iter
        i_vcmp_thr = 16'd0;
        i_vcmp_clear = 1;
        @(negedge lclk0);
        i_vcmp_clear = 0;
        @(negedge lclk0);
        i_vcmp_enable = 1;
        i_valid_pattern_en = 1;

        t = 0;
        while (!(both_vcmp_done() && o_valid_done0 && o_valid_done1) && t < 2000) begin
            @(posedge lclk0);
            t++;
        end
        step_ok = both_vcmp_done() && o_vcmp_pass0 && o_vcmp_pass1 && o_valid_done0 && o_valid_done1;
        if (!step_ok) begin
            $display("  [FAIL] Valid pattern test failed or timed out. t=%0d", t);
            ok = 0; return;
        end
        $display("  [PASS] Valid pattern test complete. t=%0d", t);

        // Verify done/pass stays high even if en is still high (wait 20 cycles)
        repeat (20) @(posedge lclk0);
        if (!(o_valid_done0 && o_valid_done1 && o_vcmp_pass0 && o_vcmp_pass1 && both_vcmp_done())) begin
            $display("  [FAIL] Valid done or pass dropped while enable remains high.");
            ok = 0; return;
        end

        // Lower enables
        @(negedge lclk0);
        i_valid_pattern_en = 0;
        i_vcmp_enable = 0;
        wait_mb(5);

        // 4. Data Pattern Perlane ID (lowest speed, consecutive iter)
        $display("Step 4: Data Pattern Perlane ID at lowest speed (consecutive iter, no reset)");
        rx_reset();
        @(negedge lclk0);
        i_lfsr_state = LFSR_CLEAR;
        wait_mb(2);
        i_lfsr_state = LFSR_IDLE;
        wait_mb(2);
        @(negedge lclk0);
        i_rx_mode = RXMODE_PERLANE;
        i_lfsr_state = LFSR_PERLANE;
        i_pcmp_mode = 1'b0; // per-lane comparison
        i_pcmp_pattern_mode = 1'b1; // perlane ID pattern
        i_pcmp_iter_count = 16'd16; // 16 consecutive iterations
        i_pcmp_lane_mask = '0;
        i_pcmp_thr_per_lane = 16'd0;
        i_pcmp_thr_aggregate = 16'd0;
        i_pcmp_clear = 1;
        @(negedge lclk0);
        i_pcmp_clear = 0;
        
        // Start streaming
        i_pcmp_enable = 1;
        t = 0;
        while (!both_rx_en() && t < 400) begin @(posedge lclk0); t++; end
        if (both_rx_en()) begin
            t = 0;
            while (!both_pcomp_en() && t < 400) begin @(posedge lclk0); t++; end
            wait_mb(3);
            @(negedge lclk0);
            
            t = 0;
            while (!(both_pcmp_done() && o_lfsr_tx_done0 && o_lfsr_tx_done1) && t < 800) begin @(posedge lclk0); t++; end
        end
        step_ok = both_rx_en() && both_pcmp_done() && 
                  (o_pcmp_per_lane_pass0 === 16'hFFFF) && (o_pcmp_per_lane_pass1 === 16'hFFFF) &&
                  o_lfsr_tx_done0 && o_lfsr_tx_done1;
        if (!step_ok) begin
            $display("  [FAIL] Data perlane test failed. rx_en=%b, pcmp_done=%b, pass0=%h, pass1=%h",
                     both_rx_en(), both_pcmp_done(), o_pcmp_per_lane_pass0, o_pcmp_per_lane_pass1);
            ok = 0; return;
        end
        $display("  [PASS] Data perlane test complete.");

        // Verify done stays high even if en is still high (wait 20 cycles)
        repeat (20) @(posedge lclk0);
        if (!(o_lfsr_tx_done0 && o_lfsr_tx_done1 && both_pcmp_done() && o_pcmp_per_lane_pass0 === 16'hFFFF && o_pcmp_per_lane_pass1 === 16'hFFFF)) begin
            $display("  [FAIL] Data LFSR TX done dropped while enable remains high.");
            ok = 0; return;
        end

        // Lower enables
        @(negedge lclk0);
        i_lfsr_state = LFSR_IDLE;
        i_pcmp_enable = 0;
        wait_mb(5);

        // 5. Data Pattern LFSR (lowest speed, threshold mode)
        $display("Step 5: Data Pattern LFSR at lowest speed (threshold mode, no reset)");
        rx_reset();
        @(negedge lclk0);
        i_lfsr_state = LFSR_CLEAR;
        wait_mb(2);
        i_lfsr_state = LFSR_IDLE;
        wait_mb(2);
        @(negedge lclk0);
        i_rx_mode = RXMODE_PATTERN;
        i_lfsr_state = LFSR_PATTERN;
        i_pcmp_mode = 1'b0; // per-lane
        i_pcmp_pattern_mode = 1'b0; // LFSR pattern
        i_pcmp_iter_count = 16'd32; // threshold iteration count
        i_pcmp_thr_per_lane = 16'd5; // threshold errors
        i_pcmp_clear = 1;
        @(negedge lclk0);
        i_pcmp_clear = 0;
        i_pcmp_enable = 1;


        t = 0;
        while (!both_rx_en() && t < 400) begin @(posedge lclk0); t++; end
        if (both_rx_en()) begin
            t = 0;
            while (!both_pcomp_en() && t < 400) begin @(posedge lclk0); t++; end
            wait_mb(3);
            @(negedge lclk0);
            
            t = 0;
            while (!(both_pcmp_done() && o_lfsr_tx_done0 && o_lfsr_tx_done1) && t < 800) begin @(posedge lclk0); t++; end
        end
        step_ok = both_rx_en() && both_pcmp_done() &&
                  (o_pcmp_per_lane_pass0 === 16'hFFFF) && (o_pcmp_per_lane_pass1 === 16'hFFFF) &&
                  o_lfsr_tx_done0 && o_lfsr_tx_done1;
        if (!step_ok) begin
            $display("  [FAIL] Data LFSR test failed.");
            ok = 0; return;
        end
        $display("  [PASS] Data LFSR test complete.");

        // Verify done stays high even if en is still high (wait 20 cycles)
        repeat (20) @(posedge lclk0);
        if (!(o_lfsr_tx_done0 && o_lfsr_tx_done1 && both_pcmp_done() && o_pcmp_per_lane_pass0 === 16'hFFFF && o_pcmp_per_lane_pass1 === 16'hFFFF)) begin
            $display("  [FAIL] Data LFSR TX done dropped while enable remains high.");
            ok = 0; return;
        end

        // Lower enables
        @(negedge lclk0);
        i_lfsr_state = LFSR_IDLE;
        i_pcmp_enable = 0;
        wait_mb(5);

        // 6. Speed change (no reset)
        $display("Step 6: PLL Speed Change to 2'b01 (no reset)");
        @(negedge o_pll_clk0);
        i_pll_speed_sel = 2'b01; // higher speed
        wait_pll(40);
        wait_mb(5);

        // 7. Valid Pattern Test (high speed, threshold mode)
        $display("Step 7: Valid Pattern Test at higher speed (threshold mode, no reset)");
        rx_reset();
        @(negedge lclk0);
        i_rx_mode = RXMODE_DATA;
        i_vcmp_mode = 1'b1; // threshold mode
        i_vcmp_thr = 16'd5;
        i_vcmp_clear = 1;
        @(negedge lclk0);
        i_vcmp_clear = 0;
        @(negedge lclk0);
        i_vcmp_enable = 1;
        i_valid_pattern_en = 1;

        t = 0;
        while (!(both_vcmp_done() && o_valid_done0 && o_valid_done1) && t < 2000) begin
            @(posedge lclk0);
            t++;
        end
        step_ok = both_vcmp_done() && o_vcmp_pass0 && o_vcmp_pass1 && o_valid_done0 && o_valid_done1;
        if (!step_ok) begin
            $display("  [FAIL] Valid pattern test at high speed failed.");
            ok = 0; return;
        end
        $display("  [PASS] Valid pattern test at high speed complete.");

        // Verify done stays high even if en is still high (wait 20 cycles)
        repeat (20) @(posedge lclk0);
        if (!(o_valid_done0 && o_valid_done1 && o_vcmp_pass0 && o_vcmp_pass1 && both_vcmp_done())) begin
            $display("  [FAIL] Valid done dropped while enable remains high.");
            ok = 0; return;
        end

        // Lower enables
        @(negedge lclk0);
        i_valid_pattern_en = 0;
        i_vcmp_enable = 0;
        wait_mb(5);

        // 8. Data Pattern Perlane ID (high speed, consecutive iter)
        $display("Step 8: Data Pattern Perlane ID at higher speed (consecutive iter, no reset)");
        rx_reset();
        @(negedge lclk0);
        i_lfsr_state = LFSR_CLEAR;
        wait_mb(2);
        i_lfsr_state = LFSR_IDLE;
        wait_mb(2);
        @(negedge lclk0);
        i_rx_mode = RXMODE_PERLANE;
        i_lfsr_state = LFSR_PERLANE;
        i_pcmp_mode = 1'b0;
        i_pcmp_pattern_mode = 1'b1;
        i_pcmp_iter_count = 16'd16;
        i_pcmp_clear = 1;
        @(negedge lclk0);
        i_pcmp_clear = 0;
        i_pcmp_enable = 1;


        t = 0;
        while (!both_rx_en() && t < 400) begin @(posedge lclk0); t++; end
        if (both_rx_en()) begin
            t = 0;
            while (!both_pcomp_en() && t < 400) begin @(posedge lclk0); t++; end
            wait_mb(3);
            @(negedge lclk0);
            
            t = 0;
            while (!(both_pcmp_done() && o_lfsr_tx_done0 && o_lfsr_tx_done1) && t < 800) begin @(posedge lclk0); t++; end
        end
        step_ok = both_rx_en() && both_pcmp_done() &&
                  (o_pcmp_per_lane_pass0 === 16'hFFFF) && (o_pcmp_per_lane_pass1 === 16'hFFFF) &&
                  o_lfsr_tx_done0 && o_lfsr_tx_done1;
        if (!step_ok) begin
            $display("  [FAIL] Data perlane test at high speed failed.");
            ok = 0; return;
        end
        $display("  [PASS] Data perlane test at high speed complete.");

        // Verify done stays high even if en is still high (wait 20 cycles)
        repeat (20) @(posedge lclk0);
        if (!(o_lfsr_tx_done0 && o_lfsr_tx_done1 && both_pcmp_done() && o_pcmp_per_lane_pass0 === 16'hFFFF && o_pcmp_per_lane_pass1 === 16'hFFFF)) begin
            $display("  [FAIL] Data LFSR TX done dropped while enable remains high.");
            ok = 0; return;
        end

        // Lower enables
        @(negedge lclk0);
        i_lfsr_state = LFSR_IDLE;
        i_pcmp_enable = 0;
        wait_mb(5);

        // 9. Data Pattern LFSR (high speed, threshold mode)
        $display("Step 9: Data Pattern LFSR at higher speed (threshold mode, no reset)");
        rx_reset();
        @(negedge lclk0);
        i_lfsr_state = LFSR_CLEAR;
        wait_mb(2);
        i_lfsr_state = LFSR_IDLE;
        wait_mb(2);
        @(negedge lclk0);
        i_rx_mode = RXMODE_PATTERN;
        i_lfsr_state = LFSR_PATTERN;
        i_pcmp_mode = 1'b0;
        i_pcmp_pattern_mode = 1'b0;
        i_pcmp_iter_count = 16'd32;
        i_pcmp_thr_per_lane = 16'd5;
        i_pcmp_clear = 1;
        @(negedge lclk0);
        i_pcmp_clear = 0;
        i_pcmp_enable = 1;


        t = 0;
        while (!both_rx_en() && t < 400) begin @(posedge lclk0); t++; end
        if (both_rx_en()) begin
            t = 0;
            while (!both_pcomp_en() && t < 400) begin @(posedge lclk0); t++; end
            wait_mb(3);
            @(negedge lclk0);
            
            t = 0;
            while (!(both_pcmp_done() && o_lfsr_tx_done0 && o_lfsr_tx_done1) && t < 800) begin @(posedge lclk0); t++; end
        end
        step_ok = both_rx_en() && both_pcmp_done() &&
                  (o_pcmp_per_lane_pass0 === 16'hFFFF) && (o_pcmp_per_lane_pass1 === 16'hFFFF) &&
                  o_lfsr_tx_done0 && o_lfsr_tx_done1;
        if (!step_ok) begin
            $display("  [FAIL] Data LFSR test at high speed failed.");
            ok = 0; return;
        end
        $display("  [PASS] Data LFSR test at high speed complete.");

        // Verify done stays high even if en is still high (wait 20 cycles)
        repeat (20) @(posedge lclk0);
        if (!(o_lfsr_tx_done0 && o_lfsr_tx_done1 && both_pcmp_done() && o_pcmp_per_lane_pass0 === 16'hFFFF && o_pcmp_per_lane_pass1 === 16'hFFFF)) begin
            $display("  [FAIL] Data LFSR TX done dropped while enable remains high.");
            ok = 0; return;
        end

        // Lower enables
        @(negedge lclk0);
        i_lfsr_state = LFSR_IDLE;
        i_pcmp_enable = 0;
        wait_mb(5);

        // 10. Active Mode (bidirectional data exchange with different data at different times)
        $display("Step 10: Entering ACTIVE Mode (no reset)");
        rx_reset();
        @(negedge lclk0);
        i_lfsr_state = LFSR_CLEAR;
        wait_mb(2);
        i_lfsr_state = LFSR_IDLE;
        wait_mb(2);
        @(negedge lclk0);
        i_rx_mode = RXMODE_DATA;
        i_lfsr_state = LFSR_DATA;
        i_mapper_en = 1;
        lp_irdy = 1;
        lp_valid = 1;
        wait_mb(15);

        // Send different random data back and forth at different times/delays
        $display("  [ACTIVE] Exchanging 5 different data pairs...");
        
        // Pair 1
        run_flit_pair({16{32'hAAAA5555}}, {16{32'h5555AAAA}}, "AA55/55AA", step_ok);
        if (!step_ok) begin ok = 0; return; end
        wait_mb(10);

        // Pair 2 (delay one side)
        lp_data0 = {16{32'h00FF00FF}};
        wait_mb(5);
        lp_data1 = {16{32'hFF00FF00}};
        t = 0;
        while (!(o_pl_valid0 && o_out_data0 === {16{32'hFF00FF00}} && o_pl_valid1 && o_out_data1 === {16{32'h00FF00FF}}) && t < 400) begin
            @(posedge lclk0); t++;
        end
        step_ok = (o_out_data0 === {16{32'hFF00FF00}} && o_out_data1 === {16{32'h00FF00FF}});
        $display("      flit pair 2 (staggered)       : %s (settle %0d)", step_ok?"MATCH":"MISS", t);
        if (!step_ok) begin ok = 0; return; end
        wait_mb(10);

        // Pair 3
        run_flit_pair({16{32'h0F0F0F0F}}, {16{32'hF0F0F0F0}}, "0F0F/F0F0", step_ok);
        if (!step_ok) begin ok = 0; return; end
        wait_mb(10);

        // Pair 4 (different random data)
        run_flit_pair({16{32'h12345678}}, {16{32'h87654321}}, "1234/8765", step_ok);
        if (!step_ok) begin ok = 0; return; end
        wait_mb(10);

        // Pair 5
        run_flit_pair({16{32'hDEADBEEF}}, {16{32'hCAFEBABE}}, "DEAD/CAFE", step_ok);
        if (!step_ok) begin ok = 0; return; end
        wait_mb(10);

        $display("  [PASS] ACTIVE mode bidirectional exchange verified with zero errors.");
    endtask

    task automatic expect_active(input string lbl, input int fault_sel, input bit want_active);
        bit got_active;
        run_training(lbl, fault_sel, got_active);
        if (got_active === want_active) begin
            scenarios_pass++;
            $display("  [SCENARIO PASS] %-26s expected reached_active=%0b, got %0b", lbl, want_active, got_active);
        end else begin
            scenarios_fail++;
            $display("  [SCENARIO FAIL] %-26s expected reached_active=%0b, got %0b", lbl, want_active, got_active);
        end
    endtask

    // ---------------------------------------------------------------- stimulus
    initial begin
        i_width_deg_tx = WIDTH_DEG_ALL;
        i_width_deg_rx = WIDTH_DEG_ALL;
        i_pll_en = 1; i_pll_speed_sel = 2'b00; lclk_g = 1;
        i_rst_n = 1; i_clk_embedded_en = 0;
        scenarios_pass = 0; scenarios_fail = 0;

        $display("\n============ MB TWO-DIE (die0 <-> die1) TRAINING SEQUENCE ============");

        // Run full training happy scenario
        begin
            bit happy_ok;
            run_fulltraining_happy_scenario(happy_ok);
            if (happy_ok) begin
                scenarios_pass++;
                $display("  [SCENARIO PASS] fulltraining_happy_scenario passed successfully.");
            end else begin
                scenarios_fail++;
                $display("  [SCENARIO FAIL] fulltraining_happy_scenario FAILED!");
            end
        end

        expect_active("clean (all pass)",         FAULT_NONE,  1'b1);
        expect_active("fault: dead clock d1->d0", FAULT_CLK,   1'b0);
        expect_active("fault: bad valid d1->d0",  FAULT_VALID, 1'b0);
        expect_active("fault: stuck data d1->d0", FAULT_DATA,  1'b0);

        $display("\n=========================================================");
        $display("  unit_mb_die2die : %0d scenarios passed, %0d failed", scenarios_pass, scenarios_fail);
        if (scenarios_fail == 0)
            $display("  >>> PASS : clean run brought BOTH dies to ACTIVE; every fault aborted training <<<");
        else
            $display("  >>> FAIL : see scenario results above <<<");
        $display("=========================================================\n");
        $stop;
    end

    initial begin
        #10_000_000;
        $display("[WATCHDOG] timeout!  scenarios_pass=%0d scenarios_fail=%0d", scenarios_pass, scenarios_fail);
        $stop;
    end

endmodule
