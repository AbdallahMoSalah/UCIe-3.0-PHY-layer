# MainBand (MB) — UCIe 3.0 Physical Layer Data Path

The **Main-Band** is the high-speed parallel data interface of the UCIe PHY. It
carries the actual protocol traffic (the flits handed down by the adapter) across
the die-to-die link, together with the forwarded clock, the valid framing lane,
and the on-die training/comparison machinery used to bring the link up and keep
it healthy.

This directory is the **canonical MainBand** (it replaces the older `MainBand`
tree that used the pre-redesign blocks). It is split into a **digital** half and
an **analog hard-macro** half so the same RTL can be retargeted between an ASIC
flow (real SerDes/PLL) and an FPGA flow (behavioural models).

---

## Top-level structure

| File | Role |
|------|------|
| `digital_mb.sv` | Digital half — all the synthesizable processing (mapper, LFSR, reversal, comparators, clock-pattern logic). |
| `mainband_analog_hard_macro.sv` | Analog half — PLL/clocking, SerDes (serializer/deserializer), tri-state lane buffers. |
| `mainband_ltsm_interface.sv` | Glue that wires the MB into the LTSM training state machine; force-controls deser enables during ACTIVE. Wraps `unit_mb_die`. |
| `Integration steps/unit_mb_die.sv` | A complete single-die MB (TX + RX), used as the building block for die-to-die loopback. |

The boundary between the two halves: the **hard macro owns the PLL, the
serializers/deserializers, and the tri-state pins**; the **digital half owns all
data processing**. Lane reversal lives on the digital side (parallel array
reversal right after the TX LFSR), and the RX clock detector samples the raw
forwarded clock/track directly.

---

## TX data path (`tx/`)

```
lp_data ──▶ mapper ──▶ lfsr_tx ──▶ lane-reversal(array) ──▶ [hard-macro serializers] ──▶ pins
                                  valid_tx ───────────────▶ [valid serializer]
                                  clk_pattern_gen_tx ─────▶ [tri-state clk/track pins]
```

| Block | File | Function |
|-------|------|----------|
| Mapper | `unit_mapper.sv` | Maps the raw protocol byte bus (64 B) onto the per-lane words; handles `lp_irdy`/`lp_valid`/`pl_trdy` handshake. |
| LFSR TX | `unit_lfsr_tx.sv` | Per-lane scrambler (leap-32 of the reference serial LFSR) and per-lane training-ID generator. |
| Lane reversal | `unit_mb_tx_reversal.sv`, `unit_mb_tx_reversal_array.sv` | Optional physical lane reversal applied in parallel before serialization. |
| Valid TX | `unit_valid_tx.sv` | Drives the valid-framing lane (canonical pattern `0x0F0F0F0F`) and the 32-cycle TVLD burst. |
| Serializer | `unit_mb_serializer.sv` | Parallel→serial (1-PLL latency); lives logically with the hard macro. |
| Clock-pattern gen | `unit_clk_pattern_gen_tx.sv` | 128-UI clock burst and continuous embedded-clock mode for the forwarded clock. |
| Clocking | `unit_mb_pll.sv`, `unit_clkdiv.sv`, `unit_clk_gate.sv` | PLL model, clock divider, and gate for the local/PLL clocks. |

## RX data path (`rx/`)

```
pins ──▶ [hard-macro deserializers] ──▶ lfsr_rx ──▶ demapper ──▶ recovered protocol bus
                                       pattern_comparator   (training-pattern check)
                                       valid_deserializer + valid_frame_detector + valid_comparator
                                       clk_pattern_detector_rx (samples raw forwarded clk/track)
```

| Block | File | Function |
|-------|------|----------|
| Data deserializer | `unit_data_deserializer.sv` | Serial→parallel per lane; samples on the quarter-delayed forwarded RX clock. |
| LFSR RX | `unit_lfsr_rx.sv` | Per-lane descrambler; must be reset between training phases. |
| Demapper | `unit_demapper.sv` | Faithful inverse of the mapper; recovers the protocol byte bus. |
| Pattern comparator | `unit_mb_pattern_comparator.sv` | Compares received training pattern vs expected; per-lane sticky **or** aggregate (OR-of-lanes-per-UI) mode, lane mask, configurable thresholds and iteration count. |
| Valid path | `unit_valid_deserializer.sv`, `unit_valid_frame_detector.sv`, `unit_valid_comparator.sv` | Recovers and validates the valid-framing lane (16-consecutive or threshold mode); `vcmp_done` feeds back into the hard-macro valid deserializer. |
| Clock detector | `unit_clk_pattern_detector_rx.sv` | Detects the forwarded clock pattern on the raw RX clk/track pins. |

---

## Features supported

- **x16 / x8 module widths** with run-time **width degrade** (TX and RX width-degrade codes).
- **Physical lane reversal** (enable-controlled, applied in parallel on TX).
- **Scrambling** via per-lane LFSR (leap-32 implementation; descrambled on RX).
- **Per-lane training-ID** and **LFSR** training pattern modes.
- **Pattern comparison** with two modes — per-lane sticky and aggregate — plus
  lane masking, per-lane / aggregate error thresholds, and an iteration counter.
- **Valid-lane framing** with comparator (consecutive-match or threshold).
- **Forwarded-clock** generation/detection: 128-UI burst and continuous
  embedded-clock modes.
- **Digital/analog split** so the same digital RTL drives either a real hard
  macro (ASIC) or behavioural models (FPGA / simulation).

---

## Parameters (`digital_mb`)

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `DATA_WIDTH` | 32 | Parallel lane-word width. |
| `NUM_LANES` | 16 | Number of data lanes. |
| `N_BYTES` | 64 | Byte width of the raw protocol bus. |
| `VALID_PATTERN` | `32'h0F0F0F0F` | Canonical valid-lane pattern. |
| `RX_ALIGN_DELAY` | 2 | RX alignment delay. |

---

## Simulation

Key listfiles (under `sim/listfiles/`, run with `make run CONFIG=<name> TOP=<tb>`):

| CONFIG | What it exercises |
|--------|-------------------|
| `integration_mb_die2die_mainband` | Full die-to-die MB loopback (`mb_die` wrapper), 5×5×3 parity sweep. |
| `integration_mb_train_seq` | Training-sequence loopback. |
| `integration_tx_deser` / `integration_tx_demap` | TX→deserializer and TX→demapper loopbacks. |
| `unit_mb_path` / `unit_mb_framed_path` | mapper→lfsr→ser→des→lfsr→demapper path tests. |

> **Note:** the MainBand testbenches now live under `tb/` (unit TBs in
> `tb/unit/mainband/`, integration TBs in `tb/integration/MAIN_BAND/`), not inside
> this RTL tree.
