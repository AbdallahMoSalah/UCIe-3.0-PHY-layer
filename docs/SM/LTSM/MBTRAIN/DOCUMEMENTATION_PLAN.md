

---

# MBTRAIN Documentation Generation Master Plan

## Objective

Generate a complete engineering documentation package for the MBTRAIN implementation within the UCIe PHY Layer project.

The documentation package shall consist of:

* 13 Substate Documentation Files
* 1 MBTRAIN Top-Level Documentation File

Total:

```text
14 Markdown Files
```

The generated documentation must describe the actual RTL implementation rather than the UCIe specification alone.

The documentation shall be derived from:

* RTL source code
* FSM implementations
* Wrapper modules
* Internal interfaces
* MBTRAIN controller logic
* UCIe specification references

The purpose of the documentation is:

* Graduation project report preparation
* Design review
* Knowledge transfer
* Future maintenance
* FSM understanding
* Verification support

---

# Phase 1 — Documentation Structure Definition

Create the following files:

```text
docs/

01_MBTRAIN_VALVREF.md
02_MBTRAIN_DATAVREF.md
03_MBTRAIN_SPEEDIDLE.md
04_MBTRAIN_TXSELFCAL.md
05_MBTRAIN_RXCLKCAL.md
06_MBTRAIN_VALTRAINCENTER.md
07_MBTRAIN_VALTRAINVREF.md
08_MBTRAIN_DATATRAINCENTER1.md
09_MBTRAIN_DATATRAINVREF.md
10_MBTRAIN_RXDESKEW.md
11_MBTRAIN_DATATRAINCENTER2.md
12_MBTRAIN_LINKSPEED.md
13_MBTRAIN_REPAIR.md

14_MBTRAIN_TOP.md
```

The numbering is mandatory.

All files must follow exactly the same structure.

---

# Phase 2 — Information Extraction Rules

Before generating any Markdown file:

The AI Agent must locate:

```text
unit_<substate>_local.sv
unit_<substate>_partner.sv
wrapper_<substate>.sv
```

For every substate.

The AI Agent shall extract:

### Local FSM

* State names
* State order
* Transition conditions
* Exit conditions
* Done conditions

### Partner FSM

* State names
* State order
* Transition conditions
* Exit conditions
* Done conditions

### Wrapper

* Interface signals
* Internal module instantiations
* Connections

The AI Agent must never infer FSM states.

Only actual RTL states are allowed.

---

# Phase 3 — Mandatory Structure of Every Substate File

Each substate file shall contain the following sections.

---

## Section 1 — Substate Overview

Purpose:

Provide a concise explanation of:

```text
Why does this substate exist?
```

Include:

* Training objective
* Calibration objective
* Position inside MBTRAIN
* Entry condition
* Exit condition

Length:

```text
1-2 pages maximum
```

---

## Section 2 — UCIe Specification Context

Describe:

```text
Where this substate appears inside
UCIe LTSM.
```

Example:

```text
RESET
SBINIT
MBINIT
MBTRAIN
   └── VALVREF
```

Reference relevant MBTRAIN stage from UCIe specification. 

---

## Section 3 — FSM Architecture Overview

Explain:

```text
Local FSM
Partner FSM
```

Explain:

* Which side initiates
* Which side responds
* Message flow
* Local responsibilities
* Partner responsibilities

This section must be generated using project architecture, not generic UCIe text. 

---

## Section 4 — FSM Diagram

Generate Mermaid diagram.

Requirements:

### Local FSM

```mermaid
stateDiagram-v2
```

Requirements:

* Rectangular states
* All states visible
* Transition conditions shown
* Moore FSM representation

---

### Partner FSM

Separate diagram.

Never combine both FSMs into one diagram.

Reason:

Large diagrams become unreadable.

Instead:

```text
Local FSM Diagram

Partner FSM Diagram
```

---

## Section 5 — Local FSM State Table

Create table:

| State ID | State Name | Purpose | Transition Condition |
| -------- | ---------- | ------- | -------------------- |

Rules:

* One row per RTL state
* Purpose must explain functionality
* Transition must describe actual RTL condition

---

## Section 6 — Partner FSM State Table

Same structure.

Separate table.

Never merge with Local FSM.

---

## Section 7 — Local FSM Execution Flow

Create sequential explanation:

```text
State 0
↓
State 1
↓
State 2
↓
...
```

Explain:

* Actions performed
* Expected messages
* Internal updates

---

## Section 8 — Partner FSM Execution Flow

Same concept.

---

## Section 9 — Wrapper Architecture

Describe:

```text
wrapper_<substate>.sv
```

Include:

* Purpose
* Instantiated modules
* Signal routing

---

## Section 10 — Wrapper Interface Table

Only wrapper-visible ports.

Table:

| Signal | Direction | Width | Description |
| ------ | --------- | ----- | ----------- |

Direction:

```text
Input
Output
Inout
```

Width:

```text
1
[3:0]
[15:0]
...
```

---

## Section 11 — Internal Signal Summary

Optional.

Only important signals.

Not every wire.

---

## Section 12 — Sideband Communication Sequence

Describe:

```text
REQ
RESP
START
DONE
```

messages.

Example:

```text
Local sends START_REQ

Partner receives START_REQ

Partner sends START_RESP

Local starts sweep
```

This section is extremely important because MBTRAIN is built around cross-die communication. 

---

## Section 13 — D2C_PT Interaction

Only if applicable.

Describe:

```text
TX_D2C_PT
or
RX_D2C_PT
```

Include:

* Sweep parameter
* Initiator
* Receiver
* Test direction

Based on actual MBTRAIN mapping. 

---

## Section 14 — Summary

One-page conclusion.

---

# Phase 4 — MBTRAIN_TOP Documentation

File:

```text
14_MBTRAIN_TOP.md
```

---

## Section 1

MBTRAIN Overview

---

## Section 2

Complete MBTRAIN Sequence

```text
VALVREF
↓
DATAVREF
↓
SPEEDIDLE
↓
...
```

All 13 substates. 

---

## Section 3

MBTRAIN Controller Architecture

Document:

```text
unit_MBTRAIN_ctrl.sv
```

Explain:

* Enable signals
* Done signals
* Transition rules

---

## Section 4

Global MBTRAIN Flow Diagram

Large Mermaid diagram.

---

## Section 5

Substate Summary Table

| Substate | Purpose | Entry Condition | Exit Condition |

---

## Section 6

Substate Dependency Matrix

| Current | Next | Condition |

---

## Section 7

Wrapper_MBTRAIN Interface Table

Top-level ports only.

---

## Section 8

Training Data Flow

Explain interaction between:

* MBTRAIN Controller
* Substates
* D2C Sweep Engine
* Sideband Interface
* Local FSMs
* Partner FSMs

---

# Phase 5 — Documentation Quality Rules

The AI Agent must:

### DO

* Use actual RTL names.
* Preserve state names exactly.
* Preserve signal names exactly.
* Preserve port widths exactly.
* Preserve hierarchy exactly.

### DO NOT

* Invent states.
* Rename states.
* Simplify transitions.
* Merge Local and Partner FSMs.
* Assume missing behavior.

---

# Expected Final Output

```text
14 Markdown Files

≈ 15–25 pages per Substate

≈ 30–50 pages for MBTRAIN_TOP

Total Documentation:
≈ 250–350 Pages
```
