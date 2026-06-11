`timescale 1ns/1ps
// =============================================================================
// Testbench : unit_mb_loopback_tb
// DUT       : unit_mb_loopback_wrapper  (unit_tx_top  ->  unit_mb_rx_top)
//
//  Goal
//  ----
//  Full Main-Band TX -> RX loopback. Drive a flit into unit_tx_top and run the
//  whole datapath
//      mapper -> lfsr_tx -> serializer ──(TD_P/TVLD_P/TCK*)──>
//      deserializer -> lfsr_rx -> demapper
//  while simultaneously exercising the RX-side comparators / detector:
//      * recovered flit          : o_out_data must equal the original flit
//      * valid comparator (NEW)  : o_vcmp_pass must assert (valid lane = 0x0F0F0F0F)
//      * pattern comparator      : informational (lfsr_rx is in DATA_TRANSFER, not
//                                  a training-pattern mode, so it is expected to
//                                  flag errors here)
//      * clock pattern detector  : informational
//
//  Run : make run CONFIG=integration_mb_rx_loopback TOP=unit_mb_loopback_tb
// =============================================================================

module unit_mb_loopback_tb;

    // ---------------------------------------------------------------- params
    localparam int DATA_WIDTH = 32;
    localparam int NUM_LANES  = 16;
    localparam int N_BYTES    = 64;
    localparam int FLITW      = 8*N_BYTES;          // 512

    localparam logic [2:0] LFSR_IDLE     = 3'b000;
    localparam logic [2:0] LFSR_DATA     = 3'b100;
    localparam logic [2:0] WIDTH_DEG_ALL = 3'b011;  // x16

    localparam int SETTLE_TIMEOUT = 300;            // lclk cycles to settle a case
    localparam int HOLD_CHK       = 8;              // pl_valid frames to confirm stable

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

    // RX control
    logic [1:0]            i_rx_mode;
    logic                  i_pcmp_enable, i_pcmp_mode, i_pcmp_pattern_mode, i_pcmp_clear;
    logic [NUM_LANES-1:0]  i_pcmp_lane_mask;
    logic [15:0]           i_pcmp_thr_per_lane, i_pcmp_thr_aggregate, i_pcmp_iter_count;
    logic                  i_vcmp_enable, i_vcmp_mode, i_vcmp_clear;
    logic [15:0]           i_vcmp_thr;
    logic                  i_clk_detector_en;

    // TX status / clocks
    logic                  lclk, o_pll_clk, o_rx_pll_clk;
    logic                  o_lfsr_tx_done, o_valid_done, o_clk_done;
    logic [NUM_LANES-1:0]  TD_P;
    logic                  TVLD_P, TCKP_P, TCKN_P, TTRK_P;

    // RX observability + results
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
    logic                  o_valid_frame_error;
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
        .o_valid_frame_error  (o_valid_frame_error),
        .o_clk_p_pass         (o_clk_p_pass),
        .o_clk_n_pass         (o_clk_n_pass),
        .o_track_pass         (o_track_pass)
    );

    // ---------------------------------------------------------------- counters
    int pass_count, fail_count, gap_count;
    bit streaming;
    bit clk_ok;                 // latched clock-lane test result (detector clears on disable)

    // gap monitor: while streaming and armed, o_data_valid must never drop
    always @(posedge lclk)
        if (streaming && o_rx_en && !o_data_valid) gap_count++;

    // ---------------------------------------------------------------- helpers
    task automatic wait_pll(input int n); repeat (n) @(posedge o_pll_clk); endtask
    task automatic wait_mb (input int n); repeat (n) @(posedge lclk);      endtask

    // Hold a flit, wait for the recovered output to settle, then confirm stable.
    task automatic run_case(input logic [FLITW-1:0] flit, input string name);
        logic [FLITW-1:0] exp;
        int  t, good, bad, seen;
        bit  got;
        exp = flit;                           // faithful round trip: out == in

        @(negedge lclk);
        lp_data = flit;

        got = 1'b0; t = 0;
        while (!got && t < SETTLE_TIMEOUT) begin
            @(posedge lclk);
            if (o_pl_valid && (o_out_data === exp)) got = 1'b1;
            t++;
        end
        if (!got) begin
            fail_count++;
            $display("  [FAIL] %-22s : never settled (%0d clk)", name, t);
            $display("         after-demap = 0x%h", o_out_data);
            $display("         before-map  = 0x%h", flit);
            return;
        end

        good = 0; bad = 0; seen = 0;
        while (seen < HOLD_CHK) begin
            @(posedge lclk);
            if (o_pl_valid) begin
                seen++;
                if (o_out_data === exp) good++;
                else begin
                    bad++;
                    if (bad <= 2)
                        $display("  [FAIL] %-22s hold: out=0x%h exp=0x%h", name, o_out_data, exp);
                end
            end
        end
        if (bad == 0) begin
            pass_count++;
            $display("  [PASS] %-22s : after-demap == before-map, stable %0d frames (settle %0d clk)",
                     name, good, t);
        end else begin
            fail_count++;
            $display("  [FAIL] %-22s : %0d/%0d hold frames mismatched", name, bad, seen);
        end
    endtask

    // ---------------------------------------------------------------- stimulus
    logic [FLITW-1:0] flit;
    integer b;
    int     vcmp_wait;

    initial begin
        // init / reset
        i_rst_n=0; lp_data='0; lp_irdy=0; lp_valid=0; i_mapper_en=0;
        i_width_deg=WIDTH_DEG_ALL; i_lfsr_state=LFSR_IDLE; i_reversal_en=0;
        i_valid_pattern_en=0; i_pll_en=1; i_pll_speed_sel=2'b00;
        lclk_g=1; i_clk_pattern_en=0; i_clk_embedded_en=0;   // clock-pattern (burst) mode
        // RX control defaults
        i_rx_mode=2'd0;                                       // DATA (descramble) loopback
        i_pcmp_enable=0; i_pcmp_mode=1; i_pcmp_pattern_mode=0; i_pcmp_clear=0;
        i_pcmp_lane_mask='0; i_pcmp_thr_per_lane=16'hFFFF;
        i_pcmp_thr_aggregate=16'hFFFF; i_pcmp_iter_count=16'd128;
        i_vcmp_enable=0; i_vcmp_mode=0; i_vcmp_clear=0; i_vcmp_thr=16'd0;
        i_clk_detector_en=0;
        pass_count=0; fail_count=0; gap_count=0; streaming=0; clk_ok=0;

        wait_pll(8);
        $display("\n=== PLL up (500 ps), releasing reset ===");
        @(negedge o_pll_clk); i_rst_n=1;
        wait_pll(20); wait_mb(4);

        // ---- clock-lane test first (burst pattern + detector), then forward
        //      the embedded clock so the deserialisers get their sampling clock ----
        i_clk_detector_en=1; i_clk_pattern_en=1;
        begin
            automatic int ct = 0;
            while (!(o_clk_p_pass && o_clk_n_pass && o_track_pass) && ct < 4000) begin
                @(posedge o_rx_pll_clk); ct++;
            end
            clk_ok = (o_clk_p_pass && o_clk_n_pass && o_track_pass);
            $display("=== CLOCK TEST : clk_p=%0b clk_n=%0b track=%0b (%0d clk) ===",
                     o_clk_p_pass, o_clk_n_pass, o_track_pass, ct);
        end
        i_clk_pattern_en=0; i_clk_detector_en=0;   // detector clears its flags here

        // start the TX pipeline streaming, enter DATA_TRANSFER, forward embedded clock
        i_mapper_en=1; lp_irdy=1; lp_valid=1; lp_data='0;
        i_clk_embedded_en=1;                      // forward the embedded clock (sample clock source)
        @(negedge lclk); i_lfsr_state=LFSR_DATA;
        $display("=== DATA_TRANSFER : waiting for RX back-end to arm (first recovered word) ===");

        begin
            automatic int g = 0;
            while (!o_rx_en && g < 200) begin @(posedge lclk); g++; end
            if (!o_rx_en) $display("  [WARN] RX never armed (no recovered word)!");
            else          $display("  [OK]   RX armed after %0d lclk; lock established.", g);
        end
        streaming = 1;

        // arm the comparators now that the streams are flowing
        i_vcmp_enable = 1;                        // valid comparator: mode 0 (16 consec)
        i_pcmp_enable = 1;                        // pattern comparator: informational

        // ---- flit recovery cases ----
        $display("\n--- Flit recovery (before-map  vs  after-demap) ---");
        run_case({16{32'hDEADBEEF}}, "0xDEADBEEF tiles");
        for (b=0;b<N_BYTES;b++) flit[b*8 +: 8] = 8'h10 + b[7:0];
        run_case(flit, "byte ramp 0x10+k");
        run_case({16{32'hCAFEBABE}}, "0xCAFEBABE tiles");
        run_case('0,                 "all zeros");
        run_case('1,                 "all ones");
        for (b=0;b<N_BYTES;b++) flit[b*8 +: 8] = (b%2==0)? 8'hA5 : 8'h5A;
        run_case(flit, "checker 0xA5/0x5A");
        run_case({16{32'h0F0F0F0F}}, "0x0F0F0F0F tiles");
        for (int c=0;c<4;c++) begin
            for (b=0;b<N_BYTES;b++) flit[b*8 +: 8] = $random;
            run_case(flit, $sformatf("random #%0d", c));
        end

        // ---- wait for the valid comparator to finish its 128-byte test ----
        vcmp_wait = 0;
        while (!o_vcmp_done && vcmp_wait < 4000) begin @(posedge o_pll_clk); vcmp_wait++; end

        // ---- stop streaming ----
        streaming = 0;
        @(negedge lclk);
        i_lfsr_state=LFSR_IDLE; i_mapper_en=0; lp_irdy=0; lp_valid=0;
        wait_mb(10);

        // ---- report ----
        $display("\n=========================================================");
        $display("  unit_mb_loopback  full TX -> RX results");
        $display("  ---------------------------------------------------------");
        $display("  flit cases PASSED         : %0d", pass_count);
        $display("  flit cases FAILED         : %0d", fail_count);
        $display("  recovered-stream bubbles  : %0d  (must be 0 for lockstep)", gap_count);
        $display("  ---------------------------------------------------------");
        $display("  [VALID CMP]  done=%0b pass=%0b  (mode 0 = 16 consecutive frames)",
                 o_vcmp_done, o_vcmp_pass);
        $display("  [CLK DET ]   clock-lane test passed (latched)=%0b  (burst clock pattern, run before embedded clock)",
                 clk_ok);
        $display("  [PATTERN CMP - informational] done=%0b agg_err_cnt=%0d agg_error=%0b per_lane_pass=0x%h",
                 o_pcmp_done, o_pcmp_agg_err_cnt, o_pcmp_agg_error, o_pcmp_per_lane_pass);
        $display("    (pattern comparator is informational here: lfsr_rx is in DATA_TRANSFER,");
        $display("     not a training pattern mode - see unit_mb_train_loopback_tb for the real check)");
        $display("=========================================================");

        if (fail_count == 0 && gap_count == 0 && pass_count > 0 && o_vcmp_done && o_vcmp_pass && clk_ok)
            $display("  >>> PASS : flit recovered exactly, valid comparator AND clock detector passed <<<");
        else if (fail_count == 0 && gap_count == 0 && pass_count > 0)
            $display("  >>> PARTIAL : flit loopback OK; vcmp pass=%0b clk_test=%0b <<<",
                     o_vcmp_pass, clk_ok);
        else
            $display("  >>> FAILURES DETECTED <<<");
        $display("");
        $stop;
    end

    // watchdog
    initial begin
        #2_000_000;   // 2 ms
        $display("[WATCHDOG] timeout!  pass=%0d fail=%0d vcmp_done=%0b", pass_count, fail_count, o_vcmp_done);
        $stop;
    end

endmodule
