`timescale 1ps/1ps
// =============================================================================
// Testbench : unit_LINKSPEED_tb
// Purpose   : Self-checking testbench for unit_LINKSPEED FSM.
//
// Architecture (follows unit_DATATRAINVREF_tb pattern):
//   - Single internal_ltsm_if bound to BOTH ls_if AND d2c_if ports.
//   - ltsm_tb_attachments handles: SB echo, 8ms timeout, analog settle,
//     and internally routes D2C PT (unit_TX_D2C_PT) when tx_pt_en=1.
//   - D2C error injection:
//       * intf.tb_rx_msginfo[4]       = 1  -> aggregate error flag set in echo
//       * intf.tb_rx_data_field[15:0] -> per-lane error bitmap in echo
//   - intf.phy_negotiated_speed controls repair vs speed-degrade path.
//   - intf.phyretrain_PHY_IN_RETRAIN & intf.params_changed control the
//     PHY-retrain exit path from EVAL_RESULT (spec §4.5.3.4.12).
//
// SB echo mechanism (from ltsm_tb_attachments):
//   The echo fires "stable_tx_sb_msg" back as rx_sb_msg, with:
//     rx_msginfo   = intf.tb_rx_msginfo
//     rx_data_field= intf.tb_rx_data_field
//   So:  when unit_TX_D2C_PT sends "Tx_Init_D_to_C_results_resp",
//         it contains our mb_rx_perlane_err in tx_data_field[15:0] and
//         mb_rx_aggr_err in tx_msginfo[4]; the echo comes back with
//         tb_rx_msginfo/tb_rx_data_field as the partner's seen errors.
//   THEREFORE: to simulate D2C errors, set tb_rx_msginfo[4]=1 and/or
//         tb_rx_data_field[15:0] = non-zero perlane bitmap BEFORE test start.
//
// Scenarios covered:
//   1.  Clean pass (speed=2, no errors)                                -> TO_LINKINIT
//   2.  D2C fail, speed > 0  (speed=3, perlane err)                   -> TO_SPEEDIDLE
//   3.  D2C fail, speed == 0 (speed=0, perlane err)                   -> TO_REPAIR
//   4.  8ms hardware timeout                                           -> TO_TRAINERROR
//   5.  Partner TRAINERROR injection                                   -> TO_TRAINERROR
//   6.  PHY_IN_RETRAIN=1, params_changed=1, no D2C err               -> TO_PHYRETRAIN
//   7.  PHY_IN_RETRAIN=1, params_changed=0, no D2C err               -> TO_LINKINIT (normal done)
//   8.  PHY_IN_RETRAIN=0, params_changed=1, no D2C err               -> TO_LINKINIT (no retrain path)
//   9.  PHY_IN_RETRAIN=1, params_changed=1, D2C err (speed>0)        -> TO_SPEEDIDLE (D2C error wins)
//   10. PHY_IN_RETRAIN=1, params_changed=1, D2C err, width degrade   -> TO_REPAIR   (D2C error wins, width degrade feasible)
//   11. PHY_IN_RETRAIN=1, params_changed=1, 8ms timeout              -> TO_TRAINERROR
//   12. x8 mode, width degrade x8->x4 feasible                       -> TO_REPAIR
//   13. speed=0, width degrade impossible                             -> TO_SPEEDIDLE (SPEEDIDLE handles speed=0)
//   14. SPMW=1, target_width=x16, width degrade blocked by SPMW      -> TO_SPEEDIDLE
//   15-164. 150 randomised speed / error / PHY_IN_RETRAIN / RF combos.
// =============================================================================
module unit_LINKSPEED_tb ();
    import UCIe_pkg::*;

    parameter integer LCLK_PERIOD          = 1000      ; // 1 ns  (1 GHz)
    parameter integer TIMEOUT_CYCLES       = 700_000   ; // plenty of headroom
    parameter integer ANALOG_SETTLE_CYCLES = 10        ;

    // ── Clock & Reset ─────────────────────────────────────────────────────
    reg lclk;
    reg rst_n;
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // ── Single interface (both ports connect to the same intf) ────────────
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // ── DUT ───────────────────────────────────────────────────────────────
    unit_LINKSPEED unit_LINKSPEED_inst (
        .ls_if  (intf),   // linkspeed_mp
        .d2c_if (intf)    // substate2d2c_mp  (same interface, per project convention)
    );

    // ── Infrastructure (SB echo, timeouts, D2C PT, MB model) ─────────────
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES      ),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES)
    ) ltsm_tb_attachments_inst (.intf(intf));

    // ── State monitoring ─────────────────────────────────────────────────
    typedef enum reg [4:0] {
        LINKSPEED_IDLE                       = 5'h00,
        LINKSPEED_START_REQ                  = 5'h01,
        LINKSPEED_START_RESP                 = 5'h02,
        LINKSPEED_TX_D2C_PT                  = 5'h03,
        LINKSPEED_EVAL_RESULT                = 5'h04,
        LINKSPEED_DONE_REQ                   = 5'h05,
        LINKSPEED_DONE_RESP                  = 5'h06,
        TO_LINKINIT                          = 5'h07,
        LINKSPEED_ERROR_REQ                  = 5'h08,
        LINKSPEED_ERROR_RESP                 = 5'h09,
        LINKSPEED_RECOVERY_DECISION          = 5'h0A,
        LINKSPEED_EXIT_TO_REPAIR_REQ         = 5'h0B,
        LINKSPEED_EXIT_TO_REPAIR_RESP        = 5'h0C,
        TO_REPAIR                            = 5'h0D,
        LINKSPEED_EXIT_TO_SPEED_DEGRADE_REQ  = 5'h0E,
        LINKSPEED_EXIT_TO_SPEED_DEGRADE_RESP = 5'h0F,
        TO_SPEEDIDLE                         = 5'h10,
        LINKSPEED_EXIT_RETRAIN_REQ           = 5'h11,
        LINKSPEED_EXIT_RETRAIN_RESP          = 5'h12,
        TO_PHYRETRAIN                        = 5'h13,
        TO_TRAINERROR                        = 5'h14
    } fsm_state_t;

    fsm_state_t current_state;
    fsm_state_t prev_printed;
    assign current_state = fsm_state_t'(unit_LINKSPEED_inst.current_state);

    // Print state transitions as they happen
    always @(posedge lclk) begin
        if (rst_n && current_state !== prev_printed) begin
            $display("# %0t ps : State -> \"%s\".", $realtime(), current_state.name());
            prev_printed <= current_state;
        end
    end

    // ── Driven inputs ─────────────────────────────────────────────────────
    reg [2:0] tb_speed;
    assign intf.phy_negotiated_speed    = tb_speed;

    // PHY_IN_RETRAIN inputs (new signals)
    reg tb_phyretrain_PHY_IN_RETRAIN;
    reg tb_params_changed;
    assign intf.phyretrain_PHY_IN_RETRAIN = tb_phyretrain_PHY_IN_RETRAIN;
    assign intf.params_changed            = tb_params_changed;

    // RF inputs (new signals for width degrade logic)
    reg tb_rf_cap_SPMW;
    reg [3:0] tb_rf_ctrl_target_link_width;
    assign intf.rf_cap_SPMW = tb_rf_cap_SPMW;
    assign intf.rf_ctrl_target_link_width = tb_rf_ctrl_target_link_width;

    // ── lclk cycle counter ────────────────────────────────────────────────
    integer lclk_counter   = 0;
    integer success_count  = 0;
    integer fail_count     = 0;
    reg     lclk_ctr_en    = 0;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else if (lclk_ctr_en) lclk_counter <= lclk_counter + 1;
        else lclk_counter <= 0;
    end

    // ── Reset task ────────────────────────────────────────────────────────
    task reset();
        rst_n                         = 0;
        intf.tb_aggr_err              = 0;
        intf.tb_perlane_err           = 0;
        intf.tb_val_err               = 0;
        intf.tb_clk_err               = 0;
        intf.tb_wait_timeout          = 0;
        intf.tb_wrong_sb_msg_en       = 0;
        intf.tb_wrong_sb_msg          = NOTHING;
        intf.tb_rx_msginfo            = 16'h0;
        intf.tb_rx_data_field         = 64'h0;
        intf.linkspeed_en             = 0;
        intf.mb_rx_data_lane_mask     = 3'b011; // all 16 lanes active
        tb_speed                      = 3'd2;
        tb_phyretrain_PHY_IN_RETRAIN  = 1'b0;
        tb_params_changed             = 1'b0;
        tb_rf_cap_SPMW                = 1'b0;
        tb_rf_ctrl_target_link_width  = 4'h2;
        prev_printed                  = LINKSPEED_IDLE;
        #(LCLK_PERIOD * 2); rst_n = 1;
        #(LCLK_PERIOD * 2);
    endtask

    // ── start_test task ───────────────────────────────────────────────────
    // Parameters:
    //   tb_d2c_has_error  : inject D2C errors via SB echo
    //   tb_d2c_perlane_err: which data lanes fail
    //   expect_*          : expected FSM exit path
    //   expect_phyretrain : expect TO_PHYRETRAIN (PHY_IN_RETRAIN + params_changed, no D2C err)
    task start_test (
            input integer  abort_after            = TIMEOUT_CYCLES,
            input integer  wrong_sb_after         = TIMEOUT_CYCLES,
            input msg_no_e wrong_msg              = NOTHING,
            input logic    tb_d2c_has_error       = 1'b0,
            input logic [15:0] tb_d2c_perlane_err = 16'h0001,
            input logic    expect_linkinit        = 1'b0,
            input logic    expect_repair          = 1'b0,
            input logic    expect_speedidle       = 1'b0,
            input logic    expect_trainerror      = 1'b0,
            input logic    expect_phyretrain      = 1'b0
        );
        // Configure D2C error injection
        if (tb_d2c_has_error) begin
            intf.tb_rx_msginfo    = 16'h0010; // bit[4]=1 -> aggregate error
            intf.tb_rx_data_field = {48'h0, tb_d2c_perlane_err};
        end else begin
            intf.tb_rx_msginfo    = 16'h0;
            intf.tb_rx_data_field = 64'h0;
        end

        lclk_ctr_en = 1;

        fork : TEST
            // ── Main checker thread ──────────────────────────────────────
            begin
                intf.linkspeed_en = 1'b1;
                wait (intf.linkspeed_done || intf.trainerror_req);
                @(posedge lclk); #1step;
                intf.linkspeed_en = 1'b0;

                // Verify expected outcome
                if (expect_trainerror && !intf.trainerror_req) begin
                    $display("\t *** FAIL *** expected TRAINERROR"); fail_count++;
                    disable TEST;
                end
                if (!expect_trainerror && intf.trainerror_req && !intf.tb_wait_timeout && !intf.tb_wrong_sb_msg_en) begin
                    $display("\t *** FAIL *** unexpected TRAINERROR"); fail_count++;
                    disable TEST;
                end
                if (expect_linkinit && !intf.linkinit_req) begin
                    $display("\t *** FAIL *** expected LINKINIT (linkinit=%0b repair=%0b speedidle=%0b phyretrain=%0b)",
                        intf.linkinit_req, intf.repair_req, intf.speedidle_req, intf.phyretrain_req);
                    fail_count++; disable TEST;
                end
                if (expect_repair && !intf.repair_req) begin
                    $display("\t *** FAIL *** expected REPAIR (linkinit=%0b repair=%0b speedidle=%0b phyretrain=%0b)",
                        intf.linkinit_req, intf.repair_req, intf.speedidle_req, intf.phyretrain_req);
                    fail_count++; disable TEST;
                end
                if (expect_speedidle && !intf.speedidle_req) begin
                    $display("\t *** FAIL *** expected SPEEDIDLE (linkinit=%0b repair=%0b speedidle=%0b phyretrain=%0b)",
                        intf.linkinit_req, intf.repair_req, intf.speedidle_req, intf.phyretrain_req);
                    fail_count++; disable TEST;
                end
                if (expect_phyretrain && !intf.phyretrain_req) begin
                    $display("\t *** FAIL *** expected PHYRETRAIN (linkinit=%0b repair=%0b speedidle=%0b phyretrain=%0b)",
                        intf.linkinit_req, intf.repair_req, intf.speedidle_req, intf.phyretrain_req);
                    fail_count++; disable TEST;
                end
                if (expect_phyretrain && intf.linkinit_req) begin
                    $display("\t *** FAIL *** got LINKINIT when expected PHYRETRAIN");
                    fail_count++; disable TEST;
                end

                success_count++;
                $display("# __(Success=%0d, Fail=%0d, lclk_cycles=%0d)__\n",
                    success_count, fail_count, lclk_counter);
                disable TEST;
            end

            // ── Wrong-SB injector ─────────────────────────────────────────
            begin
                for (int i = 0; i < wrong_sb_after; i++) @(posedge lclk);
                intf.tb_wrong_sb_msg_en = 1;
                intf.tb_wrong_sb_msg    = wrong_msg;
            end

            // ── 8ms timeout injector ─────────────────────────────────────
            begin
                for (int i = 0; i < abort_after; i++) @(posedge lclk);
                intf.tb_wait_timeout = 1;
            end
        join

        lclk_ctr_en                  = 0;
        intf.tb_wait_timeout         = 0;
        intf.tb_wrong_sb_msg_en      = 0;
        intf.tb_rx_msginfo           = 16'h0;
        intf.tb_rx_data_field        = 64'h0;
        @(posedge lclk); #1step;
    endtask

    // ── Main scenario list ────────────────────────────────────────────────
    integer scenario = 1;

    initial begin
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 1: Happy path, 12 GT/s, no errors -> TO_LINKINIT
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): Happy path (12 GT/s, no D2C err) -> LINKINIT. <=========", scenario++);
        tb_speed = 3'd2;
        start_test(.tb_d2c_has_error(1'b0), .expect_linkinit(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 2: D2C fail, speed>0, width degrade impossible -> TO_SPEEDIDLE
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): D2C fail (speed>0) -> SPEEDIDLE. <=========", scenario++);
        tb_speed = 3'd3;
        // Inject error in lane 0 and lane 8 (16'h0101) so neither x8 group is perfect,
        // forcing Speed Degrade instead of Width Degrade.
        start_test(.tb_d2c_has_error(1'b1), .tb_d2c_perlane_err(16'h0101), .expect_speedidle(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 3: D2C fail, x16 mode, upper 8 lanes clean -> Width Degrade feasible -> TO_REPAIR
        //   perlane_err = 16'h00FF -> active_lanes = 16'hFF00 -> active_lanes[15:8]==8'hFF
        //   With rf_ctrl_target_link_width=x16 and rf_cap_SPMW=0 -> width degrade possible
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): D2C fail, x16 width degrade feasible (upper half clean) -> REPAIR. <=========", scenario++);
        tb_speed = 3'd0;
        start_test(.tb_d2c_has_error(1'b1), .tb_d2c_perlane_err(16'h00FF), .expect_repair(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 4: 8ms hardware timeout -> TO_TRAINERROR
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): 8ms timeout -> TRAINERROR. <=========", scenario++);
        tb_speed = 3'd2;
        start_test(.abort_after(1), .expect_trainerror(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 5: Partner injects TRAINERROR -> TO_TRAINERROR
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): Partner TRAINERROR -> TRAINERROR. <=========", scenario++);
        tb_speed = 3'd2;
        start_test(.wrong_sb_after(300), .wrong_msg(TRAINERROR_Entry_req), .expect_trainerror(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 6: PHY_IN_RETRAIN=1, params_changed=1, no D2C err
        //   Expected: EVAL_RESULT branches to LINKSPEED_EXIT_RETRAIN_REQ -> TO_PHYRETRAIN
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): PHY_IN_RETRAIN=1, params_changed=1, no D2C err -> PHYRETRAIN. <=========", scenario++);
        tb_speed                     = 3'd2;
        tb_phyretrain_PHY_IN_RETRAIN = 1'b1;
        tb_params_changed            = 1'b1;
        start_test(.tb_d2c_has_error(1'b0), .expect_phyretrain(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 7: PHY_IN_RETRAIN=1, params_changed=0, no D2C err
        //   Expected: params_changed=0 means no retrain -> TO_LINKINIT (normal done path)
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): PHY_IN_RETRAIN=1, params_changed=0, no D2C err -> LINKINIT. <=========", scenario++);
        tb_speed                     = 3'd2;
        tb_phyretrain_PHY_IN_RETRAIN = 1'b1;
        tb_params_changed            = 1'b0; // no params change -> normal done
        start_test(.tb_d2c_has_error(1'b0), .expect_linkinit(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 8: PHY_IN_RETRAIN=0, params_changed=1, no D2C err
        //   Expected: PHY_IN_RETRAIN=0 -> retrain path inactive -> TO_LINKINIT
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): PHY_IN_RETRAIN=0, params_changed=1, no D2C err -> LINKINIT. <=========", scenario++);
        tb_speed                     = 3'd2;
        tb_phyretrain_PHY_IN_RETRAIN = 1'b0;
        tb_params_changed            = 1'b1;
        start_test(.tb_d2c_has_error(1'b0), .expect_linkinit(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 9: PHY_IN_RETRAIN=1, params_changed=1, D2C err (speed>0), width degrade impossible
        //   D2C fail takes priority over PHY_IN_RETRAIN in EVAL_RESULT ->
        //   d2c_fail_r=1 -> ERROR_REQ -> TO_SPEEDIDLE
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): PHY_IN_RETRAIN=1 + D2C err (speed>0) -> SPEEDIDLE. <=========", scenario++);
        tb_speed                     = 3'd4;
        tb_phyretrain_PHY_IN_RETRAIN = 1'b1;
        tb_params_changed            = 1'b1;
        start_test(.tb_d2c_has_error(1'b1), .tb_d2c_perlane_err(16'h0101), .expect_speedidle(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 10: PHY_IN_RETRAIN=1, params_changed=1, D2C err, width degrade feasible
        //   perlane_err = 16'h0003 -> active_lanes[15:8]==8'hFF -> width degrade feasible
        //   D2C error wins over PHY_IN_RETRAIN -> ERROR path -> REPAIR (width degrade)
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): PHY_IN_RETRAIN=1 + D2C err, width degrade feasible -> REPAIR. <=========", scenario++);
        tb_speed                     = 3'd0;
        tb_phyretrain_PHY_IN_RETRAIN = 1'b1;
        tb_params_changed            = 1'b1;
        start_test(.tb_d2c_has_error(1'b1), .tb_d2c_perlane_err(16'h0003), .expect_repair(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 11: PHY_IN_RETRAIN=1, params_changed=1, 8ms timeout
        //   Timeout overrides all -> TO_TRAINERROR
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): PHY_IN_RETRAIN=1 + 8ms timeout -> TRAINERROR. <=========", scenario++);
        tb_speed                     = 3'd2;
        tb_phyretrain_PHY_IN_RETRAIN = 1'b1;
        tb_params_changed            = 1'b1;
        start_test(.abort_after(1), .expect_trainerror(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 12: Width Degrade x8→x4 feasible (lower 4 lanes clean)
        //   rf_ctrl_target_link_width = x8, perlane_err = 16'h00F0
        //   -> active_lanes[3:0]==4'hF -> width degrade possible -> TO_REPAIR
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): x8 mode, width degrade x8->x4 feasible (lower half clean) -> REPAIR. <=========", scenario++);
        tb_speed = 3'd3;
        tb_rf_ctrl_target_link_width = 4'h1; // x8 mode
        start_test(.tb_d2c_has_error(1'b1), .tb_d2c_perlane_err(16'h00F0), .expect_repair(1'b1));
        reset();
        tb_rf_ctrl_target_link_width = 4'h2; // restore default

        // ─────────────────────────────────────────────────────────────────
        // Scenario 13: Speed Degrade at speed=0, width degrade impossible
        //   perlane_err = 16'h0101 -> neither x8 half is clean
        //   rf_ctrl_target_link_width=x16, speed=0 -> speed degrade -> TO_SPEEDIDLE
        //   (SPEEDIDLE will handle the fact that speed is already 0)
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): speed=0, width degrade impossible -> SPEEDIDLE. <=========", scenario++);
        tb_speed = 3'd0;
        start_test(.tb_d2c_has_error(1'b1), .tb_d2c_perlane_err(16'h0101), .expect_speedidle(1'b1));
        reset();

        // ─────────────────────────────────────────────────────────────────
        // Scenario 14: x16 SPMW=1 (x8 module), width degrade impossible for x16 path
        //   rf_cap_SPMW=1 disqualifies Case A (x16 width degrade)
        //   rf_ctrl_target_link_width=x16 but SPMW=1 -> width degrade NOT possible
        //   -> TO_SPEEDIDLE
        // ─────────────────────────────────────────────────────────────────
        $display("# =========> Test Scenario (%0d): SPMW=1, target_width=x16, width degrade blocked by SPMW -> SPEEDIDLE. <=========", scenario++);
        tb_speed = 3'd3;
        tb_rf_cap_SPMW = 1'b1;  // x8 module
        tb_rf_ctrl_target_link_width = 4'h2;  // target x16 (but SPMW=1 blocks it)
        start_test(.tb_d2c_has_error(1'b1), .tb_d2c_perlane_err(16'h0001), .expect_speedidle(1'b1));
        reset();
        tb_rf_cap_SPMW = 1'b0; // restore default

        // ─────────────────────────────────────────────────────────────────
        // Scenarios 15-164: 150 randomised tests
        //   Covers all combinations of: speed, D2C error, PHY_IN_RETRAIN, params_changed, Width Degrade
        // ─────────────────────────────────────────────────────────────────
        for (int s = 15; s <= 164; s++) begin
            // Use 2-state types (bit) instead of 4-state (reg) to prevent
            // X/Z meta-values from appearing in $display output.
            bit [2:0]  rnd_speed;
            bit [15:0] rnd_perlane_err;
            bit        any_err;
            bit        rnd_phy_in_retrain;
            bit        rnd_params_changed;
            bit        rnd_rf_cap_SPMW;
            bit [3:0]  rnd_rf_ctrl_target_link_width;
            
            bit [15:0] active_lanes;
            bit        width_degrade_possible;

            bit        exp_linkinit, exp_repair, exp_speedidle, exp_phyretrain;

            // Initialize all variables to known values BEFORE conditional assignment
            // to prevent X/Z meta-values from appearing in $display output.
            rnd_perlane_err     = 16'h0;
            active_lanes        = 16'hFFFF;
            width_degrade_possible = 1'b0;
            exp_linkinit        = 1'b0;
            exp_repair          = 1'b0;
            exp_speedidle       = 1'b0;
            exp_phyretrain      = 1'b0;

            rnd_speed           = 3'($urandom_range(0, 7));
            rnd_perlane_err     = ($urandom_range(0, 1) == 1) ?
                16'($urandom_range(1, 65535)) : 16'h0;
            rnd_phy_in_retrain  = $urandom_range(0, 1);
            rnd_params_changed  = $urandom_range(0, 1);
            rnd_rf_cap_SPMW     = $urandom_range(0, 1);
            rnd_rf_ctrl_target_link_width = ($urandom_range(0, 1) == 1) ? 4'h2 : 4'h1; // x16 or x8

            any_err             = |rnd_perlane_err;

            // Model the Width Degrade check logic
            active_lanes = 16'hFFFF & (~rnd_perlane_err);
            width_degrade_possible = (((active_lanes[7:0] == 8'hFF || active_lanes[15:8] == 8'hFF) && rnd_rf_ctrl_target_link_width == 4'h2 && rnd_rf_cap_SPMW == 1'b0) ||
                                      ((active_lanes[3:0] == 4'hF  || active_lanes[7:4] == 4'hF )  && rnd_rf_ctrl_target_link_width == 4'h1));

            // Priority: D2C error > PHY_IN_RETRAIN exit > normal done
            exp_phyretrain  = !any_err && rnd_phy_in_retrain && rnd_params_changed;
            exp_linkinit    = !any_err && !exp_phyretrain;
            
            if (any_err) begin
                if (width_degrade_possible) begin
                    // Width Degrade is possible, FSM goes to repair to execute it
                    exp_repair    = 1'b1;
                    exp_speedidle = 1'b0;
                end else begin
                    // Width Degrade impossible. We MUST send speed degrade req and go to SPEEDIDLE.
                    // SPEEDIDLE substate will handle the case where speed is already 0.
                    exp_speedidle = 1'b1;
                    exp_repair    = 1'b0;
                end
            end else begin
                exp_repair    = 1'b0;
                exp_speedidle = 1'b0;
            end

            $display("# =========> Test Scenario (%0d): speed=%0d perlane=0x%04h PHY_IN_RETRAIN=%0b params_changed=%0b SPMW=%0b TargetWidth=%0d | linkinit=%0b repair=%0b speedidle=%0b phyretrain=%0b. <=========",
                scenario++, rnd_speed, rnd_perlane_err,
                rnd_phy_in_retrain, rnd_params_changed,
                rnd_rf_cap_SPMW, rnd_rf_ctrl_target_link_width,
                exp_linkinit, exp_repair, exp_speedidle, exp_phyretrain);

            tb_speed                     = rnd_speed;
            tb_phyretrain_PHY_IN_RETRAIN = rnd_phy_in_retrain;
            tb_params_changed            = rnd_params_changed;
            tb_rf_cap_SPMW               = rnd_rf_cap_SPMW;
            tb_rf_ctrl_target_link_width = rnd_rf_ctrl_target_link_width;

            start_test(
                .tb_d2c_has_error   (any_err              ),
                .tb_d2c_perlane_err (rnd_perlane_err      ),
                .expect_linkinit    (exp_linkinit          ),
                .expect_repair      (exp_repair            ),
                .expect_speedidle   (exp_speedidle         ),
                .expect_trainerror  (1'b0                  ),
                .expect_phyretrain  (exp_phyretrain        )
            );
            reset();
        end

        // ── Final report ──────────────────────────────────────────────────
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
