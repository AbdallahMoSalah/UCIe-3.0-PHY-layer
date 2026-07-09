#include <stdio.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "sleep.h"
#include "ucie_driver.h"

// =============================================================================
// UCIe 3.0 PHY - FPGA FAULT-INJECTION bring-up software.
//
//   Companion to the plain loopback main.c, targeting the fault-injection
//   bitstream (top = UCIe_FPGA_top_wrapper_fi): a single die self-looped through
//   ucie_loopback_fault_injector, whose taps are driven from the shared RDI/FI
//   EMIO GPIO bank (bank 3, fault-control bits [27:8]).
//
//   It reproduces, on real hardware, the error-injection scenarios of
//   tb/integration/UCIe_PHY/UCIe_PHY_wrapper_tb.sv - corrupt lanes, lane
//   reversal, valid-strobe error, blocked sideband - plus the programmed
//   width/speed/force-x8 variations, each followed by a MainBand DMA data check.
//
//   Old main.c is kept as main_loopback_ref.c.txt in this folder; the driver
//   functions are reused verbatim (see ucie_driver.c) with fault-injection
//   helpers added (Ucie_Fi_*).
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

#define BRINGUP_MS          2000    // budget to reach ACTIVE (happy path)
#define FAIL_MS             1000    // budget before declaring "did not train"

// Width / speed codes (spec Table 9-9, mirrored from ucie_config.h comments):
//   width: 0x1=x8 0x2=x16 0x3=x32 ...     speed: 0x0=4 0x1=8 0x2=12 0x3=16 0x4=24 ...
#define W_X16   0x2
#define W_X8    0x1
#define S_8G    0x1
#define S_16G   0x3
#define S_24G   0x4

// What to assert for a scenario's outcome.
enum { CHK_ACTIVE_DATA = 0,   // must reach ACTIVE and DMA data must match
       CHK_NO_ACTIVE   = 1,   // must FAIL to reach ACTIVE (TRAINERROR/timeout)
       CHK_INFO        = 2 }; // just report what happens (no pass/fail gate)

typedef struct {
    const char *name;
    u8   width;
    u8   speed;
    int  force_x8;
    u16  corrupt;        // per-lane stuck-at-0 mask (bit i -> lane i)
    int  reverse;
    int  vld_err;
    int  block_sb;
    int  check;
} Scenario;

// -----------------------------------------------------------------------------
// Scenario table - the UCIe_PHY_wrapper_tb faults, folded onto one die.
//   Toggle any entry off by clearing its bit in `enabled` below.
// -----------------------------------------------------------------------------
static const Scenario kScenarios[] = {
  // name                              width  speed  x8  corrupt  rev vld  sb  check
  { "SC1  Happy path (no faults)",     W_X16, S_8G,  0,  0x0000,  0,  0,   0,  CHK_ACTIVE_DATA },
  { "SC3  Force x8 width mode",        W_X16, S_8G,  1,  0x0000,  0,  0,   0,  CHK_ACTIVE_DATA },
  { "SC9  Lower speed 16 GT/s",        W_X16, S_16G, 0,  0x0000,  0,  0,   0,  CHK_ACTIVE_DATA },
  { "SC4  Lane reversal",              W_X16, S_8G,  0,  0x0000,  1,  0,   0,  CHK_ACTIVE_DATA },
  { "SC6  Corrupt lanes 8..15 ->x8",   W_X16, S_8G,  0,  0xFF00,  0,  0,   0,  CHK_ACTIVE_DATA },
  { "SC7  Corrupt lanes 0..7  ->x8",   W_X16, S_8G,  0,  0x00FF,  0,  0,   0,  CHK_ACTIVE_DATA },
  { "SC2  Block sideband (TrainErr)",  W_X16, S_8G,  0,  0x0000,  0,  0,   1,  CHK_NO_ACTIVE   },
  { "SCx  Corrupt ALL lanes",          W_X16, S_8G,  0,  0xFFFF,  0,  0,   0,  CHK_NO_ACTIVE   },
  { "SCx  Valid-strobe error",         W_X16, S_8G,  0,  0x0000,  0,  1,   0,  CHK_INFO        },
};
#define N_SCENARIOS  (int)(sizeof(kScenarios)/sizeof(kScenarios[0]))

// Bitmask of enabled scenarios (bit i -> kScenarios[i]). Default: all on.
static u32 enabled = 0xFFFFFFFFu;

// -----------------------------------------------------------------------------
// MainBand DMA loopback data check. Returns 1 on match, 0 on mismatch.
// -----------------------------------------------------------------------------
static int Run_Mb_Data_Check(UcieDriver *Ucie) {
    volatile u32 *Tx = (volatile u32 *)BRAM_TX_BASEADDR;
    volatile u32 *Rx = (volatile u32 *)BRAM_RX_BASEADDR;
    for (int i = 0; i < (TEST_DATA_BYTES / 4); i++) {
        Tx[i] = 0xAA550000u + (u32)i;
        Rx[i] = 0x00000000u;
    }
    int s = Ucie_Mb_Transfer(Ucie, (void *)BRAM_TX_BASEADDR,
                             (void *)BRAM_RX_BASEADDR, TEST_DATA_BYTES);
    if (s != XST_SUCCESS) {
        xil_printf("      DMA transfer failed (%d)\r\n", s);
        return 0;
    }
    int mism = 0;
    for (int i = 0; i < (TEST_DATA_BYTES / 4); i++) {
        if (Tx[i] != Rx[i]) {
            if (mism < 4)
                xil_printf("      mismatch[%d]: tx=0x%08X rx=0x%08X\r\n", i, Tx[i], Rx[i]);
            mism++;
        }
    }
    return (mism == 0);
}

// -----------------------------------------------------------------------------
// Run one scenario. Returns 1 = scenario passed its check, 0 = failed.
// -----------------------------------------------------------------------------
static int Run_Scenario(UcieDriver *Ucie, const Scenario *s, int first) {
    // Let the UART TX FIFO drain so output doesn't garble across scenarios.
    usleep(50000);

    xil_printf("\r\n---------------------------------------------------------\r\n");
    xil_printf("[%s]\r\n", s->name);
    xil_printf("  faults: corrupt=0x%04X reverse=%d vld_err=%d block_sb=%d | "
               "w=0x%X s=0x%X x8=%d\r\n",
               s->corrupt, s->reverse, s->vld_err, s->block_sb,
               s->width, s->speed, s->force_x8);

    // Fresh link for each scenario: hardware-reset the RTL (EMIO bit 27, active
    // low) so every scenario starts from a true cold state, then return the PS
    // control lines to idle and flush any stale sideband completions.
    if (!first) {
        Ucie_Fi_ResetRtl(Ucie, 500);
        Ucie_Rdi_WriteCtrl(Ucie, (u32)RDI_STATE_NOP & RDI_CTRL_LP_STATE_REQ_MASK);
    }
    Ucie_Sb_FlushRx(Ucie);   // flush even on the very first scenario

    // Apply the fault taps BEFORE training so they are present during bring-up.
    Ucie_Fi_Set(Ucie, s->corrupt, s->reverse, s->vld_err, s->block_sb);

    // Program caps + start training with this scenario's targets.
    if (Ucie_StartTrainingCustom(Ucie, s->width, s->speed, s->force_x8) != XST_SUCCESS) {
        xil_printf("  -> sideband config write failed\r\n");
        Ucie_Fi_Clear(Ucie);
        return (s->check == CHK_NO_ACTIVE); // a rejected config counts as "did not train"
    }

    u32 budget = (s->check == CHK_NO_ACTIVE) ? FAIL_MS : BRINGUP_MS;
    int active = (Ucie_BringUpActive(Ucie, budget) == XST_SUCCESS);

    int pass = 0;
    switch (s->check) {
        case CHK_ACTIVE_DATA:
            if (!active) {
                u32 st = Ucie_Rdi_ReadStatus(Ucie);
                xil_printf("  -> FAIL: never reached ACTIVE (status=0x%08X)\r\n", st);
                pass = 0;
            } else {
                xil_printf("  -> ACTIVE. Negotiated link parameters:\r\n");
                (void)Ucie_Sb_DumpLinkStatus(Ucie, NULL);
                int data_ok = Run_Mb_Data_Check(Ucie);
                xil_printf("  -> data %s\r\n", data_ok ? "MATCH" : "MISMATCH");
                pass = data_ok;
            }
            break;

        case CHK_NO_ACTIVE:
            // Correct behaviour is to NOT reach ACTIVE (watchdog -> TRAINERROR).
            if (active) {
                xil_printf("  -> FAIL: link reached ACTIVE despite fault\r\n");
                pass = 0;
            } else {
                u32 st = Ucie_Rdi_ReadStatus(Ucie);
                xil_printf("  -> OK: link did not train (as expected). status=0x%08X terr=%u\r\n",
                           st, !!(st & RDI_STAT_PL_TRAINERROR_MASK));
                pass = 1;
            }
            break;

        case CHK_INFO:
        default:
            xil_printf("  -> INFO: active=%d", active);
            if (active) {
                int data_ok = Run_Mb_Data_Check(Ucie);
                xil_printf(" data=%s", data_ok ? "MATCH" : "MISMATCH");
            }
            xil_printf(" (informational, not gated)\r\n");
            pass = 1;
            break;
    }

    // Clear faults so they don't leak into the next scenario's reset/bring-up.
    Ucie_Fi_Clear(Ucie);
    return pass;
}

int main(void) {
    UcieDriver Ucie;

    xil_printf("====================================================\r\n");
    xil_printf("  UCIe 3.0 PHY - FPGA Fault-Injection Test Software  \r\n");
    xil_printf("====================================================\r\n");

    xil_printf("[init] DMA / Sideband FIFO / EMIO GPIO (RDI + fault bank)...\r\n");
    if (Ucie_Init(&Ucie, DMA_BASEADDR, FIFO_BASEADDR, GPIO_BASEADDR) != XST_SUCCESS) {
        xil_printf("  ERROR: hardware init failed\r\n");
        return XST_FAILURE;
    }
    // Quiet the per-poll debug spam; scenarios print their own summaries.
    Ucie_Dbg_Enable(&Ucie, 0);
    // Cold-reset the RTL (EMIO bit 27, active low) before running anything.
    Ucie_Fi_ResetRtl(&Ucie, 500);
    Ucie_Fi_Clear(&Ucie);
    xil_printf("  OK.\r\n");

    int passes = 0, runs = 0, first = 1;
    int results[N_SCENARIOS]; // 1=pass, 0=fail, -1=skipped
    for (int i = 0; i < N_SCENARIOS; i++) results[i] = -1;

    for (int i = 0; i < N_SCENARIOS; i++) {
        if (!(enabled & (1u << i))) {
            xil_printf("\r\n[%s]  (skipped)\r\n", kScenarios[i].name);
            continue;
        }
        int ok = Run_Scenario(&Ucie, &kScenarios[i], first);
        first = 0;
        runs++;
        passes += (ok != 0);
        results[i] = (ok != 0);
        xil_printf("  [%s] %s\r\n", kScenarios[i].name, ok ? "PASS" : "FAIL");
    }

    // Per-scenario status table
    xil_printf("\r\n----------------------------------------------------\r\n");
    xil_printf("  Scenario Results:\r\n");
    xil_printf("----------------------------------------------------\r\n");
    for (int i = 0; i < N_SCENARIOS; i++) {
        if (results[i] < 0)
            xil_printf("  SC%d: Skipped\r\n", i + 1);
        else
            xil_printf("  SC%d: %s\r\n", i + 1, results[i] ? "Pass" : "Fail");
    }
    xil_printf("----------------------------------------------------\r\n");

    xil_printf("\r\n====================================================\r\n");
    xil_printf("  FAULT-INJECTION SUMMARY: %d/%d scenarios passed\r\n", passes, runs);
    if (passes == runs) xil_printf("               RESULT: PASS\r\n");
    else                xil_printf("               RESULT: FAIL\r\n");
    xil_printf("====================================================\r\n");

    return (passes == runs) ? XST_SUCCESS : XST_FAILURE;
}
