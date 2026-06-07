`timescale 1ns/1ps
// =============================================================================
// Testbench : unit_tx_demap_wrapper_tb
// DUT       : unit_tx_demap_wrapper  (rtl/MainBand/Integration steps/)
//
//  Goal
//  ----
//  Drive a flit into unit_tx_top's mapper, run the full
//      mapper -> lfsr_tx -> serializer -> s2 deser -> lfsr_rx -> demapper
//  loopback, and check the recovered flit (after demapper) against the original
//  flit (before mapper).
//
//  Byte ordering: unit_demapper is a faithful inverse of unit_mapper, so the
//  recovered flit equals the original (o_out_data == lp_data). (The demapper was
//  fixed to reverse its output byte order; previously demap(map(flit)) came back
//  byte-reversed.) The TB therefore expects  o_out_data == lp_data.
//
//  Method
//  ------
//  unit_tx_top streams continuously (mapper enabled, lfsr in DATA_TRANSFER); only
//  lp_data changes per case. The descrambler stays locked across the whole run
//  (data content is irrelevant to LFSR lockstep). For each case we hold a flit,
//  wait for o_out_data to settle to byte_reverse(flit), then confirm it stays
//  stable for several pl_valid frames. Passing many DISTINCT flits proves the
//  lfsr_rx <-> lfsr_tx lockstep end-to-end. A gap monitor confirms the recovered
//  word stream is bubble-free (the precondition for that lockstep).
//
//  Run : make run CONFIG=integration_tx_demap TOP=unit_tx_demap_wrapper_tb
// =============================================================================

module unit_tx_demap_wrapper_tb;

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

    logic                  lclk, o_pll_clk, o_rx_pll_clk;
    logic                  o_lfsr_tx_done, o_valid_done, o_clk_done;
    logic [NUM_LANES-1:0]  TD_P;
    logic                  TVLD_P, TCKP_P, TCKN_P, TTRK_P;
    logic [DATA_WIDTH-1:0] o_par_data [0:NUM_LANES-1];
    logic                  o_data_valid, o_valid_frame_pulse;
    logic [DATA_WIDTH-1:0] o_rx_lane  [0:NUM_LANES-1];
    logic                  o_rx_en;
    logic [FLITW-1:0]      o_out_data;
    logic                  o_pl_valid;

    // ---------------------------------------------------------------- DUT
    unit_tx_demap_wrapper #(
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
        .o_out_data         (o_out_data),
        .o_pl_valid         (o_pl_valid)
    );

    // ---------------------------------------------------------------- counters
    int pass_count, fail_count, gap_count;
    bit streaming;

    // gap monitor: while streaming and armed, o_data_valid must never drop
    // (bubble-free recovered stream is the precondition for LFSR lockstep)
    always @(posedge lclk)
        if (streaming && o_rx_en && !o_data_valid) gap_count++;

    // ---------------------------------------------------------------- helpers
    task automatic wait_pll(input int n); repeat (n) @(posedge o_pll_clk); endtask
    task automatic wait_mb (input int n); repeat (n) @(posedge lclk);      endtask

    // diagnostic only: the OLD (unfixed) demapper returned this byte-reversed flit
    function automatic logic [FLITW-1:0] byte_reverse(input logic [FLITW-1:0] d);
        for (int k = 0; k < N_BYTES; k++)
            byte_reverse[k*8 +: 8] = d[(N_BYTES-1-k)*8 +: 8];
    endfunction

    // Hold a flit, wait for the recovered output to settle, then confirm stable.
    task automatic run_case(input logic [FLITW-1:0] flit, input string name);
        logic [FLITW-1:0] exp;
        int  t, good, bad, seen;
        bit  got;
        exp = flit;                           // faithful round trip: out == in

        @(negedge lclk);
        lp_data = flit;                       // apply this case's flit

        // wait for the demapper output to reach the expected (byte-reversed) flit
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
            if (o_out_data === byte_reverse(flit))
                $display("         (note: output is byte-reversed -> demapper inverse fix not in effect)");
            return;
        end

        // confirm it holds across HOLD_CHK valid frames
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

    initial begin
        // init / reset
        i_rst_n=0; lp_data='0; lp_irdy=0; lp_valid=0; i_mapper_en=0;
        i_width_deg=WIDTH_DEG_ALL; i_lfsr_state=LFSR_IDLE; i_reversal_en=0;
        i_valid_pattern_en=0; i_pll_en=1; i_pll_speed_sel=2'b00;
        lclk_g=1; i_clk_pattern_en=0; i_clk_embedded_en=1;
        pass_count=0; fail_count=0; gap_count=0; streaming=0;

        wait_pll(8);
        $display("\n=== PLL up (500 ps), releasing reset ===");
        @(negedge o_pll_clk); i_rst_n=1;
        wait_pll(20); wait_mb(4);

        // start the TX pipeline streaming (prime with zeros), enter DATA_TRANSFER
        i_mapper_en=1; lp_irdy=1; lp_valid=1; lp_data='0;
        @(negedge lclk); i_lfsr_state=LFSR_DATA;
        $display("=== DATA_TRANSFER : waiting for RX back-end to arm (first recovered word) ===");

        // wait until the RX back-end is armed (first recovered word seen)
        begin
            automatic int g = 0;
            while (!o_rx_en && g < 200) begin @(posedge lclk); g++; end
            if (!o_rx_en) $display("  [WARN] RX never armed (no recovered word)!");
            else          $display("  [OK]   RX armed after %0d lclk; lock established.", g);
        end
        streaming = 1;

        // ---- cases : distinct flits ----
        run_case(64'h0 + {16{32'hDEADBEEF}}, "0xDEADBEEF tiles");

        // byte ramp (each byte distinct) - like unit_mb_path_tb
        for (b=0;b<N_BYTES;b++) flit[b*8 +: 8] = 8'h10 + b[7:0];
        run_case(flit, "byte ramp 0x10+k");

        run_case({16{32'hCAFEBABE}}, "0xCAFEBABE tiles");
        run_case('0,                 "all zeros");
        run_case('1,                 "all ones");

        for (b=0;b<N_BYTES;b++) flit[b*8 +: 8] = (b%2==0)? 8'hA5 : 8'h5A;
        run_case(flit, "checker 0xA5/0x5A");

        run_case({16{32'h0F0F0F0F}}, "0x0F0F0F0F tiles");

        // a few random flits
        for (int c=0;c<4;c++) begin
            for (b=0;b<N_BYTES;b++) flit[b*8 +: 8] = $random;
            run_case(flit, $sformatf("random #%0d", c));
        end

        // ascending 32-bit words across lanes
        for (b=0;b<N_BYTES;b++) flit[b*8 +: 8] = (b*8'h07 + 8'h3) ^ b[7:0];
        run_case(flit, "mixed arithmetic");

        // ---- stop streaming ----
        streaming = 0;
        @(negedge lclk);
        i_lfsr_state=LFSR_IDLE; i_mapper_en=0; lp_irdy=0; lp_valid=0;
        wait_mb(10);

        // ---- report ----
        $display("\n=========================================================");
        $display("  unit_tx_demap_wrapper  end-to-end loopback results");
        $display("  (before-map flit  vs  after-demap recovered flit)");
        $display("  ---------------------------------------------------------");
        $display("  cases PASSED              : %0d", pass_count);
        $display("  cases FAILED              : %0d", fail_count);
        $display("  recovered-stream bubbles  : %0d  (must be 0 for lockstep)", gap_count);
        $display("=========================================================");
        if (fail_count == 0 && gap_count == 0 && pass_count > 0)
            $display("  >>> ALL %0d CASES PASS : flit recovered exactly (before-map == after-demap), LFSR locked <<<", pass_count);
        else
            $display("  >>> FAILURES DETECTED <<<");
        $display("");
        $stop;
    end

    // watchdog
    initial begin
        #2_000_000;   // 2 ms
        $display("[WATCHDOG] timeout!  pass=%0d fail=%0d", pass_count, fail_count);
        $stop;
    end

endmodule
