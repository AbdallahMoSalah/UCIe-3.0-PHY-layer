// =============================================================================
// Testbench : MB_TX_TOP_tb
// DUT       : MB_TX_TOP
//
//  Clock domains
//  ─────────────
//  o_mb_clk            (500 MHz, 2 ns period)
//      → MB_PLL ref, Mapper, LFSR_TX, VALID_TX,
//        mb_clk port of every MB_SERIALIZER.
//
//  o_pll_clk (2 GHz, 500 ps period, speed_sel=00)
//      → CLK_PATTERN_GEN_TX (always@(∗) block),
//        PLL_clk port of every MB_SERIALIZER.
//
//  PLL is enabled BEFORE reset so o_pll_clk is running when i_rst_n releases.
//  Stimulus is driven synchronous to each sub-module's clock domain.
//
//  Domain assignments for status outputs
//  ──────────────────────────────────────
//  o_mapper_ready  → Mapper    → o_mb_clk            → polled on o_mb_clk           edges
//  o_lfsr_tx_done  → LFSR_TX  → o_mb_clk            → polled on o_mb_clk           edges
//  o_valid_done    → VALID_TX  → o_mb_clk            → polled on o_mb_clk           edges
//  o_clk_done      → CLK_PAT  → o_pll_clk → polled on o_pll_clk edges
//  o_tx_data/valid → SERIALIZER PLL side   → sampled on o_pll_clk edges
//
//  Test Sequence
//  ─────────────
//  Phase 1 – CLK Pattern (CLK_PATTERN_GEN_TX, o_pll_clk domain)
//             always@(*) fires on BOTH o_pll_clk edges:
//             6144 counter steps / 2 = ~3072 o_pll_clk posedge cycles ≈ 1.54 µs.
//             o_clk_n is o_clk_p delayed by period/2 (dynamic, from MB_PLL).
//             At speed_sel=00: period=500 ps → delay=250 ps (true 180° differential).
//
//  Phase 2 – VALID Pattern (VALID_TX, o_mb_clk           domain)
//             Assert i_valid_pattern_en for 1 o_mb_clk           cycle.
//             Burst = 32 o_mb_clk           cycles = 64 ns.
//
//  Phase 3 – LFSR Pattern (LFSR_TX, o_mb_clk           domain, 128-cycle burst)
//             128 o_mb_clk           cycles = 256 ns.
//
//  Phase 3b– PER_LANE_IDE check (i_reversal_en=0)
//             Drive i_lfsr_state = LFSR_PER_LANE_IDE.
//             Poll o_lfsr_tx_done on o_mb_clk           edges.
//
//  Phase 4 – DATA_TRANSFER (i_reversal_en=0)
//             Stimulus  : o_mb_clk           (Mapper + LFSR_TX → mb_clk side of SER).
//             Output    : o_pll_clk (PLL side of MB_SERIALIZER).
//             CDC path  : 2–3 o_pll_clk cycles (toggle-sync, 3 flops).
//             DDR SER   : DATA_WIDTH/2 = 16 o_pll_clk cycles.
//             Alignment : up to 4 o_pll_clk cycles (mb:pll = 1:4 ratio).
//             Total min : ~23 o_pll_clk cycles → wait_clk_pll(50) has margin.
//
//  ── Lane-Reversal Group (i_reversal_en = 1) ──────────────────────────────
//  Phase 5 – LFSR Pattern  (same as Phase 3  but with i_reversal_en=1)
//  Phase 6 – PER_LANE_IDE  (same as Phase 3b but with i_reversal_en=1)
//  Phase 7 – DATA_TRANSFER (same as Phase 4  but with i_reversal_en=1)
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

    // Width-degradation code: 3'b011 → all 16 lanes active (1 o_mb_clk           cycle)
    localparam WIDTH_DEG_ALL = 3'b011;

    // o_mb_clk          : 500 MHz (2 ns period, 1 ns half-period)
    // timescale 1ps/1ps → delay unit is ps, so 1 ns = 1000 ps
    localparam MB_CLK_HALF = 1000;  // ps

    // =========================================================================
    // Clocks & DUT signals
    // =========================================================================
    logic o_mb_clk   ;

    logic                     i_rst_n;
    logic                     o_pll_clk;
    real                      period_out;   // matches DUT "output real period"

    // Mapper (o_mb_clk           domain)
    logic [8*N_BYTES-1:0]     i_raw_data;
    logic                     i_mapper_en;
    logic [2:0]               i_width_deg;
    logic                     i_lp_irdy;
    logic                     i_lp_valid;

    // LFSR_TX (o_mb_clk           domain)
    logic [2:0]               i_lfsr_state;
    logic                     i_reversal_en;
    logic                     i_active_state_entered;

    // VALID_TX (o_mb_clk           domain)
    logic                     i_valid_pattern_en;

    // Serial outputs (o_pll_clk domain, from MB_SERIALIZER PLL side)
    logic [NUM_LANES-1:0]     o_tx_data;
    logic                     o_tx_valid;

    // MB_PLL
    logic                     i_pll_en;
    logic [1:0]               i_pll_speed_sel;

    // CLK_PATTERN_GEN_TX (o_pll_clk domain)
    logic                     i_clk_pattern_en;
    logic                     i_clk_embedded_en;
    logic                     o_clk_p;
    logic                     o_clk_n;
    logic                     o_clk_track;
    logic                     o_clk_done;

    // Status
    logic                     o_mapper_ready;   // o_mb_clk           domain
    logic                     o_lfsr_tx_done;   // o_mb_clk           domain
    logic                     o_valid_done;     // o_mb_clk           domain

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    MB_TX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES),
        .N_BYTES    (N_BYTES)
    ) dut (
        .o_mb_clk               (o_mb_clk),
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
    // Helpers
    // =========================================================================

    // Wait N rising edges of o_pll_clk  (CLK_PATTERN_GEN_TX / MB_SERIALIZER PLL side)
    task automatic wait_clk_pll(input int n);
        repeat (n) @(posedge o_pll_clk);
    endtask

    // Wait N rising edges of o_mb_clk            (Mapper / LFSR_TX / VALID_TX)
    task automatic wait_clk_mb(input int n);
        repeat (n) @(posedge o_mb_clk);
    endtask

    // Poll a signal on o_pll_clk edges (CLK_PATTERN_GEN_TX / serial outputs)
    task automatic wait_for_signal_pll(
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
            $display("  [TIMEOUT] %s not asserted within %0d o_pll_clk cycles!",
                     sig_name, timeout_cycles);
        else
            $display("  [OK]      %s asserted after %0d o_pll_clk cycles.",
                     sig_name, cyc);
    endtask

    // Poll a signal on o_mb_clk           edges  (Mapper / LFSR_TX / VALID_TX outputs)
    task automatic wait_for_signal_mb(
        input  string sig_name,
        ref    logic  sig,
        input  int    timeout_cycles
    );
        int cyc = 0;
        while (!sig && cyc < timeout_cycles) begin
            @(posedge o_mb_clk);
            cyc++;
        end
        if (cyc >= timeout_cycles)
            $display("  [TIMEOUT] %s not asserted within %0d o_mb_clk           cycles!",
                     sig_name, timeout_cycles);
        else
            $display("  [OK]      %s asserted after %0d o_mb_clk           cycles.",
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
        // Step 1: Enable PLL.
        // speed_sel=00 → o_pll_clk at 2 GHz (500 ps period).
        // Must run before reset so MB_SERIALIZER PLL_clk side is already
        // clocking when i_rst_n de-asserts.
        // ------------------------------------------------------------------
        i_pll_en        = 1'b1;
        i_pll_speed_sel = 2'b00;

        // Wait 8 o_pll_clk cycles (4 ns) for PLL output to stabilise
        repeat (8) @(posedge o_pll_clk);

        $display("\n=== PLL running  (speed_sel=00 → 2 GHz, period=%0.1f ps) ===", period_out);
        $display("    o_clk_n delay = %0.1f ps  (period/2, dynamic from MB_PLL)", period_out / 2.0);

        // ------------------------------------------------------------------
        // Step 2: Release reset synchronous to o_mb_clk          .
        // Mapper, LFSR_TX and VALID_TX are all in the o_mb_clk           domain.
        // MB_SERIALIZER uses async reset so both clock sides clear together.
        // ------------------------------------------------------------------
        @(posedge o_pll_clk);
        i_rst_n = 1'b1;
        $display("=== RESET released (o_mb_clk           negedge) ===\n");

        // 4 o_mb_clk           cycles = 8 ns: all registers in both domains settle
        wait_clk_mb(4);

        // ==================================================================
        // PHASE 1 – Clock Pattern Generation  (o_pll_clk domain)
        //   CLK_PATTERN_GEN_TX.i_clk = o_pll_clk.
        //   Uses always@(*) → fires on BOTH o_pll_clk edges.
        //   6144 counter steps / 2 = ~3072 o_pll_clk posedge cycles ≈ 1.54 µs.
        //   o_clk_n is driven by phase_delay with i_half_period = period/2.
        //   The delay is set at event time (non-blocking + variable delay).
        // ==================================================================
        test_num = 1;
        $display("=== PHASE %0d: CLK Pattern Generation ===", test_num);

        @(negedge o_pll_clk);
        i_clk_pattern_en = 1'b1;
        $display("  Asserting i_clk_pattern_en ...");

        // ~3072 actual posedge cycles; 7000 gives ~2.3× margin
        wait_for_signal_pll("o_clk_done", o_clk_done, 7000);

        @(negedge o_pll_clk);
        i_clk_pattern_en = 1'b0;

        if ($isunknown(o_clk_p))
            $display("  [FAIL]    o_clk_p is X/Z after clock pattern burst.");
        else
            $display("  [OK]      o_clk_p = %b after burst.", o_clk_p);

        // o_clk_n is o_clk_p delayed by period/2 (= %0.1f ps).
        // After burst ends o_clk_p is 0, so o_clk_n should settle to 0 too.
        #(period_out);   // wait 1 full period for the delayed edge to resolve
        if ($isunknown(o_clk_n))
            $display("  [FAIL]    o_clk_n is X/Z (delay=%0.1f ps not resolved).", period_out/2.0);
        else
            $display("  [OK]      o_clk_n = %b  (delay = %0.1f ps = period/2).",
                     o_clk_n, period_out / 2.0);

        wait_clk_pll(4);

        // ==================================================================
        // PHASE 2 – VALID Pattern  (o_mb_clk           domain)
        //   VALID_TX.i_clk = o_mb_clk           (500 MHz).
        //   Burst = 32 o_mb_clk           cycles = 64 ns.
        //   Assert i_valid_pattern_en for exactly 1 o_mb_clk           cycle.
        //   Poll o_valid_done on o_mb_clk           edges.
        // ==================================================================
        test_num = 2;
        $display("\n=== PHASE %0d: VALID Pattern ===", test_num);

        @(negedge o_mb_clk          );
        i_valid_pattern_en = 1'b1;
        $display("  Asserting i_valid_pattern_en for 1 o_mb_clk           cycle ...");
      
        // Burst = 32 o_mb_clk           cycles; 100-cycle timeout is generous
        wait_for_signal_mb("o_valid_done", o_valid_done, 100);
        
        i_valid_pattern_en = 1'b0;
        wait_clk_mb(4);

        // ==================================================================
        // PHASE 3 – LFSR Pattern  (o_mb_clk           domain, 128-cycle burst)
        //   LFSR_TX.i_clk = o_mb_clk           (500 MHz).
        //   Hold i_lfsr_state = PATTERN_LFSR until burst finishes.
        //   Poll o_lfsr_tx_done on o_mb_clk           edges.
        //   128 o_mb_clk           cycles = 256 ns; 300-cycle timeout is ~2.3× margin.
        // ==================================================================
        test_num = 3;
        $display("\n=== PHASE %0d: LFSR Pattern (128 o_mb_clk           cycle burst) ===", test_num);

        @(negedge o_mb_clk          );
        i_lfsr_state = LFSR_PATTERN;
        $display("  Driving i_lfsr_state = PATTERN_LFSR ...");

        wait_for_signal_mb("o_lfsr_tx_done", o_lfsr_tx_done, 300);

        @(negedge o_mb_clk          );
        i_lfsr_state = LFSR_IDLE;

        wait_clk_mb(4);

        // ==================================================================
        // PHASE 3b – PER_LANE_IDE check  (i_reversal_en = 0)
        //   Drive i_lfsr_state = LFSR_PER_LANE_IDE and wait for done flag.
        //   Uses same o_mb_clk           domain as LFSR Pattern.
        // ==================================================================
        test_num = 4;
        $display("\n=== PHASE 3b: PER_LANE_IDE mode (i_reversal_en=0) ===");

        @(negedge o_mb_clk          );
        i_lfsr_state = LFSR_PER_LANE_IDE;
        $display("  Driving i_lfsr_state = LFSR_PER_LANE_IDE ...");

        wait_for_signal_mb("o_lfsr_tx_done", o_lfsr_tx_done, 300);

        @(negedge o_mb_clk          );
        i_lfsr_state = LFSR_IDLE;

        wait_clk_mb(4);

        // ==================================================================
        // PHASE 4 – DATA_TRANSFER (i_reversal_en = 0, end-to-end data path)
        //
        //   Stimulus domain  : o_mb_clk            (Mapper, LFSR_TX → mb_clk side of SER)
        //   Output domain    : o_pll_clk (PLL side of MB_SERIALIZER → o_tx_data)
        //
        //   Timing after lfsr_ser_en goes high in o_mb_clk           domain:
        //     Alignment  : up to 4 o_pll_clk cycles  (mb:pll = 1:4 ratio)
        //     CDC        : 2–3 o_pll_clk cycles       (toggle-sync, 3 flops)
        //     DDR SER    : DATA_WIDTH/2 = 16 o_pll_clk cycles
        //     Total min  : ~23 o_pll_clk cycles
        //     wait_clk_pll(50) provides ~2× margin.
        // ==================================================================
        test_num = 5;
        $display("\n=== PHASE %0d: DATA_TRANSFER – end-to-end data path (i_reversal_en=0) ===", test_num);

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

        // Assert on o_mb_clk           negedge — LFSR_TX latches on next o_mb_clk           posedge
        @(negedge o_mb_clk          );
        i_active_state_entered = 1'b1;
        $display("  Asserting i_active_state_entered (o_mb_clk           domain) ...");

        // Mapper (o_mb_clk          ): WIDTH_DEG_ALL completes in 1 o_mb_clk           cycle
        wait_for_signal_mb("o_mapper_ready", o_mapper_ready, 20);

        // Switch to o_pll_clk domain to wait for serialized output.
        // 50 o_pll_clk cycles covers worst-case CDC + DDR path (~23 cycles).
        wait_clk_pll(50);

        if (o_tx_data !== {NUM_LANES{1'b0}})
            $display("  [OK]      o_tx_data is non-zero: 0x%h", o_tx_data);
        else
            $display("  [WARN]    o_tx_data is all zeros – serializer may still loading.");

        if (o_tx_valid !== 1'b0)
            $display("  [OK]      o_tx_valid is active.");
        else
            $display("  [WARN]    o_tx_valid is 0.");

        // Run 20 more o_pll_clk cycles then de-assert on o_mb_clk          
        wait_clk_pll(20);

        @(negedge o_mb_clk          );
        i_active_state_entered = 1'b0;
        i_mapper_en            = 1'b0;
        i_lp_irdy              = 1'b0;
        i_lp_valid             = 1'b0;
        $display("  De-asserting i_active_state_entered – returning to IDLE.");

        wait_clk_mb(4);

        // ==================================================================
        // Enable Lane Reversal
        // ==================================================================
        @(negedge o_mb_clk          );
        i_reversal_en = 1'b1;
        $display("\n==================================================");
        $display("  Asserting i_reversal_en = 1 (Lane Reversal ON)");
        $display("==================================================");
        wait_clk_mb(4);

        // ==================================================================
        // PHASE 5 – LFSR Pattern  (i_reversal_en = 1, 128-cycle burst)
        //   Same stimulus as Phase 3; verifies LFSR output through
        //   reversed lane mapping.
        // ==================================================================
        test_num = 6;
        $display("\n=== PHASE %0d: LFSR Pattern (128 o_mb_clk           cycle burst, i_reversal_en=1) ===", test_num);

        @(negedge o_mb_clk          );
        i_lfsr_state = LFSR_PATTERN;
        $display("  Driving i_lfsr_state = LFSR_PATTERN (reversal enabled) ...");

        wait_for_signal_mb("o_lfsr_tx_done", o_lfsr_tx_done, 300);

        @(negedge o_mb_clk          );
        i_lfsr_state = LFSR_IDLE;

        wait_clk_mb(4);

        // ==================================================================
        // PHASE 6 – PER_LANE_IDE check  (i_reversal_en = 1)
        //   Same as Phase 3b; verifies per-lane IDE through reversed
        //   lane mapping.
        // ==================================================================
        test_num = 7;
        $display("\n=== PHASE %0d: PER_LANE_IDE mode (i_reversal_en=1) ===", test_num);

        @(negedge o_mb_clk          );
        i_lfsr_state = LFSR_PER_LANE_IDE;
        $display("  Driving i_lfsr_state = LFSR_PER_LANE_IDE (reversal enabled) ...");

        wait_for_signal_mb("o_lfsr_tx_done", o_lfsr_tx_done, 300);

        @(negedge o_mb_clk          );
        i_lfsr_state = LFSR_IDLE;

        wait_clk_mb(4);

        // ==================================================================
        // PHASE 7 – DATA_TRANSFER (i_reversal_en = 1)
        //   Same stimulus as Phase 4; verifies end-to-end serialization
        //   through reversed lane mapping.
        // ==================================================================
        test_num = 8;
        $display("\n=== PHASE %0d: DATA_TRANSFER – end-to-end data path (i_reversal_en=1) ===", test_num);

        // Same 512-bit alternating pattern: even bytes = 0xA5, odd bytes = 0x5A
        begin
            integer b;
            for (b = 0; b < N_BYTES; b = b + 1)
                i_raw_data[b*8 +: 8] = (b % 2 == 0) ? 8'hA5 : 8'h5A;
        end

        i_width_deg = WIDTH_DEG_ALL;
        i_mapper_en = 1'b1;
        i_lp_irdy   = 1'b1;
        i_lp_valid  = 1'b1;

        @(negedge o_mb_clk          );
        i_active_state_entered = 1'b1;
        $display("  Asserting i_active_state_entered (o_mb_clk           domain, reversal enabled) ...");

        wait_for_signal_mb("o_mapper_ready", o_mapper_ready, 20);

        wait_clk_pll(50);

        if (o_tx_data !== {NUM_LANES{1'b0}})
            $display("  [OK]      o_tx_data is non-zero: 0x%h  (reversed lanes)", o_tx_data);
        else
            $display("  [WARN]    o_tx_data is all zeros – serializer may still loading.");

        if (o_tx_valid !== 1'b0)
            $display("  [OK]      o_tx_valid is active.");
        else
            $display("  [WARN]    o_tx_valid is 0.");

        wait_clk_pll(20);

        @(negedge o_mb_clk          );
        i_active_state_entered = 1'b0;
        i_mapper_en            = 1'b0;
        i_lp_irdy              = 1'b0;
        i_lp_valid             = 1'b0;
        i_reversal_en          = 1'b0;
        $display("  De-asserting i_active_state_entered & i_reversal_en – returning to IDLE.");

        wait_clk_mb(4);

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
    // Phase 1 : ~3072 × 500 ps  ≈  1.54 µs  (o_pll_clk, both-edge firing)
    // Phase 2 :   ~35 × 2000 ps ≈  70 ns    (o_mb_clk          )
    // Phase 3 :  ~135 × 2000 ps ≈ 270 ns    (o_mb_clk          )  LFSR Pattern
    // Phase 3b:  ~135 × 2000 ps ≈ 270 ns    (o_mb_clk          )  PER_LANE_IDE
    // Phase 4 :  ~100 × 2000 ps ≈ 200 ns    (o_mb_clk          )  DATA_TRANSFER
    // Phase 5 :  ~135 × 2000 ps ≈ 270 ns    (o_mb_clk          )  LFSR Pattern  (reversal)
    // Phase 6 :  ~135 × 2000 ps ≈ 270 ns    (o_mb_clk          )  PER_LANE_IDE  (reversal)
    // Phase 7 :  ~100 × 2000 ps ≈ 200 ns    (o_mb_clk          )  DATA_TRANSFER (reversal)
    // All phases combined ≈ 4 µs
    // Watchdog set to 500 µs = 500_000_000 ps — well beyond any expected run.
    // =========================================================================
    initial begin
        #500_000_000;
        $display("[WATCHDOG] Simulation timed out!");
        $stop;
    end

    // =========================================================================
    // Monitor — split by clock domain
    // =========================================================================

    // o_mb_clk           domain: Mapper / LFSR_TX / VALID_TX status outputs
    always @(posedge o_mb_clk          ) begin
        if (o_valid_done)
            $display("  [MON-MB]  t=%0t  o_valid_done   HIGH", $time);
        if (o_lfsr_tx_done)
            $display("  [MON-MB]  t=%0t  o_lfsr_tx_done HIGH", $time);
        if (o_mapper_ready)
            $display("  [MON-MB]  t=%0t  o_mapper_ready HIGH", $time);
    end

    // o_pll_clk domain: CLK_PATTERN_GEN_TX done flag
    always @(posedge o_pll_clk) begin
        if (o_clk_done)
            $display("  [MON-PLL] t=%0t  o_clk_done     HIGH", $time);
    end

endmodule
