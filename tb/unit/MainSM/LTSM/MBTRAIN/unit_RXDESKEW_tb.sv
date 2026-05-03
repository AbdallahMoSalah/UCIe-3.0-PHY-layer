`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_RXDESKEW_tb
// Purpose   : Self-checking testbench for unit_RXDESKEW FSM.
//             Covers spec §4.5.3.4.10 MBTRAIN.RXDESKEW.
// =============================================================================
module unit_RXDESKEW_tb ();
    import UCIe_pkg::*;

    parameter integer LCLK_PERIOD              = 1000      ;
    parameter integer TIMEOUT_CYCLES           = 2_000_000 ;
    parameter integer ANALOG_SETTLE_CYCLES     = 10        ;
    parameter integer RANDOMIZATION_ITERATIONS = 300       ;
    
    reg lclk;
    reg rst_n;
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    unit_RXDESKEW unit_RXDESKEW_inst (
        .rxdeskew_if (intf),
        .d2c_if      (intf)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // =========================================================================
    // State & SB message monitoring
    // =========================================================================
    typedef enum reg [4:0] {
        RXDESKEW_IDLE                  = 5'd0 ,
        RXDESKEW_START_REQ_RESP        = 5'd1 ,
        RXDESKEW_CHOOSE_PRESET         = 5'd2 ,
        RXDESKEW_PRESET_REQ_RESP       = 5'd3 ,
        RXDESKEW_APPLY_SKEW_SWEEP      = 5'd4 ,
        RXDESKEW_EXIT_TO_DTC1_REQ_RESP = 5'd9 ,
        RXDESKEW_ARC_COUNT             = 5'd10,
        TO_DTC1                        = 5'd11,
        RXDESKEW_END_REQ_RESP          = 5'd12,
        TO_DTC2                        = 5'd13,
        TO_TRAINERROR                  = 5'd14
    } fsm_state_t;

    fsm_state_t current_state;
    fsm_state_t prev_printed;
    assign current_state = fsm_state_t'(unit_RXDESKEW_inst.current_state);

    function string get_short_msg_name(msg_no_e msg);
        case (msg)
            MBTRAIN_RXDESKEW_start_req                                              : return "START_REQ";
            MBTRAIN_RXDESKEW_start_resp                                             : return "START_RESP";
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req : return "PRESET_REQ";
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp: return "PRESET_RESP";
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req                           : return "EXIT_DTC1_REQ";
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp                          : return "EXIT_DTC1_RESP";
            MBTRAIN_RXDESKEW_end_req                                                : return "END_REQ";
            MBTRAIN_RXDESKEW_end_resp                                               : return "END_RESP";
            TRAINERROR_Entry_req                                                    : return "TRAINERROR_REQ";
            Start_Rx_Init_D_to_C_point_test_req,
            Start_Rx_Init_D_to_C_point_test_resp,
            Rx_Init_D_to_C_Tx_Count_Done_req,
            Rx_Init_D_to_C_Tx_Count_Done_resp,
            End_Rx_Init_D_to_C_point_test_req,
            End_Rx_Init_D_to_C_point_test_resp                                      : return "D2C_SWEEP";
            default                                                                 : return "NO_MSG";
        endcase
    endfunction

    // Shift register: keep track of last 3 received SB messages for display
    msg_no_e rx_msg_log [2:0];    // [0]=latest, [1]=prev, [2]=prev-prev
    logic rx_sb_msg_valid_d;
    
    always @(posedge lclk) begin
        rx_sb_msg_valid_d <= intf.rx_sb_msg_valid;
        if (intf.rx_sb_msg_valid && !rx_sb_msg_valid_d) begin
            rx_msg_log[2] <= rx_msg_log[1];
            rx_msg_log[1] <= rx_msg_log[0];
            rx_msg_log[0] <= intf.rx_sb_msg;
        end
    end

    // Print state changes with last-3 received SB message context
    always @(posedge lclk) begin
        if (rst_n && current_state !== prev_printed) begin
            $display("# %9t ps : State -> \"%-30s\" | last_rx[ [0]:%-15s, [1]:%-15s, [2]:%-15s].",
                $realtime(), current_state.name(),
                get_short_msg_name(rx_msg_log[0]),
                get_short_msg_name(rx_msg_log[1]),
                get_short_msg_name(rx_msg_log[2]));
            prev_printed <= current_state;
        end
    end


    // =========================================================================
    // Speed & counters
    // =========================================================================
    reg [2:0] tb_speed;
    assign intf.phy_negotiated_speed = tb_speed;

    integer lclk_counter  = 0;
    integer success_count = 0;
    integer fail_count    = 0;
    reg     lclk_ctr_en   = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_ctr_en) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    logic [15:0] tb_narrow_lane_mask;
    integer      tb_narrow_lane_width;

    // =========================================================================
    // Full hardware reset (used only at testbench start and after TRAINERROR)
    // =========================================================================
    task reset();
        rst_n                                 = 0;
        intf.tb_aggr_err                      = 0;
        intf.tb_perlane_err                   = 0;
        intf.tb_val_err                       = 0;
        intf.tb_clk_err                       = 0;
        intf.tb_wait_timeout                  = 0;
        intf.tb_wrong_sb_msg_en               = 0;
        intf.tb_wrong_sb_msg                  = NOTHING;
        intf.tb_rx_msginfo                    = 16'h0;
        intf.tb_rx_data_field                 = 64'h0;
        intf.rxdeskew_en                      = 0;
        intf.mb_rx_data_lane_mask             = 3'b011;
        intf.valtraincenter_fail_flag         = 0;
        intf.partner_valtraincenter_fail_flag = 0;
        tb_narrow_lane_mask                   = 16'h0000;
        tb_narrow_lane_width                  = 127;
        tb_speed                              = 3'd2;
        prev_printed                          = RXDESKEW_IDLE;
        rx_msg_log[0]                         = NOTHING;
        rx_msg_log[1]                         = NOTHING;
        rx_msg_log[2]                         = NOTHING;
        #(LCLK_PERIOD * 2); rst_n = 1;
        #(LCLK_PERIOD * 2);
    endtask

    // =========================================================================
    // Soft inter-test gap: deassert rxdeskew_en briefly so the FSM settles
    // back through IDLE (auto-resets preset_search_cnt, dtc1_arc_cnt, etc.)
    // Does NOT toggle rst_n, so old_preset_saved / best_deskew_code persist.
    // =========================================================================
    task soft_gap(input integer gap_cycles = 10);
        intf.rxdeskew_en        = 0;
        intf.tb_wait_timeout    = 0;
        intf.tb_wrong_sb_msg_en = 0;
        intf.valtraincenter_fail_flag = 0;
        tb_narrow_lane_mask     = 16'h0000;
        tb_narrow_lane_width    = 127;
        lclk_ctr_en = 0;
        repeat (gap_cycles) @(posedge lclk);
        #1step;
    endtask

    // =========================================================================
    // Sweep mock controls (shared by error-injection thread)
    // =========================================================================
    logic [2:0] mock_target_preset;
    integer     mock_target_start;
    integer     mock_target_end;
    integer     mock_other_start;
    integer     mock_other_end;

    // =========================================================================
    // start_test: drive one RXDESKEW run and check the exit condition.
    // =========================================================================
    task start_test (
            input integer abort_after       = TIMEOUT_CYCLES,
            input integer wrong_sb_after    = TIMEOUT_CYCLES,
            input msg_no_e wrong_msg        = NOTHING,
            input logic   inject_valtrain_fail = 0,
            input logic   inject_partner_concurrent = 0, // inject diverging partner req
            input logic [15:0] inject_lane_fail = 16'h0000, // Persistent lane failure mask

            // Sweep mock controls
            input logic [2:0] target_preset       = 3'd0,
            input integer     target_range_start  = 0,
            input integer     target_range_end    = 127,
            input integer     other_range_start   = 0,
            input integer     other_range_end     = 30,

            // Expected FSM exits
            input logic expect_dtc2       = 0,
            input logic expect_dtc1       = 0,
            input logic expect_trainerror = 0
        );

        mock_target_preset = target_preset;
        mock_target_start  = target_range_start;
        mock_target_end    = target_range_end;
        mock_other_start   = other_range_start;
        mock_other_end     = other_range_end;
        lclk_ctr_en        = 1;

        fork : TEST
            // ------------------------------------------------------------------
            // Thread A: checker – wait for FSM exit, verify outcome
            // ------------------------------------------------------------------
            begin
                intf.rxdeskew_en = 1'b1;
                wait (intf.rxdeskew_done || intf.trainerror_req || intf.datatraincenter1_req);
                @(posedge lclk); #1step;
                intf.rxdeskew_en = 1'b0;

                if (expect_trainerror && !intf.trainerror_req) begin
                    $display("\t *** FAIL *** expected TRAINERROR"); fail_count++;
                    disable TEST;
                end
                if (expect_dtc1 && !intf.datatraincenter1_req) begin
                    $display("\t *** FAIL *** expected DTC1"); fail_count++;
                    disable TEST;
                end
                if (expect_dtc2 && !(intf.rxdeskew_done && !intf.trainerror_req)) begin
                    $display("\t *** FAIL *** expected DTC2"); fail_count++;
                    disable TEST;
                end

                success_count++;
                $display("# __(Success=%0d, Fail=%0d, lclk_cycles=%0d)__\n",
                    success_count, fail_count, lclk_counter);
                disable TEST;
            end

            // ------------------------------------------------------------------
            // Thread B: per-lane error injection (drives the PI mock eye)
            // ------------------------------------------------------------------
            begin
                forever begin
                    @(posedge lclk);
                    if (inject_valtrain_fail && lclk_counter > 500)
                        intf.valtraincenter_fail_flag = 1'b1;

                    intf.tb_perlane_err = 16'hFFFF; // default: all errors
                    if (unit_RXDESKEW_inst.current_state == unit_RXDESKEW_inst.RXDESKEW_APPLY_SKEW_SWEEP &&
                            unit_RXDESKEW_inst.pi_in_sweep) begin
                        automatic logic [6:0] code   = intf.phy_rx_deskew_ctrl[0];
                        automatic logic [2:0] preset = unit_RXDESKEW_inst.partner_preset;
                        
                        // Default eye for all lanes (target or other)
                        if (preset == mock_target_preset &&
                                code >= mock_target_start && code <= mock_target_end)
                            intf.tb_perlane_err = 16'h0000;
                        else if (preset != mock_target_preset &&
                                code >= mock_other_start && code <= mock_other_end)
                            intf.tb_perlane_err = 16'h0000;
                        
                        // Apply lane failures (force error regardless of eye)
                        intf.tb_perlane_err |= inject_lane_fail;

                        // Support "narrow lane" simulation: if a bit is set in tb_narrow_lane_mask,
                        // that lane only passes within tb_narrow_lane_range.
                        for (int i=0; i<16; i++) begin
                            if (tb_narrow_lane_mask[i]) begin
                                if (preset == mock_target_preset) begin
                                    if (code < mock_target_start || code > (mock_target_start + tb_narrow_lane_width))
                                        intf.tb_perlane_err[i] = 1'b1;
                                end else begin
                                    if (code < mock_other_start || code > (mock_other_start + tb_narrow_lane_width))
                                        intf.tb_perlane_err[i] = 1'b1;
                                end
                            end
                        end
                    end
                end
            end

            // ------------------------------------------------------------------
            // Thread C: wrong-SB injector (partner TRAINERROR / erroneous msg)
            // ------------------------------------------------------------------
            begin
                if (wrong_sb_after < TIMEOUT_CYCLES) begin
                    for (int i = 0; i < wrong_sb_after; i++) @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 1;
                    intf.tb_wrong_sb_msg    = wrong_msg;
                end
            end

            // ------------------------------------------------------------------
            // Thread D: partner concurrent/diverging message injector.
            // ------------------------------------------------------------------
            begin
                if (inject_partner_concurrent) begin
                    // Wait until sweep exits
                    wait (unit_RXDESKEW_inst.current_state != unit_RXDESKEW_inst.RXDESKEW_APPLY_SKEW_SWEEP &&
                          unit_RXDESKEW_inst.current_state != unit_RXDESKEW_inst.RXDESKEW_IDLE);
                    wait (unit_RXDESKEW_inst.current_state == unit_RXDESKEW_inst.RXDESKEW_APPLY_SKEW_SWEEP);
                    // Wait for sweep to finish
                    wait (unit_RXDESKEW_inst.current_state != unit_RXDESKEW_inst.RXDESKEW_APPLY_SKEW_SWEEP);
                    // Inject partner's end_req concurrently (partner reached end before us)
                    repeat (5) @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 1;
                    intf.tb_wrong_sb_msg    = MBTRAIN_RXDESKEW_end_req;
                    $display("#   [TB] Partner concurrent %-15s injected at %0t ps", get_short_msg_name(intf.tb_wrong_sb_msg), $realtime());
                    repeat (200) @(posedge lclk);
                    intf.tb_wrong_sb_msg_en = 0;
                    intf.tb_wrong_sb_msg    = NOTHING;
                end
            end

            // ------------------------------------------------------------------
            // Thread E: timeout injector
            // ------------------------------------------------------------------
            begin
                if (abort_after < TIMEOUT_CYCLES) begin
                    for (int i = 0; i < abort_after; i++) @(posedge lclk);
                    intf.tb_wait_timeout = 1;
                end
            end
        join

        lclk_ctr_en                           = 0;
        intf.tb_wait_timeout                  = 0;
        intf.tb_wrong_sb_msg_en               = 0;
        intf.tb_rx_msginfo                    = 16'h0;
        intf.tb_rx_data_field                 = 64'h0;
        intf.valtraincenter_fail_flag         = 0;
        intf.partner_valtraincenter_fail_flag = 0;
        @(posedge lclk); #1step;
    endtask

    // =========================================================================
    // DTC1 arc scenario task
    // =========================================================================
    // Scenario:
    //   Arc 0: HS, all presets narrow (other_start/end range < 63).
    //          best_preset_saved = arc0_best (≠ old_preset_saved=0) → EXIT_DTC1 → DTC1.
    //   Gap:   rxdeskew_en deasserted 10 cycles (FSM: DTC1 → IDLE, resets cnt but NOT
    //          old_preset_saved which captures best from arc 0).
    //   Arc 1: HS, all presets still narrow. FSM again tries all presets.
    //          Goes EXIT_DTC1 → RXDESKEW_ARC_COUNT → DTC1.
    //   Gap:   same soft gap.
    //   Arc 2: HS, preset=2 now has wide eye → DTC2.
    // =========================================================================
    task run_dtc1_arc_scenario();
        // -----------------------------------------------------------------------
        // Arc 0: HS, all presets have a tiny eye (< MIN_DESIRED_SWEEP_RANGE=63).
        // Target preset=1, eye width=70-40=30 codes (narrow <63).
        // All other presets: eye 0-5=5 codes.
        // FSM tries presets 0→5, best_preset_saved=1 (widest narrow eye=30).
        // old_preset_saved=0 initially → best(1)≠old(0) → EXIT_DTC1 → DTC1.
        // -----------------------------------------------------------------------
        $display("# [DTC1-Arc-Scenario] Arc 0: all narrow, best=preset1 -> DTC1.");
        // ---- Arc 0 ----
        $display("# [DTC1-Arc-Scenario] Arc 0: all narrow, best=preset1 -> DTC1.");
        // target_preset=1, narrow range (width~30 < 63), other=tiny
        start_test(
            .target_preset(3'd1), .target_range_start(40), .target_range_end(70),
            .other_range_start(0), .other_range_end(5),
            .expect_dtc1(1)
        );

        // Soft gap: deassert rxdeskew_en so FSM goes DTC1→IDLE (resets cnts, NOT old_preset_saved)
        soft_gap(100);

        // ---- Arc 1 ----
        $display("# [DTC1-Arc-Scenario] Arc 1: all narrow again -> RXDESKEW_ARC_COUNT -> DTC1.");
        // Same narrow: preset1 still best, but old_preset_saved=1 now (from arc0).
        // Since best==old → FSM picks END_REQ (DTC2)... unless we pick a DIFFERENT best.
        // To force another DTC1, make preset3 the new best (wider than preset1 this time).
        start_test(
            .target_preset(3'd3), .target_range_start(35), .target_range_end(62),
            .other_range_start(0), .other_range_end(5),
            .expect_dtc1(1)
        );

        soft_gap(100);

        // ---- Arc 2: preset=2 finally wins with wide eye -> DTC2 ----
        $display("# [DTC1-Arc-Scenario] Arc 2: preset=2 wide eye -> DTC2.");
        start_test(
            .target_preset(3'd2), .target_range_start(10), .target_range_end(110),
            .other_range_start(0), .other_range_end(5),
            .expect_dtc2(1)
        );
    endtask

    // =========================================================================
    // MAIN TEST PROGRAM
    // =========================================================================
    integer scenario = 1;

    initial begin
        reset();

        // --- Scenario 1: Low Speed, Clean run ---
        $display("# =========> Test Scenario (%0d): Low Speed (12 GT/s), Clean run -> DTC2. <=========", scenario++);
        tb_speed = 3'd2;
        start_test(.target_range_end(127), .expect_dtc2(1));
        reset();

        // --- Scenario 2: Low Speed, Valtrain Fail -> DTC2 ---
        $display("# =========> Test Scenario (%0d): Low Speed, Valtrain Fail -> DTC2. <=========", scenario++);
        tb_speed = 3'd2;
        start_test(.inject_valtrain_fail(1), .expect_dtc2(1));
        reset();

        // --- Scenario 3: 8ms Timeout -> TRAINERROR ---
        $display("# =========> Test Scenario (%0d): 8ms Timeout -> TRAINERROR. <=========", scenario++);
        tb_speed = 3'd2;
        start_test(.abort_after(500), .expect_trainerror(1));
        reset();

        // --- Scenario 4: Partner TRAINERROR -> TRAINERROR ---
        $display("# =========> Test Scenario (%0d): Partner TRAINERROR -> TRAINERROR. <=========", scenario++);
        tb_speed = 3'd2;
        start_test(.wrong_sb_after(1000), .wrong_msg(TRAINERROR_Entry_req), .expect_trainerror(1));
        reset();

        // --- Scenario 5: HS Wide Eye Preset 0 -> DTC2 ---
        $display("# =========> Test Scenario (%0d): High Speed (64 GT/s), Wide Eye Preset 0 -> DTC2. <=========", scenario++);
        tb_speed = 3'd7;
        start_test(.target_preset(3'd0), .target_range_start(0), .target_range_end(127), .expect_dtc2(1));
        reset();

        // --- Scenario 6: HS Narrow, best=Preset3 -> DTC1 ---
        $display("# =========> Test Scenario (%0d): High Speed, Best=Preset3 narrow -> DTC1. <=========", scenario++);
        tb_speed = 3'd7;
        start_test(.target_preset(3'd3), .target_range_start(30), .target_range_end(80),
                   .other_range_start(0), .other_range_end(20), .expect_dtc1(1));
        reset();

        // --- Scenario 7: HS Narrow, best=Preset0 (already best) -> DTC2 ---
        $display("# =========> Test Scenario (%0d): High Speed, Best=Preset0 narrow -> DTC2. <=========", scenario++);
        tb_speed = 3'd7;
        start_test(.target_preset(3'd0), .target_range_start(20), .target_range_end(70),
                   .other_range_start(0), .other_range_end(20), .expect_dtc2(1));
        reset();

        // --- Scenarios 8-17: Original randomized batch ---
        for (int s = 8; s <= 17; s++) begin
            bit is_hs; bit [2:0] rnd_speed, rnd_preset;
            integer trs, tre, ors, ore, width;
            bit exp_dtc2, exp_dtc1, is_wide;
            is_hs = $urandom_range(0,1); rnd_speed = is_hs ? 3'd7 : 3'd2;
            rnd_preset = 3'($urandom_range(0,5));
            trs = $urandom_range(0,40); tre = $urandom_range(80,127);
            ors = $urandom_range(0,10); ore = $urandom_range(20,30);
            width = tre - trs; is_wide = (width > 62);
            if (!is_hs) begin exp_dtc2=1; exp_dtc1=0; end
            else if (is_wide) begin exp_dtc2=1; exp_dtc1=0; end
            else if (rnd_preset==0) begin exp_dtc2=1; exp_dtc1=0; end
            else begin exp_dtc1=1; exp_dtc2=0; end
            $display("# =========> Test Scenario (%0d): HS=%0b Preset=%0d Range=[%0d:%0d] -> DTC2=%0b DTC1=%0b. <=========",
                scenario++, is_hs, rnd_preset, trs, tre, exp_dtc2, exp_dtc1);
            tb_speed = rnd_speed;
            start_test(.target_preset(rnd_preset), .target_range_start(trs), .target_range_end(tre),
                       .other_range_start(ors), .other_range_end(ore),
                       .expect_dtc2(exp_dtc2), .expect_dtc1(exp_dtc1));
            reset();
        end

        // --- Scenario 18: Dual-Accept NO_MSG path ---
        $display("# =========> Test Scenario (%0d): HS Dual-Accept NO_MSG path -> DTC2. <=========", scenario++);
        tb_speed = 3'd7; intf.tb_rx_msginfo = 16'h0000;
        fork : DUAL_ACCEPT_MONITOR
            begin
                forever begin
                    @(posedge lclk);
                    if (unit_RXDESKEW_inst.current_state == unit_RXDESKEW_inst.RXDESKEW_APPLY_SKEW_SWEEP &&
                            intf.tx_sb_msg_valid) begin
                        $display("\t *** FAIL *** Spurious tx_sb_msg_valid during APPLY_SKEW_SWEEP (NO_MSG broken!)");
                        fail_count++;
                    end
                end
            end
            begin
                start_test(.target_preset(3'd0), .target_range_start(0), .target_range_end(127), .expect_dtc2(1));
                disable DUAL_ACCEPT_MONITOR;
            end
        join
        reset();

        // =====================================================================
        // Scenario 19: DTC1 MULTI-ARC SCENARIO
        // Proves: all narrow → DTC1 → (soft gap) → still narrow → ARC_COUNT →
        //         DTC1 again → (soft gap) → preset=2 wide → DTC2.
        // RTL auto-resets: preset_search_cnt, dtc1_arc_cnt on IDLE re-enable.
        // RTL persists  : old_preset_saved (OLD_PRESET_PROC in RTL).
        // =====================================================================
        $display("# =========> Test Scenario (%0d): DTC1 Multi-Arc (all-narrow → DTC1x2 → DTC2). <=========", scenario++);
        tb_speed = 3'd7;
        run_dtc1_arc_scenario();
        reset();

        
        // =====================================================================
        // Scenario (20): 4-Arc failure due to lane failure.
        // We simulate Lane 0 being narrow (failed eye).
        // To force 4 arcs, we need the "best" preset to improve slightly in each arc.
        // =====================================================================
        $display("# =========> Scenario (%0d): Forced 4-Arc Failure (Lane 0 Narrow) <=========", scenario++);
        begin
            reset();
            tb_speed = 3'd7; 
            intf.tb_rx_msginfo = 16'h0000;
            
            // Loop 1: Lane 0 is narrow. Preset 1 is slightly better than others.
            // P1: L0 width 10. Others: L0 width 5. All other lanes: width 80.
            // MIN(P1)=10, MIN(others)=5. Best=P1. Loop -> DTC1.
            tb_narrow_lane_mask = 16'h0001; tb_narrow_lane_width = 10;
            start_test(.target_preset(1), .target_range_start(0), .target_range_end(80),
                       .other_range_start(0), .other_range_end(5), .expect_dtc1(1), .expect_dtc2(0));
            soft_gap(100);

            // Loop 2: Preset 2 is now even better (L0 width 15).
            tb_narrow_lane_mask = 16'h0001; tb_narrow_lane_width = 15;
            start_test(.target_preset(2), .target_range_start(0), .target_range_end(80),
                       .other_range_start(0), .other_range_end(10), .expect_dtc1(1), .expect_dtc2(0));
            soft_gap(100);

            // Loop 3: Preset 3 is now even better (L0 width 20).
            tb_narrow_lane_mask = 16'h0001; tb_narrow_lane_width = 20;
            start_test(.target_preset(3), .target_range_start(0), .target_range_end(80),
                       .other_range_start(0), .other_range_end(15), .expect_dtc1(1), .expect_dtc2(0));
            soft_gap(100);

            // Loop 4: Preset 4 is now even better (L0 width 25).
            tb_narrow_lane_mask = 16'h0001; tb_narrow_lane_width = 25;
            start_test(.target_preset(4), .target_range_start(0), .target_range_end(80),
                       .other_range_start(0), .other_range_end(20), .expect_dtc1(1), .expect_dtc2(0));
            soft_gap(100);

            // Loop 5: MAX_ARC_LIMIT (4) reached. Exit to DTC2 even if P5 is better.
            tb_narrow_lane_mask = 16'h0001; tb_narrow_lane_width = 30;
            start_test(.target_preset(5), .target_range_start(0), .target_range_end(80),
                       .other_range_start(0), .other_range_end(25), .expect_dtc1(0), .expect_dtc2(1));
        end

        reset();

        // =====================================================================
        // Scenarios 21 to (RANDOMIZATION_ITERATIONS+21): Fully Randomized tests WITHOUT reset() between runs.
        // Covers:
        // - Random target range width (can be wide or narrow)
        // - Random data lane failures (causing artificially narrow sweeps)
        // - Dynamic DTC1 or DTC2 prediction based on historical best_preset
        // - Concurrent partner message injections
        // =====================================================================
        $display("# =========> Fully Randomized scenarios (no hard reset between runs). <=========");
        tb_speed = 3'd7; // stay HS for the whole block
        intf.tb_rx_msginfo = 16'h0000;
        
        begin
            static bit [2:0] last_best_preset = 3'd2; // From Scenario 19 (which picked preset 2)
            static int       tb_arc_cnt       = 0;
            
            for (int s = 0; s < RANDOMIZATION_ITERATIONS; s++) begin
                bit [2:0]  rnd_preset;
                integer    target_range_start, target_range_end, other_range_start, other_range_end, width, other_width;
                bit        exp_dtc2, exp_dtc1, is_wide;
                bit        inject_concurrent;
                logic [15:0] lane_fail_mask;

                rnd_preset         = 3'($urandom_range(0, 5));
                target_range_start = $urandom_range(0, 40);
                target_range_end   = target_range_start + $urandom_range(10, 100); // Fully random width (10 to 100)
                other_range_start  = $urandom_range(0, 10);
                other_range_end    = $urandom_range(20, 30); // Keep other ranges small (width 10-40) so target usually wins
                inject_concurrent  = $urandom_range(0, 1);
                lane_fail_mask     = ($urandom_range(0, 100) < 15) ? 16'h0001 : 16'h0000; // 15% chance to kill lane 0
                
                width       = target_range_end - target_range_start;
                other_width = other_range_end - other_range_start;
                
                if (lane_fail_mask != 16'h0000) begin
                    width       = 0; // Lane failure causes overall eye width to be 0
                    other_width = 0;
                end
                
                begin
                    bit [2:0] actual_best_preset;
                    integer   best_width;
                    
                    if (width > other_width) begin
                        actual_best_preset = rnd_preset;
                        best_width         = width;
                    end else if (width == other_width) begin
                        actual_best_preset = 3'd5; // All have the same width, last one evaluated (5) wins due to >=
                        best_width         = width;
                    end else begin
                        // other_width > width.
                        best_width = other_width;
                        if (rnd_preset == 3'd5) begin
                            actual_best_preset = 3'd4; // 0,1,2,3,4 have other_width. 4 is the last.
                        end else begin
                            actual_best_preset = 3'd5; // 5 has other_width. 5 is the last evaluated.
                        end
                    end
                    
                    is_wide = (best_width > 62);
                    
                    if (is_wide) begin
                        // Eye is wide. Goes straight to DTC2.
                        exp_dtc2 = 1; exp_dtc1 = 0;
                        last_best_preset = 3'd0; // RTL clears old_preset_saved on TO_DTC2
                        tb_arc_cnt       = 0;    // RTL clears arc counter on TO_DTC2
                    end else begin
                        // Eye is narrow.
                        if (tb_arc_cnt == 4) begin
                            // MAX_ARC_LIMIT reached! Forced to DTC2!
                            exp_dtc2 = 1; exp_dtc1 = 0;
                            last_best_preset = 3'd0;
                            tb_arc_cnt       = 0;
                        end else if (actual_best_preset == last_best_preset) begin
                            // Found the same narrow best preset twice -> go to DTC2
                            exp_dtc2 = 1; exp_dtc1 = 0;
                            last_best_preset = 3'd0; // RTL clears old_preset_saved on TO_DTC2
                            tb_arc_cnt       = 0;
                        end else begin
                            // Need another sweep -> go to DTC1
                            exp_dtc1 = 1; exp_dtc2 = 0;
                            last_best_preset = actual_best_preset; // RTL captures best_preset_saved on TO_DTC1
                            tb_arc_cnt++;
                        end
                    end
                end

                $display("# =========> Test Scenario (%0d): HS Preset=%0d Range=[%0d:%0d] LaneFail=%0b ConcurrentPtn=%0d -> %s. <=========",
                    scenario++, rnd_preset, target_range_start, target_range_end, (lane_fail_mask!=0), inject_concurrent, (exp_dtc1) ? "DTC1" : "DTC2");

                // Soft gap instead of hard reset: FSM goes through IDLE, auto-resets counters
                soft_gap(100);

            start_test(
                .target_preset(rnd_preset),
                .target_range_start(target_range_start),
                .target_range_end(target_range_end),
                .other_range_start(other_range_start),
                .other_range_end(other_range_end),
                .expect_dtc2(exp_dtc2),
                .expect_dtc1(exp_dtc1),
                .inject_partner_concurrent(inject_concurrent),
                .inject_lane_fail(lane_fail_mask)
            );
        end
        end


        // -------------------------------------------------------------------------
        // Final report
        // -------------------------------------------------------------------------
        if (fail_count == 0) begin
            $display("        ============================================       ");
            $display("      ==============                    ==============     ");
            $display("    ================  Congratulations!  ================   ");
            $display("  ==================  The tests passed  ================== ");
            $display("    ================    Successfully    ================   ");
            $display("      ==============                    ==============     ");
            $display("        ============================================       \n\n");
        end else begin
            $display("   ======  %0d test(s) FAILED  ======\n", fail_count);
        end
        @(posedge lclk); $stop;
    end
endmodule
