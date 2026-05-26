# SBINIT Step 8 Handshake — Design Comparison

> **Module**: `SBINIT.sv` — UCIe 3.0 §4.5.3.2  
> **Block**: LTSM → SBINIT → Step 8 (Done Handshake)  
> **Date**: May 2026

This document compares two implementation approaches for the **Step 8 Done Handshake** inside the SBINIT state machine. Both approaches share the same port interface and the same behavior for Steps 1-7. The difference is **only in how Step 8 is handled**.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. State Enum Difference](#2-state-enum-difference)
- [3. TX-Side Sticky Flags (Merged Only)](#3-tx-side-sticky-flags-merged-only)
- [4. Next-State Logic Difference](#4-next-state-logic-difference)
- [5. Output Logic Difference](#5-output-logic-difference)
- [6. Hardware Cost Comparison](#6-hardware-cost-comparison)
- [7. Pros & Cons Summary](#7-pros--cons-summary)
- [8. Final Decision](#8-final-decision)

---

## 1. Overview

| | Approach A: Split (4 Sub-States) | Approach B: Merged (1 State) |
|---|---|---|
| **Step 8 States** | `REQ_SEND → REQ_WAIT → RSP_SEND → RSP_WAIT` | `DONE_HANDSHAKE` (single state) |
| **Total States** | 10 | 7 |
| **State Encoding** | `logic [3:0]` (4-bit) | `logic [2:0]` (3-bit) |
| **Extra FFs** | None | 2 TX-side stickies + 2 combinational helpers |
| **Status** | ✅ **Current implementation** | ❌ Replaced |

### State Diagram — Approach A (Split)

```
  S3: OUT_OF_RESET
        │
        ▼
  S4_REQ_SEND  ──(ltsm_rdy)──►  S4_REQ_WAIT
                                      │
                                (done_req_rcvd)
                                      │
                                      ▼
                                S4_RSP_SEND  ──(ltsm_rdy)──►  S4_RSP_WAIT
                                                                    │
                                                              (done_resp_rcvd)
                                                                    │
                                                                    ▼
                                                                S6: DONE
```

### State Diagram — Approach B (Merged)

```
  S3: OUT_OF_RESET
        │
        ▼
  S4_DONE_HANDSHAKE  ──(done_req_sent && done_resp_sent &&
        │                done_req_rcvd && done_resp_rcvd)──►  S6: DONE
        │
        └── internal priority logic:
              if (!done_req_sent)                    → drive done_req
              else if (done_req_rcvd && !done_resp_sent) → drive done_resp
              else                                   → idle (wait)
```

---

## 2. State Enum Difference

**Approach A — Split (10 states, 4-bit):**
```systemverilog
typedef enum logic [3:0] {
    SB_S0_IDLE,
    SB_S1_DET_PATTERN,
    SB_S2_LINK_SYNCH,
    SB_S3_OUT_OF_RESET,
    SB_S4_REQ_SEND,       // ← Step 8a: drive done_req until FIFO accepts
    SB_S4_REQ_WAIT,       // ← Step 8b: wait for partner's done_req
    SB_S4_RSP_SEND,       // ← Step 8c: drive done_resp until FIFO accepts
    SB_S4_RSP_WAIT,       // ← Step 8d: wait for partner's done_resp
    SB_S5_ERROR,
    SB_S6_DONE
} sb_state_e;
```

**Approach B — Merged (7 states, 3-bit):**
```systemverilog
typedef enum logic [2:0] {
    SB_S0_IDLE,
    SB_S1_DET_PATTERN,
    SB_S2_LINK_SYNCH,
    SB_S3_OUT_OF_RESET,
    SB_S4_DONE_HANDSHAKE, // ← Step 8: everything in one state
    SB_S5_ERROR,
    SB_S6_DONE
} sb_state_e;
```

**Explanation**: Approach A splits the Step 8 handshake into 4 explicit sub-states, each with a single responsibility (send or wait). Approach B collapses them into one state and uses internal if/else logic + TX sticky flags to track progress.

---

## 3. TX-Side Sticky Flags (Merged Only)

This block **only exists in Approach B**. Approach A does not need it because the state itself encodes whether a message has been sent.

**Approach B — Extra FFs and combinational signals:**
```systemverilog
// ---------------- S4 TX-side stickies (deadlock-free Step 8) ----------------
logic done_req_sent;
logic done_resp_sent;
logic sending_done_req;   // combinational: we are driving done_req  this cycle
logic sending_done_resp;  // combinational: we are driving done_resp this cycle

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        done_req_sent  <= 1'b0;
        done_resp_sent <= 1'b0;
    end else if (current_state == SB_S0_IDLE) begin
        done_req_sent  <= 1'b0;
        done_resp_sent <= 1'b0;
    end else begin
        if (sending_done_req  && ltsm_rdy) done_req_sent  <= 1'b1;
        if (sending_done_resp && ltsm_rdy) done_resp_sent <= 1'b1;
    end
end
```

**Approach A — Not needed:**
```
// (Nothing here — the state register itself tracks send progress)
// REQ_SEND → ltsm_rdy → REQ_WAIT  means "done_req was sent"
// RSP_SEND → ltsm_rdy → RSP_WAIT  means "done_resp was sent"
```

**Explanation**: In Approach A, the fact that you moved from `REQ_SEND` to `REQ_WAIT` already encodes that `done_req` was accepted by the FIFO. In Approach B, since there's only one state, you need explicit `done_req_sent` / `done_resp_sent` flip-flops to remember that. This costs **2 extra FFs** + the combinational `sending_done_req` / `sending_done_resp` signals that feed back into the FF enable logic.

---

## 4. Next-State Logic Difference

**Approach A — Split (simple, one condition per state):**
```systemverilog
SB_S3_OUT_OF_RESET  : if (out_of_reset_rcvd)
                          next_state = SB_S4_REQ_SEND;

// Step 8: split handshake
SB_S4_REQ_SEND     : if (ltsm_rdy)
                          next_state = SB_S4_REQ_WAIT;

SB_S4_REQ_WAIT     : if (done_req_rcvd)
                          next_state = SB_S4_RSP_SEND;

SB_S4_RSP_SEND     : if (ltsm_rdy)
                          next_state = SB_S4_RSP_WAIT;

SB_S4_RSP_WAIT     : if (done_resp_rcvd)
                          next_state = SB_S6_DONE;
```

**Approach B — Merged (4-input AND gate):**
```systemverilog
SB_S3_OUT_OF_RESET  : if (out_of_reset_rcvd)
                          next_state = SB_S4_DONE_HANDSHAKE;

SB_S4_DONE_HANDSHAKE: if (done_req_sent  && done_resp_sent &&
                          done_req_rcvd  && done_resp_rcvd)
                          next_state = SB_S6_DONE;
```

**Explanation**: 
- Approach A has **5 case entries** for Step 8, each with a **single-bit condition**. Simple 1-input mux per transition.
- Approach B has **1 case entry** with a **4-input AND** condition. Fewer case entries but the exit condition is wider.

---

## 5. Output Logic Difference

This is the **biggest difference** between the two approaches.

**Approach A — Simple fixed assignments per state:**
```systemverilog
// Step 8: each SEND state drives one message until FIFO accepts.
SB_S4_REQ_SEND: begin
    sb_tx_valid  = 1'b1;
    sb_tx_msg_id = SBINIT_done_req;
end

SB_S4_RSP_SEND: begin
    sb_tx_valid  = 1'b1;
    sb_tx_msg_id = SBINIT_done_resp;
end

// REQ_WAIT and RSP_WAIT: outputs stay at defaults (tx_valid=0)
```

**Approach B — Priority encoder with if/else chain:**
```systemverilog
SB_S4_DONE_HANDSHAKE: begin
    // Spec Step 8: independent send-our-req and react-to-partner-req paths.
    //  - First: drive our done_req until FIFO accepts.
    //  - Once partner's done_req has arrived: drive our done_resp until FIFO accepts.
    // Exit when both ours are sent AND both partner's are received.
    if (!done_req_sent) begin
        sb_tx_valid      = 1'b1;
        sb_tx_msg_id     = SBINIT_done_req;
        sending_done_req = 1'b1;           // ← feeds back to FF
    end else if (done_req_rcvd && !done_resp_sent) begin
        sb_tx_valid       = 1'b1;
        sb_tx_msg_id      = SBINIT_done_resp;
        sending_done_resp = 1'b1;          // ← feeds back to FF
    end
end
```

**Explanation**:
- **Approach A**: Each state has **fixed, unconditional** outputs. No if/else, no priority encoder. The mux has more inputs (10 states) but each input is trivial.
- **Approach B**: One state with **2-level priority logic**. The `sending_done_req` and `sending_done_resp` signals are **combinational outputs that feed back** into the `always_ff` block (through the `done_req_sent`/`done_resp_sent` enables). This creates a **combinational feedback path** (not a loop, but increases the critical path depth).

---

## 6. Hardware Cost Comparison

### Flip-Flop Count

| Resource | Approach A (Split) | Approach B (Merged) |
|---|:---:|:---:|
| State register (binary encoding) | 4 FFs | 3 FFs |
| RX sticky flags (`out_of_reset_rcvd`, `done_req_rcvd`, `done_resp_rcvd`) | 3 FFs | 3 FFs |
| `pattern_rcvd_sticky` | 1 FF | 1 FF |
| TX sticky flags (`done_req_sent`, `done_resp_sent`) | **0** | **2 FFs** |
| **Total** | **8 FFs** | **9 FFs** |

> **Result**: Approach A uses **1 fewer FF** in binary encoding.

With **one-hot encoding** (typical FPGA):

| Resource | Approach A (Split) | Approach B (Merged) |
|---|:---:|:---:|
| State register (one-hot) | 10 FFs | 7 FFs |
| Other flags | 4 FFs | 6 FFs |
| **Total** | **14 FFs** | **13 FFs** |

> **Result**: In one-hot, Approach B saves 1 FF — negligible difference.

### Combinational Logic

| Metric | Approach A (Split) | Approach B (Merged) |
|---|---|---|
| Output mux inputs | 10 states (wider mux) | 7 states (narrower mux) |
| Logic per mux input | **Fixed assignments** — no conditionals | **Priority encoder** in S4 (if/else chain) |
| Combinational depth | Shallow — single level | Deeper — `done_req_sent` → `done_req_rcvd` → `done_resp_sent` chain |
| Feedback paths | None | `sending_done_req` / `sending_done_resp` → FF enable |

> **Result**: Approach A has **simpler combinational logic** overall.

---

## 7. Pros & Cons Summary

### Approach A: Split (4 Sub-States) — ✅ Current

| ✅ Pros | ❌ Cons |
|---|---|
| **Fewer FFs** (8 vs 9 in binary) | **More states** (10 vs 7) — wider mux |
| **Simpler output logic** — no if/else, no priority | Minimum **4 state transitions** for handshake |
| **No feedback paths** in combinational logic | — |
| **Easier debug** — each state has one clear purpose in waveform | — |
| **Consistent** with REPAIRCLK / REPAIRVAL handshake pattern | — |

### Approach B: Merged (1 State) — ❌ Replaced

| ✅ Pros | ❌ Cons |
|---|---|
| **Fewer states** (7 vs 10) — narrower mux | **More FFs** (9 vs 8) — TX stickies |
| Potentially **faster** — fewer transitions | **Complex output logic** — priority encoder |
| — | **Combinational feedback** paths |
| — | **Harder to debug** — need to check 4 flags to know handshake progress |
| — | **Not consistent** with other module handshake patterns |

### Deadlock Safety

**Both approaches are safe** — no deadlock possible in either one.

Both use **sticky flags** for RX messages (`done_req_rcvd`, `done_resp_rcvd`) that capture partner events regardless of the current FSM state. The `always_ff` for RX flags runs every cycle independent of state. So even if the partner sends a message before we reach the state that checks for it, the flag is already set and waiting.

In Approach A specifically:
- Each side sends first (`REQ_SEND`) then waits (`REQ_WAIT`).
- Neither side waits before sending, so there is no circular dependency.

---

## 8. Final Decision

**Approach A (Split, 4 Sub-States) was chosen** because:

1. **Lower HW cost** — 1 fewer FF + simpler combinational logic
2. **Easier debug** — clear per-state waveform visibility
3. **Consistent** with the handshake pattern used across all other MBINIT sub-states (REPAIRCLK, REPAIRVAL, REVERSALMB)
4. **No combinational feedback** — cleaner timing path
5. Both approaches are equally safe (no deadlock risk in either)
