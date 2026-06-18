# MBTRAIN Class-Based Testbench Implementation Plan

## 1. Goal

Create a new self-checking, class-based SystemVerilog testbench for `wrapper_MBTRAIN`.

All new TB files must live in:

```text
target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/
```

Do not depend on the old weak `wrapper_MBTRAIN_tb.sv` as the test architecture. It can be used only as a port-reference if needed.

The testbench must verify the whole MBTRAIN wrapper and controller flow:

1. Correct entry into MBTRAIN.
2. Correct substate sequence.
3. Correct Local/Partner sideband request/response behavior through the wrapper.
4. Correct D2C sweep and point-test stimulus.
5. Correct RXDESKEW DTC1 loopback behavior.
6. Correct LINKSPEED decisions: LINKINIT, SPEEDIDLE, REPAIR, PHYRETRAIN, TRAINERROR.
7. Correct REPAIR lane-mask updates and width degrade limits.
8. Correct reset, disable, and timeout behavior.
9. Trackable terminal output without noisy cycle-by-cycle spam.

## 2. Source Knowledge Used

Use these files as the authority for behavior:

```text
target_implementation_technique/null/hierarchy.md
target_implementation_technique/ucie_reference_content/details_of_MBTRAIN/*.txt
target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/MBTRAIN/**/*.sv
target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/wrapper_MBTRAIN_tb_but_with_deep_scenarios.md
```

Important hierarchy conclusions:

- MBTRAIN has 13 substates in this order:
  `VALVREF, DATAVREF, SPEEDIDLE, TXSELFCAL, RXCLKCAL, VALTRAINCENTER, VALTRAINVREF, DATATRAINCENTER1, DATATRAINVREF, RXDESKEW, DATATRAINCENTER2, LINKSPEED, REPAIR`.
- `unit_D2C_sweep` is external to individual substates and is shared through `wrapper_MBTRAIN`.
- The new implementation uses `*_pass` polarity: `1` means pass, `0` means fail.
- Do not copy old `*_err` polarity behavior from `UCIe-3.0-PHY-layer`.
- `wrapper_MBTRAIN` contains both local and partner FSMs per substate and uses one broadcast sideband RX bus.
- `wrapper_LINKSPEED` combines local and partner route requests using AND, so both local and partner halves must agree before `linkspeed_*_req` reaches `unit_MBTRAIN_ctrl`.
- `wrapper_REPAIR` owns final lane-mask update through its partner FSM.

## 3. RTL Facts That Shape the TB

### 3.1 Top wrapper ports to drive

The class-based TB must instantiate `wrapper_MBTRAIN` and drive at least:

- Clock/reset: `lclk`, `rst_n`.
- MBTRAIN control: `mbtrain_en`, `mbtrain_txselfcal_req`, `mbtrain_speedidle_req`, `mbtrain_repair_req`.
- Soft-reset generation inputs: `state_n_0`, `state_n_1`.
- Configuration: `param_negotiated_max_speed`, `is_continuous_clk_mode`, `rf_cap_SPMW`, `rf_ctrl_target_link_width`, `param_UCIe_S_x8`.
- Retrain flags: `PHY_IN_RETRAIN`, `params_changed`.
- Initial lane masks: `mbinit_rx_data_lane_mask`, `mbinit_tx_data_lane_mask`.
- External D2C: `sweep_done`, `sweep_swept_code`, `sweep_best_code[0:15]`, `sweep_min_eye_width`, `d2c_perlane_pass`.
- PHY inputs: `phy_rx_tckn_shift`, `phy_rx_decrement_shift`, `phy_tx_tckn_shift_out_of_range`.
- Sideband RX: `rx_sb_msg_valid`, `rx_sb_msg`, `rx_msginfo`.
- Analog settle: `analog_settle_time_done`.

### 3.2 Top wrapper outputs to observe

Monitor at least:

- `mbtrain_done`.
- `current_mbtrain_substate`.
- `ltsm_trainerror_req`, `ltsm_linkinit_req`, `ltsm_phyretrain_req`.
- `PHY_IN_RETRAIN_rst`, `busy_bit_rst`.
- `mb_rx_data_lane_mask`, `mb_tx_data_lane_mask`.
- `local_sweep_en`, `partner_sweep_en`, `sweep_active_lanes`.
- `phy_negotiated_speed`.
- `analog_settle_timer_en`.
- `substate_tx_sb_msg_valid`, `substate_tx_sb_msg`, `substate_tx_msginfo`, `substate_tx_data_field`.
- MB mux outputs and retained PHY controls.

### 3.3 Controller behavior to check

`unit_MBTRAIN_ctrl` does the following:

- Normal entry starts at `VALVREF`.
- Entry shortcuts:
  - `mbtrain_txselfcal_req` starts at `TXSELFCAL`.
  - `mbtrain_speedidle_req` starts at `SPEEDIDLE`.
  - `mbtrain_repair_req` starts at `REPAIR`.
- RXDESKEW:
  - `dtc1_loopback_req` routes to `DATATRAINCENTER1`.
  - Otherwise `rxdeskew_done` routes to `DATATRAINCENTER2`.
- LINKSPEED:
  - `linkspeed_linkinit_req` or `linkspeed_phyretrain_req` routes to `MBTRAIN_DONE`.
  - `linkspeed_speedidle_req` routes to `SPEEDIDLE`.
  - `linkspeed_repair_req` routes to `REPAIR`.
  - No valid route after `linkspeed_done` routes to TRAINERROR.
- REPAIR:
  - `repair_done` routes to `TXSELFCAL`.
- Any `trainerror_detected` routes to `MBTRAIN_DONE` and asserts `ltsm_trainerror_req`.
- Dropping `mbtrain_en` after MBTRAIN started returns controller to idle.

### 3.4 Important limitation

Most early wrapper substates in `wrapper_MBTRAIN.sv` tie their `ss_trainerror_req` to `0`. Therefore, training-failure scenarios for those substates cannot be tested by expecting a real exposed `trainerror_req` from the wrapper unless the RTL is later extended. For now:

- Real error scenarios must focus on RXDESKEW and REPAIR, plus invalid LINKSPEED route behavior.
- Early-substate negative tests should be modeled as timeout/no-response tests and checked by TB watchdog, not as RTL `ltsm_trainerror_req`, unless a force-based white-box mode is explicitly enabled.

## 4. Proposed Testbench File Set

Create these files in `wrapper_MBTRAIN_class_based_tb/`:

```text
mbtrain_cb_tb_top.sv
mbtrain_cb_if.sv
mbtrain_cb_pkg.sv
mbtrain_cb_types_pkg.sv
mbtrain_cb_config.sv
mbtrain_cb_transaction.sv
mbtrain_cb_sb_agent.sv
mbtrain_cb_d2c_model.sv
mbtrain_cb_driver.sv
mbtrain_cb_monitor.sv
mbtrain_cb_scoreboard.sv
mbtrain_cb_coverage.sv
mbtrain_cb_sequences.sv
mbtrain_cb_env.sv
mbtrain_cb_testlib.sv
mbtrain_class_based.f
run_mbtrain_class_based.do
```

Keep this markdown plan in the same folder.

## 5. Package and Interface Plan

### 5.1 `mbtrain_cb_types_pkg.sv`

Define enums and structs used by all classes:

- `mbtrain_scenario_group_e`: `GROUP_A_NORMAL`, `GROUP_B_SPEED`, `GROUP_C_WIDTH`, `GROUP_D_PHYRETRAIN`, `GROUP_E_FAILURE`, `GROUP_F_ASYNC`.
- `mbtrain_expected_exit_e`: `EXIT_LINKINIT`, `EXIT_SPEEDIDLE_LOOP`, `EXIT_REPAIR_LOOP`, `EXIT_PHYRETRAIN`, `EXIT_TRAINERROR`, `EXIT_TIMEOUT`, `EXIT_IDLE`.
- `mbtrain_width_e`: `WIDTH_X16`, `WIDTH_X8`, `WIDTH_X4`.
- `mbtrain_speed_e`: match RTL encodings:
  - `3'b000 = 4 GT/s`
  - `3'b001 = 8 GT/s`
  - `3'b010 = 12 GT/s`
  - `3'b011 = 16 GT/s`
  - `3'b100 = 24 GT/s`
  - `3'b101 = 32 GT/s`
  - `3'b110 = 48 GT/s`
  - `3'b111 = 64 GT/s`
- `mbtrain_route_action_e`: `ROUTE_LINKINIT`, `ROUTE_SPEED_DEGRADE`, `ROUTE_REPAIR`, `ROUTE_PHYRETRAIN`, `ROUTE_NO_VALID_ROUTE`.
- `mbtrain_d2c_result_s`:
  - `logic [15:0] perlane_pass`
  - `logic val_pass`
  - `logic aggr_pass`
  - `int min_eye_width`
  - `int best_code[16]`
- `mbtrain_scenario_s`:
  - scenario name
  - start mode
  - width setup
  - speed setup
  - continuous clock mode
  - `PHY_IN_RETRAIN`
  - `params_changed`
  - D2C results per substate
  - expected state path queue
  - expected terminal exit
  - expected lane masks
  - expected prints.

### 5.2 `mbtrain_cb_if.sv`

Create one interface that mirrors `wrapper_MBTRAIN` ports and exposes helper tasks:

- `drive_reset()`
- `release_soft_reset_sequence()`: drive `state_n_0 = LOG_RESET`, then `LOG_SBINIT` to release internal `soft_rst_n`.
- `start_mbtrain()`
- `stop_mbtrain()`
- `drive_analog_settle_done()`
- `drive_d2c_result(perlane_pass, min_eye_width, best_code[])`
- `send_rx_msg(msg, info, data)`
- `clear_rx_msg()`
- `wait_lclk(cycles)`

Use `UCIe_pkg::*` and `ltsm_state_n_pkg::*`.

## 6. Class Architecture

### 6.1 `mbtrain_cb_config`

Holds global knobs:

- `int sb_delay_cycles`
- `int analog_settle_cycles`
- `int watchdog_cycles`
- min/max code values for Vref, PI, deskew
- default D2C pass mask
- default lane masks
- `bit enable_verbose_sb`
- `bit enable_whitebox_faults`
- `bit stop_on_first_fail`
- `bit print_flow_path`

### 6.2 `mbtrain_cb_transaction`

Represents one observed or expected sideband event:

- time
- substate context
- direction: TX observed or RX injected
- message enum
- msginfo
- data
- scenario tag

### 6.3 `mbtrain_cb_sb_agent`

Acts as the remote sideband partner model.

Responsibilities:

- Watch `substate_tx_sb_msg_valid`.
- Decode `substate_tx_sb_msg`.
- After `sb_delay_cycles`, inject the correct response on `rx_sb_msg_valid`.
- Support scenario-specific overrides:
  - wrong response
  - no response
  - delayed response
  - remote initiates request before local completes
  - force speed degrade over repair
  - force PHY retrain response
  - force TRAINERROR entry request.

For normal loopback style, response mapping:

- `*_start_req -> *_start_resp`
- `*_end_req -> *_end_resp`
- `*_done_req -> *_done_resp`
- `LINKSPEED_error_req -> LINKSPEED_error_resp`
- `LINKSPEED_exit_to_repair_req -> LINKSPEED_exit_to_repair_resp`
- `LINKSPEED_exit_to_speed_degrade_req -> LINKSPEED_exit_to_speed_degrade_resp`
- `LINKSPEED_exit_to_phy_retrain_req -> LINKSPEED_exit_to_phy_retrain_resp`
- `REPAIR_init_req -> REPAIR_init_resp`
- `REPAIR_apply_degrade_req -> REPAIR_apply_degrade_resp`
- `REPAIR_end_req -> REPAIR_end_resp`
- `RXDESKEW_exit_to_DATATRAINCENTER1_req -> RXDESKEW_exit_to_DATATRAINCENTER1_resp`

The shared opcode:

```text
MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req
MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp
```

must be decoded by current substate:

- In `LOG_MBTRAIN_RXDESKEW`: treat it as EQ preset request/response.
- In `LOG_MBTRAIN_LINKSPEED`: treat it as PHY retrain request/response.

### 6.4 `mbtrain_cb_d2c_model`

Models the external sweep and point-test inputs to `wrapper_MBTRAIN`.

Responsibilities:

- Watch `local_sweep_en` and `partner_sweep_en`.
- Drive `sweep_swept_code` through legal range for the current substate.
- Drive `sweep_done` when the scenario says the sweep/point-test completed.
- Drive `sweep_best_code[0:15]`.
- Drive `sweep_min_eye_width`.
- Drive `d2c_perlane_pass`.
- For LINKSPEED, use a one-point TX D2C result. `d2c_perlane_pass & active_rx_lanes` determines stable lanes.

Default good result:

```text
d2c_perlane_pass = sweep_active_lanes
sweep_min_eye_width = nonzero passing value
best_code[lane] = mid code
```

Failure examples:

```text
x16 low half good:  d2c_perlane_pass = 16'h00FF
x16 high half good: d2c_perlane_pass = 16'hFF00
x8 low quarter:     d2c_perlane_pass = 16'h000F
x8 high quarter:    d2c_perlane_pass = 16'h00F0
unrepairable:       d2c_perlane_pass = 16'h0003 or 16'h5555
all fail:           d2c_perlane_pass = 16'h0000
```

### 6.5 `mbtrain_cb_driver`

Runs one scenario:

1. Reset DUT.
2. Release wrapper soft reset using `state_n_0 = LOG_RESET`, then `LOG_SBINIT`.
3. Configure width/speed/retrain knobs.
4. Configure D2C result script.
5. Enable MBTRAIN using selected entry request.
6. Wait for expected terminal condition.
7. Deassert `mbtrain_en`.
8. Return DUT to clean idle before next scenario.

### 6.6 `mbtrain_cb_monitor`

Collects:

- State changes from `current_mbtrain_substate`.
- One-line sideband TX/RX events when enabled.
- Route outputs: `ltsm_linkinit_req`, `ltsm_phyretrain_req`, `ltsm_trainerror_req`.
- Lane-mask changes.
- D2C sweep start/done events.
- Reset and disable events.

Do not print every cycle.

### 6.7 `mbtrain_cb_scoreboard`

Checks each scenario:

- Expected state sequence, including loops.
- Terminal condition:
  - LINKINIT: `mbtrain_done && ltsm_linkinit_req`
  - PHYRETRAIN: `mbtrain_done && ltsm_phyretrain_req`
  - TRAINERROR: `mbtrain_done && ltsm_trainerror_req`
  - timeout: TB watchdog fires and expected timeout is true
  - disable/reset: state returns to idle/NOP with no stale request.
- No illegal state jump.
- No duplicate unexpected loop.
- `mbtrain_done` only at terminal controller state.
- LINKSPEED route is consistent with scenario result.
- REPAIR lane masks match expected degraded lane map.
- `PHY_IN_RETRAIN_rst` and `busy_bit_rst` pulse only in the expected LINKSPEED cases.
- D2C pass polarity is correct: pass means `1`.

### 6.8 `mbtrain_cb_coverage`

Coverage groups:

- Entry mode: full, TXSELFCAL, SPEEDIDLE, REPAIR.
- Width: x16, x8, x4.
- Speed: 4, 8, 12, 16, 24, 32, 48, 64 GT/s.
- Clock mode: strobe, continuous.
- RXDESKEW:
  - <= 32 GT/s no EQ path.
  - > 32 GT/s EQ path.
  - 0, 1, 2, 3, 4 DTC1 loops.
  - loop overflow/trainerror.
- LINKSPEED route:
  - LINKINIT
  - REPAIR
  - SPEEDIDLE
  - PHYRETRAIN
  - invalid/no route -> TRAINERROR
- REPAIR:
  - x16 -> x8 low
  - x16 -> x8 high
  - x8 -> x4 low
  - x8 -> x4 high
  - degrade not possible
- Reset/disable:
  - reset in each major phase
  - disable in each major phase
  - no-response timeout in representative states.

## 7. Scenario Matrix

### Group A: Normal success

#### A1: Golden path x16

Setup:

- width x16:
  - `rf_cap_SPMW = 0`
  - `rf_ctrl_target_link_width = 4'h2`
  - `param_UCIe_S_x8 = 0`
  - initial lane masks `3'b011`
- speed stable
- all D2C results pass
- `PHY_IN_RETRAIN = 0`
- `params_changed = 0`

Expected path:

```text
VALVREF -> DATAVREF -> SPEEDIDLE -> TXSELFCAL -> RXCLKCAL ->
VALTRAINCENTER -> VALTRAINVREF -> DATATRAINCENTER1 ->
DATATRAINVREF -> RXDESKEW -> DATATRAINCENTER2 -> LINKSPEED ->
LINKINIT
```

Expected terminal:

```text
mbtrain_done = 1
ltsm_linkinit_req = 1
ltsm_trainerror_req = 0
ltsm_phyretrain_req = 0
```

#### A2: Golden path x8

Same as A1, but:

- `rf_ctrl_target_link_width = 4'h1`
- initial lane masks `3'b001`
- active lanes expected `16'h00FF`

#### A3: Golden path x4

Start from lane mask `3'b100` or `3'b101` after prior repair/degrade setup. Expected active lanes must match chosen x4 code. This is primarily a post-repair steady-state coverage test.

#### A4: High-speed golden path with RXDESKEW EQ

Setup:

- speed `3'b110` or `3'b111`.
- RXDESKEW should exercise EQ preset message path.
- No DTC1 loop.
- LINKSPEED stable.

Expected:

```text
RXDESKEW EQ preset handshake observed
RXDESKEW exits to DATATRAINCENTER2
LINKSPEED exits to LINKINIT
```

### Group B: Speed degrade

#### B1: Single speed degrade then success

First LINKSPEED:

- `d2c_perlane_pass` creates an error.
- `width_degrade_feasible = 0` by using an unrepairable lane result.
- LINKSPEED requests speed degrade.

Then:

- Controller returns to `SPEEDIDLE`.
- Testbench updates the next LINKSPEED D2C result to all pass.

Expected path:

```text
... -> LINKSPEED -> SPEEDIDLE -> TXSELFCAL -> RXCLKCAL ->
VALTRAINCENTER -> VALTRAINVREF -> DATATRAINCENTER1 ->
DATATRAINVREF -> RXDESKEW -> DATATRAINCENTER2 -> LINKSPEED ->
LINKINIT
```

#### B2: Multiple speed degrades then success

Setup:

- initial speed 64 GT/s.
- fail first LINKSPEED -> degrade.
- fail second LINKSPEED -> degrade.
- pass third LINKSPEED.

Expected:

- Multiple loops through `SPEEDIDLE`.
- Final route to LINKINIT.
- Print only one event per degrade loop.

#### B3: Lowest speed still fails

Setup:

- current speed is 4 GT/s.
- LINKSPEED result fails.
- No width degrade feasible.

Expected:

- Either RTL routes invalid/no valid route to `ltsm_trainerror_req`, or TB flags a design issue if it loops to SPEEDIDLE at lowest speed.
- Expected terminal should be TRAINERROR per reference.

### Group C: Width degrade and repair

#### C1: Width degrade x16 to x8 low

Setup:

- x16 module equation true:
  - `rf_cap_SPMW = 0`
  - `rf_ctrl_target_link_width = 4'h2`
  - `param_UCIe_S_x8 = 0`
- LINKSPEED failure with `d2c_perlane_pass = 16'h00FF`.

Expected:

```text
... -> LINKSPEED -> REPAIR -> TXSELFCAL -> RXCLKCAL ->
VALTRAINCENTER -> VALTRAINVREF -> DATATRAINCENTER1 ->
DATATRAINVREF -> RXDESKEW -> DATATRAINCENTER2 -> LINKSPEED ->
LINKINIT
```

Expected lane masks after repair:

```text
mb_rx_data_lane_mask = 3'b001
mb_tx_data_lane_mask = 3'b001
active lanes = 16'h00FF
```

#### C2: Width degrade x16 to x8 high

Same as C1, but `d2c_perlane_pass = 16'hFF00`.

Expected lane mask:

```text
3'b010
```

#### C3: Width degrade x8 to x4 low

Setup:

- x8 module:
  - `rf_ctrl_target_link_width = 4'h1`
- initial lane masks `3'b001`.
- LINKSPEED failure with `d2c_perlane_pass = 16'h000F`.

Expected lane mask:

```text
3'b100
```

#### C4: Width degrade x8 to x4 high

Same as C3, but `d2c_perlane_pass = 16'h00F0`.

Expected lane mask:

```text
3'b101
```

#### C5: Second width degrade not possible after x16 to x8

Setup:

- First failure degrades x16 to x8.
- Second LINKSPEED failure is not degradable for the remaining x8 lane map.

Expected:

```text
... -> LINKSPEED -> REPAIR -> ... -> LINKSPEED -> TRAINERROR
```

#### C6: Second width degrade not possible after x8 to x4

Setup:

- First failure degrades x8 to x4.
- Second LINKSPEED failure cannot degrade further.

Expected:

```text
... -> LINKSPEED -> REPAIR -> ... -> LINKSPEED -> TRAINERROR
```

### Group D: PHY retrain

#### D1: PHY retrain request

Setup:

- LINKSPEED D2C passes.
- `PHY_IN_RETRAIN = 1`.
- `params_changed = 1`.

Expected:

```text
... -> LINKSPEED -> PHYRETRAIN
```

Check:

- `ltsm_phyretrain_req = 1`
- `ltsm_linkinit_req = 0`

#### D2: PHY retrain without params changed

Setup:

- LINKSPEED D2C passes.
- `PHY_IN_RETRAIN = 1`.
- `params_changed = 0`.

Expected:

- Clear busy/PHY retrain flags as implemented.
- Continue to LINKINIT.

Check:

- `busy_bit_rst` pulse at LINKSPEED done path.
- `PHY_IN_RETRAIN_rst` pulse according to RTL.

#### D3: PHY retrain then re-enter MBTRAIN and succeed

Run two sessions:

1. Session 1 exits to PHYRETRAIN.
2. TB deasserts `mbtrain_en`, updates LTSM flags, re-enters MBTRAIN.
3. Session 2 succeeds to LINKINIT.

#### D4: PHY retrain then speed degrade

Session 2 starts after PHYRETRAIN and causes one LINKSPEED speed degrade before success.

### Group E: Training failure

#### E1: RXDESKEW DTC1 loop overflow

Setup:

- high speed.
- Force RXDESKEW to request DTC1 loop more than allowed maximum.

Expected:

```text
... -> RXDESKEW -> DATATRAINCENTER1 -> ... -> RXDESKEW repeated
then TRAINERROR
```

Check:

- `ltsm_trainerror_req = 1`.

#### E2: RXDESKEW invalid EQ preset response

Setup:

- high speed.
- Inject invalid EQ response or repeated fail response.

Expected:

- If RTL supports retry, verify bounded retry.
- If retry exhausted, TRAINERROR.

#### E3: REPAIR degrade not possible

Setup:

- LINKSPEED routes to REPAIR but `degrade_feasible = 0` or remote sends no-degrade code.

Expected:

- REPAIR asserts `trainerror_req`.
- `wrapper_MBTRAIN` asserts `ltsm_trainerror_req`.

#### E4: LINKSPEED invalid terminal route

Setup:

- Cause `linkspeed_done` without any of linkinit/speedidle/repair/phyretrain asserted.

Expected:

- Controller asserts `ltsm_trainerror_req`.

#### E5-E15: Representative no-response timeouts

For each major substate, suppress the required sideband response:

- VALVREF start response missing.
- DATAVREF end response missing.
- SPEEDIDLE done response missing.
- TXSELFCAL done response missing.
- RXCLKCAL start/done response missing.
- VALTRAINCENTER done response missing.
- VALTRAINVREF end response missing.
- DATATRAINCENTER1 end response missing.
- DATATRAINVREF end response missing.
- RXDESKEW end response missing.
- DATATRAINCENTER2 end response missing.
- LINKSPEED done/error response missing.
- REPAIR end response missing.

Expected:

- TB watchdog timeout.
- No false PASS.
- If future RTL implements timeout-to-TRAINERROR, scoreboard should accept TRAINERROR and mark the scenario as RTL-handled.

### Group F: Async and control injection

#### F1: External TRAINERROR entry request during each major substate

Inject `TRAINERROR_Entry_req` through `rx_sb_msg` while each substate is active.

Expected:

- Substates that consume TRAINERROR should assert their error output or route terminal.
- For substates that do not expose trainerror to wrapper, scoreboard records unsupported RTL path and marks as expected limitation unless white-box force mode is enabled.

#### F2: Hard reset during MBTRAIN

For each major phase:

- Assert `rst_n = 0`.
- Release reset.

Expected:

- `current_mbtrain_substate = LOG_NOP`.
- `mbtrain_done = 0`.
- no stale LTSM route request.
- all TB models return to idle.

#### F3: Soft reset sequence during MBTRAIN

Drive `state_n_0 = LOG_RESET` to assert internal soft reset, then `LOG_SBINIT` to release.

Expected:

- Current substate returns to `LOG_NOP`.
- Substate FSMs reset cleanly.

#### F4: Disable MBTRAIN mid-sequence

Drop `mbtrain_en` in each major phase.

Expected:

- Controller returns to idle.
- All substate enables deassert.
- No route request remains stuck.

## 8. Expected State Paths

The scoreboard should not compare raw enum numeric values in prints. It should convert `state_n_e` to readable strings.

Golden state list:

```text
LOG_MBTRAIN_VALVREF
LOG_MBTRAIN_DATAVREF
LOG_MBTRAIN_SPEEDIDLE
LOG_MBTRAIN_TXSELFCAL
LOG_MBTRAIN_RXCLKCAL
LOG_MBTRAIN_VALTRAINCENTER
LOG_MBTRAIN_VALTRAINVREF
LOG_MBTRAIN_DATATRAINCENTER1
LOG_MBTRAIN_DATATRAINVREF
LOG_MBTRAIN_RXDESKEW
LOG_MBTRAIN_DATATRAINCENTER2
LOG_MBTRAIN_LINKSPEED
```

Repair loop inserts:

```text
LOG_MBTRAIN_REPAIR
LOG_MBTRAIN_TXSELFCAL
...
```

Speed degrade loop inserts:

```text
LOG_MBTRAIN_SPEEDIDLE
LOG_MBTRAIN_TXSELFCAL
...
```

RXDESKEW DTC1 loop inserts:

```text
LOG_MBTRAIN_RXDESKEW
LOG_MBTRAIN_DATATRAINCENTER1
LOG_MBTRAIN_DATATRAINVREF
LOG_MBTRAIN_RXDESKEW
```

## 9. Terminal Output Strategy

The terminal must print scenario-level milestones only.

Do not print:

- every clock cycle
- every held state cycle
- every D2C swept code by default
- repeated sideband loopback messages unless verbose mode is enabled

### 9.1 Normal output format

```text
[SCENARIO START] A1_GOLDEN_X16 width=x16 speed=64G clock=continuous
[FLOW] VALVREF -> DATAVREF -> SPEEDIDLE -> TXSELFCAL -> RXCLKCAL -> VALTRAINCENTER -> VALTRAINVREF -> DATATRAINCENTER1 -> DATATRAINVREF -> RXDESKEW -> DATATRAINCENTER2 -> LINKSPEED -> LINKINIT
[CHECK] route=LINKINIT lane_mask_rx=011 lane_mask_tx=011
[RESULT] PASS A1_GOLDEN_X16 cycles=12345
```

### 9.2 Event output examples

Speed degrade:

```text
[SCENARIO START] B1_SINGLE_SPEED_DEGRADE width=x16 speed=64G
[EVENT] LINKSPEED D2C failed active_lanes=ffff pass=0003
[EVENT] LINKSPEED requested SPEED_DEGRADE
[LOOP] Re-entered at SPEEDIDLE, next_speed=48G
[EVENT] LINKSPEED stable
[RESULT] PASS B1_SINGLE_SPEED_DEGRADE
```

Width degrade:

```text
[SCENARIO START] C1_WIDTH_DEGRADE_X16_TO_X8_LOW
[EVENT] LINKSPEED D2C failed active_lanes=ffff pass=00ff
[EVENT] LINKSPEED requested REPAIR
[EVENT] REPAIR degraded width x16 -> x8 lane_mask=001 active_lanes=00ff
[EVENT] LINKSPEED stable
[RESULT] PASS C1_WIDTH_DEGRADE_X16_TO_X8_LOW
```

PHY retrain:

```text
[SCENARIO START] D1_PHY_RETRAIN_PARAMS_CHANGED
[EVENT] LINKSPEED stable with PHY_IN_RETRAIN=1 params_changed=1
[EVENT] LINKSPEED requested PHYRETRAIN
[CHECK] ltsm_phyretrain_req=1
[RESULT] PASS D1_PHY_RETRAIN_PARAMS_CHANGED
```

Trainerror:

```text
[SCENARIO START] E3_REPAIR_DEGRADE_NOT_POSSIBLE
[EVENT] LINKSPEED requested REPAIR
[EVENT] REPAIR reported TRAINERROR
[CHECK] ltsm_trainerror_req=1
[RESULT] PASS E3_REPAIR_DEGRADE_NOT_POSSIBLE
```

Timeout:

```text
[SCENARIO START] E7_TIMEOUT_RXDESKEW_END_RESP_MISSING
[INJECT] Suppress RXDESKEW end response
[TIMEOUT] Waiting for scenario terminal condition in RXDESKEW
[RESULT] PASS E7_TIMEOUT_RXDESKEW_END_RESP_MISSING expected_timeout=1
```

Failure:

```text
[RESULT] FAIL C1_WIDTH_DEGRADE_X16_TO_X8_LOW reason="expected lane_mask_rx=001 got 010"
```

### 9.3 Final summary

At the end:

```text
==================================================
MBTRAIN CLASS-BASED REGRESSION SUMMARY
==================================================
TOTAL SCENARIOS : 42
PASSED          : 42
FAILED          : 0
EXPECTED LIMITS : 0

Normal Success          PASS
Speed Degrade           PASS
Width Degrade/Repair    PASS
PHY Retrain             PASS
RXDESKEW Loops          PASS
Training Failures       PASS
Async Reset/Disable     PASS
Timeout Handling        PASS

COVERAGE SUMMARY
Width bins              3/3
Speed bins              8/8
LINKSPEED routes        5/5
RXDESKEW loop bins      5/5
REPAIR degrade bins     5/5

OVERALL RESULT : PASS
==================================================
```

## 10. Compile and Run Plan

Create `mbtrain_class_based.f` that includes:

1. Package files:
   - `UCIe_pkg.sv`
   - `ltsm_state_n_pkg.sv`
2. New class-based TB packages and interface.
3. RTL files from `target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/MBTRAIN`.
4. D2C files from `target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT`.
5. Existing common TB support only if reused:
   - `common/ltsm_tb_if.sv`
   - `common/ltsm_tb_attachments.sv`
6. `mbtrain_cb_tb_top.sv`.

Important path note:

- The current listfile refers to `rtl/common/UCIe_pkg.sv`.
- In this workspace the readable package is under `UCIe-3.0-PHY-layer/rtl/common/UCIe_pkg.sv`.
- Fix the listfile path or run from the directory where `rtl/common` exists.

Example Questa run shape:

```text
vlib work
vlog -sv -f mbtrain_class_based.f
vsim -c work.mbtrain_cb_tb_top -do "run -all; quit -f"
```

In this workspace, prefer the generated local library used by `run_mbtrain_class_based.do`:

```text
vlib work_mbtrain_cb
vlog -work work_mbtrain_cb -sv -f target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/mbtrain_class_based.f
vsim -c work_mbtrain_cb.mbtrain_cb_tb_top -do "run -all; quit -f"
```

## 11. Implementation Order

1. Create `mbtrain_cb_types_pkg.sv` and `mbtrain_cb_if.sv`.
2. Create top module and confirm `wrapper_MBTRAIN` compiles.
3. Add reset/soft-reset driver and one smoke scenario that reaches `VALVREF`.
4. Add sideband agent with normal response map.
5. Add D2C model with all-pass behavior.
6. Run A1 golden path.
7. Add monitor and scoreboard state-path comparison.
8. Add LINKSPEED route scenarios.
9. Add REPAIR and lane-mask scenarios.
10. Add RXDESKEW high-speed and DTC1-loop scenarios.
11. Add PHY retrain scenarios.
12. Add reset/disable/timeout tests.
13. Add coverage.
14. Add final summary and clean terminal output.

## 12. Done Criteria

The class-based TB is done when:

- It runs a full scenario regression without using the old weak wrapper TB.
- It is self-checking: every scenario ends PASS/FAIL automatically.
- All generated TB files are inside `wrapper_MBTRAIN_class_based_tb/`.
- It verifies all legal MBTRAIN exits and important loops.
- It reports clear, compact terminal milestones.
- It handles current RTL limitations explicitly instead of hiding them.
- It can be extended by adding scenario objects, not by copying large procedural blocks.
