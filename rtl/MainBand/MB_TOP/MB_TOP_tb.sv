`timescale 1ps/1ps
// =============================================================================
// Testbench : MB_TOP_tb  (two mb_die instances wired back-to-back)
// DUT       : mb_die × 2  (die 0 ↔ die 1)
//
//                +--------- die 0 ---------+        +--------- die 1 ---------+
//  lp_data0 →   | TX→o_TD/VLD/CK/TRK ----→|--------→| i_RD/VLD/CK/TRK→RX    |→ o_out_data1
//               | RX←i_RD/VLD/CK/TRK ←---|--------←| o_TD/VLD/CK/TRK←TX    |← lp_data1
//                +-------------------------+        +-------------------------+
//
// Scenarios exercised
// -------------------
//  fulltraining_happy_scenario  (basic, stall, heavy-load)
//  fault injection  (dead clock / bad valid / stuck data lane on die1→die0 link)
//  5 × 5 × 3 width-degrade × reversal sweep
//
// Run with:  .\run_sim.ps1 -MODE debug -CONFIG MB_TOP -TOP MB_TOP_tb
// =============================================================================

module MB_TOP_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam DATA_WIDTH = 32;
    localparam NUM_LANES  = 16;
    localparam N_BYTES    = 64;
    localparam FLITW      = 8 * N_BYTES;   // 512-bit flit bus

    // LTSM state codes
    localparam [2:0]
        ST_IDLE    = 3'b000,
        ST_CLEAR   = 3'b001,
        ST_PATTERN = 3'b010,
        ST_PERLANE = 3'b011,
        ST_DATA    = 3'b100;

    // Width-degradation codes (match LFSR_TX/LFSR_RX)
    localparam [2:0]
        W_NONE    = 3'b000,
        W_0TO7    = 3'b001,
        W_8TO15   = 3'b010,
        W_ALL16   = 3'b011,
        W_0TO3    = 3'b100,
        W_4TO7    = 3'b101;

    // Comparator type
    localparam [1:0] COM_PER_LANE = 2'b01;

    // Timeouts (in MB_clk cycles)
    localparam int TO_MB_CLK   = 4_000;   // wait for o_clk_done
    localparam int TO_MB_VALID = 300;     // wait for valid detection
    localparam int TO_MB_DATA  = 400;     // wait for o_error_done
    localparam int TO_MB_FLIT  = 150;     // wait for pl_valid in data mode

    localparam longint WD_PS = 1_200_000_000;  // watchdog 1.2 µs

    // =========================================================================
    // Global control signals (shared between die0 and die1)
    // =========================================================================
    logic       i_rst_n           = 0;
    logic       i_pll_en          = 0;
    logic [1:0] i_pll_speed_sel   = 2'b00;   // 2 GHz

    logic [2:0] i_lfsr_state      = ST_IDLE;
    logic       i_active_state_entered;       // combinational from i_lfsr_state
    logic       enbuf_now;                    // combinational enable_buffer

    logic       i_clk_pattern_en  = 0;
    logic       i_clk_embedded_en = 0;
    logic       i_valid_pattern_en= 0;
    logic       tb_reversal_en    = 0;
    logic       i_enable_cons     = 0;
    logic       i_enable_128      = 0;
    logic       i_enable_detector = 0;
    logic [11:0] i_max_err_valid  = 12'd0;
    logic [15:0] i_max_err_per_lane = 16'd0;
    logic [15:0] i_max_err_agg      = 16'd0;
    logic       i_mapper_en       = 0;
    logic       lp_irdy           = 0;

    // Combinational signals derived from i_lfsr_state
    always_comb begin
        i_active_state_entered = (i_lfsr_state == ST_DATA);
        enbuf_now = (i_lfsr_state == ST_PATTERN) ||
                    (i_lfsr_state == ST_PERLANE)  ||
                    (i_lfsr_state == ST_DATA);
    end

    // Per-die width-deg (can differ for reversal sweep)
    logic [2:0] die0_width_deg_tx = W_ALL16;
    logic [2:0] die0_width_deg_rx = W_ALL16;
    logic [2:0] die1_width_deg_tx = W_ALL16;
    logic [2:0] die1_width_deg_rx = W_ALL16;

    // Per-die data payloads
    logic [FLITW-1:0] lp_data0 = '0;
    logic [FLITW-1:0] lp_data1 = '0;
    logic             lp_valid0 = 0;
    logic             lp_valid1 = 0;

    // =========================================================================
    // Inter-die pad wires  (die0 TX → die1 RX and vice-versa)
    // =========================================================================
    logic [NUM_LANES-1:0] d0_TD_P,  d1_TD_P;
    logic                 d0_TVLD_P, d1_TVLD_P;
    logic                 d0_TCKP_P, d1_TCKP_P;
    logic                 d0_TCKN_P, d1_TCKN_P;
    logic                 d0_TTRK_P, d1_TTRK_P;

    // Channel wires (allow fault injection by intercepting here)
    logic [NUM_LANES-1:0] d1_to_d0_data;
    logic                 d1_to_d0_vld;
    logic                 d1_to_d0_ckp;
    logic                 d1_to_d0_ckn;
    logic                 d1_to_d0_trk;

    assign d1_to_d0_data = d1_TD_P;   // default (no fault)
    assign d1_to_d0_vld  = d1_TVLD_P;
    assign d1_to_d0_ckp  = d1_TCKP_P;
    assign d1_to_d0_ckn  = d1_TCKN_P;
    assign d1_to_d0_trk  = d1_TTRK_P;

    // =========================================================================
    // Die 0 output monitors
    // =========================================================================
    logic        o_pll_clk0, lclk0;       // pll and mb clocks
    logic        o_clk_done0, o_valid_done0, o_lfsr_tx_done0, o_mapper_ready0;
    logic        de_ser_done0, detection_result0, o_valid_frame_detect0;
    logic [15:0] o_per_lane_error0;
    logic [31:0] o_error_counter0;
    logic        o_error_done0;
    logic        clk_p_pass0, clk_n_pass0, track_pass0;
    logic        pl_valid0;
    logic [FLITW-1:0] o_out_data0;

    // =========================================================================
    // Die 1 output monitors
    // =========================================================================
    logic        o_pll_clk1, lclk1;
    logic        o_clk_done1, o_valid_done1, o_lfsr_tx_done1, o_mapper_ready1;
    logic        de_ser_done1, detection_result1, o_valid_frame_detect1;
    logic [15:0] o_per_lane_error1;
    logic [31:0] o_error_counter1;
    logic        o_error_done1;
    logic        clk_p_pass1, clk_n_pass1, track_pass1;
    logic        pl_valid1;
    logic [FLITW-1:0] o_out_data1;

    // =========================================================================
    // DUT — Die 0
    // =========================================================================
    mb_die #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_LANES (NUM_LANES),
        .N_BYTES   (N_BYTES)
    ) die0 (
        .i_rst_n               (i_rst_n),
        .i_pll_en              (i_pll_en),
        .i_pll_speed_sel       (i_pll_speed_sel),
        .o_pll_clk             (o_pll_clk0),
        .o_mb_clk              (lclk0),

        .lp_data               (lp_data0),
        .i_mapper_en           (i_mapper_en),
        .i_lp_irdy             (lp_irdy),
        .i_lp_valid            (lp_valid0),
        .o_mapper_ready        (o_mapper_ready0),

        .i_width_deg_tx        (die0_width_deg_tx),
        .i_lfsr_state          (i_lfsr_state),
        .i_reversal_en         (tb_reversal_en),
        .i_active_state_entered(i_active_state_entered),
        .o_lfsr_tx_done        (o_lfsr_tx_done0),

        .i_valid_pattern_en    (i_valid_pattern_en),
        .o_valid_done          (o_valid_done0),

        .i_clk_pattern_en      (i_clk_pattern_en),
        .i_clk_embedded_en     (i_clk_embedded_en),
        .o_clk_done            (o_clk_done0),

        // TX pads (die0 TX → die1 RX)
        .o_TD_P                (d0_TD_P),
        .o_TVLD_P              (d0_TVLD_P),
        .o_TCKP_P              (d0_TCKP_P),
        .o_TCKN_P              (d0_TCKN_P),
        .o_TTRK_P              (d0_TTRK_P),

        // RX pads (die0 RX ← die1 TX via channel)
        .i_RD_P                (d1_to_d0_data),
        .i_RVLD_P              (d1_to_d0_vld),
        .i_RCKP_P              (d1_to_d0_ckp),
        .i_RCKN_P              (d1_to_d0_ckn),
        .i_RTRK_P              (d1_to_d0_trk),

        .i_state               (i_lfsr_state),
        .i_width_deg_rx        (die0_width_deg_rx),
        .i_descramble_en       (i_active_state_entered),
        .i_enable_buffer       (enbuf_now),

        .i_clk_detector_en     (i_clk_pattern_en),
        .i_max_err_valid       (i_max_err_valid),
        .i_enable_cons         (i_enable_cons),
        .i_enable_128          (i_enable_128),
        .i_enable_detector     (i_enable_detector),

        .i_type_of_com         (COM_PER_LANE),
        .i_max_err_per_lane    (i_max_err_per_lane),
        .i_max_err_agg         (i_max_err_agg),

        .demapper_en           (i_active_state_entered),
        .rx_data_valid         (i_active_state_entered),

        .de_ser_done           (de_ser_done0),
        .detection_result      (detection_result0),
        .o_valid_frame_detect  (o_valid_frame_detect0),
        .o_per_lane_error      (o_per_lane_error0),
        .o_error_counter       (o_error_counter0),
        .o_error_done          (o_error_done0),
        .clk_p_pattern_pass    (clk_p_pass0),
        .clk_n_pattern_pass    (clk_n_pass0),
        .track_pattern_pass    (track_pass0),
        .pl_valid              (pl_valid0),
        .o_out_data            (o_out_data0)
    );

    // =========================================================================
    // DUT — Die 1
    // =========================================================================
    mb_die #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_LANES (NUM_LANES),
        .N_BYTES   (N_BYTES)
    ) die1 (
        .i_rst_n               (i_rst_n),
        .i_pll_en              (i_pll_en),
        .i_pll_speed_sel       (i_pll_speed_sel),
        .o_pll_clk             (o_pll_clk1),
        .o_mb_clk              (lclk1),

        .lp_data               (lp_data1),
        .i_mapper_en           (i_mapper_en),
        .i_lp_irdy             (lp_irdy),
        .i_lp_valid            (lp_valid1),
        .o_mapper_ready        (o_mapper_ready1),

        .i_width_deg_tx        (die1_width_deg_tx),
        .i_lfsr_state          (i_lfsr_state),
        .i_reversal_en         (tb_reversal_en),
        .i_active_state_entered(i_active_state_entered),
        .o_lfsr_tx_done        (o_lfsr_tx_done1),

        .i_valid_pattern_en    (i_valid_pattern_en),
        .o_valid_done          (o_valid_done1),

        .i_clk_pattern_en      (i_clk_pattern_en),
        .i_clk_embedded_en     (i_clk_embedded_en),
        .o_clk_done            (o_clk_done1),

        // TX pads (die1 TX → die0 RX directly)
        .o_TD_P                (d1_TD_P),
        .o_TVLD_P              (d1_TVLD_P),
        .o_TCKP_P              (d1_TCKP_P),
        .o_TCKN_P              (d1_TCKN_P),
        .o_TTRK_P              (d1_TTRK_P),

        // RX pads (die1 RX ← die0 TX directly)
        .i_RD_P                (d0_TD_P),
        .i_RVLD_P              (d0_TVLD_P),
        .i_RCKP_P              (d0_TCKP_P),
        .i_RCKN_P              (d0_TCKN_P),
        .i_RTRK_P              (d0_TTRK_P),

        .i_state               (i_lfsr_state),
        .i_width_deg_rx        (die1_width_deg_rx),
        .i_descramble_en       (i_active_state_entered),
        .i_enable_buffer       (enbuf_now),

        .i_clk_detector_en     (i_clk_pattern_en),
        .i_max_err_valid       (i_max_err_valid),
        .i_enable_cons         (i_enable_cons),
        .i_enable_128          (i_enable_128),
        .i_enable_detector     (i_enable_detector),

        .i_type_of_com         (COM_PER_LANE),
        .i_max_err_per_lane    (i_max_err_per_lane),
        .i_max_err_agg         (i_max_err_agg),

        .demapper_en           (i_active_state_entered),
        .rx_data_valid         (i_active_state_entered),

        .de_ser_done           (de_ser_done1),
        .detection_result      (detection_result1),
        .o_valid_frame_detect  (o_valid_frame_detect1),
        .o_per_lane_error      (o_per_lane_error1),
        .o_error_counter       (o_error_counter1),
        .o_error_done          (o_error_done1),
        .clk_p_pattern_pass    (clk_p_pass1),
        .clk_n_pattern_pass    (clk_n_pass1),
        .track_pattern_pass    (track_pass1),
        .pl_valid              (pl_valid1),
        .o_out_data            (o_out_data1)
    );

    // =========================================================================
    // Test bookkeeping
    // =========================================================================
    int scenario_pass  = 0;
    int scenario_fail  = 0;
    int total_checks   = 0;
    int total_pass     = 0;
    int total_fail     = 0;

    // =========================================================================
    // Helper tasks
    // =========================================================================

    task automatic wait_pll(input int n);
        repeat (n) @(posedge o_pll_clk0);
    endtask

    task automatic wait_mb(input int n);
        repeat (n) @(posedge lclk0);
    endtask

    task automatic wait_sig_mb(
        input  string name,
        ref    logic  sig,
        input  int    timeout_cyc,
        output bit    ok
    );
        int cnt = 0;
        ok = 0;
        @(posedge lclk0);
        while (!sig && cnt < timeout_cyc) begin
            if (cnt < 10 || cnt % 100 == 0) begin
                $display("[DEBUG TB] wait_sig_mb: name=%s, sig=%b, die0.o_clk_done=%b, gen.o_done=%b, gen.burst_cnt=%0d, gen.phase_cnt=%0d, cnt=%0d at t=%0t", 
                         name, sig, die0.o_clk_done, die0.u_tx.u_clk_pattern_gen.o_done, die0.u_tx.u_clk_pattern_gen.burst_cnt, die0.u_tx.u_clk_pattern_gen.phase_cnt, cnt, $time);
            end
            @(posedge lclk0);
            cnt++;
        end
        ok = sig;
        $display("[DEBUG TB] wait_sig_mb done: name=%s, sig=%b, ok=%b, cnt=%0d at t=%0t", name, sig, ok, cnt, $time);
    endtask

    task automatic wait_sig_pll(
        input  string name,
        ref    logic  sig,
        input  int    timeout_cyc,
        output bit    ok
    );
        int cnt = 0;
        ok = 0;
        @(posedge o_pll_clk0);
        while (!sig && cnt < timeout_cyc) begin
            @(posedge o_pll_clk0);
            cnt++;
        end
        ok = sig;
        if (!ok)
            $display("  [TIMEOUT] %s not seen after %0d pll cycles (t=%0t ps)",
                     name, timeout_cyc, $time);
    endtask

    task automatic check(input string desc, input logic cond);
        total_checks++;
        if (cond) begin
            $display("    [PASS] %s", desc);
            total_pass++;
        end else begin
            $display("    [FAIL] %s", desc);
            total_fail++;
        end
    endtask

    // Reset + PLL startup, then leave clk_embedded_en in requested state
    task automatic link_reset(input logic embedded_clk = 0);
        i_clk_pattern_en  = 0;
        i_clk_embedded_en = 0;
        i_valid_pattern_en= 0;
        i_mapper_en       = 0;
        lp_irdy           = 0;
        lp_valid0         = 0;
        lp_valid1         = 0;
        i_lfsr_state      = ST_IDLE;
        i_enable_cons     = 0;
        i_enable_128      = 0;
        i_enable_detector = 0;
        i_max_err_valid   = 12'd0;
        tb_reversal_en    = 0;
        die0_width_deg_tx = W_ALL16; die0_width_deg_rx = W_ALL16;
        die1_width_deg_tx = W_ALL16; die1_width_deg_rx = W_ALL16;

        i_rst_n  = 0;
        i_pll_en = 1;
        wait_pll(20);
        @(posedge o_pll_clk0); i_rst_n = 1;
        wait_mb(4);

        i_clk_embedded_en = embedded_clk;
    endtask

    // =========================================================================
    // Phase tasks
    // =========================================================================

    // Phase CLK: transmit and detect clock pattern on both dies
    task automatic phase_clk_test(output bit ok);
        bit ok_done0, ok_done1, ok_clk;
        $display("  [CLK phase] t=%0t ps", $time);

        @(negedge lclk0);
        i_clk_pattern_en = 1;

        wait_sig_mb("o_clk_done0", o_clk_done0, TO_MB_CLK, ok_done0);

        ok_clk = clk_p_pass0 && clk_n_pass0 && track_pass0 &&
                 clk_p_pass1 && clk_n_pass1 && track_pass1;
        check("CLK: clk_p_pass (die0)", clk_p_pass0);
        check("CLK: clk_n_pass (die0)", clk_n_pass0);
        check("CLK: track_pass (die0)", track_pass0);
        check("CLK: clk_p_pass (die1)", clk_p_pass1);
        check("CLK: clk_n_pass (die1)", clk_n_pass1);
        check("CLK: track_pass (die1)", track_pass1);

        i_clk_pattern_en = 0;
        wait_mb(40);
        ok = ok_clk;
    endtask

    // Phase VALID: transmit the VALID-lane pattern and detect on both dies
    task automatic phase_valid_test(
        input logic mode1,   // 0 = CONSEC_16 mode, 1 = ITER_128 mode
        output bit ok
    );
        bit ok_d0, ok_d1, ok_t;
        int t;
        $display("  [VALID phase mode=%0d] t=%0t ps", mode1, $time);

        @(negedge lclk0);
        i_max_err_valid  = 12'd16;
        if (mode1) begin i_enable_cons = 0; i_enable_128 = 1; end
        else       begin i_enable_cons = 1; i_enable_128 = 0; end
        i_enable_detector = 1;
        i_valid_pattern_en= 1;

        ok_d0 = 0; ok_d1 = 0; t = 0;
        while (!(ok_d0 && ok_d1) && t < TO_MB_VALID) begin
            @(posedge lclk0);
            if (detection_result0) ok_d0 = 1;
            if (detection_result1) ok_d1 = 1;
            t++;
        end
        i_valid_pattern_en = 0;
        i_enable_cons      = 0;
        i_enable_128       = 0;
        i_enable_detector  = 0;
        i_max_err_valid    = 12'd0;
        wait_mb(40);

        check("VALID: detection_result (die0)", ok_d0);
        check("VALID: detection_result (die1)", ok_d1);
        ok = ok_d0 && ok_d1;
    endtask

    // Phase DATA (LFSR training): PATTERN_LFSR or PER_LANE_ID
    task automatic phase_data_test(
        input  string   lbl,
        input  logic [2:0] lfsr_st,
        output bit      ok
    );
        bit ok_done0, ok_done1;
        bit done0, done1;
        logic [15:0] pe0, pe1;
        logic [31:0] ec0, ec1;
        int t;
        $display("  [%s phase] t=%0t ps", lbl, $time);

        // CLEAR_LFSR to sync seeds
        @(negedge lclk0);
        i_lfsr_state = ST_CLEAR;
        wait_mb(3);
        i_lfsr_state = ST_IDLE;
        wait_mb(2);

        i_max_err_per_lane = 16'd0;
        i_max_err_agg      = 16'd0;
        @(negedge lclk0);
        i_lfsr_state      = lfsr_st;
        i_enable_detector = 1;

        done0=0; done1=0; pe0='1; pe1='1; ec0='1; ec1='1; t=0;
        while (!(done0 && done1) && t < TO_MB_DATA) begin
            @(posedge lclk0);
            if (o_error_done0 && !done0) begin
                done0 = 1;
                pe0   = o_per_lane_error0;
                ec0   = o_error_counter0;
            end
            if (o_error_done1 && !done1) begin
                done1 = 1;
                pe1   = o_per_lane_error1;
                ec1   = o_error_counter1;
            end
            t++;
        end

        @(negedge lclk0);
        i_lfsr_state      = ST_IDLE;
        i_enable_detector = 0;
        wait_mb(3);

        check({lbl, ": o_error_done (die0)"},     done0);
        check({lbl, ": o_error_done (die1)"},     done1);
        check({lbl, ": o_per_lane_error==0 (d0)"}, pe0 === 16'h0000);
        check({lbl, ": o_per_lane_error==0 (d1)"}, pe1 === 16'h0000);
        ok = done0 && done1 && (pe0 === 16'h0000) && (pe1 === 16'h0000);
    endtask

    // Phase ACTIVE: full data transfer (Mapper → DDR → Demapper round-trip)
    task automatic run_flit_pair(
        input  logic [FLITW-1:0] f0,
        input  logic [FLITW-1:0] f1,
        input  string nm,
        output bit ok
    );
        bit got0, got1;
        int t;
        @(negedge lclk0);
        lp_data0 = f0;
        lp_data1 = f1;
        lp_valid0 = 1;
        lp_valid1 = 1;

        got0=0; got1=0; t=0;
        while (!(got0 && got1) && t < TO_MB_FLIT) begin
            @(posedge lclk0);
            // die0 RX should receive die1's flit
            if (pl_valid0 && (o_out_data0 === f1)) got0 = 1;
            // die1 RX should receive die0's flit
            if (pl_valid1 && (o_out_data1 === f0)) got1 = 1;
            t++;
        end
        lp_valid0 = 0;
        lp_valid1 = 0;

        check({nm, ": die0 received die1's flit"}, got0);
        check({nm, ": die1 received die0's flit"}, got1);
        ok = got0 && got1;
    endtask

    task automatic phase_active_test(output bit ok);
        bit ok_mapper0, ok_mapper1, ok_flit0, ok_flit1, ok_map;
        bit ready0, ready1;
        int t;
        logic [FLITW-1:0] flit_a, flit_b, flit_c;
        $display("  [ACTIVE data phase] t=%0t ps", $time);

        // Sync LFSRs before going active
        @(negedge lclk0);
        i_lfsr_state = ST_CLEAR;
        wait_mb(3);
        i_lfsr_state = ST_IDLE;
        wait_mb(2);

        @(negedge lclk0);
        i_lfsr_state = ST_DATA;
        i_mapper_en  = 1;
        lp_irdy      = 1;

        // Wait for both mappers to be ready
        ready0=0; ready1=0; t=0;
        while (!(ready0 && ready1) && t < TO_MB_FLIT) begin
            @(posedge lclk0);
            if (o_mapper_ready0) ready0 = 1;
            if (o_mapper_ready1) ready1 = 1;
            t++;
        end
        check("ACTIVE: o_mapper_ready (die0)", ready0);
        check("ACTIVE: o_mapper_ready (die1)", ready1);

        if (ready0 && ready1) begin
            // Build test flits
            for (int b = 0; b < N_BYTES; b++) begin
                flit_a[b*8 +: 8] = 8'(b + 1);
                flit_b[b*8 +: 8] = 8'(~b);
                flit_c[b*8 +: 8] = 8'(b ^ 8'hAA);
            end

            run_flit_pair(flit_a, flit_b, "Flit-1", ok_flit0);
            run_flit_pair(flit_b, flit_c, "Flit-2", ok_flit1);
            run_flit_pair(flit_c, flit_a, "Flit-3", ok_flit0);

            ok = ready0 && ready1 && ok_flit0 && ok_flit1;
        end else begin
            ok = 0;
        end

        lp_irdy      = 0;
        i_mapper_en  = 0;
        @(negedge lclk0);
        i_lfsr_state = ST_IDLE;
        wait_mb(5);
    endtask

    // =========================================================================
    // Full training scenario: CLK → VALID → PATTERN_LFSR → PER_LANE_ID → ACTIVE
    // =========================================================================
    task automatic fulltraining_happy_scenario(
        input  string scenario_name,
        output bit    reached_active
    );
        bit ok_clk, ok_vld, ok_pat, ok_lane, ok_data;
        int p, f;
        $display("\n── Scenario: %s  t=%0t ps ──", scenario_name, $time);

        link_reset(.embedded_clk(1));
        $display("  Reset released.");

        // 1. CLK pattern test
        phase_clk_test(ok_clk);
        if (!ok_clk) begin
            $display("  [ABORT] CLK phase failed — stopping scenario");
            reached_active = 0;
            return;
        end

        // 2. VALID pattern test
        phase_valid_test(.mode1(1), .ok(ok_vld));
        if (!ok_vld) begin
            $display("  [ABORT] VALID phase failed — stopping scenario");
            reached_active = 0;
            return;
        end

        // 3a. PATTERN_LFSR
        phase_data_test("PATTERN_LFSR", ST_PATTERN, ok_pat);
        // 3b. PER_LANE_ID
        phase_data_test("PER_LANE_ID",  ST_PERLANE, ok_lane);

        // 4. DATA_TRANSFER
        phase_active_test(ok_data);

        reached_active = ok_clk && ok_vld && ok_pat && ok_lane && ok_data;
        if (reached_active)
            $display("  ✓ Scenario %s : PASSED", scenario_name);
        else
            $display("  ✗ Scenario %s : FAILED", scenario_name);
    endtask

    // =========================================================================
    // Fault injection helpers
    // =========================================================================
    localparam int FAULT_NONE  = 0;
    localparam int FAULT_CLK   = 1;
    localparam int FAULT_VALID = 2;
    localparam int FAULT_DATA  = 3;

    task automatic inject(input int fault);
        case (fault)
            FAULT_CLK  : force d1_to_d0_ckp = 1'b0;
            FAULT_VALID: force d1_to_d0_vld  = d1_to_d0_ckp;
            FAULT_DATA : force d1_to_d0_data[3] = 1'b0;
            default    : ;
        endcase
    endtask

    task automatic uninject(input int fault);
        case (fault)
            FAULT_CLK  : release d1_to_d0_ckp;
            FAULT_VALID: release d1_to_d0_vld;
            FAULT_DATA : release d1_to_d0_data[3];
            default    : ;
        endcase
    endtask

    // =========================================================================
    // Fault-injection scenario
    // =========================================================================
    task automatic fault_scenario(
        input  string scenario_name,
        input  int    fault_id,
        input  string expected_abort_at,
        output bit    ok
    );
        bit ok_clk, ok_vld, ok_pat;
        $display("\n── Fault Scenario: %s  (%s)  t=%0t ps ──",
                 scenario_name, expected_abort_at, $time);
        inject(fault_id);

        link_reset(.embedded_clk(1));

        phase_clk_test(ok_clk);

        if (!ok_clk && fault_id == FAULT_CLK) begin
            ok = 1;
            $display("  ✓ Training aborted at CLK as expected.");
            uninject(fault_id);
            return;
        end

        phase_valid_test(.mode1(1), .ok(ok_vld));

        if (!ok_vld && fault_id == FAULT_VALID) begin
            ok = 1;
            $display("  ✓ Training aborted at VALID as expected.");
            uninject(fault_id);
            return;
        end

        phase_data_test("PATTERN_LFSR", ST_PATTERN, ok_pat);

        if (!ok_pat && fault_id == FAULT_DATA) begin
            ok = 1;
            $display("  ✓ Training aborted at PATTERN_LFSR as expected.");
            uninject(fault_id);
            return;
        end

        // If we reach here, fault did not abort training — test FAILED
        ok = 0;
        $display("  ✗ Fault %0d did NOT abort training (expected abort at %s).",
                 fault_id, expected_abort_at);
        uninject(fault_id);
    endtask

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        #(WD_PS);
        $display("\n[WATCHDOG] Simulation exceeded %0d ps — terminating.\n", WD_PS);
        $display("  PASS: %0d   FAIL: %0d (watchdog = 1 extra FAIL)",
                 total_pass, total_fail + 1);
        $finish;
    end

    // =========================================================================
    // Monitors
    // =========================================================================
    always @(posedge lclk0) begin
        if (o_clk_done0)     $display("[MON-d0] o_clk_done    t=%0t", $time);
        if (o_valid_done0)   $display("[MON-d0] o_valid_done  t=%0t", $time);
        if (o_lfsr_tx_done0) $display("[MON-d0] o_lfsr_tx_done t=%0t", $time);
        if (o_error_done0)   $display("[MON-d0] o_error_done pe=%04h ec=%0d t=%0t",
                                       o_per_lane_error0, o_error_counter0, $time);
        if (pl_valid0)       $display("[MON-d0] pl_valid out[63:0]=%016h  t=%0t",
                                       o_out_data0[63:0], $time);
        if (detection_result0) $display("[MON-d0] detection_result=1  t=%0t", $time);
    end
    always @(posedge lclk1) begin
        if (o_clk_done1)     $display("[MON-d1] o_clk_done    t=%0t", $time);
        if (o_valid_done1)   $display("[MON-d1] o_valid_done  t=%0t", $time);
        if (o_lfsr_tx_done1) $display("[MON-d1] o_lfsr_tx_done t=%0t", $time);
        if (o_error_done1)   $display("[MON-d1] o_error_done pe=%04h ec=%0d t=%0t",
                                       o_per_lane_error1, o_error_counter1, $time);
        if (pl_valid1)       $display("[MON-d1] pl_valid out[63:0]=%016h  t=%0t",
                                       o_out_data1[63:0], $time);
        if (detection_result1) $display("[MON-d1] detection_result=1  t=%0t", $time);
    end

    // =========================================================================
    // Main stimulus
    // =========================================================================
    initial begin : tb_main
        bit reached, ok;
        int sc_pass, sc_fail;
        sc_pass = 0; sc_fail = 0;

        $display("=============================================================");
        $display("  mb_die2die Testbench — UCIe 3.0 Main-Band");
        $display("  PLL: 2 GHz | Width: x16 | PLL/MB ratio: 16");
        $display("=============================================================\n");

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 1: Full happy-path training
        // ─────────────────────────────────────────────────────────────────────
        i_pll_en = 1;
        fulltraining_happy_scenario("fulltraining_happy", reached);
        check("Scenario 1: reached ACTIVE", reached);
        if (reached) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 2: CONSEC_16 valid detection mode
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Scenario 2: VALID CONSEC_16 mode ──");
        link_reset(.embedded_clk(1));
        phase_valid_test(.mode1(0), .ok(ok));
        check("Scenario 2: VALID CONSEC_16 detected (both dies)", ok);
        if (ok) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 3: Fault — dead clock on die1→die0 link
        // ─────────────────────────────────────────────────────────────────────
        fault_scenario("fault:dead_clock_d1to0", FAULT_CLK, "CLK", ok);
        check("Scenario 3: dead clock aborts at CLK", ok);
        if (ok) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 4: Fault — bad valid lane on die1→die0 link
        // ─────────────────────────────────────────────────────────────────────
        fault_scenario("fault:bad_valid_d1to0", FAULT_VALID, "VALID", ok);
        check("Scenario 4: bad valid aborts at VALID", ok);
        if (ok) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 5: Fault — stuck data lane[3] on die1→die0 link
        // ─────────────────────────────────────────────────────────────────────
        fault_scenario("fault:stuck_data_d1to0", FAULT_DATA, "PATTERN_LFSR", ok);
        check("Scenario 5: stuck data aborts at PATTERN_LFSR", ok);
        if (ok) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 6: Lane reversal sweep (W_ALL16 + reversal)
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Scenario 6: Lane reversal (W_ALL16) ──");
        link_reset(.embedded_clk(1));
        tb_reversal_en = 1;
        die0_width_deg_tx = W_ALL16; die0_width_deg_rx = W_ALL16;
        die1_width_deg_tx = W_ALL16; die1_width_deg_rx = W_ALL16;
        phase_data_test("PATTERN_LFSR+reversal", ST_PATTERN, ok);
        check("Scenario 6: PATTERN_LFSR with reversal", ok);
        tb_reversal_en = 0;
        if (ok) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 7: Degraded width — W_0TO7
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Scenario 7: Degraded W_0TO7 ──");
        link_reset(.embedded_clk(1));
        die0_width_deg_tx = W_0TO7; die0_width_deg_rx = W_0TO7;
        die1_width_deg_tx = W_0TO7; die1_width_deg_rx = W_0TO7;
        phase_data_test("PATTERN_LFSR W_0TO7", ST_PATTERN, ok);
        check("Scenario 7: PATTERN_LFSR W_0TO7 no errors", ok);
        if (ok) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 8: Degraded width — W_8TO15
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Scenario 8: Degraded W_8TO15 ──");
        link_reset(.embedded_clk(1));
        die0_width_deg_tx = W_8TO15; die0_width_deg_rx = W_8TO15;
        die1_width_deg_tx = W_8TO15; die1_width_deg_rx = W_8TO15;
        phase_data_test("PATTERN_LFSR W_8TO15", ST_PATTERN, ok);
        check("Scenario 8: PATTERN_LFSR W_8TO15 no errors", ok);
        if (ok) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 9: Degraded width — W_0TO3
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Scenario 9: Degraded W_0TO3 ──");
        link_reset(.embedded_clk(1));
        die0_width_deg_tx = W_0TO3; die0_width_deg_rx = W_0TO3;
        die1_width_deg_tx = W_0TO3; die1_width_deg_rx = W_0TO3;
        phase_data_test("PATTERN_LFSR W_0TO3", ST_PATTERN, ok);
        check("Scenario 9: PATTERN_LFSR W_0TO3 no errors", ok);
        if (ok) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Scenario 10: Full training + active data transfer (2nd run)
        // ─────────────────────────────────────────────────────────────────────
        fulltraining_happy_scenario("fulltraining_2nd_run", reached);
        check("Scenario 10: 2nd full training reached ACTIVE", reached);
        if (reached) sc_pass++; else sc_fail++;

        // ─────────────────────────────────────────────────────────────────────
        // Summary
        // ─────────────────────────────────────────────────────────────────────
        wait_mb(5);
        $display("\n=============================================================");
        $display("  mb_die2die SIMULATION COMPLETE — t = %0t ps", $time);
        $display("  Scenarios : %0d passed,  %0d failed", sc_pass, sc_fail);
        $display("  Checks    : %0d passed,  %0d failed  (total %0d)",
                 total_pass, total_fail, total_checks);
        $display("=============================================================");

        if (total_fail == 0 && sc_fail == 0) begin
            $display("  *** ALL TESTS PASSED ***");
            $display("  >>> PASS : clean run brought BOTH dies to ACTIVE; every fault aborted training <<<");
        end else begin
            $display("  *** %0d TEST(S) FAILED ***", total_fail + sc_fail);
        end
        $display("");
        $finish;
    end : tb_main

endmodule
