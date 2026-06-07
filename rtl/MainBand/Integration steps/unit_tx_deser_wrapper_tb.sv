`timescale 1ns/1ps
// =============================================================================
// Testbench : unit_tx_deser_wrapper_tb
// DUT       : unit_tx_deser_wrapper  (rtl/MainBand/Integration steps/)
//
//  Goal
//  ----
//  Close a SER/DES loop and prove the RX deserializer chain recovers, bit-for-
//  bit, the words that unit_tx_top fed into its serializers:
//
//        "data after deser"  (o_par_data[L])  ==  "data before ser" (o_ser_in[L])
//
//  o_ser_in[L] is the scrambled lane word unit_tx_top loads into MB serializer L
//  (tapped from u_tx_top.lfsr_lane[L]); o_par_data[L] is the word recovered by
//  unit_data_deserializer_s2 L. The TX scrambler makes every lane word change
//  each cycle, so a constant lp_data still exercises a fresh 32-bit word/frame.
//
//  Why a free-running queue scoreboard works (frame-lock proof)
//  -----------------------------------------------------------
//   * Data + valid serializers load on the SAME mb_clk edge with identical DDR
//     phase, so their serial bit positions are aligned.
//   * The valid lane is a seamless period-8 "11110000" stream (every frame is
//     0x0F0F0F0F). The 32-bit valid window first equals 0x0F0F0F0F only after a
//     full 32 bits are shifted in (the low bits stay 0 during fill) -> the FIRST
//     match lands on the TRUE 32-bit frame boundary, where the data window holds
//     a clean word W0.
//   * On a match, unit_valid_deserializer_s2 clears its low 30 bits. That
//     suppresses the would-be sub-matches at +8/+16/+24 bits and only re-arms at
//     +32 bits -> detection locks to one pulse per 32-bit frame.
//   * Hence the data FIFO is written exactly once per frame, capturing W0, W1,
//     W2, ... in order. Enqueuing o_ser_in on every serializer load and
//     dequeuing on every o_data_valid therefore self-aligns 1:1, with the
//     queue simply absorbing the (fixed) pipeline + async-FIFO latency.
//
//  Run : make run CONFIG=integration_tx_deser TOP=unit_tx_deser_wrapper_tb
// =============================================================================

module unit_tx_deser_wrapper_tb;

    // ---------------------------------------------------------------- params
    localparam int DATA_WIDTH = 32;
    localparam int NUM_LANES  = 16;
    localparam int N_BYTES    = 64;
    localparam int BUSW       = NUM_LANES * DATA_WIDTH;   // 512: 16 lanes packed

    // unit_lfsr_tx state codes
    localparam logic [2:0] LFSR_IDLE     = 3'b000;
    localparam logic [2:0] LFSR_DATA     = 3'b100;
    // width-degradation: all 16 lanes active in one lclk cycle
    localparam logic [2:0] WIDTH_DEG_ALL = 3'b011;

    localparam int WINDOW     = 20;   // lclk cycles streamed per data pattern
    localparam int N_PATTERNS = 8;    // number of distinct lp_data patterns

    // ----------------------------------------------------------------- DUT IO
    logic                     i_rst_n;
    logic [8*N_BYTES-1:0]     lp_data;
    logic                     lp_irdy, lp_valid, pl_trdy;
    logic                     i_mapper_en;
    logic [2:0]               i_width_deg;
    logic [2:0]               i_lfsr_state;
    logic                     i_reversal_en;
    logic                     i_valid_pattern_en;
    logic                     i_pll_en;
    logic [1:0]               i_pll_speed_sel;
    logic                     lclk_g;
    logic                     i_clk_pattern_en, i_clk_embedded_en;

    logic                     lclk, o_pll_clk, o_rx_pll_clk;
    logic                     o_lfsr_tx_done, o_valid_done, o_clk_done;
    logic [NUM_LANES-1:0]     TD_P;
    logic                     TVLD_P, TCKP_P, TCKN_P, TTRK_P;
    logic [DATA_WIDTH-1:0]    o_ser_in   [0:NUM_LANES-1];
    logic                     o_ser_en;
    logic [DATA_WIDTH-1:0]    o_par_data [0:NUM_LANES-1];
    logic                     o_data_valid;
    logic [DATA_WIDTH-1:0]    o_valid_shift_reg;
    logic                     o_valid_frame_pulse;

    // ---------------------------------------------------------------- DUT
    unit_tx_deser_wrapper #(
        .DATA_WIDTH    (DATA_WIDTH),
        .NUM_LANES     (NUM_LANES),
        .N_BYTES       (N_BYTES),
        .VALID_PATTERN (32'h0F0F0F0F),
        .PLL_PERIOD_NS (0.5)               // must match i_pll_speed_sel = 00
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
        .o_ser_in           (o_ser_in),
        .o_ser_en           (o_ser_en),
        .o_par_data         (o_par_data),
        .o_data_valid       (o_data_valid),
        .o_valid_shift_reg  (o_valid_shift_reg),
        .o_valid_frame_pulse(o_valid_frame_pulse)
    );

    // =========================================================================
    // Scoreboard : queue of "before-ser" frames (16 lanes packed per entry)
    // =========================================================================
    logic [BUSW-1:0] sb_q [$];

    int  pass_count, fail_count, frame_count, enq_count, underflow_count;
    bit  scoreboard_en;

    // Pack the 16 current serializer-input words into one BUSW-bit frame.
    function automatic logic [BUSW-1:0] pack_ser_in();
        logic [BUSW-1:0] w;
        for (int L = 0; L < NUM_LANES; L++)
            w[L*DATA_WIDTH +: DATA_WIDTH] = o_ser_in[L];
        return w;
    endfunction

    // One scoreboard step per mb_clk edge: compare a recovered frame against
    // the oldest pending serializer-input frame, then enqueue this edge's load.
    // Order is compare-THEN-enqueue so a same-edge load can never satisfy its
    // own (much later) capture.
    always @(posedge lclk) begin
        if (i_rst_n && scoreboard_en) begin
            // ---- compare (dequeue) -------------------------------------
            if (o_data_valid) begin
                logic [BUSW-1:0] exp;
                int              lane_err;
                if (sb_q.size() == 0) begin
                    underflow_count++;
                    $display("  [ANOMALY] t=%0t  o_data_valid with empty scoreboard", $time);
                end else begin
                    exp      = sb_q.pop_front();
                    lane_err = 0;
                    frame_count++;
                    for (int L = 0; L < NUM_LANES; L++) begin
                        if (o_par_data[L] !== exp[L*DATA_WIDTH +: DATA_WIDTH]) begin
                            lane_err++;
                            if (lane_err <= 4)
                                $display("  [FAIL] t=%0t frame %0d lane %0d  after_deser=0x%08h  before_ser=0x%08h",
                                         $time, frame_count, L,
                                         o_par_data[L], exp[L*DATA_WIDTH +: DATA_WIDTH]);
                        end
                    end
                    if (lane_err == 0) pass_count++;
                    else begin
                        fail_count++;
                        $display("  [FAIL] t=%0t frame %0d : %0d/%0d lanes mismatched",
                                 $time, frame_count, lane_err, NUM_LANES);
                    end
                end
            end
            // ---- enqueue this edge's serializer load -------------------
            if (o_ser_en) begin
                sb_q.push_back(pack_ser_in());
                enq_count++;
            end
        end
    end

    // =========================================================================
    // Stimulus helpers
    // =========================================================================
    task automatic wait_pll(input int n); repeat (n) @(posedge o_pll_clk); endtask
    task automatic wait_mb (input int n); repeat (n) @(posedge lclk);      endtask

    // Fill lp_data with a labelled pattern (each "case").
    task automatic set_pattern(input int idx, output string name);
        int b;
        case (idx)
            0: begin name = "checker 0xA5/0x5A";
                     for (b=0;b<N_BYTES;b++) lp_data[b*8 +: 8] = (b%2==0)? 8'hA5 : 8'h5A; end
            1: begin name = "all zeros        ";
                     lp_data = '0; end
            2: begin name = "all ones         ";
                     lp_data = '1; end
            3: begin name = "byte ramp (b)    ";
                     for (b=0;b<N_BYTES;b++) lp_data[b*8 +: 8] = b[7:0]; end
            4: begin name = "0xDEADBEEF tile  ";
                     for (b=0;b<N_BYTES;b++) lp_data[b*8 +: 8] = (32'hDEADBEEF >> ((b%4)*8)) & 8'hFF; end
            5: begin name = "0xCAFEBABE tile  ";
                     for (b=0;b<N_BYTES;b++) lp_data[b*8 +: 8] = (32'hCAFEBABE >> ((b%4)*8)) & 8'hFF; end
            6: begin name = "random bytes     ";
                     for (b=0;b<N_BYTES;b++) lp_data[b*8 +: 8] = $random; end
            7: begin name = "0x0F0F0F0F tile  ";   // data == valid pattern (stress)
                     for (b=0;b<N_BYTES;b++) lp_data[b*8 +: 8] = (b%2==0)? 8'h0F : 8'h0F; end
            default: lp_data = '0;
        endcase
    endtask

    // =========================================================================
    // Main sequence
    // =========================================================================
    initial begin
        string pname;

        // ---- init (held in reset) -------------------------------------
        i_rst_n            = 1'b0;
        lp_data            = '0;
        lp_irdy            = 1'b0;
        lp_valid           = 1'b0;
        i_mapper_en        = 1'b0;
        i_width_deg        = WIDTH_DEG_ALL;
        i_lfsr_state       = LFSR_IDLE;
        i_reversal_en      = 1'b0;
        i_valid_pattern_en = 1'b0;
        i_pll_en           = 1'b1;          // no-op (PLL .en tied high)
        i_pll_speed_sel    = 2'b00;         // 2 GHz / 500 ps (matches PLL_PERIOD_NS)
        lclk_g             = 1'b1;          // ungate gated_lclk
        i_clk_pattern_en   = 1'b0;
        i_clk_embedded_en  = 1'b1;          // clock lane busy (irrelevant to deser)
        scoreboard_en      = 1'b0;
        pass_count = 0; fail_count = 0; frame_count = 0; enq_count = 0; underflow_count = 0;

        // ---- reset sequenced off pll_clk (clkdiv freezes lclk in reset) ---
        wait_pll(8);
        $display("\n=== PLL up (speed_sel=00 -> 500 ps), releasing reset ===");
        @(negedge o_pll_clk);
        i_rst_n = 1'b1;
        wait_pll(20);
        wait_mb(4);

        // ---- arm scoreboard BEFORE DATA_TRANSFER so it captures W0 --------
        scoreboard_en = 1'b1;

        // ---- enter DATA_TRANSFER, stream pattern 0 -----------------------
        set_pattern(0, pname);
        i_mapper_en = 1'b1;
        lp_irdy     = 1'b1;
        lp_valid    = 1'b1;
        @(negedge lclk);
        i_lfsr_state = LFSR_DATA;
        $display("=== DATA_TRANSFER entered : streaming case 0 (%s) ===", pname);

        // wait until the TX pipeline is actively serializing
        begin
            automatic int g = 0;
            while (!o_ser_en && g < 40) begin @(negedge lclk); g++; end
            if (!o_ser_en) $display("  [WARN] serializer-enable never asserted!");
        end
        wait_mb(WINDOW);

        // ---- stream the remaining patterns ("more cases") ----------------
        for (int p = 1; p < N_PATTERNS; p++) begin
            @(negedge lclk);
            set_pattern(p, pname);
            $display("--- case %0d : streaming %s ---", p, pname);
            wait_mb(WINDOW);
        end

        // ---- stop streaming, let the pipeline / FIFO drain ---------------
        @(negedge lclk);
        i_lfsr_state = LFSR_IDLE;
        i_mapper_en  = 1'b0;
        lp_irdy      = 1'b0;
        lp_valid     = 1'b0;
        wait_mb(40);
        scoreboard_en = 1'b0;

        // ---- report ------------------------------------------------------
        $display("\n=========================================================");
        $display("  unit_tx_deser_wrapper  SER/DES loopback results");
        $display("  ---------------------------------------------------------");
        $display("  serializer loads enqueued : %0d", enq_count);
        $display("  frames recovered & checked: %0d", frame_count);
        $display("  frames PASSED             : %0d", pass_count);
        $display("  frames FAILED             : %0d", fail_count);
        $display("  scoreboard underflows     : %0d", underflow_count);
        $display("  words still in flight     : %0d", sb_q.size());
        $display("=========================================================");
        if (frame_count == 0)
            $display("  >>> NO FRAMES RECOVERED  -  TEST INCONCLUSIVE <<<");
        else if (fail_count == 0 && underflow_count == 0)
            $display("  >>> ALL %0d RECOVERED FRAMES MATCH (after deser == before ser) <<<", frame_count);
        else
            $display("  >>> MISMATCHES DETECTED <<<");
        $display("");
        $stop;
    end

    // ---------------------------------------------------------------- watchdog
    initial begin
        #500_000;   // 500 us
        $display("[WATCHDOG] timeout!  frames=%0d pass=%0d fail=%0d", frame_count, pass_count, fail_count);
        $stop;
    end

endmodule
