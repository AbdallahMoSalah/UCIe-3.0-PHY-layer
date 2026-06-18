# wrapper_MBTRAIN Test Plan

## UCIe 3.0 PHY Layer

## MBTRAIN Full-Flow Scenario Matrix

---

# 1. Objective

Verify `wrapper_MBTRAIN` and `unit_MBTRAIN_ctrl` by exercising all legal flow paths through MBTRAIN.

The goal is NOT to re-verify individual substates because dedicated testbenches already exist.

The goal is to verify:

* Correct substate sequencing.
* Correct transition decisions.
* Correct handling of LINKSPEED outcomes.
* Correct handling of RXDESKEW outcomes.
* Correct handling of PHYRETRAIN requests.
* Correct handling of speed degradation.
* Correct handling of width degradation.
* Correct handling of TRAINERROR entry.
* Correct completion to LINKINIT.

---

# 2. Expected Nominal MBTRAIN Order

The controller shall execute the following order:

1. VALVREF
2. DATAVREF
3. SPEEDIDLE
4. TXSELFCAL
5. RXCLKCAL
6. VALTRAINCENTER
7. VALTRAINVREF
8. DATATRAINCENTER1
9. DATATRAINVREF
10. RXDESKEW
11. DATATRAINCENTER2
12. LINKSPEED

Then:

* LINKINIT
  OR
* REPAIR
  OR
* SPEEDIDLE
  OR
* PHYRETRAIN
  OR
* TRAINERROR

---

# 3. Scenario Classification

Scenarios are divided into:

## Group A

Normal Success Flow

## Group B

Speed Degrade Flow

## Group C

Width Degrade Flow

## Group D

PHY Retrain Flow

## Group E

Training Failure Flow

## Group F

Asynchronous Error Injection

---

# 4. Scenario A1

## Golden Path

### Entry

VALVREF

### Conditions

All substates succeed.

RXDESKEW succeeds.

LINKSPEED reports stable link.

No speed degrade required.

No width degrade required.

No PHY retrain request.

### Expected Path

VALVREF
→ DATAVREF
→ SPEEDIDLE
→ TXSELFCAL
→ RXCLKCAL
→ VALTRAINCENTER
→ VALTRAINVREF
→ DATATRAINCENTER1
→ DATATRAINVREF
→ RXDESKEW
→ DATATRAINCENTER2
→ LINKSPEED
→ LINKINIT

### Expected Result

PASS

---

# 5. Scenario B1

## Single Speed Degrade

### Entry

VALVREF

### Conditions

All substates pass.

LINKSPEED determines current speed is unstable.

Next lower speed exists.

### Expected Path

...
→ LINKSPEED
→ SPEEDIDLE
→ TXSELFCAL
→ RXCLKCAL
→ VALTRAINCENTER
→ VALTRAINVREF
→ DATATRAINCENTER1
→ DATATRAINVREF
→ RXDESKEW
→ DATATRAINCENTER2
→ LINKSPEED
→ LINKINIT

### Expected Result

PASS

### Coverage

Verify one speed fallback cycle.

---

# 6. Scenario B2

## Multiple Speed Degrades

### Example

64 GT/s
→ 48 GT/s
→ 32 GT/s

### Expected Path

Training loop repeats after every SPEEDIDLE.

Final LINKSPEED reports stable.

Eventually enters LINKINIT.

### Expected Result

PASS

---

# 7. Scenario B3

## Lowest Speed Still Fails

### Conditions

LINKSPEED repeatedly requests speed degrade.

No lower speed available.

### Expected Path

...
→ LINKSPEED
→ TRAINERROR

### Expected Result

PASS

---

# 8. Scenario C1

## Width Degrade x16 → x8 (`is_x16_module` flag is asserted (=1'b1) and the flag `is_x8_module` is cleared (=1'b0))
### `Note the equation: is_x16_module = (rf_cap_SPMW == 1'b0) && (rf_ctrl_target_link_width == 4'h2) && (param_UCIe_S_x8 == 1'b0);` and `is_x8_module  = rf_ctrl_target_link_width == 4'h1;`

### Conditions

RXDESKEW passes.

LINKSPEED detects lane instability.

Width degradation allowed.

### Expected Path

...
→ LINKSPEED
→ REPAIR
→ DATATRAINCENTER2
→ LINKSPEED
→ LINKINIT

### Expected Result

PASS

---

# 9. Scenario C2

## Width Degrade x8 → x4 when this condition happens (`is_x16_module` flag is cleared (=1'b0) and the flag `is_x8_module` is asserted (=1'b1))
### `Note the equation: is_x16_module = (rf_cap_SPMW == 1'b0) && (rf_ctrl_target_link_width == 4'h2) && (param_UCIe_S_x8 == 1'b0);` and `is_x8_module  = rf_ctrl_target_link_width == 4'h1;`
if any other thing happen we expect to go to trainerror.

### Conditions

Width degradation required for the degrade to.

### Expected Path

...
→ LINKSPEED
→ REPAIR
→ DATATRAINCENTER2
→ LINKSPEED
→ REPAIR
→ DATATRAINCENTER2
→ LINKSPEED
→ LINKINIT

### Expected Result

PASS

---

# 10. Scenario C3

## Width Degrade Exhausted (x16 -> x8 -> degrade not possible)
the maximum allawed number of width degrade is 1 time of degrading (x16 → x8 or x8 → x4). Note there is no degrade from x16 → x4 (the specs didn't say any thing about this condition so, it's impossible). for the 2nd degrade implementation the degrade should be not possible and the system will go to TRAINERROR state.
when the degrade is not possible then the system will enter the TRAINERROR state.

### Conditions

No valid lane configuration remains.

### Expected Path

...
→ LINKSPEED
→ REPAIR
→ LINKSPEED
→ REPAIR
→ TRAINERROR

### Expected Result

PASS

---


# 11. Scenario C4

## Width Degrade Exhausted (x8 -> x4 -> degrade not possible)
the maximum allawed number of width degrade is 1 time of degrading (x16 → x8 or x8 → x4). Note there is no degrade from x16 → x4 (the specs didn't say any thing about this condition so, it's impossible). for the 2nd degrade implementation the degrade should be not possible and the system will go to TRAINERROR state.
when the degrade is not possible then the system will enter the TRAINERROR state.


### Conditions

No valid lane configuration remains.

### Expected Path

...
→ LINKSPEED
→ REPAIR
→ LINKSPEED
→ REPAIR
→ TRAINERROR

### Expected Result

PASS

---

# 12. Scenario D1

## PHY Retrain Request

### Conditions

LINKSPEED detects parameter change.

params_changed = 1

### Expected Path

...
→ LINKSPEED
→ PHYRETRAIN

### Expected Result

PASS

---

# 13. Scenario D2

## PHY Retrain Then Success

### Conditions

Controller re-enters MBTRAIN after PHYRETRAIN.

### Expected Path

MBTRAIN
→ LINKSPEED
→ PHYRETRAIN

New training session:

VALVREF
→ ...
→ LINKSPEED
→ LINKINIT

### Expected Result

PASS

---

# 14. Scenario D3

## PHY Retrain Then Speed Degrade

### Expected Path

MBTRAIN
→ LINKSPEED
→ PHYRETRAIN

Re-entry:

...
→ LINKSPEED
→ SPEEDIDLE
→ ...
→ LINKINIT

### Expected Result

PASS

---

# 15. Scenario E1

## VALVREF Failure

### Conditions

VALVREF requests TRAINERROR.

### Expected Path

VALVREF
→ TRAINERROR

### Expected Result

PASS

---

# 16. Scenario E2

## DATAVREF Failure

### Expected Path

VALVREF
→ DATAVREF
→ TRAINERROR

---

# 17. Scenario E3

Failure in SPEEDIDLE.

### Expected Path

...
→ SPEEDIDLE
→ TRAINERROR

---

# 18. Scenario E4

Failure in TXSELFCAL.

### Expected Path

...
→ TXSELFCAL
→ TRAINERROR

---

# 19. Scenario E5

Failure in RXCLKCAL.

### Expected Path

...
→ RXCLKCAL
→ TRAINERROR

---

# 20. Scenario E6

Failure in VALTRAINCENTER.

### Expected Path

...
→ VALTRAINCENTER
→ TRAINERROR

---

# 21. Scenario E7

Failure in VALTRAINVREF.

### Expected Path

...
→ VALTRAINVREF
→ TRAINERROR

---

# 22. Scenario E8

Failure in DATATRAINCENTER1.

### Expected Path

...
→ DATATRAINCENTER1
→ TRAINERROR

---

# 23. Scenario E9

Failure in DATATRAINVREF.

### Expected Path

...
→ DATATRAINVREF
→ TRAINERROR

---

# 24. Scenario E10

Failure in RXDESKEW.

### Expected Path

...
→ RXDESKEW
→ TRAINERROR

### Coverage

Very important because RXDESKEW is a major branch point.

---

# 25. Scenario E11

Failure in DATATRAINCENTER2.

### Expected Path

...
→ DATATRAINCENTER2
→ TRAINERROR

---

# 26. Scenario E12

LINKSPEED unrecoverable failure.

### Expected Path

...
→ LINKSPEED
→ TRAINERROR

---

# 27. Scenario F1

## TRAINERROR Injection During Any State

Inject external TRAINERROR request while controller is inside:

* VALVREF
* DATAVREF
* SPEEDIDLE
* TXSELFCAL
* RXCLKCAL
* VALTRAINCENTER
* VALTRAINVREF
* DATATRAINCENTER1
* DATATRAINVREF
* RXDESKEW
* DATATRAINCENTER2
* LINKSPEED

Expected:

Immediate transition to TRAINERROR.

---

# 28. Scenario F2

## Soft Reset During MBTRAIN

Inject soft reset while training is active.

Expected:

Return to IDLE state.

No pending requests remain asserted.

---

# 29. Scenario F3

## Disable MBTRAIN Mid-Sequence

Deassert MBTRAIN enable.

Expected:

Clean exit to idle.

No deadlock.

---

# 30. Lane Width Coverage

Run all major success scenarios using:

* x16
* x8
* x4

At minimum:

A1
B1
C1
D1

must be repeated for all widths.

---

# 31. Terminal Output Strategy

Do NOT print every state transition cycle.

Print only scenario-level milestones.

Recommended format:

[SCENARIO START] A1_GOLDEN_PATH

[FLOW]
VALVREF
DATAVREF
SPEEDIDLE
TXSELFCAL
RXCLKCAL
VALTRAINCENTER
VALTRAINVREF
DATATRAINCENTER1
DATATRAINVREF
RXDESKEW
DATATRAINCENTER2
LINKSPEED
LINKINIT

[RESULT] PASS

---

Example:

[SCENARIO START] B1_SINGLE_SPEED_DEGRADE

[EVENT] LINKSPEED requested SPEED_DEGRADE

[LOOP] Re-enter MBTRAIN sequence

[EVENT] LINKSPEED stable

[RESULT] PASS

---

Example:

[SCENARIO START] C1_WIDTH_DEGRADE_X16_TO_X8

[EVENT] LINKSPEED requested REPAIR

[EVENT] Width degraded x16 -> x8

[EVENT] LINKSPEED stable

[RESULT] PASS

---

Example:

[SCENARIO START] E10_RXDESKEW_FAILURE

[EVENT] RXDESKEW requested TRAINERROR

[RESULT] PASS

---

# 32. Final Simulation Summary

At end of simulation print only:

==================================================
MBTRAIN REGRESSION SUMMARY
==========================

TOTAL SCENARIOS : XX
PASSED          : XX
FAILED          : XX

Golden Path                PASS
Speed Degrade              PASS
Multi Speed Degrade        PASS
Width Degrade              PASS
PHY Retrain                PASS
Training Failures          PASS
Async Error Injection      PASS

==================================================
OVERALL RESULT : PASS
=====================
