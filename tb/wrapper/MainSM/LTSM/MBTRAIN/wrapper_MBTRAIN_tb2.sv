`timescale 1ns/1ps

// ====================================================================================================
// wrapper_MBTRAIN_tb.sv
//
// Integration Testbench for wrapper_MBTRAIN — Two-Die UCIe Link Simulation.
//
// Architecture:
//   - Two wrapper_MBTRAIN instances: dut_die0 (Die A) and dut_die1 (Die B).
//   - Each die has one ltsm_tb_if + ltsm_tb_attachments. The attachments contain:
//       * unit_D2C_sweep    → drives sweep_done/swept_code/best_code/min_eye_width.
//                             Its state_n input is kept synchronised to the DUT's
//                             current_mbtrain_substate so code ranges are correct.
//       * wrapper_D2C_PT_top → drives d2c_perlane_pass / d2c_val_pass.
//       * Analog-settle counter.
//   - ENABLE_LOOPBACK = 0: cross-die SB is done with an explicit shift-register.
//     The combined TX source per die is intf_dieX.tb_muxed_tx_sb_msg_valid (already
//     OR-ed inside ltsm_tb_attachments from wrapper_D2C_PT_top + intf.tx_sb_msg_valid).
//     The DUT's substate SB output is wired to intf.wrapper_tx_sb_msg_valid, which
//     ltsm_tb_attachments then feeds into tb_muxed_tx_sb_msg_valid.
//
// Terminal output philosophy:
//   - No raw SB message hex dumps.
//   - Only: scenario banners, Die A substate transitions, TRAINERROR events,
//     PASS/FAIL result and lclk cycle count per scenario.
//
// Scenarios (all happy-path, no TRAINERROR injection):
//   S1  : Nominal full flow from MBINIT
//   S2  : RXDESKEW retry ×1 then LINKINIT
//   S3  : RXDESKEW retry ×2 then LINKINIT
//   S4  : LINKSPEED → REPAIR ×1 → TXSELFCAL → … → LINKINIT
//   S5  : LINKSPEED → REPAIR ×2 → TXSELFCAL → … → LINKINIT
//   S6  : Entry at SPEEDIDLE  (PHYRETRAIN → SPEEDIDLE → … → LINKINIT)
//   S7  : Entry at TXSELFCAL  (PHYRETRAIN → TXSELFCAL → … → LINKINIT)
//   S8  : Entry at REPAIR     (PHYRETRAIN → REPAIR → TXSELFCAL → … → LINKINIT)
//   S9  : L1 → SPEEDIDLE → … → LINKINIT
//   S10 : LINKSPEED → PHYRETRAIN exit, then re-entry at TXSELFCAL → LINKINIT
//   S11 : RXDESKEW retry ×1 + REPAIR ×1 → LINKINIT
//   S12 : Worst-case: retry+repair+PHYRETRAIN exit (Part A) + REPAIR re-entry (Part B)
// ====================================================================================================

module wrapper_MBTRAIN_tb2;

    import UCIe_pkg::*;
    import ltsm_state_n_pkg::*;

    // =========================================================================
    // Simulation Parameters
    // =========================================================================
    localparam real    CLK_PERIOD           = 1.0;         // ns  (1 GHz lclk)
    localparam integer TIMEOUT_CYCLES       = 2_000_000;   // hard timeout guard per scenario
    localparam integer ANALOG_SETTLE_CYCLES = 10;
    localparam integer SB_DELAY             = 2;           // cross-die SB pipeline depth (lclk cycles)
    localparam integer MB_DELAY             = 2;           // speed-up: replaces 4096-UI MB bursts

    // Sweep code ranges — kept small so simulation runs quickly.
    // Note: ltsm_tb_attachments uses MIN_DESKEW_CODE=0 by default, so
    //   MIN_DESIRED_SWEEP_RANGE (inside wrapper_RXDESKEW) = (16-0+1)*75/100 = 12.
    //   With tb_force_perlane_pass=16'hFFFF all lanes pass → eye_width = 16 ≥ 12 → NO arc.
    //   With tb_force_perlane_pass=16'h0000 no  lanes pass → eye_width = 0  <  12 → ARC.
    localparam int unsigned MAX_VAL_VREF_CODE  = 7'd16;
    localparam int unsigned MIN_VAL_VREF_CODE  = 7'd1;
    localparam int unsigned MAX_DATA_VREF_CODE = 7'd16;
    localparam int unsigned MIN_DATA_VREF_CODE = 7'd1;
    localparam int unsigned MAX_DATA_PI_CODE   = 6'd16;
    localparam int unsigned MIN_DATA_PI_CODE   = 6'd1;
    localparam int unsigned MAX_VAL_PI_CODE    = 6'd16;
    localparam int unsigned MIN_VAL_PI_CODE    = 6'd1;
    localparam int unsigned MAX_DESKEW_CODE    = 7'd16;
    localparam int unsigned MIN_DESKEW_CODE    = 7'd1;

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    logic lclk  = 1'b0;
    logic rst_n = 1'b0;

    always #(CLK_PERIOD / 2.0) lclk = ~lclk;

    // =========================================================================
    // Interfaces — one per die
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
    // TB Attachments (ENABLE_LOOPBACK=0 — cross-die SB handled below)
    // =========================================================================
    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY),
        .MB_DELAY            (MB_DELAY),
        .MIN_VAL_VREF_CODE   (int'(MIN_VAL_VREF_CODE)),
        .MAX_VAL_VREF_CODE   (int'(MAX_VAL_VREF_CODE)),
        .MIN_DATA_VREF_CODE  (int'(MIN_DATA_VREF_CODE)),
        .MAX_DATA_VREF_CODE  (int'(MAX_DATA_VREF_CODE)),
        .MIN_VAL_PI_CODE     (int'(MIN_VAL_PI_CODE)),
        .MAX_VAL_PI_CODE     (int'(MAX_VAL_PI_CODE)),
        .MIN_DATA_PI_CODE    (int'(MIN_DATA_PI_CODE)),
        .MAX_DATA_PI_CODE    (int'(MAX_DATA_PI_CODE)),
        .MIN_DESKEW_CODE     (0),    // attachment default: 0
        .MAX_DESKEW_CODE     (int'(MAX_DESKEW_CODE)),
        .ENABLE_LOOPBACK     (1'b0)
    ) attach_die0 (.intf(intf_die0));

    ltsm_tb_attachments #(
        .TIMEOUT_CYCLES      (TIMEOUT_CYCLES),
        .ANALOG_SETTLE_CYCLES(ANALOG_SETTLE_CYCLES),
        .SB_DELAY            (SB_DELAY),
        .MB_DELAY            (MB_DELAY),
        .MIN_VAL_VREF_CODE   (int'(MIN_VAL_VREF_CODE)),
        .MAX_VAL_VREF_CODE   (int'(MAX_VAL_VREF_CODE)),
        .MIN_DATA_VREF_CODE  (int'(MIN_DATA_VREF_CODE)),
        .MAX_DATA_VREF_CODE  (int'(MAX_DATA_VREF_CODE)),
        .MIN_VAL_PI_CODE     (int'(MIN_VAL_PI_CODE)),
        .MAX_VAL_PI_CODE     (int'(MAX_VAL_PI_CODE)),
        .MIN_DATA_PI_CODE    (int'(MIN_DATA_PI_CODE)),
        .MAX_DATA_PI_CODE    (int'(MAX_DATA_PI_CODE)),
        .MIN_DESKEW_CODE     (0),
        .MAX_DESKEW_CODE     (int'(MAX_DESKEW_CODE)),
        .ENABLE_LOOPBACK     (1'b0)
    ) attach_die1 (.intf(intf_die1));

    // =========================================================================
    // DUT Control / Status Signals
    // =========================================================================
    logic mbtrain_en_d0 = 1'b0, mbtrain_en_d1 = 1'b0;
    logic mbtrain_done_d0,       mbtrain_done_d1;

    state_n_e current_mbtrain_substate_d0;
    state_n_e current_mbtrain_substate_d1;

    logic ltsm_trainerror_req_d0, ltsm_trainerror_req_d1;
    logic ltsm_linkinit_req_d0,   ltsm_linkinit_req_d1;
    logic ltsm_phyretrain_req_d0, ltsm_phyretrain_req_d1;

    // Re-entry request inputs (driven by tasks)
    logic mbtrain_txselfcal_req_d0 = 1'b0, mbtrain_speedidle_req_d0 = 1'b0, mbtrain_repair_req_d0 = 1'b0;
    logic mbtrain_txselfcal_req_d1 = 1'b0, mbtrain_speedidle_req_d1 = 1'b0, mbtrain_repair_req_d1 = 1'b0;

    // PHY-retrain signals (used to steer LINKSPEED → PHYRETRAIN)
    logic PHY_IN_RETRAIN_d0 = 1'b0, PHY_IN_RETRAIN_d1 = 1'b0;
    logic params_changed_d0 = 1'b0, params_changed_d1 = 1'b0;
    logic PHY_IN_RETRAIN_rst_d0, PHY_IN_RETRAIN_rst_d1;
    logic busy_bit_rst_d0,       busy_bit_rst_d1;

    // =========================================================================
    // Shared Configuration Signals
    // =========================================================================
    logic [2:0] param_negotiated_max_speed = 3'b010; // 12 GT/s  (≤32 GT/s → standard speed)
    logic       is_continuous_clk_mode     = 1'b0;
    logic       rf_cap_SPMW               = 1'b0;    // X16 module (not SPMW-capped)
    logic [3:0] rf_ctrl_target_link_width  = 4'h2;   // target = x16
    logic       param_UCIe_S_x8           = 1'b0;
    logic [2:0] mbinit_rx_data_lane_mask  = 3'b011;  // all 16 lanes
    logic [2:0] mbinit_tx_data_lane_mask  = 3'b011;

    // =========================================================================
    // Cross-Die SB Shift-Register Pipeline
    //   Die 0 TX → SB_DELAY cycles → Die 1 RX
    //   Die 1 TX → SB_DELAY cycles → Die 0 RX
    //
    // Source: intf_dieX.tb_muxed_tx_sb_msg_valid — already OR-ed inside
    // ltsm_tb_attachments from wrapper_D2C_PT_top and intf.tx_sb_msg_valid
    // (which is driven by intf.wrapper_tx_sb_msg_valid, the DUT's substate output).
    // =========================================================================
    logic [SB_DELAY-1:0] d0_to_d1_val_sr,  d1_to_d0_val_sr;
    logic [7:0]          d0_to_d1_msg_sr  [0:SB_DELAY-1], d1_to_d0_msg_sr  [0:SB_DELAY-1];
    logic [15:0]         d0_to_d1_info_sr [0:SB_DELAY-1], d1_to_d0_info_sr [0:SB_DELAY-1];
    logic [63:0]         d0_to_d1_data_sr [0:SB_DELAY-1], d1_to_d0_data_sr [0:SB_DELAY-1];

    always_ff @(posedge lclk or negedge rst_n) begin : SB_PIPELINE
        if (!rst_n) begin
            d0_to_d1_val_sr <= '0;
            d1_to_d0_val_sr <= '0;
            for (int i = 0; i < SB_DELAY; i++) begin
                d0_to_d1_msg_sr[i]  <= '0; d0_to_d1_info_sr[i] <= '0; d0_to_d1_data_sr[i] <= '0;
                d1_to_d0_msg_sr[i]  <= '0; d1_to_d0_info_sr[i] <= '0; d1_to_d0_data_sr[i] <= '0;
            end
            intf_die1.rx_sb_msg_valid <= 1'b0; intf_die1.rx_sb_msg <= '0;
            intf_die1.rx_msginfo      <= '0;   intf_die1.rx_data_field <= '0;
            intf_die0.rx_sb_msg_valid <= 1'b0; intf_die0.rx_sb_msg <= '0;
            intf_die0.rx_msginfo      <= '0;   intf_die0.rx_data_field <= '0;
        end else begin
            // ── Die 0 → Die 1 ──────────────────────────────────────────
            d0_to_d1_val_sr    <= {d0_to_d1_val_sr[SB_DELAY-2:0], intf_die0.tb_muxed_tx_sb_msg_valid};
            d0_to_d1_msg_sr[0]  <= intf_die0.tb_muxed_tx_sb_msg;
            d0_to_d1_info_sr[0] <= intf_die0.tb_muxed_tx_msginfo;
            d0_to_d1_data_sr[0] <= intf_die0.tb_muxed_tx_data_field;
            for (int i = 1; i < SB_DELAY; i++) begin
                d0_to_d1_msg_sr[i]  <= d0_to_d1_msg_sr[i-1];
                d0_to_d1_info_sr[i] <= d0_to_d1_info_sr[i-1];
                d0_to_d1_data_sr[i] <= d0_to_d1_data_sr[i-1];
            end
            intf_die1.rx_sb_msg_valid <= d0_to_d1_val_sr[SB_DELAY-1];
            intf_die1.rx_sb_msg       <= d0_to_d1_msg_sr[SB_DELAY-1];
            intf_die1.rx_msginfo      <= d0_to_d1_info_sr[SB_DELAY-1];
            intf_die1.rx_data_field   <= d0_to_d1_data_sr[SB_DELAY-1];

            // ── Die 1 → Die 0 ──────────────────────────────────────────
            d1_to_d0_val_sr    <= {d1_to_d0_val_sr[SB_DELAY-2:0], intf_die1.tb_muxed_tx_sb_msg_valid};
            d1_to_d0_msg_sr[0]  <= intf_die1.tb_muxed_tx_sb_msg;
            d1_to_d0_info_sr[0] <= intf_die1.tb_muxed_tx_msginfo;
            d1_to_d0_data_sr[0] <= intf_die1.tb_muxed_tx_data_field;
            for (int i = 1; i < SB_DELAY; i++) begin
                d1_to_d0_msg_sr[i]  <= d1_to_d0_msg_sr[i-1];
                d1_to_d0_info_sr[i] <= d1_to_d0_info_sr[i-1];
                d1_to_d0_data_sr[i] <= d1_to_d0_data_sr[i-1];
            end
            intf_die0.rx_sb_msg_valid <= d1_to_d0_val_sr[SB_DELAY-1];
            intf_die0.rx_sb_msg       <= d1_to_d0_msg_sr[SB_DELAY-1];
            intf_die0.rx_msginfo      <= d1_to_d0_info_sr[SB_DELAY-1];
            intf_die0.rx_data_field   <= d1_to_d0_data_sr[SB_DELAY-1];
        end
    end

    // =========================================================================
    // DUT Die 0
    // =========================================================================
    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),  .MIN_DATA_PI_CODE  (MIN_DATA_PI_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE),   .MIN_DESKEW_CODE   (MIN_DESKEW_CODE)
    ) dut_die0 (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .mbtrain_en                     (mbtrain_en_d0),
        .mbtrain_done                   (mbtrain_done_d0),
        .current_mbtrain_substate       (current_mbtrain_substate_d0),
        .ltsm_trainerror_req            (ltsm_trainerror_req_d0),
        .ltsm_linkinit_req              (ltsm_linkinit_req_d0),
        .ltsm_phyretrain_req            (ltsm_phyretrain_req_d0),
        .mbtrain_txselfcal_req          (mbtrain_txselfcal_req_d0),
        .mbtrain_speedidle_req          (mbtrain_speedidle_req_d0),
        .mbtrain_repair_req             (mbtrain_repair_req_d0),
        .analog_settle_time_done        (intf_die0.analog_settle_time_done),
        .analog_settle_timer_en         (intf_die0.analog_settle_timer_en),
        .state_n_0                      (intf_die0.state_n_0),
        .state_n_1                      (intf_die0.state_n_1),
        .param_negotiated_max_speed     (param_negotiated_max_speed),
        .is_continuous_clk_mode         (is_continuous_clk_mode),
        .rf_cap_SPMW                    (rf_cap_SPMW),
        .rf_ctrl_target_link_width      (rf_ctrl_target_link_width),
        .param_UCIe_S_x8               (param_UCIe_S_x8),
        .PHY_IN_RETRAIN                 (PHY_IN_RETRAIN_d0),
        .params_changed                 (params_changed_d0),
        .PHY_IN_RETRAIN_rst             (PHY_IN_RETRAIN_rst_d0),
        .busy_bit_rst                   (busy_bit_rst_d0),
        .mbinit_rx_data_lane_mask       (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask       (mbinit_tx_data_lane_mask),
        .mb_rx_data_lane_mask           (intf_die0.mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask           (intf_die0.mb_tx_data_lane_mask),
        // Sweep engine — driven by attachment's unit_D2C_sweep
        .local_sweep_en                 (intf_die0.sweep_en),
        .partner_sweep_en               (intf_die0.partner_sweep_en),
        .sweep_active_lanes             (),
        .sweep_done                     (intf_die0.sweep_done),
        .sweep_swept_code               (intf_die0.swept_code),
        .sweep_best_code                (intf_die0.best_code),
        .sweep_min_eye_width            (intf_die0.min_eye_width),
        // D2C results — driven by attachment's wrapper_D2C_PT_top
        .d2c_perlane_pass               (intf_die0.d2c_perlane_pass),
        // PHY outputs
        .phy_negotiated_speed           (intf_die0.phy_negotiated_speed),
        .phy_tx_selfcal_en              (),
        .phy_rx_clock_lock_en           (intf_die0.phy_rx_clock_lock_en),
        .phy_rx_track_lock_en           (intf_die0.phy_rx_track_lock_en),
        .phy_rx_phase_detector_en       (intf_die0.phy_rx_phase_detector_en),
        .phy_rx_tckn_shift              (5'd0),
        .phy_rx_decrement_shift         (1'b0),
        .phy_tx_tckn_shift_en           (intf_die0.phy_tx_tckn_shift_en),
        .phy_tx_tckn_shift              (intf_die0.phy_tx_tckn_shift),
        .phy_tx_decrement_shift         (intf_die0.phy_tx_decrement_shift),
        .phy_tx_tckn_shift_out_of_range (1'b0),
        .phy_rx_val_vref_ctrl           (intf_die0.phy_rx_valvref_ctrl),
        .phy_rx_data_vref_ctrl          (intf_die0.phy_rx_datavref_ctrl),
        .phy_tx_val_pi_phase_ctrl       (intf_die0.phy_tx_val_pi_phase_ctrl),
        .phy_tx_data_pi_phase_ctrl      (intf_die0.phy_tx_data_pi_phase_ctrl),
        .phy_rx_deskew_ctrl             (),
        .phy_tx_eq_preset_ctrl          (),
        .phy_tx_eq_preset_en            (),
        // Mainband lane selectors
        .substate_mb_tx_clk_lane_sel    (intf_die0.mb_tx_clk_lane_sel),
        .substate_mb_tx_data_lane_sel   (intf_die0.mb_tx_data_lane_sel),
        .substate_mb_tx_val_lane_sel    (intf_die0.mb_tx_val_lane_sel),
        .substate_mb_tx_trk_lane_sel    (intf_die0.mb_tx_trk_lane_sel),
        .substate_mb_rx_clk_lane_sel    (intf_die0.mb_rx_clk_lane_sel),
        .substate_mb_rx_data_lane_sel   (intf_die0.mb_rx_data_lane_sel),
        .substate_mb_rx_val_lane_sel    (intf_die0.mb_rx_val_lane_sel),
        .substate_mb_rx_trk_lane_sel    (intf_die0.mb_rx_trk_lane_sel),
        // RXCLKCAL pattern controls
        .rxclkcal_mb_tx_pattern_en      (intf_die0.mb_tx_pattern_en),
        .rxclkcal_mb_tx_pattern_setup   (intf_die0.mb_tx_pattern_setup),
        .rxclkcal_mb_tx_clk_pattern_sel (intf_die0.mb_tx_clk_pattern_sel),
        // SB TX → feeds intf.wrapper_tx_sb_msg_valid → attachment muxes into tb_muxed
        .substate_tx_sb_msg_valid       (intf_die0.wrapper_tx_sb_msg_valid),
        .substate_tx_sb_msg             (intf_die0.wrapper_tx_sb_msg),
        .substate_tx_msginfo            (intf_die0.wrapper_tx_msginfo),
        .substate_tx_data_field         (intf_die0.wrapper_tx_data_field),
        // SB RX ← driven by cross-die shift register
        .rx_sb_msg_valid                (intf_die0.rx_sb_msg_valid),
        .rx_sb_msg                      (intf_die0.rx_sb_msg),
        .rx_msginfo                     (intf_die0.rx_msginfo)
    );

    // =========================================================================
    // DUT Die 1  (identical connection pattern using intf_die1)
    // =========================================================================
    wrapper_MBTRAIN #(
        .MAX_VAL_VREF_CODE (MAX_VAL_VREF_CODE),
        .MAX_DATA_VREF_CODE(MAX_DATA_VREF_CODE),
        .MAX_DATA_PI_CODE  (MAX_DATA_PI_CODE),  .MIN_DATA_PI_CODE  (MIN_DATA_PI_CODE),
        .MAX_VAL_PI_CODE   (MAX_VAL_PI_CODE),
        .MAX_DESKEW_CODE   (MAX_DESKEW_CODE),   .MIN_DESKEW_CODE   (MIN_DESKEW_CODE)
    ) dut_die1 (
        .lclk                           (lclk),
        .rst_n                          (rst_n),
        .mbtrain_en                     (mbtrain_en_d1),
        .mbtrain_done                   (mbtrain_done_d1),
        .current_mbtrain_substate       (current_mbtrain_substate_d1),
        .ltsm_trainerror_req            (ltsm_trainerror_req_d1),
        .ltsm_linkinit_req              (ltsm_linkinit_req_d1),
        .ltsm_phyretrain_req            (ltsm_phyretrain_req_d1),
        .mbtrain_txselfcal_req          (mbtrain_txselfcal_req_d1),
        .mbtrain_speedidle_req          (mbtrain_speedidle_req_d1),
        .mbtrain_repair_req             (mbtrain_repair_req_d1),
        .analog_settle_time_done        (intf_die1.analog_settle_time_done),
        .analog_settle_timer_en         (intf_die1.analog_settle_timer_en),
        .state_n_0                      (intf_die1.state_n_0),
        .state_n_1                      (intf_die1.state_n_1),
        .param_negotiated_max_speed     (param_negotiated_max_speed),
        .is_continuous_clk_mode         (is_continuous_clk_mode),
        .rf_cap_SPMW                    (rf_cap_SPMW),
        .rf_ctrl_target_link_width      (rf_ctrl_target_link_width),
        .param_UCIe_S_x8               (param_UCIe_S_x8),
        .PHY_IN_RETRAIN                 (PHY_IN_RETRAIN_d1),
        .params_changed                 (params_changed_d1),
        .PHY_IN_RETRAIN_rst             (PHY_IN_RETRAIN_rst_d1),
        .busy_bit_rst                   (busy_bit_rst_d1),
        .mbinit_rx_data_lane_mask       (mbinit_rx_data_lane_mask),
        .mbinit_tx_data_lane_mask       (mbinit_tx_data_lane_mask),
        .mb_rx_data_lane_mask           (intf_die1.mb_rx_data_lane_mask),
        .mb_tx_data_lane_mask           (intf_die1.mb_tx_data_lane_mask),
        .local_sweep_en                 (intf_die1.sweep_en),
        .partner_sweep_en               (intf_die1.partner_sweep_en),
        .sweep_active_lanes             (),
        .sweep_done                     (intf_die1.sweep_done),
        .sweep_swept_code               (intf_die1.swept_code),
        .sweep_best_code                (intf_die1.best_code),
        .sweep_min_eye_width            (intf_die1.min_eye_width),
        .d2c_perlane_pass               (intf_die1.d2c_perlane_pass),
        .phy_negotiated_speed           (intf_die1.phy_negotiated_speed),
        .phy_tx_selfcal_en              (),
        .phy_rx_clock_lock_en           (intf_die1.phy_rx_clock_lock_en),
        .phy_rx_track_lock_en           (intf_die1.phy_rx_track_lock_en),
        .phy_rx_phase_detector_en       (intf_die1.phy_rx_phase_detector_en),
        .phy_rx_tckn_shift              (5'd0),
        .phy_rx_decrement_shift         (1'b0),
        .phy_tx_tckn_shift_en           (intf_die1.phy_tx_tckn_shift_en),
        .phy_tx_tckn_shift              (intf_die1.phy_tx_tckn_shift),
        .phy_tx_decrement_shift         (intf_die1.phy_tx_decrement_shift),
        .phy_tx_tckn_shift_out_of_range (1'b0),
        .phy_rx_val_vref_ctrl           (intf_die1.phy_rx_valvref_ctrl),
        .phy_rx_data_vref_ctrl          (intf_die1.phy_rx_datavref_ctrl),
        .phy_tx_val_pi_phase_ctrl       (intf_die1.phy_tx_val_pi_phase_ctrl),
        .phy_tx_data_pi_phase_ctrl      (intf_die1.phy_tx_data_pi_phase_ctrl),
        .phy_rx_deskew_ctrl             (),
        .phy_tx_eq_preset_ctrl          (),
        .phy_tx_eq_preset_en            (),
        .substate_mb_tx_clk_lane_sel    (intf_die1.mb_tx_clk_lane_sel),
        .substate_mb_tx_data_lane_sel   (intf_die1.mb_tx_data_lane_sel),
        .substate_mb_tx_val_lane_sel    (intf_die1.mb_tx_val_lane_sel),
        .substate_mb_tx_trk_lane_sel    (intf_die1.mb_tx_trk_lane_sel),
        .substate_mb_rx_clk_lane_sel    (intf_die1.mb_rx_clk_lane_sel),
        .substate_mb_rx_data_lane_sel   (intf_die1.mb_rx_data_lane_sel),
        .substate_mb_rx_val_lane_sel    (intf_die1.mb_rx_val_lane_sel),
        .substate_mb_rx_trk_lane_sel    (intf_die1.mb_rx_trk_lane_sel),
        .rxclkcal_mb_tx_pattern_en      (intf_die1.mb_tx_pattern_en),
        .rxclkcal_mb_tx_pattern_setup   (intf_die1.mb_tx_pattern_setup),
        .rxclkcal_mb_tx_clk_pattern_sel (intf_die1.mb_tx_clk_pattern_sel),
        .substate_tx_sb_msg_valid       (intf_die1.wrapper_tx_sb_msg_valid),
        .substate_tx_sb_msg             (intf_die1.wrapper_tx_sb_msg),
        .substate_tx_msginfo            (intf_die1.wrapper_tx_msginfo),
        .substate_tx_data_field         (intf_die1.wrapper_tx_data_field),
        .rx_sb_msg_valid                (intf_die1.rx_sb_msg_valid),
        .rx_sb_msg                      (intf_die1.rx_sb_msg),
        .rx_msginfo                     (intf_die1.rx_msginfo)
    );

    // =========================================================================
    // Assertions: 1-cycle tx_sb_msg_valid spacing rule
    // =========================================================================
    property p_die0_msg_spacing;
        @(posedge lclk) disable iff (!rst_n)
            intf_die0.tb_muxed_tx_sb_msg_valid |=> !intf_die0.tb_muxed_tx_sb_msg_valid;
    endproperty
    assert property (p_die0_msg_spacing)
    else $error("[ASSERT] Die A: tx_sb_msg_valid violated 1-cycle spacing rule at %0t ns", $realtime);

    property p_die1_msg_spacing;
        @(posedge lclk) disable iff (!rst_n)
            intf_die1.tb_muxed_tx_sb_msg_valid |=> !intf_die1.tb_muxed_tx_sb_msg_valid;
    endproperty
    assert property (p_die1_msg_spacing)
    else $error("[ASSERT] Die B: tx_sb_msg_valid violated 1-cycle spacing rule at %0t ns", $realtime);

    // =========================================================================
    // state_n synchronisation background thread
    //   Keeps intf_dieX.state_n_0 aligned with the DUT's current MBTRAIN
    //   substate so unit_D2C_sweep (inside ltsm_tb_attachments) selects the
    //   correct code range.
    //   Runs as a background thread — do_reset_and_init() drives state_n_0
    //   procedurally during reset/init (when mbtrain_en=0), then this thread
    //   takes over once the DUT is running. No conflict: only one driver is
    //   active at a time.
    // =========================================================================
    initial begin : bg_state_n_sync
        forever begin
            @(posedge lclk);
            if (mbtrain_en_d0) begin
                intf_die0.state_n_0 = current_mbtrain_substate_d0;
                intf_die1.state_n_0 = current_mbtrain_substate_d1;
            end
        end
    end

    // =========================================================================
    // Monitor: Die A substate transitions only (Die B is the symmetric partner;
    // printing both would double every line).
    // TRAINERROR events on either die are always printed.
    // =========================================================================
    initial begin : mon_substate_dieA
        state_n_e last = LOG_NOP;
        forever begin
            @(posedge lclk);
            if (current_mbtrain_substate_d0 !== last) begin
                $display("  [Die A] %-45s  (@%0t ns)",
                    current_mbtrain_substate_d0.name(), $realtime);
                last = current_mbtrain_substate_d0;
            end
        end
    end

    initial begin : mon_trainerror
        forever begin
            @(posedge lclk);
            if (dut_die0.trainerror_detected)
                $display("  [Die A] *** TRAINERROR_DETECTED at %0t ns ***", $realtime);
            if (dut_die1.trainerror_detected)
                $display("  [Die B] *** TRAINERROR_DETECTED at %0t ns ***", $realtime);
        end
    end

    // =========================================================================
    // Cycle counter (sampled at scenario start/end)
    // =========================================================================
    longint unsigned scenario_start_cycle;

    function automatic longint unsigned get_cycle();
        // timescale 1ns/1ps → $realtime is in ns; CLK_PERIOD = 1.0 ns
        return longint'($realtime / CLK_PERIOD);
    endfunction

    // =========================================================================
    // Task: init_intf_defaults
    //   Initialise interface signals that must not be left floating,
    //   including the error thresholds used by wrapper_D2C_PT_top.
    // =========================================================================
    task automatic init_intf_defaults();
        // These must be driven before the first reset
        intf_die0.cfg_max_err_thresh_perlane = 12'hFFF;
        intf_die0.cfg_max_err_thresh_aggr    = 16'hFFFF;
        intf_die0.tb_wrong_msginfo           = 16'h0;
        intf_die0.tb_wrong_data_field        = 64'h0;
        intf_die0.tb_wrong_sb_msg_en         = 1'b0;
        intf_die0.tb_wrong_sb_msg            = NOTHING;
        intf_die0.rf_cap_SPMW                = rf_cap_SPMW;
        intf_die0.rf_ctrl_target_link_width  = rf_ctrl_target_link_width;
        intf_die0.param_UCIe_S_x8            = param_UCIe_S_x8;
        intf_die0.linkspeed_success_lanes    = 16'hFFFF;
        intf_die0.state_n_1                  = LOG_MBTRAIN_VALVREF;
        intf_die0.state_n_2                  = LOG_MBTRAIN_VALVREF;
        intf_die0.state_n_3                  = LOG_MBTRAIN_VALVREF;

        intf_die1.cfg_max_err_thresh_perlane = 12'hFFF;
        intf_die1.cfg_max_err_thresh_aggr    = 16'hFFFF;
        intf_die1.tb_wrong_msginfo           = 16'h0;
        intf_die1.tb_wrong_data_field        = 64'h0;
        intf_die1.tb_wrong_sb_msg_en         = 1'b0;
        intf_die1.tb_wrong_sb_msg            = NOTHING;
        intf_die1.rf_cap_SPMW                = rf_cap_SPMW;
        intf_die1.rf_ctrl_target_link_width  = rf_ctrl_target_link_width;
        intf_die1.param_UCIe_S_x8            = param_UCIe_S_x8;
        intf_die1.linkspeed_success_lanes    = 16'hFFFF;
        intf_die1.state_n_1                  = LOG_MBTRAIN_VALVREF;
        intf_die1.state_n_2                  = LOG_MBTRAIN_VALVREF;
        intf_die1.state_n_3                  = LOG_MBTRAIN_VALVREF;
    endtask

    // =========================================================================
    // Task: set_allpass
    //   Both dies report full pass on every D2C point test.
    //   Clears all error injection and timeout overrides.
    // =========================================================================
    task automatic set_allpass();
        intf_die0.tb_force_perlane_pass = 16'hFFFF;
        intf_die0.tb_force_aggr_pass    = 1'b1;
        intf_die0.tb_force_val_pass     = 1'b1;
        intf_die0.tb_wait_timeout       = 1'b0;
        intf_die0.tb_aggr_err           = 16'h0000;

        intf_die1.tb_force_perlane_pass = 16'hFFFF;
        intf_die1.tb_force_aggr_pass    = 1'b1;
        intf_die1.tb_force_val_pass     = 1'b1;
        intf_die1.tb_wait_timeout       = 1'b0;
        intf_die1.tb_aggr_err           = 16'h0000;
    endtask

    // =========================================================================
    // Task: force_rxdeskew_narrow_eye
    //   All data lanes FAIL → unit_D2C_sweep reports eye_width=0 < 12
    //   → unit_RXDESKEW_local triggers DTC1 arc.
    // =========================================================================
    task automatic force_rxdeskew_narrow_eye();
        intf_die0.tb_force_perlane_pass = 16'h0000;
        intf_die0.tb_force_val_pass     = 1'b0;
        intf_die1.tb_force_perlane_pass = 16'h0000;
        intf_die1.tb_force_val_pass     = 1'b0;
    endtask

    // =========================================================================
    // Task: force_linkspeed_repair
    //   Partial lane pass (lower 8 of 16) so unit_LINKSPEED_local detects errors
    //   and routes to REPAIR.  degrade_feasible remains 1 (lanes 0-7 all pass).
    // =========================================================================
    task automatic force_linkspeed_repair();
        intf_die0.tb_force_perlane_pass = 16'h00FF;
        intf_die1.tb_force_perlane_pass = 16'h00FF;
    endtask

    // =========================================================================
    // Task: force_linkspeed_phyretrain
    //   Assert PHY_IN_RETRAIN + params_changed on both dies so that
    //   unit_LINKSPEED_local exits to PHYRETRAIN (no D2C errors needed).
    // =========================================================================
    task automatic force_linkspeed_phyretrain();
        PHY_IN_RETRAIN_d0 = 1'b1; PHY_IN_RETRAIN_d1 = 1'b1;
        params_changed_d0 = 1'b1; params_changed_d1 = 1'b1;
    endtask

    task automatic clear_linkspeed_phyretrain();
        PHY_IN_RETRAIN_d0 = 1'b0; PHY_IN_RETRAIN_d1 = 1'b0;
        params_changed_d0 = 1'b0; params_changed_d1 = 1'b0;
    endtask

    // =========================================================================
    // Task: do_reset_and_init
    //   Full hard reset + LTSM state-N sequencing so wrapper_MBTRAIN's internal
    //   soft_rst_n generator fires correctly.
    //   Sequence: rst_n=0 → rst_n=1 → LOG_RESET → LOG_SBINIT → LOG_MBTRAIN_VALVREF
    // =========================================================================
    task automatic do_reset_and_init();
        // Drive state_n before deasserting reset
        intf_die0.state_n_0 = LOG_RESET; intf_die1.state_n_0 = LOG_RESET;

        rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 5);

        // Hold RESET so SOFT_RESET_GEN latches first_enter_flag
        intf_die0.state_n_0 = LOG_RESET; intf_die1.state_n_0 = LOG_RESET;
        #(CLK_PERIOD * 5);

        // Transition to SBINIT → releases soft_rst_n
        intf_die0.state_n_0 = LOG_SBINIT; intf_die1.state_n_0 = LOG_SBINIT;
        #(CLK_PERIOD * 5);

        // Drive initial MBTRAIN context for unit_D2C_sweep code-range selection
        intf_die0.state_n_0 = LOG_MBTRAIN_VALVREF;
        intf_die1.state_n_0 = LOG_MBTRAIN_VALVREF;
        #(CLK_PERIOD * 5);

        // Clear any leftover re-entry requests from the previous scenario
        mbtrain_txselfcal_req_d0 = 1'b0; mbtrain_speedidle_req_d0 = 1'b0; mbtrain_repair_req_d0 = 1'b0;
        mbtrain_txselfcal_req_d1 = 1'b0; mbtrain_speedidle_req_d1 = 1'b0; mbtrain_repair_req_d1 = 1'b0;
        clear_linkspeed_phyretrain();
    endtask

    // =========================================================================
    // Task: launch_mbtrain
    //   Assert mbtrain_en on both dies and record cycle-count start.
    // =========================================================================
    task automatic launch_mbtrain();
        scenario_start_cycle = get_cycle();
        mbtrain_en_d0 = 1'b1;
        mbtrain_en_d1 = 1'b1;
    endtask

    // =========================================================================
    // Task: launch_mbtrain_with_req
    //   Assert mbtrain_en plus exactly one re-entry request; deassert the
    //   request after one clock so the ctrl FSM samples it once only.
    // =========================================================================
    task automatic launch_mbtrain_with_req(
            input logic do_speedidle,
            input logic do_txselfcal,
            input logic do_repair
        );
        scenario_start_cycle = get_cycle();
        mbtrain_speedidle_req_d0 = do_speedidle; mbtrain_speedidle_req_d1 = do_speedidle;
        mbtrain_txselfcal_req_d0 = do_txselfcal; mbtrain_txselfcal_req_d1 = do_txselfcal;
        mbtrain_repair_req_d0    = do_repair;    mbtrain_repair_req_d1    = do_repair;
        mbtrain_en_d0 = 1'b1;
        mbtrain_en_d1 = 1'b1;
        @(posedge lclk); // let ctrl FSM sample the request
        mbtrain_speedidle_req_d0 = 1'b0; mbtrain_speedidle_req_d1 = 1'b0;
        mbtrain_txselfcal_req_d0 = 1'b0; mbtrain_txselfcal_req_d1 = 1'b0;
        mbtrain_repair_req_d0    = 1'b0; mbtrain_repair_req_d1    = 1'b0;
    endtask

    // =========================================================================
    // Task: wait_for_completion
    //   Waits for mbtrain_done on both dies then evaluates the outcome.
    //   expected_exit: "LINKINIT" or "PHYRETRAIN"
    //   Prints PASS/FAIL and lclk cycles consumed.
    // =========================================================================
    task automatic wait_for_completion(
            input string test_name,
            input string expected_exit
        );
        string result;
        longint unsigned cycles_used;
        result = "FAIL";

        fork
            begin : th_done
                wait (mbtrain_done_d0 && mbtrain_done_d1);
                #(CLK_PERIOD * 5);
                if (ltsm_trainerror_req_d0 || ltsm_trainerror_req_d1) begin
                    result = "FAIL — unexpected TRAINERROR";
                end else if (expected_exit == "PHYRETRAIN") begin
                    result = (ltsm_phyretrain_req_d0 && ltsm_phyretrain_req_d1)
                        ? "PASS" : "FAIL — expected PHYRETRAIN exit, got something else";
                end else begin // LINKINIT
                    if (ltsm_linkinit_req_d0 && ltsm_linkinit_req_d1)
                        result = "PASS";
                    else if (ltsm_phyretrain_req_d0 || ltsm_phyretrain_req_d1)
                        result = "FAIL — unexpected PHYRETRAIN exit";
                    else
                        result = "FAIL — no ltsm_linkinit_req asserted";
                end
                disable th_trainerror; disable th_timeout;
            end
            begin : th_trainerror
                wait (ltsm_trainerror_req_d0 || ltsm_trainerror_req_d1);
                result = "FAIL — early TRAINERROR";
                disable th_done; disable th_timeout;
            end
            begin : th_timeout
                #(CLK_PERIOD * TIMEOUT_CYCLES);
                result = $sformatf("FAIL — TIMEOUT (Die A stuck at %s)",
                    current_mbtrain_substate_d0.name());
                disable th_done; disable th_trainerror;
            end
        join

        cycles_used = get_cycle() - scenario_start_cycle;

        $display("  ┌─────────────────────────────────────────────────────────┐");
        $display("  │  %-14s  Result : %-30s │", test_name, result);
        $display("  │  Cycles consumed : %-37d │", cycles_used);
        $display("  └─────────────────────────────────────────────────────────┘");

        mbtrain_en_d0 = 1'b0;
        mbtrain_en_d1 = 1'b0;
        #(CLK_PERIOD * 20);
    endtask

    // =========================================================================
    // SCENARIO TASKS
    // =========================================================================

    // ------------------------------------------------------------------
    // S1: Nominal Full Training Flow
    //   VALVREF→DATAVREF→SPEEDIDLE→TXSELFCAL→RXCLKCAL→
    //   VALTRAINCENTER→VALTRAINVREF→DTC1→DATATRAINVREF→
    //   RXDESKEW→DTC2→LINKSPEED→LINKINIT
    // ------------------------------------------------------------------
    task automatic scenario_01_nominal_full_flow();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S1 — Nominal Full Training Flow (From MBINIT)           ║");
        $display("  ║  VALVREF → … → LINKSPEED → LINKINIT                     ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        launch_mbtrain();
        wait_for_completion("S1", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S2: RXDESKEW Retry ×1 then LINKINIT
    //   Force narrow eye on first RXDESKEW → DTC1 arc.
    //   Restore allpass before second RXDESKEW → normal exit.
    // ------------------------------------------------------------------
    task automatic scenario_02_rxdeskew_retry_once();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S2 — RXDESKEW Retry ×1 then LINKINIT                   ║");
        $display("  ║  … → RXDESKEW(arc) → DTC1 → … → RXDESKEW(ok) → LINKINIT ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        force_rxdeskew_narrow_eye();   // arm narrow eye BEFORE launch
        launch_mbtrain();

        fork
            begin : s2_watcher
                // Wait for RXDESKEW to be entered then exited (arc → DTC1)
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_RXDESKEW && mbtrain_en_d0);
                wait (current_mbtrain_substate_d0 != LOG_MBTRAIN_RXDESKEW && mbtrain_en_d0);
                set_allpass();  // second RXDESKEW will find a wide eye
            end
        join_none

        wait_for_completion("S2", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S3: RXDESKEW Retry ×2 then LINKINIT
    //   Force narrow eye for first TWO RXDESKEW visits; restore on the third.
    // ------------------------------------------------------------------
    task automatic scenario_03_rxdeskew_retry_twice();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S3 — RXDESKEW Retry ×2 then LINKINIT                   ║");
        $display("  ║  RXDESKEW(arc)→DTC1→RXDESKEW(arc)→DTC1→RXDESKEW(ok)    ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        force_rxdeskew_narrow_eye();
        launch_mbtrain();

        fork
            begin : s3_watcher
                repeat (2) begin
                    wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_RXDESKEW && mbtrain_en_d0);
                    wait (current_mbtrain_substate_d0 != LOG_MBTRAIN_RXDESKEW && mbtrain_en_d0);
                end
                set_allpass();  // third RXDESKEW will succeed
            end
        join_none

        wait_for_completion("S3", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S4: LINKSPEED → REPAIR ×1 → TXSELFCAL → … → LINKINIT
    //   Partial-lane fail at first LINKSPEED → REPAIR.
    //   After REPAIR exits to TXSELFCAL, restore allpass for second LINKSPEED.
    // ------------------------------------------------------------------
    task automatic scenario_04_linkspeed_repair_once();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S4 — LINKSPEED → REPAIR ×1 → … → LINKINIT              ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        // Arm repair fail before DTC2 so it's active when LINKSPEED runs its D2C
        launch_mbtrain();

        fork
            begin : s4_watcher
                // Arm repair just before LINKSPEED is entered (arm at DTC2 entry)
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_DATATRAINCENTER2 && mbtrain_en_d0);
                force_linkspeed_repair();
                // Once REPAIR completes (enters TXSELFCAL), restore allpass
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_REPAIR    && mbtrain_en_d0);
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_TXSELFCAL && mbtrain_en_d0);
                set_allpass();
            end
        join_none

        wait_for_completion("S4", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S5: LINKSPEED → REPAIR ×2 → … → LINKINIT
    //   Two repair cycles before final LINKINIT.
    // ------------------------------------------------------------------
    task automatic scenario_05_linkspeed_repair_twice();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S5 — LINKSPEED → REPAIR ×2 → … → LINKINIT              ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        launch_mbtrain();

        fork
            begin : s5_watcher
                // Arm repair at DTC2 entry (first time)
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_DATATRAINCENTER2 && mbtrain_en_d0);
                force_linkspeed_repair();
                // Wait for two complete REPAIR→TXSELFCAL cycles
                repeat (2) begin
                    wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_REPAIR    && mbtrain_en_d0);
                    wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_TXSELFCAL && mbtrain_en_d0);
                end
                set_allpass();  // third LINKSPEED visit → LINKINIT
            end
        join_none

        wait_for_completion("S5", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S6: Entry at SPEEDIDLE  (From PHYRETRAIN → SPEEDIDLE → … → LINKINIT)
    // ------------------------------------------------------------------
    task automatic scenario_06_entry_at_speedidle();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S6 — Entry at SPEEDIDLE  (PHYRETRAIN → SPEEDIDLE)       ║");
        $display("  ║  SPEEDIDLE → TXSELFCAL → … → LINKINIT                   ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        launch_mbtrain_with_req(1'b1, 1'b0, 1'b0);  // speedidle_req=1
        wait_for_completion("S6", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S7: Entry at TXSELFCAL  (From PHYRETRAIN → TXSELFCAL → … → LINKINIT)
    // ------------------------------------------------------------------
    task automatic scenario_07_entry_at_txselfcal();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S7 — Entry at TXSELFCAL  (PHYRETRAIN → TXSELFCAL)       ║");
        $display("  ║  TXSELFCAL → RXCLKCAL → … → LINKINIT                    ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        launch_mbtrain_with_req(1'b0, 1'b1, 1'b0);  // txselfcal_req=1
        wait_for_completion("S7", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S8: Entry at REPAIR  (From PHYRETRAIN → REPAIR → TXSELFCAL → … → LINKINIT)
    // ------------------------------------------------------------------
    task automatic scenario_08_entry_at_repair();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S8 — Entry at REPAIR  (PHYRETRAIN → REPAIR)             ║");
        $display("  ║  REPAIR → TXSELFCAL → … → LINKINIT                      ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        launch_mbtrain_with_req(1'b0, 1'b0, 1'b1);  // repair_req=1
        wait_for_completion("S8", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S9: L1 → SPEEDIDLE → … → LINKINIT
    //   Same SPEEDIDLE entry mechanism as S6; covers the L1 path explicitly.
    // ------------------------------------------------------------------
    task automatic scenario_09_l1_resume_at_speedidle();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S9 — L1 Exit / Resume at SPEEDIDLE                      ║");
        $display("  ║  SPEEDIDLE → TXSELFCAL → … → LINKINIT                   ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        launch_mbtrain_with_req(1'b1, 1'b0, 1'b0);  // speedidle_req=1  (same as L1 path)
        wait_for_completion("S9", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S10: LINKSPEED → PHYRETRAIN exit, then re-entry at TXSELFCAL → LINKINIT
    //   Part A: force PHYRETRAIN exit.
    //   Part B: simulate external PHYRETRAIN completed; re-enter at TXSELFCAL.
    // ------------------------------------------------------------------
    task automatic scenario_10_linkspeed_phyretrain_reenter_txselfcal();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S10 — LINKSPEED → PHYRETRAIN, re-entry at TXSELFCAL     ║");
        $display("  ║  Part A: full flow → LINKSPEED → PHYRETRAIN exit         ║");
        $display("  ║  Part B: TXSELFCAL → … → LINKINIT                       ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");

        // ── Part A ─────────────────────────────────────────────────────
        $display("  [S10-A] Forcing LINKSPEED → PHYRETRAIN exit …");
        set_allpass();
        do_reset_and_init();
        // Arm phyretrain at DTC2 entry so it is active when LINKSPEED runs
        launch_mbtrain();
        fork
            begin : s10a_arm
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_DATATRAINCENTER2 && mbtrain_en_d0);
                force_linkspeed_phyretrain();
            end
        join_none
        wait_for_completion("S10-A", "PHYRETRAIN");

        // ── Part B ─────────────────────────────────────────────────────
        $display("  [S10-B] Re-entering at TXSELFCAL (PHYRETRAIN completed) …");
        clear_linkspeed_phyretrain();
        set_allpass();
        do_reset_and_init();
        launch_mbtrain_with_req(1'b0, 1'b1, 1'b0);  // txselfcal_req=1
        wait_for_completion("S10-B", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S11: RXDESKEW Retry ×1  +  REPAIR ×1 → LINKINIT
    //   Combined: first RXDESKEW arcs to DTC1, then LINKSPEED forces REPAIR.
    // ------------------------------------------------------------------
    task automatic scenario_11_rxdeskew_retry_plus_repair();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S11 — RXDESKEW Retry ×1 + REPAIR ×1 → LINKINIT         ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");
        set_allpass();
        do_reset_and_init();
        force_rxdeskew_narrow_eye();
        launch_mbtrain();

        fork
            begin : s11_ctrl
                // 1: clear narrow eye after first RXDESKEW arc
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_RXDESKEW   && mbtrain_en_d0);
                wait (current_mbtrain_substate_d0 != LOG_MBTRAIN_RXDESKEW   && mbtrain_en_d0);
                set_allpass();

                // 2: arm repair at DTC2 entry
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_DATATRAINCENTER2 && mbtrain_en_d0);
                force_linkspeed_repair();

                // 3: restore allpass once REPAIR exits to TXSELFCAL
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_REPAIR    && mbtrain_en_d0);
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_TXSELFCAL && mbtrain_en_d0);
                set_allpass();
            end
        join_none

        wait_for_completion("S11", "LINKINIT");
    endtask

    // ------------------------------------------------------------------
    // S12: Worst-Case Coverage
    //   Part A: RXDESKEW retry ×1 + REPAIR ×1 → PHYRETRAIN exit
    //   Part B: re-entry at REPAIR → TXSELFCAL → … → LINKINIT
    // ------------------------------------------------------------------
    task automatic scenario_12_worst_case();
        $display("\n");
        $display("  ╔═══════════════════════════════════════════════════════════╗");
        $display("  ║  S12 — Worst-Case Coverage                               ║");
        $display("  ║  Part A: retry+repair → PHYRETRAIN exit                 ║");
        $display("  ║  Part B: REPAIR re-entry → … → LINKINIT                 ║");
        $display("  ╚═══════════════════════════════════════════════════════════╝");

        // ── Part A ─────────────────────────────────────────────────────
        $display("  [S12-A] RXDESKEW retry + REPAIR + PHYRETRAIN exit …");
        set_allpass();
        do_reset_and_init();
        force_rxdeskew_narrow_eye();
        launch_mbtrain();

        fork
            begin : s12a_ctrl
                // 1: clear narrow eye after first RXDESKEW arc
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_RXDESKEW   && mbtrain_en_d0);
                wait (current_mbtrain_substate_d0 != LOG_MBTRAIN_RXDESKEW   && mbtrain_en_d0);
                set_allpass();

                // 2: arm repair at DTC2 entry
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_DATATRAINCENTER2 && mbtrain_en_d0);
                force_linkspeed_repair();

                // 3: after REPAIR exits, arm phyretrain for the second LINKSPEED visit
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_REPAIR    && mbtrain_en_d0);
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_TXSELFCAL && mbtrain_en_d0);
                set_allpass();
                // Arm phyretrain at the second DTC2 entry
                wait (current_mbtrain_substate_d0 == LOG_MBTRAIN_DATATRAINCENTER2 && mbtrain_en_d0);
                force_linkspeed_phyretrain();
            end
        join_none

        wait_for_completion("S12-A", "PHYRETRAIN");

        // ── Part B ─────────────────────────────────────────────────────
        $display("  [S12-B] Re-entering at REPAIR (from PHYRETRAIN) …");
        clear_linkspeed_phyretrain();
        set_allpass();
        do_reset_and_init();
        launch_mbtrain_with_req(1'b0, 1'b0, 1'b1);  // repair_req=1
        wait_for_completion("S12-B", "LINKINIT");
    endtask

    // =========================================================================
    // Main Stimulus
    // =========================================================================
    initial begin
        $display("");
        $display("  ╔═══════════════════════════════════════════════════════════════╗");
        $display("  ║     wrapper_MBTRAIN  Integration Testbench                   ║");
        $display("  ║     12 Scenarios — All Happy Paths  (No TRAINERROR Inject)   ║");
        $display("  ║     Only Die A substate transitions are printed.             ║");
        $display("  ╚═══════════════════════════════════════════════════════════════╝");

        // Safe initial state before the first reset
        init_intf_defaults();
        set_allpass();
        mbtrain_en_d0 = 1'b0; mbtrain_en_d1 = 1'b0;
        clear_linkspeed_phyretrain();

        scenario_01_nominal_full_flow();
        scenario_02_rxdeskew_retry_once();
        scenario_03_rxdeskew_retry_twice();
        scenario_04_linkspeed_repair_once();
        scenario_05_linkspeed_repair_twice();
        scenario_06_entry_at_speedidle();
        scenario_07_entry_at_txselfcal();
        scenario_08_entry_at_repair();
        scenario_09_l1_resume_at_speedidle();
        scenario_10_linkspeed_phyretrain_reenter_txselfcal();
        scenario_11_rxdeskew_retry_plus_repair();
        scenario_12_worst_case();

        $display("");
        $display("  ╔═══════════════════════════════════════════════════════════════╗");
        $display("  ║     wrapper_MBTRAIN Testbench — ALL 12 SCENARIOS COMPLETE    ║");
        $display("  ╚═══════════════════════════════════════════════════════════════╝");
        $finish;
    end

endmodule