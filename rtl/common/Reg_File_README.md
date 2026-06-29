# Reg_File — UCIe PHY Register Block (Chapter 9: Configuration & Parameters)

`Reg_File.sv` is the **memory-mapped register block** of the UCIe PHY. It holds
the link's configuration and status: capability advertisement (HWInit), software
control (RW), live hardware status (RO), error logs (ROS / RW1CS), and runtime
link-test controls. It is accessed by software through the **Sideband
register-access path** (`Reg_Access` → `Reg_Access_FSM`), and its decoded control
fields fan out to the LTSM, the RDI SM, and the Main-Band.

- **Register list source:** `docs/SB/gen_svg.py`
- **Bit-field attributes:** UCIe Specification rev 3.0, Chapter 9 (authoritative)

---

## Access interface

| Signal | Dir | Meaning |
|--------|-----|---------|
| `clk`, `rst_n` | in | Clock (the ~100 MHz `clk_sb` from the SB PLL) and async reset. |
| `rf_addr[24:0]` | in | `{space[24], RL[23:20], offset[19:0]}` — see below. |
| `rf_be[7:0]` | in | Byte enables (LSB = byte 0). |
| `rf_is_64b_access` | in | 1 = 64-bit access, 0 = 32-bit. |
| `rf_wdata[63:0]` | in | Write data. |
| `rd_en` / `wr_en` | in | 1-cycle read / write strobes. |
| `rf_rdata[63:0]` | out | Read data (registered, 1-cycle latency). |
| `rdata_vld` | out | Data-valid pulse (registered). |
| `addr_err_o` | out | Address outside both windows, or RL ≠ 0 → FSM returns **UR** (Unsupported Request). |

### Address bus (25 bits)
```
 [24]    Space selector : 0 = Config Space (CFG_ opcodes)
                          1 = MMIO Space  (MEM_/DMS_REG_ opcodes)
 [23:20] RL (Register Locator) : must be 4'h0, else addr_err_o (UR)
 [19:0]  Byte offset within the space
```
- **Config window:** `addr[24]=0`, RL=0, offsets `000h–023h`.
- **MMIO window:** `addr[24]=1`, RL=0, offsets `1000h–110Bh`.
- An out-of-window read returns `0xDEAD_BEEF_DEAD_BEEF` with `addr_err_o=1`.

---

## Attribute key

| Attr | Meaning |
|------|---------|
| **RO** | Read-Only: hardwired constant or driven live by HW; SW writes ignored. |
| **HWInit** | Latched from HW at reset, then behaves as RO. |
| **RW** | Read-Write: SW fully controls the bit. |
| **RW1C** | Write-1-to-Clear: HW sets, SW clears by writing 1. |
| **RW1CS** | Like RW1C but **Sticky** across soft resets. |
| **ROS** | Read-Only Sticky: HW writes on an error event; cleared only by reset. |
| **RsvdZ** | Reserved (this design drives many reserved bits to 1 — see notes). |

---

## Register map overview

### Config Space (`addr[24]=0`)
| Off | Register | Bytes | Attr |
|-----|----------|-------|------|
| 000h | PCIe Ext Cap Header | 4 | RO (`0x0001_0023`) |
| 004h | DVSEC Header 1 | 4 | RO (`0x0240_D2DE`) |
| 008h | DVSEC Header 2 | 2 | RO (`0x0000`) |
| 00Ah | Capability Descriptor | 2 | RO (`0xFFF7`) |
| 00Ch | UCIe Link Capability | 4 | HWInit |
| 010h | UCIe Link Control | 4 | RW |
| 014h | UCIe Link Status | 4 | RO + RW1C + RW1CS |
| 018h | Link Event Notification Control | 2 | RW |
| 01Ah | Error Notification Control | 2 | RW |
| 01Ch | Register Locator 0 Low | 4 | RO (`0x0000_1F00`) |
| 020h | Register Locator 0 High | 4 | RO (`0x0000_0000`) |

### MMIO Space (`addr[24]=1`)
| Off | Register | Bytes | Attr |
|-----|----------|-------|------|
| 1000h | PHY Capability | 4 | RO + HWInit |
| 1004h | PHY Control | 4 | RW |
| 1008h | PHY Status | 4 | RO (live) |
| 100Ch | PHY Initialization & Debug | 4 | RW + RO |
| 1010h | Training Setup 1 | 4 | RW |
| 1020h | Training Setup 2 | 4 | RW |
| 1030h | Training Setup 3 | 8 | RW |
| 1050h | Training Setup 4 | 4 | RW |
| 1060h | Current Lane Map Module 0 | 8 | RW |
| 1080h | Error Log 0 | 4 | ROS |
| 1090h | Error Log 1 | 4 | ROS + RW1CS |
| 1100h | Runtime Link Test Control | 8 | RW |
| 1108h | Runtime Link Test Status | 4 | RO (live) |

---

## Bit-level detail

### 00Ch — UCIe Link Capability (HWInit; latched at reset, then RO)
| Bits | Field | Attr |
|------|-------|------|
| [0] | Raw Format Support | HWInit |
| [3:1] | Max Link Width | HWInit |
| [7:4] | Max Link Speed → `phy_max_link_speed_cap_out` | HWInit |
| [8] | (const 1) | RO |
| [9] | Multi-Protocol Capability | HWInit |
| [10] | Advanced Package | HWInit |
| [11] | 68B Flit Format for Streaming | HWInit |
| [12] | 256B End-Header Flit Format for Streaming | HWInit |
| [13] | 256B Start-Header Flit Format for Streaming | HWInit |
| [14] | Latency-Optimized 256B Flit w/o Optional Bytes | HWInit |
| [15] | Latency-Optimized 256B Flit w/ Optional Bytes | HWInit |
| [16] | Enhanced Multi-protocol Capable | HWInit |
| [17] | Standard Start-Header Flit for PCIe | HWInit |
| [18] | Latency-Optimized Flit w/ Optional Bytes for PCIe | HWInit |
| [19] | Runtime Link Testing Parity Feature Error Signaling | HWInit |
| [20] | Advanced Package Module Width (APMW) | HWInit |
| [21] | (const 1) | RO |
| [22] | Standard Package Module Width (SPMW) | HWInit |
| [23] | Sideband Performant Mode Operation (PMO) | HWInit |
| [24] | Priority Sideband Packet Transfer (PSPT) | HWInit |
| [25] | L2 Sideband Power Down (L2SPD) | HWInit |
| [31:26] | Reserved (reads 1) | RsvdZ |

### 010h — UCIe Link Control (RW)
| Bits | Field | Attr | Output tap |
|------|-------|------|------------|
| [1] | Multi-protocol Enable (reset = cap) | RW | |
| [5:2] | Target Link Width | RW | `phy_target_link_width_ctrl_out` |
| [9:6] | Target Link Speed | RW | `phy_target_link_speed_ctrl_out` |
| [10] | **Start UCIe Link Training** | RWac | `phy_start_ucie_link_training_ctrl_out` |
| [11] | **Retrain UCIe Link** | RWac | `phy_retrain_ucie_link_ctrl_out` |
| [13] | 68B Flit Format Streaming Enable | RW | |
| [14]…[20] | Flit-format / PCIe-format enables | RW | |
| [21] | PMO | RW | `phy_pmo_ctrl_out` |
| [22] | PSPT | RW | `phy_pspt_ctrl_out` |
| [23] | L2SPD | RW | `phy_l2spd_ctrl_out` |
| [31:24] | Reserved (reads 1) | RsvdZ | |

> **Auto-clear (RWac):** bits [10] and [11] are cleared automatically when training
> completes — detected as the 1→0 edge of `phy_link_training_retraining_status_i`.
> A 0→1 SW write while training is already in progress is **ignored**. The
> auto-clear wins over a simultaneous SW write.

### 014h — UCIe Link Status (mixed)
| Bits | Field | Attr |
|------|-------|------|
| [0] | Raw Format Enable | RO |
| [1] | Multi-protocol Enable | RO |
| [2] | Enhanced Multi-protocol Enable | RO |
| [3] | x32 Advanced Package Module Enable | RO |
| [10:7] | Link Width Enable → `phy_link_width_enabled_status_out` | RO |
| [14:11] | Link Speed Enable → `phy_link_speed_enabled_status_out` | RO |
| [15] | Link Status | RO (live) |
| [16] | Link Training / Retraining | RO (live) |
| [17] | Link Status Changed | RW1C |
| [18] | HW Autonomous Bandwidth Changed | RW1C |
| [19] | Correctable Error | RW1CS |
| [20] | Uncorrectable Non-Fatal Error | RW1CS |
| [21] | Uncorrectable Fatal Error | RW1CS |
| [25:22] | Flit Format Status | RO |
| [26] | PMO Status | RO |
| [27] | PSPT Status | RO |
| [28] | L2SPD Status | RO |

### 018h — Link Event Notification Control
| Bits | Field | Attr |
|------|-------|------|
| [1:0] | Event notification control | RW |
| [10:2] | (const `0_0111_1111`) | RO |
| [15:11] | Link Event Notification Interrupt Number | RO (live) |

### 01Ah — Error Notification Control
| Bits | Field | Attr |
|------|-------|------|
| [5:0],[15:11] | Error notification control | RW |
| [10:6] | Reserved (reads 1) | RsvdZ |

### 1000h — PHY Capability (RO + HWInit)
| Bits | Field | Attr |
|------|-------|------|
| [3] | Terminated Link support | HWInit |
| [4] | Tx Equalization support | HWInit |
| [9:5] | Supported Tx Vswing encodings | HWInit |
| [12:11] | Rx Clock Mode Support (≤32 GT/s) | HWInit |
| [14:13] | Rx Clock Phase Support (≤32 GT/s) | HWInit |
| [15] | Package Type (1=Std, 0=Adv) | HWInit |
| [16] | Tightly Coupled Mode (TCM) support | HWInit |
| [17] | Tx Adjustment for Runtime Recalibration (TARR) support | HWInit |
| others | Reserved (reads 1) | RsvdZ |

### 1004h — PHY Control (RW)
| Bits | Field | Output tap |
|------|-------|------------|
| [3] | Rx Termination Enable | `phy_rx_term_status_i_ctrl_out` |
| [4] | Tx EQ Enable | `phy_tx_eq_status_i_en_ctrl_out` |
| [5] | Rx Clock Mode Select | `phy_rx_clk_mode_ctrl_out` |
| [6] | Rx Clock Phase Select | `phy_rx_clk_phase_ctrl_out` |
| [8] | Force x8 Width Mode in a UCIe-S x16 Module | `phy_x8_width_mode_ctrl_out` |
| [9] | Force I/Q Correction Enable | `phy_iq_correction_en_ctrl_out` |
| [15:10] | Force I/Q Correction Parameter | `phy_iq_correction_param_ctrl_out` |
| [16] | Force Tx EQ Preset | `phy_tx_eq_status_i_preset_ctrl_out` |
| [20:17] | Force Tx EQ Preset Setting | `phy_tx_eq_status_i_preset_setting_ctrl_out` |
| [21] | TARR Enable | `phy_tarr_en_ctrl_out` |
| [31:22] | Reserved (reads 1) | — |

### 1008h — PHY Status (RO, live)
| Bits | Field |
|------|-------|
| [3] | Rx Termination Status |
| [4] | Tx EQ Status |
| [5] | Clock Mode (0=Strobe, 1=Free-running) |
| [6] | Clock Phase (0=Differential, 1=Quadrature) |
| [7] | Lane Reversal within Module |
| [13:8] | I/Q Correction Parameter Status |
| [17:14] | EQ Preset Setting Status |
| [18] | TARR Status |
| others | reads 1 |

### 100Ch — PHY Initialization & Debug (RW + RO)
| Bits | Field | Output tap |
|------|-------|------------|
| [2:0] | PHY Initialization Done | `phy_init_ctrl_out` |
| [4:3] | (const 11) | RO |
| [5] | Resume Training | `phy_resume_training_ctrl_out` |
| [31:6] | reads 1 | RO |

### 1010h–1060h — Training Setup / Lane Map (RW)
| Off | Bits | Field | Output tap |
|-----|------|-------|------------|
| 1010h | [31:27] reserved (1); rest RW | Training Setup 1 | — |
| 1020h | [15:0] | Idle Count | `idle_count_out` |
| 1020h | [31:16] | Iterations | `iterations_out` |
| 1030h | [63:0] | Lane Mask | `lane_mask_ctrl_out` |
| 1050h | [15:4] | Max Error Threshold — per-lane comparison | `max_error_threshold_in_per_lane_comparison_out` |
| 1050h | [31:16] | Max Error Threshold — aggregate comparison | `max_error_threshold_in_aggregate_comparison_out` |
| 1060h | [15:0] | Current Lane Map Module 0 Enable | `current_lane_map_module_0_enable_out` |

### 1080h — Error Log 0 (ROS)
| Bits | Field |
|------|-------|
| [7:0] | State N (LTSM state at error) |
| [8] | Lane Reversal at error |
| [9] | Width Degrade (Standard Package only) |
| [15:10] | RsvdZ (0) |
| [23:16] | State N-1 |
| [31:24] | State N-2 |

> On `err_capture_en`, the log shifts: N-2 ← N-1 ← N ← new state, and Error Log 1
> [7:0] (State N-3) shifts in from the old N-2.

### 1090h — Error Log 1 (ROS + RW1CS)
| Bits | Field | Attr |
|------|-------|------|
| [7:0] | State N-3 | ROS |
| [8] | State Timeout | RW1CS |
| [9] | Sideband Timeout | RW1CS |
| [10] | RM Link Error | RW1CS |
| [11] | Internal Error | RW1CS |
| [31:12] | RsvdZ (0) | — |

### 1100h — Runtime Link Test Control (RW)
| Bits | Field | Output tap |
|------|-------|------------|
| [2] | Apply Module 0 Lane Repair | `rt_apply_module_0_lane_repair_ctrl_out` |
| [6] | Runtime Link Test Start (auto-cleared when `rt_link_busy_status_i`) | `rt_link_test_start_ctrl_out` |
| [7] | Inject Stuck-at Fault | `inject_stuck_at_fault_ctrl_out` |
| [14:8] | Module 0 Lane Repair ID | `module_0_lane_repair_id_ctrl_out` |
| [63:36] | reads 1 | — |

### 1108h — Runtime Link Test Status (RO, live)
| Bits | Field |
|------|-------|
| [0] | Runtime Link Test Busy (`rt_link_busy_status_i`) |

---

## Implementation notes

- **Read path** is registered (1-cycle latency) with `rdata_vld`; reads are
  byte-assembled from internal `cfg_mem`/`mmio_mem` byte arrays.
- **Write path** is byte-granular via `rf_be`, decoded into per-byte write
  enables; 64-bit writes require `rf_is_64b_access`.
- **HW-set paths** (RW1C/RW1CS/ROS) run every cycle independent of SW and OR-set
  their bits from the corresponding `*_status_i` / `*_err_i` event inputs.
- Many "Reserved" bits read back as **1** in this implementation (the comb blocks
  force the upper byte/range high); treat per the spec, not the readback value.
- **Convenience taps:** every register is also exposed as a flat `*_r_out` bus
  (e.g. `ucie_link_ctrl_r_out`, `phy_control_r_out`) for direct internal use
  without going through the access bus.

This register block is instantiated at the PHY top (`rtl/TOP/UCIe_PHY.sv`) and is
driven over the sideband by `rtl/SideBand/Reg_Access/`.
