================================================================================
PROBLEMS RESOLVED & VERIFIED DESIGN EXPLANATIONS
================================================================================

1. COMPILATION ERROR RESOLUTION (unit_RXDESKEW_partner.sv)
--------------------------------------------------------------------------------
* Problem: The compiler generated a duplicate declaration warning/error for `reg end_req_rcvd;` because it was declared both at the top of the internal registers block (line 204) and right before the `always_ff` block (line 454).
* Solution: Removed the duplicate declaration at line 454, keeping only the top-level declaration.
* Rationale: Ensures a clean SystemVerilog compile without any namespace collision warnings.

2. SCENARIO 6 HANG & ARC TRACKING RESOLUTION
--------------------------------------------------------------------------------
* Problem: In Scenario 6 Loop 1, the FSMs hung because they prematurely entered `RXDESKEW_TO_DTC2` instead of arcing back to `DTC1`. The testbench was waiting for `u_dut.local_datatraincenter1_req`, resulting in a simulation deadlock.
* Solution: 
  - Connected the new `local_arc_taken` port in `wrapper_RXDESKEW.sv` directly to `local_datatraincenter1_req`.
  - Designed a robust 1-cycle increment gate using a sticky `is_dtc1_arc_cnt_inc_allowed` flag in the Partner FSM. This ensures the authoritative `dtc1_arc_cnt` increments exactly once per DTC1 arc session (whether initiated by Local or Partner) and avoids double-counting while the FSM dwells in the terminal `TO_DTC1` state.
  - Linked the Local next-state logic to the Authoritative Partner counter (`partner_arc_cnt`), cleanly enforcing the 4-arc budget. On the 5th loop, it properly transitions to `DTC2` instead of DTC1, resolving the simulation hang.

================================================================================
SPEC-COMPLIANCE ANALYSIS (ANSWERS TO EXISTING QUESTIONS)
================================================================================

1. Q: Does the `end_req_rcvd` signal (line 335) handle the specs correctly or is it strange logic?
--------------------------------------------------------------------------------
* Answer: It is SPEC-COMPLIANT and absolutely necessary to prevent training deadlocks.
* Explanation:
  - According to UCIe 3.0 §4.5.3.4.10, a die cannot transition to DTC2 until it has both sent and received an `{end resp}`.
  - If Die A finds a wide eye on Preset 0 early, it transitions to `SEND_END_REQ` and sends `{end req}`.
  - Meanwhile, Die B is still sweeping other presets because Preset 0 was narrow.
  - If Die B's Partner FSM immediately replied with `{end resp}` to Die A, Die A would think the handshake was complete and transition to DTC2.
  - But if Die B subsequently finds that all presets are narrow, Die B's Local FSM will want to arc back to DTC1. If Die A is already in DTC2 while Die B is in DTC1, the link enters a mismatched/deadlocked state.
  - Therefore, Die B's Partner FSM must capture the `{end req}` in a sticky `end_req_rcvd` register and *defer* the `{end resp}` until Die B's Local FSM has also completed its sweeps and is ready to end (`local_end_active` is asserted).
  - If Die B's Local FSM instead decides to arc to DTC1, `local_exit_dtc1_active` is asserted, which discards the received `{end req}` and prevents sending `{end resp}` (gating it per spec). Die B then sends `{exit to DTC1 req}`, forcing Die A to follow it to DTC1.
  - Thus, `end_req_rcvd` correctly coordinates the parallel, decoupled FSMs.

2. Q: Why do we set the default value `7` to the variable `old_best_preset` in unit_RXDESKEW_local.sv?
--------------------------------------------------------------------------------
* Answer: It ensures that the first sweep session can always arc to DTC1.
* Explanation:
  - Valid UCIe preset indices range from `0` to `5`.
  - `3'd7` represents an invalid/out-of-bounds preset index indicating "no previous best preset exists."
  - During the first sweep session, if the eye is narrow, we check `(old_best_preset != best_preset)` to decide if we should arc to DTC1.
  - Since `old_best_preset` defaults to `7`, the inequality `7 != best_preset` is guaranteed to be TRUE, allowing the FSM to transition to DTC1 to search for a better preset.
  - If we had defaulted `old_best_preset` to `0`, and the best preset found in the first session was `0`, the inequality `0 != 0` would evaluate to FALSE. This would prevent the FSM from arcing to DTC1, forcing it to prematurely exit to DTC2 with a narrow eye, which violates spec compliance.

================================================================================
QUESTIONS FOR CLAUDE CODE TO DOUBLE CHECK
================================================================================

1. Double-Check Next-State Priority for TRAINERROR:
   - In both `unit_RXDESKEW_local.sv` and `unit_RXDESKEW_partner.sv`, we implemented highest-priority checks for `timeout_8ms_occured` and `TRAINERROR_Entry_req` at the top of the next-state logic to override all active states.
   - Question for Claude: Does the spec permit any case where a pending `{exit to DTC1 resp}` or `{end resp}` should take precedence over a `TRAINERROR_Entry_req`? (Our design assumes TRAINERROR is always highest priority).

2. Validation of the 4-Arc Limit Enforcement:
   - In our design, the Local FSM reads the Partner FSM's `partner_arc_cnt` to check if `partner_arc_cnt < 4`.
   - Question for Claude: Are there any race conditions when both dies simultaneously evaluate `partner_arc_cnt < 4` and send `{exit to DTC1 req}`, and how does the cross-die conflict logic handle it if one die has already reached its limit but the other has not?