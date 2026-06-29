// =============================================================================
// mbtrain_cb_monitor.sv — State & Event Monitor
//
// Watches the DUT outputs and records:
//   - Substate transitions (current_mbtrain_substate changes)
//   - SB TX events (what the DUT sends)
//   - Terminal flags: ltsm_linkinit_req, ltsm_phyretrain_req, ltsm_trainerror_req
//   - mbtrain_done assertion
//   - D2C sweep start/done
//   - Lane mask changes
//   - PHY_IN_RETRAIN_rst / busy_bit_rst pulses
//
// KEY FIXES vs previous version:
//  1. Samples mbtrain_done when asserted and latches latch_linkinit etc.
//     so scoreboard reads stable latched values (not transient signals).
//  2. Records every substate visit in actual_path_q (not just first visit)
//     so loopback and re-entry paths are captured correctly.
//  3. Prints only scenario-level milestones, not every clock cycle.
// =============================================================================
class mbtrain_cb_monitor;
    import ltsm_state_n_pkg::*;
    import mbtrain_cb_types_pkg::*;

    virtual mbtrain_cb_if vif;
    mbtrain_cb_config     cfg;

    // ── Observed path (each substate visit logged) ────────────────────────────
    state_n_e actual_path_q[$];

    // ── Terminal outcome latches ──────────────────────────────────────────────
    // These are latched the moment mbtrain_done goes high so the scoreboard
    // sees stable values even after the DUT deasserts them.
    bit latch_mbtrain_done   = 0;
    bit latch_linkinit       = 0;
    bit latch_phyretrain     = 0;
    bit latch_trainerror     = 0;

    // ── Event counts ─────────────────────────────────────────────────────────
    int phy_in_retrain_rst_count = 0;
    int busy_bit_rst_count       = 0;
    int sweep_done_count         = 0;
    int linkspeed_visit_count    = 0;
    int repair_visit_count       = 0;

    // ── Lane mask samples (captured when mbtrain_done) ────────────────────────
    logic [2:0] final_rx_lane_mask;
    logic [2:0] final_tx_lane_mask;

    // ── Running flag ─────────────────────────────────────────────────────────
    bit running = 0;

    function new(virtual mbtrain_cb_if v, mbtrain_cb_config c);
        vif = v;
        cfg = c;
    endfunction

    // ── Reset monitor state for new scenario ─────────────────────────────────
    task automatic reset_for_scenario(string scen_name);
        actual_path_q.delete();
        latch_mbtrain_done        = 0;
        latch_linkinit            = 0;
        latch_phyretrain          = 0;
        latch_trainerror          = 0;
        phy_in_retrain_rst_count  = 0;
        busy_bit_rst_count        = 0;
        sweep_done_count          = 0;
        linkspeed_visit_count     = 0;
        repair_visit_count        = 0;
        final_rx_lane_mask        = 3'b000;
        final_tx_lane_mask        = 3'b000;
        running                   = 1;
        $display("[MON] --- Monitoring started for %s ---", scen_name);
    endtask

    // ── Stop monitor ──────────────────────────────────────────────────────────
    task automatic stop();
        running = 0;
    endtask

    // ── Main run loop ─────────────────────────────────────────────────────────
    task automatic run();
        state_n_e prev_sub = LOG_NOP;
        state_n_e cur_sub;
        int       gen;

        fork
            forever begin
                @(posedge vif.lclk);
                if (!running) continue;

                gen     = cfg.scenario_generation;
                cur_sub = vif.current_mbtrain_substate;

                // ── Substate transition ───────────────────────────────────────
                if (cur_sub != prev_sub) begin
                    if (cur_sub != LOG_NOP) begin
                        actual_path_q.push_back(cur_sub);
                        $display("[MON] Substate: %s", cur_sub.name());

                        // Count LINKSPEED and REPAIR visits for degrade tracking
                        if (cur_sub == LOG_MBTRAIN_LINKSPEED)
                            linkspeed_visit_count++;
                        if (cur_sub == LOG_MBTRAIN_REPAIR)
                            repair_visit_count++;
                    end
                    prev_sub = cur_sub;
                end

                // ── DUT SB TX event ───────────────────────────────────────────
                if (vif.substate_tx_sb_msg_valid) begin
                    if (cfg.enable_verbose)
                        $display("[MON] DUT TX: sub=%s msg=0x%02X info=0x%04X",
                                 cur_sub.name(),
                                 vif.substate_tx_sb_msg,
                                 vif.substate_tx_msginfo);
                end

                // ── D2C sweep done ────────────────────────────────────────────
                if (vif.sweep_done)
                    sweep_done_count++;

                // ── PHY_IN_RETRAIN_rst ────────────────────────────────────────
                if (vif.PHY_IN_RETRAIN_rst) begin
                    phy_in_retrain_rst_count++;
                    if (cfg.enable_verbose)
                        $display("[MON] PHY_IN_RETRAIN_rst pulsed (count=%0d)",
                                 phy_in_retrain_rst_count);
                end

                // ── busy_bit_rst ──────────────────────────────────────────────
                if (vif.busy_bit_rst) begin
                    busy_bit_rst_count++;
                    if (cfg.enable_verbose)
                        $display("[MON] busy_bit_rst pulsed (count=%0d)",
                                 busy_bit_rst_count);
                end

                // ── mbtrain_done (latch on rising edge) ───────────────────────
                if (vif.mbtrain_done && !latch_mbtrain_done) begin
                    latch_mbtrain_done = 1;
                    // Sample terminal flags in this same cycle
                    latch_linkinit   = vif.ltsm_linkinit_req;
                    latch_phyretrain = vif.ltsm_phyretrain_req;
                    latch_trainerror = vif.ltsm_trainerror_req;
                    // Sample final lane masks
                    final_rx_lane_mask = vif.mb_rx_data_lane_mask;
                    final_tx_lane_mask = vif.mb_tx_data_lane_mask;
                    $display("[MON] mbtrain_done=1  linkinit=%0b phyretrain=%0b trainerror=%0b",
                             latch_linkinit, latch_phyretrain, latch_trainerror);
                    $display("[MON] Final lane masks: rx=%03b tx=%03b",
                             final_rx_lane_mask, final_tx_lane_mask);
                end

                // Stale generation → stop collecting
                if (cfg.scenario_generation != gen && gen != 0)
                    prev_sub = LOG_NOP;
            end
        join_none
    endtask

    // ── Print observed path ───────────────────────────────────────────────────
    function automatic void print_path();
        string path_str = "";
        foreach (actual_path_q[i]) begin
            if (i > 0) path_str = {path_str, " -> "};
            path_str = {path_str, actual_path_q[i].name()};
        end
        $display("[MON] Observed path: %s", path_str);
    endfunction

endclass
