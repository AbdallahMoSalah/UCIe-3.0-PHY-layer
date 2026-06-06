// =============================================================================
// Testbench : unit_lfsr_cmp_tb
// Purpose   : Verify the parallel leap-by-32 scrambler (LFSR_TX) reproduces the
//             bit-serial reference (lfsr_serial), word-for-word, for several
//             consecutive 32-bit windows from the same lane-0 seed.
//
// Reference  : UCIe 3.0 sec 4.4.1, written G(X)=X^23+X^21+X^16+X^8+X^5+X^2+1.
//             unit_lfsr_serial implements G(X) exactly (the spec text); unit_lfsr_tx is a
//             32-step leap of the same recurrence. Both pack the window LSB-first
//             (bit k = the k-th/earliest scrambling bit), so:
//                 unit_lfsr_tx o_lane[0]  ==  unit_lfsr_serial agg_word
//             for window 0 (= 0x3158E25C for seed 0) and every window after.
// =============================================================================

`timescale 1ns/1ps

module unit_lfsr_cmp_tb;

    // =========================================================================
    // Parameters / encodings
    // =========================================================================
    localparam CLK_PERIOD = 2;
    localparam NWIN       = 4;     // number of 32-bit windows to compare

    localparam [2:0] IDLE                  = 3'b000;
    localparam [2:0] PATTERN_LFSR          = 3'b010;
    localparam [2:0] DEGRADE_LANES_0_TO_15 = 3'b011;

    // =========================================================================
    // Shared clock / reset
    // =========================================================================
    logic clk;
    logic rst_n;

    // -------------------------------------------------------------------------
    // Serial DUT (reference)
    // -------------------------------------------------------------------------
    logic        s_shift_en, s_seed_load, s_mode, s_data_in;
    logic [3:0]  s_lane_num;
    logic        s_data_out;
    logic [31:0] s_agg_word;
    logic        s_agg_valid;

    // -------------------------------------------------------------------------
    // Parallel DUT (LFSR_TX)
    // -------------------------------------------------------------------------
    logic [2:0]  p_state;
    logic        p_scramble_en;
    logic [2:0]  p_width_deg;
    logic        p_reversal_en;
    logic        p_active_entered;
    logic [31:0] p_lane_in  [0:15];
    logic [31:0] p_lane_out [0:15];
    logic        p_ser_en;
    logic        p_tx_done;
    logic        p_valid_frame;

    // =========================================================================
    // DUT instantiations
    // =========================================================================
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

    unit_lfsr_tx DUT_P (
        .i_clk                  (clk),
        .i_rst_n                (rst_n),
        .i_state                (p_state),
        .i_scramble_en          (p_scramble_en),
        .i_width_deg_lfsr       (p_width_deg),
        .i_reversal_en          (p_reversal_en),
        .i_active_state_entered (p_active_entered),
        .i_lane                 (p_lane_in),
        .o_lane                 (p_lane_out),
        .o_ser_en_lfsr          (p_ser_en),
        .o_Lfsr_tx_done         (p_tx_done),
        .o_valid_frame_en       (p_valid_frame)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // =========================================================================
    // Capture storage
    // =========================================================================
    logic [31:0] serial_words [0:NWIN-1];
    logic [31:0] par_words    [0:NWIN-1];
    integer      w, k, mism;

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
        p_state          = IDLE;
        p_scramble_en    = 1'b0;
        p_width_deg      = DEGRADE_LANES_0_TO_15;
        p_reversal_en    = 1'b0;
        p_active_entered = 1'b0;
        for (k = 0; k < 16; k = k + 1) p_lane_in[k] = 32'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);   // unit_lfsr_tx now holds seed in tx_lfsr[]; frozen in IDLE

        $display("===========================================================");
        $display("  lfsr_serial (ref)  vs  LFSR_TX (leap-32)  -- lane 0");
        $display("  seed = 23'h1DBFBC, %0d consecutive 32-bit windows", NWIN);
        $display("===========================================================");

        // =====================================================================
        // SERIAL: capture NWIN consecutive agg_word windows (pattern-gen)
        // =====================================================================
        @(negedge clk);
        s_lane_num  = 4'd0;
        s_mode      = 1'b1;
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
        // PARALLEL: capture NWIN consecutive o_lane[0] words in PATTERN_LFSR
        // =====================================================================
        @(negedge clk);
        p_state = PATTERN_LFSR;
        w = 0;
        while (w < NWIN) begin
            @(negedge clk);
            if (p_ser_en) begin
                par_words[w] = p_lane_out[0];
                w = w + 1;
            end
        end
        p_state = IDLE;

        // =====================================================================
        // COMPARE
        // =====================================================================
        $display("\n  win |  serial agg_word | unit_lfsr_tx o_lane[0] | result");
        $display("  ----+------------------+-------------------+-------");
        mism = 0;
        for (w = 0; w < NWIN; w = w + 1) begin
            if (serial_words[w] === par_words[w])
                $display("   %0d  |    0x%08h    |     0x%08h    |  MATCH",
                         w, serial_words[w], par_words[w]);
            else begin
                $display("   %0d  |    0x%08h    |     0x%08h    |  MISMATCH",
                         w, serial_words[w], par_words[w]);
                mism = mism + 1;
            end
        end

        $display("\n===========================================================");
        if (mism == 0)
            $display("  RESULT: PASS  (all %0d windows match, incl. window0=0x%08h)",
                     NWIN, serial_words[0]);
        else
            $display("  RESULT: FAIL  (%0d/%0d windows differ)", mism, NWIN);
        $display("===========================================================");

        $stop;
    end

endmodule