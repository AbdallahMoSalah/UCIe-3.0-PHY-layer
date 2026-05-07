`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_REPAIR_tb
// Purpose   : Self-checking testbench for unit_REPAIR FSM.
//
// Scenarios:
//   1.  x16 pkg, degrade lanes 0-7  (linkspeed_success_lanes=00FF) -> TO_TXSELFCAL
//   2.  x8  pkg, degrade lanes 0-3  (linkspeed_success_lanes=000F) -> TO_TXSELFCAL
//   3.  Degrade not possible         (linkspeed_success_lanes=0000) -> TO_TRAINERROR
//   4.  8ms hardware timeout at INIT_REQ                           -> TO_TRAINERROR
//   5.  x16 but param_UCIe_S_x8=1 (forced x8 limits)              -> TO_TRAINERROR
//   6.  x16 pkg, all lanes pass     (linkspeed_success_lanes=FFFF) -> TO_TXSELFCAL
//   7.  x16 pkg, degrade lanes 8-15 (linkspeed_success_lanes=FF00) -> TO_TXSELFCAL
//   8.  x8  pkg, degrade lanes 4-7  (linkspeed_success_lanes=00F0) -> TO_TXSELFCAL
//   9.  Partner sends TRAINERROR_Entry_req mid-handshake           -> TO_TRAINERROR
//  10.  rx_msginfo (local_rx_lane_map_code) captured from partner  -> TO_TXSELFCAL
//  11-160. Randomised linkspeed_success_lanes combos (150 runs)
// =============================================================================
module unit_REPAIR_tb ();
    import UCIe_pkg::*;

    parameter LCLK_PERIOD          = 1000    ; // lclk = 1 ns (1 GHz) – in ps
    parameter TIMEOUT_CYCLES       = 10_000  ;
    parameter ANALOG_SETTLE_CYCLES = 10      ;

    reg  lclk;
    reg  rst_n;
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    typedef enum reg [3:0] {
        REPAIR_IDLE         = 4'd0,
        REPAIR_INIT_REQ     = 4'd1,
        REPAIR_INIT_RESP    = 4'd2,
        REPAIR_DEGRADE_REQ  = 4'd3,
        REPAIR_DEGRADE_RESP = 4'd4,
        REPAIR_EVAL_RESULT  = 4'd5,
        REPAIR_END_REQ      = 4'd6,
        REPAIR_END_RESP     = 4'd7,
        TO_TXSELFCAL        = 4'd8,
        TO_TRAINERROR       = 4'd9
    } fsm_state_t;

    fsm_state_t current_state;
    assign current_state = fsm_state_t'(unit_REPAIR_inst.current_state);

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // ── DUT ───────────────────────────────────────────────────────────────────
    unit_REPAIR unit_REPAIR_inst (
        .rp_if(intf.repair_mp)
    );

    // ── Minimal shared infrastructure (8ms timer + analog settle) ─────────────
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ── tb_rx_msginfo loopback: echo partner's tx_msginfo back in rx_msginfo ──
    always @(posedge lclk) begin
        if (rst_n) intf.tb_rx_msginfo <= intf.tx_msginfo;
    end

    // ── State monitoring ─────────────────────────────────────────────────────
    fsm_state_t prev_printed;
    always @(posedge lclk) begin
        if (rst_n && current_state !== prev_printed) begin
            $display("# %0t ps : State -> \"%s\".", $realtime(), current_state.name());
            prev_printed <= current_state;
        end
    end

    // ── Reset task ─────────────────────────────────────────────────────────────
    task reset();
        rst_n                   = 0;
        intf.tb_aggr_err        = 0;
        intf.tb_perlane_err     = 0;
        intf.tb_val_err         = 0;
        intf.tb_clk_err         = 0;
        intf.tb_wait_timeout    = 0;
        intf.tb_wrong_sb_msg_en = 0;
        intf.tb_wrong_sb_msg    = NOTHING;
        intf.tb_rx_data_field   = 64'h0;
        // intf.linkspeed_fail_flag = 0;
        intf.repair_en           = 0;
        intf.rx_pt_en            = 0;
        intf.tx_pt_en            = 0;
        intf.rf_cap_SPMW = 1'b0; // x16
        intf.rf_ctrl_target_link_width = 4'h2; // x16
        intf.linkspeed_success_lanes = 16'hFFFF;
        intf.param_UCIe_S_x8 = 1'b0;
        prev_printed = REPAIR_IDLE;
        #(LCLK_PERIOD*2); rst_n = 1;
        #(LCLK_PERIOD*2);
    endtask

    // ── Cycle counter ──────────────────────────────────────────────────────────
    integer lclk_counter = 0, success_count = 0, fail_count = 0;
    reg     lclk_ctr_en  = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_ctr_en) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    // ── start_test task ────────────────────────────────────────────────────────
    task start_test(
            input integer  abort_after       = TIMEOUT_CYCLES,
            input logic    expect_done       = 1'b1,
            input logic    expect_trainerror = 1'b0
        );
        lclk_ctr_en = 1;

        fork : TEST_EXEC
            // ── Main thread ──────────────────────────────────────────────────
            begin
                intf.repair_en = 1'b1;
                wait(intf.txselfcal_req || intf.trainerror_req);
                @(posedge lclk); #1step;
                intf.repair_en = 1'b0;

                // Checks
                if (expect_trainerror && !intf.trainerror_req) begin
                    $display("\t *** FAIL *** expected TRAINERROR"); fail_count++;
                    disable TEST_EXEC;
                end
                if (!expect_trainerror && intf.trainerror_req) begin
                    $display("\t *** FAIL *** unexpected TRAINERROR (state=%s)", current_state.name()); fail_count++;
                    disable TEST_EXEC;
                end
                if (expect_done && !intf.txselfcal_req) begin
                    $display("\t *** FAIL *** expected txselfcal_req=1"); fail_count++;
                    disable TEST_EXEC;
                end

                success_count++;
                $display("# __(Success=%0d, Fail=%0d, lclk_cycles=%0d)__\n",
                    success_count, fail_count, lclk_counter);
                disable TEST_EXEC;
            end

            // ── Hardware timeout injector ──────────────────────────────────────
            begin
                repeat(abort_after) @(posedge lclk);
                intf.tb_wait_timeout = 1;
            end
        join

        lclk_ctr_en          = 0;
        intf.tb_wait_timeout = 0;
        @(posedge lclk); #1step;
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // Helper function: mirrors the RTL local_tx_lane_map_code combinational logic
    // Returns 1 when the given inputs would produce a non-zero map code (i.e. degrade succeeds)
    // ─────────────────────────────────────────────────────────────────────────
    function automatic logic rtl_can_degrade(
            input logic [15:0] succ,
            input logic        cap_spmw,
            input logic [3:0]  tgt_width,
            input logic        param_x8
        );
        if ((cap_spmw == 1'b0 && tgt_width == 4'h2) && param_x8 == 1'b0) begin
            // x16 pkg
            return (succ == 16'hFFFF) || (succ[7:0] == 8'hFF) || (succ[15:8] == 8'hFF);
        end else if (tgt_width == 4'h1) begin
            // x8 pkg or x8 mode
            return (succ[7:0] == 8'hFF) || (succ[3:0] == 4'hF) || (succ[7:4] == 4'hF);
        end else begin
            return 1'b0;
        end
    endfunction

    // ── Scenarios ─────────────────────────────────────────────────────────────
    integer scenario = 1;

    initial begin
        reset();

        // ── Scenario 1: x16 pkg, degrade to lanes 0-7 ────────────────────────
        $display("# =========> Test Scenario (%0d): x16 degrade to 0-7 (linkspeed_success_lanes=00FF) -> TO_TXSELFCAL. <=========", scenario++);
        intf.rf_cap_SPMW = 1'b0;
        intf.rf_ctrl_target_link_width = 4'h2;
        intf.param_UCIe_S_x8 = 1'b0;
        intf.linkspeed_success_lanes = 16'h00FF;
        start_test(.expect_done(1'b1), .expect_trainerror(1'b0));
        reset();

        // ── Scenario 2: x8 pkg, degrade to lanes 0-3 ─────────────────────────
        $display("# =========> Test Scenario (%0d): x8 degrade to 0-3 (linkspeed_success_lanes=000F) -> TO_TXSELFCAL. <=========", scenario++);
        intf.rf_cap_SPMW = 1'b1;
        intf.rf_ctrl_target_link_width = 4'h1;
        intf.param_UCIe_S_x8 = 1'b1;
        intf.linkspeed_success_lanes = 16'h000F;
        start_test(.expect_done(1'b1), .expect_trainerror(1'b0));
        reset();

        // ── Scenario 3: Degrade not possible (all lanes failed) ───────────────
        $display("# =========> Test Scenario (%0d): Degrade not possible (linkspeed_success_lanes=0000) -> TRAINERROR. <=========", scenario++);
        intf.rf_cap_SPMW = 1'b0;
        intf.rf_ctrl_target_link_width = 4'h2;
        intf.param_UCIe_S_x8 = 1'b0;
        intf.linkspeed_success_lanes = 16'h0000;
        start_test(.expect_done(1'b0), .expect_trainerror(1'b1));
        reset();

        // ── Scenario 4: 8ms hardware timeout → TRAINERROR ────────────────────
        $display("# =========> Test Scenario (%0d): 8ms timeout at INIT_REQ -> TRAINERROR. <=========", scenario++);
        intf.rf_cap_SPMW = 1'b0;
        intf.rf_ctrl_target_link_width = 4'h2;
        intf.param_UCIe_S_x8 = 1'b0;
        intf.linkspeed_success_lanes = 16'h00FF;
        start_test(.abort_after(1), .expect_done(1'b0), .expect_trainerror(1'b1));
        reset();

        // ── Scenario 5: x16 but param_UCIe_S_x8=1 blocks x8 degrade path ─────
        $display("# =========> Test Scenario (%0d): x16 + param_UCIe_S_x8=1 (x8 limits) -> TRAINERROR. <=========", scenario++);
        intf.rf_cap_SPMW = 1'b0;
        intf.rf_ctrl_target_link_width = 4'h2;
        intf.param_UCIe_S_x8 = 1'b1;
        intf.linkspeed_success_lanes = 16'h00FF; // ordinarily works for x16->x8 but blocked by param_UCIe_S_x8=1
        start_test(.expect_done(1'b0), .expect_trainerror(1'b1));
        reset();

        // ── Scenario 6: x16 pkg, all lanes pass (map_code = 011 = all 16) ────
        $display("# =========> Test Scenario (%0d): x16 all lanes pass (linkspeed_success_lanes=FFFF) -> TO_TXSELFCAL (map=3'b011). <=========", scenario++);
        intf.rf_cap_SPMW = 1'b0;
        intf.rf_ctrl_target_link_width = 4'h2;
        intf.param_UCIe_S_x8 = 1'b0;
        intf.linkspeed_success_lanes = 16'hFFFF; // map_code = 3'b011 (lanes 0-15)
        start_test(.expect_done(1'b1), .expect_trainerror(1'b0));
        reset();

        // ── Scenario 7: x16 pkg, degrade to lanes 8-15 (map_code = 010) ──────
        $display("# =========> Test Scenario (%0d): x16 degrade to 8-15 (linkspeed_success_lanes=FF00) -> TO_TXSELFCAL (map=3'b010). <=========", scenario++);
        intf.rf_cap_SPMW = 1'b0;
        intf.rf_ctrl_target_link_width = 4'h2;
        intf.param_UCIe_S_x8 = 1'b0;
        intf.linkspeed_success_lanes = 16'hFF00; // map_code = 3'b010 (lanes 8-15)
        start_test(.expect_done(1'b1), .expect_trainerror(1'b0));
        reset();

        // ── Scenario 8: x8 pkg, degrade to lanes 4-7 (map_code = 101) ────────
        $display("# =========> Test Scenario (%0d): x8 degrade to 4-7 (linkspeed_success_lanes=00F0) -> TO_TXSELFCAL (map=3'b101). <=========", scenario++);
        intf.rf_cap_SPMW = 1'b1;
        intf.rf_ctrl_target_link_width = 4'h1;
        intf.param_UCIe_S_x8 = 1'b1;
        intf.linkspeed_success_lanes = 16'h00F0; // map_code = 3'b101 (lanes 4-7)
        start_test(.expect_done(1'b1), .expect_trainerror(1'b0));
        reset();

        // ── Scenario 9: Partner sends TRAINERROR_Entry_req → immediate exit ───
        // The FSM should jump to TO_TRAINERROR from any state when this message arrives.
        // We inject it via tb_wrong_sb_msg_en while a normal handshake is in progress.
        $display("# =========> Test Scenario (%0d): Partner sends TRAINERROR_Entry_req mid-handshake -> immediate TO_TRAINERROR. <=========", scenario++);
        intf.rf_cap_SPMW = 1'b0;
        intf.rf_ctrl_target_link_width = 4'h2;
        intf.param_UCIe_S_x8 = 1'b0;
        intf.linkspeed_success_lanes = 16'h00FF;
        intf.tb_wrong_sb_msg_en = 1'b1;
        intf.tb_wrong_sb_msg    = TRAINERROR_Entry_req;
        start_test(.expect_done(1'b0), .expect_trainerror(1'b1));
        intf.tb_wrong_sb_msg_en = 1'b0;
        intf.tb_wrong_sb_msg    = NOTHING;
        reset();

        // ── Scenario 10: local_rx_lane_map_code captured from partner msginfo ──
        // After REPAIR_DEGRADE_REQ is received, the partner's echoed tx_msginfo
        // (which carries local_tx_lane_map_code) is latched into local_rx_lane_map_code.
        // We verify the full path still completes to TO_TXSELFCAL.
        $display("# =========> Test Scenario (%0d): local_rx_lane_map_code captured from partner (lanes 0-7) -> TO_TXSELFCAL. <=========", scenario++);
        intf.rf_cap_SPMW = 1'b0;
        intf.rf_ctrl_target_link_width = 4'h2;
        intf.param_UCIe_S_x8 = 1'b0;
        intf.linkspeed_success_lanes = 16'h00FF; // tx_lane_map_code = 3'b001 -> looped back as rx_lane_map_code
        start_test(.expect_done(1'b1), .expect_trainerror(1'b0));
        reset();

        // ── Scenarios 11-160: 150 randomised combos ───────────────────────────
        for (int s = 11; s <= 160; s++) begin
            bit [15:0] rnd_succ;
            bit rnd_param_UCIe_S_x8;
            bit rnd_rf_cap_SPMW;
            bit [3:0] rnd_rf_ctrl_target_link_width;

            rnd_succ = $urandom;
            rnd_param_UCIe_S_x8 = $urandom_range(0, 1);
            rnd_rf_cap_SPMW = $urandom_range(0, 1);
            rnd_rf_ctrl_target_link_width = ($urandom_range(0, 1) == 1) ? 4'h2 : 4'h1; // x16 or x8

            $display("# =========> Test Scenario (%0d): Rand linkspeed_success_lanes=%04h, param_x8=%0b, cap_x8=%0b, tgt_width=%0d. <=========",
                scenario++, rnd_succ, rnd_param_UCIe_S_x8, rnd_rf_cap_SPMW, rnd_rf_ctrl_target_link_width);

            intf.rf_cap_SPMW = rnd_rf_cap_SPMW;
            intf.rf_ctrl_target_link_width = rnd_rf_ctrl_target_link_width;
            intf.param_UCIe_S_x8 = rnd_param_UCIe_S_x8;
            intf.linkspeed_success_lanes = rnd_succ;

            if (rtl_can_degrade(rnd_succ, rnd_rf_cap_SPMW, rnd_rf_ctrl_target_link_width, rnd_param_UCIe_S_x8))
                start_test(.expect_done(1'b1), .expect_trainerror(1'b0));
            else
                start_test(.expect_done(1'b0), .expect_trainerror(1'b1));

            reset();
        end

        // ── Final report ───────────────────────────────────────────────────────
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
