// =============================================================================
// mbtrain_cb_d2c_model.sv — D2C Sweep Engine Behavioral Model
//
// KEY FIXES vs previous version:
//  1. For non-LINKSPEED substates: d2c_perlane_pass = cfg.current_train_pass_mask
//     ANDed with sweep_active_lanes so inactive lanes never appear as failures.
//  2. For LINKSPEED: d2c_perlane_pass = cfg.next_linkspeed_pass_mask() — this
//     drives the LINKSPEED error/success path via the script in cfg.
//  3. sweep_done is pulsed only once per local_sweep_en assertion (not sticky).
//  4. Analog settle timer is handled inside the model: it watches
//     analog_settle_timer_en and auto-asserts analog_settle_time_done.
//  5. Both local_sweep_en and partner_sweep_en must be observed; partner_sweep_en
//     alone does not need a sweep_done response (the PARTNER holds the bus while
//     LOCAL sweeps; LOCAL controls sweep_done timing).
// =============================================================================
class mbtrain_cb_d2c_model;
    import ltsm_state_n_pkg::*;

    virtual mbtrain_cb_if vif;
    mbtrain_cb_config     cfg;

    // ── Configurable pass mask for current scenario ──────────────────────────
    // Set by driver before scenario starts.
    // For non-LINKSPEED sweeps: d2c_perlane_pass = this & sweep_active_lanes
    // For LINKSPEED: driven by cfg.next_linkspeed_pass_mask() per visit
    logic [15:0] train_pass_mask;

    // ── Sweep timing ──────────────────────────────────────────────────────────
    // How many cycles to hold sweep_done low before asserting it
    int sweep_done_delay = 3;
    // Number of codes to sweep (min→max); model drives swept_code and best_code
    int sweep_codes      = 3;

    function new(virtual mbtrain_cb_if v, mbtrain_cb_config c);
        vif             = v;
        cfg             = c;
        train_pass_mask = 16'hFFFF;
    endfunction

    // ── Run background thread ─────────────────────────────────────────────────
    task automatic run();
        fork
            run_sweep_model();
            run_analog_settle_model();
        join_none
    endtask

    // ── Analog settle auto-driver ─────────────────────────────────────────────
    // Whenever the DUT asserts analog_settle_timer_en, wait settle_cycles then
    // pulse analog_settle_time_done for one lclk.
    task automatic run_analog_settle_model();
        forever begin
            // Wait for rising edge of analog_settle_timer_en
            @(posedge vif.lclk);
            if (!vif.analog_settle_timer_en) continue;
            // Settle timer is now running — wait the configured time
            repeat(cfg.analog_settle_cycles) @(posedge vif.lclk);
            // Pulse done for one cycle
            @(negedge vif.lclk);
            vif.analog_settle_time_done = 1'b1;
            @(posedge vif.lclk);
            @(negedge vif.lclk);
            vif.analog_settle_time_done = 1'b0;
            // Wait until de-asserted before looking for next edge
            @(negedge vif.analog_settle_timer_en);
        end
    endtask

    // ── Sweep engine model ────────────────────────────────────────────────────
    task automatic run_sweep_model();
        state_n_e cur_sub;
        logic [15:0] active;
        logic [15:0] pass_mask;
        int          gen;

        forever begin
            // Wait for local_sweep_en to go high
            @(posedge vif.lclk);
            if (!vif.local_sweep_en) continue;

            // Capture scenario generation at sweep start to detect abort
            gen     = cfg.scenario_generation;
            cur_sub = vif.current_mbtrain_substate;
            active  = vif.sweep_active_lanes;

            // Determine pass mask for this sweep
            if (cur_sub == LOG_MBTRAIN_LINKSPEED) begin
                // Scripted per-visit mask
                pass_mask = cfg.next_linkspeed_pass_mask();
            end else begin
                // All non-LINKSPEED sweeps: use training mask AND active lanes
                pass_mask = train_pass_mask & active;
            end

            // Present perlane pass immediately so DUT can read it
            @(negedge vif.lclk);
            vif.d2c_perlane_pass = pass_mask;

            // Simulate sweep: drive swept_code 0→sweep_codes-1
            for (int code = 0; code < sweep_codes; code++) begin
                if (cfg.scenario_generation != gen) break;
                if (!vif.local_sweep_en)             break;
                @(negedge vif.lclk);
                vif.sweep_swept_code = code[4:0];
                for (int l = 0; l < 16; l++)
                    vif.sweep_best_code[l] = code[4:0];
                vif.sweep_min_eye_width = code[4:0];
                repeat(1) @(posedge vif.lclk);
            end

            // Abort if scenario changed
            if (cfg.scenario_generation != gen) begin
                @(negedge vif.lclk);
                vif.sweep_done  = 1'b0;
                vif.d2c_perlane_pass = 16'hFFFF;
                continue;
            end

            // Assert sweep_done after delay
            repeat(sweep_done_delay) @(posedge vif.lclk);
            if (cfg.scenario_generation != gen) continue;

            @(negedge vif.lclk);
            vif.sweep_done = 1'b1;

            // Hold sweep_done until local_sweep_en deasserts
            @(negedge vif.local_sweep_en);
            @(negedge vif.lclk);
            vif.sweep_done       = 1'b0;
            vif.d2c_perlane_pass = 16'hFFFF;
        end
    endtask

    // ── Configure for new scenario ────────────────────────────────────────────
    task automatic configure(
        input logic [15:0] t_pass_mask
    );
        train_pass_mask          = t_pass_mask;
        @(negedge vif.lclk);
        vif.sweep_done           = 1'b0;
        vif.sweep_swept_code     = '0;
        foreach (vif.sweep_best_code[i]) vif.sweep_best_code[i] = '0;
        vif.sweep_min_eye_width  = '0;
        vif.d2c_perlane_pass     = 16'hFFFF;
        vif.analog_settle_time_done = 1'b0;
    endtask

endclass
