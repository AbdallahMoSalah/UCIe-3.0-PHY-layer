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
    input  logic         rf_is_64b_access, // 64-bit access or 32-bit access
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
    output logic [15:0] current_lane_map_module_0_enable_out,
    







    //Runtime link test
    output logic rt_link_test_start_ctrl_out,
    output logic rt_apply_module_0_lane_repair_ctrl_out,
    output logic inject_stuck_at_fault_ctrl_out,
    output logic [6:0] module_0_lane_repair_id_ctrl_out,


    
    // =======================================================================
    //  Convenience taps
    // =======================================================================
    output logic [31:0]  ucie_link_cap_r_out, 
    output logic [31:0]  ucie_link_ctrl_r_out, 
    output logic [31:0]  ucie_link_status_r_out, 
    output logic [15:0]  link_event_notif_ctrl_r_out, 
    output logic [15:0]  error_notif_ctrl_r_out, 
    output logic [31:0]  phy_cap_r_out, 
    output logic [31:0]  phy_control_r_out, 
    output logic [31:0]  phy_status_r_out, 
    output logic [31:0]  phy_init_debug_r_out, // bit[7] is RO; written from phy_train_success_i at read
    output logic [31:0]  training_setup1_r_out, // Training Setup 1 (1010h)
    output logic [31:0]  training_setup2_r_out, // Training Setup 2 (1020h)
    output logic [63:0]  training_setup3_r_out, // Training Setup 3 (1030h)
    output logic [31:0]  training_setup4_r_out, // Training Setup 4 (1050h)
    output logic [63:0]  lane_map_mod0_r_out, // Current Lane Map Module 0 (1060h)
    output logic [31:0]  error_log0_r_out, 
    output logic [31:0]  error_log1_r_out, 
    output logic [63:0]  rt_test_ctrl_r_out, // Runtime Link Test Control (1100h)
    output logic [31:0]  rt_test_status_r_out);

// ===========================================================================
//  Internal Register Declarations & Output Assignments
// ===========================================================================
logic [31:0]  ucie_link_cap_r;
logic [31:0]  ucie_link_ctrl_r;
logic [31:0]  ucie_link_status_r;
logic [15:0]  link_event_notif_ctrl_r;
logic [15:0]  error_notif_ctrl_r;
logic [31:0]  phy_cap_r;
logic [31:0]  phy_control_r;
logic [31:0]  phy_status_r;
logic [31:0]  phy_init_debug_r;
logic [31:0]  training_setup1_r;
logic [31:0]  training_setup2_r;
logic [63:0]  training_setup3_r;
logic [31:0]  training_setup4_r;
logic [63:0]  lane_map_mod0_r;
logic [31:0]  error_log0_r;
logic [31:0]  error_log1_r;
logic [63:0]  rt_test_ctrl_r;
logic [31:0]  rt_test_status_r;

assign ucie_link_cap_r_out = ucie_link_cap_r;
assign ucie_link_ctrl_r_out = ucie_link_ctrl_r;
assign ucie_link_status_r_out = ucie_link_status_r;
assign link_event_notif_ctrl_r_out = link_event_notif_ctrl_r;
assign error_notif_ctrl_r_out = error_notif_ctrl_r;
assign phy_cap_r_out = phy_cap_r;
assign phy_control_r_out = phy_control_r;
assign phy_status_r_out = phy_status_r;
assign phy_init_debug_r_out = phy_init_debug_r;
assign training_setup1_r_out = training_setup1_r;
assign training_setup2_r_out = training_setup2_r;
assign training_setup3_r_out = training_setup3_r;
assign training_setup4_r_out = training_setup4_r;
assign lane_map_mod0_r_out = lane_map_mod0_r;
assign error_log0_r_out = error_log0_r;
assign error_log1_r_out = error_log1_r;
assign rt_test_ctrl_r_out = rt_test_ctrl_r;
assign rt_test_status_r_out = rt_test_status_r;

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

assign addr_err_o = !cfg_sel && !phy_mmio_sel;

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
//    [0]    Raw Format Support
//    [3:1]  Max Link Width
//    [7:4]  Max Link Speed
//    [9]    Multi-Protocol Capability
//    [10]   Advanced Package
//    [11]   68B Flit Format Streaming
//    [12]   256B End Header Flit Format for Streaming
//    [13]   256B Start Header Flit Format for Streaming
//    [14]   Latency-Optimized 256B Flit Format without Optional Bytes
//    [15]   Latency-Optimized 256B Flit Format with Optional Bytes
//    [16]   Enhanced Multi-protocol Capable
//    [17]   Standard Start Header Flit for PCIe Protocol
//    [18]   Latency-Optimized Flit with Optional Bytes for PCIe Protocol
//    [19]   Runtime Link Testing Parity Feature Error Signaling
//    [20]   Advanced Package Module Width
//    [22]   Standard Package Module Width
//    [23]   Sideband Performant Mode Operation (PMO)
//    [24]   Priority Sideband Packet Transfer (PSPT)
//    [25]   L2 Sideband Power Down (L2SPD)
//    others = RsvdZ
// ---------------------------------------------------------------------------
logic [31:0] ucie_link_cap_ff;   // Latched at reset from HW inputs
always_comb begin
    ucie_link_cap_r = ucie_link_cap_ff;
end
assign phy_max_link_speed_cap_out = ucie_link_cap_r[7:4];

// ---------------------------------------------------------------------------
//  RW registers
// ---------------------------------------------------------------------------
//  UCIe Link Control (010h)
//    [5:2] Target Link Width
//    [9:6] Target Link Speed
//    [10]  Start UCIe Link Training
//    [11]  Retrain UCIe Link
//    [21]  Sideband Performant Mode Operation (PMO)
//    [22]  Priority Sideband Packet Transfer (PSPT)
//    [23]  L2 Sideband Power Down (L2SPD)
//    others = RsvdZ
logic [31:0] ucie_link_ctrl_ff;
always_comb begin
    ucie_link_ctrl_r = ucie_link_ctrl_ff;
    ucie_link_ctrl_r[31:24] = 8'b11111111;   // Reserved
end

// ---------------------------------------------------------------------------
//  Auto-clear for bit[10] "Start UCIe Link Training" and bit[11] "Retrain"
//  UCIe Link"
//  Per UCIe Spec §9.5.1 Table 9-9:
//    bit[10]: "This bit is automatically cleared when the Link training
//              completes with either success or error."
//    bit[11]: Same auto-clear semantics.
//  Also per spec: if SW writes 1 while training is already in progress
//    (phy_link_training_retraining_status_i == 1), the write is ignored.
//
//  Implementation: detect the falling edge (1→0) of
//  phy_link_training_retraining_status_i (= Link Status bit[16]), which is
//  already wired as an RO live input.  No new ports required.
// ---------------------------------------------------------------------------
logic training_active_q;  // previous-cycle copy for edge detection

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        training_active_q <= 1'b0;
    else
        training_active_q <= phy_link_training_retraining_status_i;
end

// Pulse asserted for exactly one cycle when training finishes (1→0 edge)
logic training_done_pulse;
assign training_done_pulse = training_active_q & ~phy_link_training_retraining_status_i;

assign phy_target_link_width_ctrl_out = ucie_link_ctrl_r[5:2];
assign phy_target_link_speed_ctrl_out = ucie_link_ctrl_r[9:6];
assign phy_start_ucie_link_training_ctrl_out = ucie_link_ctrl_r[10];
assign phy_retrain_ucie_link_ctrl_out = ucie_link_ctrl_r[11];
assign phy_pmo_ctrl_out = ucie_link_ctrl_r[21];
assign phy_pspt_ctrl_out = ucie_link_ctrl_r[22];
assign phy_l2spd_ctrl_out = ucie_link_ctrl_r[23];

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
logic [31:0] ucie_link_status_ff;
logic link_status_changed_q;  // previous-cycle copy for edge detection

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        link_status_changed_q <= 1'b0;
    else
        link_status_changed_q <= phy_link_status_status_i;
end

// Pulse asserted for exactly one cycle when training finishes (1→0 edge)
logic link_status_changed_pulse;
assign link_status_changed_pulse = link_status_changed_q ^ phy_link_status_status_i;

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
    ucie_link_status_r[21:17] = ucie_link_status_ff[21:17];
    ucie_link_status_r[25:22] = adapter_flit_format_status_i;
    ucie_link_status_r[26]    = phy_sideband_performant_mode_operation_status_i;
    ucie_link_status_r[27]    = phy_priority_sideband_packet_transfer_status_i;
    ucie_link_status_r[28]    = phy_l2_sideband_power_down_status_i;
end
assign phy_link_width_enabled_status_out = ucie_link_status_r[10:7];
assign phy_link_speed_enabled_status_out = ucie_link_status_r[14:11];

//  Link Event Notif Ctrl (018h) – RW, 2-byte
logic [15:0] link_event_notif_ctrl_ff;
always_comb begin
    link_event_notif_ctrl_r [1:0]   = link_event_notif_ctrl_ff[1:0];
    link_event_notif_ctrl_r [10:2]  = 9'b0_0111_1111;
    link_event_notif_ctrl_r [15:11] = link_event_notification_interrupt_number_i;
end



//  Error Notif Ctrl (01Ah) – RW, 2-byte
logic [15:0] error_notif_ctrl_ff;
always_comb begin
    error_notif_ctrl_r = error_notif_ctrl_ff;
    error_notif_ctrl_r[10:6] = 5'b11111;
end



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
logic [31:0] phy_cap_ff;
always_comb begin
    phy_cap_r = phy_cap_ff;
end


// ---------------------------------------------------------------------------
//  RW + RO mixed – PHY Control (1004h)  [UCIe §9.5.2]
//    [3]  Rx Termination Enable
//    [4]  Tx EQ Enable
//    [5]  Rx Clock Mode Select
//    [6]  Rx Clock Phase Select
//    [8]  Force x8 Width Mode in a UCIe-S x16 Module
//    [9]  Force I/Q Correction Enable
//    [15:10] Force I/Q Correction Parameter
//    [16] Force Tx EQ Preset
//    [20:17] Force Tx EQ Preset Setting
//    [21] Tx Adjustment for Runtime Recalibration (TARR)
//
//  RW + RO mixed – PHY Initialization and Debug (100Ch)
//    [2:0] PHY Initialization Done
//    [5]   Resume Training
//    others = RsvdZ
// ---------------------------------------------------------------------------
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
always_comb begin
    phy_status_r        = 32'hFF_FF_FF_FF;
    phy_status_r[3]     = phy_rx_term_status_i;
    phy_status_r[4]     = phy_tx_eq_status_i;
    phy_status_r[5]     = phy_clk_mode_status_i;
    phy_status_r[6]     = phy_clk_phase_status_i;
    phy_status_r[7]     = phy_lane_rev_status_i;
    phy_status_r[13:8]  = phy_iq_correction_param_status_i;
    phy_status_r[17:14] = phy_eq_preset_setting_status_i;
    phy_status_r[18]    = phy_tarr_status_i;
end



// Note: bit[22] and [24] added per spec; kept generic for bits not in spec
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
logic [31:0] training_setup1_ff;
always_comb begin
    training_setup1_r = training_setup1_ff;
    training_setup1_r[31:27] = 5'b11111;
end
logic [31:0] training_setup2_ff;

always_comb begin
    training_setup2_r = training_setup2_ff;
end
    

assign idle_count_out = training_setup2_r[15:0];
assign iterations_out = training_setup2_r[31:16];
logic [63:0] training_setup3_ff;
always_comb begin
    training_setup3_r = training_setup3_ff;
end

assign lane_mask_ctrl_out = training_setup3_r;
logic [31:0] training_setup4_ff;
always_comb begin
    training_setup4_r = training_setup4_ff;
end
assign max_error_threshold_in_per_lane_comparison_out = training_setup4_r[15:4];
assign max_error_threshold_in_aggregate_comparison_out = training_setup4_r[31:16];
logic [63:0] lane_map_mod0_ff;

always_comb begin
    lane_map_mod0_r = lane_map_mod0_ff;
end
assign current_lane_map_module_0_enable_out = lane_map_mod0_r[15:0];

// ---------------------------------------------------------------------------
//  Error Log 0 (1080h) – all ROS  [UCIe §9.5.34]
//    [7:0]   State N   – LTSM state at error
//    [8]     Lane Reversal at error time
//    [9]     Width Degrade (Standard Package only)
//    [15:10] RsvdZ
//    [23:16] State N-1
//    [31:24] State N-2
// ---------------------------------------------------------------------------
logic [31:0] error_log0_ff;

always_comb begin
    error_log0_r = error_log0_ff;
    error_log0_r [15:10] = 6'b0;
end

// ---------------------------------------------------------------------------
//  Error Log 1 (1090h) – MIXED: ROS + RW1CS
//    [7:0]  State N-3            ROS   – HW shift; cleared only by reset
//    [8]    State Timeout        RW1CS – HW sets; SW clears writing 1; sticky
//    [9]    Sideband Timeout     RW1CS
//    [10]   RM Link Error        RW1CS
//    [11]   Internal Error       RW1CS
//    [31:12] RsvdZ
// ---------------------------------------------------------------------------
logic [31:0] error_log1_ff;

always_comb begin
    error_log1_r = error_log1_ff;
    error_log1_r[31:12] = 20'b0;
end
logic [63:0] rt_test_ctrl_ff;      // Runtime Link Test Control (1100h)

always_comb begin
    rt_test_ctrl_r = rt_test_ctrl_ff;
    rt_test_ctrl_r[63:36] = 28'b11111111111111111111111111;
    
end
// rt_link_test_start_ctrl_out / rt_apply_module_0_lane_repair_ctrl_out /
// inject_stuck_at_fault_ctrl_out / module_0_lane_repair_id_ctrl_out are module
// output ports (declared in the port list); driven directly by the assigns below.
assign rt_link_test_start_ctrl_out = rt_test_ctrl_r[6];
assign rt_apply_module_0_lane_repair_ctrl_out = rt_test_ctrl_r[2];
assign inject_stuck_at_fault_ctrl_out = rt_test_ctrl_r[7];
assign module_0_lane_repair_id_ctrl_out = rt_test_ctrl_r[14:8];

// ---------------------------------------------------------------------------
//  Runtime Link Test Status (1108h) – RO live field --------------------------
// ---------------------------------------------------------------------------
always_comb begin
    rt_test_status_r = '0;
    rt_test_status_r [0] = rt_link_busy_status_i;   
end


// ===========================================================================
//  Byte-level Write Address Decoders (combinatorial memory mapping)
// ===========================================================================
logic       cfg_we   [0:35];
logic [7:0] cfg_wdat [0:35];

always_comb begin
    for (int i=0; i<=35; i++) begin
        cfg_we[i]   = 1'b0;
        cfg_wdat[i] = 8'h0;
    end
    if (wr_en && cfg_sel) begin
        for (int i=0; i<8; i++) begin
            if ((i < 4 || rf_is_64b_access) && rf_be[i]) begin
                if ((int'(rf_addr[11:0]) + i) <= 35) begin
                    cfg_we[int'(rf_addr[11:0]) + i]   = 1'b1;
                    cfg_wdat[int'(rf_addr[11:0]) + i] = rf_wdata[i*8 +: 8];
                end
            end
        end
    end
end

logic       mmio_we  [0:267];
logic [7:0] mmio_wdat[0:267];

always_comb begin
    for (int i=0; i<=267; i++) begin
        mmio_we[i]   = 1'b0;
        mmio_wdat[i] = 8'h0;
    end
    if (wr_en && phy_mmio_sel) begin
        for (int i=0; i<8; i++) begin
            if ((i < 4 || rf_is_64b_access) && rf_be[i]) begin
                if ((int'(rf_addr[12:0]) - 32'h1000 + i) <= 267) begin
                    mmio_we[int'(rf_addr[12:0]) - 32'h1000 + i]   = 1'b1;
                    mmio_wdat[int'(rf_addr[12:0]) - 32'h1000 + i] = rf_wdata[i*8 +: 8];
                end
            end
        end
    end
end

// ===========================================================================
//  Byte-level Read Data Mapping (combinatorial memory mapping)
// ===========================================================================
logic [7:0] cfg_mem [0:35];
always_comb begin
    for (int i=0; i<=35; i++) cfg_mem[i] = 8'h0;
    
    {cfg_mem[3], cfg_mem[2], cfg_mem[1], cfg_mem[0]} = PCIE_EXT_CAP_HDR_VAL;
    {cfg_mem[7], cfg_mem[6], cfg_mem[5], cfg_mem[4]} = DVSEC_HDR1_VAL;
    {cfg_mem[9], cfg_mem[8]}                         = DVSEC_HDR2_VAL;
    {cfg_mem[11], cfg_mem[10]}                       = CAP_DESC_VAL;
    {cfg_mem[15], cfg_mem[14], cfg_mem[13], cfg_mem[12]} = ucie_link_cap_r;
    {cfg_mem[19], cfg_mem[18], cfg_mem[17], cfg_mem[16]} = ucie_link_ctrl_r;
    {cfg_mem[23], cfg_mem[22], cfg_mem[21], cfg_mem[20]} = ucie_link_status_r;
    {cfg_mem[25], cfg_mem[24]}                           = link_event_notif_ctrl_r;
    {cfg_mem[27], cfg_mem[26]}                           = error_notif_ctrl_r;
    {cfg_mem[31], cfg_mem[30], cfg_mem[29], cfg_mem[28]} = REG_LOC_0_LOW_VAL;
    {cfg_mem[35], cfg_mem[34], cfg_mem[33], cfg_mem[32]} = REG_LOC_0_HIGH_VAL;
end

logic [7:0] mmio_mem [0:267];
always_comb begin
    for (int i=0; i<=267; i++) mmio_mem[i] = 8'h0;
    
    {mmio_mem[3], mmio_mem[2], mmio_mem[1], mmio_mem[0]}       = phy_cap_r;
    {mmio_mem[7], mmio_mem[6], mmio_mem[5], mmio_mem[4]}       = phy_control_r;
    {mmio_mem[11], mmio_mem[10], mmio_mem[9], mmio_mem[8]}     = phy_status_r;
    {mmio_mem[15], mmio_mem[14], mmio_mem[13], mmio_mem[12]}   = phy_init_debug_r;
    {mmio_mem[19], mmio_mem[18], mmio_mem[17], mmio_mem[16]}   = training_setup1_r;
    {mmio_mem[35], mmio_mem[34], mmio_mem[33], mmio_mem[32]}   = training_setup2_r;
    {mmio_mem[55], mmio_mem[54], mmio_mem[53], mmio_mem[52], mmio_mem[51], mmio_mem[50], mmio_mem[49], mmio_mem[48]} = training_setup3_r;
    {mmio_mem[83], mmio_mem[82], mmio_mem[81], mmio_mem[80]}   = training_setup4_r;
    {mmio_mem[103], mmio_mem[102], mmio_mem[101], mmio_mem[100], mmio_mem[99], mmio_mem[98], mmio_mem[97], mmio_mem[96]} = lane_map_mod0_r;
    {mmio_mem[131], mmio_mem[130], mmio_mem[129], mmio_mem[128]} = error_log0_r;
    {mmio_mem[147], mmio_mem[146], mmio_mem[145], mmio_mem[144]} = error_log1_r;
    {mmio_mem[263], mmio_mem[262], mmio_mem[261], mmio_mem[260], mmio_mem[259], mmio_mem[258], mmio_mem[257], mmio_mem[256]} = rt_test_ctrl_r;
    {mmio_mem[267], mmio_mem[266], mmio_mem[265], mmio_mem[264]} = rt_test_status_r;
end

// ===========================================================================
//  Write / HW-set logic (synchronous)
// ===========================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin

        // ── Latch HWInit at reset ───────────────────────────────────────
        // UCIe Link Capability (RO after reset)
        ucie_link_cap_ff              <= '0;
        ucie_link_cap_ff[0]           <= adapter_raw_format_support_cap_i;
        ucie_link_cap_ff[3:1]         <= hw_max_link_width_cap_i;
        ucie_link_cap_ff[7:4]         <= hw_max_link_speed_cap_i;
        ucie_link_cap_ff[8]           <= 1'b1;
        ucie_link_cap_ff[9]           <= adapter_multi_protocol_cap_i;
        ucie_link_cap_ff[10]          <= phy_advanced_pkg_cap_i;
        ucie_link_cap_ff[11]          <= adapter_68B_flit_formate_streaming_cap_i;
        ucie_link_cap_ff[12]          <= adapter_256B_end_header_flit_format_streaming_cap_i;
        ucie_link_cap_ff[13]          <= adapter_256B_start_header_flit_format_streaming_cap_i;
        ucie_link_cap_ff[14]          <= adapter_256B_latency_optimized_flit_format_without_optional_bytes_streaming_cap_i;
        ucie_link_cap_ff[15]          <= adapter_256B_latency_optimized_flit_format_with_optional_bytes_streaming_cap_i;
        ucie_link_cap_ff[16]          <= adapter_enhanced_multi_protocol_capable_cap_i;
        ucie_link_cap_ff[17]          <= adapter_standard_start_header_flit_for_pcie_protocol_cap_i;
        ucie_link_cap_ff[18]          <= adapter_latency_optimized_flit_with_optional_bytes_for_pcie_protocol_cap_i;
        ucie_link_cap_ff[19]          <= adapter_runtime_link_testing_parity_feature_error_signaling_cap_i;
        ucie_link_cap_ff[20]          <= hw_apmw_cap_i;
        ucie_link_cap_ff[21]          <= 1'b1;
        ucie_link_cap_ff[22]          <= hw_spmw_cap_i;
        ucie_link_cap_ff[23]          <= phy_sideband_performant_mode_operation_cap_i;
        ucie_link_cap_ff[24]          <= phy_priority_sideband_packet_transfer_cap_i;
        ucie_link_cap_ff[25]          <= phy_l2_sideband_power_down_cap_i;
        ucie_link_cap_ff[31:26]       <= 6'b111111;

        // PHY Capability (RO after reset)
        phy_cap_ff                    <= 32'hFFFF_FFFF;
        phy_cap_ff[3]                 <= phy_term_link_cap_i;
        phy_cap_ff[4]                 <= phy_tx_eq_status_iualization_support_cap_i;
        phy_cap_ff[9:5]               <= phy_tx_vswing_encodings_cap_i;
        phy_cap_ff[12:11]             <= phy_rx_clk_mode_support_cap_i;
        phy_cap_ff[14:13]             <= phy_rx_clk_phase_support_cap_i;
        phy_cap_ff[15]                <= phy_package_type_cap_i;
        phy_cap_ff[16]                <= phy_tcm_support_cap_i;
        phy_cap_ff[17]                <= phy_tarr_support_cap_i;

        // ── Config Space RW resets ───────────────────────────────────────
        // UCIe Link Control default value after reset is 0
        ucie_link_ctrl_ff[0]          <= 1'b0;
        ucie_link_ctrl_ff[1]          <= adapter_multi_protocol_cap_i;

        ucie_link_ctrl_ff[5:2]          <= 4'(hw_max_link_width_cap_i);

        ucie_link_ctrl_ff[9:6]          <= hw_max_link_speed_cap_i;
        ucie_link_ctrl_ff[10]         <= 1'b0;
        ucie_link_ctrl_ff[11]         <= 1'b0;
        ucie_link_ctrl_ff[12]         <= 1'b0;

        ucie_link_ctrl_ff[13]         <= adapter_68B_flit_formate_streaming_cap_i;
        ucie_link_ctrl_ff[14]         <= adapter_256B_end_header_flit_format_streaming_cap_i;
        ucie_link_ctrl_ff[15]         <= adapter_256B_start_header_flit_format_streaming_cap_i;
        ucie_link_ctrl_ff[16]         <= adapter_256B_latency_optimized_flit_format_without_optional_bytes_streaming_cap_i;
        ucie_link_ctrl_ff[17]         <= adapter_256B_latency_optimized_flit_format_with_optional_bytes_streaming_cap_i;
        ucie_link_ctrl_ff[18]         <= adapter_enhanced_multi_protocol_capable_cap_i;
        ucie_link_ctrl_ff[19]         <= adapter_standard_start_header_flit_for_pcie_protocol_cap_i;

        ucie_link_ctrl_ff[20]         <= adapter_latency_optimized_flit_with_optional_bytes_for_pcie_protocol_cap_i;
        ucie_link_ctrl_ff[21]         <= phy_sideband_performant_mode_operation_cap_i;
        ucie_link_ctrl_ff[22]         <= phy_priority_sideband_packet_transfer_cap_i;
        ucie_link_ctrl_ff[23]         <= phy_l2_sideband_power_down_cap_i;
        ucie_link_ctrl_ff[31:24]      <= 8'b11111111;





        ucie_link_status_ff          <= 32'h0000_0000;
        link_event_notif_ctrl_ff      <= 16'h0000;
        error_notif_ctrl_ff           <= 16'h0000;

        // ── MMIO Space RW resets ─────────────────────────────────────────
        phy_control_ff                <= 32'h0000_0000;
        phy_init_debug_ff             <= 32'h0000_0000;
        training_setup1_ff            <= 32'h0000_0000;
        training_setup2_ff            <= 32'h0000_0000;
        training_setup3_ff            <= 64'h0;
        training_setup4_ff            <= 32'h0000_0000;
        lane_map_mod0_ff              <= 64'h0;
        rt_test_ctrl_ff               <= 64'h0;

        // ── MMIO Space ROS / RW1CS resets ────────────────────────────────
        error_log0_ff                 <= 32'h0000_0000;
        error_log1_ff                 <= 32'h0000_0000;

    end else begin

        // ═══════════════════════════════════════════════════════════════════
        //  HW SET paths (always active every cycle — independent of SW)
        // ═══════════════════════════════════════════════════════════════════

        //  UCIe Link Status [17],[18] – RW1C: OR-set from HW events
        if (link_status_changed_pulse) ucie_link_status_ff[17] <= 1'b1;
        if (phy_bw_changed_status_i)          ucie_link_status_ff[18] <= 1'b1;
        if (phy_uci_e_link_correctable_error_i) ucie_link_status_ff[19] <= 1'b1;
        if (phy_uci_e_link_uncorrectable_non_fatal_error_i) ucie_link_status_ff[20] <= 1'b1;
        if (phy_uci_e_link_uncorrectable_fatal_error_i) ucie_link_status_ff[21] <= 1'b1;

        //  Error Log 1 [8],[9],[10],[11] – RW1CS: OR-set from HW events
        if (phy_state_timeout_i) error_log1_ff[8]  <= 1'b1;
        if (phy_sb_timeout_i)    error_log1_ff[9]  <= 1'b1;
        if (phy_rm_link_err_i)   error_log1_ff[10] <= 1'b1;
        if (phy_internal_err_i)  error_log1_ff[11] <= 1'b1;


        // ═══════════════════════════════════════════════════════════════════
        //  SW write path – Config Space (addr[24]=0, RL=0) mapped from byte memory
        // ═══════════════════════════════════════════════════════════════════
        if (wr_en && cfg_sel) begin
            if (cfg_we[16]) ucie_link_ctrl_ff[7:0]   <= cfg_wdat[16];
            if (cfg_we[17]) begin
                // byte 1 of UCIe Link Control (offset 11h) contains:
                //   [10] Start UCIe Link Training  (bit 2 of this byte)
                //   [11] Retrain UCIe Link         (bit 3 of this byte)
                // Per spec: if training is already in progress, a 0→1 write
                // on these bits must be ignored.
                ucie_link_ctrl_ff[15:8] <= cfg_wdat[17];
                if (phy_link_training_retraining_status_i) begin
                    if(!phy_link_status_status_i)begin 
                        ucie_link_ctrl_ff[10] <= ucie_link_ctrl_ff[10]; // hold – write ignored during training
                    end
                    ucie_link_ctrl_ff[11] <= ucie_link_ctrl_ff[11]; // hold – write ignored during training
                end
            end
            if (cfg_we[18]) ucie_link_ctrl_ff[23:16] <= cfg_wdat[18];

            if (cfg_we[22]) begin // 014h, byte 2 has RW1C bits [21:17]
                ucie_link_status_ff[17] <= ucie_link_status_ff[17] & ~cfg_wdat[22][1];
                ucie_link_status_ff[18] <= ucie_link_status_ff[18] & ~cfg_wdat[22][2];
                ucie_link_status_ff[19] <= ucie_link_status_ff[19] & ~cfg_wdat[22][3];
                ucie_link_status_ff[20] <= ucie_link_status_ff[20] & ~cfg_wdat[22][4];
                ucie_link_status_ff[21] <= ucie_link_status_ff[21] & ~cfg_wdat[22][5];
            end

            if (cfg_we[24]) link_event_notif_ctrl_ff[1:0] <= cfg_wdat[24][1:0];

            if (cfg_we[26]) error_notif_ctrl_ff[7:0]  <= cfg_wdat[26];
            if (cfg_we[27]) error_notif_ctrl_ff[15:8] <= cfg_wdat[27];

        end  // if (wr_en && cfg_sel)

        // ═══════════════════════════════════════════════════════════════════
        //  HW auto-clear – UCIe Link Control [10],[11]  (RWac)
        //  Per UCIe Spec §9.5.1 Table 9-9:
        //    bit[10] "Start UCIe Link Training" and bit[11] "Retrain UCIe Link"
        //    are automatically cleared when Link training completes (success or
        //    error), detected as the falling edge (1→0) of the live RO signal
        //    phy_link_training_retraining_status_i (= Link Status bit[16]).
        //  Placed AFTER the SW write block so it always wins (last assignment
        //  in always_ff takes effect — HW beats SW on simultaneous events).
        // ═══════════════════════════════════════════════════════════════════
        if (training_done_pulse) begin
            ucie_link_ctrl_ff[10] <= 1'b0;  // Start UCIe Link Training – auto-cleared
            ucie_link_ctrl_ff[11] <= 1'b0;  // Retrain UCIe Link      – auto-cleared
        end


        if(rt_link_busy_status_i) begin
            rt_test_ctrl_ff[6] <= 0;
        end
        // ═══════════════════════════════════════════════════════════════════
        //  SW write path – MMIO Space (addr[24]=1, RL=0) mapped from byte memory
        // ═══════════════════════════════════════════════════════════════════
        if (wr_en && phy_mmio_sel) begin
            if (mmio_we[4]) phy_control_ff[7:0]   <= mmio_wdat[4];
            if (mmio_we[5]) phy_control_ff[15:8]  <= mmio_wdat[5];
            if (mmio_we[6]) phy_control_ff[23:16] <= mmio_wdat[6];
            if (mmio_we[7]) phy_control_ff[31:24] <= mmio_wdat[7];

            if (mmio_we[12]) phy_init_debug_ff[7:0]   <= mmio_wdat[12];
            if (mmio_we[13]) phy_init_debug_ff[15:8]  <= mmio_wdat[13];
            if (mmio_we[14]) phy_init_debug_ff[23:16] <= mmio_wdat[14];
            if (mmio_we[15]) phy_init_debug_ff[31:24] <= mmio_wdat[15];

            if (mmio_we[16]) training_setup1_ff[7:0]   <= mmio_wdat[16];
            if (mmio_we[17]) training_setup1_ff[15:8]  <= mmio_wdat[17];
            if (mmio_we[18]) training_setup1_ff[23:16] <= mmio_wdat[18];
            if (mmio_we[19]) training_setup1_ff[31:24] <= mmio_wdat[19];

            if (mmio_we[32]) training_setup2_ff[7:0]   <= mmio_wdat[32];
            if (mmio_we[33]) training_setup2_ff[15:8]  <= mmio_wdat[33];
            if (mmio_we[34]) training_setup2_ff[23:16] <= mmio_wdat[34];
            if (mmio_we[35]) training_setup2_ff[31:24] <= mmio_wdat[35];

            if (mmio_we[48]) training_setup3_ff[7:0]   <= mmio_wdat[48];
            if (mmio_we[49]) training_setup3_ff[15:8]  <= mmio_wdat[49];
            if (mmio_we[50]) training_setup3_ff[23:16] <= mmio_wdat[50];
            if (mmio_we[51]) training_setup3_ff[31:24] <= mmio_wdat[51];
            if (mmio_we[52]) training_setup3_ff[39:32] <= mmio_wdat[52];
            if (mmio_we[53]) training_setup3_ff[47:40] <= mmio_wdat[53];
            if (mmio_we[54]) training_setup3_ff[55:48] <= mmio_wdat[54];
            if (mmio_we[55]) training_setup3_ff[63:56] <= mmio_wdat[55];

            if (mmio_we[80]) training_setup4_ff[7:0]   <= mmio_wdat[80];
            if (mmio_we[81]) training_setup4_ff[15:8]  <= mmio_wdat[81];
            if (mmio_we[82]) training_setup4_ff[23:16] <= mmio_wdat[82];
            if (mmio_we[83]) training_setup4_ff[31:24] <= mmio_wdat[83];

            if (mmio_we[96])  lane_map_mod0_ff[7:0]   <= mmio_wdat[96];
            if (mmio_we[97])  lane_map_mod0_ff[15:8]  <= mmio_wdat[97];
            if (mmio_we[98])  lane_map_mod0_ff[23:16] <= mmio_wdat[98];
            if (mmio_we[99])  lane_map_mod0_ff[31:24] <= mmio_wdat[99];
            if (mmio_we[100]) lane_map_mod0_ff[39:32] <= mmio_wdat[100];
            if (mmio_we[101]) lane_map_mod0_ff[47:40] <= mmio_wdat[101];
            if (mmio_we[102]) lane_map_mod0_ff[55:48] <= mmio_wdat[102];
            if (mmio_we[103]) lane_map_mod0_ff[63:56] <= mmio_wdat[103];

            if (mmio_we[145]) begin // 1090h byte 1
                error_log1_ff[8]  <= error_log1_ff[8]  & ~mmio_wdat[145][0];
                error_log1_ff[9]  <= error_log1_ff[9]  & ~mmio_wdat[145][1];
                error_log1_ff[10] <= error_log1_ff[10] & ~mmio_wdat[145][2];
                error_log1_ff[11] <= error_log1_ff[11] & ~mmio_wdat[145][3];
            end

            if (mmio_we[256]) rt_test_ctrl_ff[7:0]   <= mmio_wdat[256];
            if (mmio_we[257]) rt_test_ctrl_ff[15:8]  <= mmio_wdat[257];
            if (mmio_we[258]) rt_test_ctrl_ff[23:16] <= mmio_wdat[258];
            if (mmio_we[259]) rt_test_ctrl_ff[31:24] <= mmio_wdat[259];
            if (mmio_we[260]) rt_test_ctrl_ff[39:32] <= mmio_wdat[260];
            if (mmio_we[261]) rt_test_ctrl_ff[47:40] <= mmio_wdat[261];
            if (mmio_we[262]) rt_test_ctrl_ff[55:48] <= mmio_wdat[262];
            if (mmio_we[263]) rt_test_ctrl_ff[63:56] <= mmio_wdat[263];
        end

        // ═══════════════════════════════════════════════════════════════════
        //  HW write path – Error Log 0 ROS capture  [UCIe §9.5.34]
        //  Shift: N-2 ← N-1 ← N ← new state
        // ═══════════════════════════════════════════════════════════════════
        if (err_capture_en) begin
            error_log0_ff[31:24] <= error_log0_ff[23:16]; // State N-2
            error_log0_ff[23:16] <= error_log0_ff[7:0];   // State N-1
            error_log0_ff[7:0]   <= err_state_capture;   // State N (current)
            error_log0_ff[8]     <= phy_lane_rev_err_log_i;         // Lane Reversal at error
            error_log0_ff[9]     <= phy_width_degrade_err_log_i;                 // Width Degrade (not modelled)
            // Error Log 1 [7:0] – State N-3: shift from Error Log 0's old N-2
            error_log1_ff[7:0]   <= error_log0_ff[31:24]; // State N-3
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
            for (int i=0; i<8; i++) begin
                if (i < 4 || rf_is_64b_access) begin
                    rf_rdata[i*8 +: 8] <= ((int'(rf_addr[11:0]) + i) <= 35) ? cfg_mem[int'(rf_addr[11:0]) + i] : 8'h0;
                end else begin
                    rf_rdata[i*8 +: 8] <= 8'h0;
                end
            end
        end else if (phy_mmio_sel) begin
            for (int i=0; i<8; i++) begin
                if (i < 4 || rf_is_64b_access) begin
                    rf_rdata[i*8 +: 8] <= ((int'(rf_addr[12:0]) - 32'h1000 + i) <= 267) ? mmio_mem[int'(rf_addr[12:0]) - 32'h1000 + i] : 8'h0;
                end else begin
                    rf_rdata[i*8 +: 8] <= 8'h0;
                end
            end
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
