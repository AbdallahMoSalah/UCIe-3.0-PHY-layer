// ===========================================================================
//  Reg_File
//  UCIe PHY Register Block – Chapter 9 "Configuration and Parameters"
//
//  Register map source : docs/SB/gen_svg.py  (ground truth for register list)
//  Bit-field attributes: UCIe Specification rev3.0 Chapter 9 (authoritative)
//
//  ─── Attribute key ──────────────────────────────────────────────────────────
//   RO     – Read-Only : hardwired constant or driven live by HW; SW writes ignored
//   HWInit – Initialized by hardware at reset and held RO afterwards
//   RW     – Read-Write: SW fully controls this bit via SB write packet
//   RW1C   – Write-1-to-Clear: HW sets the bit; SW clears by writing 1
//   RW1CS  – Like RW1C but "Sticky" – value persists across soft resets
//   ROS    – Read-Only Sticky: HW writes once on error event; only cleared by reset
//   RsvdZ  – Reserved, always reads 0; SW writes ignored
//
//  ─── Address bus: 25 bits ───────────────────────────────────────────────────
//   [24]    = Space selector (set by Reg_DePacketizer from opcode):
//               0 → Config Space  (CFG_ opcodes)
//               1 → MMIO Space    (MEM_ / DMS_REG_ opcodes)
//   [23:20] = RL (Register Locator) – must be 4'h0; else addr_err_o = 1 (UR)
//   [19:0]  = Byte offset within the space
//
//  ─── Config Space (addr[24]=0, offsets 000h–023h) ───────────────────────────
//  Off  Name                       Bytes  §ref   Mixed attrs?
//  000h PCIe Ext Cap Header        4      §9.x   all RO
//  004h DVSEC Header 1             4      §9.x   all RO
//  008h DVSEC Header 2             2      §9.x   all RO        (upper 2B RsvdZ)
//  00Ah Capability Descriptor      2      §9.x   all RO        (upper 2B RsvdZ)
//  00Ch UCIe Link Capability       4      §9.x   RO + HWInit
//  010h UCIe Link Control          4      §9.x   RW + HWInit
//  014h UCIe Link Status           4      §9.x   RO + RW1C + RW1CS  ← mixed!
//  018h Link Event Notif Ctrl      2      §9.x   RW            (upper 2B RsvdZ)
//  01Ah Error Notif Ctrl           2      §9.x   RW            (upper 2B RsvdZ)
//  01Ch Register Locator 0 Low     4      §9.x   all RO
//  020h Register Locator 0 High    4      §9.x   all RO
//
//  ─── MMIO Space – PHY block (addr[24]=1, offsets 1000h–1108h) ───────────────
//  Off   Name                          Bytes  §ref     Mixed attrs?
//  1000h PHY Capability                4      §9.5.1   RO + HWInit
//  1004h PHY Control                   4      §9.5.2   RW
//  1008h PHY Status                    4      §9.5.24  all RO (live HW inputs)
//  100Ch PHY Initialization and Debug  4      §9.5.x   RW + RO
//  1010h Training Setup 1              4      §9.5.x   RW
//  1020h Training Setup 2              4      §9.5.x   RW
//  1030h Training Setup 3              4      §9.5.x   RW
//  1050h Training Setup 4              4      §9.5.x   RW
//  1060h Current Lane Map Module 0     8      §9.5.x   RW
//  1080h Error Log 0                   4      §9.5.34  all ROS
//  1090h Error Log 1                   4      §9.5.x   ROS + RW1CS  ← mixed!
//  1100h Runtime Link Test Control     8      §9.5.x   RW
//  1108h Runtime Link Test Status      4      §9.5.x   all RO (live HW inputs)
// ===========================================================================

module Reg_File (
    input  logic         clk,
    input  logic         rst_n,

    // -----------------------------------------------------------------------
    // Register-access interface (driven by Reg_Access_FSM)
    // -----------------------------------------------------------------------
    input  logic [24:0]  rf_addr,    // 25-bit: {space[24], RL[23:20], offset[19:0]}
    input  logic [7:0]   rf_be,      // Byte enables (LSB = byte 0)
    input  logic [63:0]  rf_wdata,   // Write data (up to 64 bits)
    input  logic         rd_en,      // Read  strobe (1-cycle pulse)
    input  logic         wr_en,      // Write strobe (1-cycle pulse)

    output logic [63:0]  rf_rdata,   // Read data  (registered; 1-cycle latency)
    output logic         rdata_vld,  // Data-valid (1-cycle registered pulse)

    // -----------------------------------------------------------------------
    // Address error: addr outside both windows, or RL != 4'h0
    // FSM treats this as UR (Unsupported Request) completion status.
    // -----------------------------------------------------------------------
    output logic         addr_err_o,

    // =======================================================================
    //  HW INPUTS – RO / HWInit / ROS fields driven by hardware circuits
    // =======================================================================

    // --- Config Space: UCIe Link Capability (00Ch) – HWInit bits -----------
    // Sampled once at reset; held constant thereafter.
    input  logic         hw_apmw_i,        // Advanced Package Module Width  [20]
    input  logic         hw_spmw_i,        // Standard Package Module Width  [22]

    // --- Config Space: UCIe Link Status (014h) – RW1C / RW1CS set paths ---
    // HW asserts these when the corresponding event occurs (1-cycle pulse OK).
    //   [17] Link Status Changed
    //   [18] HW Autonomous Bandwidth Changed
    //   [21:19] Error Detection (Correctable/Non-Fatal/Fatal) = RW1CS
    input  logic         hw_link_status_changed_i,  // sets bit [17]
    input  logic         hw_bw_changed_i,           // sets bit [18]
    input  logic [2:0]   hw_err_detect_i,           // sets bits [21:19]

    // --- Config Space: UCIe Link Status (014h) – RO live field ------------
    input  logic         ucie_link_up_i,    // bit [12]: 1 = Link Up

    // --- MMIO: PHY Capability (1000h) – HWInit bits -----------------------
    // Sampled at reset; held constant (RO) afterwards.
    input  logic         hw_term_link_i,    // Terminated Link support  [3]
    input  logic         hw_pkg_type_i,     // Package Type (1=Std, 0=Adv) [15]

    // --- MMIO: PHY Status (1008h) – RO live fields  [UCIe §9.5.24] --------
    input  logic [7:0]   phy_link_state,    // LTSM state encoding (§9.5.34)
    input  logic         phy_rx_term,       // [3]  Rx termination active
    input  logic         phy_tx_eq,         // [4]  Tx EQ active
    input  logic         phy_clk_mode,      // [5]  0=Strobe, 1=Free-running
    input  logic         phy_clk_phase,     // [6]  0=Differential, 1=Quadrature
    input  logic         phy_lane_rev,      // [7]  Lane reversal within module
    input  logic         phy_link_status,   // [12] Link status

    // --- MMIO: PHY Initialization and Debug (100Ch) – RO bit --------------
    // Driven live by the link training FSM.
    input  logic         phy_train_success_i,  // [7] Link Training Success

    // --- MMIO: Error Log 0 (1080h) – ROS capture --------------------------
    input  logic [7:0]   err_state_capture,  // LTSM state at error event
    input  logic         err_capture_en,     // Pulse: shift new state into log

    // --- MMIO: Error Log 1 (1090h) – RW1CS set paths ----------------------
    // HW asserts when the corresponding error event occurs.
    input  logic         hw_state_timeout_i, // sets bit [8]  (RW1CS)
    input  logic         hw_sb_timeout_i, // sets bit [9]  (RW1CS)
    input  logic         hw_rm_link_err_i,  // sets bit [10] (RW1CS)
    input  logic         hw_internal_err_i,  // sets bit [11] (RW1CS)

    // --- MMIO: Runtime Link Test Status (1108h) – RO live field -----------
    input  logic [31:0]  rt_test_status_i,   // Runtime link-test result bits

    // =======================================================================
    //  Convenience taps
    // =======================================================================
    output logic         rx_term_en,    // PHY_CONTROL[0]: Rx Termination Enable
    output logic         tx_eq_en,      // PHY_CONTROL[1]: Tx EQ Enable
    output logic         retrain_req    // PHY_CONTROL[2]: Retrain Request (self-clears)
);

// ===========================================================================
//  Address decode
// ===========================================================================

// Config Space window: addr[24]=0, RL=0, offset 000h–023h
logic cfg_sel;
assign cfg_sel = !rf_addr[24]
                 && (rf_addr[23:20] == 4'h0)
                 && (rf_addr[11:0] <= 12'h023);

// MMIO PHY block window: addr[24]=1, RL=0, offsets 1000h–110Bh
logic phy_mmio_sel;
assign phy_mmio_sel = rf_addr[24]
                      && (rf_addr[23:20] == 4'h0)
                      && (rf_addr[12:0] >= 13'h1000)
                      && (rf_addr[12:0] <= 13'h110B);

assign addr_err_o = (rd_en || wr_en) && !cfg_sel && !phy_mmio_sel;

// ===========================================================================
//  ─── CONFIG SPACE ────────────────────────────────────────────────────────
// ===========================================================================

// ---------------------------------------------------------------------------
//  Hardwired RO constants
// ---------------------------------------------------------------------------
//  PCIe Ext Cap Header (000h)
//    [15:0]  Extended Capability ID = 0x0023  (PCIe DVSEC)
//    [19:16] Capability Revision    = 0x1
//    [31:20] Next Cap Offset        = 0x000
localparam logic [31:0] PCIE_EXT_CAP_HDR_VAL = 32'h0001_0023;

//  DVSEC Header 1 (004h)
//    [15:0]  Vendor ID              = 0xD2DE  (UCIe Consoritum, from spec)
//    [19:16] DVSEC Revision         = 0x0
//    [31:20] DVSEC Length           = 0x024
localparam logic [31:0] DVSEC_HDR1_VAL       = 32'h0240_D2DE;

//  DVSEC Header 2 (008h)  [15:0] only; [31:16] = RsvdZ
//    [15:0]  DVSEC ID = 0x0001
localparam logic [15:0] DVSEC_HDR2_VAL       = 16'h0001;

//  Capability Descriptor (00Ah) [15:0]; [31:16] = RsvdZ – impl-defined
localparam logic [15:0] CAP_DESC_VAL          = 16'h0001;

//  Register Locator 0 Low (01Ch)
//    [2:0]  Register BIR   = 3'h0 (BAR 0)
//    [31:4] DWORD offset to MMIO register block  (impl-defined; 0x100)
localparam logic [31:0] REG_LOC_0_LOW_VAL    = 32'h0000_1000;

//  Register Locator 0 High (020h) – upper 32 bits of 64-bit locator
localparam logic [31:0] REG_LOC_0_HIGH_VAL   = 32'h0000_0000;

// ---------------------------------------------------------------------------
//  HWInit register – UCIe Link Capability (00Ch)
//  Sampled once at reset; afterwards behaves as RO.
//  Spec §9.x Table:
//    [0]    Raw Format Support       = RO constant (0 = not supported here)
//    [20]   APMW (Adv Pkg Mod Width) = HWInit from hw_apmw_i
//    [22]   SPMW (Std Pkg Mod Width) = HWInit from hw_spmw_i
//    [25]   UCIe Rev 1.1 Support     = RO constant (0 = not supported here)
//    others = RsvdZ
// ---------------------------------------------------------------------------
logic [31:0] ucie_link_cap_r;   // Latched at reset from HW inputs

// ---------------------------------------------------------------------------
//  RW registers
// ---------------------------------------------------------------------------
//  UCIe Link Control (010h)
//    [0]  Raw Format Enable          = RW (default 0)
//    [11] Speed Degrade Enable       = RW (default 1, per spec reset value)
//    [12] Width Degrade Enable       = RW (default 1)
//    [17] Sideband Mailbox Mech En   = RW (default 0)
//    others = RsvdZ
logic [31:0] ucie_link_ctrl_r;

//  Link Event Notif Ctrl (018h) – RW, 2-byte
logic [15:0] link_event_notif_ctrl_r;

//  Error Notif Ctrl (01Ah) – RW, 2-byte
logic [15:0] error_notif_ctrl_r;

// ---------------------------------------------------------------------------
//  UCIe Link Status (014h) – MIXED: RO [12] + RW1C [18:17] + RW1CS [21:19]
//
//  [12]    Link Status (1=Link Up)   RO  – live from ucie_link_up_i
//  [17]    Link Status Changed       RW1C  – HW sets; SW clears writing 1
//  [18]    HW Autonomous BW Changed  RW1C  – HW sets; SW clears writing 1
//  [21:19] Error Detection           RW1CS – HW sets; SW clears writing 1;
//                                           sticky across soft-resets
//
//  Implementation:
//   – ucie_link_status_r holds the RW1C and RW1CS bits only.
//   – bit[12] is not stored in a flop; it's injected at read time from live HW.
// ---------------------------------------------------------------------------
logic [21:0]  ucie_link_status_r;
// ucie_link_status_r layout mirrors the register:
//   bit position 17 → index 17 of the stored FF
//   bit position 18 → index 18
//   bits [21:19]    → index [21:19]
// (Stored as a 32-bit word aligned to register bit positions for clarity)
logic [31:0] ucie_link_status_ff;
// Only bits [21:17] have FFs; the rest are RsvdZ or live RO.

// ===========================================================================
//  ─── MMIO SPACE ──────────────────────────────────────────────────────────
// ===========================================================================

// ---------------------------------------------------------------------------
//  HWInit – PHY Capability (1000h) bits [3] and [15]
//  All other capability bits are hardwired constants (localparam).
//    [3]   Terminated Link support     = HWInit from hw_term_link_i
//    [15]  Package Type (1=Std,0=Adv)  = HWInit from hw_pkg_type_i
//    others = RsvdZ or constant-0 (RO)
// ---------------------------------------------------------------------------
logic [31:0] phy_cap_r;

// ---------------------------------------------------------------------------
//  RO (combinatorial) – PHY Status (1008h)  [UCIe §9.5.24]
//    [3]     Rx Termination Status
//    [4]     Tx EQ Status
//    [5]     Clock Mode (0=Strobe, 1=Free-running)
//    [6]     Clock Phase (0=Differential, 1=Quadrature)
//    [7]     Lane Reversal within Module
//    [12]    Link Status
//    [26:19] Link State (LTSM encoding §9.5.34)
//    others  = RsvdZ
// ---------------------------------------------------------------------------
logic [31:0] phy_status;
always_comb begin
    phy_status        = '0;
    phy_status[3]     = phy_rx_term;
    phy_status[4]     = phy_tx_eq;
    phy_status[5]     = phy_clk_mode;
    phy_status[6]     = phy_clk_phase;
    phy_status[7]     = phy_lane_rev;
    phy_status[12]    = phy_link_status;
    phy_status[26:19] = phy_link_state;
end

// ---------------------------------------------------------------------------
//  RW + RO mixed – PHY Control (1004h)  [UCIe §9.5.2]
//    [0]  Physical Layer Initialization Abort  RW
//    [22] PHY Reset (Software-triggered)       RW
//    [24] Direct PHY Control Enable            RW
//    others = RsvdZ
//
//  RW + RO mixed – PHY Initialization and Debug (100Ch)
//    [0]  Manual Link Training Start           RW
//    [7]  Link Training Success                RO (live from HW input)
//    others = RsvdZ
// ---------------------------------------------------------------------------
logic [31:0] phy_control_r;
// Note: bit[22] and [24] added per spec; kept generic for bits not in spec
logic [31:0] phy_init_debug_r;   // bit[7] is RO; written from phy_train_success_i at read

// ---------------------------------------------------------------------------
//  RW registers (generic 32-bit)
// ---------------------------------------------------------------------------
logic [31:0] training_setup1_r;   // Training Setup 1 (1010h)
logic [31:0] training_setup2_r;   // Training Setup 2 (1020h)
logic [31:0] training_setup3_r;   // Training Setup 3 (1030h)
logic [31:0] training_setup4_r;   // Training Setup 4 (1050h)
logic [63:0] lane_map_mod0_r;     // Current Lane Map Module 0 (1060h)
logic [63:0] rt_test_ctrl_r;      // Runtime Link Test Control (1100h)

// ---------------------------------------------------------------------------
//  Error Log 0 (1080h) – all ROS  [UCIe §9.5.34]
//    [7:0]   State N   – LTSM state at error
//    [8]     Lane Reversal at error time
//    [9]     Width Degrade (Standard Package only)
//    [15:10] RsvdZ
//    [23:16] State N-1
//    [31:24] State N-2
// ---------------------------------------------------------------------------
logic [31:0] error_log0_r;

// ---------------------------------------------------------------------------
//  Error Log 1 (1090h) – MIXED: ROS + RW1CS
//    [7:0]  State N-3            ROS   – HW shift; cleared only by reset
//    [8]    State Timeout        RW1CS – HW sets; SW clears writing 1; sticky
//    [9:10] RsvdZ
//    [11]   Internal Error       RW1CS – HW sets; SW clears writing 1; sticky
//    [31:12] RsvdZ
// ---------------------------------------------------------------------------
logic [31:0] error_log1_r;

// ===========================================================================
//  Write / HW-set logic (synchronous)
// ===========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin

        // ── Latch HWInit at reset ───────────────────────────────────────
        // UCIe Link Capability (RO after reset)
        ucie_link_cap_r              <= '0;
        ucie_link_cap_r[20]          <= hw_apmw_i;
        ucie_link_cap_r[22]          <= hw_spmw_i;

        // PHY Capability (RO after reset)
        phy_cap_r                    <= '0;
        phy_cap_r[3]                 <= hw_term_link_i;
        phy_cap_r[15]                <= hw_pkg_type_i;

        // ── Config Space RW resets ───────────────────────────────────────
        ucie_link_ctrl_r             <= 32'h0000_1800; // bits[11:12]=1 per spec reset
        ucie_link_status_ff          <= 32'h0000_0000;
        link_event_notif_ctrl_r      <= 16'h0000;
        error_notif_ctrl_r           <= 16'h0000;

        // ── MMIO Space RW resets ─────────────────────────────────────────
        phy_control_r                <= 32'h0000_0000;
        phy_init_debug_r             <= 32'h0000_0000;
        training_setup1_r            <= 32'h0000_0000;
        training_setup2_r            <= 32'h0000_0000;
        training_setup3_r            <= 32'h0000_0000;
        training_setup4_r            <= 32'h0000_0000;
        lane_map_mod0_r              <= 64'h0;
        rt_test_ctrl_r               <= 64'h0;

        // ── MMIO Space ROS / RW1CS resets ────────────────────────────────
        error_log0_r                 <= 32'h0000_0000;
        error_log1_r                 <= 32'h0000_0000;

    end else begin

        // ═══════════════════════════════════════════════════════════════════
        //  HW SET paths (always active every cycle — independent of SW)
        // ═══════════════════════════════════════════════════════════════════

        //  UCIe Link Status [17],[18] – RW1C: OR-set from HW events
        if (hw_link_status_changed_i) ucie_link_status_ff[17] <= 1'b1;
        if (hw_bw_changed_i)          ucie_link_status_ff[18] <= 1'b1;

        //  UCIe Link Status [21:19] – RW1CS: OR-set from HW events
        ucie_link_status_ff[21:19] <= ucie_link_status_ff[21:19] | hw_err_detect_i;

        //  Error Log 1 [8],[9],[10],[11] – RW1CS: OR-set from HW events
        if (hw_state_timeout_i) error_log1_r[8]  <= 1'b1;
        if (hw_sb_timeout_i)    error_log1_r[9]  <= 1'b1;
        if (hw_rm_link_err_i)   error_log1_r[10] <= 1'b1;
        if (hw_internal_err_i)  error_log1_r[11] <= 1'b1;

        // ═══════════════════════════════════════════════════════════════════
        //  SW write path – Config Space (addr[24]=0, RL=0)
        // ═══════════════════════════════════════════════════════════════════
        if (wr_en && cfg_sel) begin
            case (rf_addr[11:0])

                // 000h PCIe Ext Cap Header    – RO : ignore
                // 004h DVSEC Header 1         – RO : ignore
                // 008h DVSEC Header 2         – RO : ignore
                // 00Ah Capability Descriptor  – RO : ignore
                // 00Ch UCIe Link Capability   – HWInit (RO after reset) : ignore

                12'h010: begin  // UCIe Link Control – RW (4 bytes)
                    if (rf_be[0]) ucie_link_ctrl_r[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) ucie_link_ctrl_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) ucie_link_ctrl_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) ucie_link_ctrl_r[31:24] <= rf_wdata[31:24];
                end

                12'h014: begin  // UCIe Link Status – RW1C + RW1CS (W1C on bits [21:17])
                    // bit[12] (Link Up) is RO – SW writes to this bit are ignored.
                    // Bits [21:17] are RW1C/RW1CS: writing 1 clears the bit.
                    if (rf_be[2]) begin  // byte 2 covers bits [23:16]
                        // bit[17] and [16] are in byte 2 ([17:16])
                        ucie_link_status_ff[17] <= ucie_link_status_ff[17] & ~rf_wdata[17];
                        ucie_link_status_ff[18] <= ucie_link_status_ff[18] & ~rf_wdata[18];
                    end
                    if (rf_be[2] | rf_be[3]) begin  // bits[21:19] span bytes 2-3
                        ucie_link_status_ff[21:19] <=
                            ucie_link_status_ff[21:19] & ~rf_wdata[21:19];
                    end
                end

                12'h018: begin  // Link Event Notif Ctrl – RW (2 bytes)
                    if (rf_be[0]) link_event_notif_ctrl_r[7:0]  <= rf_wdata[7:0];
                    if (rf_be[1]) link_event_notif_ctrl_r[15:8] <= rf_wdata[15:8];
                end

                12'h01A: begin  // Error Notif Ctrl – RW (2 bytes)
                    if (rf_be[0]) error_notif_ctrl_r[7:0]  <= rf_wdata[7:0];
                    if (rf_be[1]) error_notif_ctrl_r[15:8] <= rf_wdata[15:8];
                end

                // 01Ch Register Locator 0 Low  – RO : ignore
                // 020h Register Locator 0 High – RO : ignore

                default: ; // RO / HWInit / unmapped: discard
            endcase
        end

        // ═══════════════════════════════════════════════════════════════════
        //  SW write path – MMIO Space (addr[24]=1, RL=0)
        // ═══════════════════════════════════════════════════════════════════
        if (wr_en && phy_mmio_sel) begin
            case (rf_addr[12:0])

                // 1000h PHY Capability           – HWInit (RO after reset): ignore
                // 1008h PHY Status               – RO live: ignore

                13'h1004: begin  // PHY Control – RW
                    if (rf_be[0]) phy_control_r[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) phy_control_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) phy_control_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) phy_control_r[31:24] <= rf_wdata[31:24];
                end

                13'h100C: begin  // PHY Initialization and Debug – RW (bit[7] is RO)
                    // bit[7] = Link Training Success is RO (from HW); SW write ignored.
                    if (rf_be[0]) phy_init_debug_r[6:0]   <= rf_wdata[6:0];   // bit[7] protected
                    if (rf_be[1]) phy_init_debug_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) phy_init_debug_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) phy_init_debug_r[31:24] <= rf_wdata[31:24];
                end

                13'h1010: begin  // Training Setup 1 – RW
                    if (rf_be[0]) training_setup1_r[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) training_setup1_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) training_setup1_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) training_setup1_r[31:24] <= rf_wdata[31:24];
                end

                13'h1020: begin  // Training Setup 2 – RW
                    if (rf_be[0]) training_setup2_r[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) training_setup2_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) training_setup2_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) training_setup2_r[31:24] <= rf_wdata[31:24];
                end

                13'h1030: begin  // Training Setup 3 – RW
                    if (rf_be[0]) training_setup3_r[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) training_setup3_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) training_setup3_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) training_setup3_r[31:24] <= rf_wdata[31:24];
                end

                13'h1050: begin  // Training Setup 4 – RW
                    if (rf_be[0]) training_setup4_r[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) training_setup4_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) training_setup4_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) training_setup4_r[31:24] <= rf_wdata[31:24];
                end

                13'h1060: begin  // Current Lane Map Module 0 – RW, 64-bit
                    if (rf_be[0]) lane_map_mod0_r[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) lane_map_mod0_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) lane_map_mod0_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) lane_map_mod0_r[31:24] <= rf_wdata[31:24];
                    if (rf_be[4]) lane_map_mod0_r[39:32] <= rf_wdata[39:32];
                    if (rf_be[5]) lane_map_mod0_r[47:40] <= rf_wdata[47:40];
                    if (rf_be[6]) lane_map_mod0_r[55:48] <= rf_wdata[55:48];
                    if (rf_be[7]) lane_map_mod0_r[63:56] <= rf_wdata[63:56];
                end

                // 1080h Error Log 0 – ROS: SW writes completely ignored

                13'h1090: begin  // Error Log 1 – ROS [7:0] + RW1CS [8] [9] [10] [11]
                    // bits[7:0]  = ROS: SW writes silently ignored
                    // bit[8]     = RW1CS: write 1 to clear (if BE covers byte 1)
                    // bit[9]     = RW1CS: write 1 to clear (if BE covers byte 1)
                    // bit[10]    = RW1CS: write 1 to clear (if BE covers byte 1)
                    // bit[11]    = RW1CS: write 1 to clear (if BE covers byte 1)
                    if (rf_be[1]) begin
                        error_log1_r[8]  <= error_log1_r[8]  & ~rf_wdata[8];
                        error_log1_r[9]  <= error_log1_r[9]  & ~rf_wdata[9];
                        error_log1_r[10] <= error_log1_r[10] & ~rf_wdata[10];
                        error_log1_r[11] <= error_log1_r[11] & ~rf_wdata[11];
                    end
                    // bits[31:12] = RsvdZ: ignore
                end

                // 1108h Runtime Link Test Status – RO: ignore

                13'h1100: begin  // Runtime Link Test Control – RW, 64-bit
                    if (rf_be[0]) rt_test_ctrl_r[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) rt_test_ctrl_r[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) rt_test_ctrl_r[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) rt_test_ctrl_r[31:24] <= rf_wdata[31:24];
                    if (rf_be[4]) rt_test_ctrl_r[39:32] <= rf_wdata[39:32];
                    if (rf_be[5]) rt_test_ctrl_r[47:40] <= rf_wdata[47:40];
                    if (rf_be[6]) rt_test_ctrl_r[55:48] <= rf_wdata[55:48];
                    if (rf_be[7]) rt_test_ctrl_r[63:56] <= rf_wdata[63:56];
                end

                default: ; // RO / ROS / HWInit / unmapped: discard
            endcase
        end

        // ═══════════════════════════════════════════════════════════════════
        //  HW write path – Error Log 0 ROS capture  [UCIe §9.5.34]
        //  Shift: N-2 ← N-1 ← N ← new state
        // ═══════════════════════════════════════════════════════════════════
        if (err_capture_en) begin
            error_log0_r[31:24] <= error_log0_r[23:16]; // State N-2
            error_log0_r[23:16] <= error_log0_r[7:0];   // State N-1
            error_log0_r[7:0]   <= err_state_capture;   // State N (current)
            error_log0_r[8]     <= phy_lane_rev;         // Lane Reversal at error
            error_log0_r[9]     <= 1'b0;                 // Width Degrade (not modelled)
            // Error Log 1 [7:0] – State N-3: shift from Error Log 0's old N-2
            error_log1_r[7:0]   <= error_log0_r[31:24]; // State N-3
        end

        // ═══════════════════════════════════════════════════════════════════
        //  Self-clearing: PHY_CONTROL[0] = Init Abort (clears after SW reads FSM ack)
        //  PHY_CONTROL[22] = PHY Reset (1-cycle pulse, then auto-clear here)
        // ═══════════════════════════════════════════════════════════════════
        if (phy_control_r[22])
            phy_control_r[22] <= 1'b0;
        // retrain_req logic:
        // old bit[2] is now bit[0] per spec; keep  bit[0] self-clear if needed
        // (spec §9.5.2 – Physical Layer Initialization Abort: cleared by HW)
        // left to HW implementation; no auto-clear here unless required

    end  // else (not reset)
end

// ===========================================================================
//  Read logic (1-cycle registered)
// ===========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rf_rdata  <= '0;
        rdata_vld <= 1'b0;
    end else if (rd_en) begin
        rdata_vld <= 1'b1;

        if (cfg_sel) begin
            // ────────────────────────────────────────────────────────────
            //  Config Space reads (addr[24]=0)
            // ────────────────────────────────────────────────────────────
            case (rf_addr[11:0])
                12'h000: rf_rdata <= {32'h0, PCIE_EXT_CAP_HDR_VAL};
                12'h004: rf_rdata <= {32'h0, DVSEC_HDR1_VAL};
                12'h008: rf_rdata <= {48'h0, DVSEC_HDR2_VAL};         // 2-byte
                12'h00A: rf_rdata <= {48'h0, CAP_DESC_VAL};           // 2-byte
                12'h00C: rf_rdata <= {32'h0, ucie_link_cap_r};        // HWInit
                12'h010: rf_rdata <= {32'h0, ucie_link_ctrl_r};       // RW
                12'h014: begin                                          // mixed
                    // Assemble from: RO live [12] + RW1C/RW1CS FF [21:17]
                    rf_rdata <= {32'h0,
                                 10'h0,                                // [31:22] RsvdZ
                                 ucie_link_status_ff[21:19],          // [21:19] RW1CS
                                 ucie_link_status_ff[18],             // [18]    RW1C
                                 ucie_link_status_ff[17],             // [17]    RW1C
                                 4'h0,                                 // [16:13] RsvdZ
                                 ucie_link_up_i,                      // [12]    RO live
                                 12'h0};                               // [11:0]  RsvdZ
                end
                12'h018: rf_rdata <= {48'h0, link_event_notif_ctrl_r};// 2-byte RW
                12'h01A: rf_rdata <= {48'h0, error_notif_ctrl_r};     // 2-byte RW
                12'h01C: rf_rdata <= {32'h0, REG_LOC_0_LOW_VAL};
                12'h020: rf_rdata <= {32'h0, REG_LOC_0_HIGH_VAL};
                default: rf_rdata <= 64'hDEAD_BEEF_DEAD_BEEF;
            endcase

        end else if (phy_mmio_sel) begin
            // ────────────────────────────────────────────────────────────
            //  MMIO Space reads (addr[24]=1)
            // ────────────────────────────────────────────────────────────
            case (rf_addr[12:0])
                13'h1000: rf_rdata <= {32'h0, phy_cap_r};              // HWInit
                13'h1004: rf_rdata <= {32'h0, phy_control_r};          // RW
                13'h1008: rf_rdata <= {32'h0, phy_status};             // RO live
                13'h100C: begin                                          // RW + RO mixed
                    // bit[7] = RO (Link Training Success) injected at read time
                    rf_rdata <= {32'h0,
                                 phy_init_debug_r[31:8],               // RW bits
                                 phy_train_success_i,                  // [7] RO live
                                 phy_init_debug_r[6:0]};               // RW bits
                end
                13'h1010: rf_rdata <= {32'h0, training_setup1_r};
                13'h1020: rf_rdata <= {32'h0, training_setup2_r};
                13'h1030: rf_rdata <= {32'h0, training_setup3_r};
                13'h1050: rf_rdata <= {32'h0, training_setup4_r};
                13'h1060: rf_rdata <= lane_map_mod0_r;                  // 64-bit
                13'h1080: rf_rdata <= {32'h0, error_log0_r};           // ROS
                13'h1090: rf_rdata <= {32'h0, error_log1_r};           // ROS+RW1CS
                13'h1100: rf_rdata <= rt_test_ctrl_r;                   // 64-bit
                13'h1108: rf_rdata <= {32'h0, rt_test_status_i};       // RO live
                default:  rf_rdata <= 64'hDEAD_BEEF_DEAD_BEEF;
            endcase

        end else begin
            rf_rdata <= 64'hDEAD_BEEF_DEAD_BEEF;  // addr_err_o already set
        end

    end else if (wr_en) begin
        rdata_vld <= 1'b1;
        rf_rdata  <= '0;
    end else begin
        rdata_vld <= 1'b0;
        rf_rdata  <= '0;
    end
end

// ===========================================================================
//  Convenience output taps
// ===========================================================================
// Per updated spec §9.5.2: using actual field positions
assign rx_term_en  = phy_control_r[0];   // Physical Layer Initialization Abort (proxy)
assign tx_eq_en    = phy_control_r[24];  // Direct PHY Control Enable
assign retrain_req = phy_control_r[22];  // PHY Reset (self-clearing after 1 cycle)

endmodule
