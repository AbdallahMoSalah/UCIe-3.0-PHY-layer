// =============================================================================
// Testbench : MB_TX_TOP_tb
// DUT       : MB_TX_TOP
//
//  All DUT sub-modules (Mapper, LFSR_TX, VALID_TX, CLK_PATTERN_GEN_TX,
//  MB_SERIALIZER) are clocked by o_pll_clk (output of MB_PLL).
//  Therefore the PLL is enabled BEFORE reset is released, and every
//  stimulus / sampling task is synchronised to o_pll_clk.
//
//  i_mb_clk drives only the MB_PLL reference input (500 MHz).
//  i_pll_speed_sel = 00 → 2 GHz o_pll_clk (500 ps period).
//
//  Test Sequence
//  ─────────────
//  Phase 1 – CLK Pattern Generation
//             Assert i_clk_pattern_en → wait for o_clk_done.
//             CLK_PATTERN_GEN_TX uses always@(*) — fires on BOTH o_pll_clk edges.
//             6144 total counter steps / 2 edges per cycle = ~3072 posedge cycles.
//
//  Phase 2 – VALID Pattern
//             Assert i_valid_pattern_en for 1 cycle → wait for o_valid_done.
//             VALID_TX runs for 32 o_pll_clk cycles.
//
//  Phase 3 – LFSR Pattern (PATTERN_LFSR – 128-cycle burst)
//             Drive i_lfsr_state = PATTERN_LFSR → wait for o_lfsr_tx_done.
//
//  Phase 4 – DATA_TRANSFER (end-to-end data path)
//             Assert i_active_state_entered with mapper_en/lp_irdy/lp_valid
//             and a known i_raw_data pattern. Verify o_tx_data / o_tx_valid.
// =============================================================================

`timescale 1ps/1ps

module MB_TX_TOP_tb;

    // =========================================================================
    // Parameters (must match DUT)
    // =========================================================================
    localparam DATA_WIDTH = 32;
    localparam NUM_LANES  = 16;
    localparam N_BYTES    = 64;

    // LFSR state codes (matching LFSR_TX localparams)
    localparam LFSR_IDLE         = 3'b000;
    localparam LFSR_CLEAR        = 3'b001;
    localparam LFSR_PATTERN      = 3'b010;
    localparam LFSR_PER_LANE_IDE = 3'b011;
    localparam LFSR_DATA         = 3'b100;

    // Width-degradation code: 3'b011 → all 16 lanes active (1 clock cycle)
    localparam WIDTH_DEG_ALL = 3'b011;

    // i_mb_clk: 500 MHz (2 ns period, 1 ns half-period)
    // timescale is 1ps/1ps → delay unit is ps, so 1 ns = 1000 ps
    localparam MB_CLK_HALF = 1000;  // ps

    // =========================================================================
    // Clocks & DUT signals
    // =========================================================================
    logic i_mb_clk = 1'b0;
    always #(MB_CLK_HALF) i_mb_clk = ~i_mb_clk;

    logic                     i_rst_n;
    logic                     o_pll_clk;
    real                      period_out;          // DUT port is "output real period"

    // Mapper
    logic [8*N_BYTES-1:0]     i_raw_data;
    logic                     i_mapper_en;
    logic [2:0]               i_width_deg;
    logic                     i_lp_irdy;
    logic                     i_lp_valid;

    // LFSR_TX
    logic [2:0]               i_lfsr_state;
    logic                     i_reversal_en;
    logic                     i_active_state_entered;

    // VALID_TX
    logic                     i_valid_pattern_en;

    // Serial outputs
    logic [NUM_LANES-1:0]     o_tx_data;
    logic                     o_tx_valid;

    // MB_PLL
    logic                     i_pll_en;
    logic [1:0]               i_pll_speed_sel;

    // CLK_PATTERN_GEN_TX
    logic                     i_clk_pattern_en;
    logic                     i_clk_embedded_en;
    logic                     o_clk_p;
    logic                     o_clk_n;
    logic                     o_clk_track;
    logic                     o_clk_done;

    // Status
    logic                     o_mapper_ready;
    logic                     o_lfsr_tx_done;
    logic                     o_valid_done;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    MB_TX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES),
        .N_BYTES    (N_BYTES)
    ) dut (
        .i_mb_clk               (i_mb_clk),
        .i_rst_n                (i_rst_n),
        .o_pll_clk              (o_pll_clk),
        .period                 (period_out),

        .i_raw_data             (i_raw_data),
        .i_mapper_en            (i_mapper_en),
        .i_width_deg            (i_width_deg),
        .i_lp_irdy              (i_lp_irdy),
        .i_lp_valid             (i_lp_valid),

        .i_lfsr_state           (i_lfsr_state),
        .i_reversal_en          (i_reversal_en),
        .i_active_state_entered (i_active_state_entered),

        .i_valid_pattern_en     (i_valid_pattern_en),

        .o_tx_data              (o_tx_data),
        .o_tx_valid             (o_tx_valid),

        .i_pll_en               (i_pll_en),
        .i_pll_speed_sel        (i_pll_speed_sel),

        .i_clk_pattern_en       (i_clk_pattern_en),
        .i_clk_embedded_en      (i_clk_embedded_en),
        .o_clk_p                (o_clk_p),
        .o_clk_n                (o_clk_n),
        .o_clk_track            (o_clk_track),
        .o_clk_done             (o_clk_done),

        .o_mapper_ready         (o_mapper_ready),
        .o_lfsr_tx_done         (o_lfsr_tx_done),
        .o_valid_done           (o_valid_done)
    );

    // =========================================================================
    // Helpers — all synchronised to o_pll_clk (the DUT's operational clock)
    // =========================================================================

    // Wait N rising edges of o_pll_clk
    task automatic wait_clk(input int n);
        repeat (n) @(posedge o_pll_clk);
    endtask

    // Poll a logic signal on o_pll_clk edges, with a cycle timeout
    task automatic wait_for_signal(
        input  string sig_name,
        ref    logic  sig,
        input  int    timeout_cycles
    );
        int cyc = 0;
        while (!sig && cyc < timeout_cycles) begin
            @(posedge o_pll_clk);
            cyc++;
        end
        if (cyc >= timeout_cycles)
            $display("  [TIMEOUT] %s did not assert within %0d o_pll_clk cycles!",
                     sig_name, timeout_cycles);
        else
            $display("  [OK]      %s asserted after %0d o_pll_clk cycles.",
                     sig_name, cyc);
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    integer test_num;

    initial begin

        // ------------------------------------------------------------------
        // Initialise all inputs — DUT held in reset
        // ------------------------------------------------------------------
        i_rst_n                = 1'b0;
        i_raw_data             = '0;
        i_mapper_en            = 1'b0;
        i_width_deg            = WIDTH_DEG_ALL;
        i_lp_irdy              = 1'b0;
        i_lp_valid             = 1'b0;
        i_lfsr_state           = LFSR_IDLE;
        i_reversal_en          = 1'b0;
        i_active_state_entered = 1'b0;
        i_valid_pattern_en     = 1'b0;
        i_pll_en               = 1'b0;
        i_pll_speed_sel        = 2'b00;   // 2 GHz
        i_clk_pattern_en       = 1'b0;
        i_clk_embedded_en      = 1'b0;

        // ------------------------------------------------------------------
        // Step 1: Enable PLL — must come before reset release because every
        // DUT register is clocked by o_pll_clk. Without o_pll_clk running,
        // no sequential logic can initialise.
        // speed_sel = 00 → 2 GHz (500 ps period, 1ps resolution from MB_PLL)
        // ------------------------------------------------------------------
        @(posedge i_mb_clk);
        i_pll_en        = 1'b1;
        i_pll_speed_sel = 2'b00;

        // Wait for PLL to start driving o_pll_clk and stabilise
        repeat (8) @(posedge o_pll_clk);

        $display("\n=== PLL running  (speed_sel=00 → 2 GHz, period=%0.1f ps) ===", period_out);

        // ------------------------------------------------------------------
        // Step 2: Release reset on a o_pll_clk negedge so all registers
        // see the de-assertion cleanly at the next posedge
        // ------------------------------------------------------------------
        @(negedge o_pll_clk);
        i_rst_n = 1'b1;
        $display("=== RESET released ===\n");
        wait_clk(4);

        // ==================================================================
        // PHASE 1 – Clock Pattern Generation
        //   CLK_PATTERN_GEN_TX is clocked by o_pll_clk.
        //   always@(*) fires on both edges → 6144 counter steps / 2 = ~3072 posedge cycles.
        // ==================================================================
        test_num = 1;
        $display("=== PHASE %0d: CLK Pattern Generation ===", test_num);

        @(negedge o_pll_clk);
        i_clk_pattern_en = 1'b1;
        $display("  Asserting i_clk_pattern_en ...");

        // ~3072 actual posedge cycles; 7000 is ~2.3× margin
        wait_for_signal("o_clk_done", o_clk_done, 7000);

        @(negedge o_pll_clk);
        i_clk_pattern_en = 1'b0;

        if ($isunknown(o_clk_p))
            $display("  [FAIL]    o_clk_p is X/Z after clock pattern burst.");
        else
            $display("  [OK]      o_clk_p = %b after burst.", o_clk_p);

        wait_clk(4);

        // ==================================================================
        // PHASE 2 – VALID Pattern  (VALID_TX 32-cycle burst)
        //   VALID_TX is clocked by o_pll_clk.
        //   Burst runs for MAX_COUNT-1 = 32 o_pll_clk cycles.
        // ==================================================================
        test_num = 2;
        $display("\n=== PHASE %0d: VALID Pattern ===", test_num);

        @(negedge o_pll_clk);
        i_valid_pattern_en = 1'b1;
        $display("  Asserting i_valid_pattern_en for 1 cycle ...");
        @(negedge o_pll_clk);
        i_valid_pattern_en = 1'b0;

        // Burst is 32 cycles; 100-cycle timeout is generous
        wait_for_signal("o_valid_done", o_valid_done, 100);

        wait_clk(4);

        // ==================================================================
        // PHASE 3 – LFSR Pattern  (PATTERN_LFSR – 128-cycle burst)
        //   LFSR_TX is clocked by o_pll_clk.
        //   LFSR_TX uses edge-detection on i_lfsr_state — hold the state
        //   high until the burst finishes.
        // ==================================================================
        test_num = 3;
        $display("\n=== PHASE %0d: LFSR Pattern (128-cycle burst) ===", test_num);

        @(negedge o_pll_clk);
        i_lfsr_state = LFSR_PATTERN;
        $display("  Driving i_lfsr_state = PATTERN_LFSR ...");

        // 128 burst cycles + ~2 entry latency; 300-cycle timeout
        wait_for_signal("o_lfsr_tx_done", o_lfsr_tx_done, 300);

        @(negedge o_pll_clk);
        i_lfsr_state = LFSR_IDLE;

        wait_clk(4);

        // ==================================================================
        // PHASE 4 – DATA_TRANSFER (Mapper → LFSR_TX → Serializer → output)
        // ==================================================================
        test_num = 4;
        $display("\n=== PHASE %0d: DATA_TRANSFER – end-to-end data path ===", test_num);

        // 512-bit alternating pattern: even bytes = 0xA5, odd bytes = 0x5A
        begin
            integer b;
            for (b = 0; b < N_BYTES; b = b + 1)
                i_raw_data[b*8 +: 8] = (b % 2 == 0) ? 8'hA5 : 8'h5A;
        end

        i_width_deg = WIDTH_DEG_ALL;
        i_mapper_en = 1'b1;
        i_lp_irdy   = 1'b1;
        i_lp_valid  = 1'b1;

        // Enter DATA_TRANSFER — LFSR_TX latches this on posedge o_pll_clk
        @(negedge o_pll_clk);
        i_active_state_entered = 1'b1;
        $display("  Asserting i_active_state_entered ...");

        // Mapper with WIDTH_DEG_ALL completes in 1 cycle → ready fires fast
        wait_for_signal("o_mapper_ready", o_mapper_ready, 20);

        // Allow the serializer time to shift out one full 32-bit word.
        // CDC sync: 2 posedge cycles. DDR serialization: DATA_WIDTH/2 = 16 cycles.
        // Total minimum = 18 posedge cycles; 50 gives ample margin.
        wait_clk(50);

        if (o_tx_data !== {NUM_LANES{1'b0}})
            $display("  [OK]      o_tx_data is non-zero: 0x%h", o_tx_data);
        else
            $display("  [WARN]    o_tx_data is all zeros – serializer may still loading.");

        if (o_tx_valid !== 1'b0)
            $display("  [OK]      o_tx_valid is active.");
        else
            $display("  [WARN]    o_tx_valid is 0.");

        // Run a further 20 cycles then de-assert
        wait_clk(20);

        @(negedge o_pll_clk);
        i_active_state_entered = 1'b0;
        i_mapper_en            = 1'b0;
        i_lp_irdy              = 1'b0;
        i_lp_valid             = 1'b0;
        $display("  De-asserting i_active_state_entered – returning to IDLE.");

        wait_clk(4);

        // ==================================================================
        // All phases complete
        // ==================================================================
        $display("\n=================================================");
        $display("  MB_TX_TOP Testbench COMPLETE – all phases done.");
        $display("=================================================\n");
        $stop;
    end

    // =========================================================================
    // Timeout watchdog
    // timescale 1ps/1ps → units are ps.
    // Worst case: Phase 1 CLK burst = 3072 × 500 ps ≈ 1.54 µs (both-edge firing)
    //             All phases combined ≈ 5 µs
    // Watchdog set to 500 µs = 500_000_000 ps — well beyond any expected run.
    // =========================================================================
    initial begin
        #500_000_000;
        $display("[WATCHDOG] Simulation timed out!");
        $stop;
    end

    // =========================================================================
    // Monitor — sampled on o_pll_clk (the DUT's operational clock domain)
    // =========================================================================
    always @(posedge o_pll_clk) begin
        if (o_clk_done)
            $display("  [MON] t=%0t  o_clk_done    HIGH", $time);
        if (o_valid_done)
            $display("  [MON] t=%0t  o_valid_done  HIGH", $time);
        if (o_lfsr_tx_done)
            $display("  [MON] t=%0t  o_lfsr_tx_done HIGH", $time);
        if (o_mapper_ready)
            $display("  [MON] t=%0t  o_mapper_ready HIGH", $time);
    end

endmodule
