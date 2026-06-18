# MBTRAIN Class-Based TB Simple Task List

This file is a simplified task version of `MBTRAIN_CLASS_BASED_TB_IMPLEMENTATION_PLAN.md`.

Goal: create a self-checking class-based SystemVerilog TB for `wrapper_MBTRAIN`.

All files created by these tasks must stay in this folder:

```text
target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/
```

Do not use the old weak `wrapper_MBTRAIN_tb.sv` as the TB structure.

---

## Phase 1: Create Empty File Structure

Create these files:

```text
mbtrain_cb_types_pkg.sv
mbtrain_cb_if.sv
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
mbtrain_cb_pkg.sv
mbtrain_cb_tb_top.sv
mbtrain_class_based.f
run_mbtrain_class_based.do
```

Each file should compile alone after its dependencies are included.

---

## Phase 2: Build Basic Types

In `mbtrain_cb_types_pkg.sv`, add:

1. Scenario group enum:
   - normal
   - speed degrade
   - width degrade
   - PHY retrain
   - failure
   - async/reset

2. Expected exit enum:
   - LINKINIT
   - SPEEDIDLE loop
   - REPAIR loop
   - PHYRETRAIN
   - TRAINERROR
   - TIMEOUT
   - IDLE

3. Width enum:
   - x16
   - x8
   - x4

4. Speed enum using RTL encoding:
   - `3'b000` = 4 GT/s
   - `3'b001` = 8 GT/s
   - `3'b010` = 12 GT/s
   - `3'b011` = 16 GT/s
   - `3'b100` = 24 GT/s
   - `3'b101` = 32 GT/s
   - `3'b110` = 48 GT/s
   - `3'b111` = 64 GT/s

5. Scenario struct with:
   - name
   - width
   - speed
   - expected exit
   - expected state path queue
   - D2C pass mask
   - `PHY_IN_RETRAIN`
   - `params_changed`
   - expected lane masks
   - timeout expected flag

---

## Phase 3: Build Testbench Interface

In `mbtrain_cb_if.sv`, create an interface that contains all `wrapper_MBTRAIN` ports.

Must include tasks:

1. `drive_reset()`
2. `release_soft_reset_sequence()`
3. `start_mbtrain()`
4. `stop_mbtrain()`
5. `send_rx_msg(msg, info, data)`
6. `clear_rx_msg()`
7. `drive_d2c_result(perlane_pass)`
8. `wait_lclk(cycles)`

Important:

- Import `UCIe_pkg::*`.
- Import `ltsm_state_n_pkg::*`.
- To release internal `soft_rst_n`, drive:
  - `state_n_0 = LOG_RESET`
  - then `state_n_0 = LOG_SBINIT`

---

## Phase 4: Build Top Module

In `mbtrain_cb_tb_top.sv`:

1. Generate `lclk`.
2. Instantiate `mbtrain_cb_if`.
3. Instantiate `wrapper_MBTRAIN`.
4. Connect every DUT port to the interface.
5. Import the TB package.
6. Create one environment object.
7. Call `env.run()`.

First target: compile the top with no tests.

---

## Phase 5: Build Compile List

In `mbtrain_class_based.f`, include files in this order:

1. `UCIe_pkg.sv`
2. `ltsm_state_n_pkg.sv`
3. New TB type/interface/package files.
4. New RTL MBTRAIN files.
5. New RTL D2C files.
6. `mbtrain_cb_tb_top.sv`

Important path note:

The packages may be found here in this workspace:

```text
UCIe-3.0-PHY-layer/rtl/common/UCIe_pkg.sv
UCIe-3.0-PHY-layer/rtl/MainSM/LTSM/common/ltsm_state_n_pkg.sv
```

Do not accidentally use old RTL MBTRAIN files from `UCIe-3.0-PHY-layer/rtl/MainSM/LTSM/MBTRAIN`.

Use the new RTL here:

```text
target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/MBTRAIN/
```

---

## Phase 6: Build Config and Transaction Classes

In `mbtrain_cb_config.sv`, create a class with:

- sideband delay
- watchdog cycles
- analog settle cycles
- default lane masks
- default D2C pass mask
- verbose enable
- stop-on-first-fail enable

In `mbtrain_cb_transaction.sv`, create a class for sideband events:

- time
- message
- msginfo
- data
- direction
- current substate
- scenario name

---

## Phase 7: Build Sideband Agent

In `mbtrain_cb_sb_agent.sv`, create a class that:

1. Watches DUT TX sideband:
   - `substate_tx_sb_msg_valid`
   - `substate_tx_sb_msg`
   - `substate_tx_msginfo`
   - `substate_tx_data_field`

2. Sends the correct RX response after a delay.

Normal response mapping:

```text
*_start_req -> *_start_resp
*_end_req   -> *_end_resp
*_done_req  -> *_done_resp
LINKSPEED_error_req -> LINKSPEED_error_resp
LINKSPEED_exit_to_repair_req -> LINKSPEED_exit_to_repair_resp
LINKSPEED_exit_to_speed_degrade_req -> LINKSPEED_exit_to_speed_degrade_resp
LINKSPEED_exit_to_phy_retrain_req -> LINKSPEED_exit_to_phy_retrain_resp
REPAIR_init_req -> REPAIR_init_resp
REPAIR_apply_degrade_req -> REPAIR_apply_degrade_resp
REPAIR_end_req -> REPAIR_end_resp
RXDESKEW_exit_to_DATATRAINCENTER1_req -> RXDESKEW_exit_to_DATATRAINCENTER1_resp
```

Special rule:

The opcode for LINKSPEED PHYRETRAIN and RXDESKEW EQ preset is shared. Decode it using `current_mbtrain_substate`.

---

## Phase 8: Build D2C Model

In `mbtrain_cb_d2c_model.sv`, create a class that:

1. Watches:
   - `local_sweep_en`
   - `partner_sweep_en`

2. Drives:
   - `sweep_done`
   - `sweep_swept_code`
   - `sweep_best_code[0:15]`
   - `sweep_min_eye_width`
   - `d2c_perlane_pass`

Default all-pass:

```text
d2c_perlane_pass = sweep_active_lanes
```

Remember:

```text
*_pass = 1 means pass
*_pass = 0 means fail
```

---

## Phase 9: Build Monitor

In `mbtrain_cb_monitor.sv`, collect:

1. State changes from `current_mbtrain_substate`.
2. Sideband TX/RX events.
3. LINKSPEED route outputs:
   - `ltsm_linkinit_req`
   - `ltsm_phyretrain_req`
   - `ltsm_trainerror_req`
4. Lane mask changes.
5. D2C sweep start and done.

Do not print every cycle.

Only print:

- scenario start
- important events
- scenario result
- final summary

---

## Phase 10: Build Scoreboard

In `mbtrain_cb_scoreboard.sv`, check:

1. Expected state path.
2. Expected final exit.
3. Expected lane mask after REPAIR.
4. No unexpected TRAINERROR.
5. No timeout unless timeout is expected.
6. `mbtrain_done` occurs only at terminal.
7. `PHY_IN_RETRAIN_rst` and `busy_bit_rst` pulse only in expected cases.

Terminal checks:

```text
LINKINIT:    mbtrain_done && ltsm_linkinit_req
PHYRETRAIN:  mbtrain_done && ltsm_phyretrain_req
TRAINERROR:  mbtrain_done && ltsm_trainerror_req
TIMEOUT:     watchdog fires and scenario expects timeout
IDLE:        current_mbtrain_substate == LOG_NOP
```

---

## Phase 11: Build Driver

In `mbtrain_cb_driver.sv`, create task `run_scenario(scenario)`:

1. Reset DUT.
2. Release soft reset.
3. Configure width and speed.
4. Configure retrain flags.
5. Configure D2C model result.
6. Start MBTRAIN.
7. Wait for scoreboard terminal condition.
8. Stop MBTRAIN.
9. Clean up before next scenario.

---

## Phase 12: Build Environment

In `mbtrain_cb_env.sv`:

1. Create config.
2. Create driver.
3. Create sideband agent.
4. Create D2C model.
5. Create monitor.
6. Create scoreboard.
7. Create coverage.
8. Start background components.
9. Run all scenarios from test library.
10. Print final summary.

---

## Phase 13: Build First Smoke Test

Create one scenario only:

```text
A1_GOLDEN_X16
```

Expected path:

```text
VALVREF -> DATAVREF -> SPEEDIDLE -> TXSELFCAL -> RXCLKCAL ->
VALTRAINCENTER -> VALTRAINVREF -> DATATRAINCENTER1 ->
DATATRAINVREF -> RXDESKEW -> DATATRAINCENTER2 -> LINKSPEED ->
LINKINIT
```

Expected result:

```text
PASS
```

Do not add more scenarios until A1 passes.

---

## Phase 14: Add Main Scenario Groups

After A1 passes, add these one by one:

1. Golden x8.
2. Golden high-speed RXDESKEW EQ path.
3. Single speed degrade then success.
4. Multiple speed degrade then success.
5. Lowest speed fail -> TRAINERROR.
6. Width degrade x16 -> x8 low.
7. Width degrade x16 -> x8 high.
8. Width degrade x8 -> x4 low.
9. Width degrade x8 -> x4 high.
10. Width degrade exhausted -> TRAINERROR.
11. PHY retrain params changed -> PHYRETRAIN.
12. PHY retrain no params changed -> LINKINIT.
13. RXDESKEW DTC1 loop.
14. RXDESKEW DTC1 loop overflow -> TRAINERROR.
15. REPAIR degrade not possible -> TRAINERROR.
16. Disable MBTRAIN mid-sequence -> IDLE.
17. Hard reset mid-sequence -> IDLE.
18. Soft reset mid-sequence -> IDLE.
19. Missing sideband response -> expected TIMEOUT.

---

## Phase 15: Add Coverage

In `mbtrain_cb_coverage.sv`, add coverage for:

1. Width: x16, x8, x4.
2. Speed: all 8 speed encodings.
3. LINKSPEED route:
   - LINKINIT
   - SPEEDIDLE
   - REPAIR
   - PHYRETRAIN
   - TRAINERROR
4. RXDESKEW loop count:
   - 0
   - 1
   - 2
   - 3
   - 4
   - overflow
5. REPAIR result:
   - x16 -> x8 low
   - x16 -> x8 high
   - x8 -> x4 low
   - x8 -> x4 high
   - not possible

---

## Phase 16: Terminal Output Rules

Print this style:

```text
[SCENARIO START] A1_GOLDEN_X16 width=x16 speed=64G
[FLOW] VALVREF -> DATAVREF -> ... -> LINKSPEED -> LINKINIT
[CHECK] route=LINKINIT lane_mask_rx=011 lane_mask_tx=011
[RESULT] PASS A1_GOLDEN_X16
```

For events:

```text
[EVENT] LINKSPEED requested SPEED_DEGRADE
[EVENT] REPAIR degraded width x16 -> x8 lane_mask=001
[EVENT] LINKSPEED requested PHYRETRAIN
[EVENT] REPAIR reported TRAINERROR
[TIMEOUT] Waiting for RXDESKEW end response
```

Final summary:

```text
==================================================
MBTRAIN CLASS-BASED REGRESSION SUMMARY
==================================================
TOTAL SCENARIOS : XX
PASSED          : XX
FAILED          : XX
EXPECTED LIMITS : XX

OVERALL RESULT : PASS
==================================================
```

Do not print huge repeated logs.

---

## Phase 17: Important RTL Limitations

Current `wrapper_MBTRAIN.sv` ties many early substate trainerror signals to `0`.

So do not expect real `ltsm_trainerror_req` for every early substate failure.

For early states, missing response should usually be a TB timeout unless RTL later adds timeout-to-TRAINERROR.

Real TRAINERROR checks should focus first on:

1. RXDESKEW.
2. REPAIR.
3. Invalid LINKSPEED route.

---

## Phase 18: Done Criteria

The task is complete when:

1. The class-based TB compiles.
2. A1 golden path passes.
3. Main scenario groups pass.
4. Scoreboard catches wrong path or wrong exit.
5. Terminal output is compact and readable.
6. All new TB files are in this folder.
7. No old weak TB code structure is copied.

