### RDI_SM Verification Plan

---

#### 1. Testbench Architecture

**DUT:** `RDI_SM` (top-level wrapper — full integration, not unit-level)

**Testbench components:**

|Component|Role|
|---|---|
|`clk_gen`|Drives `lclk` at parameterized frequency (default 2GHz)|
|`adapter_driver`|Drives `lp_state_req`, `lp_linkerror`, `lp_stallack`, `lp_clk_ack`, `lp_wake_req`|
|`ltsm_model`|Drives `state_sts`, `pl_error` with programmable LTSM state sequences|
|`peer_msg_driver`|Drives `Link_Mgmt_Msg_Receive` + `valid_r` to simulate remote partner sideband responses|
|`sb_responder`|Auto-responds to `valid_s` / `Link_Mgmt_Msg_Send` to complete message handshakes|
|`dvsec_driver`|Drives `UCIe_Link_DVSEC_*` inputs for status decoder coverage|
|`output_monitor`|Samples all DUT outputs, logs to scoreboard|
|`scoreboard`|Compares observed `pl_state_sts` transitions and messages against expected sequences|
|`checker_pkg`|SVA assertions bound to DUT|

**Clock and reset:** Assert `rst_n` for minimum 5 cycles at start. All tests begin from post-reset state.

**Peer message model:** The `peer_msg_driver` must implement the symmetric RDI peer — when DUT sends a REQ, the peer responds with the matching RSP after a programmable delay (1–10 cycles). Controllable to inject no-response (timeout) scenarios.

---

#### 2. Test Groups

---

##### TG-01: Reset and Initialization

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-01.1|Assert `rst_n` for 5 cycles then deassert|All outputs at reset values; `pl_state_sts == Reset`; `pl_inband_pres == 0`; `pl_stallreq == 0`; `pl_clk_req == 0`|
|TC-01.2|Deassert `rst_n` mid-operation from Active state|DUT returns to Reset; all sub-SM `EN` signals deasserted; `pl_state_sts` transitions to Reset after clk handshake|
|TC-01.3|Apply reset with `lp_state_req` driven to non-NOP value|Post-reset `pl_state_sts == Reset` regardless of `lp_state_req` value|

---

##### TG-02: Reset → Active (Link Bring-Up)

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-02.1|`state_sts = LINKINIT` → `lp_state_req = NOP` → `lp_state_req = Active` → peer responds with `RDI_ACTIVE_RSP`|`pl_state_sts` transitions Reset → Active; `pl_inband_pres` asserts before transition; `Active_handshake_strt` pulses; `pl_state_sts` only updates after `clk_handshake_done`|
|TC-02.2|Same as TC-02.1 but peer sends `RDI_ACTIVE_REQ` first (overlap/FLOW_1)|Active handshake completes via FLOW_1 path; `pl_state_sts == Active`|
|TC-02.3|`lp_state_req = Active` asserted before `state_sts = LINKINIT`|DUT stays in Reset training sub-state; waits for LINKINIT before initiating Active handshake|
|TC-02.4|Active handshake started; peer sends `RDI_ACTIVE_REQ` and `RDI_ACTIVE_RSP` simultaneously (FLOW_2)|Active handshake completes via FLOW_2; `pl_state_sts == Active`|

---

##### TG-03: Active State — Retrain Flows

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-03.1|`lp_state_req = Retrain` while Active|`pl_stallreq` asserts; after `lp_stallack`, sends `RDI_RETRAIN_REQ`; peer responds `RDI_RETRAIN_RSP`; `pl_state_sts == Retrain`|
|TC-03.2|`pl_error` pulse while Active|Same Retrain flow as TC-03.1 triggered internally|
|TC-03.3|`state_sts == PHYRETRAIN` while Active|Same Retrain flow triggered from LTSM|
|TC-03.4|Peer sends `RDI_RETRAIN_REQ` while Active|DUT stalls, sends `RDI_RETRAIN_RSP`, transitions to Retrain|
|TC-03.5|Retrain → Active: entered from Active (`pm_exit == 0`)|DUT waits for NOP→Active transition on `lp_state_req` before starting Active handshake|
|TC-03.6|Retrain → Active: entered from L1 (`pm_exit == 1`)|DUT starts Active handshake immediately on `lp_state_req == Active` without waiting for NOP first|

---

##### TG-04: Active State — PM Entry (L1/L2)

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-04.1|`lp_state_req = L1` while Active|Stall completes; sends `RDI_L1_REQ`; peer responds `RDI_L1_RSP`; `pl_state_sts == L1`|
|TC-04.2|`lp_state_req = L2` while Active|Same as TC-04.1 with L2 messages; `pl_state_sts == L2`|
|TC-04.3|Peer sends `RDI_L1_REQ` while Active|DUT stalls, sends `RDI_L1_RSP`, transitions to L1|
|TC-04.4|DUT sends L1 REQ; peer responds with `RDI_PMNAK_RSP`|`pl_state_sts == Active.PMNAK`; 1µs timer starts; after timer expires and `lp_state_req == Active`, transitions back to Active|
|TC-04.5|DUT in Active; peer sends PM REQ; `lp_state_req` stays Active for > 1µs|DUT sends `RDI_PMNAK_RSP` within 1µs; `pl_state_sts == Active.PMNAK`|
|TC-04.6|PM abort: `lp_state_req` changes to Active after L1 REQ sent but before RSP received|Verify PM abort flow; `pl_state_sts` returns to Active|

---

##### TG-05: L1/L2 State — Exit and Error Flows

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-05.1|`lp_state_req = Active` while in L1|L1 sub-SM triggers Active handshake (pm_exit path); `pl_state_sts` → Retrain → Active|
|TC-05.2|`lp_state_req = Active` while in L2|L2 exit → Reset state; NOP→Active on `lp_state_req` required; `pl_state_sts` → Reset → Active|
|TC-05.3|`lp_linkerror` asserted while in L1|Sends `RDI_LINK_ERROR_REQ`; peer responds; `pl_state_sts == LinkError`|
|TC-05.4|Peer sends `RDI_LINK_RESET_REQ` while in L1|DUT sends `RDI_LINK_RESET_RSP`; `pl_state_sts == LinkReset`|
|TC-05.5|`lp_state_req = Disabled` while in L1|Sends `RDI_DISABLE_REQ`; peer responds; `pl_state_sts == Disabled`|
|TC-05.6|Peer sends `RDI_DISABLE_REQ` while in L2|DUT sends `RDI_DISABLE_RSP`; `pl_state_sts == Disabled`|

---

##### TG-06: LinkReset State

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-06.1|`lp_state_req = LinkReset` from Active|Stall → `RDI_LINK_RESET_REQ` → peer RSP → `pl_state_sts == LinkReset`|
|TC-06.2|`lp_state_req = Active` while in LinkReset|Transitions to Reset; `pl_state_sts == Reset`|
|TC-06.3|`lp_state_req = Disabled` while in LinkReset|Sends `RDI_DISABLE_REQ`; `pl_state_sts == Disabled`|
|TC-06.4|`lp_linkerror` asserted while in LinkReset|`pl_state_sts == LinkError`|
|TC-06.5|Peer sends `RDI_LINK_RESET_REQ` while Active|DUT sends RSP; `pl_state_sts == LinkReset`|

---

##### TG-07: LinkError State

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-07.1|`lp_linkerror` asserted while Active|Sends `RDI_LINK_ERROR_REQ`; peer responds; `pl_state_sts == LinkError`; `pl_trainerror` asserts|
|TC-07.2|Peer sends `RDI_LINK_ERROR_REQ` while Active|DUT sends `RDI_LINK_ERROR_RSP`; `pl_state_sts == LinkError`|
|TC-07.3|`lp_linkerror` asserted while in Reset state|Direct transition to LinkError|
|TC-07.4|`lp_linkerror` asserted in Retrain, L1, L2, LinkReset|Verify LinkError transition is reachable from all these states|
|TC-07.5|`lp_state_req = Active` + `lp_linkerror = 0` after 16ms in LinkError|`pl_state_sts` transitions to Reset (minimum residency enforced)|
|TC-07.6|`lp_state_req = Active` before 16ms in LinkError|DUT must NOT exit LinkError; remains in LinkError|

---

##### TG-08: Disabled State

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-08.1|`lp_state_req = Disabled` from Active|`pl_state_sts == Disabled` after REQ/RSP exchange|
|TC-08.2|`lp_state_req = Active` from Disabled|Transitions to Reset|
|TC-08.3|`lp_linkerror` asserted while Disabled|`pl_state_sts == LinkError`|
|TC-08.4|Peer sends `RDI_DISABLE_REQ` while in Retrain|DUT sends RSP; `pl_state_sts == Disabled`|

---

##### TG-09: Handshake Sub-modules

**Stall Handshake:**

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-09.1|`stall_req` asserts from SM; `lp_stallack` responds 1 cycle later|`pl_stallreq` asserts; `stall_done` asserts 1 cycle after `lp_stallack`|
|TC-09.2|`lp_stallack` delayed by 10 cycles|`pl_stallreq` remains asserted until `lp_stallack`; `stall_done` asserts correctly|
|TC-09.3|`stall_req` de-asserts before `lp_stallack`|`pl_stallreq` de-asserts; `stall_done` does not assert|

**CLK Handshake:**

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-09.4|`signal_transition` asserts; `lp_clk_ack` responds|`pl_clk_req` asserts; `clk_handshake_done` asserts on `lp_clk_ack`; `pl_state_sts` updated only after `clk_handshake_done`|
|TC-09.5|`traffic_req` asserts|`clk_handshake_strt` asserts via OR path; same clk handshake sequence|
|TC-09.6|Both `signal_transition` and `traffic_req` assert simultaneously|Single clk handshake executes; no double-trigger|

**AWAKE Handshake:**

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-09.7|`lp_wake_req` asserts|`ungating_req` asserts; after `ungating_done`, `pl_wake_ack` asserts|
|TC-09.8|`lp_wake_req` de-asserts after `pl_wake_ack`|`pl_wake_ack` de-asserts; returns to IDLE|

**Active Handshake (FLOW_0 / FLOW_1 / FLOW_2):**

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-09.9|`Active_handshake_strt`; peer sends RSP then REQ (FLOW_0)|`Active_handshake_done` asserts after both sent and received|
|TC-09.10|Peer sends REQ first, then `Active_handshake_strt` (FLOW_1)|FLOW_1 path: DUT sends RSP then REQ; done asserts|
|TC-09.11|REQ/RSP arrive simultaneously (FLOW_2)|FLOW_2 path completes correctly|

---

##### TG-10: Clock Gating Logic

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-10.1|`pl_state_sts ∈ {Reset, LinkReset, Disabled, L1, L2}` + all gating conditions met for >1µs|`lclk_g` gates to 0; `ungating_done == 0`|
|TC-10.2|`pl_state_sts == Active`|Gating conditions never met; `lclk_g == lclk` always|
|TC-10.3|During gating, `ungating_req` asserts|`lclk_g` immediately ungates|
|TC-10.4|During gating, `pl_clk_req` asserts|`lclk_g` immediately ungates|
|TC-10.5|During gating, `phyinrecenter` asserts|`lclk_g` immediately ungates|
|TC-10.6|All gating conditions met but 1µs not elapsed|Gating does NOT occur|
|TC-10.7|`inband_pres` asserts during gating eligibility|Gating inhibited|

---

##### TG-11: Message Handler

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-11.1|`Message_send != NOP` from SM|`valid_s` asserts; `Link_Mgmt_Msg_Send` driven correctly|
|TC-11.2|`valid_r` asserts while SM idle|`Message_receive` driven; processed by sub-SM|
|TC-11.3|`valid_r` asserts simultaneously with `Message_send != NOP`|`Message_send` takes priority; `valid_r` captured into `pending_rx_msg`; processed after TX completes|
|TC-11.4|`Active_message_send != NOP` while idle|Active handshake message forwarded to SB|
|TC-11.5|`valid_r` asserts while in `LnkMsgS`|Captured in `pending_rx_valid`; processed on return to IDLE|
|TC-11.6|Second `valid_r` arrives before first is consumed|Second message overwrites pending — document as known limitation|

---

##### TG-12: Signal Transition Detector

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-12.1|`rdi_state_sts` changes value|`signal_transition` asserts; `pl_state_sts` does NOT update until `clk_handshake_done`|
|TC-12.2|`phyinrecenter` toggles|`signal_transition` asserts; `pl_phyinrecenter` updates after handshake|
|TC-12.3|`inband_pres` toggles|`signal_transition` asserts; `pl_inband_pres` updates after handshake|
|TC-12.4|`trainerror` asserts|`signal_transition` asserts; `pl_trainerror` updates after handshake; since it is a level signal, it remains asserted — verify it is not de-asserted prematurely|
|TC-12.5|Multiple signals change simultaneously|Single `signal_transition` pulse; all values captured together on one `clk_handshake_done`|
|TC-12.6|Signal changes again while clk handshake is in progress|`signal_transition` stays asserted; new value captured on next `clk_handshake_done`|

---

##### TG-13: Status Decoder

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-13.1|All valid DVSEC link capability/status encodings|`pl_speedmode`, `pl_max_speedmode`, `pl_lnk_cfg` match expected decoded values|
|TC-13.2|Reserved DVSEC encodings|Verify no X-propagation; outputs default safely|

---

##### TG-14: Timer

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-14.1|`start_time_1us` held high|`time_1us` asserts after exactly 1µs (± 1 cycle tolerance)|
|TC-14.2|`start_time_16ms` held high|`time_16ms` asserts after exactly 16ms|
|TC-14.3|`start_time_1us` de-asserted before expiry|Counter resets; `time_1us` never asserts|
|TC-14.4|`start_time_1us` re-asserted after de-assert|Counter restarts from initial value|

---

##### TG-15: Error / Corner Cases

|TC|Stimulus|Expected Outcome|
|---|---|---|
|TC-15.1|`lp_linkerror` asserted and held across multiple state transitions|DUT always transitions to LinkError regardless of current state (except if already in LinkError)|
|TC-15.2|Peer sends no RSP to any REQ (timeout scenario)|Verify DUT does not hang; after 8ms (if implemented) → LinkError|
|TC-15.3|`lp_state_req` changes rapidly between valid values|DUT follows last stable value; no illegal state entered|
|TC-15.4|Both `lp_linkerror` and `lp_state_req = Retrain` simultaneously|LinkError takes precedence|
|TC-15.5|`pl_error` pulse while `pl_state_sts != Active`|No Retrain triggered; `pl_error` ignored in non-Active states|
|TC-15.6|`rst_n` pulsed for only 1 cycle|Verify reset still takes effect; no partial reset|

---

#### 3. Assertions (SVA Checkers)

|Assertion|Description|
|---|---|
|`A01`|`pl_state_sts` must never change without a completed `clk_handshake_done` preceding it|
|`A02`|`pl_stallreq` must assert before any PM/Retrain/LinkReset/Disable sideband message is sent by DUT|
|`A03`|`pl_state_sts == LinkError` must be maintained as long as `lp_linkerror == 1`|
|`A04`|`pl_inband_pres` must stay asserted in Active, Retrain, PMNAK, L1, L2; must de-assert in Reset, LinkReset, Disabled, LinkError|
|`A05`|`Active_handshake_done` must be a pulse (asserts for exactly 1 cycle)|
|`A06`|`stall_done` must not assert unless `pl_stallreq` was previously asserted|
|`A07`|`clk_handshake_done` must not assert unless `pl_clk_req` was previously asserted|
|`A08`|`pl_wake_ack` must only assert when `lp_wake_req` is asserted|
|`A09`|`pl_state_sts` encoding must only be one of the 9 defined values — no illegal encodings|
|`A10`|`Link_Mgmt_Msg_Send` must not change while `valid_s == 0` (no spurious message drive)|
|`A11`|In LinkError state, DUT must not exit before 16ms have elapsed (timer residency)|
|`A12`|`pl_trainerror` must assert when `pl_state_sts == LinkError` and de-assert when exiting to Reset|
|`A13`|After `lp_state_req` transitions NOP→Active in Reset state, `Active_handshake_strt` must pulse within a bounded cycle count|
|`A14`|`lclk_g` must equal `lclk` whenever `pl_state_sts ∈ {Active, Retrain, Active_PMNAK}`|

---

#### 4. Coverage Plan

**State coverage:**

- All 9 `pl_state_sts` values reached at least once
- All `pl_state_sts` values held for at least 10 cycles (residency)

**Transition coverage (cross product):**

- Every legal `pl_state_sts → pl_state_sts` arc from spec Table 10-4 exercised at least once
- Every illegal arc verified to NOT occur (checked by A09)

**Message coverage:**

- Every `msg_no_e` value driven on `Link_Mgmt_Msg_Receive` at least once
- Every `msg_no_e` value observed on `Link_Mgmt_Msg_Send` at least once

**Handshake coverage:**

- CLK handshake: `clk_handshake_strt` sourced from `signal_transition` path and `traffic_req` path independently
- Active handshake: FLOW_0, FLOW_1, FLOW_2 all exercised
- Stall handshake: `lp_stallack` delayed by 1, 5, 10 cycles

**Trigger source coverage for Retrain:**

- `lp_state_req == Retrain` (adapter-initiated)
- `pl_error` pulse (PHY-detected framing error)
- `state_sts == PHYRETRAIN` (LTSM-initiated)
- Peer `RDI_RETRAIN_REQ` (remote-initiated)

**Gating logic coverage:**

- `lclk_g == 0` reached for each gateable state
- All 5 ungating trigger sources exercised independently

## You said: continue

continue

9:32 PM

## Claude responded: ---

Thinking about what previous context to continue from

Thinking about what previous context to continue from

---

#### 5. End-to-End Scenario Tests (Full Sequences)

These are multi-step integration scenarios testing complete protocol flows, not isolated units.

---

##### SC-01: Full Link Bring-Up

```
rst_n deassert
→ state_sts = PHYRESET (default)
→ lp_state_req = NOP
→ state_sts = LINKINIT
→ lp_state_req = NOP→Active
→ peer responds: RDI_ACTIVE_RSP
→ clk handshake completes
→ ASSERT: pl_state_sts == Active
→ ASSERT: pl_inband_pres == 1
→ ASSERT: pl_state_sts only changed after clk_handshake_done
```

---

##### SC-02: Active → L1 → Active (Full PM Cycle)

```
[Start from Active]
→ lp_state_req = L1
→ ASSERT: pl_stallreq asserts
→ lp_stallack
→ ASSERT: stall_done
→ DUT sends RDI_L1_REQ
→ peer responds RDI_L1_RSP
→ clk handshake
→ ASSERT: pl_state_sts == L1
→ lclk_g gates after 1µs
→ lp_wake_req asserts
→ ungating completes
→ lp_state_req = Active
→ DUT sends RDI_ACTIVE_REQ (pm_exit path)
→ peer responds RDI_ACTIVE_RSP
→ ASSERT: pl_state_sts == Active
```

---

##### SC-03: Active → L1 → Active (PM Abort — PMNAK)

```
[Start from Active]
→ lp_state_req = L1
→ Stall + L1 REQ sent
→ peer responds RDI_PMNAK_RSP
→ ASSERT: pl_state_sts == Active.PMNAK
→ 1µs timer runs
→ lp_state_req = Active (after timer)
→ ASSERT: pl_state_sts == Active
```

---

##### SC-04: Active → Retrain → Active

```
[Start from Active]
→ lp_state_req = Retrain
→ Stall handshake
→ DUT sends RDI_RETRAIN_REQ
→ peer responds RDI_RETRAIN_RSP
→ ASSERT: pl_state_sts == Retrain
→ state_sts = LINKINIT (LTSM retraining done)
→ lp_state_req = NOP then Active
→ Active handshake (FLOW_0)
→ ASSERT: pl_state_sts == Active
```

---

##### SC-05: Active → LinkError → Reset → Active (Full Recovery)

```
[Start from Active]
→ lp_linkerror = 1
→ DUT sends RDI_LINK_ERROR_REQ
→ peer responds RDI_LINK_ERROR_RSP
→ ASSERT: pl_state_sts == LinkError
→ ASSERT: pl_trainerror == 1
→ Wait 16ms (timer)
→ lp_linkerror = 0; lp_state_req = Active
→ ASSERT: pl_state_sts == Reset
→ lp_state_req = NOP then Active
→ Full bring-up again
→ ASSERT: pl_state_sts == Active
```

---

##### SC-06: Active → Retrain (peer-initiated) → Active

```
[Start from Active]
→ peer sends RDI_RETRAIN_REQ
→ ASSERT: pl_stallreq asserts (before RSP)
→ lp_stallack
→ DUT sends RDI_RETRAIN_RSP
→ ASSERT: pl_state_sts == Retrain
→ Retrain → Active (pm_exit = 0, standard NOP→Active path)
```

---

##### SC-07: L2 → Reset → Active

```
[Start from Active]
→ lp_state_req = L2
→ L2 entry completes
→ ASSERT: pl_state_sts == L2
→ lp_state_req = Active
→ ASSERT: pl_state_sts == Reset (L2 exit is through Reset, not Retrain)
→ lp_state_req = NOP then Active
→ LTSM bring-up
→ ASSERT: pl_state_sts == Active
```

---

##### SC-08: Active.PMNAK → Retrain (interrupt during PMNAK)

```
[Start from Active.PMNAK]
→ lp_state_req = Retrain (while waiting in PMNAK)
→ ASSERT: Active_PMNAK sub-SM handles Retrain request
→ Stall + RDI_RETRAIN_REQ + RSP
→ ASSERT: pl_state_sts == Retrain
```

---

##### SC-09: Consecutive Full State Machine Cycles (Stress)

```
Repeat 3 times:
  Full bring-up (Reset→Active)
  → L1 entry and exit
  → Retrain and return to Active
  → LinkError and recovery
ASSERT: Each cycle produces identical pl_state_sts transitions
ASSERT: No state machine lock-up after cycle 3
```

---

##### SC-10: Clock Gating During L1 with Interrupt

```
[Start in L1]
→ Gating conditions met; 1µs elapsed
→ ASSERT: lclk_g == 0
→ lp_wake_req asserts while gated
→ ASSERT: ungating_req asserts
→ ASSERT: lclk_g restores within same cycle as ungating_done
→ pl_wake_ack asserts
→ lp_wake_req deasserts
→ ASSERT: pl_wake_ack deasserts
→ Gating re-evaluates (conditions still met)
→ ASSERT: lclk_g gates again after 1µs
```

---

#### 6. Illegal / Spec-Forbidden Transition Tests

Per spec Table 10-4, certain `lp_state_req` values are explicitly "Ignore" in specific states. These must be verified to produce no state change.

|TC|Current `pl_state_sts`|`lp_state_req`|Expected|
|---|---|---|---|
|TC-ILL-01|Reset|L1|No transition; stays in Reset|
|TC-ILL-02|Reset|L2|No transition; stays in Reset|
|TC-ILL-03|Reset|Retrain|No transition; stays in Reset|
|TC-ILL-04|Active|NOP|No transition; stays in Active|
|TC-ILL-05|L1|L2|No transition; stays in L1|
|TC-ILL-06|L1|Retrain|No transition; stays in L1|
|TC-ILL-07|L1|LinkReset|No transition; stays in L1|
|TC-ILL-08|LinkReset|LinkReset|No transition; stays in LinkReset|
|TC-ILL-09|Disabled|Disabled|No transition; stays in Disabled|
|TC-ILL-10|LinkError|L1|No transition; stays in LinkError|
|TC-ILL-11|LinkError|L2|No transition; stays in LinkError|
|TC-ILL-12|LinkError|Retrain|No transition; stays in LinkError|
|TC-ILL-13|Active.PMNAK|L1|No transition; stays in Active.PMNAK|
|TC-ILL-14|Active.PMNAK|L2|No transition; stays in Active.PMNAK|

---

#### 7. Timing Parameter Tests

These tests directly verify spec-mandated timing constraints, not functional flows.

|TC|Parameter|Method|
|---|---|---|
|TC-TIM-01|1µs PM wait timer|Drive `start_time_1us`; count cycles until `time_1us`; verify = `CLK_FREQ × 1e-6 ± 1 cycle`|
|TC-TIM-02|16ms LinkError residency timer|Drive `start_time_16ms`; verify `time_16ms` fires at correct cycle count|
|TC-TIM-03|Clock gating 1µs hold|Verify gating state is not entered until full 1µs of stable conditions observed|
|TC-TIM-04|PMNAK 2µs retry window|After PMNAK received, drive `lp_state_req = L1` before 2µs; verify retry proceeds correctly|
|TC-TIM-05|Timer reset on condition change|De-assert `start_time_1us` mid-count; verify counter resets; re-assert; verify full 1µs counts again|

**Timer acceleration:** Use a `CLK_FREQ` parameter override in the testbench at a lower frequency (e.g., 1MHz) to make 16ms and 1µs timers fire in simulation-feasible cycle counts. Parameterize all timer tests accordingly.

---

#### 8. Scoreboard Checks

Every test must pass all of the following automatically logged checks:

|Check ID|Description|
|---|---|
|SC-CHK-01|`pl_state_sts` encoding is always a legal value (9 defined states only)|
|SC-CHK-02|Every `pl_state_sts` transition was preceded by a completed `clk_handshake_done`|
|SC-CHK-03|Every DUT-initiated sideband REQ was preceded by `pl_stallreq` + `lp_stallack` (where applicable)|
|SC-CHK-04|Every DUT-initiated sideband REQ received a peer RSP and no transition occurred before RSP|
|SC-CHK-05|`pl_inband_pres` de-asserted when `pl_state_sts ∈ {Reset, LinkReset, Disabled, LinkError}`|
|SC-CHK-06|`pl_inband_pres` asserted when `pl_state_sts ∈ {Active, Retrain, Active_PMNAK, L1, L2}`|
|SC-CHK-07|`lclk_g == lclk` whenever `pl_state_sts ∈ {Active, Retrain, Active_PMNAK}`|
|SC-CHK-08|`pl_stallreq` de-asserted before `pl_state_sts` leaves Active/PMNAK|
|SC-CHK-09|`pl_wake_ack` deasserts within 1 cycle of `lp_wake_req` deasserting|
|SC-CHK-10|`Message_receive` value is stable for at least 1 cycle after `valid_r` deasserts|
|SC-CHK-11|`pending_rx_valid` never holds two unprocessed messages simultaneously|
|SC-CHK-12|In LinkError, `pl_state_sts` does not transition to Reset before 16ms elapsed|

---

#### 9. File Structure

```
tb/
├── rdi_sm_tb_top.sv           — DUT instantiation, clock gen, reset
├── drivers/
│   ├── adapter_driver.sv      — lp_state_req, lp_linkerror, lp_stallack, lp_clk_ack, lp_wake_req
│   ├── ltsm_model.sv          — state_sts, pl_error stimulus
│   ├── peer_msg_driver.sv     — Link_Mgmt_Msg_Receive, valid_r, configurable delay + no-response mode
│   └── dvsec_driver.sv        — DVSEC register field stimulus
├── monitors/
│   └── output_monitor.sv      — samples all DUT outputs, logs to scoreboard
├── scoreboard/
│   └── rdi_sm_scoreboard.sv   — expected vs observed transition checker
├── assertions/
│   └── rdi_sm_assertions.sv   — SVA checker package bound to DUT
├── sequences/
│   ├── seq_reset_to_active.sv
│   ├── seq_active_to_l1.sv
│   ├── seq_pm_abort.sv
│   ├── seq_retrain.sv
│   ├── seq_linkerror_recovery.sv
│   └── seq_l2_exit.sv
├── tests/
│   ├── test_tg01_reset.sv
│   ├── test_tg02_bringup.sv
│   ├── test_tg03_retrain.sv
│   ├── test_tg04_pm.sv
│   ├── test_tg05_l1l2.sv
│   ├── test_tg06_linkreset.sv
│   ├── test_tg07_linkerror.sv
│   ├── test_tg08_disabled.sv
│   ├── test_tg09_handshakes.sv
│   ├── test_tg10_gating.sv
│   ├── test_tg11_msghandler.sv
│   ├── test_tg12_sigtransdet.sv
│   ├── test_tg13_decoder.sv
│   ├── test_tg14_timers.sv
│   ├── test_tg15_corner.sv
│   ├── test_illegal_transitions.sv
│   └── test_scenarios.sv
└── pkg/
    └── rdi_sm_tb_pkg.sv       — shared types, enums, task library
```

---

#### 10. Pass/Fail Criteria

|Criterion|Target|
|---|---|
|All TG-01 through TG-15 test cases pass|100%|
|All SC-01 through SC-10 scenario tests pass|100%|
|All TC-ILL illegal transition tests produce no state change|100%|
|All SVA assertions A01–A14 pass with zero violations|100%|
|All scoreboard checks SC-CHK-01 through SC-CHK-12 pass|100%|
|State coverage: all 9 `pl_state_sts` values reached|100%|
|Transition coverage: all legal arcs from spec Table 10-4 exercised|100%|
|Message coverage: all `msg_no_e` values sent and received|100%|
|Active handshake FLOW_0 / FLOW_1 / FLOW_2 all exercised|100%|
|Clock gating: all 5 ungating triggers exercised independently|100%|
|Retrain trigger source coverage: all 4 sources exercised|100%|
|Zero simulation X-state propagation to `pl_state_sts` at any time|100%|