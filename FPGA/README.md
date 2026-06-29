# UCIe 3.0 PHY — FPGA Bring-up

This folder is the **FPGA target** of the UCIe PHY: the digital PHY packaged as a
self-loopback IP, the AXI-Stream / GPIO shells that connect it to a Zynq
UltraScale+ processing system, the bare-metal C driver + test application, the
timing constraints, and the lint report.

The idea: the analog hard macros (PLL, SerDes, tri-state) **cannot** map to FPGA
fabric, so they are stripped. What remains is the **whole digital PHY**
(MainBand scramble/descramble + framing, Sideband packetization + register
access, RDI SM, LTSM training) wired into **self-loopback** — every TX boundary
folded back onto its own RX boundary. A processor then configures the PHY,
walks it to **ACTIVE**, streams data through the MainBand, and compares TX vs RX.

> This is the *implementation* README (real files + results). The higher-level
> Vivado IP-Integrator architecture/planning write-up lives in
> [`docs/FPGA/README.md`](../docs/FPGA/README.md). Where the two differ, this one
> reflects what is actually built: the sideband uses an **AXI-Stream + FIFO**
> path (not an AXI4-Lite bridge), and RDI uses the **PS EMIO GPIO** (not AXI GPIO).

---

## Directory layout

| Path | Contents |
|------|----------|
| `rtl/` | FPGA-target RTL: loopback cores, AXI-Stream bridges, synthesizable top wrapper. |
| `src/` | Bare-metal C: driver (`ucie_driver.*`), config (`ucie_config.h`), test app (`main.c`). |
| `tb/` | Simulation testbenches for the two loopback cores. |
| `constraints/` | `UCIe_FPGA_loopback.xdc` — clock defs, CDC groups, clk-detector false-path. |
| `reports/` | Verilator lint report. |
| `rtl/UCIe_FPGA_top_wrapper.f` | Filelist for the synthesizable top (use for lint / synth). |

The packaged block design and bitstream live outside this folder, under
[`vivado/UCIe_PHY/`](../vivado/UCIe_PHY/); the Vitis platform + application are
under [`vitis_ucie/`](../vitis_ucie/).

---

## RTL hierarchy

```
UCIe_FPGA_top_wrapper                         (synthesizable BD top)
│
├── axis_slave_to_mb_tx     S_AXIS_MBTX  ─▶ lp_data/lp_irdy/lp_valid  (pl_trdy→TREADY)
├── axis_master_from_mb_rx  pl_data/pl_valid ─▶ M_AXIS_MBRX  (+overflow, FIFO)
├── axis_slave_to_sb_cfg    S_AXIS_SBTX  ─▶ lp_cfg/lp_cfg_vld  (downstream credits)
├── axis_master_from_sb_cfg pl_cfg/pl_cfg_vld ─▶ M_AXIS_SBRX  (+overflow, FIFO, credits)
│
└── UCIe_FPGA_loopback
    ├── unit_clk_gate        (`ifdef FPGA → BUFGCE; else pass-through)
    └── digital_ucie_loopback
        └── digital_ucie  (the full digital PHY) wired in self-loopback
```

### The two loopback cores
- **`digital_ucie_loopback.sv`** — instantiates `digital_ucie` and folds its
  parallel boundaries back on themselves (no SerDes):
  - MainBand: `tx_reversal out → lfsr_rx in`, `valid_word → valid_frame_data`,
    `tckp/tckn/ttrk_pre → RCKP/RCKN/RTRK`.
  - Sideband: `sb_ser_data/vld_send → sb_des_data/vld_rcvd`, `sb_ser_rdy = 1`.
  Because TX and RX share the **same word clock**, there is no ser/des latency, so
  the RX descrambler (`lfsr_rx`) stays lock-step with `lfsr_tx` word-for-word.
- **`UCIe_FPGA_loopback.v`** — wraps `digital_ucie_loopback` and re-creates the
  MainBand word-clock gate that the (removed) hard macro used to provide:
  under `` `ifdef FPGA `` the core's `o_mb_lclk_g` enable drives a **BUFGCE**
  (global, glitch-free) so `gated_lclk` is generated on-chip; otherwise the
  external `gated_lclk` is passed through (simulation / ASIC).

### Host-facing interfaces (`UCIe_FPGA_top_wrapper`)
| Interface | Type | Width | Purpose |
|-----------|------|-------|---------|
| `s_axis_mb_tx_*` | AXI-Stream slave | 512-bit `TDATA` (=8·N_BYTES) | flit data in (DMA MM2S) |
| `m_axis_mb_rx_*` | AXI-Stream master | 512-bit `TDATA` | flit data out (DMA S2MM); `o_mb_rx_overflow` |
| `s_axis_sb_tx_*` | AXI-Stream slave | 32-bit | sideband config requests in |
| `m_axis_sb_rx_*` | AXI-Stream master | 32-bit | sideband completions out; `o_sb_rx_overflow` |
| `lp_*` / `pl_*` | flat ports | — | RDI control/status (→ PS EMIO GPIO) |

`Xilinx X_INTERFACE_INFO/PARAMETER` attributes on `lclk`/`rst_n` associate every
AXIS interface with the clock so IP Integrator tracks the real `pl_clk0`
frequency (fixes BD freq-mismatch and "not associated to any clock" warnings).

---

## Clocking

The design runs **fully synchronous**: the top wrapper ties `clk_sb = lclk` and
feeds `lclk` as `gated_lclk` and `pll_clk` into the core. The constraints file
documents the *modelled* periods (mirroring the sim TB):

| Clock | Period | Freq | Role |
|-------|--------|------|------|
| `pll_clk` | 0.5 ns | 2000 MHz | clk-pattern gen/detect (analog bit-rate model) |
| `lclk` / `gated_lclk` | 8.0 ns | 125 MHz | MainBand word clock (= analog pll/16) |
| `clk_sb` | 10.0 ns | 100 MHz | Sideband parallel clock (= analog sb_pll/8) |

> ⚠️ `pll_clk @ 2 GHz` is **not** achievable in FPGA fabric. For real hardware,
> lower it and re-scale the clk-pattern gen/detector counters. The 2 GHz value is
> kept only so simulation numbers match. With `` `define FPGA ``, `gated_lclk` is
> generated by the on-chip BUFGCE and stays in the `lclk` domain (no `create_clock`
> needed); `pll_clk`/`clk_sb` are async and CDC is handled by FIFOs/handshakes.
> The RX clock-detector sample regs are marked `ASYNC_REG` + false-path.

---

## Software (`src/`)

A bare-metal app for the Zynq US+ PS. The driver (`ucie_driver.c/.h`) wraps three
hardware channels:

| Channel | Xilinx IP / driver | Use |
|---------|--------------------|-----|
| MainBand data | **AXI DMA** (`XAxiDma`) | bulk 512-bit flit DMA TX↔RX through BRAM |
| Sideband config | **AXI Stream FIFO** (`XLlFifo`) | register read/write packets + completions |
| RDI control/status | **PS EMIO GPIO** (`XGpioPs`, bank 3) | drive `lp_*`, observe `pl_*` |

**Address map** (from the Vivado Address Editor; single source of truth in
`ucie_driver.h`):

| Block | Base | Size |
|-------|------|------|
| AXI DMA `S_AXI_LITE` | `0xA000_0000` | 64 K |
| AXI Stream FIFO `S_AXI` | `0xA001_0000` | 64 K |
| dst BRAM (MB RX) | `0xA002_0000` | 8 K |
| src BRAM (MB TX) | `0xA002_2000` | 8 K |
| PS EMIO GPIO (bank 3) | `0xFF0A_0000` | fixed |

**RDI EMIO bit map** — output bits `[7:0]` drive `lp_*` (state_req[3:0], clk_ack,
wake_req, stallack, linkerror); input bits read `pl_*` (clk_req, stallreq,
wake_ack, trainerror, inband_pres, phyinrecenter, state_sts[9:6],
max_speedmode, speedmode, lnk_cfg) plus the two RX-overflow flags.

**Sideband register access** is encoded as 32-bit AXIS packets using the SB
opcodes (`SB_OPC_32_CFG_READ/WRITE`, `64_*`, completions); the register offsets
(`REG_UCIE_LINK_CTRL`, `REG_PHY_CONTROL`, `REG_TRAIN_SETUP3/4`,
`REG_UCIE_LINK_STATUS`) and their bit-field macros are in `ucie_driver.h` and map
to the [Reg_File](../rtl/common/Reg_File_README.md).

**`main.c` bring-up sequence:**
1. `Ucie_Init` — DMA + sideband FIFO + EMIO GPIO.
2. `Ucie_StartTraining` — program PHY regs + assert *Start UCIe Link Training* over sideband.
3. `Ucie_BringUpActive` — drive RDI via GPIO, poll until **ACTIVE** (2 s budget).
4. Read back negotiated width/speed from `LINK_STATUS` (0x14).
5. (aux) sideband remote-message loopback — treated as a *warning* if it fails (not wired in this self-loopback config).
6. MainBand DMA loopback: fill src BRAM → DMA → loopback → DMA → dst BRAM.
7. Compare TX vs RX → **PASS/FAIL**.

A lightweight event monitor (`Ucie_Dbg_Poll/Mark`) prints a decoded one-liner
whenever the RDI status / FIFO occupancy changes, so you can see exactly where
bring-up stalls.

---

## Simulation & build

| Listfile (`sim/listfiles/`) | Top | Scope |
|------------------------------|-----|-------|
| `digital_ucie_loopback.f` | `digital_ucie_loopback_tb` | digital core in loopback |
| `ucie_phy_loopback.f` | `ucie_phy_loopback_tb` | full PHY (with analog models) in loopback |
| `FPGA/rtl/UCIe_FPGA_top_wrapper.f` | `UCIe_FPGA_top_wrapper` | synthesizable BD top (lint/synth) |

Testbenches live in `tb/`. Run a sim with `make run CONFIG=digital_ucie_loopback
TOP=digital_ucie_loopback_tb`.

---

## Results

- **Lint (Verilator 5.046):** clean of correctness defects. Remaining items are
  cosmetic/style only — `DECLFILENAME` (module≠filename), `PINCONNECTEMPTY`
  (intentionally unused FIFO flags), `UNUSEDPARAM`, `BLKSEQ` (single-writer regs
  using `=`), `PROCASSINIT`. The report's own verdict:
  *"CORRECTNESS RISK: none of the above changes RTL behavior."* The only real
  defect it surfaced (a missing `PHYRETRAIN` file) is fixed. See
  [`reports/UCIe_FPGA_loopback_verilator_lint.rpt`](reports/UCIe_FPGA_loopback_verilator_lint.rpt).
- **Digital loopback:** the stripped digital PHY trains and passes in self-loopback.
- **Vivado/Zynq:** the block design (wrapper + PS, EMIO GPIO for RDI, DMA/FIFO
  datapath, clk-detector hold false-path) builds to a **clean bitstream** —
  see [`vivado/UCIe_PHY/`](../vivado/UCIe_PHY/).
- **On-target:** `main.c` walks Init → train → ACTIVE → DMA loopback → compare and
  prints `TEST RESULT: PASS` when TX matches RX.

---

## Notes / caveats

- `pll_clk` at 2 GHz must be re-scaled for real silicon (see Clocking).
- The sideband **remote-message** loopback is auxiliary and not wired in this
  self-loopback config; a failure there is a warning, not a test failure.
- Reserved register bits read back as `1` in this implementation — interpret per
  the [Reg_File map](../rtl/common/Reg_File_README.md), not the readback.
