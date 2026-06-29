# SideBand (SB) — UCIe 3.0 Physical Layer Control/Management Channel

The **Sideband** is the low-speed, always-on auxiliary channel of the UCIe PHY.
It is the link's control plane: it carries the training/management messages that
bring the Main-Band up, the register-access (configuration) traffic to/from the
Reg_File, and the RDI control messages exchanged with the adapter. It runs on a
forwarded-clock serial pair (`TXCKSB`/`TXDATASB` out, `RXCKSB`/`RXDATASB` in)
independent of the Main-Band data path.

Top module: **`top/SideBand_Top.sv`** (an AXIS-wrapped variant exists in
`top/SideBand_AXIS_Top.sv`). The digital/analog split lives in
`digital_sideband.sv` + `sideband_analog_hard_macro.sv`.

---

## Block diagram

```
                    ┌──────────────── SideBand_Top ───────────────────┐
   Training msgs ──▶│ Training_Mgmt ─┐                                 │
   (LTSM)           │                ├─▶ Link_Controller ─▶ SerDes ─▶ TXDATASB/TXCKSB
   RDI msgs    ───▶ │ RDI_control ───┘    (mapper/demapper,            │
   (adapter)        │                      pattern engine,    ◀─ RXDATASB/RXCKSB
   Reg access  ◀──▶ │ Reg_Access ◀── packets ◀── Link_Demux ◀─ deser  │
   (Reg_File)       │                                                  │
                    └──────────────────────────────────────────────────┘
```

---

## Sub-blocks

### `Link_Controller/` — packet framing + serial pattern engine
| File | Function |
|------|----------|
| `Link_Controller.sv` | Top of the link controller; sequences mapping, pattern, and (de)serialization. |
| `sb_mapper.sv` / `sb_demapper.sv` | Pack/unpack the 64-bit message + 32-bit gap into the serial sideband frame. |
| `Link_Demux.sv` | Routes received packets to Training_Mgmt, RDI_control, or Reg_Access by type. |
| `sb_pattern_detector.sv` / `sb_pattern_engine.sv` | Generate and detect the SBINIT clock/training patterns (`start_pat_req`, `det_pat_rcvd`, `iter_done`). |

### `Training_mgmt/` — LTSM message transport
| File | Function |
|------|----------|
| `Training_Mgmt.sv` | Top; carries LTSM messages (`ltsm_*_send`/`ltsm_*_rcvd`) with `msg_data`/`msg_info`. |
| `Packetizer.sv` / `DePacketizer.sv` | Frame outgoing / parse incoming training-management packets (back-to-back streaming supported). |
| `roud_robin_arbiter.sv`, `arbiter.sv` | Round-robin arbitration between competing send sources. |
| `Training_Mgmt_Demux.sv` | Demux received training messages. |

### `rdi_controller/` — RDI (adapter) message transport
| File | Function |
|------|----------|
| `RDI_control.sv` | Top; carries adapter config traffic (`lp_cfg`/`pl_cfg`) and RDI SM messages over SB. |
| `rdi_aggregator.sv` / `rdi_de_aggregator.sv` | Aggregate / de-aggregate multi-beat RDI payloads. |
| `rdi_router.sv` | Routes RDI messages between adapter, SB, and the RDI SM. |
| `credit_counter.sv` | Flow control / credit accounting (`pl_cfg_crd`/`lp_cfg_crd`). |
| `rdi_comp_req_decoder.sv` | Decodes RDI request/completion opcodes. |

### `Reg_Access/` — register-access (config) endpoint
| File | Function |
|------|----------|
| `Reg_Access.sv` | Top; bridges SB register-access packets to the Reg_File bus. |
| `Reg_Access_FSM.sv` | Drives the Reg_File interface (`rf_addr`/`rf_be`/`rf_wdata`/`rd_en`/`wr_en`), handles `rdata_vld` and `addr_err_o` (→ UR completion). |
| `Reg_DePacketizer.sv` | Parses register-access packets; derives the space selector (Config vs MMIO) from the opcode. |
| `Completion_gen.sv` | Generates completion packets (Success / UR) back over the sideband. |

### `common/` — shared infrastructure
| File | Function |
|------|----------|
| `sb_pkg.sv`, `msg_codec_pkg.sv` | Message/opcode encodings and shared types. |
| `sb_demux.sv`, `sb_priority_arbiter.sv` | Generic demux and priority arbiter primitives. |

### Analog / clocking
| File | Function |
|------|----------|
| `sb_pll.sv` | Sideband PLL; the `÷8` tap produces the ~100 MHz `clk_sb` that feeds the Reg_File. |
| `sideband_analog_hard_macro.sv` | SerDes (serializer + deserializer) and serial pin drivers. |
| `digital_sideband.sv` | Digital half of the split (everything except the hard macro). |

---

## Features supported

- **Three logical message channels** multiplexed onto one serial link:
  Training/LTSM management, RDI/adapter messages, and Register-access.
- **SBINIT pattern generation & detection** (clock pattern, iteration count,
  `det_pat_rcvd` handshake) used to wake and align the sideband before MB training.
- **Register access** to the full Config + MMIO map with byte enables, 32/64-bit
  accesses, and Success/UR completions (`addr_err_o`).
- **Credit-based flow control** on the RDI/adapter config channel.
- **Round-robin / priority arbitration** with back-to-back packet streaming.
- **Performant-mode operation (PMO)** gating via `pmo_en`.
- **Digital/analog split** for ASIC vs FPGA/simulation retargeting.

---

## Key interfaces (`SideBand_Top`)

| Group | Signals |
|-------|---------|
| Clocks / reset | `clk_main`, `clk_ltsm`, `rst_main_n`, `rst_sb_n`, `clk_sb` (out) |
| Serial pins | `RXCKSB`, `TXCKSB`, `TXDATASB`, `RXDATASB` |
| Pattern | `pattern_mode`, `start_pat_req`, `req_iter_count`, `iter_done`, `det_pat_rcvd` |
| RDI SM | `RDI_msg_no_send/rcvd`, `RDI_vld_*`, `stall_send/rcvd`, `traffic_req/rdy` |
| LTSM | `ltsm_msg_n_send`, `msg_data/info_send`, `ltsm_*_rcvd` |
| Adapter (RDI ctrl) | `lp_cfg`, `lp_cfg_vld`, `pl_cfg_crd`, `lp_cfg_crd`, `pl_cfg`, `pl_cfg_vld` |
| Reg_File | `rf_addr`, `rf_be`, `rf_is_64b_access`, `rf_wdata`, `rd_en`, `wr_en`, `rf_rdata`, `rdata_vld`, `addr_err_o` |

---

## Simulation

| CONFIG | What it exercises |
|--------|-------------------|
| `integration_SideBand_Top` | Full sideband top integration. |
| `integration_SideBand_AXIS_Top` | AXIS-wrapped sideband top. |
| `integration_MBINIT_SideBand` / `integration_MBINIT_D2C_SideBand` | SBINIT + MBINIT message flows. |
| `wrapper_sb_serdes_loopback` | Serial SerDes loopback. |

Sideband unit testbenches live under `tb/unit/sideband/`.
