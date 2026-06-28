#ifndef UCIE_DRIVER_H
#define UCIE_DRIVER_H

#include "xil_types.h"
#include "xstatus.h"
#include "xaxidma.h"
#include "xllfifo.h"
#include "xgpiops.h"   // PS EMIO GPIO (NOT axi xgpio.h)

// =============================================================================
// Hardware base addresses (from the Vivado IP Integrator Address Editor).
//
//   Single source of truth: if you re-assign addresses in the Address Editor,
//   change them HERE only. main.c picks these up unless overridden at compile
//   time (-DDMA_BASEADDR=... etc).
//
//     axi_dma_0      / S_AXI_LITE : 0xA0000000  (64K)
//     axi_fifo_mm_s_0/ S_AXI      : 0xA0010000  (64K)
//     src_bram       / S_AXI      : 0xA0022000  (8K)  -> MainBand TX (DMA MM2S src)
//     dst_bram       / S_AXI      : 0xA0020000  (8K)  -> MainBand RX (DMA S2MM dst)
//     PS EMIO GPIO (bank 3)       : 0xFF0A0000        -> fixed Zynq US+ PS GPIO
// =============================================================================
#define UCIE_DMA_BASEADDR       0xA0000000U
#define UCIE_FIFO_BASEADDR      0xA0010000U
#define UCIE_GPIO_BASEADDR      0xFF0A0000U
#define UCIE_BRAM_TX_BASEADDR   0xA0022000U
#define UCIE_BRAM_RX_BASEADDR   0xA0020000U

// =============================================================================
// UCIe sideband register addresses (Offsets)
// =============================================================================
#define REG_UCIE_LINK_CTRL    0x000010
#define REG_PHY_CONTROL       0x001004
#define REG_TRAIN_SETUP3      0x001030
#define REG_TRAIN_SETUP4      0x001050
#define REG_UCIE_LINK_STATUS  0x000014

// =============================================================================
// UCIe Link Control register (Offset 0x10) bit fields  (spec Table 9-9).
//   Target Link Width  [5:2] : 0x1=x8 0x2=x16 0x3=x32 0x4=x64 0x5=x128 0x6=x256
//   Target Link Speed  [9:6] : 0x0=4 0x1=8 0x2=12 0x3=16 0x4=24 0x5=32
//                              0x6=48 0x7=64 (GT/s)
// =============================================================================
#define LINK_CTRL_TGT_WIDTH_SHIFT   2
#define LINK_CTRL_TGT_WIDTH_MASK    0x0000003Cu   // [5:2]
#define LINK_CTRL_TGT_SPEED_SHIFT   6
#define LINK_CTRL_TGT_SPEED_MASK    0x000003C0u   // [9:6]
#define LINK_CTRL_START_TRAINING    (1u << 10)    // [10] start UCIe link training
#define LINK_CTRL_RETRAIN           (1u << 11)    // [11] retrain UCIe link

// =============================================================================
// PHY Control register (Offset 0x1004) bit fields  (spec Table 9-48 / RTL).
// =============================================================================
#define PHY_CTRL_RX_TERM            (1u << 3)     // [3]  Rx Termination Enable
#define PHY_CTRL_TX_EQ_EN           (1u << 4)     // [4]  Tx EQ Enable
#define PHY_CTRL_RX_CLK_MODE        (1u << 5)     // [5]  Rx Clock Mode Select
#define PHY_CTRL_RX_CLK_PHASE       (1u << 6)     // [6]  Rx Clock Phase Select
#define PHY_CTRL_FORCE_X8           (1u << 8)     // [8]  Force x8 Width Mode (UCIe-S x16)

// =============================================================================
// Training Setup 4 register (Offset 0x1050) bit fields  (RTL Reg_File).
//   [15:4]  Max error threshold, per-lane comparison   (12-bit)
//   [31:16] Max error threshold, aggregate comparison  (16-bit)
// =============================================================================
#define TRAIN_SETUP4_PERLANE_SHIFT  4
#define TRAIN_SETUP4_PERLANE_MASK   0x0000FFF0u   // [15:4]
#define TRAIN_SETUP4_AGG_SHIFT      16
#define TRAIN_SETUP4_AGG_MASK       0xFFFF0000u   // [31:16]

// =============================================================================
// UCIe Link Status register (Offset 0x14) bit fields  (spec Table 9-10).
//   Width/Speed fields are only meaningful when LINK_UP (bit 15) is set.
// =============================================================================
#define LINK_STATUS_RAW_FORMAT_EN       (1u << 0)
#define LINK_STATUS_MULTI_PROTO_EN      (1u << 1)
#define LINK_STATUS_ENH_MULTI_PROTO_EN  (1u << 2)
#define LINK_STATUS_X32_ADV_PKG_EN      (1u << 3)
#define LINK_STATUS_WIDTH_MASK          0x00000780u   // [10:7] Link Width enabled
#define LINK_STATUS_WIDTH_SHIFT         7
#define LINK_STATUS_SPEED_MASK          0x00007800u   // [14:11] Link Speed enabled
#define LINK_STATUS_SPEED_SHIFT         11
#define LINK_STATUS_LINK_UP             (1u << 15)    // [15] Link Status (Link Up)
#define LINK_STATUS_TRAINING            (1u << 16)    // [16] Link Training/Retraining

// =============================================================================
// Sideband Opcode Definitions
// =============================================================================
#define SB_OPC_32_MEM_READ     0x00
#define SB_OPC_32_MEM_WRITE    0x01
#define SB_OPC_32_CFG_READ     0x04
#define SB_OPC_32_CFG_WRITE    0x05

#define SB_OPC_64_MEM_READ     0x08
#define SB_OPC_64_MEM_WRITE    0x09
#define SB_OPC_64_CFG_READ     0x0C
#define SB_OPC_64_CFG_WRITE    0x0D

#define SB_OPC_CPL_WITHOUT_DATA 0x10
#define SB_OPC_CPL_WITH_32_DATA 0x11
#define SB_OPC_CPL_WITH_64_DATA 0x19

#define SB_OPC_MSG_WITH_64_DATA 0x1B

// =============================================================================
// Sideband Source & Destination IDs
// =============================================================================
#define SB_ID_ADAPTER          0x1
#define SB_ID_LOCAL_PHY        0x2
#define SB_ID_REMOTE_ADAPTER   0x5

// =============================================================================
// RDI State Enumeration (matching RDI_state package in RTL)
// =============================================================================
typedef enum {
    RDI_STATE_RESET = 0,
    RDI_STATE_ACTIVE = 1,
    RDI_STATE_ACTIVE_PMNAK = 2,
    RDI_STATE_L1 = 3,
    RDI_STATE_L2 = 4,
    RDI_STATE_LINK_RESET = 5,
    RDI_STATE_LINK_ERROR = 6,
    RDI_STATE_RETRAIN = 7,
    RDI_STATE_DISABLED = 8,
    RDI_STATE_NOP = 9
} UcieRdiState;

// =============================================================================
// EMIO GPIO bank + bit map  (must match the block-design slices/concat)
//
//   On Zynq UltraScale+ the EMIO GPIO is bank 3 (bits [24:0] = the 25-bit
//   emio_gpio_o / emio_gpio_i buses we wired in IP Integrator).
//
//   EMIO_O bits drive lp_* (PS -> PL), EMIO_I bits read pl_* (PL -> PS).
//   EMIO I and O are independent PL nets, so the overlapping index ranges are OK:
//   we set bits [7:0] as outputs (control) and read the whole bank for status.
// =============================================================================
#define UCIE_EMIO_BANK        3
#define UCIE_EMIO_CTRL_MASK   0x000000FF  // bits [7:0] are PS outputs (lp_*)

// ---- Control bits  (emio_gpio_o -> lp_*) ----
#define RDI_CTRL_LP_STATE_REQ_MASK   0x0000000F  // bits [3:0]
#define RDI_CTRL_LP_STATE_REQ_SHIFT  0
#define RDI_CTRL_LP_CLK_ACK_MASK     0x00000010  // bit 4
#define RDI_CTRL_LP_WAKE_REQ_MASK    0x00000020  // bit 5
#define RDI_CTRL_LP_STALLACK_MASK    0x00000040  // bit 6
#define RDI_CTRL_LP_LINKERROR_MASK   0x00000080  // bit 7

// ---- Status bits  (pl_* -> emio_gpio_i)  -- matches xlconcat_pl (In0 = bit0) ----
#define RDI_STAT_PL_CLK_REQ_MASK       0x00000001  // bit 0
#define RDI_STAT_PL_STALLREQ_MASK      0x00000002  // bit 1
#define RDI_STAT_PL_WAKE_ACK_MASK      0x00000004  // bit 2
#define RDI_STAT_PL_TRAINERROR_MASK    0x00000008  // bit 3
#define RDI_STAT_PL_INBAND_PRES_MASK   0x00000010  // bit 4
#define RDI_STAT_PL_PHYINRECENTER_MASK 0x00000020  // bit 5
#define RDI_STAT_PL_STATE_STS_MASK     0x000003C0  // bits [9:6]
#define RDI_STAT_PL_STATE_STS_SHIFT    6
#define RDI_STAT_PL_MAX_SPEEDMODE_MASK 0x00000400  // bit 10
#define RDI_STAT_PL_SPEEDMODE_MASK     0x00003800  // bits [13:11]
#define RDI_STAT_PL_SPEEDMODE_SHIFT    11
#define RDI_STAT_PL_LNK_CFG_MASK       0x0001C000  // bits [16:14]
#define RDI_STAT_PL_LNK_CFG_SHIFT      14
#define RDI_STAT_MB_RX_OVERFLOW_MASK   0x00020000  // bit 17
#define RDI_STAT_SB_RX_OVERFLOW_MASK   0x00040000  // bit 18

// =============================================================================
// Driver Structure  (single PS GPIO instance for both control + status)
// =============================================================================
typedef struct {
    XAxiDma  AxiDma;
    XLlFifo  AxiFifo;
    XGpioPs  Gpio;       // PS EMIO GPIO (bank 3)
    u32      CtrlShadow; // last value written to the EMIO output bits

    // ---- Lightweight event monitor (debug) ----
    u8       DbgEnable;  // 1 = print events, 0 = silent
    u8       DbgPrimed;  // 1 = DbgPrev* are valid (skip the first-call spam)
    u32      DbgTick;    // monotonic poll counter (rough timeline)
    u32      DbgPrevStat;// last RDI status word logged
    u32      DbgPrevRxOcc;// last RX FIFO occupancy logged
    u32      DbgPrevCtrl;// last control (lp_*) word logged
} UcieDriver;

// =============================================================================
// API
// =============================================================================
// Base addresses come from xparameters.h (Vitis 2025.2 SDT uses BaseAddress).
int Ucie_Init(UcieDriver *Dev, UINTPTR DmaBaseAddr, UINTPTR FifoBaseAddr, UINTPTR GpioBaseAddr);

// Raw RDI GPIO access
void Ucie_Rdi_WriteCtrl(UcieDriver *Dev, u32 CtrlBits);
u32  Ucie_Rdi_ReadStatus(UcieDriver *Dev);
void Ucie_Rdi_SetStateReq(UcieDriver *Dev, UcieRdiState State);

// Sideband configuration register access (64-bit)
int Ucie_Sb_WriteReg(UcieDriver *Dev, u32 RegAddr, u64 Data);
int Ucie_Sb_ReadReg(UcieDriver *Dev, u32 RegAddr, u64 *DataValPtr);

// Read + pretty-print the negotiated link parameters from LINK_STATUS (0x14).
// Returns the raw register value via *StatusOut (may be NULL if not needed).
int Ucie_Sb_DumpLinkStatus(UcieDriver *Dev, u64 *StatusOut);

// Remote message transfer over sideband loopback
int Ucie_Sb_SendRemoteMsg(UcieDriver *Dev, u8 MsgOpcode, u32 MsgInfo, u64 MsgData,
                          u32 *RxW0, u32 *RxW1, u32 *RxW2, u32 *RxW3);

// Link training management
int Ucie_StartTraining(UcieDriver *Dev);
int Ucie_BringUpActive(UcieDriver *Dev, u32 TimeoutMs); // request + service handshake until ACTIVE

// Mainband AXI DMA data transfer (cache-safe)
int Ucie_Mb_Transfer(UcieDriver *Dev, void *SrcAddr, void *DstAddr, u32 LengthBytes);

// =============================================================================
// Event monitor (debug). Ucie_Dbg_Poll() reads the RDI status + FIFO levels and
// prints a decoded one-liner ONLY when something changed since the last call, so
// you can drop it inside any polling loop to see exactly where bring-up stalls.
// Ucie_Dbg_Mark() forces an unconditional decoded line (a labelled checkpoint).
// =============================================================================
void Ucie_Dbg_Enable(UcieDriver *Dev, int on);
void Ucie_Dbg_Poll(UcieDriver *Dev, const char *where);
void Ucie_Dbg_Mark(UcieDriver *Dev, const char *where);

#endif // UCIE_DRIVER_H
