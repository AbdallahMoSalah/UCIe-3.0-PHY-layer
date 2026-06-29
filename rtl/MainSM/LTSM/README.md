# LTSM — Link Training State Machine (UCIe 3.0)

The **LTSM** is the master bring-up controller of the UCIe PHY. It walks the link
through the full UCIe training sequence — from cold reset, through sideband init,
main-band init and main-band training, to the operational **ACTIVE** state — and
handles the low-power (L1/L2), retrain, and error paths afterwards. It drives the
Main-Band and Sideband blocks via enables/config, consumes their done/status
flags, and exposes its state and logs to the Reg_File and the RDI SM.

Top module: **`LTSM_wrapper.sv`** (instantiated under `LTSM_TOP.sv` together with
the `mainband_ltsm_interface`). The core sequencing FSM is
`unit_ltsm_controller.sv`; a shared **8 ms watchdog** (`Common/timeout_counter.sv`)
backs every state's timeout.

---

## Top-level states (`LTSM_state_e`)

| Code | State | Purpose |
|------|-------|---------|
| 0 | **RESET** | Power-on dwell (≈4 ms) + wait for a training trigger; exits when both are satisfied. |
| 1 | **SBINIT** | Sideband initialization — exchange/detect SB patterns, establish the control channel. |
| 2 | **MBINIT** | Main-band initialization — clock repair, parameter exchange, calibration, reversal/valid/MB repair. |
| 3 | **MBTRAIN** | Main-band training — the 13-substate data/valid/clock training and speed/width negotiation. |
| 4 | **LINKINIT** | Final link initialization handshake before traffic. |
| 5 | **ACTIVE** | Operational; normal data traffic flows on the Main-Band. |
| 6 | **PHYRETRAIN** | Re-run training without a full cold reset. |
| 7 | **TRAINERROR** | Training-failure handling with the §4.5.3.8 entry handshake (both roles, collision-safe). |
| 8 | **L1** | Low-power standby. |
| 9 | **L2** | Deeper low-power / power-down. |
| 10 | NO_OP | Idle/no-operation sentinel. |

```
RESET ─▶ SBINIT ─▶ MBINIT ─▶ MBTRAIN ─▶ LINKINIT ─▶ ACTIVE
                                                      │  ▲
                                              L1/L2 ◀─┘  └─▶ PHYRETRAIN / TRAINERROR
```

---

## Directory map

| Path | Contents |
|------|----------|
| `unit_ltsm_controller.sv` | The main sequencing FSM (enables, status, 8 ms timer control). |
| `LTSM_wrapper.sv` / `LTSM_TOP.sv` | Integration top: controller + state blocks + SB/MB output muxes. |
| `RESET.sv`, `SBINIT.sv`, `LINKINIT/`, `ACTIVE.sv`, `L1.sv`, `L2.sv`, `TRAINERROR.sv`, `PHYRETRAIN.sv` | Top-level state blocks. |
| `trainerror_handshake.sv` | §4.5.3.8 TRAINERROR entry handshake (role-symmetric, Option-A collision handling, timeout-triggered). |
| `MBINIT/` | MBINIT controller + substates: `MBINIT_PARAM`, `MBINIT_CAL`, `MBINIT_REPAIRCLK`, `MBINIT_REPAIRVAL`, `MBINIT_REVERSALMB`, `MBINIT_REPAIRMB`. |
| `MBTRAIN/` | MBTRAIN controller + 13 substate wrappers (see below) + `wrapper_MBTRAIN.sv`. |
| `D2C/` | Die-to-Continuity point-test blocks (TX/RX local & partner) used by MBINIT.REPAIRMB; lane sweep + lane select. |
| `Common/` | Shared `timeout_counter`, pulse generators (`unit_pulse_gen_tx/rx`), `unit_analog_settle_timer`, `internal_ltsm_if`. |

### MBTRAIN substates (`MBTRAIN/`)
`VALVREF → DATAVREF → SPEEDIDLE → TXSELFCAL → RXCLKCAL → VALTRAINCENTER →
VALTRAINVREF → DATATRAINCENTER1 → DATATRAINVREF → RXDESKEW → DATATRAINCENTER2 →
LINKSPEED → REPAIR`

Each substate is a `wrapper_*` with `*_local`/`*_partner` halves driven through the
`internal_ltsm_if` modport. Detailed per-substate docs are in
`MBTRAIN/details_of_MBTRAIN/` and `MBTRAIN/MBTRAIN_overview.md`.

---

## Features supported

- **Full UCIe bring-up sequence** RESET→…→ACTIVE with a shared 8 ms watchdog per state.
- **Both link roles** (local / partner) with collision-safe handshakes
  (TRAINERROR entry, D2C point test).
- **MBINIT** clock repair, parameter exchange, calibration, lane reversal,
  valid repair, and MB repair (via the D2C point test).
- **MBTRAIN** 13-substate data/valid/clock training, including
  **LINKSPEED** speed degrade and **REPAIR** width degrade/lane repair.
- **Low-power entry/exit** (L1/L2) and **PHYRETRAIN** without cold reset.
- **State & error logging**: shift-register history of the last states
  (`log0_state_n` … `log1_state_n_minus_3`) plus lane-reversal / width-degrade flags,
  fed to the Reg_File Error Log registers.
- **Reg_File-driven control**: target width/speed, start/retrain triggers, PMO/PSPT/L2SPD.

---

## Key interfaces (`LTSM_wrapper`)

| Group | Signals |
|-------|---------|
| Clock/reset | `clk`, `rst_n` |
| Observability | `current_ltsm_state`, `link_training_retraining`, `link_status`, `timeout_8ms_occured`, `busy_flag`, `RESET_state_done` |
| State logs | `log0_state_n`, `log0_lane_reversal`, `log0_width_degrade`, `log0_state_n_minus_1/2`, `log1_state_n_minus_3` |
| Triggers | `phy_start_ucie_link_training_ctrl_out`, `sb_det_pattern_rcvd`, `sb_det_pattern_rcvd_sticky`, `SPMW` |
| Capability/config (→ MBINIT) | `start_bit`, `reg_phy_x8_mode_ctrl`, `reg_TARR_support_local_cap`, target width/speed, … |

---

## Simulation

| CONFIG | What it exercises |
|--------|-------------------|
| `unit_ltsm_ctrl` | The controller FSM in isolation. |
| `unit_ltsm_wrapper` | The integration wrapper. |
| `integration_LTSM_SideBand` / `integration_ltsm_sideband_die2die` | LTSM driving the real sideband. |
| `MB_SB_LTSM_tb` | Full MB + SB + LTSM integration (7-scenario TB). |

LTSM testbenches live under `tb/unit/MainSM/LTSM/` and `tb/wrapper/MainSM/LTSM/`.
