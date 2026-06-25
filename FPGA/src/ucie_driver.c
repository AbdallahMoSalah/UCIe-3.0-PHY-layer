#include "ucie_driver.h"
#include "xparameters.h"

// =============================================================================
// Helper function to wait for incoming RX packets in the FIFO
// =============================================================================
static int Ucie_Wait_Rx_Fifo(XLlFifo *FifoPtr, u32 ExpectedBytes, u32 TimeoutUs) {
    u32 elapsed = 0;
    while (XLlFifo_RxOccupancy(FifoPtr) < (ExpectedBytes / 4)) {
        usleep(1);
        elapsed++;
        if (elapsed >= TimeoutUs) {
            return XST_TIMEOUT;
        }
    }
    return XST_SUCCESS;
}


// =============================================================================
// Initialize AXI DMA, AXI FIFO, and AXI GPIOs
// =============================================================================
int Ucie_Init(UcieDriver *InstancePtr, u16 DmaDeviceId, u16 FifoDeviceId, u16 GpioCtrlDeviceId, u16 GpioStatDeviceId) {
    int Status;
    XAxiDma_Config *DmaConfig;
    XLlFifo_Config *FifoConfig;

    InstancePtr->DmaDeviceId = DmaDeviceId;
    InstancePtr->FifoDeviceId = FifoDeviceId;
    InstancePtr->GpioCtrlDeviceId = GpioCtrlDeviceId;
    InstancePtr->GpioStatDeviceId = GpioStatDeviceId;

    // 1. Initialize AXI DMA
    DmaConfig = XAxiDma_LookupConfig(DmaDeviceId);
    if (!DmaConfig) {
        return XST_FAILURE;
    }

    Status = XAxiDma_CfgInitialize(&InstancePtr->AxiDmaInstance, DmaConfig);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // Disable DMA Interrupts for simple polling mode
    XAxiDma_IntrDisable(&InstancePtr->AxiDmaInstance, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&InstancePtr->AxiDmaInstance, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    // 2. Initialize AXI FIFO
    FifoConfig = XLlFifo_LookupConfig(FifoDeviceId);
    if (!FifoConfig) {
        return XST_FAILURE;
    }

    Status = XLlFifo_CfgInitialize(&InstancePtr->AxiFifoInstance, FifoConfig, FifoConfig->BaseAddress);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // Reset FIFO
    XLlFifo_Reset(&InstancePtr->AxiFifoInstance);

    // 3. Initialize GPIO #0 (RDI Control)
    Status = XGpio_Initialize(&InstancePtr->GpioCtrlInstance, GpioCtrlDeviceId);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }
    // Channel 1: set direction to all outputs (0x00000000)
    XGpio_SetDataDirection(&InstancePtr->GpioCtrlInstance, 1, 0x00000000);

    // Set initial control state: lp_state_req = NOP, all other controls = 0
    XGpio_DiscreteWrite(&InstancePtr->GpioCtrlInstance, 1, RDI_STATE_NOP);

    // 4. Initialize GPIO #1 (RDI Status)
    Status = XGpio_Initialize(&InstancePtr->GpioStatInstance, GpioStatDeviceId);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }
    // Channel 1: set direction to all inputs (0xFFFFFFFF)
    XGpio_SetDataDirection(&InstancePtr->GpioStatInstance, 1, 0xFFFFFFFF);

    return XST_SUCCESS;
}

// =============================================================================
// Write Register over Sideband (64-bit Access)
// =============================================================================
int Ucie_Sb_WriteReg(UcieDriver *InstancePtr, u32 RegAddr, u64 Data) {
    u32 opc = (RegAddr >= 0x1000) ? SB_OPC_64_MEM_WRITE : SB_OPC_64_CFG_WRITE;
    u32 be = 0xFF; // enable all bytes for 64-bit access
    u32 tag = 0x0;
    u32 srcid = SB_ID_ADAPTER;
    u32 dstid = SB_ID_LOCAL_PHY;

    // Pack headers into 32-bit chunks
    u32 word0 = (srcid << 29) | (tag << 20) | (be << 12) | opc;
    u32 word1 = (dstid << 24) | (RegAddr & 0x00FFFFFF);
    u32 word2 = (u32)(Data & 0xFFFFFFFF);
    u32 word3 = (u32)((Data >> 32) & 0xFFFFFFFF);

    // Write chunks to TX FIFO
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word0, 4);
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word1, 4);
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word2, 4);
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word3, 4);

    // Initiate transmission (16 bytes = 4 chunks)
    XLlFifo_TxExecute(&InstancePtr->AxiFifoInstance, 16);

    // Wait for the completion packet (SB_COMPLETION_WITHOUT_DATA = 8 bytes = 2 chunks)
    int Status = Ucie_Wait_Rx_Fifo(&InstancePtr->AxiFifoInstance, 8, 100000); // 100ms timeout
    if (Status != XST_SUCCESS) {
        return XST_TIMEOUT;
    }

    u32 rx_len = XLlFifo_RxGetLen(&InstancePtr->AxiFifoInstance);
    if (rx_len != 8) {
        // Read out garbage to clear FIFO
        for (u32 i = 0; i < (rx_len / 4); i++) {
            (void)XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
        }
        return XST_FAILURE;
    }

    u32 cpl0 = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
    u32 cpl1 = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);

    // Check completion status (status is in cpl1[2:0] for no-data completion)
    u32 cpl_status = cpl1 & 0x7;
    if (cpl_status != 0) {
        return XST_FAILURE; // Completion error status returned
    }

    return XST_SUCCESS;
}

// =============================================================================
// Read Register over Sideband (64-bit Access)
// =============================================================================
int Ucie_Sb_ReadReg(UcieDriver *InstancePtr, u32 RegAddr, u64 *DataValPtr) {
    u32 opc = (RegAddr >= 0x1000) ? SB_OPC_64_MEM_READ : SB_OPC_64_CFG_READ;
    u32 be = 0xFF; // enable all bytes for 64-bit access
    u32 tag = 0x0;
    u32 srcid = SB_ID_ADAPTER;
    u32 dstid = SB_ID_LOCAL_PHY;

    // Pack headers
    u32 word0 = (srcid << 29) | (tag << 20) | (be << 12) | opc;
    u32 word1 = (dstid << 24) | (RegAddr & 0x00FFFFFF);

    // Write chunks to TX FIFO (8 bytes = 2 chunks)
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word0, 4);
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word1, 4);

    // Initiate transmission
    XLlFifo_TxExecute(&InstancePtr->AxiFifoInstance, 8);

    // Wait for completion packet (SB_COMPLETION_WITH_64_DATA = 16 bytes = 4 chunks)
    int Status = Ucie_Wait_Rx_Fifo(&InstancePtr->AxiFifoInstance, 16, 100000);
    if (Status != XST_SUCCESS) {
        return XST_TIMEOUT;
    }

    u32 rx_len = XLlFifo_RxGetLen(&InstancePtr->AxiFifoInstance);
    if (rx_len != 16) {
        for (u32 i = 0; i < (rx_len / 4); i++) {
            (void)XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
        }
        return XST_FAILURE;
    }

    u32 cpl0 = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
    u32 cpl1 = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
    u32 data_low = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
    u32 data_high = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);

    // Check completion status (status is in cpl1[2:0] for with-data completion)
    u32 cpl_status = (cpl1 >> 0) & 0x7;
    if (cpl_status != 0) {
        return XST_FAILURE;
    }

    *DataValPtr = ((u64)data_high << 32) | data_low;
    return XST_SUCCESS;
}

// =============================================================================
// Send Remote Message over Sideband (Loops back to the local RX FIFO)
// =============================================================================
int Ucie_Sb_SendRemoteMsg(UcieDriver *InstancePtr, u8 MsgOpcode, u32 MsgInfo, u64 MsgData, u32 *RxWord0, u32 *RxWord1, u32 *RxWord2, u32 *RxWord3) {
    u32 tag = 0x0;
    u32 be = 0xFF;
    u32 srcid = SB_ID_ADAPTER;
    u32 dstid = SB_ID_REMOTE_ADAPTER;

    // Pack headers into 32-bit chunks
    u32 word0 = (srcid << 29) | (tag << 20) | (be << 12) | MsgOpcode;
    u32 word1 = (dstid << 24) | (MsgInfo & 0x00FFFFFF);
    u32 word2 = (u32)(MsgData & 0xFFFFFFFF);
    u32 word3 = (u32)((MsgData >> 32) & 0xFFFFFFFF);

    // Write chunks to TX FIFO (exactly 16 bytes = 4 chunks)
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word0, 4);
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word1, 4);
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word2, 4);
    XLlFifo_Write(&InstancePtr->AxiFifoInstance, &word3, 4);

    // Initiate transmission
    XLlFifo_TxExecute(&InstancePtr->AxiFifoInstance, 16);

    // Wait for the looped back packet in RX FIFO (exactly 16 bytes = 4 chunks)
    int Status = Ucie_Wait_Rx_Fifo(&InstancePtr->AxiFifoInstance, 16, 100000); // 100ms timeout
    if (Status != XST_SUCCESS) {
        return XST_TIMEOUT;
    }

    u32 rx_len = XLlFifo_RxGetLen(&InstancePtr->AxiFifoInstance);
    if (rx_len != 16) {
        // Read out garbage to clear FIFO
        for (u32 i = 0; i < (rx_len / 4); i++) {
            (void)XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
        }
        return XST_FAILURE;
    }

    *RxWord0 = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
    *RxWord1 = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
    *RxWord2 = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);
    *RxWord3 = XLlFifo_RxGetWord(&InstancePtr->AxiFifoInstance);

    return XST_SUCCESS;
}

// =============================================================================
// Start Link Training
// =============================================================================
int Ucie_StartTraining(UcieDriver *InstancePtr) {
    int Status;

    // 1. Configure training setup parameters
    // Equivalent to program_die: setup link control and speed caps
    // Program TRAIN_SETUP4 timer values
    Status = Ucie_Sb_WriteReg(InstancePtr, REG_TRAIN_SETUP4, 0x00000000003200A0ULL);
    if (Status != XST_SUCCESS) return Status;

    // Program PHY_CONTROL to force x8 or default mode
    Status = Ucie_Sb_WriteReg(InstancePtr, REG_PHY_CONTROL, 0x0000000000200060ULL);
    if (Status != XST_SUCCESS) return Status;

    // 2. Start training via LINK_CTRL register
    // Set Target Link Width = 4'h2, Target Speed = 4'h5, Start Training = 1
    u64 link_ctrl_val = 0ULL;
    link_ctrl_val |= (0x2ULL << 2);   // Target Link Width
    link_ctrl_val |= (0x5ULL << 6);   // Target Speed
    link_ctrl_val |= (0x1ULL << 10);  // Start Training bit
    
    Status = Ucie_Sb_WriteReg(InstancePtr, REG_UCIE_LINK_CTRL, link_ctrl_val);
    return Status;
}

// =============================================================================
// Poll Link Training Status (Check if ACTIVE)
// =============================================================================
int Ucie_CheckLinkActive(UcieDriver *InstancePtr, int *IsActivePtr) {
    u32 stat_val;
    u32 ctrl_val;

    // Read status GPIO
    stat_val = XGpio_DiscreteRead(&InstancePtr->GpioStatInstance, 1);

    // Check if already in ACTIVE state
    u32 state_sts = stat_val & RDI_STAT_PL_STATE_STS_MASK;
    if (state_sts == RDI_STATE_ACTIVE) {
        *IsActivePtr = 1;
        return XST_SUCCESS;
    }

    // If not active, check if inband presence is asserted (training done)
    if (stat_val & RDI_STAT_PL_INBAND_PRES_MASK) {
        // Request active state: set lp_state_req = ACTIVE (1)
        ctrl_val = XGpio_DiscreteRead(&InstancePtr->GpioCtrlInstance, 1);
        ctrl_val = (ctrl_val & ~RDI_CTRL_LP_STATE_REQ_MASK) | RDI_STATE_ACTIVE;
        XGpio_DiscreteWrite(&InstancePtr->GpioCtrlInstance, 1, ctrl_val);

        // Perform active handshake loop (echo pl_clk_req -> lp_clk_ack, pl_stallreq -> lp_stallack)
        u32 timeout = 50000; // timeout loop count
        while (timeout > 0) {
            stat_val = XGpio_DiscreteRead(&InstancePtr->GpioStatInstance, 1);
            state_sts = stat_val & RDI_STAT_PL_STATE_STS_MASK;

            if (state_sts == RDI_STATE_ACTIVE) {
                *IsActivePtr = 1;
                return XST_SUCCESS;
            }

            // Echo pl_clk_req (bit 4) to lp_clk_ack (bit 4)
            u32 clk_req = (stat_val & RDI_STAT_PL_CLK_REQ_MASK) ? 1 : 0;
            // Echo pl_stallreq (bit 5) to lp_stallack (bit 6)
            u32 stall_req = (stat_val & RDI_STAT_PL_STALLREQ_MASK) ? 1 : 0;

            ctrl_val = XGpio_DiscreteRead(&InstancePtr->GpioCtrlInstance, 1);
            if (clk_req) {
                ctrl_val |= RDI_CTRL_LP_CLK_ACK_MASK;
            } else {
                ctrl_val &= ~RDI_CTRL_LP_CLK_ACK_MASK;
            }

            if (stall_req) {
                ctrl_val |= RDI_CTRL_LP_STALLACK_MASK;
            } else {
                ctrl_val &= ~RDI_CTRL_LP_STALLACK_MASK;
            }

            XGpio_DiscreteWrite(&InstancePtr->GpioCtrlInstance, 1, ctrl_val);

            usleep(10);
            timeout--;
        }

        *IsActivePtr = 0;
        return XST_TIMEOUT;
    }

    // Inband presence is not high yet, link is still training
    *IsActivePtr = 0;
    return XST_SUCCESS;
}

// =============================================================================
// MainBand AXI DMA Loopback Transfer
// =============================================================================
int Ucie_Mb_Transfer(UcieDriver *InstancePtr, u32 *SrcAddr, u32 *DstAddr, u32 LengthBytes) {
    int Status;

    // Cache operations are omitted here because we are using dedicated BRAM blocks 
    // for the Mainband loopback memory mapping (which is non-cacheable).

    // 1. Setup Receive (S2MM) Channel
    Status = XAxiDma_SimpleTransfer(&InstancePtr->AxiDmaInstance, (UINTPTR)DstAddr, LengthBytes, XAXIDMA_DEVICE_TO_DMA);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // 2. Setup Transmit (MM2S) Channel
    Status = XAxiDma_SimpleTransfer(&InstancePtr->AxiDmaInstance, (UINTPTR)SrcAddr, LengthBytes, XAXIDMA_DMA_TO_DEVICE);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    // 3. Poll for S2MM Receive Channel Completion
    while (XAxiDma_Busy(&InstancePtr->AxiDmaInstance, XAXIDMA_DEVICE_TO_DMA)) {
        // Wait
    }

    // 4. Poll for MM2S Transmit Channel Completion
    while (XAxiDma_Busy(&InstancePtr->AxiDmaInstance, XAXIDMA_DMA_TO_DEVICE)) {
        // Wait
    }

    return XST_SUCCESS;
}
