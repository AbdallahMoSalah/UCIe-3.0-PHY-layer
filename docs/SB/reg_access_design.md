# Reg_Access RTL — Design Document
## UCIe PHY SideBand Register Access Block

---

## 1. Overview

The `Reg_Access` block sits between the RDI_CONTROL (SideBand demux) and the PHY Register File.
It decodes incoming SideBand register-access request packets, executes reads or writes on the
PHY register file, and returns a completion packet to the fabric.

```
RDI_CONTROL → reg_msg/reg_vld → Reg_Access → completion_msg/vld → Link_Controller TX
                                      │
                                      └──── rf_addr/be/wdata/rd/wr ──► Reg_File (PHY §9.5)
```

---

## 2. Architecture (from docs/SB/SB_Reg_Access_arc.png)

| Sub-block | File | Role |
|---|---|---|
| `Reg_DePacketizer` | `Reg_DePacketizer.sv` | Decodes 128-bit SB packet → fields |
| `Reg_Access_FSM` | `Reg_Access_FSM.sv` | IDLE→DECODE→EXECUTE→GENERATE controller |
| `Completion_gen` | `Completion_gen.sv` | Builds and sends SB completion packet |
| `Reg_File` | `Reg_File.sv` | UCIe PHY register storage (§9.5) |
| `Reg_Access` | `Reg_Access.sv` | Top-level wrapper wiring all subblocks |

**Internal wires matching the architecture diagram:**

| Wire | From → To | Description |
|---|---|---|
| `opcode`, `rf_addr`, `rf_be`, `rf_wdata` | DePacketizer → FSM | Decoded fields |
| `Original_Header` | DePacketizer → FSM/Completion_gen | Full latched header |
| `parity_err`, `false_msg`, `ep` | DePacketizer → FSM | Error qualification |
| `rd_en`, `wr_en`, `rf_addr_o`, `rf_be_o`, `rf_wdata_o` | FSM → Reg_File | Register access |
| `rf_rdata`, `rdata_vld` | Reg_File → FSM & Completion_gen | Read data path |
| `status`, `completion_start` | FSM → Completion_gen | Trigger and status |
| `completion_msg`, `completion_vld` | Completion_gen → output | SB response |

---

## 3. UCIe §7.1.1 — Sideband Register Access Packet Format

> **UCIe §7.1.1:** *"Register Accesses: These can be Configuration (CFG) or Memory Mapped
> accesses for both Reads or Writes. These can be associated with 32b of data or 64b of
> data. All register accesses (Reads or Writes) have an associated completion."*

### 3.1 Supported Opcodes (Table 7-1, UCIe §7.1.1)

| Opcode[4:0] | Name | Type |
|---|---|---|
| `5'b00000` | `SB_32_MEM_READ` | Read |
| `5'b00001` | `SB_32_MEM_WRITE` | Write |
| `5'b00010` | `SB_32_DMS_REG_READ` | Read |
| `5'b00011` | `SB_32_DMS_REG_WRITE` | Write |
| `5'b00100` | `SB_32_CFG_READ` | Read |
| `5'b00101` | `SB_32_CFG_WRITE` | Write |
| `5'b01000` | `SB_64_MEM_READ` | Read |
| `5'b01001` | `SB_64_MEM_WRITE` | Write |
| `5'b01010` | `SB_64_DMS_REG_READ` | Read |
| `5'b01011` | `SB_64_DMS_REG_WRITE` | Write |
| `5'b01100` | `SB_64_CFG_READ` | Read |
| `5'b01101` | `SB_64_CFG_WRITE` | Write |

### 3.2 Request Header Field Layout (64-bit, §7.1.1 Table 7-2/7-3)

| Bits | Field | Description |
|---|---|---|
| `[4:0]` | `opcode[4:0]` | Packet type |
| `[5]` | `ep` | Data parity: `^wdata` for writes, 0 for reads |
| `[10:6]` | `rsvd0` | Reserved |
| `[13:11]` | `tag[2:0]` | Transaction tag — echoed in completion |
| `[21:14]` | `be[7:0]` | Byte enables (1=byte active) |
| `[28:22]` | `rsvd1` | Reserved |
| `[31:29]` | `srcid[2:0]` | Source identifier |
| `[55:32]` | `addr[23:0]` | Target byte address (reconstructed as `{MsgInfo[15:0], MsgSubcode[7:0]}`) |
| `[58:56]` | `dstid[2:0]` | Destination identifier |
| `[61:59]` | `rsvd2` | Reserved |
| `[63]` | `cp` | Control parity: even parity over bits[62:0] |

**Payload [127:64]:** Write data `wdata[63:0]`. Zero for reads.

### 3.3 Completion Header (§7.1.1.2, Table 7-7)

> **UCIe §7.1.1.2:** *"The completion must contain the same tag and source identifier as the corresponding request header."*

| Bits | Field | Description |
|---|---|---|
| `[4:0]` | `opcode` | `10000`=no-data, `10001`=32b data, `11001`=64b data |
| `[5]` | `ep` | `^rf_rdata` for completions with data; 0 otherwise |
| `[13:11]` | `tag[2:0]` | **Mirrored from request** |
| `[31:29]` | `srcid[2:0]` | **Mirrored from request dstid** |
| `[34:32]` | `status[2:0]` | Completion status code |
| `[58:56]` | `dstid[2:0]` | **Mirrored from request srcid** |
| `[63]` | `cp` | Even parity over bits[62:0] |

### 3.4 Completion Status Codes (§7.1.1.2)

| status[2:0] | Meaning | When used |
|---|---|---|
| `3'b000` | **SC** – Successful Completion | Normal read/write completed |
| `3'b001` | **UR** – Unsupported Request | Bad opcode, parity error, unmapped address |
| `3'b100` | **CA** – Completer Abort | Internal fatal error |
| `3'b111` | **Stall** | Responder not ready (sent by higher layer) |

---

## 4. UCIe §9.5 — PHY Register File

> **UCIe §9 "Configuration and Parameters":** *"The D22/PHY Register Block is 8 KB.
> The first 4 KB (0000h–0FFFh) is the D2D Adapter block.
> The second 4 KB (1000h–1FFFh) is the Physical Layer register block."*

### 4.1 Register Map

| Offset | Name | Access | Width | Spec Ref |
|---|---|---|---|---|
| `1000h` | PHY Capability | RO | 32 | §9.5.1 |
| `1004h` | PHY Control | RW | 32 | §9.5.2 |
| `1008h` | PHY Status | RO (HW) | 32 | §9.5.24 |
| `100Ch` | Training Control | RW | 32 | §9.5 |
| `1010h` | Rx Training Config | RW | 32 | §9.5 |
| `1020h` | Tx Training Config | RW | 32 | §9.5 |
| `1030h` | Lane Map 0 | RW | 32 | §9.5 |
| `1040h` | Lane Map 1 | RW | 32 | §9.5 |
| `1050h` | Link Speed Config | RW | 32 | §9.5 |
| `1060h` | MBINIT Param Config | RW | **64** | §9.5 |
| `1068h` | MBTRAIN Config | RW | 32 | §9.5 |
| `1070h` | Error Status | **RW1C** | 32 | §9.5 |
| `1078h` | Error Enable | RW | 32 | §9.5 |
| `1080h` | Error Log 0 | **ROS** | 32 | §9.5.34 |
| `1084h` | Error Log 1 | ROS | 32 | §9.5 |
| `1088h` | Error Log 2 | ROS | 32 | §9.5 |

### 4.2 PHY Capability (1000h) — RO

> **UCIe §9.5.1**

| Bits | Attr | Reset | Description |
|---|---|---|---|
| `[0]` | RO | `1` | Standard Package supported |
| `[1]` | RO | `0` | Advanced Package supported |
| `[3:2]` | RO | `00` | Num Modules (00=1 module) |
| `[7:4]` | RO | `0100` | Max Data Rate (0100=16 GT/s) |
| `[15:8]` | RO | `0` | Rx Clock Modes supported |
| `[31:16]` | RsvdZ | `0` | Reserved |

### 4.3 PHY Control (1004h) — RW

> **UCIe §9.5.2**

| Bits | Attr | Reset | Description |
|---|---|---|---|
| `[0]` | RW | `0` | **Rx Termination Enable** |
| `[1]` | RW | `0` | **Tx EQ Enable** |
| `[2]` | RW | `0` | **Retrain Request** (self-clearing) |
| `[5:3]` | RW | `0` | Force Link Speed |
| `[6]` | RW | `0` | Force Lane Reversal |
| `[31:7]` | RsvdZ | `0` | Reserved |

### 4.4 PHY Status (1008h) — RO, Hardware-driven

> **UCIe §9.5.24 Table 9-49:** *"This register is global and not per module."*
> *"Rx Termination Status: This is the current status of the local UCIe Module.
> Note that this is always 0 for Advanced Packages."*
> *"Clock Mode Status: This is remote partner's advertised value during MBINIT.PARAM."*

| Bits | Attr | Reset | Description |
|---|---|---|---|
| `[2:0]` | RO | `0` | Reserved |
| `[3]` | RO | — | **Rx Termination Status** (1=terminated) |
| `[4]` | RO | — | **Tx EQ Status** (1=enabled) |
| `[5]` | RO | — | **Clock Mode** (0=Strobe, 1=Free-running) |
| `[6]` | RO | — | **Clock Phase** (0=Differential, 1=Quadrature) |
| `[7]` | RO | — | **Lane Reversal within Module** |
| `[18:8]` | RO | `0` | Reserved |
| `[26:19]` | RO | — | **Link State** (LTSM encoding) |
| `[31:27]` | RsvdZ | `0` | Reserved |

### 4.5 Error Log 0 (1080h) — ROS

> **UCIe §9.5.34:** *"This register is replicated per module. Offsets 1080h to 108Ch are
> used in 4B offset increments for multi-module scenarios."*
> *"State N: Captures the current Link training state machine status. State Encodings
> are given by: 00h RESET, 01h SBINIT, 02h MBINIT.PARAM, 03h MBINIT.CAL, ...
> 17h ACTIVE, 18h TRAINERROR, 19h L1/L2. All other encodings are reserved."*

| Bits | Attr | Reset | Description |
|---|---|---|---|
| `[7:0]` | ROS | `0` | **State N** — LTSM state at error |
| `[8]` | ROS | `0` | Lane Reversal within module |
| `[9]` | ROS | `0` | Width Degrade (Standard only) |
| `[15:10]` | RsvdZ | `0` | Reserved |
| `[23:16]` | ROS | `0` | **State N-1** |
| `[31:24]` | ROS | `0` | **State N-2** |

State encoding (§9.5.34):

| Code | State | Code | State |
|---|---|---|---|
| `00h` | RESET | `0Eh` | MBTRAIN.DATATRAINVREF |
| `01h` | SBINIT | `0Fh` | MBTRAIN.DATATRAINVREF (end) |
| `02h` | MBINIT.PARAM | `11h` | MBTRAIN.RXDESKEW |
| `03h` | MBINIT.CAL | `13h` | MBTRAIN.LINKSPEED |
| `04h` | MBINIT.REPAIRCLK | `14h` | MBTRAIN.REPAIR |
| `05h` | MBINIT.REPAIRVAL | `15h` | PHYRETRAIN |
| `06h` | MBINIT.REVERSALMB | `16h` | LINKINIT |
| `07h` | MBINIT.REPAIRMB | `17h` | ACTIVE |
| `08h` | MBTRAIN.VALVREF | `18h` | TRAINERROR |
| `09h` | MBTRAIN.DATAVREF | `19h` | L1/L2 |
| `0Ah` | MBTRAIN.SPEEDIDLE | — | — |

### 4.6 Error Status (1070h) — RW1C

| Bits | Attr | Reset | Description |
|---|---|---|---|
| `[0]` | RW1C | `0` | Parity error detected |
| `[1]` | RW1C | `0` | Unsupported Request received |
| `[2]` | RW1C | `0` | Training timeout |
| `[3]` | RW1C | `0` | Link error |
| `[31:4]` | RsvdZ | `0` | Reserved |

---

## 5. FSM State Diagram

Matches `docs/SB/reg_access_fsm.png`:

```
    ┌────────┐  (reg_vld==1)    ┌────────┐
    │  IDLE  │────────────────► │ DECODE │
    └────────┘                  └───┬────┘
        ▲                (error==1) │ (error==0)
        │                ┌──────────┘     │
        │                ▼                 ▼
        │          ┌──────────┐      ┌─────────┐
        └──────────│ GENERATE │◄─────│ EXECUTE │◄─(rdata_vld==0)─┐
                   └──────────┘      └─────────┘                  │
                    (completion_     (rdata_vld==1)        self-loop┘
                     start=1)
```

| State | FSM Outputs |
|---|---|
| **IDLE** | All outputs deasserted |
| **DECODE** | Evaluates `parity_err`, `false_msg` |
| **EXECUTE** | `rd_en=1` (read) or `wr_en=1` (write) |
| **GENERATE** | `completion_start=1`, `status=error?UR:SC` |

---

## 6. Files Created

| File | Path |
|---|---|
| [Reg_DePacketizer.sv](file:///media/abdallah-salah/eng/Graduation_Project/UCIe-3.0-PHY-layer/rtl/SideBand/Reg_Access/Reg_DePacketizer.sv) | `rtl/SideBand/Reg_Access/` |
| [Reg_Access_FSM.sv](file:///media/abdallah-salah/eng/Graduation_Project/UCIe-3.0-PHY-layer/rtl/SideBand/Reg_Access/Reg_Access_FSM.sv) | `rtl/SideBand/Reg_Access/` |
| [Completion_gen.sv](file:///media/abdallah-salah/eng/Graduation_Project/UCIe-3.0-PHY-layer/rtl/SideBand/Reg_Access/Completion_gen.sv) | `rtl/SideBand/Reg_Access/` |
| [Reg_File.sv](file:///media/abdallah-salah/eng/Graduation_Project/UCIe-3.0-PHY-layer/rtl/SideBand/Reg_Access/Reg_File.sv) | `rtl/SideBand/Reg_Access/` |
| [Reg_Access.sv](file:///media/abdallah-salah/eng/Graduation_Project/UCIe-3.0-PHY-layer/rtl/SideBand/Reg_Access/Reg_Access.sv) | `rtl/SideBand/Reg_Access/` |


1Ah + 2h = 1C
1Ch + 8h = 24h
24h + 8h = 2Ch
decimal(2Ch) = 44
