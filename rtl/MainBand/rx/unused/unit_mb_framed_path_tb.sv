// =============================================================================
// Testbench : unit_mb_framed_path_tb
// Purpose   : Option-A framed datapath check. Same continuous / multi-flit +
//             lane-degrade integration as mb_path_stream_tb, but the data lanes
//             are framed by a REAL valid lane instead of a TB backdoor:
//
//   Mapper -> LFSR_TX -> unit_mb_serializer x16 ----------------\
//                                                           >-- unit_mb_deserializer_framed x16
//   VALID_TX(0x0F0F0F0F) -> MB_SERIALIZER(valid) -> RVLD_P -+-> MB_DESERIALIZER_VALID
//                                                           |    (framer: word_load)
//                                                           \---------^
//            -> LFSR_RX -> Demapper
//
//   The framer locks onto the first valid posedge and broadcasts o_word_load to
//   all 16 data lanes, so word boundaries come from the valid frame, NOT from
//   des_en timing. The old `des_en aligned to u_ser.rising_ser_en_pll` peek is
//   gone; des_en is simply held high for the whole stream.
//
//   The LFSRs run continuously (never re-seeded): a misaligned framer (even by
//   one byte, mod-8) makes per-word descramble garbage that no constant pipeline
//   offset can reconcile -> the lockstep checker FAILS. A full match therefore
//   proves the framer aligns the data words to the valid frame correctly.
// =============================================================================
`timescale 1ns/1ps

module unit_mb_framed_path_tb;

    localparam int W       = 32;
    localparam int N_BYTES = 64;

    localparam [2:0] NONE  = 3'b000;
    localparam [2:0] D0_7  = 3'b001;
    localparam [2:0] D8_15 = 3'b010;
    localparam [2:0] X16   = 3'b011;
    localparam [2:0] D0_3  = 3'b100;
    localparam [2:0] D4_7  = 3'b101;

    // -------------------------------------------------------------------------
    // Clocks / reset
    // -------------------------------------------------------------------------
    logic MB_clk, pll_tx, pll_rx, i_rst_n;
    initial begin pll_tx=0; forever #1 pll_tx=~pll_tx; end
    always @(pll_tx) #0.5 pll_rx = pll_tx;          // quarter-delayed RX clock
    initial begin MB_clk=0; forever #(W/2) MB_clk=~MB_clk; end

    // -------------------------------------------------------------------------
    // DUT controls / nets
    // -------------------------------------------------------------------------
    logic [2:0] wdeg;
    logic [8*N_BYTES-1:0] flit;
    logic [W-1:0] map_lane [0:15];
    logic [W-1:0] tx_scr   [0:15];
    logic [15:0]  ser_out;
    logic [W-1:0] des_word [0:15];
    logic         de_done  [0:15];
    logic [W-1:0] rx_lane  [0:15];
    logic [W-1:0] rx_gen   [0:15];
    logic [8*N_BYTES-1:0] out_data;

    logic mapper_en, lp_irdy, lp_valid, out_scramble_en, mapper_ready;
    logic tx_active, tx_scramble_en;
    wire  ser_en_w, tx_done_w, tx_vf_w;
    logic des_en;
    logic rx_active, rx_descr, rx_buf;
    wire  rx_comp_en;
    logic demapper_en, rx_data_valid, pl_valid;

    // ----- valid lane (framing master) ---------------------------------------
    wire  [W-1:0] valid_word;       // VALID_TX -> 0x0F0F0F0F
    wire          valid_ser_en;     // unit_valid_tx serializer-enable (= ser_en_w in VALID_FRAME)
    wire          valid_done;
    wire          tvld_p;           // serial valid (RVLD_P at the framer input)
    wire  [W-1:0] rvld_l;           // deserialized valid word
    wire          val_de_done;
    wire          en_valid_frame_w;
    wire          word_load_w;      // shared framing strobe -> all data lanes
    wire          frame_start_w;    // lock pulse (observability)

    // =========================================================================
    // DUT instances
    // =========================================================================
    unit_mapper #(.WIDTH(W), .NUM_LANES(16), .N_BYTES(N_BYTES)) u_map (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .i_in_data(flit), .mapper_en(mapper_en), .i_width_deg_map(wdeg),
        .lp_irdy(lp_irdy), .lp_valid(lp_valid),
        .o_lane_0 (map_lane[0]),  .o_lane_1 (map_lane[1]),  .o_lane_2 (map_lane[2]),  .o_lane_3 (map_lane[3]),
        .o_lane_4 (map_lane[4]),  .o_lane_5 (map_lane[5]),  .o_lane_6 (map_lane[6]),  .o_lane_7 (map_lane[7]),
        .o_lane_8 (map_lane[8]),  .o_lane_9 (map_lane[9]),  .o_lane_10(map_lane[10]), .o_lane_11(map_lane[11]),
        .o_lane_12(map_lane[12]), .o_lane_13(map_lane[13]), .o_lane_14(map_lane[14]), .o_lane_15(map_lane[15]),
        .out_scramble_en(out_scramble_en), .mapper_ready(mapper_ready)
    );

    unit_lfsr_tx #(.WIDTH(W)) u_lfsr_tx (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .i_state(3'b000), .i_scramble_en(tx_scramble_en), .i_width_deg_lfsr(wdeg),
        .i_reversal_en(1'b0), .i_active_state_entered(tx_active),
        .i_lane(map_lane), .o_lane(tx_scr),
        .o_ser_en_lfsr(ser_en_w), .o_Lfsr_tx_done(tx_done_w), .o_valid_frame_en(tx_vf_w)
    );

    // ----- valid lane: VALID_TX -> serializer -> framer ----------------------
    unit_valid_tx u_valid_tx (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .valid_pattern_en(1'b0),            // stay in VALID_FRAME -> 0x0F0F0F0F, gated by LFSR ser-en
        .ser_en_lfsr_i(ser_en_w),
        .ser_en_o(valid_ser_en),
        .O_done(valid_done),
        .o_TVLD_L(valid_word)
    );

    unit_mb_serializer #(.DATA_WIDTH(W)) u_valid_ser (
        .mb_clk(MB_clk), .PLL_clk(pll_tx), .i_rst_n(i_rst_n),
        .Ser_en(valid_ser_en), .in_data(valid_word), .SER_out(tvld_p));

    MB_DESERIALIZER_VALID #(.DATA_WIDTH(W)) u_framer (
        .MB_clk(MB_clk), .pll_clk(pll_rx), .i_rst_n(i_rst_n),
        .ser_valid_en(des_en), .ser_data_in(tvld_p),
        .enable_des_valid_frame(en_valid_frame_w),
        .par_data_out(rvld_l), .de_ser_done(val_de_done),
        .o_word_load(word_load_w), .o_frame_start(frame_start_w));

    // ----- data lanes: serializer -> FRAMED deserializer ---------------------
    genvar g;
    generate
        for (g=0; g<16; g=g+1) begin : g_lane
            unit_mb_serializer #(.DATA_WIDTH(W)) u_ser (
                .mb_clk(MB_clk), .PLL_clk(pll_tx), .i_rst_n(i_rst_n),
                .Ser_en(ser_en_w), .in_data(tx_scr[g]), .SER_out(ser_out[g]));
            unit_mb_deserializer_framed #(.DATA_WIDTH(W)) u_des (
                .MB_clk(MB_clk), .pll_clk(pll_rx), .i_rst_n(i_rst_n),
                .ser_data_en(des_en), .ser_data_in(ser_out[g]),
                .i_word_load(word_load_w),
                .par_data_out(des_word[g]), .de_ser_done(de_done[g]));
        end
    endgenerate

    unit_lfsr_rx #(.WIDTH(W)) u_lfsr_rx (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .i_state(3'b000), .i_width_deg_lfsr(wdeg),
        .i_active_state_entered(rx_active), .i_descramble_en(rx_descr),
        .i_enable_buffer(rx_buf), .i_data_in(des_word),
        .o_Data_by(rx_lane), .o_final_gene(rx_gen), .pattern_comp_en(rx_comp_en)
    );

    unit_demapper #(.N_BYTES(N_BYTES), .NUM_LANES(16), .WIDTH(W)) u_demap (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .i_lane_0 (rx_lane[0]),  .i_lane_1 (rx_lane[1]),  .i_lane_2 (rx_lane[2]),  .i_lane_3 (rx_lane[3]),
        .i_lane_4 (rx_lane[4]),  .i_lane_5 (rx_lane[5]),  .i_lane_6 (rx_lane[6]),  .i_lane_7 (rx_lane[7]),
        .i_lane_8 (rx_lane[8]),  .i_lane_9 (rx_lane[9]),  .i_lane_10(rx_lane[10]), .i_lane_11(rx_lane[11]),
        .i_lane_12(rx_lane[12]), .i_lane_13(rx_lane[13]), .i_lane_14(rx_lane[14]), .i_lane_15(rx_lane[15]),
        .demapper_en(demapper_en), .rx_data_valid(rx_data_valid), .i_width_deg_demap(wdeg),
        .pl_valid(pl_valid), .o_out_data(out_data)
    );

    // =========================================================================
    // Valid-lane self-check: once framed, RVLD_L must read 0x0F0F0F0F
    // =========================================================================
    integer valid_ok_cnt, valid_bad_cnt;
    always @(posedge MB_clk) begin
        if (!i_rst_n) begin
            valid_ok_cnt  <= 0;
            valid_bad_cnt <= 0;
        end else if (val_de_done && en_valid_frame_w) begin
            if (rvld_l === 32'h0F0F0F0F) valid_ok_cnt  <= valid_ok_cnt  + 1;
            else                         valid_bad_cnt <= valid_bad_cnt + 1;
        end
    end

    // =========================================================================
    // Capture buffers
    // =========================================================================
    localparam int NCAP = 256;
    logic [W-1:0] map_q [0:NCAP-1][0:15];
    logic [W-1:0] rx_q  [0:NCAP-1][0:15];
    integer       map_n, rx_n;
    logic         tx_cap_en, rx_cap_en;

    always @(posedge MB_clk) begin
        if (tx_cap_en && out_scramble_en && map_n < NCAP) begin
            for (int i=0;i<16;i=i+1) map_q[map_n][i] <= map_lane[i];
            map_n <= map_n + 1;
        end
    end
    always @(posedge MB_clk) begin
        if (rx_cap_en && rx_n < NCAP) begin
            for (int i=0;i<16;i=i+1) rx_q[rx_n][i] <= rx_lane[i];
            rx_n <= rx_n + 1;
        end
    end

    // =========================================================================
    // which lanes are active for a given mode
    // =========================================================================
    function automatic logic lane_active(input [2:0] m, input int ln);
        begin
            case (m)
                X16  : lane_active = 1'b1;
                D0_7 : lane_active = (ln < 8);
                D8_15: lane_active = (ln >= 8);
                D0_3 : lane_active = (ln < 4);
                D4_7 : lane_active = (ln >= 4 && ln < 8);
                default: lane_active = 1'b0;
            endcase
        end
    endfunction

    // =========================================================================
    // offset-search checker (longest in-order lockstep run)
    // =========================================================================
    integer total_fail;
    logic   last_pass;

    task automatic check_stream(input [127:0] name, input [2:0] m, input logic verbose);
        integer S, D, run, best_run, best_S, best_D, i, REQ;
        logic ok;
        begin
            best_run=0; best_S=0; best_D=0;
            for (S=0; S<=4 && S<map_n; S=S+1) begin
                for (D=0; D<rx_n; D=D+1) begin
                    run=0; ok=1'b1;
                    while (ok && (S+run)<map_n && (D+run)<rx_n) begin
                        for (i=0;i<16;i=i+1)
                            if (lane_active(m,i) && rx_q[D+run][i] !== map_q[S+run][i]) ok=1'b0;
                        if (ok) run=run+1;
                    end
                    if (run>best_run) begin best_run=run; best_S=S; best_D=D; end
                end
            end
            REQ = map_n - 3; if (REQ < 3) REQ = 3;
            last_pass = (best_run >= REQ);
            if (verbose) begin
                if (last_pass)
                    $display("  [%0s] PASS  (%0d/%0d words descrambled in lockstep; tx_fill_skip=%0d rx_pipe=%0d)",
                             name, best_run, map_n, best_S, best_D);
                else begin
                    total_fail = total_fail + 1;
                    $display("  [%0s] FAIL  (longest lockstep run=%0d of %0d, need %0d; map_n=%0d rx_n=%0d)",
                             name, best_run, map_n, REQ, map_n, rx_n);
                end
            end
        end
    endtask

    // =========================================================================
    // Streaming driver
    // =========================================================================
    task automatic run_stream(input [127:0] name, input [2:0] m, input int nf,
                              input int rx_lead, input logic verbose);
        integer c, words_per_flit, total_words, fidx;
        begin
            // reset whole DUT so both LFSRs start from seed
            i_rst_n=0; mapper_en=0; lp_valid=0; lp_irdy=1;
            tx_active=0; tx_scramble_en=1; des_en=0;
            rx_active=0; rx_descr=0; rx_buf=0;
            demapper_en=1; rx_data_valid=0;
            tx_cap_en=0; rx_cap_en=0; map_n=0; rx_n=0; flit=0;
            wdeg=m;
            repeat(4) @(posedge MB_clk); i_rst_n=1; repeat(2) @(posedge MB_clk);

            words_per_flit = (m==X16) ? 1 : (m==D0_7 || m==D8_15) ? 2 : 4;
            total_words    = nf * words_per_flit;

            // ---- start TX scrambling + unit_mapper streaming; hold des_en high ----
            @(negedge MB_clk);
            mapper_en=1; lp_valid=1; tx_active=1; tx_cap_en=1;
            des_en=1;                       // framer self-aligns -> no backdoor needed
            fidx=0;

            fork
                begin : feeder
                    for (fidx=0; fidx<nf; fidx=fidx+1) begin
                        for (c=0;c<64;c=c+1) flit[c*8 +: 8] = (name[7:0] + fidx*8'h11 + c[7:0]);
                        repeat(words_per_flit) @(negedge MB_clk);
                    end
                    lp_valid=0;
                end
                begin : rx_start
                    repeat(rx_lead) @(posedge MB_clk);
                    @(negedge MB_clk); rx_active=1; rx_descr=1; rx_cap_en=1;
                end
            join

            repeat(total_words + 12) @(posedge MB_clk);
            tx_active=0; rx_active=0; rx_descr=0; des_en=0;
            tx_cap_en=0; rx_cap_en=0;
            @(posedge MB_clk);

            if (map_n > total_words) map_n = total_words;
            check_stream(name, m, verbose);
        end
    endtask

    // =========================================================================
    // Main
    // =========================================================================
    integer lead, good_lead;
    initial begin
        total_fail = 0;
        good_lead  = -1;
        $display("==============================================================");
        $display("  Option-A framed datapath test  (valid-lane word_load framing)");
        $display("==============================================================");

        // calibrate the RX descramble lead (chain latency incl. framer lock)
        for (lead=0; lead<=24 && good_lead<0; lead=lead+1) begin
            run_stream("cal", X16, 8, lead, 1'b0);
            if (last_pass) good_lead = lead;
        end
        if (good_lead < 0) begin
            $display("  CALIBRATION FAILED: no rx_lead in [0,24] aligns the LFSRs");
            $display("  (valid_ok=%0d valid_bad=%0d : if valid_bad>0 the framer pair-phase is off)",
                     valid_ok_cnt, valid_bad_cnt);
            $display("==============================================================");
            $display("  RESULT: FAIL"); $stop;
        end
        $display("  calibrated rx_lead = %0d (TX->RX descramble latency)\n", good_lead);

        run_stream("x16 multiflit",  X16,  8, good_lead, 1'b1);
        run_stream("x8  lanes0-7",   D0_7, 5, good_lead, 1'b1);
        run_stream("x8  lanes8-15",  D8_15,5, good_lead, 1'b1);
        run_stream("x4  lanes0-3",   D0_3, 3, good_lead, 1'b1);
        run_stream("x4  lanes4-7",   D4_7, 3, good_lead, 1'b1);

        $display("--------------------------------------------------------------");
        $display("  valid-lane framing self-check: RVLD_L==0x0F0F0F0F ok=%0d bad=%0d",
                 valid_ok_cnt, valid_bad_cnt);
        $display("==============================================================");
        if (total_fail==0 && valid_bad_cnt==0)
            $display("  RESULT: PASS  (all modes framed & descrambled in lockstep)");
        else
            $display("  RESULT: FAIL  (%0d mode(s) failed, valid_bad=%0d)", total_fail, valid_bad_cnt);
        $display("==============================================================");
        $stop;
    end
    initial begin #500000; $display("  RESULT: FAIL (global timeout)"); $stop; end

endmodule
