// =============================================================================
// mbtrain_cb_testlib.sv — Scenario Library
//
// CORRECTED Group D per updated MBTRAIN_overview.md:
//   D1: LINKSPEED detects params_changed → PHYRETRAIN exit
//   D2: Re-entry at TXSELFCAL after PHYRETRAIN → LINKINIT
//   D3: Re-entry at SPEEDIDLE after PHYRETRAIN (speed degrade) → LINKINIT
//   D4: Re-entry at REPAIR after PHYRETRAIN (width degrade) → LINKINIT
// =============================================================================
class mbtrain_cb_testlib;
    import ltsm_state_n_pkg::*;
    import mbtrain_cb_types_pkg::*;

    mbtrain_scenario_s scenarios[$];

    // =========================================================================
    // Internal helpers
    // =========================================================================
    local function automatic void reset_scenario(ref mbtrain_scenario_s s);
        s.name                           = "";
        s.width                          = WIDTH_X16;
        s.speed                          = SPEED_32G;
        s.expected_exit                  = EXIT_LINKINIT;
        s.state_path_q.delete();
        s.d2c_pass_mask                  = 16'hFFFF;
        s.linkspeed_pass_q.delete();
        s.PHY_IN_RETRAIN                 = 0;
        s.params_changed                 = 0;
        s.expected_rx_mask               = 3'b000;
        s.expected_tx_mask               = 3'b000;
        s.expected_timeout               = 0;
        s.inject_soft_reset_mid_sequence = 0;
        s.inject_disable_mid_sequence    = 0;
        s.suppress_response_en           = 0;
        s.suppress_response_msg          = 8'h00;
    endfunction

    // Add the full nominal (golden) state path up to LINKSPEED
    local function automatic void add_nominal_path(ref mbtrain_scenario_s s);
        s.state_path_q.push_back(LOG_MBTRAIN_VALVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATAVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_SPEEDIDLE);
        s.state_path_q.push_back(LOG_MBTRAIN_TXSELFCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_RXCLKCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINCENTER);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER1);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_RXDESKEW);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER2);
        s.state_path_q.push_back(LOG_MBTRAIN_LINKSPEED);
    endfunction

    // Add the post-SPEEDIDLE re-entry path (TXSELFCAL onwards)
    local function automatic void add_post_speedidle_path(ref mbtrain_scenario_s s);
        s.state_path_q.push_back(LOG_MBTRAIN_TXSELFCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_RXCLKCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINCENTER);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER1);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_RXDESKEW);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER2);
        s.state_path_q.push_back(LOG_MBTRAIN_LINKSPEED);
    endfunction

    // Add the post-REPAIR re-entry path (TXSELFCAL onwards)
    local function automatic void add_post_repair_path(ref mbtrain_scenario_s s);
        s.state_path_q.push_back(LOG_MBTRAIN_TXSELFCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_RXCLKCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINCENTER);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER1);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_RXDESKEW);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER2);
        s.state_path_q.push_back(LOG_MBTRAIN_LINKSPEED);
    endfunction

    local function automatic void push_scenario(mbtrain_scenario_s s);
        scenarios.push_back(s);
    endfunction

    // =========================================================================
    function new();
        build_all_scenarios();
    endfunction

    // =========================================================================
    // Build ALL scenarios
    // =========================================================================
    function automatic void build_all_scenarios();
        mbtrain_scenario_s s;
        scenarios.delete();

        // =====================================================================
        // GROUP A — Normal Success
        // =====================================================================

        // A1: Golden path x16 at 32GT/s
        reset_scenario(s);
        s.name          = "A1_GOLDEN_X16";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF);
        s.expected_rx_mask = 3'b011;
        s.expected_tx_mask = 3'b011;
        add_nominal_path(s);
        push_scenario(s);

        // A2: Golden path x8 at 32GT/s
        reset_scenario(s);
        s.name          = "A2_GOLDEN_X8";
        s.width         = WIDTH_X8;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'h00FF;
        s.linkspeed_pass_q.push_back(16'h00FF);
        s.expected_rx_mask = 3'b001;
        s.expected_tx_mask = 3'b001;
        add_nominal_path(s);
        push_scenario(s);

        // A3: Golden path x16 at high speed (48GT/s) — RXDESKEW EQ preset path
        reset_scenario(s);
        s.name          = "A3_GOLDEN_HIGHSPEED_X16";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_48G;
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF);
        s.expected_rx_mask = 3'b011;
        s.expected_tx_mask = 3'b011;
        add_nominal_path(s);
        push_scenario(s);

        // =====================================================================
        // GROUP B — Speed Degrade
        // =====================================================================

        // B1: Single speed degrade then success
        // 1st LINKSPEED: 16'h0000 → speed degrade (no lanes pass → no repair possible)
        // After SPEEDIDLE (speed lowered), re-run full training, 2nd LINKSPEED passes
        reset_scenario(s);
        s.name          = "B1_SINGLE_SPEED_DEGRADE_THEN_SUCCESS";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_48G; // start at 48GT/s so degrade to 32GT/s is valid
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'h0000); // 1st visit: all fail → speed degrade
        s.linkspeed_pass_q.push_back(16'hFFFF); // 2nd visit (after SPEEDIDLE): all pass
        s.expected_rx_mask = 3'b011;
        s.expected_tx_mask = 3'b011;
        add_nominal_path(s);                     // up to first LINKSPEED
        s.state_path_q.push_back(LOG_MBTRAIN_SPEEDIDLE);
        add_post_speedidle_path(s);              // TXSELFCAL → ... → 2nd LINKSPEED
        push_scenario(s);

        // B2: Multiple speed degrades then success (48→32→16GT/s)
        reset_scenario(s);
        s.name          = "B2_MULTI_SPEED_DEGRADE_THEN_SUCCESS";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_48G;
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'h0000); // 1st: fail → degrade to 32GT/s
        s.linkspeed_pass_q.push_back(16'h0000); // 2nd: fail → degrade to 24GT/s
        s.linkspeed_pass_q.push_back(16'hFFFF); // 3rd: pass → LINKINIT
        s.expected_rx_mask = 3'b011;
        s.expected_tx_mask = 3'b011;
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_SPEEDIDLE);
        add_post_speedidle_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_SPEEDIDLE);
        add_post_speedidle_path(s);
        push_scenario(s);

        // B3: Lowest speed still fails → TRAINERROR via SPEEDIDLE degrade error
        // Start at 4GT/s (lowest); LINKSPEED fails; SPEEDIDLE detects degrade impossible
        reset_scenario(s);
        s.name          = "B3_LOWEST_SPEED_STILL_FAILS";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_4G; // already at minimum
        s.expected_exit = EXIT_TRAINERROR;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'h0000); // all fail → speed degrade requested
        // SPEEDIDLE will see state_n_1==LOG_MBTRAIN_LINKSPEED and speed==4GT/s
        // → speed_degrade_error=1 → TRAINERROR
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_SPEEDIDLE); // enters then TRAINERROR
        push_scenario(s);

        // =====================================================================
        // GROUP C — Width Degrade
        // =====================================================================

        // C1: x16 → degrade to x8 lower half (lanes 0-7)
        reset_scenario(s);
        s.name          = "C1_WIDTH_DEGRADE_X16_TO_X8_LOW";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'hFFFF;
        // 1st LINKSPEED: lower 8 pass, upper 8 fail → REPAIR (x8 low)
        // After REPAIR→TXSELFCAL→...→2nd LINKSPEED: lower 8 pass → LINKINIT
        s.linkspeed_pass_q.push_back(16'h00FF); // triggers REPAIR
        s.linkspeed_pass_q.push_back(16'h00FF); // 2nd visit passes
        s.expected_rx_mask = 3'b001;
        s.expected_tx_mask = 3'b001;
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);
        add_post_repair_path(s);
        push_scenario(s);

        // C2: x16 → degrade to x8 upper half (lanes 8-15)
        reset_scenario(s);
        s.name          = "C2_WIDTH_DEGRADE_X16_TO_X8_HIGH";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFF00); // upper 8 pass → REPAIR x8 high
        s.linkspeed_pass_q.push_back(16'hFF00); // 2nd visit passes
        s.expected_rx_mask = 3'b010;
        s.expected_tx_mask = 3'b010;
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);
        add_post_repair_path(s);
        push_scenario(s);

        // C3: x8 → degrade to x4 lower half (lanes 0-3)
        reset_scenario(s);
        s.name          = "C3_WIDTH_DEGRADE_X8_TO_X4_LOW";
        s.width         = WIDTH_X8;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'h00FF; // x8 active during training
        s.linkspeed_pass_q.push_back(16'h000F); // lanes 0-3 pass → REPAIR x4 low
        s.linkspeed_pass_q.push_back(16'h000F); // 2nd visit passes
        s.expected_rx_mask = 3'b100;
        s.expected_tx_mask = 3'b100;
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);
        add_post_repair_path(s);
        push_scenario(s);

        // C4: x8 → degrade to x4 upper half (lanes 4-7)
        reset_scenario(s);
        s.name          = "C4_WIDTH_DEGRADE_X8_TO_X4_HIGH";
        s.width         = WIDTH_X8;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_LINKINIT;
        s.d2c_pass_mask = 16'h00FF;
        s.linkspeed_pass_q.push_back(16'h00F0); // lanes 4-7 pass → REPAIR x4 high
        s.linkspeed_pass_q.push_back(16'h00F0); // 2nd visit passes
        s.expected_rx_mask = 3'b101;
        s.expected_tx_mask = 3'b101;
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);
        add_post_repair_path(s);
        push_scenario(s);

        // C5: Width degrade exhausted x16→x8→TRAINERROR
        // 1st LINKSPEED → REPAIR (x16→x8 low)
        // 2nd LINKSPEED → REPAIR attempt; partner sends 3'b000 → TRAINERROR
        reset_scenario(s);
        s.name          = "C5_WIDTH_DEGRADE_EXHAUSTED_AFTER_X16_TO_X8";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_TRAINERROR;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'h00FF); // 1st: repair to x8 low
        s.linkspeed_pass_q.push_back(16'h0000); // 2nd: all fail → try repair but code=3'b000
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);   // 1st repair
        add_post_repair_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);   // 2nd repair → TRAINERROR
        push_scenario(s);

        // C6: Width degrade exhausted x8→x4→TRAINERROR
        reset_scenario(s);
        s.name          = "C6_WIDTH_DEGRADE_EXHAUSTED_AFTER_X8_TO_X4";
        s.width         = WIDTH_X8;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_TRAINERROR;
        s.d2c_pass_mask = 16'h00FF;
        s.linkspeed_pass_q.push_back(16'h000F); // 1st: repair to x4 low
        s.linkspeed_pass_q.push_back(16'h0000); // 2nd: all fail → no repair possible
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);
        add_post_repair_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);
        push_scenario(s);

        // =====================================================================
        // GROUP D — PHY Retrain  (CORRECTED per updated MBTRAIN_overview.md)
        // =====================================================================

        // D1: LINKSPEED detects params_changed → PHYRETRAIN exit
        // Conditions: PHY_IN_RETRAIN=1, params_changed=1, all D2C pass
        // The DUT LOCAL FSM sees success + PHY_IN_RETRAIN + params_changed
        // → sends {exit to phy retrain req} → partner replies → DUT exits PHYRETRAIN
        reset_scenario(s);
        s.name           = "D1_PHY_RETRAIN_PARAMS_CHANGED";
        s.width          = WIDTH_X16;
        s.speed          = SPEED_32G;
        s.expected_exit  = EXIT_PHYRETRAIN;
        s.PHY_IN_RETRAIN = 1;
        s.params_changed = 1;
        s.d2c_pass_mask  = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF); // all pass, but params_changed → PHY retrain
        add_nominal_path(s);
        push_scenario(s);

        // D2: PHY Retrain Then Success
        // Re-entry at TXSELFCAL (mbtrain_txselfcal_req=1) after PHYRETRAIN
        // Expected path: TXSELFCAL → RXCLKCAL → ... → LINKSPEED → LINKINIT
        reset_scenario(s);
        s.name           = "D2_PHY_RETRAIN_REENTRY_SUCCESS";
        s.width          = WIDTH_X16;
        s.speed          = SPEED_32G;
        s.expected_exit  = EXIT_LINKINIT;
        s.PHY_IN_RETRAIN = 0; // cleared after PHYRETRAIN re-entry
        s.params_changed = 0;
        s.d2c_pass_mask  = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF);
        s.expected_rx_mask = 3'b011;
        s.expected_tx_mask = 3'b011;
        // Path starts at TXSELFCAL (driver sets mbtrain_txselfcal_req=1)
        s.state_path_q.push_back(LOG_MBTRAIN_TXSELFCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_RXCLKCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINCENTER);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER1);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_RXDESKEW);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER2);
        s.state_path_q.push_back(LOG_MBTRAIN_LINKSPEED);
        push_scenario(s);

        // D3: PHY Retrain Then Speed Degrade
        // Re-entry at SPEEDIDLE (mbtrain_speedidle_req=1)
        // Expected: SPEEDIDLE → TXSELFCAL → ... → LINKSPEED → LINKINIT
        reset_scenario(s);
        s.name           = "D3_PHY_RETRAIN_REENTRY_SPEED_DEGRADE";
        s.width          = WIDTH_X16;
        s.speed          = SPEED_48G; // re-entered at SPEEDIDLE with this speed
        s.expected_exit  = EXIT_LINKINIT;
        s.PHY_IN_RETRAIN = 0;
        s.params_changed = 0;
        s.d2c_pass_mask  = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF);
        s.expected_rx_mask = 3'b011;
        s.expected_tx_mask = 3'b011;
        // Path starts at SPEEDIDLE (driver sets mbtrain_speedidle_req=1)
        s.state_path_q.push_back(LOG_MBTRAIN_SPEEDIDLE);
        s.state_path_q.push_back(LOG_MBTRAIN_TXSELFCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_RXCLKCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINCENTER);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER1);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_RXDESKEW);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER2);
        s.state_path_q.push_back(LOG_MBTRAIN_LINKSPEED);
        push_scenario(s);

        // D4: PHY Retrain Then Width Degrade
        // Re-entry at REPAIR (mbtrain_repair_req=1)
        // Expected: REPAIR → TXSELFCAL → ... → LINKSPEED → LINKINIT
        reset_scenario(s);
        s.name           = "D4_PHY_RETRAIN_REENTRY_WIDTH_DEGRADE";
        s.width          = WIDTH_X16;
        s.speed          = SPEED_32G;
        s.expected_exit  = EXIT_LINKINIT;
        s.PHY_IN_RETRAIN = 0;
        s.params_changed = 0;
        s.d2c_pass_mask  = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'h00FF); // lower 8 pass after repair
        s.expected_rx_mask = 3'b001; // x8 low after repair
        s.expected_tx_mask = 3'b001;
        // Path starts at REPAIR (driver sets mbtrain_repair_req=1)
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);
        s.state_path_q.push_back(LOG_MBTRAIN_TXSELFCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_RXCLKCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINCENTER);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER1);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_RXDESKEW);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER2);
        s.state_path_q.push_back(LOG_MBTRAIN_LINKSPEED);
        push_scenario(s);

        // =====================================================================
        // GROUP E — Training Failure
        // =====================================================================

        // E1: PHY_IN_RETRAIN set but params_changed=0 → LINKINIT (clear & proceed)
        reset_scenario(s);
        s.name           = "E1_PHY_IN_RETRAIN_NO_PARAMS_CHANGE";
        s.width          = WIDTH_X16;
        s.speed          = SPEED_32G;
        s.expected_exit  = EXIT_LINKINIT;
        s.PHY_IN_RETRAIN = 1;
        s.params_changed = 0;
        s.d2c_pass_mask  = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF);
        s.expected_rx_mask = 3'b011;
        s.expected_tx_mask = 3'b011;
        add_nominal_path(s);
        push_scenario(s);

        // E2: REPAIR degrade not possible (partner sends 3'b000) → TRAINERROR
        reset_scenario(s);
        s.name          = "E2_REPAIR_DEGRADE_NOT_POSSIBLE";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_TRAINERROR;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'h00FF); // partial → triggers REPAIR
        add_nominal_path(s);
        s.state_path_q.push_back(LOG_MBTRAIN_REPAIR);
        push_scenario(s);

        // E3: RXDESKEW arc overflow → TRAINERROR
        // High speed, sweep returns min_eye_width=0 so LOCAL always wants DTC1 arc
        // After 4 arcs the partner sends TRAINERROR
        reset_scenario(s);
        s.name          = "E3_RXDESKEW_ARC_OVERFLOW";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_64G;
        s.expected_exit = EXIT_TRAINERROR;
        // d2c_pass_mask=all pass but min_eye_width=0 (model drives swept_code 0→2)
        // RXDESKEW LOCAL checks min_eye_width < MIN_DESIRED_SWEEP_RANGE → always true
        // → keeps taking DTC1 arcs until partner hits dtc1_arc_cnt==4 → TRAINERROR
        s.d2c_pass_mask = 16'hFFFF;
        s.state_path_q.push_back(LOG_MBTRAIN_VALVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATAVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_SPEEDIDLE);
        s.state_path_q.push_back(LOG_MBTRAIN_TXSELFCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_RXCLKCAL);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINCENTER);
        s.state_path_q.push_back(LOG_MBTRAIN_VALTRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINCENTER1);
        s.state_path_q.push_back(LOG_MBTRAIN_DATATRAINVREF);
        s.state_path_q.push_back(LOG_MBTRAIN_RXDESKEW); // will loop back to DTC1 ×4 then TRAINERROR
        push_scenario(s);

        // =====================================================================
        // GROUP F — Async / Reset
        // =====================================================================

        // F1: Soft reset mid-sequence (injected during RXCLKCAL) → IDLE
        reset_scenario(s);
        s.name          = "F1_SOFT_RESET_MID_SEQUENCE";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_IDLE;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF);
        s.inject_soft_reset_mid_sequence = 1;
        s.state_path_q.push_back(LOG_MBTRAIN_VALVREF);
        push_scenario(s);

        // F2: Disable mbtrain_en mid-sequence → IDLE
        reset_scenario(s);
        s.name          = "F2_DISABLE_MBTRAIN_MID_SEQUENCE";
        s.width         = WIDTH_X16;
        s.speed         = SPEED_32G;
        s.expected_exit = EXIT_IDLE;
        s.d2c_pass_mask = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF);
        s.inject_disable_mid_sequence = 1;
        s.state_path_q.push_back(LOG_MBTRAIN_VALVREF);
        push_scenario(s);

        // F3: Missing RXDESKEW end_resp → timeout expected
        reset_scenario(s);
        s.name                  = "F3_TIMEOUT_RXDESKEW_END_RESP_MISSING";
        s.width                 = WIDTH_X16;
        s.speed                 = SPEED_32G;
        s.expected_exit         = EXIT_TIMEOUT;
        s.expected_timeout      = 1;
        s.d2c_pass_mask         = 16'hFFFF;
        s.linkspeed_pass_q.push_back(16'hFFFF);
        s.suppress_response_en  = 1;
        s.suppress_response_msg = MBTRAIN_RXDESKEW_end_resp;
        add_nominal_path(s);
        push_scenario(s);

    endfunction // build_all_scenarios

endclass
