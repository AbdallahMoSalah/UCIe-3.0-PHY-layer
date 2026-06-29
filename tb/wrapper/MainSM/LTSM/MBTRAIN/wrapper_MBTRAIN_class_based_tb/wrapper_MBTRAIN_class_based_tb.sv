// =============================================================================
// wrapper_MBTRAIN_class_based_tb.sv — MBTRAIN Class-Based Testbench Top
//
// KEY FIXES vs previous version:
//  1. state_n_1 is driven by a combinational always block that tracks
//     current_mbtrain_substate transitions so wrapper_MBTRAIN.sv sees the
//     correct previous-substate value (used by SPEEDIDLE for degrade detection
//     and REPAIR for lane mask initialization).
//  2. All wrapper_MBTRAIN ports are connected to the interface correctly,
//     including the 5-bit wide sweep codes (MAX_CODE=16 → $clog2(17)=5 bits).
//  3. The TB drives phy_rx_tckn_shift=5'h01 so RXCLKCAL IQ loop terminates
//     (shift=0 would loop forever asking for adjustments).
//  4. mbtrain_cb_tb_top is a thin wrapper that just instantiates this module.
// =============================================================================
`timescale 1ns/1ps

module wrapper_MBTRAIN_class_based_tb;
    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;
    import mbtrain_cb_types_pkg::*;
    import mbtrain_cb_pkg::*;

    // =========================================================================
    // Parameters matching wrapper_MBTRAIN defaults
    // =========================================================================
    localparam int unsigned MAX_VAL_VREF_CODE  = 16;
    localparam int unsigned MAX_DATA_VREF_CODE = 16;
    localparam int unsigned MAX_DATA_PI_CODE   = 16;
    localparam int unsigned MAX_VAL_PI_CODE    = 16;
    localparam int unsigned MAX_DESKEW_CODE    = 16;
    localparam int unsigned MIN_DATA_PI_CODE   = 1;
    localparam int unsigned MIN_DESKEW_CODE    = 1;

    // Derived — must match wrapper_MBTRAIN parameter expression
    localparam int unsigned MAX_CODE = 16; // max of all above
    localparam int unsigned CW = $clog2(MAX_CODE + 1); // = 5 bits

    // =========================================================================
    // Clock generation
    // =========================================================================
    logic lclk;
    logic rst_n;

    initial lclk = 0;
    always #5 lclk = ~lclk; // 100 MHz (10 ns period)

    // =========================================================================
    // Interface instantiation
    // =========================================================================
    mbtrain_cb_if vif (.lclk(lclk), .rst_n(rst_n));

    // =========================================================================
    // state_n_1 combinational tracker
    // =========================================================================
    // wrapper_MBTRAIN uses state_n_1 in SPEEDIDLE (to know if degrade is legal)
    // and REPAIR (to know when to reload mbinit lane masks).
    // The TB must update state_n_1 to reflect the previous state whenever the
    // current_mbtrain_substate changes.
    //
    // Mapping rule (spec §4.5.3.3 / SPEEDIDLE entry):
    //   Entering SPEEDIDLE from DATAVREF     → state_n_1 = LOG_MBTRAIN_DATAVREF
    //   Entering SPEEDIDLE from LINKSPEED    → state_n_1 = LOG_MBTRAIN_LINKSPEED
    //   Entering SPEEDIDLE from PHYRETRAIN   → state_n_1 = LOG_PHYRETRAIN
    //   (L1/L1_L2 not exercised in this TB)
    state_n_e prev_substate_r;
    state_n_e cur_substate_w;
    assign cur_substate_w = vif.current_mbtrain_substate;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            prev_substate_r <= LOG_NOP;
        end else begin
            if (cur_substate_w != prev_substate_r &&
                cur_substate_w != LOG_NOP) begin
                prev_substate_r <= cur_substate_w;
            end else if (cur_substate_w == LOG_NOP) begin
                prev_substate_r <= LOG_NOP;
            end
        end
    end

    // Drive state_n_1 from the registered previous substate.
    // When MBTRAIN is not active (state_n_0 != LOG_MBTRAIN) keep LOG_NOP.
    assign vif.state_n_1 = (vif.state_n_0 == LOG_MBTRAIN) ?
                            prev_substate_r : LOG_NOP;

    // =========================================================================
    // DUT — wrapper_MBTRAIN
    // =========================================================================
    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE  (MAX_VAL_VREF_CODE ),
        .MAX_DATA_VREF_CODE (MAX_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE   (MAX_DATA_PI_CODE  ),
        .MAX_VAL_PI_CODE    (MAX_VAL_PI_CODE   ),
        .MAX_DESKEW_CODE    (MAX_DESKEW_CODE   ),
        .MIN_DATA_PI_CODE   (MIN_DATA_PI_CODE  ),
        .MIN_DESKEW_CODE    (MIN_DESKEW_CODE   )
    ) dut (
        // ── Clock & Reset ─────────────────────────────────────────────────────
        .lclk                           (lclk                               ),
        .rst_n                          (rst_n                              ),

        // ── MBTRAIN Control ───────────────────────────────────────────────────
        .mbtrain_en                     (vif.mbtrain_en                     ),
        .mbtrain_done                   (vif.mbtrain_done                   ),
        .current_mbtrain_substate       (vif.current_mbtrain_substate       ),
        .ltsm_trainerror_req            (vif.ltsm_trainerror_req            ),
        .ltsm_linkinit_req              (vif.ltsm_linkinit_req              ),
        .ltsm_phyretrain_req            (vif.ltsm_phyretrain_req            ),
        .mbtrain_txselfcal_req          (vif.mbtrain_txselfcal_req          ),
        .mbtrain_speedidle_req          (vif.mbtrain_speedidle_req          ),
        .mbtrain_repair_req             (vif.mbtrain_repair_req             ),

        // ── Analog settle ─────────────────────────────────────────────────────
        .analog_settle_time_done        (vif.analog_settle_time_done        ),
        .analog_settle_timer_en         (vif.analog_settle_timer_en         ),

        // ── LTSM state history ────────────────────────────────────────────────
        .state_n_0                      (vif.state_n_0                      ),
        .state_n_1                      (vif.state_n_1                      ),

        // ── Configuration registers ───────────────────────────────────────────
        .param_negotiated_max_speed     (vif.param_negotiated_max_speed     ),
        .is_continuous_clk_mode         (vif.is_continuous_clk_mode         ),
        .rf_cap_SPMW                    (vif.rf_cap_SPMW                    ),
        .rf_ctrl_target_link_width      (vif.rf_ctrl_target_link_width      ),
        .param_UCIe_S_x8               (vif.param_UCIe_S_x8               ),

        // ── PHY retrain flags ─────────────────────────────────────────────────
        .PHY_IN_RETRAIN                 (vif.PHY_IN_RETRAIN                 ),
        .params_changed                 (vif.params_changed                 ),
        .PHY_IN_RETRAIN_rst             (vif.PHY_IN_RETRAIN_rst             ),
        .busy_bit_rst                   (vif.busy_bit_rst                   ),

        // ── Lane masks ────────────────────────────────────────────────────────
        .mbinit_rx_data_lane_mask       (vif.mbinit_rx_data_lane_mask       ),
        .mbinit_tx_data_lane_mask       (vif.mbinit_tx_data_lane_mask       ),
        .mb_rx_data_lane_mask           (vif.mb_rx_data_lane_mask           ),
        .mb_tx_data_lane_mask           (vif.mb_tx_data_lane_mask           ),

        // ── D2C sweep interface ───────────────────────────────────────────────
        .local_sweep_en                 (vif.local_sweep_en                 ),
        .partner_sweep_en               (vif.partner_sweep_en               ),
        .sweep_active_lanes             (vif.sweep_active_lanes             ),
        .sweep_done                     (vif.sweep_done                     ),
        .sweep_swept_code               (vif.sweep_swept_code               ),
        .sweep_best_code                (vif.sweep_best_code                ),
        .sweep_min_eye_width            (vif.sweep_min_eye_width            ),
        .d2c_perlane_pass               (vif.d2c_perlane_pass               ),

        // ── PHY controls (outputs) ────────────────────────────────────────────
        .phy_negotiated_speed           (vif.phy_negotiated_speed           ),
        .phy_tx_selfcal_en              (vif.phy_tx_selfcal_en              ),
        .phy_rx_clock_lock_en           (vif.phy_rx_clock_lock_en           ),
        .phy_rx_track_lock_en           (vif.phy_rx_track_lock_en           ),
        .phy_rx_phase_detector_en       (vif.phy_rx_phase_detector_en       ),

        // ── RXCLKCAL IQ PHY interface ─────────────────────────────────────────
        // Drive phy_rx_tckn_shift=0 → IQ local FSM sees shift=0 → Done immediately
        .phy_rx_tckn_shift              (5'h00                              ),
        .phy_rx_decrement_shift         (1'b0                               ),
        .phy_tx_tckn_shift_en           (vif.phy_tx_tckn_shift_en           ),
        .phy_tx_tckn_shift              (vif.phy_tx_tckn_shift              ),
        .phy_tx_decrement_shift         (vif.phy_tx_decrement_shift         ),
        // tckn_shift_out_of_range=0 → partner IQ always reports Success
        .phy_tx_tckn_shift_out_of_range (1'b0                               ),

        // ── PHY code outputs (monitored by TB) ───────────────────────────────
        .phy_rx_val_vref_ctrl           (vif.phy_rx_val_vref_ctrl           ),
        .phy_rx_data_vref_ctrl          (vif.phy_rx_data_vref_ctrl          ),
        .phy_tx_val_pi_phase_ctrl       (vif.phy_tx_val_pi_phase_ctrl       ),
        .phy_tx_data_pi_phase_ctrl      (vif.phy_tx_data_pi_phase_ctrl      ),
        .phy_rx_deskew_ctrl             (vif.phy_rx_deskew_ctrl             ),
        .phy_tx_eq_preset_ctrl          (vif.phy_tx_eq_preset_ctrl          ),
        .phy_tx_eq_preset_en            (vif.phy_tx_eq_preset_en            ),

        // ── MB lane selectors (outputs, monitored) ────────────────────────────
        .substate_mb_tx_clk_lane_sel    (vif.substate_mb_tx_clk_lane_sel   ),
        .substate_mb_tx_data_lane_sel   (vif.substate_mb_tx_data_lane_sel  ),
        .substate_mb_tx_val_lane_sel    (vif.substate_mb_tx_val_lane_sel   ),
        .substate_mb_tx_trk_lane_sel    (vif.substate_mb_tx_trk_lane_sel   ),
        .substate_mb_rx_clk_lane_sel    (vif.substate_mb_rx_clk_lane_sel   ),
        .substate_mb_rx_data_lane_sel   (vif.substate_mb_rx_data_lane_sel  ),
        .substate_mb_rx_val_lane_sel    (vif.substate_mb_rx_val_lane_sel   ),
        .substate_mb_rx_trk_lane_sel    (vif.substate_mb_rx_trk_lane_sel   ),
        .rxclkcal_mb_tx_pattern_en      (vif.rxclkcal_mb_tx_pattern_en     ),
        .rxclkcal_mb_tx_pattern_setup   (vif.rxclkcal_mb_tx_pattern_setup  ),
        .rxclkcal_mb_tx_clk_pattern_sel (vif.rxclkcal_mb_tx_clk_pattern_sel),

        // ── SB outputs (DUT → TB) ─────────────────────────────────────────────
        .substate_tx_sb_msg_valid       (vif.substate_tx_sb_msg_valid       ),
        .substate_tx_sb_msg             (vif.substate_tx_sb_msg             ),
        .substate_tx_msginfo            (vif.substate_tx_msginfo            ),
        .substate_tx_data_field         (vif.substate_tx_data_field         ),

        // ── SB inputs (TB → DUT) ──────────────────────────────────────────────
        .rx_sb_msg_valid                (vif.rx_sb_msg_valid                ),
        .rx_sb_msg                      (vif.rx_sb_msg                      ),
        .rx_msginfo                     (vif.rx_msginfo                     )
    );

    // =========================================================================
    // Hard reset sequence
    // =========================================================================
    initial begin
        rst_n = 1'b0;
        repeat(10) @(posedge lclk);
        @(negedge lclk);
        rst_n = 1'b1;
    end

    // =========================================================================
    // Main test program
    // =========================================================================
    initial begin
        // Build and run all scenarios
        mbtrain_cb_env          env;
        mbtrain_cb_testlib      testlib;
        mbtrain_scenario_s      scenarios[$];

        // Wait for reset to deassert
        @(posedge rst_n);
        repeat(5) @(posedge lclk);

        // Create environment
        env     = new(vif);
        testlib = new();

        // Get scenario list from testlib
        scenarios = testlib.scenarios;

        $display("==================================================");
        $display("MBTRAIN CLASS-BASED TB STARTING");
        $display("Total scenarios: %0d", scenarios.size());
        $display("==================================================");

        // Run all scenarios
        env.run_all(scenarios);

        // End simulation
        repeat(20) @(posedge lclk);
        $finish;
    end

    // =========================================================================
    // Simulation timeout guard (absolute backstop)
    // =========================================================================
    initial begin
        #50_000_000; // 50 ms at 1ns timescale
        $display("[FATAL] Simulation timeout — exceeded 50ms absolute limit");
        $finish;
    end

endmodule
