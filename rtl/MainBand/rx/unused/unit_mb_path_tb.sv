// =============================================================================
// Testbench : unit_mb_path_tb
// Purpose   : Integration check of the MainBand datapath
//
//     Mapper -> LFSR_TX -> unit_mb_serializer x16 -> unit_mb_deserializer x16
//            -> LFSR_RX -> Demapper
//
//   A single 512-bit flit is pushed through in x16 mode. Because scramble and
//   descramble cancel and the serdes is transparent, the data recovered at
//   unit_lfsr_rx must equal the Mapper's lane words, and the unit_demapper output must
//   equal demapper(mapper(flit)).
//
//   Uses the SPEC-FIXED blocks from unsued/ (LFSR_TX, mb_deserializer, LFSR_RX)
//   so the path is actually correct end to end. The serdes uses a quarter-period
//   delayed RX clock (mid-eye sampling) and ser_data_en aligned to the
//   serializer load and held for exactly one 16-cycle word -- the recipe proven
//   in the serdes probe.
//
//   Both LFSRs process exactly ONE word from seed state, so TX scrambles with
//   prbs32(SEED) and RX descrambles with prbs32(SEED) -- inherently aligned, no
//   multi-word state tracking needed.
//
//   Checks:
//     A) unit_lfsr_rx o_Data_by[i] == unit_mapper o_lane[i]   (per-lane, 16 lanes)
//     B) unit_demapper o_out_data  == demapper_model(unit_mapper lanes)
// =============================================================================
`timescale 1ns/1ps

module unit_mb_path_tb;

    localparam int W       = 32;
    localparam int N_BYTES = 64;
    localparam [2:0] X16   = 3'b011;   // DEGRADE_LANES_0_TO_15
    localparam [2:0] IDLE          = 3'b000;
    localparam [2:0] DATA_TRANSFER = 3'b100;

    // -------------------------------------------------------------------------
    // Clocks / reset
    // -------------------------------------------------------------------------
    logic MB_clk, pll_tx, pll_rx, i_rst_n;
    initial begin pll_tx = 0; forever #1 pll_tx = ~pll_tx; end          // 2 ns
    always @(pll_tx) #0.5 pll_rx = pll_tx;                              // +0.5 ns (mid-eye)
    initial begin MB_clk = 0; forever #(W/2) MB_clk = ~MB_clk; end      // 32 ns

    // -------------------------------------------------------------------------
    // Inter-stage nets
    // -------------------------------------------------------------------------
    logic [8*N_BYTES-1:0] flit;
    logic [W-1:0] map_lane [0:15];     // unit_mapper outputs (TX lanes, golden)
    logic [W-1:0] tx_scr   [0:15];     // unit_lfsr_tx scrambled outputs
    logic [15:0]  ser_out;             // 16 serial lines
    logic [W-1:0] des_word [0:15];     // Deserializer parallel outputs
    logic         de_done  [0:15];
    logic [W-1:0] rx_lane  [0:15];     // unit_lfsr_rx descrambled outputs (RX lanes)
    logic [W-1:0] rx_gen   [0:15];
    logic [8*N_BYTES-1:0] out_data;

    // unit_mapper controls
    logic mapper_en, lp_irdy, lp_valid, out_scramble_en, mapper_ready;
    // unit_lfsr_tx controls
    logic [2:0] tx_state;
    logic tx_scramble_en;
    wire  ser_en_w;                    // = LFSR_TX.o_ser_en_lfsr (self-aligned load)
    wire  tx_done_w;
    // serdes controls
    logic des_en;
    // unit_lfsr_rx controls
    logic [2:0] rx_state;
    logic rx_descr, rx_buf;
    wire  rx_comp_en;
    // unit_demapper controls
    logic demapper_en, rx_data_valid, pl_valid;

    // =========================================================================
    // Stage 1: Mapper
    // =========================================================================
    unit_mapper #(.WIDTH(W), .NUM_LANES(16), .N_BYTES(N_BYTES)) u_map (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .i_in_data(flit), .mapper_en(mapper_en), .i_width_deg_map(X16),
        .lp_irdy(lp_irdy), .lp_valid(lp_valid),
        .o_lane_0 (map_lane[0]),  .o_lane_1 (map_lane[1]),  .o_lane_2 (map_lane[2]),  .o_lane_3 (map_lane[3]),
        .o_lane_4 (map_lane[4]),  .o_lane_5 (map_lane[5]),  .o_lane_6 (map_lane[6]),  .o_lane_7 (map_lane[7]),
        .o_lane_8 (map_lane[8]),  .o_lane_9 (map_lane[9]),  .o_lane_10(map_lane[10]), .o_lane_11(map_lane[11]),
        .o_lane_12(map_lane[12]), .o_lane_13(map_lane[13]), .o_lane_14(map_lane[14]), .o_lane_15(map_lane[15]),
        .out_scramble_en(out_scramble_en), .mapper_ready(mapper_ready)
    );

    // =========================================================================
    // Stage 2: LFSR_TX (scramble)
    // =========================================================================
    unit_lfsr_tx #(.WIDTH(W)) u_lfsr_tx (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .i_state(tx_state), .i_scramble_en(tx_scramble_en), .i_width_deg_lfsr(X16),
        .i_reversal_en(1'b0),
        .i_lane(map_lane), .o_lane(tx_scr),
        .o_ser_en_lfsr(ser_en_w), .o_Lfsr_tx_done(tx_done_w)
    );

    // =========================================================================
    // Stage 3+4: 16x serializer / deserializer
    // =========================================================================
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : g_lane
            unit_mb_serializer #(.DATA_WIDTH(W)) u_ser (
                .mb_clk(MB_clk), .PLL_clk(pll_tx), .i_rst_n(i_rst_n),
                .Ser_en(ser_en_w), .in_data(tx_scr[g]), .SER_out(ser_out[g])
            );
            unit_mb_deserializer #(.DATA_WIDTH(W)) u_des (
                .MB_clk(MB_clk), .pll_clk(pll_rx), .i_rst_n(i_rst_n),
                .ser_data_en(des_en), .ser_data_in(ser_out[g]),
                .enable_des_valid_frame(1'b1),
                .par_data_out(des_word[g]), .de_ser_done(de_done[g])
            );
        end
    endgenerate

    // =========================================================================
    // Stage 5: LFSR_RX (descramble)
    // =========================================================================
    unit_lfsr_rx #(.WIDTH(W)) u_lfsr_rx (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .i_state(rx_state), .i_width_deg_lfsr(X16),
        .i_descramble_en(rx_descr),
        .i_enable_buffer(rx_buf), .i_data_in(des_word),
        .o_Data_by(rx_lane), .o_final_gene(rx_gen), .pattern_comp_en(rx_comp_en)
    );

    // =========================================================================
    // Stage 6: Demapper
    // =========================================================================
    unit_demapper #(.N_BYTES(N_BYTES), .NUM_LANES(16), .WIDTH(W)) u_demap (
        .i_clk(MB_clk), .i_rst_n(i_rst_n),
        .i_lane_0 (rx_lane[0]),  .i_lane_1 (rx_lane[1]),  .i_lane_2 (rx_lane[2]),  .i_lane_3 (rx_lane[3]),
        .i_lane_4 (rx_lane[4]),  .i_lane_5 (rx_lane[5]),  .i_lane_6 (rx_lane[6]),  .i_lane_7 (rx_lane[7]),
        .i_lane_8 (rx_lane[8]),  .i_lane_9 (rx_lane[9]),  .i_lane_10(rx_lane[10]), .i_lane_11(rx_lane[11]),
        .i_lane_12(rx_lane[12]), .i_lane_13(rx_lane[13]), .i_lane_14(rx_lane[14]), .i_lane_15(rx_lane[15]),
        .demapper_en(demapper_en), .rx_data_valid(rx_data_valid), .i_width_deg_demap(X16),
        .pl_valid(pl_valid), .o_out_data(out_data)
    );

    // =========================================================================
    // Golden model of the x16 demapper (from captured unit_mapper lanes)
    // =========================================================================
    function automatic logic [8*N_BYTES-1:0] demap_x16(input logic [W-1:0] L [0:15]);
        integer p, grp, lane;
        logic [8*N_BYTES-1:0] o;
        begin
            o = '0;
            for (p = 0; p < 64; p = p + 1) begin
                grp  = p / 16;            // byte-lane 0..3
                lane = p % 16;
                // MSB byte first: out byte (63-p) = L[lane][8*grp +:8]
                o[(63-p)*8 +: 8] = L[lane][8*grp +: 8];
            end
            demap_x16 = o;
        end
    endfunction

    // =========================================================================
    // Capture storage + checking
    // =========================================================================
    logic [W-1:0] cap_map [0:15];
    logic [W-1:0] cap_rx  [0:15];
    logic [8*N_BYTES-1:0] exp_out, out_data_cap;
    logic [W-1:0] cap_txscr;
    integer i, k, fails;

    // latch the scrambled lane-0 word at the cycle the serializer is loaded
    always @(posedge MB_clk) if (ser_en_w) cap_txscr <= tx_scr[0];

    initial begin
        // defaults
        i_rst_n=0; flit=0; mapper_en=0; lp_irdy=1; lp_valid=0;
        tx_state=IDLE; tx_scramble_en=1; des_en=0;
        rx_state=IDLE; rx_descr=0; rx_buf=0;
        demapper_en=1; rx_data_valid=0; fails=0;

        repeat (4) @(posedge MB_clk); i_rst_n=1; @(posedge MB_clk);

        // a recognizable flit (each byte distinct)
        for (k=0;k<64;k=k+1) flit[k*8 +: 8] = 8'h10 + k[7:0];

        // ---- drive the mapper, hold inputs so its lane outputs are stable ----
        mapper_en=1; lp_valid=1; lp_irdy=1;
        repeat (3) @(posedge MB_clk);
        for (i=0;i<16;i=i+1) cap_map[i]=map_lane[i];
        $display("MAP lane0=0x%08h lane1=0x%08h lane15=0x%08h",
                 cap_map[0], cap_map[1], cap_map[15]);

        // ---- LFSR_TX: scramble ONE word (seed state) -> drives ser_en_w ----
        @(negedge MB_clk); tx_state=DATA_TRANSFER;
        @(negedge MB_clk); tx_state=IDLE;

        // ---- serdes: align des_en to serializer load, hold 16 pll cycles ----
        @(posedge pll_tx);
        while (!g_lane[0].u_ser.rising_ser_en_pll) @(posedge pll_tx);
        des_en=1;
        repeat (16) @(posedge pll_tx);
        des_en=0;

        // wait for deserialized word (capture at de_done)
        k=0;
        while (!de_done[0] && k<40) begin @(posedge MB_clk); #0.1; k=k+1; end
        $display("TXSCR lane0=0x%08h  (= prbs32(SEED0) ^ map_lane0)", cap_txscr);
        $display("DES  lane0=0x%08h  de_done=%b  (serdes-transported scrambled word)",
                 des_word[0], de_done[0]);

        // ---- LFSR_RX: descramble ONE word (seed state), hold 3 cycles ----
        @(negedge MB_clk); rx_state=DATA_TRANSFER; rx_descr=1;
        repeat (3) @(posedge MB_clk);
        @(negedge MB_clk); rx_state=IDLE; rx_descr=0;
        @(posedge MB_clk); #0.1;
        for (i=0;i<16;i=i+1) cap_rx[i]=rx_lane[i];
        $display("RX   lane0=0x%08h lane1=0x%08h lane15=0x%08h",
                 cap_rx[0], cap_rx[1], cap_rx[15]);

        // ---- CHECK A: per-lane round trip ----
        $display("\n--- CHECK A: unit_lfsr_rx lanes vs unit_mapper lanes ---");
        for (i=0;i<16;i=i+1) begin
            if (cap_rx[i] !== cap_map[i]) begin
                fails=fails+1;
                $display("  lane %0d MISMATCH: rx=0x%08h map=0x%08h", i, cap_rx[i], cap_map[i]);
            end
        end
        if (fails==0) $display("  all 16 lanes MATCH");

        // ---- Demapper: hold rx_data_valid (rx_lane holds the flit) and capture
        //      o_out_data exactly when pl_valid asserts ----
        @(negedge MB_clk); rx_data_valid=1;
        out_data_cap = 'x; k=0;
        while (k<10) begin
            @(posedge MB_clk); #0.1;
            if (pl_valid) begin out_data_cap = out_data; k=99; end
            else k=k+1;
        end
        rx_data_valid=0;
        exp_out = demap_x16(cap_map);
        $display("\n--- CHECK B: unit_demapper output vs model ---");
        $display("  out=0x%032h", out_data_cap);
        $display("  exp=0x%032h", exp_out);
        if (out_data_cap !== exp_out) begin
            fails=fails+1;
            $display("  unit_demapper MISMATCH");
        end else $display("  unit_demapper MATCH  (pl_valid captured)");

        $display("\n==============================================================");
        if (fails==0) $display("  RESULT: PASS  (mapper->lfsr_tx->ser->des->lfsr_rx->demapper)");
        else          $display("  RESULT: FAIL  (%0d mismatch(es))", fails);
        $display("==============================================================");
        $stop;
    end

    initial begin #200000; $display("  RESULT: FAIL (global timeout)"); $stop; end

endmodule
