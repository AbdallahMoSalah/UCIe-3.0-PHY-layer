// =============================================================================
// Testbench : TX_TOP_tb
// DUT       : TX_TOP   (rtl/MainBand/unsued/TX_TOP.sv)
//
//  Clock domains  (NOTE: hierarchy is inverted vs the older revision)
//  -------------
//  dut.pll_clk : ROOT clock, generated INSIDE the DUT by MB_PLL whose .en is
//                hardwired to 1'b1 (always on). 2 GHz / 500 ps at speed_sel=00.
//      -> CLK_PATTERN_GEN_TX, PLL_clk port of every serializer.
//
//  lclk        : DUT *output*, produced internally as pll_clk / 16 by ClkDiv
//                (= 125 MHz / 8 ns), then gated by CLK_GATE (enabled by lclk_g)
//                into gated_lclk, the functional clock for Mapper / LFSR_TX /
//                VALID_TX and the mb_clk (slow) side of every serializer.
//      The TB does NOT drive lclk; it observes it as a DUT output.
//
//  NOTE: i_pll_en is now a NO-OP (PLL .en is tied to 1'b1) - pll_clk runs from
//        t=0 regardless. lclk_g MUST be held high or gated_lclk stays X.
//        ClkDiv holds lclk static while i_rst_n=0, so reset is sequenced off
//        dut.pll_clk, not lclk.
//
//        Unlike MB_TX_TOP, TX_TOP does NOT bring the PLL clock / period out to
//        its port list (pll_clk and pll_period are internal). The TB therefore
//        taps them hierarchically (dut.pll_clk, dut.pll_period) so it can sample
//        the serial outputs in the correct domain.
//
//  Sub-module quirks honoured here (these come from the unsued/ variants):
//    * VALID_TX has no IDLE state and resets into VALID_FRAME. To exercise the
//      32-cycle pattern, valid_pattern_en must be HELD high (not pulsed) until
//      O_done; dropping it returns the FSM to VALID_FRAME and clears the counter.
//    * VALID_TX drives a fixed TVLD word (0x0F0F0F0F) and gates the valid lane
//      from the LFSR serializer-enable (ser_en_lfsr_i), not from valid_frame_en.
//    * CLK_PATTERN_GEN_TX has no i_period port; TCKN_P is TCKP_P delayed by a
//      fixed phase_delay (5 units), not period/2. The TB only checks it is
//      defined (not X/Z), it does not assume a 180-degree relationship.
//
//  Test sequence
//  -------------
//  Phase 1 - CLK pattern  (TCKP_P/TCKN_P/TTRK_P, pll_clk domain)
//  Phase 2 - VALID pattern (o_valid_done, lclk domain, valid_pattern_en HELD)
//  Phase 3 - LFSR pattern  (o_lfsr_tx_done, lclk domain, 128-cycle burst)
//  Phase 4 - DATA_TRANSFER (end-to-end: lp_data -> TD_P / TVLD_P)
// =============================================================================

`timescale 1ps/1ps

module TX_TOP_tb;

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

    // Width-degradation code: 3'b011 -> all 16 lanes active (1 lclk cycle)
    localparam WIDTH_DEG_ALL = 3'b011;

    // Number of data-transfer cycles to self-check
    localparam CHECK_CYCLES = 16;

    // =========================================================================
    // Clock & DUT signals
    // =========================================================================
    // lclk is a DUT *output* (pll_clk / 16 via ClkDiv ~ 125 MHz). The TB only
    // observes it; the sole free-running clock is dut.pll_clk (MB_PLL, .en=1).
    logic lclk;

    logic                     i_rst_n;
    logic                     lclk_g;   // CLK_GATE enable - MUST be high to ungate

    // Mapper / adapter interface (lclk domain)
    logic [8*N_BYTES-1:0]     lp_data;
    logic                     lp_irdy;
    logic                     lp_valid;
    logic                     pl_trdy;
    logic                     i_mapper_en;
    logic [2:0]               i_width_deg;

    // LFSR_TX (lclk domain)
    logic [2:0]               i_lfsr_state;
    logic                     i_reversal_en;
    logic                     i_active_state_entered;

    // VALID_TX (lclk domain)
    logic                     i_valid_pattern_en;

    // MB_PLL
    logic                     i_pll_en;
    logic [1:0]               i_pll_speed_sel;

    // CLK_PATTERN_GEN_TX control
    logic                     i_clk_pattern_en;
    logic                     i_clk_embedded_en;

    // Serial / physical outputs
    logic [NUM_LANES-1:0]     TD_P;       // pll_clk domain (serializer PLL side)
    logic                     TVLD_P;     // pll_clk domain
    logic                     TCKP_P;     // pll_clk domain
    logic                     TCKN_P;
    logic                     TTRK_P;

    // Status
    logic                     o_lfsr_tx_done;   // lclk domain
    logic                     o_valid_done;     // lclk domain
    logic                     o_clk_done;       // pll_clk domain

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    TX_TOP #(
        .DATA_WIDTH (DATA_WIDTH),
        .NUM_LANES  (NUM_LANES),
        .N_BYTES    (N_BYTES)
    ) dut (
        .lclk                   (lclk),
        .i_rst_n                (i_rst_n),

        .lp_data                (lp_data),
        .lp_irdy                (lp_irdy),
        .lp_valid               (lp_valid),
        .pl_trdy                (pl_trdy),

        .i_mapper_en            (i_mapper_en),
        .i_width_deg            (i_width_deg),

        .i_lfsr_state           (i_lfsr_state),
        .i_reversal_en          (i_reversal_en),
        .i_active_state_entered (i_active_state_entered),

        .i_valid_pattern_en     (i_valid_pattern_en),

        .i_pll_en               (i_pll_en),
        .i_pll_speed_sel        (i_pll_speed_sel),
        .lclk_g                 (lclk_g),

        .i_clk_pattern_en       (i_clk_pattern_en),
        .i_clk_embedded_en      (i_clk_embedded_en),

        .TD_P                   (TD_P),
        .TVLD_P                 (TVLD_P),
        .TCKP_P                 (TCKP_P),
        .TCKN_P                 (TCKN_P),
        .TTRK_P                 (TTRK_P),

        .o_lfsr_tx_done         (o_lfsr_tx_done),
        .o_valid_done           (o_valid_done),
        .o_clk_done             (o_clk_done)
    );

    // =========================================================================
    // Helpers  (pll_clk tapped hierarchically – TX_TOP keeps it internal)
    // =========================================================================
    task automatic wait_clk_pll(input int n);
        repeat (n) @(posedge dut.pll_clk);
    endtask

    task automatic wait_clk_mb(input int n);
        repeat (n) @(posedge lclk);
    endtask

    task automatic wait_for_signal_pll(
        input  string sig_name,
        ref    logic  sig,
        input  int    timeout_cycles
    );
        int cyc = 0;
        while (!sig && cyc < timeout_cycles) begin
            @(posedge dut.pll_clk);
            cyc++;
        end
        if (cyc >= timeout_cycles)
            $display("  [TIMEOUT] %s not asserted within %0d pll_clk cycles!",
                     sig_name, timeout_cycles);
        else
            $display("  [OK]      %s asserted after %0d pll_clk cycles.",
                     sig_name, cyc);
    endtask

    task automatic wait_for_signal_mb(
        input  string sig_name,
        ref    logic  sig,
        input  int    timeout_cycles
    );
        int cyc = 0;
        while (!sig && cyc < timeout_cycles) begin
            @(posedge lclk);
            cyc++;
        end
        if (cyc >= timeout_cycles)
            $display("  [TIMEOUT] %s not asserted within %0d lclk cycles!",
                     sig_name, timeout_cycles);
        else
            $display("  [OK]      %s asserted after %0d lclk cycles.",
                     sig_name, cyc);
    endtask

    // =========================================================================
    // Independent reference models (NOT copied from the DUT)
    // =========================================================================

    // Mapper reference for WIDTH_DEG_ALL (DEGRADE_LANES_0_TO_15), no reversal.
    // Lane L word = {byte@384+8L, byte@256+8L, byte@128+8L, byte@8L}, byte@8L = LSB.
    function automatic logic [DATA_WIDTH-1:0] map_lane(
        input logic [8*N_BYTES-1:0] d, input int L
    );
        map_lane = { d[384+8*L +: 8], d[256+8*L +: 8],
                     d[128+8*L +: 8], d[  8*L +: 8] };
    endfunction

    // Bit-serial PRBS reference: spec poly X^23+X^21+X^16+X^8+X^5+X^2+1.
    // Feedback f = s[22]^s[20]^s[15]^s[7]^s[4]^s[1]; s' = {s[21:0], f}.
    // Returns 32 consecutive Data_Out bits, LSB = earliest (matches LFSR_TX
    // packing). Written from the polynomial, independent of the DUT prbs32 LUT.
    function automatic logic [31:0] serial_prbs32(input logic [22:0] seed);
        logic [22:0] s;
        logic        f;
        int          k;
        s = seed;
        for (k = 0; k < 32; k++) begin
            f             = s[22]^s[20]^s[15]^s[7]^s[4]^s[1];
            serial_prbs32[k] = f;
            s             = {s[21:0], f};
        end
    endfunction

    // 32-step state advance (same recurrence) - independent of nextstate32 LUT.
    function automatic logic [22:0] serial_next32(input logic [22:0] seed);
        logic [22:0] s;
        logic        f;
        int          k;
        s = seed;
        for (k = 0; k < 32; k++) begin
            f = s[22]^s[20]^s[15]^s[7]^s[4]^s[1];
            s = {s[21:0], f};
        end
        serial_next32 = s;
    endfunction

    // =========================================================================
    // Main test sequence
    // =========================================================================
    integer test_num;

    initial begin
        // ------------------------------------------------------------------
        // Initialise all inputs - DUT held in reset
        // ------------------------------------------------------------------
        i_rst_n                = 1'b0;
        lp_data                = '0;
        lp_irdy                = 1'b0;
        lp_valid               = 1'b0;
        i_mapper_en            = 1'b0;
        i_width_deg            = WIDTH_DEG_ALL;
        i_lfsr_state           = LFSR_IDLE;
        i_reversal_en          = 1'b0;
        i_active_state_entered = 1'b0;
        i_valid_pattern_en     = 1'b0;
        i_pll_en               = 1'b1;    // no-op (PLL .en tied to 1'b1) - kept for port compat
        i_pll_speed_sel        = 2'b00;   // 2 GHz
        i_clk_pattern_en       = 1'b0;
        i_clk_embedded_en      = 1'b0;
        lclk_g                 = 1'b1;    // ungate gated_lclk (else it stays X)

        // ------------------------------------------------------------------
        // Step 1: pll_clk is already free-running (MB_PLL .en=1'b1). Just let
        //         it settle - reset must be sequenced off pll_clk because
        //         ClkDiv holds lclk static while i_rst_n=0.
        // ------------------------------------------------------------------
        repeat (8) @(posedge dut.pll_clk);   // let PLL output stabilise
        $display("\n=== PLL running (speed_sel=00 -> 2 GHz, period=%0.1f ps) ===",
                 dut.pll_period);

        // ------------------------------------------------------------------
        // Step 2: release reset on a pll_clk edge, then wait for ClkDiv to
        //         start toggling lclk (>= one lclk period = 16 pll cycles)
        //         before any mb-domain wait.
        // ------------------------------------------------------------------
        @(negedge dut.pll_clk);
        i_rst_n = 1'b1;
        $display("=== RESET released (pll_clk negedge) ===\n");
        repeat (20) @(posedge dut.pll_clk);  // let lclk come alive
        wait_clk_mb(4);

        // ==================================================================
        // PHASE 1 - Clock pattern generation (pll_clk domain)
        // ==================================================================
        test_num = 1;
        $display("=== PHASE %0d: CLK pattern generation ===", test_num);

        @(negedge dut.pll_clk);
        i_clk_pattern_en = 1'b1;
        $display("  Asserting i_clk_pattern_en ...");

        wait_for_signal_pll("o_clk_done", o_clk_done, 7000);

        @(negedge dut.pll_clk);
        i_clk_pattern_en = 1'b0;

        if ($isunknown(TCKP_P))
            $display("  [FAIL]    TCKP_P is X/Z after clock burst.");
        else
            $display("  [OK]      TCKP_P = %b after burst.", TCKP_P);

        #(10);   // allow the fixed phase_delay on TCKN_P to resolve
        if ($isunknown(TCKN_P))
            $display("  [FAIL]    TCKN_P is X/Z.");
        else
            $display("  [OK]      TCKN_P = %b (fixed phase_delay vs TCKP_P).", TCKN_P);

        wait_clk_pll(4);

        // ==================================================================
        // PHASE 2 - VALID pattern (lclk domain, valid_pattern_en HELD)
        // ==================================================================
        test_num = 2;
        $display("\n=== PHASE %0d: VALID pattern ===", test_num);

        @(negedge lclk);
        i_valid_pattern_en = 1'b1;     // HELD high (unsued VALID_TX needs this)
        $display("  Holding i_valid_pattern_en (no IDLE state in unsued VALID_TX) ...");

        wait_for_signal_mb("o_valid_done", o_valid_done, 100);

        @(negedge lclk);
        i_valid_pattern_en = 1'b0;
        $display("  TVLD word = 0x%h", dut.valid_word);
        wait_clk_mb(4);

        // ==================================================================
        // PHASE 3 - LFSR pattern (lclk domain, 128-cycle burst)
        // ==================================================================
        test_num = 3;
        $display("\n=== PHASE %0d: LFSR pattern (128 lclk cycle burst) ===", test_num);

        @(negedge lclk);
        i_lfsr_state = LFSR_PATTERN;
        $display("  Driving i_lfsr_state = PATTERN_LFSR ...");

        wait_for_signal_mb("o_lfsr_tx_done", o_lfsr_tx_done, 300);

        @(negedge lclk);
        i_lfsr_state = LFSR_IDLE;
        wait_clk_mb(4);

        // ==================================================================
        // PHASE 4 - DATA_TRANSFER: mapping + scrambling SELF-CHECK
        //
        //   Every active data cycle (no reversal, WIDTH_DEG_ALL) the RTL must
        //   satisfy:
        //     mapper_lane[L] = slice(lp_data, L)                      (mapping)
        //     lfsr_lane[i]   = PRBS32(tx_lfsr[i%8]) ^ mapper_lane[i]   (scramble)
        //     tx_lfsr(t)     = advance32(tx_lfsr(t-1))                 (LFSR step)
        //
        //   lfsr_lane / tx_lfsr / o_ser_en_lfsr are registered together, so a
        //   stable negedge sample of lfsr_lane corresponds to the tx_lfsr and
        //   mapper_lane present on the PREVIOUS negedge. Live DUT state is fed
        //   through the independent serial reference models above.
        // ==================================================================
        test_num = 4;
        $display("\n=== PHASE %0d: DATA_TRANSFER - mapping + scrambling check ===", test_num);

        // Known input: even bytes = 0xA5, odd bytes = 0x5A
        begin
            integer b;
            for (b = 0; b < N_BYTES; b = b + 1)
                lp_data[b*8 +: 8] = (b % 2 == 0) ? 8'hA5 : 8'h5A;
        end
        i_width_deg = WIDTH_DEG_ALL;

        // Stream data and enter DATA_TRANSFER
        i_mapper_en = 1'b1;
        lp_irdy     = 1'b1;
        lp_valid    = 1'b1;
        @(negedge lclk);
        i_active_state_entered = 1'b1;
        $display("  Streaming lp_data, asserting i_active_state_entered ...");

        // Wait until the LFSR is actively scrambling (o_ser_en_lfsr high)
        begin
            automatic int g = 0;
            while (!dut.lfsr_ser_en && g < 30) begin @(negedge lclk); g++; end
        end

        // --- 4a. MAPPING: mapper_lane == documented slice of lp_data --------
        begin
            automatic int err_map = 0;
            for (int L = 0; L < NUM_LANES; L++)
                if (dut.mapper_lane[L] !== map_lane(lp_data, L)) begin
                    err_map++;
                    $display("  [FAIL-MAP] lane %0d: got 0x%08h exp 0x%08h",
                             L, dut.mapper_lane[L], map_lane(lp_data, L));
                end
            if (err_map == 0)
                $display("  [OK]      MAPPING : all 16 mapper lanes match the lp_data slicing.");
            else
                $display("  [FAIL]    MAPPING : %0d/16 lanes mismatched.", err_map);
        end

        // --- 4b/4c. SCRAMBLE XOR + LFSR progression over a window -----------
        begin
            logic [22:0] s_prev [0:7];
            logic [31:0] m_prev [0:15];
            logic [31:0] prbs_w;
            automatic int err_scr = 0, err_prg = 0, n_chk = 0;

            // prime references from live DUT state
            @(negedge lclk);
            for (int i = 0; i < 8;  i++) s_prev[i] = dut.u_lfsr_tx.tx_lfsr[i];
            for (int L = 0; L < 16; L++) m_prev[L] = dut.mapper_lane[L];

            repeat (CHECK_CYCLES) begin
                @(negedge lclk);
                if (dut.lfsr_ser_en && !$isunknown(dut.lfsr_lane[0])) begin
                    n_chk++;
                    for (int i = 0; i < 8; i++) begin
                        prbs_w = serial_prbs32(s_prev[i]);
                        if (dut.lfsr_lane[i]   !== (prbs_w ^ m_prev[i]))   err_scr++;
                        if (dut.lfsr_lane[8+i] !== (prbs_w ^ m_prev[8+i])) err_scr++;
                        if (dut.u_lfsr_tx.tx_lfsr[i] !== serial_next32(s_prev[i])) err_prg++;
                    end
                end
                for (int i = 0; i < 8;  i++) s_prev[i] = dut.u_lfsr_tx.tx_lfsr[i];
                for (int L = 0; L < 16; L++) m_prev[L] = dut.mapper_lane[L];
            end

            if (n_chk == 0)
                $display("  [WARN]    SCRAMBLE: no active scrambling cycles observed.");
            else if (err_scr == 0)
                $display("  [OK]      SCRAMBLE: %0d cycles - lfsr_lane == serialPRBS(LFSR) XOR mapper_lane (all 16 lanes).", n_chk);
            else
                $display("  [FAIL]    SCRAMBLE: %0d mismatches over %0d cycles.", err_scr, n_chk);

            if (n_chk > 0) begin
                if (err_prg == 0)
                    $display("  [OK]      LFSR    : state advances by the spec 32-step recurrence each cycle.");
                else
                    $display("  [FAIL]    LFSR    : %0d progression mismatches.", err_prg);
            end
        end

        // --- 4d. Serializer carries the data (activity over a window) -------
        wait_clk_pll(30);
        begin
            logic td_seen, tvld_hi, tvld_lo;
            td_seen = 1'b0; tvld_hi = 1'b0; tvld_lo = 1'b0;
            repeat (40) begin
                @(posedge dut.pll_clk);
                if (!$isunknown(TD_P) && TD_P !== {NUM_LANES{1'b0}}) td_seen = 1'b1;
                if (TVLD_P === 1'b1) tvld_hi = 1'b1;
                if (TVLD_P === 1'b0) tvld_lo = 1'b1;
            end
            if (td_seen) $display("  [OK]      TD_P    : serialized data active (last 0x%h).", TD_P);
            else         $display("  [FAIL]    TD_P    : never left zero over the window.");
            if (tvld_hi && tvld_lo) $display("  [OK]      TVLD_P  : toggling (0x0F0F0F0F serialized).");
            else                    $display("  [WARN]    TVLD_P  : did not toggle (hi=%b lo=%b).", tvld_hi, tvld_lo);
        end

        @(negedge lclk);
        i_active_state_entered = 1'b0;
        i_mapper_en            = 1'b0;
        lp_irdy                = 1'b0;
        lp_valid               = 1'b0;
        $display("  De-asserting i_active_state_entered - returning to IDLE.");
        wait_clk_mb(4);

        // ==================================================================
        // Done
        // ==================================================================
        $display("\n=================================================");
        $display("  TX_TOP testbench COMPLETE - all phases done.");
        $display("=================================================\n");
        $stop;
    end

    // =========================================================================
    // Timeout watchdog (Phase 1 dominates at ~1.5 us; 500 us is well clear)
    // =========================================================================
    initial begin
        #500_000_000;
        $display("[WATCHDOG] Simulation timed out!");
        $stop;
    end

    // =========================================================================
    // Monitor - split by clock domain
    // =========================================================================
    always @(posedge lclk) begin
        if (o_valid_done)   $display("  [MON-MB]  t=%0t  o_valid_done   HIGH", $time);
        if (o_lfsr_tx_done) $display("  [MON-MB]  t=%0t  o_lfsr_tx_done HIGH", $time);
        if (pl_trdy)        $display("  [MON-MB]  t=%0t  pl_trdy        HIGH", $time);
    end

    always @(posedge dut.pll_clk) begin
        if (o_clk_done) $display("  [MON-PLL] t=%0t  o_clk_done     HIGH", $time);
    end

endmodule
