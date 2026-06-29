# RDI SM — Raw Die-to-Die Interface State Machine (UCIe 3.0)

The **RDI SM** implements the PHY side of the **RDI** (the interface between the
UCIe **adapter** and the **PHY**). It runs the RDI power/link state protocol,
performs the clock / wake / stall / active handshakes with the adapter, gates the
Main-Band clock for power management, and exchanges link-management messages over
the Sideband. While the LTSM owns *training*, the RDI SM owns the *run-time
power-state and flow-control contract* with the adapter (per UCIe Table 10-4).

Top module: **`RDI_SM/RDI_SM.sv`**. It is built from a state wrapper
(`wrapper_sm/wrapper_sm.sv`), a handshake-logic wrapper
(`wrapper_handshake_logic/`), plus gating, transition-detect, status-decode and
message-handler units.

> **Design rule:** when an RDI_SM testbench exposes a mismatch with the spec,
> fix the RTL to match UCIe Table 10-4 — not the test.

---

## RDI states (`RDI_state`)

| State | Meaning |
|-------|---------|
| **Reset** | Initial / link-down state. |
| **Active** | Normal operation; traffic allowed. |
| **Active_PMNAK** | Active, but a power-management request was NAK'd. |
| **L_1** | Power-management L1 (clock-gated standby). |
| **L_2** | Power-management L2 (deeper power-down). |
| **LinkReset** | Link reset in progress. |
| **LinkError** | Link error state. |
| **Retrain** | Retraining requested. |
| **Disabled** | Link disabled. |
| **Nop** | No-operation sentinel. |

`pl_state_sts` is the (lagging) RDI state reported on the output interface, while
`rdi_state` mirrors the internal `wrapper_sm` state forwarded to the LTSM.

---

## Sub-blocks

| Unit | File | Function |
|------|------|----------|
| State machine | `wrapper_sm/wrapper_sm.sv` + `unit_main_controller/` | Core RDI state sequencing and per-state logic (`unit_reset_state`, `unit_active_state`, `unit_active_pmnak_state`, `unit_retrain_state`, `unit_L1_state`, `unit_L2_state`, `unit_linkreset_state`, `unit_linkerror_state`, `unit_disabled_state`). |
| Handshake logic | `wrapper_handshake_logic/` | Adapter handshakes: `unit_clk_handshake` (clk_req/clk_ack), `unit_awak_handshake` (wake_req/wake_ack), `unit_stall_handshake` (stallreq/stallack), `unit_active_handshake`. |
| Clock gating | `unit_gating_logic/` | Drives `lclk_g` (MB TX clock-gate enable): UNGATING ⇒ 1, GATING ⇒ 0. Keeps the MB clock on through the RESET→SBINIT training-start window. |
| Transition detect | `unit_signal_transition_detector/` | Edge detection on control signals. |
| Status decode | `unit_status_decoder/` | Decodes link capability/status fields from the Reg_File / sideband. |
| Message handling | `unit_msg_handler/`, `unit_message_send_MUX/`, `message_timeout_handler/` | Link-management message RX/TX over the sideband, with an 8 ms message-handshake timeout (`sb_msg_timeout`). |
| Timer | `unit_Timer/` | Generic timer used by the handshakes/timeouts. |

---

## Features supported

- **Full RDI power/link state protocol** (Reset / Active / PMNAK / L1 / L2 /
  LinkReset / LinkError / Retrain / Disabled) per UCIe Table 10-4.
- **Adapter handshakes**: clock request/ack, wake request/ack, stall request/ack,
  and the active handshake — including the role-asymmetric **L1 entry** path.
- **Main-Band clock gating** for power management, with a `phy_start`-driven
  ungate so the MB clock stays on during reset-start.
- **Sideband link-management messaging** with an **8 ms handshake timeout**.
- **Stall handshake** with a latched `stall_done` for the RDI stall flow.
- **Link capability/speed/width** reporting to the adapter
  (`pl_max_speedmode`, `pl_speedmode`, `pl_lnk_cfg`).

---

## Key interfaces (`RDI_SM`)

| Group | Signals |
|-------|---------|
| Adapter | `lp_clk_ack`, `lp_wake_req`, `lp_stallack`, `lp_state_req`, `lp_linkerror`; `pl_clk_req`, `pl_stallreq`, `pl_wake_ack`, `pl_trainerror`, `pl_inband_pres`, `pl_phyinrecenter`, `pl_state_sts`, `pl_max_speedmode`, `pl_speedmode`, `pl_lnk_cfg` |
| Sideband | `Link_Mgmt_Msg_Receive/Send`, `valid_r/valid_s`, `sb_msg_timeout`, `traffic_req`, `clk_handshake_done`; link-capability/status taps |
| Main-Band | `lclk_g`, `stall_done`, `stall_done_latched`, `mapper_en`, `pl_error` |
| LTSM | `state_sts`, `phy_start_ucie_link_training_ctrl_out`, `sticky_sb_pattern_detected`, `rdi_state` (out) |

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `MSG_TIMEOUT_CYCLES` | 16,000,000 | Sideband message-handshake timeout (8 ms @ 2 GHz). |

---

## Simulation

| CONFIG | What it exercises |
|--------|-------------------|
| `RDI_SM` | Top-level RDI SM TB (with checker). |
| `unit_*` | Per-unit TBs (handshakes, states, gating, msg_handler, Timer, …). |
| `Logical_PHY` | RDI + MB + SB + LTSM integration wrapper. |

RDI_SM testbenches live under `tb/unit/MainSM/RDI_SM/` and `tb/integration/RDI_SM/`.
