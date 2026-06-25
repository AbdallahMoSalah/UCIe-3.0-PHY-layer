#ifndef UCIE_DRIVER_H
#define UCIE_DRIVER_H

#include "xil_types.h"
#include "xstatus.h"
#include "xaxidma.h"
#include "xllfifo.h"

#include "xgpio.h"

// =============================================================================
// UCIe sideband register addresses (Offsets)
// =============================================================================
#define REG_UCIE_LINK_CTRL    0x000010
#define REG_PHY_CONTROL       0x001004
#define REG_TRAIN_SETUP4      0x001050
#define REG_UCIE_LINK_STATUS  0x000014

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

// =============================================================================
// Sideband Source & Destination IDs
// =============================================================================
#define SB_ID_ADAPTER          0x1
#define SB_ID_LOCAL_PHY        0x2
#define SB_ID_REMOTE_ADAPTER   0x5

#define SB_OPC_MSG_WITH_64_DATA 0x1B

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
// GPIO Pin Masks
// =============================================================================
// AXI GPIO #0 (RDI control - output from CPU)
#define RDI_CTRL_LP_STATE_REQ_MASK   0x0F  // Bits [3:0]
#define RDI_CTRL_LP_CLK_ACK_MASK     0x10  // Bit 4
#define RDI_CTRL_LP_WAKE_REQ_MASK    0x20  // Bit 5
#define RDI_CTRL_LP_STALLACK_MASK    0x40  // Bit 6
#define RDI_CTRL_LP_LINKERROR_MASK   0x80  // Bit 7

// AXI GPIO #1 (RDI status - input to CPU)
#define RDI_STAT_PL_STATE_STS_MASK     0x0000000F  // Bits [3:0]
#define RDI_STAT_PL_CLK_REQ_MASK       0x00000010  // Bit 4
#define RDI_STAT_PL_STALLREQ_MASK      0x00000020  // Bit 5
#define RDI_STAT_PL_WAKE_ACK_MASK      0x00000040  // Bit 6
#define RDI_STAT_PL_TRAINERROR_MASK    0x00000080  // Bit 7
#define RDI_STAT_PL_INBAND_PRES_MASK   0x00000100  // Bit 8
#define RDI_STAT_PL_PHYINRECENTER_MASK 0x00000200  // Bit 9
#define RDI_STAT_PL_SPEEDMODE_MASK     0x00001C00  // Bits [12:10]
#define RDI_STAT_PL_LNK_CFG_MASK       0x0000E000  // Bits [15:13]
#define RDI_STAT_PL_MAX_SPEEDMODE_MASK 0x00010000  // Bit 16

// =============================================================================
// Driver Structures
// =============================================================================
typedef struct {
    XAxiDma AxiDmaInstance;
    XLlFifo AxiFifoInstance;
    XGpio   GpioCtrlInstance; // GPIO #0 (RDI Control)
    XGpio   GpioStatInstance; // GPIO #1 (RDI Status)
    u32     DmaDeviceId;
    u32     FifoDeviceId;
    u32     GpioCtrlDeviceId;
    u32     GpioStatDeviceId;
} UcieDriver;

// =============================================================================
// API Declarations
// =============================================================================

// Initialization
int Ucie_Init(UcieDriver *InstancePtr, u16 DmaDeviceId, u16 FifoDeviceId, u16 GpioCtrlDeviceId, u16 GpioStatDeviceId);

// Sideband configuration register access (64-bit)
int Ucie_Sb_WriteReg(UcieDriver *InstancePtr, u32 RegAddr, u64 Data);
int Ucie_Sb_ReadReg(UcieDriver *InstancePtr, u32 RegAddr, u64 *DataValPtr);

// Remote message transfer over sideband loopback
int Ucie_Sb_SendRemoteMsg(UcieDriver *InstancePtr, u8 MsgOpcode, u32 MsgInfo, u64 MsgData, u32 *RxWord0, u32 *RxWord1, u32 *RxWord2, u32 *RxWord3);

// Link training management
int Ucie_StartTraining(UcieDriver *InstancePtr);
int Ucie_CheckLinkActive(UcieDriver *InstancePtr, int *IsActivePtr);

// Mainband AXI DMA Data Transfer
int Ucie_Mb_Transfer(UcieDriver *InstancePtr, u32 *SrcAddr, u32 *DstAddr, u32 LengthBytes);

#endif // UCIE_DRIVER_H
