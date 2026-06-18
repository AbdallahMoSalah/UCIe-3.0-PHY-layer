// target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/mbtrain_cb_testlib.sv

class mbtrain_cb_testlib;
  mbtrain_scenario_s scenarios[$];

  function new();
    define_scenarios();
  endfunction

  function void reset_scenario(ref mbtrain_scenario_s s);
    s.name = "";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_LINKINIT;
    s.state_path_q.delete();
    s.linkspeed_pass_q.delete();
    s.d2c_pass_mask = 16'hFFFF;
    s.PHY_IN_RETRAIN = 1'b0;
    s.params_changed = 1'b0;
    s.expected_rx_mask = 3'b011;
    s.expected_tx_mask = 3'b011;
    s.expected_timeout = 1'b0;
    s.inject_soft_reset_mid_sequence = 1'b0;
    s.inject_disable_mid_sequence = 1'b0;
    s.suppress_response_en = 1'b0;
    s.suppress_response_msg = 8'h00;
  endfunction

  function void add_nominal_path(ref mbtrain_scenario_s s);
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

  function void push_scenario(input mbtrain_scenario_s s);
    scenarios.push_back(s);
  endfunction

  function void define_scenarios();
    mbtrain_scenario_s s;

    // -------------------------------------------------------------------------
    // Group A: normal success flows
    // -------------------------------------------------------------------------
    reset_scenario(s);
    s.name = "A1_GOLDEN_X16";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFFFF);
    s.expected_rx_mask = 3'b011;
    s.expected_tx_mask = 3'b011;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "A2_GOLDEN_X8";
    s.width = WIDTH_X8;
    s.speed = SPEED_32G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'h00FF;
    s.linkspeed_pass_q.push_back(16'h00FF);
    s.expected_rx_mask = 3'b001;
    s.expected_tx_mask = 3'b001;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "A3_GOLDEN_X4";
    s.width = WIDTH_X4;
    s.speed = SPEED_16G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'h000F;
    s.linkspeed_pass_q.push_back(16'h000F);
    s.expected_rx_mask = 3'b100;
    s.expected_tx_mask = 3'b100;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "A4_HIGH_SPEED_RXDESKEW_EQ_GOLDEN";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFFFF);
    add_nominal_path(s);
    push_scenario(s);

    // -------------------------------------------------------------------------
    // Group B: speed degrade
    // -------------------------------------------------------------------------
    reset_scenario(s);
    s.name = "B1_SINGLE_SPEED_DEGRADE_THEN_SUCCESS";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'h0003);
    s.linkspeed_pass_q.push_back(16'hFFFF);
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "B2_MULTI_SPEED_DEGRADE_THEN_SUCCESS";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'h0003);
    s.linkspeed_pass_q.push_back(16'h0003);
    s.linkspeed_pass_q.push_back(16'hFFFF);
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "B3_LOWEST_SPEED_STILL_FAILS";
    s.width = WIDTH_X16;
    s.speed = SPEED_4G;
    s.expected_exit = EXIT_TRAINERROR;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'h0003);
    add_nominal_path(s);
    push_scenario(s);

    // -------------------------------------------------------------------------
    // Group C: width degrade / repair
    // -------------------------------------------------------------------------
    reset_scenario(s);
    s.name = "C1_WIDTH_DEGRADE_X16_TO_X8_LOW";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'h00FF);
    s.linkspeed_pass_q.push_back(16'h00FF);
    s.expected_rx_mask = 3'b001;
    s.expected_tx_mask = 3'b001;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "C2_WIDTH_DEGRADE_X16_TO_X8_HIGH";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFF00);
    s.linkspeed_pass_q.push_back(16'hFF00);
    s.expected_rx_mask = 3'b010;
    s.expected_tx_mask = 3'b010;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "C3_WIDTH_DEGRADE_X8_TO_X4_LOW";
    s.width = WIDTH_X8;
    s.speed = SPEED_32G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'h00FF;
    s.linkspeed_pass_q.push_back(16'h000F);
    s.linkspeed_pass_q.push_back(16'h000F);
    s.expected_rx_mask = 3'b100;
    s.expected_tx_mask = 3'b100;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "C4_WIDTH_DEGRADE_X8_TO_X4_HIGH";
    s.width = WIDTH_X8;
    s.speed = SPEED_32G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'h00FF;
    s.linkspeed_pass_q.push_back(16'h00F0);
    s.linkspeed_pass_q.push_back(16'h00F0);
    s.expected_rx_mask = 3'b101;
    s.expected_tx_mask = 3'b101;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "C5_WIDTH_DEGRADE_EXHAUSTED_AFTER_X16_TO_X8";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_TRAINERROR;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'h00FF);
    s.linkspeed_pass_q.push_back(16'h0003);
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "C6_WIDTH_DEGRADE_EXHAUSTED_AFTER_X8_TO_X4";
    s.width = WIDTH_X8;
    s.speed = SPEED_32G;
    s.expected_exit = EXIT_TRAINERROR;
    s.d2c_pass_mask = 16'h00FF;
    s.linkspeed_pass_q.push_back(16'h000F);
    s.linkspeed_pass_q.push_back(16'h0003);
    add_nominal_path(s);
    push_scenario(s);

    // -------------------------------------------------------------------------
    // Group D: PHY retrain
    // -------------------------------------------------------------------------
    reset_scenario(s);
    s.name = "D1_PHY_RETRAIN_PARAMS_CHANGED";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_PHYRETRAIN;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFFFF);
    s.PHY_IN_RETRAIN = 1'b1;
    s.params_changed = 1'b1;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "D2_PHY_RETRAIN_NO_PARAMS_CHANGED";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_LINKINIT;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFFFF);
    s.PHY_IN_RETRAIN = 1'b1;
    s.params_changed = 1'b0;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "D3_PHY_RETRAIN_REENTRY_SUCCESS";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_PHYRETRAIN;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFFFF);
    s.PHY_IN_RETRAIN = 1'b1;
    s.params_changed = 1'b1;
    add_nominal_path(s);
    push_scenario(s);

    // -------------------------------------------------------------------------
    // Group E/F: representative negative/control scenarios.
    // These are intentionally expected to expose RTL behavior once the first
    // happy/regression paths are stable.
    // -------------------------------------------------------------------------
    reset_scenario(s);
    s.name = "E3_REPAIR_DEGRADE_NOT_POSSIBLE";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_TRAINERROR;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'h0000);
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "E7_TIMEOUT_RXDESKEW_END_RESP_MISSING";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_TIMEOUT;
    s.expected_timeout = 1'b1;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFFFF);
    s.suppress_response_en = 1'b1;
    s.suppress_response_msg = MBTRAIN_RXDESKEW_end_resp;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "F3_SOFT_RESET_MID_SEQUENCE";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_IDLE;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFFFF);
    s.inject_soft_reset_mid_sequence = 1'b1;
    add_nominal_path(s);
    push_scenario(s);

    reset_scenario(s);
    s.name = "F4_DISABLE_MBTRAIN_MID_SEQUENCE";
    s.width = WIDTH_X16;
    s.speed = SPEED_64G;
    s.expected_exit = EXIT_IDLE;
    s.d2c_pass_mask = 16'hFFFF;
    s.linkspeed_pass_q.push_back(16'hFFFF);
    s.inject_disable_mid_sequence = 1'b1;
    add_nominal_path(s);
    push_scenario(s);
  endfunction
endclass
