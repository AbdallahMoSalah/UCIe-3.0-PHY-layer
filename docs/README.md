# UCIe 3.0 PHY Layer — Documentation

Design and verification documentation for the UCIe 3.0 PHY layer (digital).
This is the index — start here and follow the links into each subsystem.

> Convention: substate docs are numbered in **execution order**
> (`NN_<NAME>.md`). Folders prefixed with `_` (`_sources/`, `_reference/`,
> `assets/`) hold raw inputs, extracted spec text, and figures — not narrative.

---

## 1. Specification

| Doc | What it covers |
|---|---|
| [Spec/PHY_Interface.md](Spec/PHY_Interface.md) | Complete PHY ↔ partner interface (RDI) port summary |
| [Spec/UCIe_Specification_rev3p0_…pdf](Spec/) | Full UCIe 3.0 spec PDF (searchable via the `spec-lookup` skill) |

## 2. MainBand (MB)

| Doc | What it covers |
|---|---|
| [MB/ddr_serializer_design.md](MB/ddr_serializer_design.md) | DDR serializer design — theory vs. practice |
| [MB/mb_lane_reversal_dataflow.md](MB/mb_lane_reversal_dataflow.md) | Lane reversal & width-degradation data flow |
| [MB/assets/](MB/assets/) | `MB_TX_TOP.drawio`, `MB_RX_TOP.drawio`, serializer figure |

## 3. SideBand (SB)

| Doc | What it covers |
|---|---|
| [SB/README.md](SB/README.md) | Sideband overview — register-access model & figures |
| [SB/reg_access_design.md](SB/reg_access_design.md) | Full `Reg_Access` RTL design (depacketizer, FSM, completion gen, reg-file) |
| [SB/assets/](SB/assets/) | FSM/arch figures, `reg_file_layout.svg`, `gen_svg.py` |

## 4. State Machines (SM)

### 4.1 RDI State Machine
| Doc | What it covers |
|---|---|
| [SM/RDI_SM/RDI_SM_Arch.png](SM/RDI_SM/RDI_SM_Arch.png) | RDI SM architecture diagram (source: `RDI_SM.drawio`, `_sources/SM.docx`) |

### 4.2 LTSM — Link Training State Machine
Training executes in this order: **SBINIT → MBINIT → MBTRAIN**.

**SBINIT** — [folder](SM/LTSM/SBINIT/)
- [01_SBINIT_Design_Comparison.md](SM/LTSM/SBINIT/01_SBINIT_Design_Comparison.md)
- [02_SBINIT_Test_Plan.md](SM/LTSM/SBINIT/02_SBINIT_Test_Plan.md)

**MBINIT** — [folder](SM/LTSM/MBINIT/)
- [00_MBINIT_Architecture.md](SM/LTSM/MBINIT/00_MBINIT_Architecture.md) — overview
- [01_MBINIT_PARAM_Test_Plan.md](SM/LTSM/MBINIT/01_MBINIT_PARAM_Test_Plan.md)
- [02_MBINIT_REPAIRCLK_Test_Plan.md](SM/LTSM/MBINIT/02_MBINIT_REPAIRCLK_Test_Plan.md)
- [03_MBINIT_REPAIRVAL_Test_Plan.md](SM/LTSM/MBINIT/03_MBINIT_REPAIRVAL_Test_Plan.md)
- [04_MBINIT_REVERSALMB_Test_Plan.md](SM/LTSM/MBINIT/04_MBINIT_REVERSALMB_Test_Plan.md)
- [05_MBINIT_REPAIRMB_Architecture.md](SM/LTSM/MBINIT/05_MBINIT_REPAIRMB_Architecture.md)
- [06_MBINIT_REPAIRMB_Test_Plan.md](SM/LTSM/MBINIT/06_MBINIT_REPAIRMB_Test_Plan.md)

**MBTRAIN** — [folder](SM/LTSM/MBTRAIN/) · [00_DOCUMENTATION_PLAN.md](SM/LTSM/MBTRAIN/00_DOCUMENTATION_PLAN.md)
- Substates `01_..13_` in execution order, top-level integration in
  [14_MBTRAIN_TOP.md](SM/LTSM/MBTRAIN/14_MBTRAIN_TOP.md).
- `_reference/` holds the extracted per-substate spec text; `_sources/` holds
  the `UCIe_PHY_Guideline` `.docx` source files.

## 5. FPGA Bring-up

| Doc | What it covers |
|---|---|
| [FPGA/README.md](FPGA/README.md) | Vivado IP-Integrator block design for digital self-loopback (HW/SW co-design) |
