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

    // --- Config Space: UCIe Link Capability (00Ch) -----------
    // Sampled once at reset; held constant thereafter.
    input  logic         adapter_raw_format_support_cap_i,  // [0] Raw Format Support
    input  logic [2:0]   hw_max_link_width_cap_i,           // [3:1] Max Link Width
    input  logic [3:0]   hw_max_link_speed_cap_i,           // [7:4] Max Link Speed
    input  logic         adapter_multi_protocol_cap_i,  // [9] Multi-Protocol Capability
    input  logic         phy_advanced_pkg_cap_i,            // [10] Advanced Package
    input  logic         adapter_68B_flit_formate_streaming_cap_i, // [11] 68B Flit Formate Streaming
    input  logic         adapter_256B_end_header_flit_format_streaming_cap_i, // [12] 256B End Header Flit Format for Streaming
    input  logic         adapter_256B_start_header_flit_format_streaming_cap_i, // [13] 256B Start Header Flit Format for Streaming
    input  logic         adapter_256B_latency_optimized_flit_format_without_optional_bytes_streaming_cap_i, // [14] Latency-Optimized 256B Flit Format without Optional Bytes for Streaming
    input  logic         adapter_256B_latency_optimized_flit_format_with_optional_bytes_streaming_cap_i, // [15] Latency-Optimized 256B Flit Format with Optional Bytes for Streaming
    input  logic         adapter_enhanced_multi_protocol_capable_cap_i, // [16] Enhanced Multi-protocol Capable
    input  logic         adapter_standard_start_header_flit_for_pcie_protocol_cap_i, // [17] Standard Start Header Flit for PCIe Protocol
    input  logic         adapter_latency_optimized_flit_with_optional_bytes_for_pcie_protocol_cap_i, // [18] Latency-Optimized Flit with Optional Bytes for PCIe Protocol
    input  logic         adapter_runtime_link_testing_parity_feature_error_signaling_cap_i, // [19] Runtime Link Testing Parity’ Feature Error Signaling
    input  logic         hw_apmw_cap_i,                     // Advanced Package Module Width  [20]
    input  logic         hw_spmw_cap_i,                     // Standard Package Module Width  [22]
    input  logic         phy_sideband_performant_mode_operation_cap_i, // [23] Sideband Performant Mode Operation (PMO)
    input  logic         phy_priority_sideband_packet_transfer_cap_i, // [24] Priority Sideband Packet Transfer (PSPT)
    input  logic         phy_l2_sideband_power_down_cap_i, // [25] L2 Sideband Power Down (L2SPD)

    // --- Config Space: UCIe Link Status (014h) – RW1C / RW1CS set paths ---
    // HW asserts these when the corresponding event occurs (1-cycle pulse OK).
    //   [17] Link Status Changed
    //   [18] HW Autonomous Bandwidth Changed
    //   [21:19] Error Detection (Correctable/Non-Fatal/Fatal) = RW1CS
    input  logic         adapter_raw_format_enabled_status_i, // [0] Raw Format Enable
    input  logic         adapter_multi_protocol_enabled_status_i, // [1] Multi-protocol Enable
    input  logic         adapter_enhanced_multi_protocol_enabled_status_i, // [2] Enhanced Multi-protocol Enable
    input  logic         phy_x32_advanced_package_module_enabled_status_i, // [3] x32 Advanced Package Module Enable
    input  logic [3:0]   phy_link_width_enabled_status_i, // [10:7] Link Width Enable
    input  logic [3:0]   phy_link_speed_enabled_status_i, // [14:11] Link Speed Enable
    input  logic         phy_link_status_status_i, // [15] Link Status
    input  logic         phy_link_training_retraining_status_i,
    input  logic         phy_link_status_changed_status_i,  // sets bit [17]
    input  logic         phy_bw_changed_status_i,           // sets bit [18]Link Training/Retraining
    input  logic         phy_uci_e_link_correctable_error_i,    // sets bits [19]
    input  logic         phy_uci_e_link_uncorrectable_non_fatal_error_i,    // sets bits [20]
    input  logic         phy_uci_e_link_uncorrectable_fatal_error_i,    // sets bits [21]
    input  logic [3:0]   adapter_flit_format_status_i, // [25:22] Flit Format Status
    input  logic         phy_sideband_performant_mode_operation_status_i, // [26] Sideband Performant Mode Operation (PMO)
    input  logic         phy_priority_sideband_packet_transfer_status_i, // [27] Priority Sideband Packet Transfer (PSPT)
    input  logic         phy_l2_sideband_power_down_status_i, // [28] L2 Sideband Power Down (L2SPD)

    // --- Config Space: Link Event Notification Control (018h) -----------
    input logic [4:0] link_event_notification_interrupt_number_i, // [4:0] Link Event Notification Interrupt number
    
    // --- MMIO: PHY Capability (1000h) – HWInit bits -----------------------
    // Sampled at reset; held constant (RO) afterwards.
    input  logic         phy_term_link_cap_i,    // Terminated Link support  [3]
    input  logic         phy_tx_eq_status_iualization_support_cap_i, // TX Equalization support [4]
    input  logic [4:0]   phy_tx_vswing_encodings_cap_i, // Supported Tx Vswing encodings [9:5]
    input  logic [1:0]   phy_rx_clk_mode_support_cap_i, // Rx Clock Mode Support for <= 32 GT/s [12:11]
    input  logic [1:0]   phy_rx_clk_phase_support_cap_i, // Rx Clock Phase Support for <= 32 GT/s [14:13]
    input  logic         phy_package_type_cap_i, // Package Type (1=Std, 0=Adv) [15]
    input  logic         phy_tcm_support_cap_i, // Tightly coupled mode (TCM) support [16]
    input  logic         phy_tarr_support_cap_i, // Tx Adjustment for Runtime Recalibration (TARR) [17]

    // --- MMIO: PHY Status (1008h) – RO live fields  [UCIe §9.5.24] --------
    input  logic         phy_rx_term_status_i,       // [3]  Rx termination active
    input  logic         phy_tx_eq_status_i,         // [4]  Tx EQ active
    input  logic         phy_clk_mode_status_i,      // [5]  0=Strobe, 1=Free-running
    input  logic         phy_clk_phase_status_i,     // [6]  0=Differential, 1=Quadrature
    input  logic         phy_lane_rev_status_i,      // [7]  Lane reversal within module
    input  logic [5:0]   phy_iq_correction_param_status_i, // [13:8] I/Q Correction Parameter
    input  logic [3:0]   phy_eq_preset_setting_status_i, // [17:14] EQ Preset Setting
    input  logic         phy_tarr_status_i, // [18] Tx Adjustment for Runtime Recalibration (TARR)

    // --- MMIO: Error Log 0 (1080h) – ROS capture --------------------------
    input  logic [7:0]   err_state_capture,  // [7:0] LTSM state at error event
    input  logic         phy_lane_rev_err_log_i, // [8] Lane reversal at error
    input  logic         phy_width_degrade_err_log_i, // [9] Width degrade
    input  logic         err_capture_en,     // Pulse: shift new state into log

    // --- MMIO: Error Log 1 (1090h) – RW1CS set paths ----------------------
    // HW asserts when the corresponding error event occurs.
    input  logic         phy_state_timeout_i, // sets bit [8]  (RW1CS)
    input  logic         phy_sb_timeout_i, // sets bit [9]  (RW1CS)
    input  logic         phy_rm_link_err_i,  // sets bit [10] (RW1CS)
    input  logic         phy_internal_err_i,  // sets bit [11] (RW1CS)

    // --- MMIO: Runtime Link Test Status (1108h) – RO live field -----------
    input  logic         rt_link_busy_status_i,   // [0] Runtime link-test busy

    // ======================================================================
    // RDI SM iterface 
    // =======================================================================
    output logic [3:0] phy_max_link_speed_cap_out,
    output logic [3:0] phy_link_width_enabled_status_out,
    output logic [3:0] phy_link_speed_enabled_status_out,


    // ======================================================================
    // LTSM iterface 
    // =======================================================================
    output logic [3:0] phy_target_link_width_ctrl_out,
    output logic [3:0] phy_target_link_speed_ctrl_out,
    output logic       phy_start_ucie_link_training_ctrl_out,
    output logic       phy_retrain_ucie_link_ctrl_out,
    output logic       phy_pmo_ctrl_out,
    output logic       phy_pspt_ctrl_out,
    output logic       phy_l2spd_ctrl_out,

    output logic       phy_rx_term_status_i_ctrl_out,    // PHY_CONTROL[3]: Rx Termination Enable
    output logic       phy_tx_eq_status_i_en_ctrl_out,      // PHY_CONTROL[4]: Tx EQ Enable
    output logic       phy_rx_clk_mode_ctrl_out,    // PHY_CONTROL[5]: Rx Clock Mode Select
    output logic       phy_rx_clk_phase_ctrl_out,    // PHY_CONTROL[6]: Rx Clock Phase Select
    output logic       phy_x8_width_mode_ctrl_out,    // PHY_CONTROL[8]: Force x8 Width Mode in a UCIe-S x16 Module
    output logic       phy_iq_correction_en_ctrl_out,    // PHY_CONTROL[9]: Force I/Q Correction Enable
    output logic [5:0] phy_iq_correction_param_ctrl_out,    // PHY_CONTROL[15:10]: Force I/Q Correction Parameter
    output logic       phy_tx_eq_status_i_preset_ctrl_out,    // PHY_CONTROL[16]: Force Tx EQ Preset
    output logic [3:0] phy_tx_eq_status_i_preset_setting_ctrl_out,    // PHY_CONTROL[20:17]: Force Tx EQ Preset Setting
    output logic       phy_tarr_en_ctrl_out,    // PHY_CONTROL[21]: Tx Adjustment for Runtime Recalibration (TARR)
    

    output logic   [2:0]  phy_init_ctrl_out,    // PHY_INIT_DEBUG[2:0]: PHY Initialization Done
    output logic          phy_resume_training_ctrl_out,    // PHY_INIT_DEBUG[5]: Resume Training
    
    output logic [63:0] lane_mask_ctrl_out,
    output logic [11:0] max_error_threshold_in_per_lane_comparison_out,
    output logic [15:0] max_error_threshold_in_aggregate_comparison_out,

    output logic [15:0] idle_count_out,
    output logic [15:0] iterations_out,
    // =======================================================================
    //  Convenience taps
    // =======================================================================

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
//    [15:0]  DVSEC ID = 0x0000
localparam logic [15:0] DVSEC_HDR2_VAL       = 16'h0000;

//  Capability Descriptor (00Ah) [15:0]; [31:16] = RsvdZ – impl-defined
localparam logic [15:0] CAP_DESC_VAL          = 16'hFFF7;

//  Register Locator 0 Low (01Ch)
//    [2:0]  Register BIR   = 3'h0 (BAR 0)
//    [31:4] DWORD offset to MMIO register block  (impl-defined; 0x100)
localparam logic [31:0] REG_LOC_0_LOW_VAL    = 32'h0000_1F00;

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
assign phy_max_link_speed_cap_out = ucie_link_cap_r[7:4];

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

assign phy_target_link_width_ctrl_out = ucie_link_ctrl_r[5:2];
assign phy_target_link_speed_ctrl_out = ucie_link_ctrl_r[9:6];
assign phy_start_ucie_link_training_ctrl_out = ucie_link_ctrl_r[10];
assign phy_retrain_ucie_link_ctrl_out = ucie_link_ctrl_r[11];
assign phy_pmo_ctrl_out = ucie_link_ctrl_r[21];
assign phy_pspt_ctrl_out = ucie_link_ctrl_r[22];
assign phy_l2spd_ctrl_out = ucie_link_ctrl_r[23];

//  Link Event Notif Ctrl (018h) – RW, 2-byte
logic [15:0] link_event_notif_ctrl_r;
always_comb begin
    link_event_notif_ctrl_r [1:0]   = link_event_notif_ctrl_ff[1:0];
    link_event_notif_ctrl_r [10:2]  = 7'b1111111;
    link_event_notif_ctrl_r [15:11] = link_event_notification_interrupt_number_i;
end

logic [15:0] link_event_notif_ctrl_ff;

//  Error Notif Ctrl (01Ah) – RW, 2-byte
logic [15:0] error_notif_ctrl_r;
always_comb begin
    error_notif_ctrl_r = error_notif_ctrl_ff;
    error_notif_ctrl_r[10:6] = 5'b11111;
end
logic [15:0] error_notif_ctrl_ff;

// ---------------------------------------------------------------------------
//  UCIe Link Status (014h) – MIXED: RO [12] + RW1C [18:17] + RW1CS [21:19]
//
//  [17]    Link Status Changed       RW1C  – HW sets; SW clears writing 1
//  [18]    HW Autonomous BW Changed  RW1C  – HW sets; SW clears writing 1
//  [21:19] Error Detection           RW1CS – HW sets; SW clears writing 1;
//                                           sticky across soft-resets
//
//  Implementation:
//   – ucie_link_status_r holds the RW1C and RW1CS bits only.
//   – bit[12] is not stored in a flop; it's injected at read time from live HW.
// ---------------------------------------------------------------------------
logic [31:0]  ucie_link_status_r;

always_comb begin
    ucie_link_status_r        = '0;
    ucie_link_status_r[0]     = adapter_raw_format_enabled_status_i;
    ucie_link_status_r[1]     = adapter_multi_protocol_enabled_status_i;
    ucie_link_status_r[2]     = adapter_enhanced_multi_protocol_enabled_status_i;
    ucie_link_status_r[3]     = phy_x32_advanced_package_module_enabled_status_i;
    ucie_link_status_r[10:7]  = phy_link_width_enabled_status_i;
    ucie_link_status_r[14:11] = phy_link_speed_enabled_status_i;
    ucie_link_status_r[15]    = phy_link_status_status_i;
    ucie_link_status_r[16]    = phy_link_training_retraining_status_i;
    ucie_link_status_r[17]    = ucie_link_status_ff[17];
    ucie_link_status_r[18]    = ucie_link_status_ff[18];
    ucie_link_status_r[21:19] = ucie_link_status_ff[21:19];
    ucie_link_status_r[25:22] = adapter_flit_format_status_i;
    ucie_link_status_r[26]    = phy_sideband_performant_mode_operation_status_i;
    ucie_link_status_r[27]    = phy_priority_sideband_packet_transfer_status_i;
    ucie_link_status_r[28]    = phy_l2_sideband_power_down_status_i;
end
assign phy_link_width_enabled_status_out = ucie_link_status_r[10:7];
assign phy_link_speed_enabled_status_out = ucie_link_status_r[14:11];
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
    phy_status        = 32'hFF_FF_FF_FF;
    phy_status[3]     = phy_rx_term_status_i;
    phy_status[4]     = phy_tx_eq_status_i;
    phy_status[5]     = phy_clk_mode_status_i;
    phy_status[6]     = phy_clk_phase_status_i;
    phy_status[7]     = phy_lane_rev_status_i;
    phy_status[13:8]  = phy_iq_correction_param_status_i;
    phy_status[17:14] = phy_eq_preset_setting_status_i;
    phy_status[18]    = phy_tarr_status_i;
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
logic [31:0] phy_control_ff;
always_comb begin
    phy_control_r = phy_control_ff;
    phy_control_r[31:22] = 10'b1111111111;
    
end

assign phy_rx_term_status_i_ctrl_out  = phy_control_r[3];   // Physical Layer Initialization Abort (proxy)
assign phy_tx_eq_status_i_en_ctrl_out    = phy_control_r[4];  // Direct PHY Control Enable
assign phy_rx_clk_mode_ctrl_out = phy_control_r[5];    // PHY_CONTROL[5]: Rx Clock Mode Select
assign phy_rx_clk_phase_ctrl_out = phy_control_r[6];    // PHY_CONTROL[6]: Rx Clock Phase Select
assign phy_x8_width_mode_ctrl_out = phy_control_r[8];    // PHY_CONTROL[8]: Force x8 Width Mode in a UCIe-S x16 Module
assign phy_iq_correction_en_ctrl_out = phy_control_r[9];    // PHY_CONTROL[9]: Force I/Q Correction Enable
assign phy_iq_correction_param_ctrl_out = phy_control_r[15:10];    // PHY_CONTROL[15:10]: Force I/Q Correction Parameter
assign phy_tx_eq_status_i_preset_ctrl_out = phy_control_r[16];    // PHY_CONTROL[16]: Force Tx EQ Preset
assign phy_tx_eq_status_i_preset_setting_ctrl_out = phy_control_r[20:17];    // PHY_CONTROL[20:17]: Force Tx EQ Preset Setting
assign phy_tarr_en_ctrl_out = phy_control_r[21];    // PHY_CONTROL[21]: Tx Adjustment for Runtime Recalibration (TARR)


// Note: bit[22] and [24] added per spec; kept generic for bits not in spec
logic [31:0] phy_init_debug_r;   // bit[7] is RO; written from phy_train_success_i at read
logic [31:0] phy_init_debug_ff;

always_comb begin
    phy_init_debug_r = phy_init_debug_ff;
    phy_init_debug_r[4:3] = 2'b11;
    phy_init_debug_r[31:6] = 26'b11111111111111111111111111;  
end
assign phy_init_ctrl_out = phy_init_debug_r[2:0];    // PHY_INIT_DEBUG[2:0]: PHY Initialization Done
assign phy_resume_training_ctrl_out = phy_init_debug_r[5];    // PHY_INIT_DEBUG[5]: Resume Training
// ---------------------------------------------------------------------------
//  RW registers (generic 32-bit)
// ---------------------------------------------------------------------------
logic [31:0] training_setup1_r;   // Training Setup 1 (1010h)
logic [31:0] training_setup1_ff;
always_comb begin
    training_setup1_r = training_setup1_ff;
    training_setup1_r[31:27] = 5'b11111;
end

logic [31:0] training_setup2_r;   // Training Setup 2 (1020h)

assign idle_count_out = training_setup2_r[15:0];
assign iterations_out = training_setup2_r[31:16];

logic [63:0] training_setup3_r;   // Training Setup 3 (1030h)

assign lane_mask_ctrl_out = training_setup3_r;

logic [31:0] training_setup4_r;   // Training Setup 4 (1050h)

assign max_error_threshold_in_per_lane_comparison_out = training_setup4_r[15:4];
assign max_error_threshold_in_aggregate_comparison_out = training_setup4_r[31:16];

logic [63:0] lane_map_mod0_r;     // Current Lane Map Module 0 (1060h)


logic [63:0] rt_test_ctrl_r;      // Runtime Link Test Control (1100h)
logic [63:0] rt_test_ctrl_ff;      // Runtime Link Test Control (1100h)

always_comb begin
    rt_test_ctrl_r = rt_test_ctrl_ff;
    rt_test_ctrl_r[63:36] = 28'b11111111111111111111111111;
    
end
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

// ---------------------------------------------------------------------------
//  Runtime Link Test Status (1108h) – RO live field --------------------------
// ---------------------------------------------------------------------------
logic [31:0] rt_test_status_r;
always_comb begin
    rt_test_status_r = '0;
    rt_test_status_r [0] = rt_link_busy_status_i;   
end
// ===========================================================================
//  Write / HW-set logic (synchronous)
// ===========================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin

        // ── Latch HWInit at reset ───────────────────────────────────────
        // UCIe Link Capability (RO after reset)
        ucie_link_cap_r              <= '0;
        ucie_link_cap_r[0]           <= adapter_raw_format_support_cap_i;
        ucie_link_cap_r[3:1]         <= hw_max_link_width_cap_i;
        ucie_link_cap_r[7:4]         <= hw_max_link_speed_cap_i;
        ucie_link_cap_r[8]           <= 1'b1;
        ucie_link_cap_r[9]           <= adapter_multi_protocol_cap_cap_i;
        ucie_link_cap_r[10]          <= phy_advanced_pkg_cap_i;
        ucie_link_cap_r[11]          <= adapter_68B_flit_formate_streaming_cap_i;
        ucie_link_cap_r[12]          <= adapter_256B_end_header_flit_format_streaming_cap_i;
        ucie_link_cap_r[13]          <= adapter_256B_start_header_flit_format_streaming_cap_i;
        ucie_link_cap_r[14]          <= adapter_256B_latency_optimized_flit_format_without_optional_bytes_streaming_cap_i;
        ucie_link_cap_r[15]          <= adapter_256B_latency_optimized_flit_format_with_optional_bytes_streaming_cap_i;
        ucie_link_cap_r[16]          <= adapter_enhanced_multi_protocol_capable_cap_i;
        ucie_link_cap_r[17]          <= adapter_standard_start_header_flit_for_pcie_protocol_cap_i;
        ucie_link_cap_r[18]          <= adapter_latency_optimized_flit_with_optional_bytes_for_pcie_protocol_cap_i;
        ucie_link_cap_r[19]          <= adapter_runtime_link_testing_parity_feature_error_signaling_cap_i;
        ucie_link_cap_r[20]          <= hw_apmw_cap_i;
        ucie_link_cap_r[21]          <= 1'b1;
        ucie_link_cap_r[22]          <= hw_spmw_cap_i;
        ucie_link_cap_r[23]          <= phy_sideband_performant_mode_operation_cap_i;
        ucie_link_cap_r[24]          <= phy_priority_sideband_packet_transfer_cap_i;
        ucie_link_cap_r[25]          <= phy_l2_sideband_power_down_cap_i;
        ucio_link_cap_r[31:26]       <= '1;

        // PHY Capability (RO after reset)
        phy_cap_r                    <= 32'hFFFF_FFFF;
        phy_cap_r[3]                 <= phy_term_link_cap_i;
        phy_cap_r[4]                 <= phy_tx_eq_status_iualization_support_cap_i;
        phy_cap_r[9:5]               <= phy_tx_vswing_encodings_cap_i;
        phy_cap_r[12:11]             <= phy_rx_clk_mode_support_cap_i;
        phy_cap_r[14:13]             <= phy_rx_clk_phase_support_cap_i;
        phy_cap_r[15]                <= phy_package_type_cap_i;
        phy_cap_r[16]                <= phy_tcm_support_cap_i;
        phy_cap_r[17]                <= phy_tarr_support_cap_i;

        // ── Config Space RW resets ───────────────────────────────────────
        ucie_link_ctrl_r             <= 32'h0000_1800; // bits[11:12]=1 per spec reset
        ucie_link_status_ff          <= 32'h0000_0000;
        link_event_notif_ctrl_ff      <= 16'h0000;
        error_notif_ctrl_ff           <= 16'h0000;

        // ── MMIO Space RW resets ─────────────────────────────────────────
        phy_control_ff                <= 32'h0000_0000;
        phy_init_debug_ff             <= 32'h0000_0000;
        training_setup1_ff            <= 32'h0000_0000;
        training_setup2_r            <= 32'h0000_0000;
        training_setup3_r            <= 64'h0;
        training_setup4_r            <= 32'h0000_0000;
        lane_map_mod0_r              <= 64'h0;
        rt_test_ctrl_ff               <= 64'h0;

        // ── MMIO Space ROS / RW1CS resets ────────────────────────────────
        error_log0_r                 <= 32'h0000_0000;
        error_log1_r                 <= 32'h0000_0000;

    end else begin

        // ═══════════════════════════════════════════════════════════════════
        //  HW SET paths (always active every cycle — independent of SW)
        // ═══════════════════════════════════════════════════════════════════

        //  UCIe Link Status [17],[18] – RW1C: OR-set from HW events
        if (phy_link_status_changed_status_i) ucie_link_status_ff[17] <= 1'b1;
        if (phy_bw_changed_status_i)          ucie_link_status_ff[18] <= 1'b1;
        if (phy_uci_e_link_correctable_error_i) ucie_link_status_ff[19] <= 1'b1;
        if (phy_uci_e_link_uncorrectable_non_fatal_error_i) ucie_link_status_ff[20] <= 1'b1;
        if (phy_uci_e_link_uncorrectable_fatal_error_i) ucie_link_status_ff[21] <= 1'b1;

        //  Error Log 1 [8],[9],[10],[11] – RW1CS: OR-set from HW events
        if (phy_state_timeout_i) error_log1_r[8]  <= 1'b1;
        if (phy_sb_timeout_i)    error_log1_r[9]  <= 1'b1;
        if (phy_rm_link_err_i)   error_log1_r[10] <= 1'b1;
        if (phy_internal_err_i)  error_log1_r[11] <= 1'b1;

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

                12'h018: begin  // Link Event Notif Ctrl – RW (2 bits)
                    if (rf_be[0]) link_event_notif_ctrl_ff[1:0]  <= rf_wdata[1:0];
                end

                12'h01A: begin  // Error Notif Ctrl – RW (2 bytes)
                    if (rf_be[0]) error_notif_ctrl_ff[7:0]  <= rf_wdata[7:0];
                    if (rf_be[1]) error_notif_ctrl_ff[15:8] <= rf_wdata[15:8];
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
                    if (rf_be[0]) phy_control_ff[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) phy_control_ff[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) phy_control_ff[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) phy_control_ff[31:24] <= rf_wdata[31:24];
                end

                13'h100C: begin  // PHY Initialization and Debug – RW (bit[7] is RO)
                    // bit[7] = Link Training Success is RO (from HW); SW write ignored.
                    if (rf_be[0]) phy_init_debug_ff[6:0]   <= rf_wdata[6:0];   // bit[7] protected
                    if (rf_be[1]) phy_init_debug_ff[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) phy_init_debug_ff[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) phy_init_debug_ff[31:24] <= rf_wdata[31:24];
                end

                13'h1010: begin  // Training Setup 1 – RW
                    if (rf_be[0]) training_setup1_ff[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) training_setup1_ff[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) training_setup1_ff[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) training_setup1_ff[31:24] <= rf_wdata[31:24];
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
                    if (rf_be[4]) training_setup3_r[39:32] <= rf_wdata[39:32];
                    if (rf_be[5]) training_setup3_r[47:40] <= rf_wdata[47:40];
                    if (rf_be[6]) training_setup3_r[55:48] <= rf_wdata[55:48];
                    if (rf_be[7]) training_setup3_r[63:56] <= rf_wdata[63:56];
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
                    if (rf_be[0]) rt_test_ctrl_ff[7:0]   <= rf_wdata[7:0];
                    if (rf_be[1]) rt_test_ctrl_ff[15:8]  <= rf_wdata[15:8];
                    if (rf_be[2]) rt_test_ctrl_ff[23:16] <= rf_wdata[23:16];
                    if (rf_be[3]) rt_test_ctrl_ff[31:24] <= rf_wdata[31:24];
                    if (rf_be[4]) rt_test_ctrl_ff[39:32] <= rf_wdata[39:32];
                    if (rf_be[5]) rt_test_ctrl_ff[47:40] <= rf_wdata[47:40];
                    if (rf_be[6]) rt_test_ctrl_ff[55:48] <= rf_wdata[55:48];
                    if (rf_be[7]) rt_test_ctrl_ff[63:56] <= rf_wdata[63:56];
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
            error_log0_r[8]     <= phy_lane_rev_err_log_i;         // Lane Reversal at error
            error_log0_r[9]     <= phy_width_degrade_err_log_i;                 // Width Degrade (not modelled)
            // Error Log 1 [7:0] – State N-3: shift from Error Log 0's old N-2
            error_log1_r[7:0]   <= error_log0_r[31:24]; // State N-3
        end

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
                12'h014: rf_rdata <= {32'h0, ucie_link_status_r};     // mixed
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
                13'h100C: rf_rdata <= {32'h0, phy_init_debug_r};       // RW + RO mixed
                13'h1010: rf_rdata <= {32'h0, training_setup1_r};
                13'h1020: rf_rdata <= {32'h0, training_setup2_r};
                13'h1030: rf_rdata <= training_setup3_r;
                13'h1050: rf_rdata <= {32'h0, training_setup4_r};
                13'h1060: rf_rdata <= lane_map_mod0_r;                  // 64-bit
                13'h1080: rf_rdata <= {32'h0, error_log0_r};           // ROS
                13'h1090: rf_rdata <= {32'h0, error_log1_r};           // ROS+RW1CS
                13'h1100: rf_rdata <= rt_test_ctrl_r;                   // 64-bit
                13'h1108: rf_rdata <= {32'h0, rt_test_status_r};       // RO live
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


endmodule
