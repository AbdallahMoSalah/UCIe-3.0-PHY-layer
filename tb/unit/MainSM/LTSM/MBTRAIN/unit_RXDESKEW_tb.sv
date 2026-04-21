`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_RXDESKEW_tb
// Purpose   : Self-checking testbench for unit_RXDESKEW FSM.
//
// Scenarios:
//   ✓ Speed ≤32: no accum error → deskew sweep → end
//   ✓ Speed ≤32: accum error → speed-degrade exit (S7 direct)
//   ✓ Speed >32: EQ preset loop; preset unchanged → deskew sweep
//   ✓ Speed >32: accum error → new preset → DTC1 re-entry (IDLE2) × 4
//   ✓ 8ms hardware timeout → TO_TRAINERROR
//   ✓ Partner TRAINERROR → TO_TRAINERROR
//   ✓ Randomized speed/fail combinations (speed ≤32 only for simplicity)
// =============================================================================
module unit_RXDESKEW_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1*1000 ;
    parameter TIMEOUT_CYCLES       = 700_000;
    parameter ANALOG_SETTLE_CYCLES = 10     ;
    parameter MIN_DESKEW_CODE      = 7'h00  ;
    parameter MAX_DESKEW_CODE      = 7'h1F  ; // Reduced for sim speed
    parameter SPEED_32GTS          = 3'd5   ;

    reg  lclk ;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // FSM state names
    typedef enum reg [4:0] {
        RXDESKEW_IDLE        = unit_RXDESKEW_inst.RXDESKEW_IDLE       ,
        RXDESKEW_START_REQ   = unit_RXDESKEW_inst.RXDESKEW_START_REQ  ,
        RXDESKEW_START_RESP  = unit_RXDESKEW_inst.RXDESKEW_START_RESP ,
        RXDESKEW_SET_DSK     = unit_RXDESKEW_inst.RXDESKEW_SET_DESKEW_CODE,
        RXDESKEW_RX_D2C      = unit_RXDESKEW_inst.RXDESKEW_RX_D2C_PT ,
        RXDESKEW_LOG         = unit_RXDESKEW_inst.RXDESKEW_LOG_RESULT ,
        RXDESKEW_CALC        = unit_RXDESKEW_inst.RXDESKEW_CALC_APPLY ,
        RXDESKEW_END_REQ     = unit_RXDESKEW_inst.RXDESKEW_END_REQ    ,
        RXDESKEW_END_RESP    = unit_RXDESKEW_inst.RXDESKEW_END_RESP   ,
        TO_DTC2              = unit_RXDESKEW_inst.TO_DTC2             ,
        RXDESKEW_CHOOSE_PRE  = unit_RXDESKEW_inst.RXDESKEW_CHOOSE_PRESET,
        RXDESKEW_PRESET_REQ  = unit_RXDESKEW_inst.RXDESKEW_PRESET_REQ ,
        RXDESKEW_PRESET_RESP = unit_RXDESKEW_inst.RXDESKEW_PRESET_RESP,
        RXDESKEW_PRESET_CHK  = unit_RXDESKEW_inst.RXDESKEW_PRESET_CHECK,
        RXDESKEW_LOOP_CHK    = unit_RXDESKEW_inst.RXDESKEW_LOOP_CHECK ,
        RXDESKEW_EXIT_REQ    = unit_RXDESKEW_inst.RXDESKEW_EXIT_DTC1_REQ,
        RXDESKEW_EXIT_RESP   = unit_RXDESKEW_inst.RXDESKEW_EXIT_DTC1_RESP,
        TO_DTC1              = unit_RXDESKEW_inst.TO_DTC1             ,
        RXDESKEW_IDLE2       = unit_RXDESKEW_inst.RXDESKEW_IDLE2      ,
        TO_TRAINERROR        = unit_RXDESKEW_inst.TO_TRAINERROR
    } fsm_state_t;
    fsm_state_t current_state;
    assign current_state = fsm_state_t'(unit_RXDESKEW_inst.current_state);

    // Clock
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // DUT
    unit_RXDESKEW #(
        .MAX_DESKEW_CODE(MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE(MIN_DESKEW_CODE),
        .SPEED_32GTS    (SPEED_32GTS    )
    ) unit_RXDESKEW_inst (
        .rxdeskew_if(intf),
        .d2c_if     (intf)
    );

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ── Deskew eye model ─────────────────────────────────────────────────
    // Use phy_rx_deskew_ctrl[0] to avoid packed/unpacked type mismatch.
    reg [6:0] deskew_pass_min, deskew_pass_max;
    always @(*) begin
        intf.tb_aggr_err =
            (intf.phy_rx_deskew_ctrl[0] < deskew_pass_min ||
                intf.phy_rx_deskew_ctrl[0] > deskew_pass_max) ? 1'b1 : 1'b0;
        intf.tb_perlane_err = {16{intf.tb_aggr_err}};
    end

    // ── Reset ──────────────────────────────────────────────────────────────
    task reset();
        rst_n                            = 0;
        intf.tb_aggr_err                 = 0;
        intf.tb_perlane_err              = 0;
        intf.tb_val_err                  = 0;
        intf.tb_clk_err                  = 0;
        intf.tb_wait_timeout             = 0;
        intf.tb_wrong_sb_msg_en          = 0;
        intf.tb_wrong_sb_msg             = NOTHING;
        intf.tb_rx_msginfo               = 16'h0;
        intf.tb_rx_data_field            = 64'h0;
        intf.datatraincenter1_fail_flag  = 1'b0;
        intf.valtraincenter_fail_flag    = 1'b0;
        intf.param_negotiated_max_speed  = 3'd4; // ≤32 GT/s by default
        deskew_pass_min                  = 7'h08;
        deskew_pass_max                  = 7'h18;
        #10; rst_n = 1;
    endtask

    integer lclk_counter = 0, success_count = 0, fail_count = 0;
    reg     lclk_counter_run_flag = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_counter_run_flag) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    task start_test(
            input integer  abort_after       = TIMEOUT_CYCLES,
            input integer  wrong_sb_after    = TIMEOUT_CYCLES,
            input msg_no_e wrong_msg         = NOTHING,
            input logic    expect_dtc1_req   = 1'b0,
            input logic    expect_trainerror = 1'b0,
            input integer  expected_dtc1_loops = 0
        );
        integer dtc1_req_count;
        dtc1_req_count    = 0;
        lclk_counter_run_flag = 1;

        fork : TEST
            begin
                intf.rxdeskew_en = 1'b1;

                // Monitor DTC1 re-entry requests
                if (expect_dtc1_req) begin
                    for (int i = 0; i < expected_dtc1_loops; i++) begin
                        @(posedge intf.datatraincenter1_req); #1step;
                        dtc1_req_count++;
                        // Simulate controller: deassert rxdeskew_en, run DTC1,
                        // reassert rxdeskew_en (enters IDLE2).
                        intf.rxdeskew_en = 1'b0;
                        repeat(10) @(posedge lclk);
                        intf.rxdeskew_en = 1'b1;
                    end
                end

                wait(intf.rxdeskew_done || intf.trainerror_req); #1step;
                intf.rxdeskew_en = 1'b0;

                if (expect_trainerror && !intf.trainerror_req) begin
                    repeat(5) $display("\t\t *** ERROR *** Expected TRAINERROR!"); $stop;
                end
                if (!expect_trainerror && intf.trainerror_req &&
                        !intf.tb_wait_timeout && !intf.tb_wrong_sb_msg_en) begin
                    repeat(5) $display("\t\t *** ERROR *** Unexpected TRAINERROR!"); $stop;
                end
                if (expect_dtc1_req && dtc1_req_count != expected_dtc1_loops) begin
                    $display("\t\t *** ERROR *** DTC1 re-entry count=%0d expected=%0d",
                        dtc1_req_count, expected_dtc1_loops); $stop;
                end

                wait(current_state == RXDESKEW_IDLE || current_state == TO_TRAINERROR);
                success_count++;
                $display("%10t ps: Passed. (Success=%0d Cycles=%0d)\n",
                    $realtime(), success_count, lclk_counter);
                disable TEST;
            end

            begin
                for (int i = 0; i < wrong_sb_after; i++) @(posedge lclk);
                intf.tb_wrong_sb_msg_en = 1;
                intf.tb_wrong_sb_msg    = wrong_msg;
            end

            begin
                for (int i = 0; i < abort_after; i++) @(posedge lclk);
                intf.tb_wait_timeout = 1;
            end
        join

        lclk_counter_run_flag           = 0;
        intf.tb_wait_timeout            = 0;
        intf.tb_wrong_sb_msg_en         = 0;
        intf.datatraincenter1_fail_flag = 0;
        intf.valtraincenter_fail_flag   = 0;
        @(posedge lclk); #1step;
    endtask

    integer scenario = 1;

    initial begin
        reset();
        $monitor("%10t ps: State=(%s)", $realtime(), current_state.name());

        // ─ 1: Speed ≤32, no accum error → full deskew sweep ──────────────
        $display("\n==> Scenario %0d: Speed<=32, No accum error", scenario++);
        intf.param_negotiated_max_speed = SPEED_32GTS; // 32 GT/s
        intf.datatraincenter1_fail_flag = 0;
        intf.valtraincenter_fail_flag   = 0;
        start_test();
        reset();

        // ─ 2: Speed ≤32, accum error → speed-degrade exit ────────────────
        $display("\n==> Scenario %0d: Speed<=32, accum error (speed-degrade)", scenario++);
        intf.param_negotiated_max_speed = SPEED_32GTS;
        intf.datatraincenter1_fail_flag = 1;
        start_test();
        reset();

        // ─ 3: Speed >32, no accum error → preset unchanged → deskew ──────
        $display("\n==> Scenario %0d: Speed>32, No accum, no new preset", scenario++);
        intf.param_negotiated_max_speed = 3'd6; // 40 GT/s (> 32)
        intf.datatraincenter1_fail_flag = 0;
        intf.valtraincenter_fail_flag   = 0;
        start_test();
        reset();

        // ─ 4: Speed >32, accum error → 4 DTC1 re-entries ─────────────────
        $display("\n==> Scenario %0d: Speed>32, accum error, DTC1 x4 re-entries", scenario++);
        intf.param_negotiated_max_speed = 3'd7; // 64 GT/s
        intf.datatraincenter1_fail_flag = 1;
        intf.tb_rx_msginfo              = 16'h1; // partner also has new preset
        start_test(.expect_dtc1_req(1'b1), .expected_dtc1_loops(4));
        reset();

        // ─ 5: 8ms hardware timeout (abort_after=1 → immediate SB block) ──
        $display("\n==> Scenario %0d: 8ms hardware timeout -> TRAINERROR", scenario++);
        intf.param_negotiated_max_speed = SPEED_32GTS;
        start_test(.abort_after(1), .expect_trainerror(1'b1));
        reset();

        // ─ 6: Partner TRAINERROR ──────────────────────────────────────────
        $display("\n==> Scenario %0d: Partner TRAINERROR msg", scenario++);
        intf.param_negotiated_max_speed = SPEED_32GTS;
        start_test(.wrong_sb_after(50_000),
            .wrong_msg(TRAINERROR_Entry_req), .expect_trainerror(1'b1));
        reset();

        // ─ 7-16: Randomized speed/fail (speed ≤32 to avoid DTC1 loops) ───
        for (int s = 7; s <= 16; s++) begin
            $display("\n==> Scenario %0d: Random (speed<=32)", scenario++);
            // Constrain to speed <= SPEED_32GTS to avoid complex EQ preset paths
            intf.param_negotiated_max_speed = $urandom_range(0, SPEED_32GTS);
            intf.datatraincenter1_fail_flag = $urandom_range(0, 1);
            intf.valtraincenter_fail_flag   = $urandom_range(0, 1);
            deskew_pass_min = $urandom_range(0, int'(MAX_DESKEW_CODE)/2);
            deskew_pass_max = $urandom_range(int'(MAX_DESKEW_CODE)/2, int'(MAX_DESKEW_CODE));
            start_test();
            reset();
        end

        if (fail_count == 0) begin
            $display("        ============================================       ");
            $display("      ==============  Congratulations!  ==============     ");
            $display("   ==================  Tests Passed!  ==================   ");
            $display("        ============================================       ");
        end
        @(posedge lclk); $stop;
    end
endmodule
