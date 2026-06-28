#include "ucie_driver.h"
#include "ucie_config.h"
#include "xparameters.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "sleep.h"

// =============================================================================
// Sideband header parity.
//   The reg-access depacketizer rejects any packet whose control-parity bit is
//   wrong: parity_err = (hdr.cp != ^hdr[61:0])  (Reg_DePacketizer.sv). So every
//   sideband header MUST carry:
//     cp = bit 62 (= word1[30]) = XOR of header bits [61:0]
//     dp = bit 63 (= word1[31]) = XOR of the 64-bit payload (data) bits
//   Omitting cp made writes with odd-parity headers come back as UR (status=1).
// =============================================================================
static inline u32 Ucie_Parity32(u32 x) {
    x ^= x >> 16; x ^= x >> 8; x ^= x >> 4; x ^= x >> 2; x ^= x >> 1;
    return x & 1u;
}

// Stamp cp (and dp) into word1 given the two header words + the 64-bit payload.
// Pass payload_lo/hi = 0 for header-only (read / no-data) messages.
static inline u32 Ucie_Sb_AddParity(u32 word0, u32 word1, u32 payload_lo, u32 payload_hi) {
    u32 cp = Ucie_Parity32(word0) ^ Ucie_Parity32(word1 & 0x3FFFFFFFu); // hdr[61:0]
    u32 dp = Ucie_Parity32(payload_lo) ^ Ucie_Parity32(payload_hi);     // data[63:0]
    return (word1 & 0x3FFFFFFFu) | (cp << 30) | (dp << 31);
}

// =============================================================================
// Event monitor (debug). Decodes the RDI status word + the lp_* control word +
// FIFO levels; Ucie_Dbg_Poll() prints ONLY on change so it can sit inside any
// polling loop without flooding the UART. See the header for the contract.
// =============================================================================
static const char *Ucie_Dbg_StateName(u32 s) {
    switch (s) {
        case RDI_STATE_RESET:        return "RESET";
        case RDI_STATE_ACTIVE:       return "ACTIVE";
        case RDI_STATE_ACTIVE_PMNAK: return "ACTpmnak";
        case RDI_STATE_L1:           return "L1";
        case RDI_STATE_L2:           return "L2";
        case RDI_STATE_LINK_RESET:   return "LNKRST";
        case RDI_STATE_LINK_ERROR:   return "LNKERR";
        case RDI_STATE_RETRAIN:      return "RETRAIN";
        case RDI_STATE_DISABLED:     return "DISABLED";
        case RDI_STATE_NOP:          return "NOP";
        default:                     return "?";
    }
}

static void Ucie_Dbg_Print(UcieDriver *Dev, const char *where, u32 stat, u32 rxocc) {
    u32 state = (stat & RDI_STAT_PL_STATE_STS_MASK) >> RDI_STAT_PL_STATE_STS_SHIFT;
    xil_printf("[DBG %8u %-9s] stat=0x%08X | clkreq=%u stall=%u wake=%u TERR=%u "
               "inband=%u recntr=%u state=%u(%s) sbov=%u mbov=%u || "
               "lp_state=%u clk_ack=%u stallack=%u | rxocc=%u txvac=%u\r\n",
        (unsigned)Dev->DbgTick, where, (unsigned)stat,
        !!(stat & RDI_STAT_PL_CLK_REQ_MASK),
        !!(stat & RDI_STAT_PL_STALLREQ_MASK),
        !!(stat & RDI_STAT_PL_WAKE_ACK_MASK),
        !!(stat & RDI_STAT_PL_TRAINERROR_MASK),
        !!(stat & RDI_STAT_PL_INBAND_PRES_MASK),
        !!(stat & RDI_STAT_PL_PHYINRECENTER_MASK),
        (unsigned)state, Ucie_Dbg_StateName(state),
        !!(stat & RDI_STAT_SB_RX_OVERFLOW_MASK),
        !!(stat & RDI_STAT_MB_RX_OVERFLOW_MASK),
        (unsigned)((Dev->CtrlShadow & RDI_CTRL_LP_STATE_REQ_MASK) >> RDI_CTRL_LP_STATE_REQ_SHIFT),
        !!(Dev->CtrlShadow & RDI_CTRL_LP_CLK_ACK_MASK),
        !!(Dev->CtrlShadow & RDI_CTRL_LP_STALLACK_MASK),
        (unsigned)rxocc, (unsigned)XLlFifo_TxVacancy(&Dev->AxiFifo));
}

void Ucie_Dbg_Enable(UcieDriver *Dev, int on) {
    Dev->DbgEnable = on ? 1 : 0;
    Dev->DbgPrimed = 0;   // re-arm: next poll prints a fresh baseline
}

void Ucie_Dbg_Mark(UcieDriver *Dev, const char *where) {
    if (!Dev->DbgEnable) return;
    u32 stat  = Ucie_Rdi_ReadStatus(Dev);
    u32 rxocc = XLlFifo_RxOccupancy(&Dev->AxiFifo);
    Ucie_Dbg_Print(Dev, where, stat, rxocc);
    Dev->DbgPrevStat  = stat;
    Dev->DbgPrevRxOcc = rxocc;
    Dev->DbgPrevCtrl  = Dev->CtrlShadow;
    Dev->DbgPrimed    = 1;
}

void Ucie_Dbg_Poll(UcieDriver *Dev, const char *where) {
    Dev->DbgTick++;
    if (!Dev->DbgEnable) return;
    u32 stat  = Ucie_Rdi_ReadStatus(Dev);
    u32 rxocc = XLlFifo_RxOccupancy(&Dev->AxiFifo);
    // Any change in the PHY status, the RX FIFO level, or our own lp_* outputs
    // counts as an "event" worth logging.
    if (!Dev->DbgPrimed ||
        stat != Dev->DbgPrevStat ||
        rxocc != Dev->DbgPrevRxOcc ||
        Dev->CtrlShadow != Dev->DbgPrevCtrl) {
        Ucie_Dbg_Print(Dev, where, stat, rxocc);
        Dev->DbgPrevStat  = stat;
        Dev->DbgPrevRxOcc = rxocc;
        Dev->DbgPrevCtrl  = Dev->CtrlShadow;
        Dev->DbgPrimed    = 1;
    }
}

// =============================================================================
// Internal: wait until the RX FIFO holds at least ExpectedBytes
// =============================================================================
static int Ucie_Wait_Rx_Fifo(UcieDriver *Dev, u32 ExpectedBytes, u32 TimeoutUs) {
    u32 elapsed = 0;
    while (XLlFifo_RxOccupancy(&Dev->AxiFifo) < (ExpectedBytes / 4)) {
        Ucie_Dbg_Poll(Dev, "rxwait");
        usleep(1);
        if (++elapsed >= TimeoutUs) {
            Ucie_Dbg_Mark(Dev, "rx-TMO");
            return XST_TIMEOUT;
        }
    }
    return XST_SUCCESS;
}

// =============================================================================
// Internal: run ONE full RDI clk handshake so a pending sideband completion can
// be released onto the RX path. Call once after sending each sideband request,
// BEFORE waiting on the RX FIFO.
//
//   The PHY will NOT push a reg-access completion upstream until the RDI clk
//   handshake completes: rdi_de_aggregator raises traffic_req -> RDI_SM asserts
//   pl_clk_req and BLOCKS in REQ until it sees lp_clk_ack; granting the ack moves
//   it to DONE (traffic_rdy=1) which streams the completion, and pl_clk_req then
//   drops. This is a proper 4-phase req/ack, so we run the whole cycle:
//
//       req=0 ack=0   (idle)
//       req=1 ack=0   (PHY requests)      <- phase 1: wait for req=1
//       req=1 ack=1   (we grant)          <- phase 2: raise ack
//       req=0 ack=1   (PHY drops req)     <- phase 3: wait for req=0
//       req=0 ack=0   (we drop ack)       <- phase 4: lower ack -> handshake done
//
//   Each phase the watched signal is HELD until the other side moves (req stays
//   1 until we ack, stays 0 after), so there is no edge to miss and no need for a
//   clean-slate hack -- we always leave ack=0 ready for the next access.
// =============================================================================
static int Ucie_Sb_ClkHandshake(UcieDriver *Dev, u32 TimeoutUs) {
    u32 elapsed;

    // Phase 1: wait for pl_clk_req == 1 (completion queued upstream).
    elapsed = 0;
    while (!(Ucie_Rdi_ReadStatus(Dev) & RDI_STAT_PL_CLK_REQ_MASK)) {
        Ucie_Dbg_Poll(Dev, "req^wait");
        usleep(1);
        if (++elapsed >= TimeoutUs) {
            Ucie_Dbg_Mark(Dev, "req^TMO");
            return XST_TIMEOUT;
        }
    }

    // Phase 2: raise lp_clk_ack = 1.
    Ucie_Rdi_WriteCtrl(Dev, Dev->CtrlShadow | RDI_CTRL_LP_CLK_ACK_MASK);
    Ucie_Dbg_Poll(Dev, "ack-hi");

    // Phase 3: wait for pl_clk_req == 0 (PHY drops req once granted).
    elapsed = 0;
    while (Ucie_Rdi_ReadStatus(Dev) & RDI_STAT_PL_CLK_REQ_MASK) {
        Ucie_Dbg_Poll(Dev, "reqVwait");
        usleep(1);
        if (++elapsed >= TimeoutUs) {
            Ucie_Dbg_Mark(Dev, "reqVTMO");
            return XST_TIMEOUT;
        }
    }

    // Phase 4: lower lp_clk_ack = 0 -> handshake complete.
    Ucie_Rdi_WriteCtrl(Dev, Dev->CtrlShadow & ~RDI_CTRL_LP_CLK_ACK_MASK);
    Ucie_Dbg_Poll(Dev, "ack-lo");
    return XST_SUCCESS;
}

// Clean-slate the clk handshake BEFORE sending a sideband request. The bring-up
// phase (Ucie_BringUpActive) leaves lp_clk_ack asserted; if it is still high when
// the next request goes out, the PHY auto-completes the handshake (REQ->DONE in
// one cycle) and streams the completion before our us-scale poll can ever sample
// pl_clk_req=1 -> Ucie_Sb_ClkHandshake then waits forever for an edge it missed.
// Forcing ack low first makes the PHY HOLD pl_clk_req until we grant it.
static inline void Ucie_Sb_ClkAckClear(UcieDriver *Dev) {
    Ucie_Rdi_WriteCtrl(Dev, Dev->CtrlShadow & ~RDI_CTRL_LP_CLK_ACK_MASK);
}

// =============================================================================
// Initialize AXI DMA, AXI-Stream FIFO, and the PS EMIO GPIO
// =============================================================================
int Ucie_Init(UcieDriver *Dev, UINTPTR DmaBaseAddr, UINTPTR FifoBaseAddr, UINTPTR GpioBaseAddr) {
    int Status;

    // ---- 1. AXI DMA ----
    XAxiDma_Config *DmaCfg = XAxiDma_LookupConfig(DmaBaseAddr);
    if (DmaCfg == NULL) {
        return XST_FAILURE;
    }
    Status = XAxiDma_CfgInitialize(&Dev->AxiDma, DmaCfg);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }
    // Simple polling mode -> no interrupts
    XAxiDma_IntrDisable(&Dev->AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&Dev->AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    // ---- 2. AXI-Stream FIFO (sideband path) ----
    // SDT-flow xllfifo: initialize directly from the base address (there is no
    // XLlFifo_LookupConfig in this driver version).
    XLlFifo_Initialize(&Dev->AxiFifo, FifoBaseAddr);
    XLlFifo_Reset(&Dev->AxiFifo);

    // ---- 3. PS EMIO GPIO (single instance, bank 3) ----
    XGpioPs_Config *GpioCfg = XGpioPs_LookupConfig(GpioBaseAddr);
    if (GpioCfg == NULL) {
        return XST_FAILURE;
    }
    Status = XGpioPs_CfgInitialize(&Dev->Gpio, GpioCfg, GpioCfg->BaseAddr);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }
    // bits [7:0] = outputs (control / lp_*), all others stay inputs (status / pl_*).
    XGpioPs_SetDirection(&Dev->Gpio, UCIE_EMIO_BANK, UCIE_EMIO_CTRL_MASK);
    XGpioPs_SetOutputEnable(&Dev->Gpio, UCIE_EMIO_BANK, UCIE_EMIO_CTRL_MASK);

    // Initial control state: lp_state_req = NOP, everything else deasserted.
    Dev->CtrlShadow = ((u32)RDI_STATE_NOP & RDI_CTRL_LP_STATE_REQ_MASK);
    XGpioPs_Write(&Dev->Gpio, UCIE_EMIO_BANK, Dev->CtrlShadow);

    // Event monitor: on by default for bring-up (call Ucie_Dbg_Enable(Dev,0) to
    // silence). Zero the change-detector shadows so the first poll prints a base.
    Dev->DbgEnable    = 1;
    Dev->DbgPrimed    = 0;
    Dev->DbgTick      = 0;
    Dev->DbgPrevStat  = 0;
    Dev->DbgPrevRxOcc = 0;
    Dev->DbgPrevCtrl  = 0;

    return XST_SUCCESS;
}

// =============================================================================
// Raw RDI GPIO helpers
// =============================================================================
void Ucie_Rdi_WriteCtrl(UcieDriver *Dev, u32 CtrlBits) {
    Dev->CtrlShadow = CtrlBits & UCIE_EMIO_CTRL_MASK;
    XGpioPs_Write(&Dev->Gpio, UCIE_EMIO_BANK, Dev->CtrlShadow);
}

u32 Ucie_Rdi_ReadStatus(UcieDriver *Dev) {
    // EMIO DATA_RO reflects the GPIO_I input wires (= emio_gpio_i = pl_*),
    // independent of pin direction, so this returns the real status bits.
    return XGpioPs_Read(&Dev->Gpio, UCIE_EMIO_BANK);
}

void Ucie_Rdi_SetStateReq(UcieDriver *Dev, UcieRdiState State) {
    u32 c = Dev->CtrlShadow & ~RDI_CTRL_LP_STATE_REQ_MASK;
    c |= ((u32)State << RDI_CTRL_LP_STATE_REQ_SHIFT) & RDI_CTRL_LP_STATE_REQ_MASK;
    Ucie_Rdi_WriteCtrl(Dev, c);
}

// =============================================================================
// Sideband: Write Register (64-bit access)
// =============================================================================
int Ucie_Sb_WriteReg(UcieDriver *Dev, u32 RegAddr, u64 Data) {
    u32 opc   = (RegAddr >= 0x1000) ? SB_OPC_64_MEM_WRITE : SB_OPC_64_CFG_WRITE;
    u32 be    = 0xFF;
    u32 tag   = 0x0;
    u32 srcid = SB_ID_ADAPTER;
    u32 dstid = SB_ID_LOCAL_PHY;

    u32 word0 = (srcid << 29) | (tag << 20) | (be << 12) | opc;
    u32 word1 = (dstid << 24) | (RegAddr & 0x00FFFFFF);
    u32 word2 = (u32)(Data & 0xFFFFFFFF);
    u32 word3 = (u32)((Data >> 32) & 0xFFFFFFFF);
    word1 = Ucie_Sb_AddParity(word0, word1, word2, word3); // cp + dp
    Ucie_Sb_ClkAckClear(Dev); // fresh handshake state for this access

    if (Dev->DbgEnable) {
        xil_printf("[DBG ---- WR  reg=0x%06X opc=0x%02X data=0x%08X_%08X]\r\n",
                   (unsigned)RegAddr, (unsigned)opc,
                   (u32)(Data >> 32), (u32)(Data & 0xFFFFFFFF));
    }

    XLlFifo_Write(&Dev->AxiFifo, &word0, 4);
    XLlFifo_Write(&Dev->AxiFifo, &word1, 4);
    XLlFifo_Write(&Dev->AxiFifo, &word2, 4);
    XLlFifo_Write(&Dev->AxiFifo, &word3, 4);
    XLlFifo_TxSetLen(&Dev->AxiFifo, 16); // 16 bytes = 4 words

    // PHY gates the completion behind the RDI clk handshake -- grant it first.
    if (Ucie_Sb_ClkHandshake(Dev, 100000) != XST_SUCCESS) {
        return XST_TIMEOUT;
    }

    // A write completion is a header (cpl0,cpl1); this RTL may append data words
    // (we observed a 16-byte completion for a 64-bit write). Don't hard-fail on
    // the length -- read the header for the status, then DRAIN any trailing words
    // so the RX FIFO stays packet-aligned. (The loopback TB ignores write
    // completions entirely; we only keep the status check.)
    if (Ucie_Wait_Rx_Fifo(Dev, 8, 100000) != XST_SUCCESS) { // >= 2 words (header)
        return XST_TIMEOUT;
    }
    u32 rx_len = XLlFifo_RxGetLen(&Dev->AxiFifo);  // bytes in this packet
    (void)XLlFifo_RxGetWord(&Dev->AxiFifo);        // cpl0
    u32 cpl1 = XLlFifo_RxGetWord(&Dev->AxiFifo);   // cpl1
    for (u32 i = 2; i < (rx_len / 4); i++) {       // discard trailing data words
        (void)XLlFifo_RxGetWord(&Dev->AxiFifo);
    }
    if (Dev->DbgEnable) {
        xil_printf("[DBG ---- WR cpl len=%u cpl1=0x%08X st=%u]\r\n",
                   (unsigned)rx_len, cpl1, (unsigned)(cpl1 & 0x7));
    }

    if ((cpl1 & 0x7) != 0) {
        return XST_FAILURE; // non-zero completion status
    }
    return XST_SUCCESS;
}

// =============================================================================
// Sideband: Read Register (64-bit access)
// =============================================================================
int Ucie_Sb_ReadReg(UcieDriver *Dev, u32 RegAddr, u64 *DataValPtr) {
    u32 opc   = (RegAddr >= 0x1000) ? SB_OPC_64_MEM_READ : SB_OPC_64_CFG_READ;
    u32 be    = 0xFF;
    u32 tag   = 0x0;
    u32 srcid = SB_ID_ADAPTER;
    u32 dstid = SB_ID_LOCAL_PHY;

    u32 word0 = (srcid << 29) | (tag << 20) | (be << 12) | opc;
    u32 word1 = (dstid << 24) | (RegAddr & 0x00FFFFFF);
    word1 = Ucie_Sb_AddParity(word0, word1, 0, 0); // header-only: cp only, dp=0
    Ucie_Sb_ClkAckClear(Dev); // fresh handshake state for this access

    if (Dev->DbgEnable) {
        xil_printf("[DBG ---- RD  reg=0x%06X opc=0x%02X]\r\n",
                   (unsigned)RegAddr, (unsigned)opc);
    }

    XLlFifo_Write(&Dev->AxiFifo, &word0, 4);
    XLlFifo_Write(&Dev->AxiFifo, &word1, 4);
    XLlFifo_TxSetLen(&Dev->AxiFifo, 8); // 8 bytes = 2 words

    // PHY gates the completion behind the RDI clk handshake -- grant it first.
    if (Ucie_Sb_ClkHandshake(Dev, 100000) != XST_SUCCESS) {
        return XST_TIMEOUT;
    }

    // Expect completion-with-64-data (16 bytes = 4 words)
    if (Ucie_Wait_Rx_Fifo(Dev, 16, 100000) != XST_SUCCESS) {
        return XST_TIMEOUT;
    }
    u32 rx_len = XLlFifo_RxGetLen(&Dev->AxiFifo);
    if (rx_len != 16) {
        for (u32 i = 0; i < (rx_len / 4); i++) (void)XLlFifo_RxGetWord(&Dev->AxiFifo);
        return XST_FAILURE;
    }
    (void)XLlFifo_RxGetWord(&Dev->AxiFifo);            // cpl0
    u32 cpl1      = XLlFifo_RxGetWord(&Dev->AxiFifo);  // cpl1
    u32 data_low  = XLlFifo_RxGetWord(&Dev->AxiFifo);
    u32 data_high = XLlFifo_RxGetWord(&Dev->AxiFifo);

    if ((cpl1 & 0x7) != 0) {
        return XST_FAILURE;
    }
    *DataValPtr = ((u64)data_high << 32) | data_low;
    return XST_SUCCESS;
}

// =============================================================================
// Read LINK_STATUS (0x14) over sideband and print the negotiated link config.
//   Decodes the Link Width / Link Speed fields per spec Table 9-10. These are
//   only valid once Link is up (bit 15). Returns the raw value via *StatusOut.
// =============================================================================
int Ucie_Sb_DumpLinkStatus(UcieDriver *Dev, u64 *StatusOut) {
    // Link Width enabled [10:7] encoding (Table 9-10).
    static const char *const width_str[16] = {
        "x4", "x8", "x16", "x32", "x64", "x128", "x256",
        "rsvd", "rsvd", "rsvd", "rsvd", "rsvd", "rsvd", "rsvd", "rsvd", "rsvd"
    };
    // Link Speed enabled [14:11] encoding (Table 9-10), in GT/s.
    static const char *const speed_str[16] = {
        "4 GT/s", "8 GT/s", "12 GT/s", "16 GT/s", "24 GT/s", "32 GT/s",
        "48 GT/s", "64 GT/s", "rsvd", "rsvd", "rsvd", "rsvd",
        "rsvd", "rsvd", "rsvd", "rsvd"
    };

    u64 val = 0;
    int Status = Ucie_Sb_ReadReg(Dev, REG_UCIE_LINK_STATUS, &val);
    if (StatusOut) *StatusOut = val;
    if (Status != XST_SUCCESS) {
        xil_printf("    ERROR: LINK_STATUS read failed (%d)\r\n", Status);
        return Status;
    }

    u32 sts   = (u32)val;
    u32 width = (sts & LINK_STATUS_WIDTH_MASK) >> LINK_STATUS_WIDTH_SHIFT;
    u32 speed = (sts & LINK_STATUS_SPEED_MASK) >> LINK_STATUS_SPEED_SHIFT;

    xil_printf("    LINK_STATUS (0x14) = 0x%08X\r\n", sts);
    xil_printf("      Link Up        : %s\r\n",
               (sts & LINK_STATUS_LINK_UP) ? "YES" : "no");
    xil_printf("      Negotiated wid : %s (0x%X)\r\n", width_str[width & 0xF], width);
    xil_printf("      Negotiated spd : %s (0x%X)\r\n", speed_str[speed & 0xF], speed);
    xil_printf("      Retraining     : %s\r\n",
               (sts & LINK_STATUS_TRAINING) ? "YES" : "no");
    xil_printf("      Raw fmt / MP / EnhMP / x32AdvPkg : %d / %d / %d / %d\r\n",
               (sts & LINK_STATUS_RAW_FORMAT_EN)      ? 1 : 0,
               (sts & LINK_STATUS_MULTI_PROTO_EN)     ? 1 : 0,
               (sts & LINK_STATUS_ENH_MULTI_PROTO_EN) ? 1 : 0,
               (sts & LINK_STATUS_X32_ADV_PKG_EN)     ? 1 : 0);
    return XST_SUCCESS;
}

// =============================================================================
// Sideband: Send remote message (loops back to local RX in self-loopback)
// =============================================================================
int Ucie_Sb_SendRemoteMsg(UcieDriver *Dev, u8 MsgOpcode, u32 MsgInfo, u64 MsgData,
                          u32 *RxW0, u32 *RxW1, u32 *RxW2, u32 *RxW3) {
    u32 tag   = 0x0;
    u32 be    = 0xFF;
    u32 srcid = SB_ID_ADAPTER;
    u32 dstid = SB_ID_REMOTE_ADAPTER;

    u32 word0 = (srcid << 29) | (tag << 20) | (be << 12) | MsgOpcode;
    u32 word1 = (dstid << 24) | (MsgInfo & 0x00FFFFFF);
    word1 = Ucie_Sb_AddParity(word0, word1,
                              (u32)(MsgData & 0xFFFFFFFF), (u32)(MsgData >> 32)); // cp + dp
    Ucie_Sb_ClkAckClear(Dev); // fresh handshake state for this access
    u32 word2 = (u32)(MsgData & 0xFFFFFFFF);
    u32 word3 = (u32)((MsgData >> 32) & 0xFFFFFFFF);

    XLlFifo_Write(&Dev->AxiFifo, &word0, 4);
    XLlFifo_Write(&Dev->AxiFifo, &word1, 4);
    XLlFifo_Write(&Dev->AxiFifo, &word2, 4);
    XLlFifo_Write(&Dev->AxiFifo, &word3, 4);
    XLlFifo_TxSetLen(&Dev->AxiFifo, 16);

    // PHY gates the looped-back message behind the RDI clk handshake.
    if (Ucie_Sb_ClkHandshake(Dev, 100000) != XST_SUCCESS) {
        return XST_TIMEOUT;
    }

    if (Ucie_Wait_Rx_Fifo(Dev, 16, 100000) != XST_SUCCESS) {
        return XST_TIMEOUT;
    }
    u32 rx_len = XLlFifo_RxGetLen(&Dev->AxiFifo);
    if (rx_len != 16) {
        for (u32 i = 0; i < (rx_len / 4); i++) (void)XLlFifo_RxGetWord(&Dev->AxiFifo);
        return XST_FAILURE;
    }
    *RxW0 = XLlFifo_RxGetWord(&Dev->AxiFifo);
    *RxW1 = XLlFifo_RxGetWord(&Dev->AxiFifo);
    *RxW2 = XLlFifo_RxGetWord(&Dev->AxiFifo);
    *RxW3 = XLlFifo_RxGetWord(&Dev->AxiFifo);
    return XST_SUCCESS;
}

// =============================================================================
// Start link training (program caps + assert start-training bit over sideband)
// =============================================================================
int Ucie_StartTraining(UcieDriver *Dev) {
    int s3, s4, sphy, slink;

    // Compose TRAIN_SETUP4 from the two max-error thresholds in config.h.
    u64 train_setup4_val = 0ULL;
    train_setup4_val |= ((u64)CFG_MAX_ERR_THRESH_PER_LANE << TRAIN_SETUP4_PERLANE_SHIFT)
                        & TRAIN_SETUP4_PERLANE_MASK;
    train_setup4_val |= ((u64)CFG_MAX_ERR_THRESH_AGGREGATE << TRAIN_SETUP4_AGG_SHIFT)
                        & TRAIN_SETUP4_AGG_MASK;

    // Compose PHY_CONTROL: base payload + the x8-width toggle from config.h.
    u64 phy_control_val = CFG_PHY_CONTROL_BASE;
    if (CFG_PHY_FORCE_X8) phy_control_val |=  PHY_CTRL_FORCE_X8;
    else                  phy_control_val &= ~(u64)PHY_CTRL_FORCE_X8;

    // Compose LINK_CTRL from the tunable targets in config.h.
    u64 link_ctrl_val = 0ULL;
    link_ctrl_val |= ((u64)CFG_TARGET_LINK_WIDTH << LINK_CTRL_TGT_WIDTH_SHIFT)
                     & LINK_CTRL_TGT_WIDTH_MASK;
    link_ctrl_val |= ((u64)CFG_TARGET_LINK_SPEED << LINK_CTRL_TGT_SPEED_SHIFT)
                     & LINK_CTRL_TGT_SPEED_MASK;
    link_ctrl_val |= LINK_CTRL_START_TRAINING;

    // DEBUG: attempt all writes and report each, rather than bailing on the first
    // UR. The golden loopback TB programs only SETUP4/PHY_CONTROL/LINK_CTRL (NOT
    // TRAIN_SETUP3 0x1030), so we want to see exactly which register is rejected.
    s3    = Ucie_Sb_WriteReg(Dev, REG_TRAIN_SETUP3,   CFG_LANE_MASK);
    s4    = Ucie_Sb_WriteReg(Dev, REG_TRAIN_SETUP4,   train_setup4_val);
    sphy  = Ucie_Sb_WriteReg(Dev, REG_PHY_CONTROL,    phy_control_val);
    slink = Ucie_Sb_WriteReg(Dev, REG_UCIE_LINK_CTRL, link_ctrl_val);

    xil_printf("    reg-write results: SETUP3(0x1030)=%d SETUP4(0x1050)=%d "
               "PHY_CTRL(0x1004)=%d LINK_CTRL(0x10)=%d\r\n", s3, s4, sphy, slink);

    // SETUP3 is the lane mask (default 0 = no masking); the TB omits it, so a UR
    // there is non-fatal. The link cannot train if LINK_CTRL was rejected.
    if (slink != XST_SUCCESS) return slink;
    if (s4 != XST_SUCCESS)    return s4;
    if (sphy != XST_SUCCESS)  return sphy;
    return XST_SUCCESS;
}

// Service the RDI clk/stall handshake once: echo pl_clk_req -> lp_clk_ack and
// pl_stallreq -> lp_stallack based on the latest status word.
static void Ucie_Rdi_ServiceHandshake(UcieDriver *Dev, u32 st) {
    u32 c = Dev->CtrlShadow;
    if (st & RDI_STAT_PL_CLK_REQ_MASK)  c |=  RDI_CTRL_LP_CLK_ACK_MASK;
    else                                c &= ~RDI_CTRL_LP_CLK_ACK_MASK;
    if (st & RDI_STAT_PL_STALLREQ_MASK) c |=  RDI_CTRL_LP_STALLACK_MASK;
    else                                c &= ~RDI_CTRL_LP_STALLACK_MASK;

    if (c != Dev->CtrlShadow) {
        Ucie_Rdi_WriteCtrl(Dev, c);
    }
}

// =============================================================================
// Drive RDI to ACTIVE and service the clk/stall handshake until it gets there.
//
//   IMPORTANT ordering: do NOT request ACTIVE right after start-training. The
//   RDI SM only completes the NOP->ACTIVE Active-handshake once pl_inband_pres
//   is high (see unit_Active_handshake.sv: it advances only on `req_r &&
//   inband_pres`). If we assert lp_state_req=ACTIVE before inband presence is
//   detected, the SM kicks off the Active handshake early and can hit the
//   sideband message timeout -> trainerror. So we first wait for the
//   pl_inband_pres 0->1 edge, THEN request ACTIVE.
//
//   This services the RDI handshake from software (echo pl_clk_req ->
//   lp_clk_ack, pl_stallreq -> lp_stallack). It relies on the PHY *waiting* for
//   the ack (true req/ack handshake, not a hard timeout). The loop is tight (no
//   sleep) to be as fast as GPIO allows.
// =============================================================================
int Ucie_BringUpActive(UcieDriver *Dev, u32 TimeoutMs) {
    u32 deadline = TimeoutMs * 1000; // approx loop budget in us-ish ticks

    // Phase 1: wait for in-band presence (NOP -> ACTIVE precondition).
    //   Keep servicing the clk/stall handshake so training can progress and the
    //   PHY can detect the sideband presence that raises pl_inband_pres.
    int inband_seen = 0;
    while (deadline--) {
        u32 st = Ucie_Rdi_ReadStatus(Dev);

        if (st & RDI_STAT_PL_TRAINERROR_MASK) {
            Ucie_Dbg_Mark(Dev, "p1-TERR");
            return XST_FAILURE; // PHY reported a training error before ACTIVE
        }
        if (st & RDI_STAT_PL_INBAND_PRES_MASK) {
            inband_seen = 1;
            Ucie_Dbg_Mark(Dev, "inband");
            break; // presence detected -> safe to request ACTIVE
        }

        Ucie_Rdi_ServiceHandshake(Dev, st);
        Ucie_Dbg_Poll(Dev, "p1-wait");
        usleep(1);
    }
    if (!inband_seen) {
        Ucie_Dbg_Mark(Dev, "p1-TMO");
        return XST_TIMEOUT; // inband presence never asserted
    }

    // Phase 2: now request ACTIVE and service the handshake until we get there.
    Ucie_Rdi_SetStateReq(Dev, RDI_STATE_ACTIVE);
    Ucie_Dbg_Mark(Dev, "req-ACT");

    while (deadline--) {
        u32 st = Ucie_Rdi_ReadStatus(Dev);

        u32 state = (st & RDI_STAT_PL_STATE_STS_MASK) >> RDI_STAT_PL_STATE_STS_SHIFT;
        if (state == RDI_STATE_ACTIVE) {
            Ucie_Dbg_Mark(Dev, "ACTIVE");
            return XST_SUCCESS;
        }
        if (st & RDI_STAT_PL_TRAINERROR_MASK) {
            Ucie_Dbg_Mark(Dev, "p2-TERR");
            return XST_FAILURE; // PHY reported a training error
        }

        Ucie_Rdi_ServiceHandshake(Dev, st);
        Ucie_Dbg_Poll(Dev, "p2-wait");
        usleep(1);
    }
    Ucie_Dbg_Mark(Dev, "p2-TMO");
    return XST_TIMEOUT;
}

// =============================================================================
// MainBand AXI DMA transfer – FLIT-BY-FLIT (cache-safe).
//
//   The MB RX bridge (axis_master_from_mb_rx) has a small FIFO (depth 8).  If
//   the DMA S2MM channel can't drain fast enough during a burst, the FIFO
//   overflows and flits are silently dropped (flagged by o_mb_rx_overflow).
//
//   To avoid that, we send ONE FLIT at a time:
//     1. Flush the source flit from D-cache.
//     2. Invalidate the destination flit region.
//     3. Arm S2MM for one flit (64 bytes).
//     4. Fire MM2S for one flit (64 bytes).
//     5. Poll until both channels are idle (with a timeout).
//     6. Invalidate destination again so the CPU sees DMA-written data.
//     7. Check o_mb_rx_overflow via GPIO status; abort if set.
//     8. Advance pointers, repeat for the next flit.
//
//   LengthBytes must be a multiple of FLIT_SIZE (64 bytes).
// =============================================================================
#define MB_FLIT_SIZE  64   /* 512-bit flit = 64 bytes */

int Ucie_Mb_Transfer(UcieDriver *Dev, void *SrcAddr, void *DstAddr, u32 LengthBytes) {
    int Status;

    if (LengthBytes == 0 || (LengthBytes % MB_FLIT_SIZE) != 0) {
        return XST_FAILURE;  // must be a whole number of flits
    }

    u32 NumFlits = LengthBytes / MB_FLIT_SIZE;
    UINTPTR src  = (UINTPTR)SrcAddr;
    UINTPTR dst  = (UINTPTR)DstAddr;

    for (u32 f = 0; f < NumFlits; f++) {
        // ---- cache maintenance for this flit ----
        Xil_DCacheFlushRange(src, MB_FLIT_SIZE);
        Xil_DCacheInvalidateRange(dst, MB_FLIT_SIZE);

        // ---- arm RX (S2MM) first, then fire TX (MM2S) ----
        Status = XAxiDma_SimpleTransfer(&Dev->AxiDma, dst, MB_FLIT_SIZE,
                                        XAXIDMA_DEVICE_TO_DMA);
        if (Status != XST_SUCCESS) {
            xil_printf("    MB flit %u: S2MM arm failed (%d)\r\n", f, Status);
            return XST_FAILURE;
        }

        Status = XAxiDma_SimpleTransfer(&Dev->AxiDma, src, MB_FLIT_SIZE,
                                        XAXIDMA_DMA_TO_DEVICE);
        if (Status != XST_SUCCESS) {
            xil_printf("    MB flit %u: MM2S arm failed (%d)\r\n", f, Status);
            return XST_FAILURE;
        }

        // ---- wait for both channels to complete (with timeout) ----
        u32 timeout = 1000000;  // ~1 second at 1 us/tick
        while (XAxiDma_Busy(&Dev->AxiDma, XAXIDMA_DEVICE_TO_DMA) ||
               XAxiDma_Busy(&Dev->AxiDma, XAXIDMA_DMA_TO_DEVICE)) {
            if (--timeout == 0) {
                xil_printf("    MB flit %u: DMA timeout (TX busy=%d RX busy=%d)\r\n",
                           f,
                           XAxiDma_Busy(&Dev->AxiDma, XAXIDMA_DMA_TO_DEVICE),
                           XAxiDma_Busy(&Dev->AxiDma, XAXIDMA_DEVICE_TO_DMA));
                return XST_TIMEOUT;
            }
            usleep(1);
        }

        // ---- make DMA-written data visible to CPU ----
        Xil_DCacheInvalidateRange(dst, MB_FLIT_SIZE);

        // ---- check for RX FIFO overflow (sticky, fatal for data integrity) ----
        u32 st = Ucie_Rdi_ReadStatus(Dev);
        if (st & RDI_STAT_MB_RX_OVERFLOW_MASK) {
            xil_printf("    MB flit %u: RX FIFO overflow detected!\r\n", f);
            return XST_FAILURE;
        }

        src += MB_FLIT_SIZE;
        dst += MB_FLIT_SIZE;
    }

    return XST_SUCCESS;
}
