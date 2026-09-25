#include <stdio.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "ucie_driver.h"

// =============================================================================
// Base addresses come from ucie_driver.h (single source of truth, taken from
// the Vivado Address Editor). Override at compile time with -DDMA_BASEADDR=...
// etc. if ever neAeded; otherwise edit the values in ucie_driver.h.
// =============================================================================
#ifndef DMA_BASEADDR
#define DMA_BASEADDR        UCIE_DMA_BASEADDR
#endif
#ifndef FIFO_BASEADDR
#define FIFO_BASEADDR       UCIE_FIFO_BASEADDR
#endif
#ifndef GPIO_BASEADDR
#define GPIO_BASEADDR       UCIE_GPIO_BASEADDR
#endif
#ifndef BRAM_TX_BASEADDR
#define BRAM_TX_BASEADDR    UCIE_BRAM_TX_BASEADDR
#endif
#ifndef BRAM_RX_BASEADDR
#define BRAM_RX_BASEADDR    UCIE_BRAM_RX_BASEADDR
#endif

// MainBand flit = 512 bits = 64 bytes (DMA stream width must match)
#define FLIT_SIZE_BYTES     64
#define NUM_TEST_FLITS      16
#define TEST_DATA_BYTES     (FLIT_SIZE_BYTES * NUM_TEST_FLITS)

int main(void) {
    int Status;
    UcieDriver Ucie;

    xil_printf("====================================================\r\n");
    xil_printf("   UCIe 3.0 PHY - FPGA Loopback Bring-up Software    \r\n");
    xil_printf("====================================================\r\n");

    // 1. Init hardware (DMA + sideband FIFO + EMIO GPIO)
    xil_printf("[1] Init DMA / Sideband FIFO / EMIO GPIO...\r\n");
    Status = Ucie_Init(&Ucie, DMA_BASEADDR, FIFO_BASEADDR, GPIO_BASEADDR);
    if (Status != XST_SUCCESS) {
        xil_printf("    ERROR: hardware init failed (%d)\r\n", Status);
        return XST_FAILURE;
    }
    xil_printf("    OK.\r\n");

    // 2. Program PHY + start training over sideband
    xil_printf("[2] Programming PHY regs + starting training...\r\n");
    Status = Ucie_StartTraining(&Ucie);
    if (Status != XST_SUCCESS) {
        xil_printf("    ERROR: sideband config write failed (%d)\r\n", Status);
        return XST_FAILURE;
    }
    xil_printf("    OK.\r\n");

    // 3. Drive RDI to ACTIVE
    xil_printf("[3] Bringing RDI up to ACTIVE...\r\n");
    Status = Ucie_BringUpActive(&Ucie, 2000 /* ms budget */);
    if (Status != XST_SUCCESS) {
        u32 st = Ucie_Rdi_ReadStatus(&Ucie);
        xil_printf("    ERROR: link not ACTIVE (%d). status=0x%08X state=%u\r\n",
                   Status, st,
                   (unsigned)((st & RDI_STAT_PL_STATE_STS_MASK) >> RDI_STAT_PL_STATE_STS_SHIFT));
        return XST_FAILURE;
    }
    xil_printf("    SUCCESS: UCIe link is ACTIVE.\r\n");

    // 3a. Read back the negotiated training result from LINK_STATUS (0x14).
    xil_printf("    Negotiated link parameters (sideband read of 0x14):\r\n");
    (void)Ucie_Sb_DumpLinkStatus(&Ucie, NULL);

    // 3b. Sideband remote-message loopback
    xil_printf("[4] Sideband remote-message loopback...\r\n");
    u32 RxW0, RxW1, RxW2, RxW3;
    u8  TxOpc  = SB_OPC_MSG_WITH_64_DATA;
    u32 TxInfo = 0x123456;
    u64 TxData = 0xDEADBEEFCAFEF00DULL;

    // NOTE: this is an AUXILIARY test. A remote message (dstid=REMOTE_ADAPTER)
    // is NOT serviced locally like a reg-access; it must traverse the full
    // sideband message loopback path, which the golden TB does not exercise and
    // which is not wired in this self-loopback config. So treat a failure here as
    // a WARNING and continue to the MainBand DMA loopback (the real test).
    Status = Ucie_Sb_SendRemoteMsg(&Ucie, TxOpc, TxInfo, TxData, &RxW0, &RxW1, &RxW2, &RxW3);
    if (Status != XST_SUCCESS) {
        xil_printf("    WARN: remote message loopback failed (%d) - skipping (not "
                   "supported in this loopback). Continuing to MainBand test.\r\n", Status);
    } else {
        u8  RxOpc   = RxW0 & 0x1F;          // opcode [4:0]
        u32 RxInfo  = RxW1 & 0x00FFFFFF;     // MsgInfo/MsgSubcode [23:0]
        u32 RxDstId = (RxW1 >> 24) & 0x07;   // dstid [58:56] only (cp/dp sit in [31:30])
        // 64-bit data printed as two halves (xil_printf has no %ll support)
        xil_printf("    sent: opc=0x%02X info=0x%06X data=0x%08X_%08X\r\n",
                   TxOpc, TxInfo, (u32)(TxData >> 32), (u32)(TxData & 0xFFFFFFFF));
        xil_printf("    recv: opc=0x%02X info=0x%06X data=0x%08X_%08X dst=0x%02X\r\n",
                   RxOpc, RxInfo, RxW3, RxW2, RxDstId);

        if (RxOpc == TxOpc && RxInfo == TxInfo &&
            RxW2 == (u32)(TxData & 0xFFFFFFFF) && RxW3 == (u32)(TxData >> 32) &&
            RxDstId == SB_ID_REMOTE_ADAPTER) {
            xil_printf("    SUCCESS: sideband message looped back.\r\n");
        } else {
            xil_printf("    WARN: sideband message mismatch - continuing.\r\n");
        }
    }

    // 4. MainBand DMA loopback through BRAM
    xil_printf("[5] MainBand DMA loopback (%d bytes)...\r\n", TEST_DATA_BYTES);
    volatile u32 *Tx = (volatile u32 *)BRAM_TX_BASEADDR;
    volatile u32 *Rx = (volatile u32 *)BRAM_RX_BASEADDR;
    for (int i = 0; i < (TEST_DATA_BYTES / 4); i++) {
        Tx[i] = 0xAA550000u + (u32)i;
        Rx[i] = 0x00000000u;
    }

    Status = Ucie_Mb_Transfer(&Ucie, (void *)BRAM_TX_BASEADDR,
                              (void *)BRAM_RX_BASEADDR, TEST_DATA_BYTES);
    if (Status != XST_SUCCESS) {
        xil_printf("    ERROR: MainBand DMA transfer failed (%d)\r\n", Status);
        return XST_FAILURE;
    }

    // 5. Verify
    int Mismatches = 0;
    for (int i = 0; i < (TEST_DATA_BYTES / 4); i++) {
        if (Tx[i] != Rx[i]) {
            if (Mismatches < 8) {
                xil_printf("    mismatch[%d]: tx=0x%08X rx=0x%08X\r\n", i, Tx[i], Rx[i]);
            }
            Mismatches++;
        }
    }

    xil_printf("====================================================\r\n");
    if (Mismatches == 0) {
        xil_printf("              TEST RESULT: PASS\r\n");
    } else {
        xil_printf("              TEST RESULT: FAIL (%d mismatches)\r\n", Mismatches);
    }
    xil_printf("====================================================\r\n");

    return (Mismatches == 0) ? XST_SUCCESS : XST_FAILURE;
}
