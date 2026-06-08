`timescale 1ns/1ps
// =============================================================================
// Testbench : unit_mb_train_loopback_tb
// DUT       : unit_mb_loopback_wrapper  (unit_tx_top  ->  unit_mb_rx_top)
//
//  Goal
//  ----
//  TX -> RX loopback in TRAINING mode. The TX lfsr is driven into PATTERN_LFSR,
//  so it transmits the pure PRBS pattern (prbs32) on every lane. On the RX side
//  unit_mb_rx_top runs lfsr_rx in PATTERN_LFSR too (i_rx_mode=1): it regenerates
//  the same PRBS locally (o_final_gene) while capturing the received words
//  (o_Data_by). The pattern comparator then checks received vs locally-generated.
//
//  A clean link => 0 bit errors => every lane PASSes.
//
//  Run : make run CONFIG=integration_mb_rx_loopback TOP=unit_mb_train_loopback_tb
// =============================================================================

module unit_mb_train_loopback_tb;

    // ---------------------------------------------------------------- params
    localparam int DATA_WIDTH = 32;
    localparam int NUM_LANES  = 16;
    localparam int N_BYTES    = 64;
    localparam int FLITW      = 8*N_BYTES;

    localparam logic [2:0] LFSR_IDLE     = 3'b000;
    localparam logic [2:0] LFSR_PATTERN  = 3'b010;
    localparam logic [2:0] LFSR_PERLANE  = 3'b011;
    localparam logic [2:0] WIDTH_DEG_ALL = 3'b011;  // x16

    localparam logic [1:0] RXMODE_PATTERN = 2'd1;
    localparam logic [1:0] RXMODE_PERLANE = 2'd2;

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

    task automatic wait_pll(input int n); repeat (n) @(posedge o_pll_clk); endtask
    task automatic wait_mb (input int n); repeat (n) @(posedge lclk);      endtask

    int  pass_count, fail_count;

    // Run one training phase: full reset, drive the chosen TX lfsr state + RX
    // mode, arm, then run the pattern comparator and check all 16 lanes pass.
    //   pat_mode 0 = LFSR (count bit errors, threshold 0)
    //   pat_mode 1 = per-lane ID (16 consecutive matching iterations)
    task automatic run_phase(input logic [1:0] rxmode,
                             input logic [2:0] lfsr_st,
                             input logic       pat_mode,
                             input logic [15:0] iter,
                             input string      name);
        int armed_after, pcmp_wait;

        // ---- per-phase reset / config ----
        // Forward the embedded clock: the RX deserialisers now sample on the
        // forwarded TX clock (unit_mb_rx_top derives sample_clk from i_TCKP_P),
        // so embedded_en must be high for any data to be recovered.
        i_clk_embedded_en=1;
        i_rst_n=0; lp_data='0; lp_irdy=0; lp_valid=0; i_mapper_en=0;
        i_lfsr_state=LFSR_IDLE; i_pcmp_enable=0; i_pcmp_clear=0;
        i_rx_mode=rxmode; i_pcmp_mode=0; i_pcmp_pattern_mode=pat_mode;
        i_pcmp_lane_mask='0; i_pcmp_thr_per_lane=16'd0;
        i_pcmp_thr_aggregate=16'd0; i_pcmp_iter_count=iter;

        wait_pll(8);
        @(negedge o_pll_clk); i_rst_n=1;
        wait_pll(20); wait_mb(4);

        // start TX, enter the requested training state
        i_mapper_en=1; lp_irdy=1; lp_valid=1; lp_data='0;
        @(negedge lclk); i_lfsr_state=lfsr_st;
        $display("=== %s : waiting for RX to arm + lfsr_rx to generate ===", name);

        armed_after = 0;
        while (!o_rx_en && armed_after < 200) begin @(posedge lclk); armed_after++; end
        if (!o_rx_en) begin
            fail_count++;
            $display("  [FAIL] %s : RX never armed", name);
            return;
        end
        $display("  [OK]   RX armed after %0d lclk", armed_after);

        // wait until lfsr_rx is generating the reference, then skip a couple of
        // startup cycles so o_final_gene and o_Data_by are both aligned & valid.
        @(posedge o_pattern_comp_en);
        wait_mb(3);

        i_pcmp_enable = 1;
        pcmp_wait = 0;
        while (!o_pcmp_done && pcmp_wait < 400) begin @(posedge lclk); pcmp_wait++; end

        $display("  [%s] pcmp done=%0b per_lane_pass=0x%04h agg_err_cnt=%0d agg_error=%0b",
                 name, o_pcmp_done, o_pcmp_per_lane_pass, o_pcmp_agg_err_cnt, o_pcmp_agg_error);
        if (o_pcmp_done && (o_pcmp_per_lane_pass === 16'hFFFF)) begin
            pass_count++;
            $display("  [PASS] %s : all 16 lanes matched the local reference", name);
        end else begin
            fail_count++;
            $display("  [FAIL] %s : done=%0b mask=0x%04h", name, o_pcmp_done, o_pcmp_per_lane_pass);
        end

        // teardown for the next phase
        @(negedge lclk);
        i_lfsr_state=LFSR_IDLE; i_mapper_en=0; lp_irdy=0; lp_valid=0; i_pcmp_enable=0;
        wait_mb(5);
    endtask

    initial begin
        // static config
        i_width_deg=WIDTH_DEG_ALL; i_reversal_en=0; i_valid_pattern_en=0;
        i_pll_en=1; i_pll_speed_sel=2'b00; lclk_g=1;
        i_clk_pattern_en=0; i_clk_embedded_en=0; i_clk_detector_en=0;
        i_vcmp_enable=0; i_vcmp_mode=0; i_vcmp_clear=0; i_vcmp_thr=16'd0;
        pass_count=0; fail_count=0;

        $display("\n=== MB training loopback : PATTERN_LFSR then PER_LANE_ID ===");
        run_phase(RXMODE_PATTERN, LFSR_PATTERN, 1'b0, 16'd32, "PATTERN_LFSR");
        run_phase(RXMODE_PERLANE, LFSR_PERLANE, 1'b1, 16'd16, "PER_LANE_ID ");

        $display("\n=========================================================");
        $display("  unit_mb_train_loopback results : %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0 && pass_count == 2)
            $display("  >>> PASS : pattern comparator matched local reference in BOTH modes <<<");
        else
            $display("  >>> FAIL : see per-phase results above <<<");
        $display("=========================================================\n");
        $stop;
    end

    // watchdog
    initial begin
        #2_000_000;
        $display("[WATCHDOG] timeout! pcmp_done=%0b", o_pcmp_done);
        $stop;
    end

endmodule
