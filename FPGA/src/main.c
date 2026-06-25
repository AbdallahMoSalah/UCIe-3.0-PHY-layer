#include <stdio.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "ucie_driver.h"

// =============================================================================
// Device IDs from xparameters.h
// Modify these to match your actual Vivado design system names if necessary
// =============================================================================
#ifndef XPAR_AXIDMA_0_DEVICE_ID
#define DMA_DEV_ID          XPAR_AXI_DMA_0_DEVICE_ID
#else
#define DMA_DEV_ID          0 // Default device ID for first DMA
#endif

#ifndef XPAR_AXI_FIFO_0_DEVICE_ID
#define FIFO_DEV_ID         XPAR_AXI_FIFO_0_DEVICE_ID
#else
#define FIFO_DEV_ID         0 // Default device ID for first FIFO
#endif

#ifndef XPAR_AXI_GPIO_0_DEVICE_ID
#define GPIO_CTRL_DEV_ID    XPAR_AXI_GPIO_0_DEVICE_ID
#else
#define GPIO_CTRL_DEV_ID    0 // Default device ID for control GPIO
#endif

#ifndef XPAR_AXI_GPIO_1_DEVICE_ID
#define GPIO_STAT_DEV_ID    XPAR_AXI_GPIO_1_DEVICE_ID
#else
#define GPIO_STAT_DEV_ID    1 // Default device ID for status GPIO
#endif

// Mainband word width on Zynq (flit size = 512 bits = 64 bytes)
#define FLIT_SIZE_BYTES     64
#define NUM_TEST_FLITS      16
#define TEST_DATA_BYTES     (FLIT_SIZE_BYTES * NUM_TEST_FLITS)

// =============================================================================
// BRAM Base Addresses for Mainband Path (instead of DDR)
// =============================================================================
#ifndef XPAR_BRAM_0_BASEADDR
#define BRAM_TX_BASEADDR    0xC0000000 // Placeholder TX BRAM base address
#else
#define BRAM_TX_BASEADDR    XPAR_BRAM_0_BASEADDR
#endif

#ifndef XPAR_BRAM_1_BASEADDR
#define BRAM_RX_BASEADDR    0xC0002000 // Placeholder RX BRAM base address
#else
#define BRAM_RX_BASEADDR    XPAR_BRAM_1_BASEADDR
#endif

// =============================================================================
// Main function
// =============================================================================
int main() {
    int Status;
    UcieDriver UcieInstance;
    int IsActive = 0;
    int Timeout = 10000; // Loopback training polling timeout

    xil_printf("====================================================\r\n");
    xil_printf("     Universal Chiplet Interconnect Express (UCIe)   \r\n");
    xil_printf("          FPGA Loopback Bring-up Software            \r\n");
    xil_printf("====================================================\r\n");

    // 1. Initialize UCIe Driver (DMA, Sideband FIFO, and GPIOs)
    xil_printf("Initializing hardware DMA, Sideband FIFO, and GPIOs...\r\n");
    Status = Ucie_Init(&UcieInstance, DMA_DEV_ID, FIFO_DEV_ID, GPIO_CTRL_DEV_ID, GPIO_STAT_DEV_ID);
    if (Status != XST_SUCCESS) {
        xil_printf("Error: Hardware initialization failed!\r\n");
        return XST_FAILURE;
    }
    xil_printf("Hardware initialization OK.\r\n");

    // 2. Start Sideband Link Training
    xil_printf("Programming PHY registers and initiating training...\r\n");
    Status = Ucie_StartTraining(&UcieInstance);
    if (Status != XST_SUCCESS) {
        xil_printf("Error: Sideband register write configuration failed!\r\n");
        return XST_FAILURE;
    }

    // 3. Poll Link Status until ACTIVE
    xil_printf("Waiting for Link Training State Machine to reach ACTIVE state...\r\n");
    while (Timeout > 0) {
        Status = Ucie_CheckLinkActive(&UcieInstance, &IsActive);
        if (Status == XST_SUCCESS && IsActive) {
            break;
        }
        usleep(500); // Wait 500us
        Timeout--;
    }

    if (Timeout <= 0) {
        xil_printf("Error: Link training TIMEOUT! Link failed to train.\r\n");
        return XST_FAILURE;
    }
    xil_printf("SUCCESS: UCIe Link is ACTIVE!\r\n");

    // 3b. Test Remote Sideband Message Loopback
    xil_printf("Testing Remote Sideband Message loopback...\r\n");
    u8 TxMsgOpcode = SB_OPC_MSG_WITH_64_DATA;
    u32 TxMsgInfo = 0x123456;
    u64 TxMsgData = 0xDEADBEEFCAFEF00DULL;
    u32 RxW0, RxW1, RxW2, RxW3;

    Status = Ucie_Sb_SendRemoteMsg(&UcieInstance, TxMsgOpcode, TxMsgInfo, TxMsgData, &RxW0, &RxW1, &RxW2, &RxW3);
    if (Status != XST_SUCCESS) {
        xil_printf("Error: Remote message loopback failed! Status: %d\r\n", Status);
        return XST_FAILURE;
    }

    // Deconstruct and check received fields
    u8 RxMsgOpcode = RxW0 & 0xFF;
    u32 RxMsgInfo = RxW1 & 0x00FFFFFF;
    u64 RxMsgData = ((u64)RxW3 << 32) | RxW2;
    u32 RxDstId = (RxW1 >> 24) & 0xFF;
    u32 RxSrcId = (RxW0 >> 29) & 0x7;

    xil_printf("Sent Message: Opcode=0x%02X, Info=0x%06X, Data=0x%016llX, DstId=0x%02X, SrcId=0x%02X\r\n", 
               TxMsgOpcode, TxMsgInfo, (unsigned long long)TxMsgData, SB_ID_REMOTE_ADAPTER, SB_ID_ADAPTER);
    xil_printf("Recv Message: Opcode=0x%02X, Info=0x%06X, Data=0x%016llX, DstId=0x%02X, SrcId=0x%02X\r\n", 
               RxMsgOpcode, RxMsgInfo, (unsigned long long)RxMsgData, RxDstId, RxSrcId);

    if (RxMsgOpcode == TxMsgOpcode && RxMsgInfo == TxMsgInfo && RxMsgData == TxMsgData && RxDstId == SB_ID_REMOTE_ADAPTER) {
        xil_printf("SUCCESS: Sideband remote message looped back perfectly!\r\n");
    } else {
        xil_printf("Error: Sideband remote message mismatch!\r\n");
        return XST_FAILURE;
    }

    // 4. Populate test data pattern in DDR source buffer
    // 4. Populate test data pattern in TX BRAM
    xil_printf("Generating test data pattern in TX BRAM (16 flits of 512-bit data)...\r\n");
    volatile u32 *BramTxPtr = (volatile u32 *)BRAM_TX_BASEADDR;
    volatile u32 *BramRxPtr = (volatile u32 *)BRAM_RX_BASEADDR;
    for (int i = 0; i < (TEST_DATA_BYTES / 4); i++) {
        BramTxPtr[i] = 0xAA550000 + i; // alternating pattern + increment
        BramRxPtr[i] = 0x00000000;     // clear destination buffer in RX BRAM
    }

    // 5. Run Mainband AXI DMA simple loopback transfer
    xil_printf("Triggering Mainband data loopback transfer via AXI DMA...\r\n");
    Status = Ucie_Mb_Transfer(&UcieInstance, (u32 *)BRAM_TX_BASEADDR, (u32 *)BRAM_RX_BASEADDR, TEST_DATA_BYTES);
    if (Status != XST_SUCCESS) {
        xil_printf("Error: Mainband AXI DMA transfer failed!\r\n");
        return XST_FAILURE;
    }

    // 6. Verify data integrity
    xil_printf("Verifying received data integrity in RX BRAM...\r\n");
    int Mismatches = 0;
    for (int i = 0; i < (TEST_DATA_BYTES / 4); i++) {
        if (BramTxPtr[i] != BramRxPtr[i]) {
            xil_printf("Mismatch at index %d: Sent 0x%08X, Received 0x%08X\r\n", 
                       i, BramTxPtr[i], BramRxPtr[i]);
            Mismatches++;
        }
    }

    xil_printf("====================================================\r\n");
    if (Mismatches == 0) {
        xil_printf("             TEST RESULT: PASS                      \r\n");
        xil_printf("   Mainband data looped back with 100%% integrity!   \r\n");
    } else {
        xil_printf("             TEST RESULT: FAIL                      \r\n");
        xil_printf("   Found %d mismatched words in loopback transfer!  \r\n", Mismatches);
    }
    xil_printf("====================================================\r\n");

    return (Mismatches == 0) ? XST_SUCCESS : XST_FAILURE;
}
