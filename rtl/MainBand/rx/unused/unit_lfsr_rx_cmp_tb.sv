// =============================================================================
// Testbench : unit_lfsr_rx_cmp_tb
// Purpose   : Verify the SPEC-FIXED RX scrambler (unsued/LFSR_RX.sv) against the
//             bit-serial reference (lfsr_serial), in the same direction/style as
//             lfsr_cmp_tb (which checks LFSR_TX). Three checks:
//
//   TEST 1 - MAPPING / PATTERN  : in PATTERN_LFSR the RX reference word
//             o_final_gene[0] must equal unit_lfsr_serial agg_word, word-for-word,
//             for NWIN consecutive 32-bit windows from lane-0 seed
//             (window0 = 0x3158E25C). This proves the broken
//             {state,o_lane_23} packing is gone and prbs32() is correct.
//
//   TEST 2 - PER-LANE MAPPING   : in PATTERN_LFSR with DEGRADE_LANES_0_TO_15,
//             each lane i (0..7) must emit prbs32(SEED[i]) (golden constants
//             below, BM-verified), and lanes 8..15 must mirror lanes 0..7.
//
//   TEST 3 - SCRAMBLE/DESCRAMBLE: capture the PRBS scrambling stream P[] in
//             PATTERN, then in DATA_TRANSFER feed scrambled data
//             (P[w] ^ ORIG[w]) and confirm the RX descrambles back to ORIG[w].
//             This is the round-trip the link relies on.
//
// Reference  : UCIe 3.0 sec 4.4.1, written G(X)=X^23+X^21+X^16+X^8+X^5+X^2+1.
// =============================================================================

`timescale 1ns/1ps

module unit_lfsr_rx_cmp_tb;

    // =========================================================================
    // Parameters / encodings
    // =========================================================================
    localparam CLK_PERIOD = 2;
    localparam WIDTH      = 32;
    localparam NWIN       = 8;     // windows compared vs serial reference (lane 0)
    localparam NCAP       = 16;    // PRBS windows captured for the descramble test

    localparam [2:0] IDLE                  = 3'b000;
    localparam [2:0] CLEAR_LFSR            = 3'b001;
    localparam [2:0] PATTERN_LFSR          = 3'b010;
    localparam [2:0] PER_LANE_IDE          = 3'b011;
    localparam [2:0] DATA_TRANSFER         = 3'b100;
    localparam [2:0] DEGRADE_LANES_0_TO_15 = 3'b011;

    // Golden window-0 word per lane = prbs32(SEED[i]) (verified vs lfsr_serial)
    localparam logic [31:0] EXP_W0 [0:7] = '{
        32'h3158E25C,  // lane 0  seed 0x1DBFBC
        32'h4374E38D,  // lane 1  seed 0x0607BB
        32'h48B153CE,  // lane 2  seed 0x1EC760
        32'h0BC5B043,  // lane 3  seed 0x18C0DB
        32'h52C2DF60,  // lane 4  seed 0x010F12
        32'h59076F23,  // lane 5  seed 0x19CFC9
        32'h2B2B6EF2,  // lane 6  seed 0x0277CE
        32'h722C01D1   // lane 7  seed 0x1BB807
    };

    // =========================================================================
    // Shared clock / reset
    // =========================================================================
    logic clk;
    logic rst_n;

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Serial reference DUT
    // -------------------------------------------------------------------------
    logic        s_shift_en, s_seed_load, s_mode, s_data_in;
    logic [3:0]  s_lane_num;
    logic        s_data_out;
    logic [31:0] s_agg_word;
    logic        s_agg_valid;

    unit_lfsr_serial DUT_S (
        .clk       (clk),
        .rst_n     (rst_n),
        .shift_en  (s_shift_en),
        .seed_load (s_seed_load),
        .lane_num  (s_lane_num),
        .mode      (s_mode),
        .data_in   (s_data_in),
        .data_out  (s_data_out),
        .agg_word  (s_agg_word),
        .agg_valid (s_agg_valid)
    );

    // -------------------------------------------------------------------------
    // RX DUT (the fixed copy)
    // -------------------------------------------------------------------------
    logic [2:0]       r_state;
    logic [2:0]       r_width_deg;
    logic             r_active_entered;
    logic             r_descramble_en;
    logic             r_enable_buffer;
    logic [WIDTH-1:0] r_data_in  [0:15];
    logic [WIDTH-1:0] r_data_by  [0:15];
    logic [WIDTH-1:0] r_final    [0:15];
    logic             r_comp_en;

    unit_lfsr_rx #(.WIDTH(WIDTH)) DUT_R (
        .i_clk                  (clk),
        .i_rst_n                (rst_n),
        .i_state                (r_state),
        .i_width_deg_lfsr       (r_width_deg),
        .i_active_state_entered (r_active_entered),
        .i_descramble_en        (r_descramble_en),
        .i_enable_buffer        (r_enable_buffer),
        .i_data_in              (r_data_in),
        .o_Data_by              (r_data_by),
        .o_final_gene           (r_final),
        .pattern_comp_en        (r_comp_en)
    );

    // =========================================================================
    // Capture storage
    // =========================================================================
    logic [31:0] serial_words [0:NWIN-1];
    logic [31:0] rx_words     [0:NWIN-1];
    logic [31:0] P            [0:NCAP-1];   // PRBS scrambling stream (lane 0)
    logic [31:0] ORIG         [0:NCAP-1];   // plaintext fed through descrambler
    logic [31:0] OUT          [0:NCAP-1];   // RX descrambled output (lane 0)
    integer      w, k, mism, fails;

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        // ---- init & reset ----
        rst_n            = 1'b0;
        s_shift_en       = 1'b0;
        s_seed_load      = 1'b0;
        s_lane_num       = 4'd0;
        s_mode           = 1'b0;
        s_data_in        = 1'b0;
        r_state          = IDLE;
        r_width_deg      = DEGRADE_LANES_0_TO_15;
        r_active_entered = 1'b0;
        r_descramble_en  = 1'b0;
        r_enable_buffer  = 1'b1;
        for (k = 0; k < 16; k = k + 1) r_data_in[k] = 32'b0;
        fails = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // SERIAL reference: capture NWIN consecutive agg_word windows (lane 0)
        // =====================================================================
        @(negedge clk);
        s_lane_num  = 4'd0;
        s_mode      = 1'b1;       // pattern-gen
        s_data_in   = 1'b0;
        s_seed_load = 1'b1;
        s_shift_en  = 1'b0;
        @(negedge clk);
        s_seed_load = 1'b0;
        s_shift_en  = 1'b1;

        w = 0;
        while (w < NWIN) begin
            @(negedge clk);
            if (s_agg_valid) begin
                serial_words[w] = s_agg_word;
                w = w + 1;
            end
        end
        s_shift_en = 1'b0;

        // =====================================================================
        // TEST 1+2: RX PATTERN_LFSR — capture NCAP windows (all lanes), and
        //           keep lane-0 windows for the serial compare.
        // =====================================================================
        @(negedge clk);
        r_state         = PATTERN_LFSR;
        r_enable_buffer = 1'b1;

        // wait for the first generated word
        @(negedge clk);
        while (!r_comp_en) @(negedge clk);

        // first per-lane snapshot (window 0 for every lane) for TEST 2
        $display("===========================================================");
        $display("  TEST 2 : per-lane window-0 mapping (DEGRADE_LANES_0_TO_15)");
        $display("  lane | o_final_gene |  expected   | result");
        $display("  -----+--------------+-------------+-------");
        for (k = 0; k < 8; k = k + 1) begin
            if (r_final[k] !== EXP_W0[k]) fails = fails + 1;
            $display("   %0d   |  0x%08h  | 0x%08h | %s",
                     k, r_final[k], EXP_W0[k],
                     (r_final[k] === EXP_W0[k]) ? "MATCH" : "MISMATCH");
        end
        // lanes 8..15 must mirror 0..7
        for (k = 0; k < 8; k = k + 1) begin
            if (r_final[k+8] !== r_final[k]) begin
                fails = fails + 1;
                $display("   lane %0d mirror FAIL: 0x%08h != lane %0d 0x%08h",
                         k+8, r_final[k+8], k, r_final[k]);
            end
        end
        $display("  (lanes 8..15 mirror lanes 0..7: %s)",
                 (fails == 0) ? "OK" : "see above");

        // now stream NCAP consecutive lane-0 windows (window0 already present)
        k = 0;
        P[0] = r_final[0];
        for (k = 1; k < NCAP; k = k + 1) begin
            @(negedge clk);
            P[k] = r_final[0];
        end
        for (w = 0; w < NWIN; w = w + 1) rx_words[w] = P[w];

        r_state = IDLE;
        @(negedge clk);

        // ---- TEST 1 compare ----
        $display("\n===========================================================");
        $display("  TEST 1 : RX o_final_gene[0]  vs  unit_lfsr_serial agg_word");
        $display("  win |  serial (ref)  |  RX o_final_gene[0] | result");
        $display("  ----+----------------+--------------------+-------");
        mism = 0;
        for (w = 0; w < NWIN; w = w + 1) begin
            if (serial_words[w] !== rx_words[w]) mism = mism + 1;
            $display("   %0d  |   0x%08h   |     0x%08h     | %s",
                     w, serial_words[w], rx_words[w],
                     (serial_words[w] === rx_words[w]) ? "MATCH" : "MISMATCH");
        end
        if (mism != 0) fails = fails + mism;

        // =====================================================================
        // TEST 3: scramble/descramble round-trip on lane 0.
        //   Re-seed via CLEAR_LFSR so the DATA_TRANSFER state starts at SEED,
        //   exactly the alignment of the captured P[] stream.
        // =====================================================================
        @(negedge clk);
        r_state = CLEAR_LFSR;            // reload seeds
        @(negedge clk);
        r_state = IDLE;
        @(negedge clk);

        // choose recognizable plaintext, build scrambled input = P[w] ^ ORIG[w]
        for (k = 0; k < NCAP; k = k + 1) ORIG[k] = 32'hCAFE_0000 + k;

        // enter DATA_TRANSFER via active-state pulse
        r_active_entered = 1'b1;
        r_descramble_en  = 1'b1;
        r_enable_buffer  = 1'b1;
        @(posedge clk);                 // IDLE -> DATA_TRANSFER (state still SEED)

        for (k = 0; k < NCAP; k = k + 1) begin
            @(negedge clk);
            r_data_in[0] = P[k] ^ ORIG[k];   // scrambled word for cycle k
            @(posedge clk);
            OUT[k] = r_data_by[0];           // o_Data_by lags temp by 1 cycle
        end
        r_active_entered = 1'b0;
        r_descramble_en  = 1'b0;
        r_state          = IDLE;

        // Output pipeline is 2 deep (i_data_in -> temp_Data_by -> o_Data_by),
        // so o_Data_by sampled after DATA cycle k holds the plaintext ORIG[k-2].
        $display("\n===========================================================");
        $display("  TEST 3 : descramble round-trip (lane 0, pipeline latency = 2)");
        $display("  cyc | scrambled in | RX o_Data_by | expected ORIG | result");
        $display("  ----+--------------+--------------+---------------+-------");
        mism = 0;
        for (k = 2; k < NCAP; k = k + 1) begin
            if (OUT[k] !== ORIG[k-2]) mism = mism + 1;
            $display("   %0d  |  0x%08h  |  0x%08h  |  0x%08h   | %s",
                     k, (P[k-2] ^ ORIG[k-2]), OUT[k], ORIG[k-2],
                     (OUT[k] === ORIG[k-2]) ? "MATCH" : "MISMATCH");
        end
        if (mism != 0) fails = fails + mism;

        // =====================================================================
        // SUMMARY
        // =====================================================================
        $display("\n===========================================================");
        if (fails == 0)
            $display("  RESULT: PASS  (mapping + per-lane + descramble all OK)");
        else
            $display("  RESULT: FAIL  (%0d mismatch(es))", fails);
        $display("===========================================================");

        $stop;
    end

endmodule