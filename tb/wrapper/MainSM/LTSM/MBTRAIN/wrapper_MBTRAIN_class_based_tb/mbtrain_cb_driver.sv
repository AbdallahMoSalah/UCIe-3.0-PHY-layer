// target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/mbtrain_cb_driver.sv


class mbtrain_cb_driver;
  virtual mbtrain_cb_if vif;
  mbtrain_cb_config cfg;
  
  function new(virtual mbtrain_cb_if vif, mbtrain_cb_config cfg);
    this.vif = vif;
    this.cfg = cfg;
  endfunction

  task automatic wait_for_state_or_timeout(input state_n_e target_state, output bit hit_state);
    hit_state = 1'b0;
    fork
      begin
        wait(vif.current_mbtrain_substate == target_state);
        hit_state = 1'b1;
      end
      begin
        repeat(cfg.watchdog_cycles) @(posedge vif.lclk);
      end
    join_any
    disable fork;
  endtask

  task automatic cleanup_after_check();
    vif.stop_mbtrain();
    cfg.suppress_response_en = 1'b0;
    vif.clear_rx_msg();
    @(negedge vif.lclk);
    vif.state_n_0 = LOG_RESET;
    repeat(3) @(posedge vif.lclk);
  endtask

  task automatic track_ltsm_context(input int generation);
    state_n_e last_substate;

    last_substate = LOG_NOP;
    forever begin
      @(negedge vif.lclk);
      if (!vif.rst_n || generation != cfg.scenario_generation) begin
        return;
      end
      if (vif.mbtrain_en
          && vif.current_mbtrain_substate != LOG_NOP
          && vif.current_mbtrain_substate != last_substate) begin
        vif.state_n_0 = vif.current_mbtrain_substate;
        last_substate = vif.current_mbtrain_substate;
      end
    end
  endtask

  task run_scenario(mbtrain_scenario_s scenario);
    bit hit_injection_state;

    $display("[SCENARIO START] %s width=%s speed=%0d", scenario.name, scenario.width.name(), scenario.speed);
    cfg.begin_scenario();
    
    // 1. Reset DUT
    vif.drive_reset();
    wait(vif.rst_n === 1'b1);
    
    // 2. Configure width/speed/retrain while soft reset is still active.
    vif.param_negotiated_max_speed = scenario.speed;
    vif.PHY_IN_RETRAIN = scenario.PHY_IN_RETRAIN;
    vif.params_changed = scenario.params_changed;
    cfg.current_train_pass_mask = 16'hFFFF;
    cfg.configure_linkspeed_script(scenario.linkspeed_pass_q, scenario.d2c_pass_mask);
    cfg.suppress_response_en = scenario.suppress_response_en;
    cfg.suppress_response_msg = scenario.suppress_response_msg;
    cfg.last_timeout = 1'b0;
    
    // Width config (simplified for now, setting target link width)
    case(scenario.width)
      WIDTH_X16: begin
        vif.rf_ctrl_target_link_width = 4'h2;
        vif.mbinit_rx_data_lane_mask = 3'b011;
        vif.mbinit_tx_data_lane_mask = 3'b011;
      end
      WIDTH_X8: begin
        vif.rf_ctrl_target_link_width = 4'h1;
        vif.mbinit_rx_data_lane_mask = 3'b001;
        vif.mbinit_tx_data_lane_mask = 3'b001;
      end
      WIDTH_X4: begin
        // The RTL models x4 as an x8-class module using an x4 lane-mask code.
        // unit_negotiated_lanes only asserts is_x8_module for target width 4'h1.
        vif.rf_ctrl_target_link_width = 4'h1;
        vif.mbinit_rx_data_lane_mask = 3'b100;
        vif.mbinit_tx_data_lane_mask = 3'b100;
      end
    endcase

    // 3. Drive RESET -> SBINIT to create the wrapper's internal soft_rst_n
    // release before entering MBTRAIN.VALVREF.
    vif.release_soft_reset_sequence(LOG_MBTRAIN_VALVREF);

    // 4. Configure D2C model result.
    vif.drive_d2c_result(scenario.d2c_pass_mask);
    
    // 5. Start MBTRAIN
    vif.start_mbtrain();
    fork
      track_ltsm_context(cfg.scenario_generation);
    join_none

    if (scenario.inject_soft_reset_mid_sequence) begin
      wait_for_state_or_timeout(LOG_MBTRAIN_RXCLKCAL, hit_injection_state);
      if (!hit_injection_state) begin
        cfg.last_timeout = 1'b1;
        $display("[ERROR] Timeout waiting for RXCLKCAL injection point in %s", scenario.name);
        vif.stop_mbtrain();
        cfg.suppress_response_en = 1'b0;
        repeat(5) @(posedge vif.lclk);
        $display("[SCENARIO END] %s", scenario.name);
        return;
      end
      $display("[INJECT] soft reset during %s", vif.current_mbtrain_substate.name());
      vif.state_n_0 = LOG_RESET;
      repeat(3) @(posedge vif.lclk);
      vif.state_n_0 = LOG_SBINIT;
      repeat(3) @(posedge vif.lclk);
      vif.stop_mbtrain();
      cfg.suppress_response_en = 1'b0;
      repeat(5) @(posedge vif.lclk);
      $display("[SCENARIO END] %s", scenario.name);
      return;
    end

    if (scenario.inject_disable_mid_sequence) begin
      wait_for_state_or_timeout(LOG_MBTRAIN_RXCLKCAL, hit_injection_state);
      if (!hit_injection_state) begin
        cfg.last_timeout = 1'b1;
        $display("[ERROR] Timeout waiting for RXCLKCAL injection point in %s", scenario.name);
        vif.stop_mbtrain();
        cfg.suppress_response_en = 1'b0;
        repeat(5) @(posedge vif.lclk);
        $display("[SCENARIO END] %s", scenario.name);
        return;
      end
      $display("[INJECT] mbtrain_en deassert during %s", vif.current_mbtrain_substate.name());
      vif.stop_mbtrain();
      cfg.suppress_response_en = 1'b0;
      repeat(5) @(posedge vif.lclk);
      $display("[SCENARIO END] %s", scenario.name);
      return;
    end
    
    // 6. Wait for scoreboard terminal condition
    // This task assumes that some higher level (env) or background task 
    // will detect terminal condition. For now, we wait on mbtrain_done.
    fork
      begin
        wait(vif.mbtrain_done === 1);
        cfg.last_timeout = 1'b0;
        $display("[EVENT] mbtrain_done detected");
      end
      begin
        repeat(cfg.watchdog_cycles) @(posedge vif.lclk);
        cfg.last_timeout = 1'b1;
        $display("[ERROR] Timeout waiting for mbtrain_done in driver after %0d cycles", cfg.watchdog_cycles);
        $display("[TIMEOUT SNAPSHOT] substate=%s state_n_0=%s soft_rst_n=%b mbtrain_en=%b tx_valid=%b tx_msg=0x%02h rx_valid=%b rx_msg=0x%02h sweep(local,partner,done)=%b,%b,%b masks(tx,rx)=%b,%b active_lanes=%h valvref(local_state,partner_state,local_done,partner_done)=%0d,%0d,%b,%b",
          vif.current_mbtrain_substate.name(),
          vif.state_n_0.name(),
          vif.dbg_soft_rst_n,
          vif.mbtrain_en,
          vif.substate_tx_sb_msg_valid,
          vif.substate_tx_sb_msg,
          vif.rx_sb_msg_valid,
          vif.rx_sb_msg,
          vif.local_sweep_en,
          vif.partner_sweep_en,
          vif.sweep_done,
          vif.mb_tx_data_lane_mask,
          vif.mb_rx_data_lane_mask,
          vif.sweep_active_lanes,
          vif.dbg_valvref_local_state,
          vif.dbg_valvref_partner_state,
          vif.dbg_valvref_local_done,
          vif.dbg_valvref_partner_done);
      end
    join_any
    disable fork;
    
    // 7. Leave terminal evidence visible until scoreboard checks this scenario.
    cfg.suppress_response_en = 1'b0;
    
    $display("[SCENARIO END] %s", scenario.name);
  endtask
endclass
