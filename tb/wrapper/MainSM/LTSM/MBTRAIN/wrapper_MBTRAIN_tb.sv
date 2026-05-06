`timescale 1ps/1ps
// =============================================================================
// Module  : unit_wrapper_MBTRAIN_tb
// Purpose : Integration-level testbench for wrapper_MBTRAIN + wrapper_D2C_PT.
//
// Architecture note:
//   ltsm_tb_attachments cannot be used here because it internally instantiates
//   unit_RX_D2C_PT and unit_TX_D2C_PT, which would conflict with the D2C
//   modules already inside wrapper_D2C_PT (multi-driven test_d2c_done, etc.).
//   Instead, the MB pattern-counter, SB echo-back, and timer models are
//   implemented inline below, mirroring the approach in ltsm_tb_attachments.sv.
// =============================================================================

module wrapper_MBTRAIN_tb ();
    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;
    import LTSM_state_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter integer LCLK_PERIOD          = 1000;   // 1 ns (1 GHz), ×1000 for ps timescale
    parameter integer ANALOG_SETTLE_CYCLES = 10;
    parameter real    SB_CLK_PERIOD        = 1.25;   // 800 MHz SB clock (ns)
    parameter integer SB_TX_PULSE_WIDTH    = 8;      // lclk cycles to stretch tx_sb_msg_valid_pulse

    // ── Simulation-speed parameters ─────────────────────────────────────────
    // Keep sweep ranges tiny so each MBTRAIN run takes O(thousands) not
    // O(hundreds-of-thousands) of LCLK cycles.
    parameter integer SIM_MAX_VAL_VREF_CODE  = 12; // sweep vref 8→12  (vs 0→128 in silicon)
    parameter integer SIM_MIN_VAL_VREF_CODE  = 8;  // → 4 vref codes total
    parameter integer SIM_MAX_DATA_VREF_CODE = 12;
    parameter integer SIM_MIN_DATA_VREF_CODE = 8;
    parameter integer SIM_MAX_PI_PHASE       = 4;  // PI phase sweep 0→4 steps (vs 0→64)
    parameter integer SIM_MIN_PI_PHASE       = 0;
    parameter integer SIM_D2C_ITER_COUNT     = 4;  // spec: 128 iters; 4 is enough for FSM coverage
    parameter integer SIM_D2C_BURST_COUNT    = 2;  // spec: 8-cycle burst; 2 keeps MB model fast
    // Per-substate RTL timeout (each sub-state gets this many cycles before
    // timeout_8ms_occured is asserted by the testbench timer).
    parameter integer TIMEOUT_CYCLES         = 10_000;
    // Scenario-level abort for run_test()'s fork timer: must cover ALL 13 substates
    // running back-to-back.  13 × TIMEOUT_CYCLES gives each one its full budget.
    parameter integer SCENARIO_ABORT_CYCLES  = 13 * TIMEOUT_CYCLES; // = 130 000

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    reg lclk, rst_n;
    initial begin lclk = 0; forever #(LCLK_PERIOD/2) lclk = ~lclk; end

    // Shared interface (Final signals used by the TB models)
    internal_ltsm_if intf (.lclk(lclk), .rst_n(rst_n));

    // Isolated interfaces for wrapper_MBTRAIN ports to prevent multi-driver 'X' states
    internal_ltsm_if mbtrain_intf (.lclk(lclk), .rst_n(rst_n));
    internal_ltsm_if d2c_intf (.lclk(lclk), .rst_n(rst_n));

    // Keep current_ltsm_state = MBTRAIN so wrapper_D2C_PT selects mbtrain branch
    assign intf.current_ltsm_state = MBTRAIN;

    // Dummy interface for wrapper_D2C_PT.mbinit_if (never active in this TB)
    internal_ltsm_if mbinit_intf (.lclk(lclk), .rst_n(rst_n));
    assign mbinit_intf.rx_pt_en = 1'b0;
    assign mbinit_intf.tx_pt_en = 1'b0;

    // Interface for D2C MUX outputs
    internal_ltsm_if d2c_mux_intf (.lclk(lclk), .rst_n(rst_n));

    // =========================================================================
    // DUT 1 – wrapper_MBTRAIN
    // =========================================================================
    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE  (SIM_MAX_VAL_VREF_CODE ),
        .MIN_VAL_VREF_CODE  (SIM_MIN_VAL_VREF_CODE ),
        .MAX_DATA_VREF_CODE (SIM_MAX_DATA_VREF_CODE),
        .MIN_DATA_VREF_CODE (SIM_MIN_DATA_VREF_CODE),
        .MAX_PI_PHASE       (SIM_MAX_PI_PHASE      ),
        .MIN_PI_PHASE       (SIM_MIN_PI_PHASE      ),
        .D2C_ITER_COUNT     (SIM_D2C_ITER_COUNT    ),
        .D2C_BURST_COUNT    (SIM_D2C_BURST_COUNT   )
    ) u_wrapper_mbtrain (
        .mbtrain_if (mbtrain_intf.mbtrain_mp  ),
        .d2c_if     (d2c_intf.substate2d2c_mp )
    );

    // =========================================================================
    // DUT 2 – wrapper_D2C_PT
    //   mbinit_if            -> mbinit_intf (isolated, never selected)
    //   mbtrain_if           -> d2c_intf.d2c2substate_mp (active path)
    //   current_ltsm_state_if-> intf.current_ltsm_state_mp
    //   mux_if               -> d2c_mux_intf.d2c2mux_mp
    // =========================================================================
    wrapper_D2C_PT u_wrapper_d2c_pt (
        .mbinit_if            (mbinit_intf.d2c2substate_mp     ),
        .mbtrain_if           (d2c_intf.d2c2substate_mp        ),
        .current_ltsm_state_if(intf.current_ltsm_state_mp      ),
        .mux_if               (d2c_mux_intf.d2c2mux_mp         )
    );

    // MUX variables for MB/SB Models
    wire d2c_active = (d2c_intf.tx_pt_en || d2c_intf.rx_pt_en);

    wire        active_mb_tx_pattern_en = d2c_active ? d2c_mux_intf.mb_tx_pattern_en  : mbtrain_intf.mb_tx_pattern_en;
    wire [15:0] active_mb_tx_burst_count= d2c_active ? d2c_mux_intf.mb_tx_burst_count : mbtrain_intf.mb_tx_burst_count;
    wire [15:0] active_mb_tx_idle_count = d2c_active ? d2c_mux_intf.mb_tx_idle_count  : mbtrain_intf.mb_tx_idle_count;
    wire [15:0] active_mb_tx_iter_count = d2c_active ? d2c_mux_intf.mb_tx_iter_count  : mbtrain_intf.mb_tx_iter_count;

    wire        active_tx_sb_msg_valid  = d2c_active ? d2c_mux_intf.tx_sb_msg_valid   : mbtrain_intf.tx_sb_msg_valid;
    msg_no_e    active_tx_sb_msg;
    assign      active_tx_sb_msg        = d2c_active ? d2c_mux_intf.tx_sb_msg         : mbtrain_intf.tx_sb_msg;

    // Feedback to D2C
    assign d2c_mux_intf.mb_tx_pattern_count_done = intf.mb_tx_pattern_count_done;
    assign d2c_mux_intf.mb_rx_compare_done       = intf.mb_rx_compare_done;
    assign d2c_mux_intf.mb_rx_aggr_err           = intf.mb_rx_aggr_err;
    assign d2c_mux_intf.mb_rx_perlane_err        = intf.mb_rx_perlane_err;
    assign d2c_mux_intf.mb_rx_val_err            = intf.mb_rx_val_err;
    assign d2c_mux_intf.mb_rx_clk_err            = intf.mb_rx_clk_err;

    assign d2c_mux_intf.rx_sb_msg_valid          = intf.rx_sb_msg_valid;
    assign d2c_mux_intf.rx_sb_msg                = intf.rx_sb_msg;
    assign d2c_mux_intf.rx_msginfo               = intf.rx_msginfo;
    assign d2c_mux_intf.rx_data_field            = intf.rx_data_field;

    // Bypass inputs from intf to mbtrain_intf
    assign mbtrain_intf.mb_tx_pattern_count_done = intf.mb_tx_pattern_count_done;
    assign mbtrain_intf.timeout_8ms_occured      = intf.timeout_8ms_occured;
    assign mbtrain_intf.analog_settle_time_done  = intf.analog_settle_time_done;
    assign mbtrain_intf.rx_sb_msg_valid          = intf.rx_sb_msg_valid;
    assign mbtrain_intf.rx_sb_msg                = intf.rx_sb_msg;
    assign mbtrain_intf.rx_msginfo               = intf.rx_msginfo;
    assign mbtrain_intf.rx_data_field            = intf.rx_data_field;

    // Bypass final outputs to intf so the rest of TB can monitor them easily
    assign intf.trainerror_req           = mbtrain_intf.trainerror_req;
    assign intf.tx_pt_en                 = d2c_intf.tx_pt_en;
    assign intf.rx_pt_en                 = d2c_intf.rx_pt_en;
    assign intf.phy_tx_val_pi_phase_ctrl = mbtrain_intf.phy_tx_val_pi_phase_ctrl;

    // =========================================================================
    // ── MB MODEL ──────────────────────────────────────────────────────────────
    // Watches mb_tx_pattern_en, counts iterations, then drives pattern_count_done
    // and comparison results back to intf (mirrors ltsm_tb_attachments MB logic).
    // =========================================================================
    integer burst_ctr, idle_ctr, iter_ctr;

    assign intf.mb_tx_pattern_count_done =
        (iter_ctr >= active_mb_tx_iter_count) && (intf.tb_wait_timeout == 0) ? 1 : 0;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            burst_ctr                  <= 0;
            idle_ctr                   <= 0;
            iter_ctr                   <= 0;
            intf.mb_rx_compare_done    <= 0;
            intf.mb_rx_aggr_err        <= 0;
            intf.mb_rx_perlane_err     <= 0;
            intf.mb_rx_val_err         <= 0;
            intf.mb_rx_clk_err         <= 0;
        end else begin
            if (active_mb_tx_pattern_en || intf.rx_pt_en) begin
                if (burst_ctr < active_mb_tx_burst_count && iter_ctr < active_mb_tx_iter_count)
                    burst_ctr <= burst_ctr + 1;
                else if (idle_ctr < active_mb_tx_idle_count && iter_ctr < active_mb_tx_iter_count)
                    idle_ctr <= idle_ctr + 1;
                else if (iter_ctr < active_mb_tx_iter_count) begin
                    iter_ctr  <= iter_ctr + 1;
                    burst_ctr <= 0;
                    idle_ctr  <= 0;
                end
            end else begin
                burst_ctr <= 0; idle_ctr <= 0; iter_ctr <= 0;
            end

            if (intf.mb_tx_pattern_count_done) begin
                intf.mb_rx_compare_done <= 1;
                intf.mb_rx_aggr_err     <= intf.tb_aggr_err;
                intf.mb_rx_perlane_err  <= intf.tb_perlane_err;
                intf.mb_rx_val_err      <= intf.tb_val_err;
                intf.mb_rx_clk_err      <= intf.tb_clk_err;
            end else begin
                intf.mb_rx_compare_done <= 0;
            end
        end
    end

    // PHY feedback stubs for RXCLKCAL
    assign intf.phy_rx_tckn_shift          = 5'd6;
    assign intf.phy_rx_decrement_shift     = 1'b0;
    // phy_rx_clk_drift_cal_state/valid are not used by any sub-state or controller.

    // =========================================================================
    // ── SB MODEL ──────────────────────────────────────────────────────────────
    // SB clock, pulse stretcher, echo-back FSM – mirrors ltsm_tb_attachments.
    // =========================================================================
    reg sb_clk;
    initial begin sb_clk = 0; forever #(SB_CLK_PERIOD/2 * 1000) sb_clk = ~sb_clk; end

    msg_no_e stable_tx_sb_msg;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) stable_tx_sb_msg <= NOTHING;
        else        stable_tx_sb_msg <= active_tx_sb_msg;
    end

    reg active_tx_sb_msg_valid_d;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) active_tx_sb_msg_valid_d <= 0;
        else active_tx_sb_msg_valid_d <= active_tx_sb_msg_valid;
    end
    wire tx_sb_msg_valid_edge = active_tx_sb_msg_valid && !active_tx_sb_msg_valid_d;

    reg [$clog2(SB_TX_PULSE_WIDTH):0] pulse_ctr;
    reg tx_sb_valid_pulse;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            tx_sb_valid_pulse <= 0; pulse_ctr <= 0;
        end else if (tx_sb_msg_valid_edge) begin
            tx_sb_valid_pulse <= 1;
            pulse_ctr <= 1;
        end else if (pulse_ctr > 0 && pulse_ctr < SB_TX_PULSE_WIDTH-1) begin
            tx_sb_valid_pulse <= 1;
            pulse_ctr <= pulse_ctr + 1;
        end else begin
            tx_sb_valid_pulse <= 0; pulse_ctr <= 0;
        end
    end

    integer sb_wait;
    reg sb_active;
    always @(posedge sb_clk or negedge rst_n) begin
        if (!rst_n) begin
            intf.rx_sb_msg_valid <= 0;
            intf.rx_sb_msg       <= NOTHING;
            intf.rx_msginfo      <= 0;
            intf.rx_data_field   <= 0;
            sb_wait              <= 0;
            sb_active            <= 0;
        end else begin
            if (!intf.tb_wait_timeout) begin
                if (tx_sb_valid_pulse && !sb_active && stable_tx_sb_msg != NOTHING)
                    sb_active <= 1;
                if (sb_active) begin
                    sb_wait <= sb_wait + 1;
                    if (sb_wait == 4) begin
                        intf.rx_sb_msg_valid <= 1;
                        intf.rx_sb_msg       <= intf.tb_wrong_sb_msg_en ? intf.tb_wrong_sb_msg : stable_tx_sb_msg;
                        intf.rx_msginfo      <= intf.tb_rx_msginfo;
                        intf.rx_data_field   <= intf.tb_rx_data_field;
                    end else if (sb_wait == 5) begin
                        intf.rx_sb_msg_valid <= 0;
                        sb_wait              <= 0;
                        sb_active            <= 0;
                    end
                end
            end else begin
                intf.rx_sb_msg_valid <= 0;
            end
        end
    end

    // =========================================================================
    // Aliases and counters  (declared early – referenced by timer blocks below)
    // =========================================================================
    mbtrain_substate_e current_substate;
    assign current_substate = intf.current_mbtrain_substate;

    integer success_count = 0, fail_count = 0;
    integer lclk_counter  = 0;
    reg     cnt_run       = 0;
    int     test_no       = 1;

    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) lclk_counter <= 0;
        else        lclk_counter <= cnt_run ? lclk_counter + 1 : 0;
    end

    // =========================================================================
    // ── TIMER MODELS ──────────────────────────────────────────────────────────
    // ── Timeout counter – resets per sub-state ─────────────────────────────
    // Each sub-state gets its own independent TIMEOUT_CYCLES budget.
    // Without the substate-change reset the counter accumulates across all
    // 13 sub-states and fires the timeout flag on the very first cycle of
    // later sub-states.
    integer timeout_ctr;
    mbtrain_substate_e timeout_prev_substate;
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_ctr               <= 0;
            timeout_prev_substate     <= MBTRAIN_IDLE;
            intf.timeout_8ms_occured  <= 0;
        end else begin
            // Clear counter on sub-state transition (fresh budget per sub-state)
            if (current_substate !== timeout_prev_substate) begin
                timeout_ctr              <= 0;
                timeout_prev_substate    <= current_substate;
                intf.timeout_8ms_occured <= 0;
            end else begin
                timeout_ctr              <= intf.timeout_timer_en ? timeout_ctr + 1 : 0;
                intf.timeout_8ms_occured <= (timeout_ctr >= TIMEOUT_CYCLES) ? 1 : 0;
            end
        end
    end

    integer settle_ctr;
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) settle_ctr <= 0;
        else        settle_ctr <= intf.analog_settle_timer_en ?
            (settle_ctr < ANALOG_SETTLE_CYCLES ? settle_ctr + 1 : settle_ctr) : 0;
    end
    assign intf.analog_settle_time_done =
        (settle_ctr >= ANALOG_SETTLE_CYCLES) && intf.analog_settle_timer_en;

    // =========================================================================
    // Task: reset
    // =========================================================================
    task reset();
        rst_n                           = 0;
        intf.mbtrain_en                 = 0;
        intf.mbtrain_repair_req         = 0;
        intf.mbtrain_speedidle_req      = 0;
        intf.mbtrain_txselfcal_req      = 0;
        intf.phyretrain_PHY_IN_RETRAIN  = 0;
        intf.params_changed             = 0;
        intf.tb_aggr_err                = 0;
        intf.tb_perlane_err             = 0;
        intf.tb_val_err                 = 0;
        intf.tb_clk_err                 = 0;
        intf.tb_wait_timeout            = 0;
        intf.tb_wrong_sb_msg_en         = 0;
        intf.tb_wrong_sb_msg            = NOTHING;
        intf.tb_rx_msginfo              = 0;
        intf.tb_rx_data_field           = 0;
        intf.rf_cap_SPMW                = 0;
        intf.rf_ctrl_target_link_width  = 4'd2;
        intf.param_UCIe_S_x8           = 0;
        intf.param_negotiated_max_speed = 3'd0;
        intf.mbinit_rx_data_lane_mask   = 3'b011;
        intf.mbinit_tx_data_lane_mask   = 3'b011;
        intf.cfg_train4_max_err_thresh_aggr    = 16'hFFFF;
        intf.cfg_train4_max_err_thresh_perlane = 12'hFFF;
        #10; rst_n = 1;
    endtask

    // =========================================================================
    // Task: run_test
    // =========================================================================
    task run_test(
            input integer  abort_after   = SCENARIO_ABORT_CYCLES,
            input integer  wrong_sb_dly  = SCENARIO_ABORT_CYCLES,
            input msg_no_e wrong_sb_msg  = NOTHING
        );
        cnt_run = 1;
        fork : exec
            begin // Main: enable, wait for done or error
                intf.mbtrain_en = 1;
                wait (intf.mbtrain_done || intf.trainerror_req);
                #1step;
                intf.mbtrain_en = 0;
                if (!intf.trainerror_req) begin
                    wait(current_substate == MBTRAIN_IDLE);
                    success_count++;
                    $display("%0t ps [%0d cycles]: PASS - mbtrain_done.", $realtime, lclk_counter);
                end else if (intf.tb_wait_timeout || intf.tb_wrong_sb_msg_en) begin
                    success_count++;
                    $display("%0t ps [%0d cycles]: PASS - trainerror_req as expected.", $realtime, lclk_counter);
                end else begin
                    fail_count++;
                    $display("%0t ps: FAIL - unexpected trainerror_req!", $realtime);
                    $stop;
                end
                $display("(Success=%0d Fail=%0d Cycles=%0d)\n", success_count, fail_count, lclk_counter);
                disable exec;
            end
            begin // SB wrong-msg injector
                repeat(wrong_sb_dly) @(posedge lclk);
                if (wrong_sb_msg != NOTHING) intf.tb_wrong_sb_msg_en = 1;
                intf.tb_wrong_sb_msg = wrong_sb_msg;
            end
            begin // Timeout injector
                repeat(abort_after) @(posedge lclk);
                intf.tb_wait_timeout = 1;
            end
        join
        #1step;
        cnt_run = 0;
        intf.tb_wait_timeout   = 0;
        intf.tb_wrong_sb_msg_en = 0;
        @(posedge lclk); #1step;
    endtask

    // Substate transition logger – fires only when current_substate changes.
    // Avoids any per-cycle or x-state !== comparison hazards.
    ltsm_state_n_pkg::mbtrain_substate_e dbg_prev_substate;
    always @(posedge lclk) begin
        if (rst_n && current_substate !== dbg_prev_substate) begin
            $display("%0t ps [cyc %0d] ==> substate: %s  (tx_d2c_st=%0d rx_d2c_st=%0d tx_pt_en=%0b rx_pt_en=%0b)",
                $realtime, lclk_counter, current_substate.name(),
                u_wrapper_d2c_pt.TX_D2C_PT.current_state,
                u_wrapper_d2c_pt.RX_D2C_PT.current_state,
                intf.tx_pt_en, intf.rx_pt_en);
            dbg_prev_substate <= current_substate;
        end
    end

    // TX/RX D2C inner-state monitor: fires whenever tx_pt_en or rx_pt_en is active
    // and the inner TX/RX D2C FSM state changes. Helps diagnose deadlocks.
    reg [3:0] dbg_prev_tx_d2c_st = 4'hF;
    reg [3:0] dbg_prev_rx_d2c_st = 4'hF;
    always @(posedge lclk) begin
        if (rst_n && (intf.tx_pt_en || intf.rx_pt_en)) begin
            if (u_wrapper_d2c_pt.TX_D2C_PT.current_state !== dbg_prev_tx_d2c_st) begin
                // $display("%0t ps [cyc %0d]  TX_D2C st: %0d->%0d  sb_msg=%0d sb_valid=%0b",
                //     $realtime, lclk_counter,
                //     dbg_prev_tx_d2c_st,
                //     u_wrapper_d2c_pt.TX_D2C_PT.current_state,
                //     intf.rx_sb_msg, intf.rx_sb_msg_valid);
                dbg_prev_tx_d2c_st <= u_wrapper_d2c_pt.TX_D2C_PT.current_state;
            end
            if (u_wrapper_d2c_pt.RX_D2C_PT.current_state !== dbg_prev_rx_d2c_st) begin
                // $display("%0t ps [cyc %0d]  RX_D2C st: %0d->%0d  sb_msg=%0d sb_valid=%0b",
                //     $realtime, lclk_counter,
                //     dbg_prev_rx_d2c_st,
                //     u_wrapper_d2c_pt.RX_D2C_PT.current_state,
                //     intf.rx_sb_msg, intf.rx_sb_msg_valid);
                dbg_prev_rx_d2c_st <= u_wrapper_d2c_pt.RX_D2C_PT.current_state;
            end
        end else begin
            dbg_prev_tx_d2c_st <= 4'hF;
            dbg_prev_rx_d2c_st <= 4'hF;
        end
    end

    // =========================================================================
    // Main
    // =========================================================================
    initial begin
        reset();

        // Debug prints for inner FSM
        // always @(u_wrapper_mbtrain.u_valvref.current_state) begin
        //    $display("%0t ps: VALVREF FSM = %s", $realtime, u_wrapper_mbtrain.u_valvref.current_state.name());
        // end

        // -----------------------------------------------------------------
        // Scenario 1 – Full x16, 4 GT/s, no errors
        // -----------------------------------------------------------------
        $display("\n===> Scenario %0d: x16, 4GT/s, no errors <===", test_no++);
        intf.param_negotiated_max_speed = 3'd0;
        intf.mbinit_rx_data_lane_mask   = 3'b011;
        run_test();

        // -----------------------------------------------------------------
        // Scenario 2 – x8 SPMW mode, 8 GT/s
        // -----------------------------------------------------------------
        $display("\n===> Scenario %0d: x8 SPMW, 8GT/s, no errors <===", test_no++);
        intf.rf_cap_SPMW                = 1;
        intf.param_negotiated_max_speed = 3'd1;
        intf.mbinit_rx_data_lane_mask   = 3'b001;
        intf.mbinit_tx_data_lane_mask   = 3'b001;
        run_test();
        intf.rf_cap_SPMW = 0;

        // -----------------------------------------------------------------
        // Scenario 3 – x16, 32 GT/s (EQ preset path)
        // -----------------------------------------------------------------
        $display("\n===> Scenario %0d: x16, 32GT/s (EQ preset) <===", test_no++);
        intf.param_negotiated_max_speed = 3'd4;
        intf.mbinit_rx_data_lane_mask   = 3'b011;
        intf.mbinit_tx_data_lane_mask   = 3'b011;
        run_test();

        // -----------------------------------------------------------------
        // Scenario 4 – Width-degrade (lanes 0-7 only)
        // -----------------------------------------------------------------
        $display("\n===> Scenario %0d: Width-degrade lanes 0-7 <===", test_no++);
        intf.param_negotiated_max_speed = 3'd0;
        intf.mbinit_rx_data_lane_mask   = 3'b001;
        intf.mbinit_tx_data_lane_mask   = 3'b001;
        run_test();

        // -----------------------------------------------------------------
        // Scenario 5 – PHYRETRAIN path from LINKSPEED
        // -----------------------------------------------------------------
        $display("\n===> Scenario %0d: PHYRETRAIN path (params_changed=1) <===", test_no++);
        intf.param_negotiated_max_speed = 3'd0;
        intf.mbinit_rx_data_lane_mask   = 3'b011;
        intf.mbinit_tx_data_lane_mask   = 3'b011;
        intf.phyretrain_PHY_IN_RETRAIN  = 1;
        intf.params_changed             = 1;
        run_test();
        intf.phyretrain_PHY_IN_RETRAIN  = 0;
        intf.params_changed             = 0;

        // -----------------------------------------------------------------
        // Scenarios 6-8 – SB timeout (8ms)
        // -----------------------------------------------------------------
        repeat(3) begin
            $display("\n===> Scenario %0d: SB timeout (8ms) <===", test_no++);
            intf.param_negotiated_max_speed = 3'd0;
            intf.mbinit_rx_data_lane_mask   = 3'b011;
            intf.mbinit_tx_data_lane_mask   = 3'b011;
            run_test(.abort_after(TIMEOUT_CYCLES), .wrong_sb_dly($urandom_range(0,560_000)));
            reset();
        end

        // -----------------------------------------------------------------
        // Scenario 9 – TRAINERROR_Entry_req on SB
        // -----------------------------------------------------------------
        $display("\n===> Scenario %0d: TRAINERROR_Entry_req on SB <===", test_no++);
        intf.param_negotiated_max_speed = 3'd0;
        intf.mbinit_rx_data_lane_mask   = 3'b011;
        run_test(.wrong_sb_dly(300_000), .wrong_sb_msg(TRAINERROR_Entry_req));
        reset();

        // -----------------------------------------------------------------
        // Randomised loop – 50 iterations
        // -----------------------------------------------------------------
        for (int i = 0; i < 50; i++) begin
            msg_no_e rnd_msg;
            $display("\n===> Scenario %0d: Random %0d/50 <===", test_no++, i+1);
            rnd_msg = ($urandom_range(0,4) == 0) ? TRAINERROR_Entry_req : NOTHING;
            intf.rf_cap_SPMW                = $urandom_range(0,1);
            intf.param_negotiated_max_speed = $urandom_range(0,7);
            intf.mbinit_rx_data_lane_mask   = $urandom_range(0,3);
            intf.mbinit_tx_data_lane_mask   = $urandom_range(0,3);
            intf.mbtrain_repair_req         = $urandom_range(0,1);
            intf.mbtrain_speedidle_req      = $urandom_range(0,1);
            intf.mbtrain_txselfcal_req      = $urandom_range(0,1);
            intf.tb_aggr_err                = $urandom_range(0,1000);
            intf.tb_perlane_err             = $urandom_range(0,16'hFFFF);
            intf.tb_val_err                 = $urandom_range(0,1);
            run_test(.wrong_sb_dly($urandom_range(0,400_000)), .wrong_sb_msg(rnd_msg));
            reset();
        end

        // -----------------------------------------------------------------
        // Final banner
        // -----------------------------------------------------------------
        if (fail_count == 0) begin
            $display("         .=====================================.    ");
            $display("     ===|      Congratulations! All PASSED      |===");
            $display("         '====================================='    \n\n");
        end else begin
            $display("  ====  FAILED: %0d scenario(s).  ====", fail_count);
        end
        @(posedge lclk); $stop;
    end

endmodule
