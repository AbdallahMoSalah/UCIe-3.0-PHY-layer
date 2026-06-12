# UCIe Main-Band Lane Reversal & Width Degradation Data Flow

This document details the end-to-end data flow from the transmitter (TX) Mapper to the receiver (RX) Demapper. It covers all permutations of lane degradation (x16, x8, x4) both with and without lane reversal enabled.

---

## 1. Data Flow Architecture

The data path flows through the following stages:

```mermaid
graph TD
    A["Raw Flit (512-bit)"] --> B["unit_mapper (TX)"]
    B -->|mapper_lane[15:0]| C["unit_lfsr_tx (Straight Mode)"]
    C -->|lfsr_lane[15:0]| D["serializers (16x)"]
    D -->|TD_P_int[15:0]| E["unit_mb_tx_reversal (TX Wrapper)"]
    E -->|o_TD_P[15:0]| F["Reversed Channel (Routing)"]
    F -->|i_RD_P[15:0]| G["deserializers (16x)"]
    G -->|Parallel Words| H["unit_lfsr_rx (Straight Mode)"]
    H -->|Logical Lanes| I["unit_demapper (RX)"]
    I --> J["Recovered Flit (512-bit)"]
```

### Key Principles of the Architecture:
1. **TX-Side Lane Reversal (`unit_mb_tx_reversal`)**: Pre-reverses the serial outputs before they leave the TX die:
   $$\text{o\_TD\_P}[i] = \text{i\_reversal\_en} ? \text{TD\_P\_int}[15-i] : \text{TD\_P\_int}[i]$$
2. **Channel Reversal**: Performs another physical reversal during transmission:
   $$\text{i\_RD\_P}[j] = \text{reverse\_lanes} ? \text{o\_TD\_P}[15-j] : \text{o\_TD\_P}[j]$$
3. **Double Reversal Cancellation**: When both are enabled (`1`), they cancel each other out:
   $$\text{i\_RD\_P}[j] = \text{TD\_P\_int}[15 - (15-j)] = \text{TD\_P\_int}[j]$$
4. **Straight IP Operations**: Since the reversal is completely canceled out at the physical boundary, both TX and RX IP blocks (`unit_lfsr_tx` and `unit_lfsr_rx`) operate in straight/unreversed mode. This ensures that the seed for logical lane $i$ matches the descrambler seed on physical/logical lane $i$ at the RX.

---

## 2. End-to-End Traces

### Case 1: x16 Mode — No Reversal
* **Config**: `width_deg = 3'b011` (x16), `i_reversal_en = 0`, `reverse_lanes = 0`

| Stage / Lane | 0 | 1 | ... | 14 | 15 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Mapper Output** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **TX LFSR Seed** | Seed 0 | Seed 1 | ... | Seed 14 | Seed 15 |
| **Serializer Out (`TD_P_int`)** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **Reversal Out (`o_TD_P`)** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **Channel Out (`i_RD_P`)** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **RX LFSR Seed** | Seed 0 | Seed 1 | ... | Seed 14 | Seed 15 |
| **Demapper Input** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **Status** | **PASS** (Seeds and data lanes align perfectly) |

---

### Case 2: x16 Mode — With Reversal
* **Config**: `width_deg = 3'b011` (x16), `i_reversal_en = 1`, `reverse_lanes = 1`

| Stage / Lane | 0 | 1 | ... | 14 | 15 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Mapper Output** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **TX LFSR Seed** | Seed 0 | Seed 1 | ... | Seed 14 | Seed 15 |
| **Serializer Out (`TD_P_int`)** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **Reversal Out (`o_TD_P`)** | Lane 15 | Lane 14 | ... | Lane 1 | Lane 0 |
| **Channel Out (`i_RD_P`)** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **RX LFSR Seed** | Seed 0 | Seed 1 | ... | Seed 14 | Seed 15 |
| **Demapper Input** | Lane 0 | Lane 1 | ... | Lane 14 | Lane 15 |
| **Status** | **PASS** (Reversal module pre-swaps, channel restores straight order) |

---

### Case 3: x8 Low Mode (Lanes 0-7) — With Reversal
* **Config**: `width_deg = 3'b001` (x8 Low), `i_reversal_en = 1`, `reverse_lanes = 1`

| Stage / Lane | 0 | 1 | ... | 7 | 8 | ... | 15 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Mapper Output** | Lane 0 | Lane 1 | ... | Lane 7 | Idle (0) | ... | Idle (0) |
| **TX LFSR Seed** | Seed 0 | Seed 1 | ... | Seed 7 | - | ... | - |
| **Serializer Out (`TD_P_int`)** | Lane 0 | Lane 1 | ... | Lane 7 | Idle (0) | ... | Idle (0) |
| **Reversal Out (`o_TD_P`)** | Idle (0) | Idle (0) | ... | Idle (0) | Lane 7 | ... | Lane 0 |
| **Channel Out (`i_RD_P`)** | Lane 0 | Lane 1 | ... | Lane 7 | Idle (0) | ... | Idle (0) |
| **RX LFSR Seed** | Seed 0 | Seed 1 | ... | Seed 7 | - | ... | - |
| **Demapper Input** | Lane 0 | Lane 1 | ... | Lane 7 | Idle (0) | ... | Idle (0) |
| **Status** | **PASS** (Pre-reversal shifted active lanes to physical 8-15; channel restored to 0-7) |

---

### Case 4: x8 High Mode (Lanes 8-15) — With Reversal
* **Config**: `width_deg = 3'b010` (x8 High), `i_reversal_en = 1`, `reverse_lanes = 1`

| Stage / Lane | 0 | ... | 7 | 8 | 9 | ... | 15 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Mapper Output** | Idle (0) | ... | Idle (0) | Lane 8 | Lane 9 | ... | Lane 15 |
| **TX LFSR Seed** | - | ... | - | Seed 8 | Seed 9 | ... | Seed 15 |
| **Serializer Out (`TD_P_int`)** | Idle (0) | ... | Idle (0) | Lane 8 | Lane 9 | ... | Lane 15 |
| **Reversal Out (`o_TD_P`)** | Lane 15 | ... | Lane 8 | Idle (0) | Idle (0) | ... | Idle (0) |
| **Channel Out (`i_RD_P`)** | Idle (0) | ... | Idle (0) | Lane 8 | Lane 9 | ... | Lane 15 |
| **RX LFSR Seed** | - | ... | - | Seed 8 | Seed 9 | ... | Seed 15 |
| **Demapper Input** | Idle (0) | ... | Idle (0) | Lane 8 | Lane 9 | ... | Lane 15 |
| **Status** | **PASS** (Active lanes 8-15 shifted to 0-7 on TX pins, then returned to 8-15 at RX pins) |

---

### Case 5: x4 Low Mode (Lanes 0-3) — With Reversal
* **Config**: `width_deg = 3'b100` (x4 Low), `i_reversal_en = 1`, `reverse_lanes = 1`

| Stage / Lane | 0 | 1 | 2 | 3 | 4 | ... | 12 | 13 | 14 | 15 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Mapper Output** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Idle | ... | Idle | Idle | Idle | Idle |
| **TX LFSR Seed** | Seed 0 | Seed 1 | Seed 2 | Seed 3 | - | ... | - | - | - | - |
| **Serializer Out (`TD_P_int`)** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Idle | ... | Idle | Idle | Idle | Idle |
| **Reversal Out (`o_TD_P`)** | Idle | Idle | Idle | Idle | Idle | ... | Lane 3 | Lane 2 | Lane 1 | Lane 0 |
| **Channel Out (`i_RD_P`)** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Idle | ... | Idle | Idle | Idle | Idle |
| **RX LFSR Seed** | Seed 0 | Seed 1 | Seed 2 | Seed 3 | - | ... | - | - | - | - |
| **Demapper Input** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Idle | ... | Idle | Idle | Idle | Idle |
| **Status** | **PASS** (Active lanes 0-3 pre-swapped to TX 12-15; channel restored to RX 0-3) |

---

### Case 6: x4 Mid-Low Mode (Lanes 4-7) — With Reversal
* **Config**: `width_deg = 3'b101` (x4 Mid-Low), `i_reversal_en = 1`, `reverse_lanes = 1`

| Stage / Lane | 0 | ... | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | ... | 15 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Mapper Output** | Idle | ... | Idle | Lane 4 | Lane 5 | Lane 6 | Lane 7 | Idle | Idle | Idle | Idle | Idle | ... | Idle |
| **TX LFSR Seed** | - | ... | - | Seed 4 | Seed 5 | Seed 6 | Seed 7 | - | - | - | - | - | ... | - |
| **Serializer Out (`TD_P_int`)** | Idle | ... | Idle | Lane 4 | Lane 5 | Lane 6 | Lane 7 | Idle | Idle | Idle | Idle | Idle | ... | Idle |
| **Reversal Out (`o_TD_P`)** | Idle | ... | Idle | Idle | Idle | Idle | Idle | Lane 7 | Lane 6 | Lane 5 | Lane 4 | Idle | ... | Idle |
| **Channel Out (`i_RD_P`)** | Idle | ... | Idle | Lane 4 | Lane 5 | Lane 6 | Lane 7 | Idle | Idle | Idle | Idle | Idle | ... | Idle |
| **RX LFSR Seed** | - | ... | - | Seed 4 | Seed 5 | Seed 6 | Seed 7 | - | - | - | - | - | ... | - |
| **Demapper Input** | Idle | ... | Idle | Lane 4 | Lane 5 | Lane 6 | Lane 7 | Idle | Idle | Idle | Idle | Idle | ... | Idle |
| **Status** | **PASS** (Active lanes 4-7 pre-swapped to TX 8-11; channel restored to RX 4-7) |

---

### Case 7: Asymmetric x8 Low / x4 Low — With Reversal
* **Config**: Link 0->1 TX is `3'b001` (x8 Low), Link 0->1 RX is `3'b100` (x4 Low), `i_reversal_en = 1`, `reverse_lanes = 1`
* **Masking**: As RX is in x4 mode (lanes 0-3 active) and TX is in x8 mode (lanes 0-7 active), the testbench calculates:
  $$\text{Mask} = \sim(\text{Active}(TX) \ \& \ \text{Active}(RX)) = \sim(\text{h00FF} \ \& \ \text{h000F}) = \text{hFFF0}$$
  Only lanes 0-3 are validated during pattern check. Other lanes are masked and ignored.

| Stage / Lane | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | ... | 15 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Mapper Output** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Lane 4 | Lane 5 | Lane 6 | Lane 7 | Idle | ... | Idle |
| **TX LFSR Seed** | Seed 0 | Seed 1 | Seed 2 | Seed 3 | Seed 4 | Seed 5 | Seed 6 | Seed 7 | - | ... | - |
| **Serializer Out (`TD_P_int`)** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Lane 4 | Lane 5 | Lane 6 | Lane 7 | Idle | ... | Idle |
| **Reversal Out (`o_TD_P`)** | Idle | ... | Idle | Lane 7 | Lane 6 | Lane 5 | Lane 4 | Lane 3 | Lane 2 | Lane 1 | Lane 0 |
| **Channel Out (`i_RD_P`)** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Lane 4 | Lane 5 | Lane 6 | Lane 7 | Idle | ... | Idle |
| **RX Deserializer Out** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Lane 4 | Lane 5 | Lane 6 | Lane 7 | Idle | ... | Idle |
| **RX LFSR (x4 mode)** | Seed 0 | Seed 1 | Seed 2 | Seed 3 | - | - | - | - | - | ... | - |
| **Demapper In (x4 mode)** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | - | - | - | - | - | ... | - |
| **Status** | **PASS** (Lanes 0-3 align and train. Lanes 4-7 are ignored by RX and masked by TB) |

---

### Case 8: x4 Low — Reversed with Reversal DISABLED (Failure Trace)
* **Config**: `width_deg = 3'b100` (x4 Low), `i_reversal_en = 0`, `reverse_lanes = 1`

| Stage / Lane | 0 | 1 | 2 | 3 | 4 | ... | 12 | 13 | 14 | 15 |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Mapper Output** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Idle | ... | Idle | Idle | Idle | Idle |
| **TX LFSR Seed** | Seed 0 | Seed 1 | Seed 2 | Seed 3 | - | ... | - | - | - | - |
| **Serializer Out (`TD_P_int`)** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Idle | ... | Idle | Idle | Idle | Idle |
| **Reversal Out (`o_TD_P`)** | Lane 0 | Lane 1 | Lane 2 | Lane 3 | Idle | ... | Idle | Idle | Idle | Idle |
| **Channel Out (`i_RD_P`)** | Idle | Idle | Idle | Idle | Idle | ... | Lane 3 | Lane 2 | Lane 1 | Lane 0 |
| **RX LFSR (x4 mode)** | Idle | Idle | Idle | Idle | - | ... | - | - | - | - |
| **Demapper Input** | **NO SIG** | **NO SIG** | **NO SIG** | **NO SIG** | - | ... | - | - | - | - |
| **Status** | **FAIL** (Lanes arrive at physical 12-15; RX listens only to 0-3. LFSR comparator fails) |
