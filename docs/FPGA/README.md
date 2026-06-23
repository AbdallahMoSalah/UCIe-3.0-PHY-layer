# UCIe PHY — FPGA Bring-up (Vivado IP Integrator Architecture)

**Status:** preliminary / planning. This document describes the intended Vivado
*IP Integrator* (Block Design) for testing the **digital** part of the UCIe PHY
as an IP inside an embedded system (HW/SW co-design), using **self-loopback**.
No analog hard macros (PLL, SerDes, tri-state) are present on the FPGA.

> Scope: this is an architecture sketch to build the block design from. The
> custom IP top and the two MainBand AXI-Stream adapters are **not written yet**
> (see [TODO RTL](#5-rtl-still-to-write)). The AXI4-Lite sideband bridge already
> exists: [`FPGA/rtl/axi4lite_sb_cfg_bridge.sv`](../../FPGA/rtl/axi4lite_sb_cfg_bridge.sv).

---

## 1. Goal

Let a processor (Zynq PS / MicroBlaze) running C software:

1. **Configure** the PHY by reading/writing the Sideband register file (ctrl/config).
2. **Drive the RDI state machine** at runtime to walk the training handshakes.
3. **Stream MainBand flit data in**, let the digital datapath loop it back, and
   **capture the data out** to compare TX vs RX (digital integrity check).

The DUT is [`digital_ucie_loopback`](../../FPGA/rtl/digital_ucie_loopback.sv),
which folds the MainBand and Sideband TX boundaries back onto their own RX
boundaries — so the whole digital path (scramble/descramble, framing, RDI/LTSM,
sideband packetization) is exercised with **no SerDes**.

---

## 2. Three host-facing interfaces (the mentor's three "things")

| PHY face | Direction | AXI flavour | Why |
|---|---|---|---|
| **MainBand TX** (`lp_data`/`lp_irdy`/`lp_valid`/`pl_trdy`) | host → PHY | **AXI4-Stream slave** | bulk flit data pushed by DMA |
| **MainBand RX** (`pl_data`/`pl_valid`) | PHY → host | **AXI4-Stream master** | captured flit data into DDR/BRAM |
| **Sideband cfg** (`lp_cfg`/`pl_cfg` + credits) | host ↔ PHY | **AXI4-Lite slave** | register read/write = addressed request→response |
| **RDI SM** (`lp_state_req`, `pl_state_sts`, handshakes) | host ↔ PHY | **AXI GPIO** | poked/observed by SW during training |

Rationale for AXI4-Lite (not Stream) on the sideband: a register access is a
single addressed **request that returns a completion** (ack for write, data for
read). AXI4-Lite carries that round-trip inside one transaction (`RDATA`/`BRESP`),
while two streams would force software to correlate request and completion by
hand. The bridge hides the SB packetization and credit handshake.

---

## 3. Block Design

```
                          PS clock (e.g. 100 MHz)
                                 │
   ┌─────────────────────────────────────────────────────────────────────────┐
   │                         Zynq US+ MPSoC  /  MicroBlaze                     │
   │   M_AXI (control) ───┐                       ┌──── S_AXI_HP (to DDR)      │
   └──────────────────────┼───────────────────────┼───────────────────────────┘
                          │                        │
                  ┌───────▼────────┐       ┌───────▼────────┐
                  │ AXI SmartConn. │       │ AXI SmartConn. │
                  │   (control)    │       │   (memory)     │
                  └─┬───┬───┬───┬──┘       └───────▲────────┘
        AXI4-Lite   │   │   │   │                  │ MM2S read / S2MM write
        ┌───────────┘   │   │   └──────────┐       │
        │           ┌───┘   └───┐          │   ┌───┴────────┐
        ▼           ▼           ▼          ▼   │  AXI DMA   │
  ┌──────────┐ ┌─────────┐ ┌─────────┐ ┌──────┤  MM2S      │
  │ AXI GPIO │ │ AXI GPIO│ │  (dbg)  │ │ DMA  │  S2MM      │
  │  RDI in  │ │ RDI out │ │ VIO/ILA │ │ ctrl └──┬──────┬──┘
  └────┬─────┘ └────┬────┘ └─────────┘ └─────────┘      │
       │ rdi_*      │ rdi_*           M_AXIS_MM2S │      │ S_AXIS_S2MM
       │ (drive)    │ (observe)      (512-bit)    ▼      ▲ (512-bit)
       │            │                       ┌─────┴──────┴───────────────┐
       │            │                       │      ucie_phy_ip  (custom) │
       │            │   S_AXI_SB (AXI4-Lite)│                            │
       └────────────┴───────────────────────►  axi4lite_sb_cfg_bridge    │
                                            │        │  lp_cfg/pl_cfg     │
                                            │        ▼                    │
                                            │  S_AXIS_MBTX → mb_tx_adapter│
                                            │        │   lp_data/irdy/vld │
                                            │        ▼                    │
                                            │   digital_ucie_loopback     │
                                            │        │  pl_data/pl_valid  │
                                            │        ▼                    │
                                            │  mb_rx_adapter → M_AXIS_MBRX│
                                            │  rdi_* flat ports ◄─────────┤
                                            └──────────────▲──────────────┘
                                                           │ clocks
                                                  ┌────────┴────────┐
                                                  │ Clocking Wizard │  lclk, gated_lclk,
                                                  │     (MMCM)      │  pll_clk, clk_sb
                                                  └─────────────────┘
                          Processor System Reset (per clock domain)
```

---

## 4. Blocks to instantiate in IP Integrator

| # | Vivado IP | Role |
|---|---|---|
| 1 | **Zynq UltraScale+ MPSoC** (or Zynq-7000 / MicroBlaze) | host CPU running the test SW; provides AXI master + DDR slave port |
| 2 | **AXI SmartConnect** (control) | routes CPU `M_AXI` to SB bridge, DMA ctrl, GPIOs |
| 3 | **AXI SmartConnect** (memory) | routes DMA master to PS `S_AXI_HP` → DDR |
| 4 | **AXI DMA** | `MM2S` → `S_AXIS_MBTX`; `S2MM` ← `M_AXIS_MBRX`. Width = **512** |
| 5 | **AXI GPIO #0** (RDI control) | CPU drives `lp_state_req[3:0]`, `lp_clk_ack`, `lp_wake_req`, `lp_stallack`, `lp_linkerror` |
| 6 | **AXI GPIO #1** (RDI status) | CPU observes `pl_state_sts[3:0]`, `pl_clk_req`, `pl_stallreq`, `pl_wake_ack`, `pl_trainerror`, `pl_inband_pres`, `pl_phyinrecenter`, `pl_speedmode[2:0]`, `pl_lnk_cfg[2:0]`, `pl_max_speedmode` |
| 7 | **Clocking Wizard (MMCM)** | one reference clock → `lclk`, `gated_lclk`, `pll_clk`, `clk_sb` (replaces analog PLLs) |
| 8 | **Processor System Reset** | synchronized resets per clock domain |
| 9 | **ucie_phy_ip** (custom, *to package*) | the DUT + bridge + MB adapters (Section 5) |
| 10 | **ILA / VIO** *(optional, debug)* | observe internal RDI/LTSM/sideband signals on hardware |

### Custom IP `ucie_phy_ip` — external interfaces

| Interface | Type | Notes |
|---|---|---|
| `S_AXI_SB` | AXI4-Lite slave | sideband register access (via `axi4lite_sb_cfg_bridge`) |
| `S_AXIS_MBTX` | AXI4-Stream slave | `TDATA[511:0]` flit in |
| `M_AXIS_MBRX` | AXI4-Stream master | `TDATA[511:0]` flit out |
| `rdi_ctrl_i[*]` / `rdi_stat_o[*]` | flat ports | wired to AXI GPIO #0 / #1 |
| `lclk`, `gated_lclk`, `pll_clk`, `clk_sb`, `aclk`, `aresetn` | clocks/reset | from Clocking Wizard + Proc Sys Reset |

---

## 5. RTL still to write

The bridge exists; these wrappers do **not** yet:

1. **`mb_tx_axis_adapter`** — AXI4-Stream slave → `lp_data[511:0]` / `lp_irdy` / `lp_valid`,
   with `pl_trdy` driving `TREADY`. (flit handshake ↔ stream handshake)
2. **`mb_rx_axis_adapter`** — `pl_data[511:0]` / `pl_valid` → AXI4-Stream master
   (`TVALID`/`TDATA`, optional `TLAST` per flit/packet).
3. **`ucie_phy_ip` top** — instantiates `digital_ucie_loopback` +
   `axi4lite_sb_cfg_bridge` + the two adapters, and exposes the table above.
   Package it with *Tools → Create and Package New IP*.

The AXI4-Lite ↔ sideband bridge is done and compiles:
[`axi4lite_sb_cfg_bridge.sv`](../../FPGA/rtl/axi4lite_sb_cfg_bridge.sv)
(maps AXI write→`SB_32_CFG_WRITE`, read→`SB_32_CFG_READ`, parses the completion
status/data, handles credits, has a timeout→`SLVERR`).

---

## 6. Example address map

| Slave | Base | Size |
|---|---|---|
| SB cfg bridge (`S_AXI_SB`) | `0x40000000` | 32 MB (25-bit `rf_addr`) |
| AXI GPIO #0 (RDI control) | `0x40010000` | 64 KB |
| AXI GPIO #1 (RDI status) | `0x40020000` | 64 KB |
| AXI DMA control | `0x40400000` | 64 KB |
| DDR (DMA buffers) | PS DDR region | — |

> Software accesses the sideband registers as `*(volatile uint32_t*)(0x40000000 + rf_addr)`.
> The reg file uses a **25-bit** address `rf_addr[24:0]`:
> - `rf_addr[23:0]`  → carried in the packet header `addr` field (AXI addr `[23:0]`).
> - `rf_addr[24]` (**space**) → CFG (0) vs MEM (1); not in the header, it is encoded
>   in the opcode, so the bridge picks the opcode from `{AXI addr[24], is_write}`.

---

## 7. Clocking

The analog PLLs are gone, so the four PHY clocks come from a **Clocking Wizard**:

| Clock | Original source | FPGA source |
|---|---|---|
| `lclk` / `gated_lclk` | analog `pll/16` | MMCM output (word clock) |
| `pll_clk` | analog fast PLL | MMCM faster output (clk-pattern gen/detect) |
| `clk_sb` | analog `sb_pll/8` | MMCM output (sideband) |

**CDC caution (important):** `axi4lite_sb_cfg_bridge` is single-clock — its
`S_AXI_SB` (`s_axi_aclk`) and the `lp_cfg`/`pl_cfg` interface (`clk_sb`) must be
the **same** clock. For first bring-up, drive the AXI control domain and `clk_sb`
from one MMCM output. If they must differ, add an async-FIFO / AXI clock-converter
between the bridge and the sideband. The same applies to the MainBand AXI-Stream
adapters vs `lclk`.

---

## 8. Loopback test sequence (software)

1. **Reset & clocks** up; release `aresetn`.
2. **Configure PHY**: write the ctrl/config registers over `S_AXI_SB` (AXI4-Lite),
   read them back to verify.
3. **Walk training**: drive `lp_state_req` etc. via AXI GPIO #0, poll
   `pl_state_sts` on AXI GPIO #1 until the link reaches **Active**.
4. **Prepare data**: fill a DDR TX buffer with a known pattern.
5. **Run DMA**: `MM2S` streams the TX buffer into `S_AXIS_MBTX`; the digital
   loopback folds TX→RX; `M_AXIS_MBRX` is captured by `S2MM` into a DDR RX buffer.
6. **Compare** TX vs RX buffers in software → PASS/FAIL.
   (Optionally also capture into distributed BRAM for on-chip compare.)

---

## 9. Open decisions / assumptions

- **CPU**: Zynq US+ assumed; MicroBlaze works the same with `M_AXI`/`AXI4-Lite`.
- **Reg opcodes**: 4 opcodes chosen from `{AXI addr[24]=space, is_write}` —
  `OPC_CFG_RD/WR` (space 0) and `OPC_MEM_RD/WR` (space 1). Override the params if
  the second space should be `SB_32_DMS_REG_*` instead of `SB_32_MEM_*`.
- **Address width**: `rf_addr` is 25-bit, so `AXI_ADDR_W >= 25` and the SB slave
  must be given a ≥ 32 MB AXI window (bit `[24]` selects CFG vs MEM space).
- **dstid**: defaults `LOCAL_PHY`. Change if the target reg block differs.
- **Sideband parity** (`cr`/`cp`/`dp`) is left 0 by the bridge — add a generator
  if the sideband checks it.
- **DMA flavour**: simple AXI DMA is enough for a single buffer; switch to
  scatter-gather for large/segmented transfers.
