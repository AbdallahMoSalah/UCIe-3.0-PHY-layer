// =============================================================================
// mbtrain_cb_driver.sv — Scenario Driver
//
// KEY FIXES vs previous version:
//  1. state_n_1 is updated correctly:
//       - Before SPEEDIDLE: LOG_MBTRAIN_DATAVREF (first entry) or
//                           LOG_MBTRAIN_LINKSPEED / LOG_PHYRETRAIN (re-entry)
//       - Before REPAIR:    LOG_MBTRAIN_LINKSPEED
//       - After REPAIR exits to TXSELFCAL state_n_1 is preserved so SPEEDIDLE
//         knows to stay at same speed (re-enter from REPAIR).
//     The driver tracks which mbtrain_speedidle_req/repair_req to assert.
//  2. Width configuration maps correctly to all three register fields:
//       rf_cap_SPMW, rf_ctrl_target_link_width, param_UCIe_S_x8
//  3. mbinit_rx/tx_data_lane_mask is set consistently with width.
//  4. Watchdog: latches cfg.last_timeout and returns without scoreboard check.
//  5. Soft-reset / disable-mid-sequence injection is handled cleanly.
//  6. mbtrain_done sampling: waits for LATCHED monitor value, not transient DUT pin.
// =============================================================================
class mbtrain_cb_driver;
    import ltsm_state_n_pkg::*;
    import mbtrain_cb_types_pkg::*;

    virtual mbtrain_cb_if  vif;
    mbtrain_cb_config      cfg;
    mbtrain_cb_sb_agent    sb_agent;
    mbtrain_cb_d2c_model   d2c_model;
    mbtrain_cb_monitor     mon;

    function new(virtual mbtrain_cb_if  v,
                 mbtrain_cb_config      c,
                 mbtrain_cb_sb_agent    sba,
                 mbtrain_cb_d2c_model   d2c,
                 mbtrain_cb_monitor     m);
        vif       = v;
        cfg       = c;
        sb_agent  = sba;
        d2c_model = d2c;
        mon       = m;
    endfunction

    // =========================================================================
    // Configure DUT registers from scenario width/speed
    // =========================================================================
    task automatic configure_width_speed(mbtrain_scenario_s scen);
        @(negedge vif.lclk);

        // Speed
        vif.param_negotiated_max_speed = scen.speed;

        // Width registers
        // is_x16_module = (rf_cap_SPMW==0) && (rf_ctrl_target_link_width==4'h2)
        //                  && (param_UCIe_S_x8==0)
        // is_x8_module  = rf_ctrl_target_link_width == 4'h1
        case (scen.width)
            WIDTH_X16: begin
                vif.rf_cap_SPMW              = 1'b0;
                vif.rf_ctrl_target_link_width = 4'h2;
                vif.param_UCIe_S_x8          = 1'b0;
                vif.mbinit_rx_data_lane_mask  = 3'b011; // lanes 0-15
                vif.mbinit_tx_data_lane_mask  = 3'b011;
            end
            WIDTH_X8: begin
                vif.rf_cap_SPMW              = 1'b0;
                vif.rf_ctrl_target_link_width = 4'h1;
                vif.param_UCIe_S_x8          = 1'b0;
                vif.mbinit_rx_data_lane_mask  = 3'b001; // lanes 0-7
                vif.mbinit_tx_data_lane_mask  = 3'b001;
            end
            WIDTH_X4: begin
                // x4 is reached via degrade from x8; initial config is x8
                vif.rf_cap_SPMW              = 1'b0;
                vif.rf_ctrl_target_link_width = 4'h1;
                vif.param_UCIe_S_x8          = 1'b0;
                vif.mbinit_rx_data_lane_mask  = 3'b001;
                vif.mbinit_tx_data_lane_mask  = 3'b001;
            end
            default: begin
                vif.rf_cap_SPMW              = 1'b0;
                vif.rf_ctrl_target_link_width = 4'h2;
                vif.param_UCIe_S_x8          = 1'b0;
                vif.mbinit_rx_data_lane_mask  = 3'b011;
                vif.mbinit_tx_data_lane_mask  = 3'b011;
            end
        endcase

        // Speed affects is_high_speed inside RTL (>32GT/s → 3'b110 or 3'b111)
        vif.is_continuous_clk_mode = (scen.speed >= SPEED_48G) ? 1'b1 : 1'b0;
    endtask

    // =========================================================================
    // Run one scenario
    // Returns 1=PASS, 0=FAIL
    // =========================================================================
    task automatic run_scenario(mbtrain_scenario_s scen, output bit result);
        int   watchdog;
        bit   done_seen;
        bit   timed_out;

        $display("");
        $display("--------------------------------------------------");
        $display("[SCENARIO START] %s width=%s speed=%s",
                 scen.name, scen.width.name(), scen.speed.name());

        // ── 1. Begin new scenario in config ──────────────────────────────────
        cfg.begin_scenario();

        // ── 2. Flush stale SB responses ───────────────────────────────────────
        sb_agent.flush();

        // ── 3. Reset monitor ──────────────────────────────────────────────────
        mon.reset_for_scenario(scen.name);

        // ── 4. Assert hard reset ──────────────────────────────────────────────
        vif.drive_reset();
        repeat(5) @(posedge vif.lclk);

        // ── 5. Configure width / speed ────────────────────────────────────────
        configure_width_speed(scen);

        // ── 6. Set PHY retrain flags ──────────────────────────────────────────
        @(negedge vif.lclk);
        vif.PHY_IN_RETRAIN = scen.PHY_IN_RETRAIN;
        vif.params_changed = scen.params_changed;

        // ── 7. Set D2C model pass mask ────────────────────────────────────────
        d2c_model.configure(scen.d2c_pass_mask);

        // ── 8. Load LINKSPEED script into config ──────────────────────────────
        cfg.configure_linkspeed_script(scen.linkspeed_pass_q, scen.d2c_pass_mask);

        // ── 9. Configure REPAIR partner lane code ────────────────────────────
        // Default: report same code as DUT sends (meaning remote die agrees).
        // For "degrade not possible" scenarios we override below.
        sb_agent.configure_repair_partner_code(3'b011); // full width = all ok

        // For exhausted degrade scenarios: partner sends 3'b000
        if (scen.expected_exit == EXIT_TRAINERROR) begin
            // Check if this is a REPAIR exhaustion scenario by counting
            // expected REPAIR visits in state_path_q
            int repair_count = 0;
            foreach (scen.state_path_q[i])
                if (scen.state_path_q[i] == LOG_MBTRAIN_REPAIR) repair_count++;
            if (repair_count >= 2)
                sb_agent.configure_repair_partner_code(3'b000);
        end

        // ── 10. Set response suppression ─────────────────────────────────────
        cfg.suppress_response_en  = scen.suppress_response_en;
        cfg.suppress_response_msg = scen.suppress_response_msg;

        // ── 11. Configure re-entry request flags ──────────────────────────────
        @(negedge vif.lclk);
        vif.mbtrain_txselfcal_req = 1'b0;
        vif.mbtrain_speedidle_req = 1'b0;
        vif.mbtrain_repair_req    = 1'b0;

        // For re-entry scenarios derive from state_path_q first state
        if (scen.state_path_q.size() > 0) begin
            case (scen.state_path_q[0])
                LOG_MBTRAIN_TXSELFCAL: vif.mbtrain_txselfcal_req = 1'b1;
                LOG_MBTRAIN_SPEEDIDLE: vif.mbtrain_speedidle_req  = 1'b1;
                LOG_MBTRAIN_REPAIR:    vif.mbtrain_repair_req     = 1'b1;
                default:               ; // nominal entry at VALVREF
            endcase
        end

        // ── 12. Release soft reset ────────────────────────────────────────────
        vif.release_soft_reset_sequence();

        // ── 13. Start MBTRAIN ─────────────────────────────────────────────────
        vif.start_mbtrain();

        // ── 14. Handle mid-sequence injections (soft-reset / disable) ────────
        if (scen.inject_soft_reset_mid_sequence ||
            scen.inject_disable_mid_sequence) begin
            fork
                begin
                    // Wait until RXCLKCAL is active (good mid-point)
                    int timeout_cnt = 0;
                    while (vif.current_mbtrain_substate != LOG_MBTRAIN_RXCLKCAL
                           && timeout_cnt < 5000) begin
                        @(posedge vif.lclk);
                        timeout_cnt++;
                    end
                    if (timeout_cnt >= 5000) begin
                        $display("[ERROR] Timeout waiting for RXCLKCAL injection point in %s",
                                 scen.name);
                    end else begin
                        repeat(10) @(posedge vif.lclk);
                        if (scen.inject_soft_reset_mid_sequence) begin
                            $display("[EVENT] Injecting soft reset mid-sequence");
                            @(negedge vif.lclk);
                            vif.state_n_0 = LOG_RESET;
                            repeat(3) @(posedge vif.lclk);
                            @(negedge vif.lclk);
                            vif.state_n_0 = LOG_SBINIT;
                            repeat(3) @(posedge vif.lclk);
                            @(negedge vif.lclk);
                            vif.state_n_0 = LOG_MBTRAIN;
                        end
                        if (scen.inject_disable_mid_sequence) begin
                            $display("[EVENT] Injecting mbtrain_en=0 mid-sequence");
                            vif.stop_mbtrain();
                        end
                    end
                end
            join_none
        end

        // ── 15. Wait for terminal condition (watchdog) ────────────────────────
        watchdog   = 0;
        done_seen  = 0;
        timed_out  = 0;

        while (!done_seen && watchdog < cfg.watchdog_cycles) begin
            @(posedge vif.lclk);
            watchdog++;

            // For soft-reset / disable scenarios: done means monitor saw IDLE
            if (scen.inject_soft_reset_mid_sequence ||
                scen.inject_disable_mid_sequence) begin
                if (vif.current_mbtrain_substate == LOG_NOP && watchdog > 100) begin
                    mon.latch_mbtrain_done = 0;
                    done_seen = 1;
                end
            end else begin
                // Normal: wait for latched done from monitor
                if (mon.latch_mbtrain_done)
                    done_seen = 1;
            end
        end

        if (!done_seen) begin
            timed_out          = 1;
            cfg.last_timeout   = 1;
            $display("[ERROR] Timeout waiting for mbtrain_done in driver after %0d cycles",
                     cfg.watchdog_cycles);
        end

        // ── 16. Stop MBTRAIN ──────────────────────────────────────────────────
        vif.stop_mbtrain();
        repeat(10) @(posedge vif.lclk);

        mon.stop();
        mon.print_path();

        $display("[SCENARIO END] %s", scen.name);
        result = 1; // scoreboard will set final result
        cfg.last_timeout = timed_out;
    endtask

endclass
