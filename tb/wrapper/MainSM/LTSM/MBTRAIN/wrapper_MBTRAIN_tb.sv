`timescale 1ns/1ps

// ====================================================================================================
// wrapper_MBTRAIN_tb.sv
//
// Integration Testbench for wrapper_MBTRAIN.
// Simulates two interconnected UCIe dies (Die 0 and Die 1) running the full MBTRAIN sequence.
//
// Architecture:
//   - Two independent wrapper_MBTRAIN instances (dut_die0, dut_die1).
//   - Each die has an ltsm_tb_if + ltsm_tb_attachments, which internally instantiate:
//       * unit_D2C_sweep  → drives sweep_done, swept_code, best_code, min_eye_width.
//       * wrapper_D2C_PT_top → drives d2c_perlane_pass, d2c_aggr_pass, d2c_val_pass.
//       * Timeout 8ms counter (intf.timeout_8ms_occured — unused by new wrapper, kept for compat).
//       * Analog-settle counter (intf.analog_settle_time_done → wrapper.analog_settle_time_done).
//   - ENABLE_LOOPBACK = 0: cross-die SB routing is done explicitly via shift-register pipelines.
//
// Ports changed vs old wrapper_MBTRAIN (corrected in this TB):
//   REMOVED: timeout_8ms_occured, timeout_timer_en (no longer wrapper ports)
//            d2c_aggr_pass, d2c_val_pass           (no longer wrapper ports)
//            d2c_state_n                            (commented out in wrapper)
//            ltsm_repair_req, ltsm_speedidle_req    (commented out in wrapper)
//            state_n[3:0] array port                (replaced by state_n_0, state_n_1 scalars)
//   KEPT:    d2c_perlane_pass (still a wrapper input, driven by intf.d2c_perlane_pass)
//            analog_settle_time_done, analog_settle_timer_en (still in wrapper)
//            sweep_done/swept_code/best_code/min_eye_width (driven by attachment's unit_D2C_sweep)
//
// Tests covered:
//   1. Normal path  : VALVREF → DATAVREF → SPEEDIDLE → TXSELFCAL → RXCLKCAL →
//                     VALTRAINCENTER → VALTRAINVREF → DTC1 → DATATRAINVREF →
//                     RXDESKEW → DTC2 → LINKSPEED → LINKINIT
//   2. Re-entry at SPEEDIDLE  (From L1 / From PHYRETRAIN → SPEEDIDLE)
//   3. Re-entry at TXSELFCAL  (From PHYRETRAIN → TXSELFCAL)
//   4. Re-entry at REPAIR     (From PHYRETRAIN → REPAIR)
// ====================================================================================================

module wrapper_MBTRAIN_tb;

    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;

    // =========================================================================
    // Simulation Parameters
    // =========================================================================
    localparam real    CLK_PERIOD           = 1.0;       // ns  (1 GHz lclk)
    localparam integer TIMEOUT_CYCLES       = 'D500_000; // per-test timeout
    localparam integer ANALOG_SETTLE_CYCLES = 'D10;
    localparam integer SB_DELAY             = 2;         // cross-die pipeline depth
    localparam integer MB_DELAY             = 2;

    // Keep sweep ranges small so simulation finishes quickly.
    localparam int unsigned MAX_VAL_VREF_CODE  = 'd16;
    localparam int unsigned MIN_VAL_VREF_CODE  = 'd10;
    localparam int unsigned MAX_DATA_VREF_CODE = 'd16;
    localparam int unsigned MIN_DATA_VREF_CODE = 'd10;
    localparam int unsigned MAX_DATA_PI_CODE   = 'd16;
    localparam int unsigned MIN_DATA_PI_CODE   = 'd0;
    localparam int unsigned MAX_VAL_PI_CODE    = 'd16;
    localparam int unsigned MIN_VAL_PI_CODE    = 'd0;
    localparam int unsigned MAX_DESKEW_CODE    = 'd16;
    localparam int unsigned MIN_DESKEW_CODE    = 'd0;

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    logic lclk  = 1'b0;
    logic rst_n = 1'b0;

    always #(CLK_PERIOD / 2.0) lclk = ~lclk;

    // =========================================================================
    // Interfaces — one per die.
    // The ltsm_tb_attachments inside each interface drives:
    //   * intf.sweep_done, intf.swept_code / best_code / min_eye_width
    //     (via unit_D2C_sweep instance)
    //   * intf.d2c_perlane_pass, intf.d2c_aggr_pass, intf.d2c_val_pass
    //     (via wrapper_D2C_PT_top instance)
    //   * intf.analog_settle_time_done (via analog-settle counter)
    //   * intf.timeout_8ms_occured     (via 8 ms counter — no longer consumed by wrapper)
    // =========================================================================
    ltsm_tb_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE)
    ) intf_die0 (.lclk(lclk), .rst_n(rst_n));

    ltsm_tb_if #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE)
    ) intf_die1 (.lclk(lclk), .rst_n(rst_n));

    // =========================================================================
    // Interface Unconnected/Default Assignments to avoid X-state propagation
    // =========================================================================
    assign intf_die0.tx_sb_msg_valid = 1'b0;
    assign intf_die0.tx_sb_msg       = 8'h00;
    assign intf_die0.tx_msginfo      = 16'h0000;
    assign intf_die0.tx_data_field   = 64'h0000_0000_0000_0000;

    assign intf_die0.cfg_max_err_thresh_perlane = 12'd0;
    assign intf_die0.cfg_max_err_thresh_aggr    = 16'd0;

    assign intf_die1.tx_sb_msg_valid = 1'b0;
    assign intf_die1.tx_sb_msg       = 8'h00;
    assign intf_die1.tx_msginfo      = 16'h0000;
    assign intf_die1.tx_data_field   = 64'h0000_0000_0000_0000;

    assign intf_die1.cfg_max_err_thresh_perlane = 12'd0;
    assign intf_die1.cfg_max_err_thresh_aggr    = 16'd0;

    // =========================================================================
    // TB Attachments (ENABLE_LOOPBACK=0 — we do explicit cross-die SB below)
    // =========================================================================
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY),
        .MB_DELAY            (MB_DELAY),
        .MIN_VAL_VREF_CODE   (MIN_VAL_VREF_CODE),
        .MAX_VAL_VREF_CODE   (MAX_VAL_VREF_CODE),
        .MIN_DATA_VREF_CODE  (MIN_DATA_VREF_CODE),
        .MAX_DATA_VREF_CODE  (MAX_DATA_VREF_CODE),
        .MIN_VAL_PI_CODE     (MIN_VAL_PI_CODE),
        .MAX_VAL_PI_CODE     (MAX_VAL_PI_CODE),
        .MIN_DATA_PI_CODE    (MIN_DATA_PI_CODE),
        .MAX_DATA_PI_CODE    (MAX_DATA_PI_CODE),
        .MIN_DESKEW_CODE     (MIN_DESKEW_CODE),
        .MAX_DESKEW_CODE     (MAX_DESKEW_CODE),
        .ENABLE_LOOPBACK     (1'b0)
    ) attach_die0 (.intf(intf_die0));

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY),
        .MB_DELAY            (MB_DELAY),
        .MIN_VAL_VREF_CODE   (MIN_VAL_VREF_CODE),
        .MAX_VAL_VREF_CODE   (MAX_VAL_VREF_CODE),
        .MIN_DATA_VREF_CODE  (MIN_DATA_VREF_CODE),
        .MAX_DATA_VREF_CODE  (MAX_DATA_VREF_CODE),
        .MIN_VAL_PI_CODE     (MIN_VAL_PI_CODE),
        .MAX_VAL_PI_CODE     (MAX_VAL_PI_CODE),
        .MIN_DATA_PI_CODE    (MIN_DATA_PI_CODE),
        .MAX_DATA_PI_CODE    (MAX_DATA_PI_CODE),
        .MIN_DESKEW_CODE     (MIN_DESKEW_CODE),
        .MAX_DESKEW_CODE     (MAX_DESKEW_CODE),
        .ENABLE_LOOPBACK     (1'b0)
    ) attach_die1 (.intf(intf_die1));

    // =========================================================================
    // Cross-Die Sideband Pipeline
    //   Die 0 TX → (SB_DELAY cycles) → Die 1 RX
    //   Die 1 TX → (SB_DELAY cycles) → Die 0 RX
    //
    // The SB TX source is:
    //   dut_dieX.substate_tx_sb_msg_valid (DUT output port, routed via intf.wrapper_tx_sb_msg_valid)
    //   OR intf_dieX.tb_muxed_tx_sb_msg_valid (from the wrapper_D2C_PT_top inside ltsm_tb_attachments)
    //
    // We form a combined signal — DUT SB takes priority if both fire (should not happen).
    // =========================================================================
    logic [SB_DELAY-1:0] d0_to_d1_val_sr;
    logic [7:0]          d0_to_d1_msg_sr  [0:SB_DELAY-1];
    logic [15:0]         d0_to_d1_info_sr [0:SB_DELAY-1];
    logic [63:0]         d0_to_d1_data_sr [0:SB_DELAY-1];

    logic [SB_DELAY-1:0] d1_to_d0_val_sr;
    logic [7:0]          d1_to_d0_msg_sr  [0:SB_DELAY-1];
    logic [15:0]         d1_to_d0_info_sr [0:SB_DELAY-1];
    logic [63:0]         d1_to_d0_data_sr [0:SB_DELAY-1];

    // Combined TX: DUT substate output takes priority over D2C_PT attachment output
    logic       d0_tx_valid; logic [7:0] d0_tx_msg; logic [15:0] d0_tx_info; logic [63:0] d0_tx_data;
    logic       d1_tx_valid; logic [7:0] d1_tx_msg; logic [15:0] d1_tx_info; logic [63:0] d1_tx_data;

    assign d0_tx_valid = dut_die0.substate_tx_sb_msg_valid | intf_die0.tb_muxed_tx_sb_msg_valid;
    assign d0_tx_msg   = dut_die0.substate_tx_sb_msg_valid ? dut_die0.substate_tx_sb_msg     : intf_die0.tb_muxed_tx_sb_msg;
    assign d0_tx_info  = dut_die0.substate_tx_sb_msg_valid ? dut_die0.substate_tx_msginfo    : intf_die0.tb_muxed_tx_msginfo;
    assign d0_tx_data  = dut_die0.substate_tx_sb_msg_valid ? dut_die0.substate_tx_data_field : intf_die0.tb_muxed_tx_data_field;

    assign d1_tx_valid = dut_die1.substate_tx_sb_msg_valid | intf_die1.tb_muxed_tx_sb_msg_valid;
    assign d1_tx_msg   = dut_die1.substate_tx_sb_msg_valid ? dut_die1.substate_tx_sb_msg     : intf_die1.tb_muxed_tx_sb_msg;
    assign d1_tx_info  = dut_die1.substate_tx_sb_msg_valid ? dut_die1.substate_tx_msginfo    : intf_die1.tb_muxed_tx_msginfo;
    assign d1_tx_data  = dut_die1.substate_tx_sb_msg_valid ? dut_die1.substate_tx_data_field : intf_die1.tb_muxed_tx_data_field;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            d0_to_d1_val_sr <= '0;
            d1_to_d0_val_sr <= '0;
            for (int i = 0; i < SB_DELAY; i++) begin
                d0_to_d1_msg_sr[i] <= '0; d0_to_d1_info_sr[i] <= '0; d0_to_d1_data_sr[i] <= '0;
                d1_to_d0_msg_sr[i] <= '0; d1_to_d0_info_sr[i] <= '0; d1_to_d0_data_sr[i] <= '0;
            end
            intf_die1.rx_sb_msg_valid <= 1'b0; intf_die1.rx_sb_msg <= '0;
            intf_die1.rx_msginfo      <= '0;   intf_die1.rx_data_field <= '0;
            intf_die0.rx_sb_msg_valid <= 1'b0; intf_die0.rx_sb_msg <= '0;
            intf_die0.rx_msginfo      <= '0;   intf_die0.rx_data_field <= '0;
        end else begin
            // ── Debug prints ────────────────────────────────────────────────
            if (d0_tx_valid) $display("Time %0t | D0 TX -> Msg:%0h Info:%0h Data:%0h", $time, d0_tx_msg, d0_tx_info, d0_tx_data);
            if (d1_tx_valid) $display("Time %0t | D1 TX -> Msg:%0h Info:%0h Data:%0h", $time, d1_tx_msg, d1_tx_info, d1_tx_data);

            // ── Die 0 → Die 1 ───────────────────────────────────────────────
            d0_to_d1_val_sr    <= {d0_to_d1_val_sr[SB_DELAY-2:0], d0_tx_valid};
            d0_to_d1_msg_sr[0] <= d0_tx_msg; d0_to_d1_info_sr[0] <= d0_tx_info; d0_to_d1_data_sr[0] <= d0_tx_data;
            for (int i = 1; i < SB_DELAY; i++) begin
                d0_to_d1_msg_sr[i]  <= d0_to_d1_msg_sr[i-1];
                d0_to_d1_info_sr[i] <= d0_to_d1_info_sr[i-1];
                d0_to_d1_data_sr[i] <= d0_to_d1_data_sr[i-1];
            end
            intf_die1.rx_sb_msg_valid <= d0_to_d1_val_sr[SB_DELAY-1];
            intf_die1.rx_sb_msg       <= d0_to_d1_msg_sr[SB_DELAY-1];
            intf_die1.rx_msginfo      <= d0_to_d1_info_sr[SB_DELAY-1];
            intf_die1.rx_data_field   <= d0_to_d1_data_sr[SB_DELAY-1];
            if (d0_to_d1_val_sr[SB_DELAY-1])
                $display("Time %0t | D1 RX <- Msg:%0h Info:%0h Data:%0h", $time,
                    d0_to_d1_msg_sr[SB_DELAY-1], d0_to_d1_info_sr[SB_DELAY-1], d0_to_d1_data_sr[SB_DELAY-1]);

            // ── Die 1 → Die 0 ───────────────────────────────────────────────
            d1_to_d0_val_sr    <= {d1_to_d0_val_sr[SB_DELAY-2:0], d1_tx_valid};
            d1_to_d0_msg_sr[0] <= d1_tx_msg; d1_to_d0_info_sr[0] <= d1_tx_info; d1_to_d0_data_sr[0] <= d1_tx_data;
            for (int i = 1; i < SB_DELAY; i++) begin
                d1_to_d0_msg_sr[i]  <= d1_to_d0_msg_sr[i-1];
                d1_to_d0_info_sr[i] <= d1_to_d0_info_sr[i-1];
                d1_to_d0_data_sr[i] <= d1_to_d0_data_sr[i-1];
            end
            intf_die0.rx_sb_msg_valid <= d1_to_d0_val_sr[SB_DELAY-1];
            intf_die0.rx_sb_msg       <= d1_to_d0_msg_sr[SB_DELAY-1];
            intf_die0.rx_msginfo      <= d1_to_d0_info_sr[SB_DELAY-1];
            intf_die0.rx_data_field   <= d1_to_d0_data_sr[SB_DELAY-1];
            if (d1_to_d0_val_sr[SB_DELAY-1])
                $display("Time %0t | D0 RX <- Msg:%0h Info:%0h Data:%0h", $time,
                    d1_to_d0_msg_sr[SB_DELAY-1], d1_to_d0_info_sr[SB_DELAY-1], d1_to_d0_data_sr[SB_DELAY-1]);
        end
    end

    // =========================================================================
    // LTSM State-N Control Signals
    // wrapper_MBTRAIN now takes state_n_0 and state_n_1 as separate scalar ports
    // (replacing the old state_n[3:0] array). The ltsm_tb_if still has state_n_0
    // through state_n_3 fields for compatibility with the attachment's unit_D2C_sweep.
    // =========================================================================
    // We drive intf.state_n_0 (used by attachment's unit_D2C_sweep .state_n port)
    // and pass the same value directly to the DUT's state_n_0 / state_n_1 ports.

    // =========================================================================
    // MBTRAIN Control Signals
    // =========================================================================
    logic mbtrain_en_d0   = 1'b0, mbtrain_en_d1   = 1'b0;
    logic mbtrain_done_d0,        mbtrain_done_d1;
    state_n_e current_mbtrain_substate_d0, current_mbtrain_substate_d1;

    // LTSM exit routing outputs
    logic ltsm_trainerror_req_d0, ltsm_linkinit_req_d0, ltsm_phyretrain_req_d0;
    logic ltsm_trainerror_req_d1, ltsm_linkinit_req_d1, ltsm_phyretrain_req_d1;

    // Re-entry request inputs (driven by TB for path tests)
    logic mbtrain_txselfcal_req_d0 = 1'b0, mbtrain_speedidle_req_d0 = 1'b0, mbtrain_repair_req_d0 = 1'b0;
    logic mbtrain_txselfcal_req_d1 = 1'b0, mbtrain_speedidle_req_d1 = 1'b0, mbtrain_repair_req_d1 = 1'b0;

    // =========================================================================
    // Configuration Signals (shared between dies)
    // =========================================================================
    logic [2:0] param_negotiated_max_speed = 3'b010; // 12 GT/s, standard speed (≤ 32 GT/s)
    logic       is_continuous_clk_mode     = 1'b0;
    logic       rf_cap_SPMW               = 1'b0;
    logic [3:0] rf_ctrl_target_link_width  = 4'h2;
    logic       param_UCIe_S_x8           = 1'b0;
    logic       PHY_IN_RETRAIN_d0         = 1'b0, PHY_IN_RETRAIN_d1 = 1'b0;
    logic       params_changed_d0         = 1'b0, params_changed_d1 = 1'b0;
    logic [2:0] mbinit_rx_data_lane_mask  = 3'b011;
    logic [2:0] mbinit_tx_data_lane_mask  = 3'b011;

    // DUT retrain/busy clear outputs (ignored in this TB)
    logic PHY_IN_RETRAIN_rst_d0, PHY_IN_RETRAIN_rst_d1;
    logic busy_bit_rst_d0,       busy_bit_rst_d1;

    // =========================================================================
    // DUT Die 0
    // Notes on sweep/D2C connections:
    //   - local_sweep_en → intf_die0.sweep_en  (attachment's unit_D2C_sweep reads it)
    //   - sweep_done     ← intf_die0.sweep_done (driven by attachment's unit_D2C_sweep)
    //   - sweep_swept_code ← intf_die0.swept_code  (from unit_D2C_sweep)
    //   - sweep_best_code  ← intf_die0.best_code   (from unit_D2C_sweep)
    //   - sweep_min_eye_width ← intf_die0.min_eye_width (from unit_D2C_sweep)
    //   - d2c_perlane_pass ← intf_die0.d2c_perlane_pass (from wrapper_D2C_PT_top)
    // =========================================================================
    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE  (MIN_DATA_PI_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE   (MIN_DESKEW_CODE)
    ) dut_die0 (
        // ── Clock / Reset ─────────────────────────────────────────────────
        .lclk                       (lclk),
        .rst_n                      (rst_n),

        // ── MBTRAIN State Control ──────────────────────────────────────────
        .mbtrain_en                 (mbtrain_en_d0),
        .mbtrain_done               (mbtrain_done_d0),
        .current_mbtrain_substate   (current_mbtrain_substate_d0),

        // ── LTSM Exit Routing ─────────────────────────────────────────────
        .ltsm_trainerror_req        (ltsm_trainerror_req_d0),
        .ltsm_linkinit_req          (ltsm_linkinit_req_d0),
        .ltsm_phyretrain_req        (ltsm_phyretrain_req_d0),

        // ── External Re-Entry Requests (PHYRETRAIN / L1 paths) ───────────
        .mbtrain_txselfcal_req      (mbtrain_txselfcal_req_d0),
        .mbtrain_speedidle_req      (mbtrain_speedidle_req_d0),
        .mbtrain_repair_req         (mbtrain_repair_req_d0),

        // ── Analog Settle Timer ───────────────────────────────────────────
        // analog_settle_time_done is driven by attach_die0's internal counter.
        // analog_settle_timer_en  is an output from the DUT, read by attach_die0.
        .analog_settle_time_done    (intf_die0.analog_settle_time_done),
        .analog_settle_timer_en     (intf_die0.analog_settle_timer_en),

        // ── LTSM State-N → Internal soft_rst_n Generator ─────────────────
        // state_n_0 is used to generate soft_rst_n inside wrapper_MBTRAIN.
        // state_n_1 is a secondary state signal (e.g. for monitoring / RF).
        // We drive both from the interface's state_n_0 and state_n_1 fields,
        // which are also read by the attachment's unit_D2C_sweep.
        .state_n_0                  (intf_die0.state_n_0),
        .state_n_1                  (intf_die0.state_n_1),

        // ── Register-File / Configuration ─────────────────────────────────
        .param_negotiated_max_speed (param_negotiated_max_speed),
        .is_continuous_clk_mode     (is_continuous_clk_mode),
        .rf_cap_SPMW                (rf_cap_SPMW),
        .rf_ctrl_target_link_width  (rf_ctrl_target_link_width),
        .param_UCIe_S_x8            (param_UCIe_S_x8),

        // ── PHY Retrain ───────────────────────────────────────────────────
        .PHY_IN_RETRAIN             (PHY_IN_RETRAIN_d0),
        .params_changed             (params_changed_d0),
        .PHY_IN_RETRAIN_rst         (PHY_IN_RETRAIN_rst_d0),
        .busy_bit_rst               (busy_bit_rst_d0),

        // ── Lane Masks ───────────────────────────────────────────────────
        .mbinit_rx_data_lane_mask   (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask   (mbinit_tx_data_lane_mask),
        .mb_rx_data_lane_mask       (intf_die0.mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask       (intf_die0.mb_tx_data_lane_mask),

        // ── External D2C Sweep Engine (driven by attach_die0.u_D2C_sweep) ─
        .local_sweep_en             (intf_die0.sweep_en),
        .partner_sweep_en           (intf_die0.partner_sweep_en),
        .sweep_active_lanes         (),         // informational only
        .sweep_done                 (intf_die0.sweep_done),
        .sweep_swept_code           (intf_die0.swept_code),
        .sweep_best_code            (intf_die0.best_code),
        .sweep_min_eye_width        (intf_die0.min_eye_width),

        // ── D2C Point-Test Results (driven by attach_die0.wrapper_D2C_PT_top) ──
        // d2c_aggr_pass and d2c_val_pass are no longer wrapper ports.
        // Only d2c_perlane_pass is consumed.
        .d2c_perlane_pass           (intf_die0.d2c_perlane_pass),

        // ── PHY Controls (outputs) ────────────────────────────────────────
        .phy_negotiated_speed       (intf_die0.phy_negotiated_speed),
        .phy_tx_selfcal_en          (),
        .phy_rx_clock_lock_en       (intf_die0.phy_rx_clock_lock_en),
        .phy_rx_track_lock_en       (intf_die0.phy_rx_track_lock_en),
        .phy_rx_phase_detector_en   (intf_die0.phy_rx_phase_detector_en),

        // ── PHY Clock-Shift (RXCLKCAL partner inputs) ─────────────────────
        .phy_rx_tckn_shift          (5'd0),
        .phy_rx_decrement_shift     (1'b0),
        .phy_tx_tckn_shift_en       (intf_die0.phy_tx_tckn_shift_en),
        .phy_tx_tckn_shift          (intf_die0.phy_tx_tckn_shift),
        .phy_tx_decrement_shift     (intf_die0.phy_tx_decrement_shift),
        .phy_tx_tckn_shift_out_of_range (1'b0),

        // ── Per-Lane PHY Vref / PI Controls ───────────────────────────────
        .phy_rx_val_vref_ctrl        (intf_die0.phy_rx_valvref_ctrl),
        .phy_rx_data_vref_ctrl       (intf_die0.phy_rx_datavref_ctrl),
        .phy_tx_val_pi_phase_ctrl   (intf_die0.phy_tx_val_pi_phase_ctrl),
        .phy_tx_data_pi_phase_ctrl  (intf_die0.phy_tx_data_pi_phase_ctrl),
        .phy_rx_deskew_ctrl         (),
        .phy_tx_eq_preset_ctrl      (),
        .phy_tx_eq_preset_en        (),

        // ── Mainband Lane Selectors ────────────────────────────────────────
        .substate_mb_tx_clk_lane_sel  (intf_die0.mb_tx_clk_lane_sel),
        .substate_mb_tx_data_lane_sel (intf_die0.mb_tx_data_lane_sel),
        .substate_mb_tx_val_lane_sel  (intf_die0.mb_tx_val_lane_sel),
        .substate_mb_tx_trk_lane_sel  (intf_die0.mb_tx_trk_lane_sel),
        .substate_mb_rx_clk_lane_sel  (intf_die0.mb_rx_clk_lane_sel),
        .substate_mb_rx_data_lane_sel (intf_die0.mb_rx_data_lane_sel),
        .substate_mb_rx_val_lane_sel  (intf_die0.mb_rx_val_lane_sel),
        .substate_mb_rx_trk_lane_sel  (intf_die0.mb_rx_trk_lane_sel),

        // ── RXCLKCAL Pattern Controls ──────────────────────────────────────
        .rxclkcal_mb_tx_pattern_en      (intf_die0.mb_tx_pattern_en),
        .rxclkcal_mb_tx_pattern_setup   (intf_die0.mb_tx_pattern_setup),
        .rxclkcal_mb_tx_clk_pattern_sel (intf_die0.mb_tx_clk_pattern_sel),

        // ── Sideband TX ───────────────────────────────────────────────────
        .substate_tx_sb_msg_valid   (intf_die0.wrapper_tx_sb_msg_valid),
        .substate_tx_sb_msg         (intf_die0.wrapper_tx_sb_msg),
        .substate_tx_msginfo        (intf_die0.wrapper_tx_msginfo),
        .substate_tx_data_field     (intf_die0.wrapper_tx_data_field),

        // ── Sideband RX (driven by cross-die shift register above) ────────
        .rx_sb_msg_valid            (intf_die0.rx_sb_msg_valid),
        .rx_sb_msg                  (intf_die0.rx_sb_msg),
        .rx_msginfo                 (intf_die0.rx_msginfo)
        // .rx_data_field              (intf_die0.rx_data_field)
    );

    // =========================================================================
    // DUT Die 1  (identical connection pattern, using intf_die1)
    // =========================================================================
    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),
        .MIN_DATA_PI_CODE  (MIN_DATA_PI_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE),
        .MIN_DESKEW_CODE   (MIN_DESKEW_CODE)
    ) dut_die1 (
        .lclk                       (lclk),
        .rst_n                      (rst_n),
        .mbtrain_en                 (mbtrain_en_d1),
        .mbtrain_done               (mbtrain_done_d1),
        .current_mbtrain_substate   (current_mbtrain_substate_d1),
        .ltsm_trainerror_req        (ltsm_trainerror_req_d1),
        .ltsm_linkinit_req          (ltsm_linkinit_req_d1),
        .ltsm_phyretrain_req        (ltsm_phyretrain_req_d1),
        .mbtrain_txselfcal_req      (mbtrain_txselfcal_req_d1),
        .mbtrain_speedidle_req      (mbtrain_speedidle_req_d1),
        .mbtrain_repair_req         (mbtrain_repair_req_d1),
        .analog_settle_time_done    (intf_die1.analog_settle_time_done),
        .analog_settle_timer_en     (intf_die1.analog_settle_timer_en),
        .state_n_0                  (intf_die1.state_n_0),
        .state_n_1                  (intf_die1.state_n_1),
        .param_negotiated_max_speed (param_negotiated_max_speed),
        .is_continuous_clk_mode     (is_continuous_clk_mode),
        .rf_cap_SPMW                (rf_cap_SPMW),
        .rf_ctrl_target_link_width  (rf_ctrl_target_link_width),
        .param_UCIe_S_x8            (param_UCIe_S_x8),
        .PHY_IN_RETRAIN             (PHY_IN_RETRAIN_d1),
        .params_changed             (params_changed_d1),
        .PHY_IN_RETRAIN_rst         (PHY_IN_RETRAIN_rst_d1),
        .busy_bit_rst               (busy_bit_rst_d1),
        .mbinit_rx_data_lane_mask   (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask   (mbinit_tx_data_lane_mask),
        .mb_rx_data_lane_mask       (intf_die1.mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask       (intf_die1.mb_tx_data_lane_mask),
        .local_sweep_en             (intf_die1.sweep_en),
        .partner_sweep_en           (intf_die1.partner_sweep_en),
        .sweep_active_lanes         (),
        .sweep_done                 (intf_die1.sweep_done),
        .sweep_swept_code           (intf_die1.swept_code),
        .sweep_best_code            (intf_die1.best_code),
        .sweep_min_eye_width        (intf_die1.min_eye_width),
        .d2c_perlane_pass           (intf_die1.d2c_perlane_pass),
        .phy_negotiated_speed       (intf_die1.phy_negotiated_speed),
        .phy_tx_selfcal_en          (),
        .phy_rx_clock_lock_en       (intf_die1.phy_rx_clock_lock_en),
        .phy_rx_track_lock_en       (intf_die1.phy_rx_track_lock_en),
        .phy_rx_phase_detector_en   (intf_die1.phy_rx_phase_detector_en),
        .phy_rx_tckn_shift          (5'd0),
        .phy_rx_decrement_shift     (1'b0),
        .phy_tx_tckn_shift_en       (intf_die1.phy_tx_tckn_shift_en),
        .phy_tx_tckn_shift          (intf_die1.phy_tx_tckn_shift),
        .phy_tx_decrement_shift     (intf_die1.phy_tx_decrement_shift),
        .phy_tx_tckn_shift_out_of_range (1'b0),
        .phy_rx_val_vref_ctrl        (intf_die1.phy_rx_valvref_ctrl),
        .phy_rx_data_vref_ctrl       (intf_die1.phy_rx_datavref_ctrl),
        .phy_tx_val_pi_phase_ctrl   (intf_die1.phy_tx_val_pi_phase_ctrl),
        .phy_tx_data_pi_phase_ctrl  (intf_die1.phy_tx_data_pi_phase_ctrl),
        .phy_rx_deskew_ctrl         (),
        .phy_tx_eq_preset_ctrl      (),
        .phy_tx_eq_preset_en        (),
        .substate_mb_tx_clk_lane_sel  (intf_die1.mb_tx_clk_lane_sel),
        .substate_mb_tx_data_lane_sel (intf_die1.mb_tx_data_lane_sel),
        .substate_mb_tx_val_lane_sel  (intf_die1.mb_tx_val_lane_sel),
        .substate_mb_tx_trk_lane_sel  (intf_die1.mb_tx_trk_lane_sel),
        .substate_mb_rx_clk_lane_sel  (intf_die1.mb_rx_clk_lane_sel),
        .substate_mb_rx_data_lane_sel (intf_die1.mb_rx_data_lane_sel),
        .substate_mb_rx_val_lane_sel  (intf_die1.mb_rx_val_lane_sel),
        .substate_mb_rx_trk_lane_sel  (intf_die1.mb_rx_trk_lane_sel),
        .rxclkcal_mb_tx_pattern_en      (intf_die1.mb_tx_pattern_en),
        .rxclkcal_mb_tx_pattern_setup   (intf_die1.mb_tx_pattern_setup),
        .rxclkcal_mb_tx_clk_pattern_sel (intf_die1.mb_tx_clk_pattern_sel),
        .substate_tx_sb_msg_valid   (intf_die1.wrapper_tx_sb_msg_valid),
        .substate_tx_sb_msg         (intf_die1.wrapper_tx_sb_msg),
        .substate_tx_msginfo        (intf_die1.wrapper_tx_msginfo),
        .substate_tx_data_field     (intf_die1.wrapper_tx_data_field),
        .rx_sb_msg_valid            (intf_die1.rx_sb_msg_valid),
        .rx_sb_msg                  (intf_die1.rx_sb_msg),
        .rx_msginfo                 (intf_die1.rx_msginfo)
        // .rx_data_field              (intf_die1.rx_data_field)
    );

    // =========================================================================
    // Assertions: 1-cycle tx_sb_msg_valid spacing rule
    // =========================================================================
    property p_die0_msg_spacing;
        @(posedge lclk) disable iff (!rst_n)
            d0_tx_valid |=> !d0_tx_valid;
    endproperty
    assert property (p_die0_msg_spacing)
    else $error("Time %0t | Die 0: tx_sb_msg_valid violated 1-cycle spacing rule", $time);

    property p_die1_msg_spacing;
        @(posedge lclk) disable iff (!rst_n)
            d1_tx_valid |=> !d1_tx_valid;
    endproperty
    assert property (p_die1_msg_spacing)
    else $error("Time %0t | Die 1: tx_sb_msg_valid violated 1-cycle spacing rule", $time);

    // =========================================================================
    // Debug Monitors (run as background threads)
    // =========================================================================

    // Monitor 1: Substate transitions
    initial begin : mon_substate
        state_n_e last_d0;
        state_n_e last_d1;
        last_d0 = LOG_NOP;
        last_d1 = LOG_NOP;
        forever begin
            @(posedge lclk);
            if (current_mbtrain_substate_d0 !== last_d0) begin
                $display("Time %0t | D0 Substate -> %s", $time, current_mbtrain_substate_d0.name());
                last_d0 = current_mbtrain_substate_d0;
            end
            if (current_mbtrain_substate_d1 !== last_d1) begin
                $display("Time %0t | D1 Substate -> %s", $time, current_mbtrain_substate_d1.name());
                last_d1 = current_mbtrain_substate_d1;
            end
        end
    end

    // Monitor 2: Trainerror events (uses unified ss_trainerror_req[] array in new RTL)
    initial begin : mon_trainerror
        forever begin
            @(posedge lclk);
            if (dut_die0.trainerror_detected) begin
                $display("Time %0t | D0 trainerror_detected!", $time);
                for (int i = 0; i < 13; i++)
                    if (dut_die0.ss_trainerror_req[i])
                        $display("  D0 ss_trainerror_req[%0d] asserted", i);
            end
            if (dut_die1.trainerror_detected) begin
                $display("Time %0t | D1 trainerror_detected!", $time);
                for (int i = 0; i < 13; i++)
                    if (dut_die1.ss_trainerror_req[i])
                        $display("  D1 ss_trainerror_req[%0d] asserted", i);
            end
        end
    end

    // Monitor 3: soft_rst_n / first_enter_flag transitions
    initial begin : mon_soft_rst
        logic last_d0;
        logic last_d1;
        last_d0 = 0;
        last_d1 = 0;
        forever begin
            @(posedge lclk);
            if (dut_die0.soft_rst_n !== last_d0) begin
                $display("Time %0t | D0 soft_rst_n = %b  (first_enter_flag=%b, state_n_0=%s)",
                    $time, dut_die0.soft_rst_n, dut_die0.first_enter_flag, intf_die0.state_n_0.name());
                last_d0 = dut_die0.soft_rst_n;
            end
            if (dut_die1.soft_rst_n !== last_d1) begin
                $display("Time %0t | D1 soft_rst_n = %b", $time, dut_die1.soft_rst_n);
                last_d1 = dut_die1.soft_rst_n;
            end
        end
    end

    // Monitor 4: sweep_en transitions
    initial begin : mon_sweep
        logic last_d0;
        logic last_d1;
        last_d0 = 0;
        last_d1 = 0;
        forever begin
            @(posedge lclk);
            if (intf_die0.sweep_en !== last_d0) begin
                $display("Time %0t | D0 local_sweep_en = %b", $time, intf_die0.sweep_en);
                last_d0 = intf_die0.sweep_en;
            end
            if (intf_die1.sweep_en !== last_d1) begin
                $display("Time %0t | D1 local_sweep_en = %b", $time, intf_die1.sweep_en);
                last_d1 = intf_die1.sweep_en;
            end
        end
    end

    // =========================================================================
    // Task: Common Reset + LTSM State-N Initialization
    //   Sequence:
    //     1. rst_n = 0   (hard reset, all FFs → reset state)
    //     2. rst_n = 1
    //     3. state_n = LOG_RESET   → SOFT_RESET_GEN sees RESET first time, sets soft_rst_n = 0
    //     4. state_n = LOG_SBINIT  → SOFT_RESET_GEN releases soft_rst_n = 1
    //     5. state_n = LOG_MBTRAIN_VALVREF (typical context)
    // =========================================================================
    task automatic do_reset_and_init();
        // Drive state_n via intf fields (also consumed by attachment's unit_D2C_sweep)
        intf_die0.state_n_0 = LOG_RESET; intf_die0.state_n_1 = LOG_RESET;
        intf_die0.state_n_2 = LOG_RESET; intf_die0.state_n_3 = LOG_RESET;
        intf_die1.state_n_0 = LOG_RESET; intf_die1.state_n_1 = LOG_RESET;
        intf_die1.state_n_2 = LOG_RESET; intf_die1.state_n_3 = LOG_RESET;

        rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 5);

        // Pulse through RESET state so SOFT_RESET_GEN captures the edge
        intf_die0.state_n_0 = LOG_RESET; intf_die0.state_n_1 = LOG_RESET;
        intf_die1.state_n_0 = LOG_RESET; intf_die1.state_n_1 = LOG_RESET;
        #(CLK_PERIOD * 5);

        // Transition to SBINIT → releases soft_rst_n
        intf_die0.state_n_0 = LOG_SBINIT; intf_die0.state_n_1 = LOG_SBINIT;
        intf_die1.state_n_0 = LOG_SBINIT; intf_die1.state_n_1 = LOG_SBINIT;
        #(CLK_PERIOD * 5);

        // Drive MBTRAIN context state for RF / monitoring
        intf_die0.state_n_0 = LOG_MBTRAIN_VALVREF; intf_die0.state_n_1 = LOG_MBTRAIN_VALVREF;
        intf_die0.state_n_2 = LOG_MBTRAIN_VALVREF; intf_die0.state_n_3 = LOG_MBTRAIN_VALVREF;
        intf_die1.state_n_0 = LOG_MBTRAIN_VALVREF; intf_die1.state_n_1 = LOG_MBTRAIN_VALVREF;
        intf_die1.state_n_2 = LOG_MBTRAIN_VALVREF; intf_die1.state_n_3 = LOG_MBTRAIN_VALVREF;
        #(CLK_PERIOD * 5);
    endtask

    // =========================================================================
    // Task: Set default TB override signals to "all-pass / no-error" state
    // =========================================================================
    task automatic set_allpass();
        intf_die0.tb_force_perlane_pass = 16'hFFFF;
        intf_die0.tb_force_aggr_pass    = 1'b1;
        intf_die0.tb_force_val_pass     = 1'b1;
        intf_die0.tb_wait_timeout       = 1'b0;
        intf_die0.tb_wrong_sb_msg_en    = 1'b0;
        intf_die0.tb_wrong_msginfo      = 16'h0000;
        intf_die0.tb_wrong_data_field   = 64'h0000_0000_0000_0000;
        intf_die0.tb_aggr_err           = 16'h0000;

        intf_die1.tb_force_perlane_pass = 16'hFFFF;
        intf_die1.tb_force_aggr_pass    = 1'b1;
        intf_die1.tb_force_val_pass     = 1'b1;
        intf_die1.tb_wait_timeout       = 1'b0;
        intf_die1.tb_wrong_sb_msg_en    = 1'b0;
        intf_die1.tb_wrong_msginfo      = 16'h0000;
        intf_die1.tb_wrong_data_field   = 64'h0000_0000_0000_0000;
        intf_die1.tb_aggr_err           = 16'h0000;
    endtask

    integer fail_count = 0;

    // =========================================================================
    // Task: Wait for mbtrain_done on both dies, with timeout and error checks
    // =========================================================================
    task automatic wait_for_completion(input string test_name);
        fork
            begin : wait_done
                wait (mbtrain_done_d0 && mbtrain_done_d1);
                #(CLK_PERIOD * 10);
                if (ltsm_trainerror_req_d0 || ltsm_trainerror_req_d1) begin
                    $error("%s FAILED: exited to TRAINERROR. D0=%b D1=%b",
                        test_name, ltsm_trainerror_req_d0, ltsm_trainerror_req_d1);
                    fail_count++;
                end else if (ltsm_linkinit_req_d0 && ltsm_linkinit_req_d1) begin
                    $display("%s PASSED: both dies → LINKINIT.", test_name);
                end else if (ltsm_phyretrain_req_d0 || ltsm_phyretrain_req_d1) begin
                    $display("%s PASSED (PHYRETRAIN path): D0_phy=%b D1_phy=%b",
                        test_name, ltsm_phyretrain_req_d0, ltsm_phyretrain_req_d1);
                end else begin
                    $error("%s FAILED: unexpected exit. D0_li=%b D1_li=%b D0_phy=%b D1_phy=%b",
                        test_name,
                        ltsm_linkinit_req_d0, ltsm_linkinit_req_d1,
                        ltsm_phyretrain_req_d0, ltsm_phyretrain_req_d1);
                    fail_count++;
                end
                disable wait_trainerror;
                disable wait_timeout;
            end
            begin : wait_trainerror
                wait (ltsm_trainerror_req_d0 || ltsm_trainerror_req_d1);
                $error("%s: early TRAINERROR. D0=%s D1=%s",
                    test_name,
                    current_mbtrain_substate_d0.name(),
                    current_mbtrain_substate_d1.name());
                fail_count++;
                disable wait_done;
                disable wait_timeout;
            end
            begin : wait_timeout
                #(CLK_PERIOD * TIMEOUT_CYCLES);
                $error("%s TIMEOUT. D0=%s D1=%s",
                    test_name,
                    current_mbtrain_substate_d0.name(),
                    current_mbtrain_substate_d1.name());
                fail_count++;
                disable wait_done;
                disable wait_trainerror;
            end
        join

        mbtrain_en_d0 = 1'b0;
        mbtrain_en_d1 = 1'b0;
        #(CLK_PERIOD * 10);
    endtask

    // =========================================================================
    // TEST 1: Normal Forward Path
    //   VALVREF → DATAVREF → SPEEDIDLE → TXSELFCAL → RXCLKCAL →
    //   VALTRAINCENTER → VALTRAINVREF → DTC1 → DATATRAINVREF →
    //   RXDESKEW → DTC2 → LINKSPEED → LINKINIT
    // =========================================================================
    task automatic test_normal_path();
        $display("\n==== TEST 1: Normal Path (VALVREF → LINKINIT) ====");
        set_allpass();
        do_reset_and_init();
        intf_die0.state_n_1 = LOG_MBTRAIN_DATAVREF;
        intf_die1.state_n_1 = LOG_MBTRAIN_DATAVREF;
        mbtrain_en_d0 = 1'b1;
        mbtrain_en_d1 = 1'b1;
        wait_for_completion("TEST 1");
    endtask

    // =========================================================================
    // TEST 2: Re-entry at SPEEDIDLE
    //   From L1 → SPEED_IDLE  or  From PHYRETRAIN → SPEED_IDLE
    // =========================================================================
    task automatic test_entry_at_speedidle();
        $display("\n==== TEST 2: Re-entry at SPEEDIDLE ====");
        set_allpass();
        do_reset_and_init();
        intf_die0.state_n_1 = LOG_L1;
        intf_die1.state_n_1 = LOG_L1;

        // Assert the re-entry request before enabling MBTRAIN
        mbtrain_speedidle_req_d0 = 1'b1;
        mbtrain_speedidle_req_d1 = 1'b1;
        mbtrain_en_d0 = 1'b1;
        mbtrain_en_d1 = 1'b1;
        @(posedge lclk); // let ctrl sample the req
        #(CLK_PERIOD * 0.2); // avoid race condition with FSM clock edge evaluation
        mbtrain_speedidle_req_d0 = 1'b0;
        mbtrain_speedidle_req_d1 = 1'b0;

        wait_for_completion("TEST 2");
    endtask

    // =========================================================================
    // TEST 3: Re-entry at TXSELFCAL
    //   From PHYRETRAIN → TXSELFCAL
    // =========================================================================
    task automatic test_entry_at_txselfcal();
        $display("\n==== TEST 3: Re-entry at TXSELFCAL ====");
        set_allpass();
        do_reset_and_init();
        intf_die0.state_n_1 = LOG_MBTRAIN_DATAVREF;
        intf_die1.state_n_1 = LOG_MBTRAIN_DATAVREF;

        mbtrain_txselfcal_req_d0 = 1'b1;
        mbtrain_txselfcal_req_d1 = 1'b1;
        mbtrain_en_d0 = 1'b1;
        mbtrain_en_d1 = 1'b1;
        @(posedge lclk);
        #(CLK_PERIOD * 0.2); // avoid race condition with FSM clock edge evaluation
        mbtrain_txselfcal_req_d0 = 1'b0;
        mbtrain_txselfcal_req_d1 = 1'b0;

        wait_for_completion("TEST 3");
    endtask

    // =========================================================================
    // TEST 4: Re-entry at REPAIR
    //   From PHYRETRAIN → REPAIR
    //   After REPAIR finishes it goes to TXSELFCAL → normal forward path.
    // =========================================================================
    task automatic test_entry_at_repair();
        $display("\n==== TEST 4: Re-entry at REPAIR ====");
        set_allpass();
        do_reset_and_init();
        intf_die0.state_n_1 = LOG_MBTRAIN_DATAVREF;
        intf_die1.state_n_1 = LOG_MBTRAIN_DATAVREF;

        mbtrain_repair_req_d0 = 1'b1;
        mbtrain_repair_req_d1 = 1'b1;
        mbtrain_en_d0 = 1'b1;
        mbtrain_en_d1 = 1'b1;
        @(posedge lclk);
        #(CLK_PERIOD * 0.2); // avoid race condition with FSM clock edge evaluation
        mbtrain_repair_req_d0 = 1'b0;
        mbtrain_repair_req_d1 = 1'b0;

        wait_for_completion("TEST 4");
    endtask

    // =========================================================================
    // Main Stimulus
    // =========================================================================
    initial begin
        $display("=== wrapper_MBTRAIN Integration Testbench START ===");

        // Bring up with safe defaults before driving reset
        set_allpass();
        intf_die0.state_n_0 = LOG_RESET; intf_die0.state_n_1 = LOG_RESET;
        intf_die0.state_n_2 = LOG_RESET; intf_die0.state_n_3 = LOG_RESET;
        intf_die1.state_n_0 = LOG_RESET; intf_die1.state_n_1 = LOG_RESET;
        intf_die1.state_n_2 = LOG_RESET; intf_die1.state_n_3 = LOG_RESET;
        mbtrain_en_d0 = 1'b0;
        mbtrain_en_d1 = 1'b0;

        // Run all tests sequentially
        test_normal_path();
        test_entry_at_speedidle();
        test_entry_at_txselfcal();
        test_entry_at_repair();

        $display("=== wrapper_MBTRAIN Integration Testbench COMPLETE ===");
        if (fail_count == 0) begin
            $display("MBTRAIN_TB_RESULT: SUCCESS");
        end else begin
            $display("MBTRAIN_TB_RESULT: FAILURE");
        end
        $finish;
    end

endmodule
