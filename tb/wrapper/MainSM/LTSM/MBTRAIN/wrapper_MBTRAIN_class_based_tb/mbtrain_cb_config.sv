// =============================================================================
// mbtrain_cb_config.sv — TB Configuration Class
// =============================================================================
class mbtrain_cb_config;

    // ── Timing knobs ──────────────────────────────────────────────────────────
    // Number of lclk cycles the SB agent waits before sending a response.
    // Keep ≥ 2 so the DUT has moved past its SEND state before it sees the resp.
    int sb_delay_cycles     = 5;

    // Maximum lclk cycles the driver will wait for mbtrain_done before declaring
    // a timeout.  Set conservatively large; most scenarios finish in < 2000 cyc.
    int watchdog_cycles     = 15000;

    // Cycles the D2C model holds analog_settle_time_done low before asserting it.
    int analog_settle_cycles = 10;

    // ── Scenario-generation counter ───────────────────────────────────────────
    // Incremented at the start of every scenario so stale pending items in the
    // SB-agent queue are silently discarded instead of poisoning the next run.
    int scenario_generation = 0;

    // ── Default pass masks ────────────────────────────────────────────────────
    // Used by the D2C model for non-LINKSPEED sweeps (VALVREF, DATAVREF, …).
    // The model ANDs this with sweep_active_lanes before presenting it to the DUT.
    logic [15:0] current_train_pass_mask = 16'hFFFF;

    // ── LINKSPEED pass-mask script ────────────────────────────────────────────
    // One entry per LINKSPEED visit.  After the queue is exhausted the last
    // entry is repeated indefinitely.
    logic [15:0] linkspeed_pass_q[$];
    int          linkspeed_sweep_index = 0;

    // ── Response-suppression (for timeout scenarios) ──────────────────────────
    bit          suppress_response_en  = 1'b0;
    logic [7:0]  suppress_response_msg = 8'h00;

    // ── Run-control ───────────────────────────────────────────────────────────
    bit last_timeout       = 1'b0;
    bit enable_verbose     = 0;
    bit stop_on_first_fail = 0;   // set to 1 to abort regression on first failure

    // ── Scenario bookkeeping ──────────────────────────────────────────────────
    function void begin_scenario();
        scenario_generation++;
        linkspeed_sweep_index  = 0;
        last_timeout           = 1'b0;
        suppress_response_en   = 1'b0;
        suppress_response_msg  = 8'h00;
    endfunction

    // Load the LINKSPEED pass-mask script for the current scenario.
    // If the supplied queue is empty the fallback_mask is used for every visit.
    function void configure_linkspeed_script(
        logic [15:0] script_q[$],
        logic [15:0] fallback_mask
    );
        linkspeed_pass_q.delete();
        foreach (script_q[i])
            linkspeed_pass_q.push_back(script_q[i]);
        if (linkspeed_pass_q.size() == 0)
            linkspeed_pass_q.push_back(fallback_mask);
        linkspeed_sweep_index = 0;
    endfunction

    // Return the next LINKSPEED pass mask, advancing the script index.
    // Once exhausted the last entry is returned forever.
    function logic [15:0] next_linkspeed_pass_mask();
        logic [15:0] mask;
        if (linkspeed_pass_q.size() == 0) begin
            mask = current_train_pass_mask;
        end else if (linkspeed_sweep_index < linkspeed_pass_q.size()) begin
            mask = linkspeed_pass_q[linkspeed_sweep_index];
        end else begin
            mask = linkspeed_pass_q[linkspeed_pass_q.size()-1];
        end
        linkspeed_sweep_index++;
        return mask;
    endfunction

endclass
