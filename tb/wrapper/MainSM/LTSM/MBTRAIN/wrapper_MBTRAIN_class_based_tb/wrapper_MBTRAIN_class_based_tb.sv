// target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/mbtrain_cb_tb_top.sv

import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import mbtrain_cb_types_pkg::*;
import mbtrain_cb_pkg::*;

module wrapper_MBTRAIN_class_based_tb;

  logic lclk;
  logic rst_n;

  // Clock generation
  initial begin
    lclk = 0;
    forever #1 lclk = ~lclk;
  end

  mbtrain_cb_if vif(lclk, rst_n);

  state_n_e simulated_state_n_1;
  state_n_e last_logged_substate;
  state_n_e speedidle_entry_state;

  always_ff @(posedge lclk or negedge rst_n) begin
    if (!rst_n) begin
      last_logged_substate <= LOG_NOP;
      speedidle_entry_state <= LOG_MBTRAIN_DATAVREF;
    end else begin
      if (vif.current_mbtrain_substate != last_logged_substate) begin
        if (vif.current_mbtrain_substate == LOG_MBTRAIN_SPEEDIDLE) begin
          speedidle_entry_state <= last_logged_substate;
        end
        last_logged_substate <= vif.current_mbtrain_substate;
      end
    end
  end

  always_comb begin
    case (vif.current_mbtrain_substate)
      // current_mbtrain_substate is a registered log signal and can lag the
      // controller state by one cycle. During the first SPEEDIDLE cycle after
      // DATAVREF or LINKSPEED, keep state_n_1 equal to that legal entry source.
      LOG_MBTRAIN_DATAVREF:        simulated_state_n_1 = LOG_MBTRAIN_DATAVREF;
      LOG_MBTRAIN_LINKSPEED:       simulated_state_n_1 = LOG_MBTRAIN_LINKSPEED;
      LOG_PHYRETRAIN:              simulated_state_n_1 = LOG_PHYRETRAIN;
      LOG_MBTRAIN_SPEEDIDLE:       simulated_state_n_1 = speedidle_entry_state;
      default:                     simulated_state_n_1 = vif.current_mbtrain_substate;
    endcase
  end
  assign vif.state_n_1 = simulated_state_n_1;

  wrapper_MBTRAIN DUT (
    .lclk(vif.lclk),
    .rst_n(vif.rst_n),
    .mbtrain_en(vif.mbtrain_en),
    .mbtrain_done(vif.mbtrain_done),
    .current_mbtrain_substate(vif.current_mbtrain_substate),
    .ltsm_trainerror_req(vif.ltsm_trainerror_req),
    .ltsm_linkinit_req(vif.ltsm_linkinit_req),
    .ltsm_phyretrain_req(vif.ltsm_phyretrain_req),
    .mbtrain_txselfcal_req(vif.mbtrain_txselfcal_req),
    .mbtrain_speedidle_req(vif.mbtrain_speedidle_req),
    .mbtrain_repair_req(vif.mbtrain_repair_req),
    .analog_settle_time_done(vif.analog_settle_time_done),
    .analog_settle_timer_en(vif.analog_settle_timer_en),
    .state_n_0(vif.state_n_0),
    .state_n_1(vif.state_n_1),
    .param_negotiated_max_speed(vif.param_negotiated_max_speed),
    .is_continuous_clk_mode(vif.is_continuous_clk_mode),
    .rf_cap_SPMW(vif.rf_cap_SPMW),
    .rf_ctrl_target_link_width(vif.rf_ctrl_target_link_width),
    .param_UCIe_S_x8(vif.param_UCIe_S_x8),
    .PHY_IN_RETRAIN(vif.PHY_IN_RETRAIN),
    .params_changed(vif.params_changed),
    .PHY_IN_RETRAIN_rst(vif.PHY_IN_RETRAIN_rst),
    .busy_bit_rst(vif.busy_bit_rst),
    .mbinit_rx_data_lane_mask(vif.mbinit_rx_data_lane_mask),
    .mbinit_tx_data_lane_mask(vif.mbinit_tx_data_lane_mask),
    .mb_rx_data_lane_mask(vif.mb_rx_data_lane_mask),
    .mb_tx_data_lane_mask(vif.mb_tx_data_lane_mask),
    .local_sweep_en(vif.local_sweep_en),
    .partner_sweep_en(vif.partner_sweep_en),
    .sweep_active_lanes(vif.sweep_active_lanes),
    .sweep_done(vif.sweep_done),
    .sweep_swept_code(vif.sweep_swept_code),
    .sweep_best_code(vif.sweep_best_code),
    .sweep_min_eye_width(vif.sweep_min_eye_width),
    .d2c_perlane_pass(vif.d2c_perlane_pass),
    .phy_negotiated_speed(vif.phy_negotiated_speed),
    .phy_tx_selfcal_en(vif.phy_tx_selfcal_en),
    .phy_rx_clock_lock_en(vif.phy_rx_clock_lock_en),
    .phy_rx_track_lock_en(vif.phy_rx_track_lock_en),
    .phy_rx_phase_detector_en(vif.phy_rx_phase_detector_en),
    .phy_tx_tckn_shift_en(vif.phy_tx_tckn_shift_en),
    .phy_tx_tckn_shift(vif.phy_tx_tckn_shift),
    .phy_tx_decrement_shift(vif.phy_tx_decrement_shift),
    .phy_rx_val_vref_ctrl(vif.phy_rx_val_vref_ctrl),
    .phy_rx_data_vref_ctrl(vif.phy_rx_data_vref_ctrl),
    .phy_tx_val_pi_phase_ctrl(vif.phy_tx_val_pi_phase_ctrl),
    .phy_tx_data_pi_phase_ctrl(vif.phy_tx_data_pi_phase_ctrl),
    .phy_rx_deskew_ctrl(vif.phy_rx_deskew_ctrl),
    .phy_tx_eq_preset_ctrl(vif.phy_tx_eq_preset_ctrl),
    .phy_tx_eq_preset_en(vif.phy_tx_eq_preset_en),
    .substate_mb_tx_clk_lane_sel(vif.substate_mb_tx_clk_lane_sel),
    .substate_mb_tx_data_lane_sel(vif.substate_mb_tx_data_lane_sel),
    .substate_mb_tx_val_lane_sel(vif.substate_mb_tx_val_lane_sel),
    .substate_mb_tx_trk_lane_sel(vif.substate_mb_tx_trk_lane_sel),
    .substate_mb_rx_clk_lane_sel(vif.substate_mb_rx_clk_lane_sel),
    .substate_mb_rx_data_lane_sel(vif.substate_mb_rx_data_lane_sel),
    .substate_mb_rx_val_lane_sel(vif.substate_mb_rx_val_lane_sel),
    .substate_mb_rx_trk_lane_sel(vif.substate_mb_rx_trk_lane_sel),
    .rxclkcal_mb_tx_pattern_en(vif.rxclkcal_mb_tx_pattern_en),
    .rxclkcal_mb_tx_pattern_setup(vif.rxclkcal_mb_tx_pattern_setup),
    .rxclkcal_mb_tx_clk_pattern_sel(vif.rxclkcal_mb_tx_clk_pattern_sel),
    .substate_tx_sb_msg_valid(vif.substate_tx_sb_msg_valid),
    .substate_tx_sb_msg(vif.substate_tx_sb_msg),
    .substate_tx_msginfo(vif.substate_tx_msginfo),
    .substate_tx_data_field(vif.substate_tx_data_field),
    .rx_sb_msg_valid(vif.rx_sb_msg_valid),
    .rx_sb_msg(vif.rx_sb_msg),
    .rx_msginfo(vif.rx_msginfo),
    .phy_rx_tckn_shift('0),
    .phy_rx_decrement_shift('0),
    .phy_tx_tckn_shift_out_of_range('0)
  );

  assign vif.dbg_soft_rst_n = DUT.soft_rst_n;
  assign vif.dbg_valvref_local_state = DUT.u_VALVREF.u_VALVREF_local.current_state;
  assign vif.dbg_valvref_partner_state = DUT.u_VALVREF.u_VALVREF_partner.current_state;
  assign vif.dbg_valvref_local_done = DUT.u_VALVREF.local_valvref_done;
  assign vif.dbg_valvref_partner_done = DUT.u_VALVREF.partner_valvref_done;

  initial begin
    mbtrain_cb_env env;
    mbtrain_cb_testlib testlib;

    env = new(vif);
    testlib = new();

    env.run_all(testlib.scenarios);

    $finish;
  end

endmodule
