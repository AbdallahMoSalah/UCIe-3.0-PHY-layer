// ===========================================================================
//  Reg_Access  (Top-level wrapper)
//  UCIe Sideband Register-Access Block – Chapter 9
//
//  Instantiates and wires together:
//    1. Reg_DePacketizer  – breaks the 128-bit SB packet into control/datapath
//    2. Reg_Access_FSM    – sequences DECODE → EXECUTE → GEN
//    3. Reg_File          – register storage, read/write logic
//    4. Completion_gen    – builds the SB completion packet
//
//  ─── External Interfaces ────────────────────────────────────────────────
//    • SB RX side  : pkt_in / pkt_vld / reg_vld / reg_rdy
//    • SB TX side  : completion_msg / completion_vld / completion_rdy
//    • PHY context : phy_in_reset
//    • All Reg_File HW inputs/outputs are passed through transparently
// ===========================================================================

module Reg_Access
    import sb_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // -----------------------------------------------------------------------
    // SB RX interface (from Link_Demux / RDI control)
    // -----------------------------------------------------------------------
    input  logic [127:0] pkt_in,           // Incoming 128-bit SB packet
    input  logic         pkt_vld,          // Packet is latched/valid
    input  logic         reg_vld,          // Handshake: new request available
    output logic         reg_rdy,          // Handshake: block is ready

    // -----------------------------------------------------------------------
    // PHY context
    // -----------------------------------------------------------------------
    input  logic         phy_in_reset,     // 1 during Link/Soft Reset → UR all reqs

    // -----------------------------------------------------------------------
    // SB TX interface (to Link_Controller TX arbiter)
    // -----------------------------------------------------------------------
    output logic [127:0] completion_msg,   // Completion SB packet
    output logic         completion_vld,   // Completion valid
    input  logic         completion_rdy,   // TX arbiter ready

    // =======================================================================
    //  HW INPUTS passed through to Reg_File
    //  (see Reg_File.sv for full documentation of every port)
    // =======================================================================

    // --- Config Space: UCIe Link Capability (00Ch) --------------------------
    input  logic         adapter_raw_format_support_cap_i,
    input  logic [2:0]   hw_max_link_width_cap_i,
    input  logic [3:0]   hw_max_link_speed_cap_i,
    input  logic         adapter_multi_protocol_cap_i,
    input  logic         phy_advanced_pkg_cap_i,
    input  logic         adapter_68B_flit_formate_streaming_cap_i,
    input  logic         adapter_256B_end_header_flit_format_streaming_cap_i,
    input  logic         adapter_256B_start_header_flit_format_streaming_cap_i,
    input  logic         adapter_256B_latency_optimized_flit_format_without_optional_bytes_streaming_cap_i,
    input  logic         adapter_256B_latency_optimized_flit_format_with_optional_bytes_streaming_cap_i,
    input  logic         adapter_enhanced_multi_protocol_capable_cap_i,
    input  logic         adapter_standard_start_header_flit_for_pcie_protocol_cap_i,
    input  logic         adapter_latency_optimized_flit_with_optional_bytes_for_pcie_protocol_cap_i,
    input  logic         adapter_runtime_link_testing_parity_feature_error_signaling_cap_i,
    input  logic         hw_apmw_cap_i,
    input  logic         hw_spmw_cap_i,
    input  logic         phy_sideband_performant_mode_operation_cap_i,
    input  logic         phy_priority_sideband_packet_transfer_cap_i,
    input  logic         phy_l2_sideband_power_down_cap_i,

    // --- Config Space: UCIe Link Status (014h) – RW1C/RW1CS set paths ------
    input  logic         adapter_raw_format_enabled_status_i,
    input  logic         adapter_multi_protocol_enabled_status_i,
    input  logic         adapter_enhanced_multi_protocol_enabled_status_i,
    input  logic         phy_x32_advanced_package_module_enabled_status_i,
    input  logic [3:0]   phy_link_width_enabled_status_i,
    input  logic [3:0]   phy_link_speed_enabled_status_i,
    input  logic         phy_link_status_status_i,
    input  logic         phy_link_training_retraining_status_i,
    input  logic         phy_link_status_changed_status_i,
    input  logic         phy_bw_changed_status_i,
    input  logic         phy_uci_e_link_correctable_error_i,
    input  logic         phy_uci_e_link_uncorrectable_non_fatal_error_i,
    input  logic         phy_uci_e_link_uncorrectable_fatal_error_i,
    input  logic [3:0]   adapter_flit_format_status_i,
    input  logic         phy_sideband_performant_mode_operation_status_i,
    input  logic         phy_priority_sideband_packet_transfer_status_i,
    input  logic         phy_l2_sideband_power_down_status_i,

    // --- Config Space: Link Event Notification Control (018h) ---------------
    input  logic [4:0]   link_event_notification_interrupt_number_i,

    // --- MMIO: PHY Capability (1000h) – HWInit bits -------------------------
    input  logic         phy_term_link_cap_i,
    input  logic         phy_tx_eq_status_iualization_support_cap_i,
    input  logic [4:0]   phy_tx_vswing_encodings_cap_i,
    input  logic [1:0]   phy_rx_clk_mode_support_cap_i,
    input  logic [1:0]   phy_rx_clk_phase_support_cap_i,
    input  logic         phy_package_type_cap_i,
    input  logic         phy_tcm_support_cap_i,
    input  logic         phy_tarr_support_cap_i,

    // --- MMIO: PHY Status (1008h) – RO live fields --------------------------
    input  logic         phy_rx_term_status_i,
    input  logic         phy_tx_eq_status_i,
    input  logic         phy_clk_mode_status_i,
    input  logic         phy_clk_phase_status_i,
    input  logic         phy_lane_rev_status_i,
    input  logic [5:0]   phy_iq_correction_param_status_i,
    input  logic [3:0]   phy_eq_preset_setting_status_i,
    input  logic         phy_tarr_status_i,

    // --- MMIO: Error Log 0 (1080h) – ROS capture ---------------------------
    input  logic [7:0]   err_state_capture,
    input  logic         phy_lane_rev_err_log_i,
    input  logic         phy_width_degrade_err_log_i,
    input  logic         err_capture_en,

    // --- MMIO: Error Log 1 (1090h) – RW1CS set paths -----------------------
    input  logic         phy_state_timeout_i,
    input  logic         phy_sb_timeout_i,
    input  logic         phy_rm_link_err_i,
    input  logic         phy_internal_err_i,

    // --- MMIO: Runtime Link Test Status (1108h) – RO live field ------------
    input  logic         rt_link_busy_status_i,

    // =======================================================================
    //  RDI SM interface  (outputs from Reg_File)
    // =======================================================================
    output logic [3:0]   phy_max_link_speed_cap_out,
    output logic [3:0]   phy_link_width_enabled_status_out,
    output logic [3:0]   phy_link_speed_enabled_status_out,

    // =======================================================================
    //  LTSM interface  (outputs from Reg_File)
    // =======================================================================
    output logic [3:0]   phy_target_link_width_ctrl_out,
    output logic [3:0]   phy_target_link_speed_ctrl_out,
    output logic         phy_start_ucie_link_training_ctrl_out,
    output logic         phy_retrain_ucie_link_ctrl_out,
    output logic         phy_pmo_ctrl_out,
    output logic         phy_pspt_ctrl_out,
    output logic         phy_l2spd_ctrl_out,

    output logic         phy_rx_term_status_i_ctrl_out,
    output logic         phy_tx_eq_status_i_en_ctrl_out,
    output logic         phy_rx_clk_mode_ctrl_out,
    output logic         phy_rx_clk_phase_ctrl_out,
    output logic         phy_x8_width_mode_ctrl_out,
    output logic         phy_iq_correction_en_ctrl_out,
    output logic [5:0]   phy_iq_correction_param_ctrl_out,
    output logic         phy_tx_eq_status_i_preset_ctrl_out,
    output logic [3:0]   phy_tx_eq_status_i_preset_setting_ctrl_out,
    output logic         phy_tarr_en_ctrl_out,

    output logic [2:0]   phy_init_ctrl_out,
    output logic         phy_resume_training_ctrl_out,

    output logic [63:0]  lane_mask_ctrl_out,
    output logic [11:0]  max_error_threshold_in_per_lane_comparison_out,
    output logic [15:0]  max_error_threshold_in_aggregate_comparison_out,
    output logic [15:0]  idle_count_out,
    output logic [15:0]  iterations_out,
    output logic [15:0]  current_lane_map_module_0_enable_out,

    // =======================================================================
    //  Convenience register taps  (outputs from Reg_File)
    // =======================================================================
    output logic [31:0]  ucie_link_cap_r_out,
    output logic [31:0]  ucie_link_ctrl_r_out,
    output logic [31:0]  ucie_link_status_r_out,
    output logic [15:0]  link_event_notif_ctrl_r_out,
    output logic [15:0]  error_notif_ctrl_r_out,
    output logic [31:0]  phy_cap_r_out,
    output logic [31:0]  phy_control_r_out,
    output logic [31:0]  phy_status_r_out,
    output logic [31:0]  phy_init_debug_r_out,
    output logic [31:0]  training_setup1_r_out,
    output logic [31:0]  training_setup2_r_out,
    output logic [63:0]  training_setup3_r_out,
    output logic [31:0]  training_setup4_r_out,
    output logic [63:0]  lane_map_mod0_r_out,
    output logic [31:0]  error_log0_r_out,
    output logic [31:0]  error_log1_r_out,
    output logic [63:0]  rt_test_ctrl_r_out,
    output logic [31:0]  rt_test_status_r_out
);

// ===========================================================================
//  Internal wires connecting sub-modules
// ===========================================================================

// DePacketizer → FSM
sb_opcode_e  opcode_w;
logic        parity_err_w;
logic        ep_w;
logic        false_msg_w;

// DePacketizer → Reg_File
logic [24:0] rf_addr_w;
logic [7:0]  rf_be_w;
logic        rf_is_64b_access_w;
logic [63:0] rf_wdata_w;

// DePacketizer → Completion_gen
logic [63:0] orig_hdr_w;

// FSM → Reg_File
logic        rd_en_w;
logic        wr_en_w;

// Reg_File → FSM + Completion_gen
logic [63:0] rf_rdata_w;
logic        rdata_vld_w;

// Reg_File → FSM (addr error, forwarded to status)
logic        addr_err_w;

// FSM → Completion_gen
logic [2:0]  status_w;
logic        completion_start_w;

// ===========================================================================
//  1. Reg_DePacketizer
// ===========================================================================
Reg_DePacketizer u_depacketizer (
    .clk             (clk),
    .rst_n           (rst_n),
    // Packet input
    .pkt_in          (pkt_in),
    .pkt_vld         (pkt_vld),
    // Control → FSM
    .opcode          (opcode_w),
    .parity_err      (parity_err_w),
    .ep              (ep_w),
    .false_msg       (false_msg_w),
    // Datapath → Reg_File
    .rf_addr         (rf_addr_w),
    .rf_be           (rf_be_w),
    .rf_is_64b_access(rf_is_64b_access_w),
    .rf_wdata        (rf_wdata_w),
    // Raw header → Completion_gen
    .Original_Header (orig_hdr_w)
);

// ===========================================================================
//  2. Reg_Access_FSM
//     The FSM sees addr_err from Reg_File as an additional error flag.
//     We OR it into parity_err input (or pass false_msg – using parity_err
//     since addr_err is a decode-time error).  In practice the FSM evaluates
//     error in DECODE state before rd_en/wr_en are issued; addr_err is only
//     valid during EXECUTE.  We feed it into the FSM's `ep` so that if the
//     register file asserts addr_err the completion transitions to UR.
// ===========================================================================
Reg_Access_FSM u_fsm (
    .clk             (clk),
    .rst_n           (rst_n),
    .phy_in_reset    (phy_in_reset),
    // Handshake
    .reg_vld         (reg_vld),
    .reg_rdy         (reg_rdy),
    .completion_rdy  (completion_rdy),
    // From DePacketizer
    .opcode          (opcode_w),
    .parity_err      (parity_err_w),
    .ep              (ep_w | addr_err_w),   // merge addr decode error
    .false_msg       (false_msg_w),
    // To/From Reg_File
    .rd_en           (rd_en_w),
    .wr_en           (wr_en_w),
    .rdata_vld       (rdata_vld_w),
    // To Completion_gen
    .status          (status_w),
    .completion_start(completion_start_w)
);

// ===========================================================================
//  3. Reg_File
// ===========================================================================
Reg_File u_reg_file (
    .clk                        (clk),
    .rst_n                      (rst_n),
    // Register-access interface
    .rf_addr                    (rf_addr_w),
    .rf_be                      (rf_be_w),
    .rf_is_64b_access           (rf_is_64b_access_w),
    .rf_wdata                   (rf_wdata_w),
    .rd_en                      (rd_en_w),
    .wr_en                      (wr_en_w),
    .rf_rdata                   (rf_rdata_w),
    .rdata_vld                  (rdata_vld_w),
    .addr_err_o                 (addr_err_w),
    // HW inputs – Link Capability
    .adapter_raw_format_support_cap_i                                       (adapter_raw_format_support_cap_i),
    .hw_max_link_width_cap_i                                                (hw_max_link_width_cap_i),
    .hw_max_link_speed_cap_i                                                (hw_max_link_speed_cap_i),
    .adapter_multi_protocol_cap_i                                           (adapter_multi_protocol_cap_i),
    .phy_advanced_pkg_cap_i                                                 (phy_advanced_pkg_cap_i),
    .adapter_68B_flit_formate_streaming_cap_i                               (adapter_68B_flit_formate_streaming_cap_i),
    .adapter_256B_end_header_flit_format_streaming_cap_i                    (adapter_256B_end_header_flit_format_streaming_cap_i),
    .adapter_256B_start_header_flit_format_streaming_cap_i                  (adapter_256B_start_header_flit_format_streaming_cap_i),
    .adapter_256B_latency_optimized_flit_format_without_optional_bytes_streaming_cap_i (adapter_256B_latency_optimized_flit_format_without_optional_bytes_streaming_cap_i),
    .adapter_256B_latency_optimized_flit_format_with_optional_bytes_streaming_cap_i    (adapter_256B_latency_optimized_flit_format_with_optional_bytes_streaming_cap_i),
    .adapter_enhanced_multi_protocol_capable_cap_i                          (adapter_enhanced_multi_protocol_capable_cap_i),
    .adapter_standard_start_header_flit_for_pcie_protocol_cap_i             (adapter_standard_start_header_flit_for_pcie_protocol_cap_i),
    .adapter_latency_optimized_flit_with_optional_bytes_for_pcie_protocol_cap_i (adapter_latency_optimized_flit_with_optional_bytes_for_pcie_protocol_cap_i),
    .adapter_runtime_link_testing_parity_feature_error_signaling_cap_i      (adapter_runtime_link_testing_parity_feature_error_signaling_cap_i),
    .hw_apmw_cap_i                                                          (hw_apmw_cap_i),
    .hw_spmw_cap_i                                                          (hw_spmw_cap_i),
    .phy_sideband_performant_mode_operation_cap_i                            (phy_sideband_performant_mode_operation_cap_i),
    .phy_priority_sideband_packet_transfer_cap_i                             (phy_priority_sideband_packet_transfer_cap_i),
    .phy_l2_sideband_power_down_cap_i                                        (phy_l2_sideband_power_down_cap_i),
    // HW inputs – Link Status
    .adapter_raw_format_enabled_status_i                                    (adapter_raw_format_enabled_status_i),
    .adapter_multi_protocol_enabled_status_i                                (adapter_multi_protocol_enabled_status_i),
    .adapter_enhanced_multi_protocol_enabled_status_i                       (adapter_enhanced_multi_protocol_enabled_status_i),
    .phy_x32_advanced_package_module_enabled_status_i                       (phy_x32_advanced_package_module_enabled_status_i),
    .phy_link_width_enabled_status_i                                        (phy_link_width_enabled_status_i),
    .phy_link_speed_enabled_status_i                                        (phy_link_speed_enabled_status_i),
    .phy_link_status_status_i                                               (phy_link_status_status_i),
    .phy_link_training_retraining_status_i                                  (phy_link_training_retraining_status_i),
    .phy_link_status_changed_status_i                                       (phy_link_status_changed_status_i),
    .phy_bw_changed_status_i                                                (phy_bw_changed_status_i),
    .phy_uci_e_link_correctable_error_i                                     (phy_uci_e_link_correctable_error_i),
    .phy_uci_e_link_uncorrectable_non_fatal_error_i                         (phy_uci_e_link_uncorrectable_non_fatal_error_i),
    .phy_uci_e_link_uncorrectable_fatal_error_i                             (phy_uci_e_link_uncorrectable_fatal_error_i),
    .adapter_flit_format_status_i                                           (adapter_flit_format_status_i),
    .phy_sideband_performant_mode_operation_status_i                         (phy_sideband_performant_mode_operation_status_i),
    .phy_priority_sideband_packet_transfer_status_i                          (phy_priority_sideband_packet_transfer_status_i),
    .phy_l2_sideband_power_down_status_i                                     (phy_l2_sideband_power_down_status_i),
    // HW inputs – Link Event Notif Ctrl
    .link_event_notification_interrupt_number_i                             (link_event_notification_interrupt_number_i),
    // HW inputs – PHY Capability
    .phy_term_link_cap_i                                                    (phy_term_link_cap_i),
    .phy_tx_eq_status_iualization_support_cap_i                             (phy_tx_eq_status_iualization_support_cap_i),
    .phy_tx_vswing_encodings_cap_i                                          (phy_tx_vswing_encodings_cap_i),
    .phy_rx_clk_mode_support_cap_i                                          (phy_rx_clk_mode_support_cap_i),
    .phy_rx_clk_phase_support_cap_i                                         (phy_rx_clk_phase_support_cap_i),
    .phy_package_type_cap_i                                                 (phy_package_type_cap_i),
    .phy_tcm_support_cap_i                                                  (phy_tcm_support_cap_i),
    .phy_tarr_support_cap_i                                                 (phy_tarr_support_cap_i),
    // HW inputs – PHY Status
    .phy_rx_term_status_i                                                   (phy_rx_term_status_i),
    .phy_tx_eq_status_i                                                     (phy_tx_eq_status_i),
    .phy_clk_mode_status_i                                                  (phy_clk_mode_status_i),
    .phy_clk_phase_status_i                                                 (phy_clk_phase_status_i),
    .phy_lane_rev_status_i                                                  (phy_lane_rev_status_i),
    .phy_iq_correction_param_status_i                                       (phy_iq_correction_param_status_i),
    .phy_eq_preset_setting_status_i                                         (phy_eq_preset_setting_status_i),
    .phy_tarr_status_i                                                      (phy_tarr_status_i),
    // HW inputs – Error Log 0
    .err_state_capture                                                      (err_state_capture),
    .phy_lane_rev_err_log_i                                                 (phy_lane_rev_err_log_i),
    .phy_width_degrade_err_log_i                                            (phy_width_degrade_err_log_i),
    .err_capture_en                                                         (err_capture_en),
    // HW inputs – Error Log 1
    .phy_state_timeout_i                                                    (phy_state_timeout_i),
    .phy_sb_timeout_i                                                       (phy_sb_timeout_i),
    .phy_rm_link_err_i                                                      (phy_rm_link_err_i),
    .phy_internal_err_i                                                     (phy_internal_err_i),
    // HW inputs – RT Link Test Status
    .rt_link_busy_status_i                                                  (rt_link_busy_status_i),
    // RDI SM outputs
    .phy_max_link_speed_cap_out                                             (phy_max_link_speed_cap_out),
    .phy_link_width_enabled_status_out                                      (phy_link_width_enabled_status_out),
    .phy_link_speed_enabled_status_out                                      (phy_link_speed_enabled_status_out),
    // LTSM outputs
    .phy_target_link_width_ctrl_out                                         (phy_target_link_width_ctrl_out),
    .phy_target_link_speed_ctrl_out                                         (phy_target_link_speed_ctrl_out),
    .phy_start_ucie_link_training_ctrl_out                                  (phy_start_ucie_link_training_ctrl_out),
    .phy_retrain_ucie_link_ctrl_out                                         (phy_retrain_ucie_link_ctrl_out),
    .phy_pmo_ctrl_out                                                       (phy_pmo_ctrl_out),
    .phy_pspt_ctrl_out                                                      (phy_pspt_ctrl_out),
    .phy_l2spd_ctrl_out                                                     (phy_l2spd_ctrl_out),
    .phy_rx_term_status_i_ctrl_out                                          (phy_rx_term_status_i_ctrl_out),
    .phy_tx_eq_status_i_en_ctrl_out                                         (phy_tx_eq_status_i_en_ctrl_out),
    .phy_rx_clk_mode_ctrl_out                                               (phy_rx_clk_mode_ctrl_out),
    .phy_rx_clk_phase_ctrl_out                                              (phy_rx_clk_phase_ctrl_out),
    .phy_x8_width_mode_ctrl_out                                             (phy_x8_width_mode_ctrl_out),
    .phy_iq_correction_en_ctrl_out                                          (phy_iq_correction_en_ctrl_out),
    .phy_iq_correction_param_ctrl_out                                       (phy_iq_correction_param_ctrl_out),
    .phy_tx_eq_status_i_preset_ctrl_out                                     (phy_tx_eq_status_i_preset_ctrl_out),
    .phy_tx_eq_status_i_preset_setting_ctrl_out                             (phy_tx_eq_status_i_preset_setting_ctrl_out),
    .phy_tarr_en_ctrl_out                                                   (phy_tarr_en_ctrl_out),
    .phy_init_ctrl_out                                                      (phy_init_ctrl_out),
    .phy_resume_training_ctrl_out                                           (phy_resume_training_ctrl_out),
    .lane_mask_ctrl_out                                                     (lane_mask_ctrl_out),
    .max_error_threshold_in_per_lane_comparison_out                         (max_error_threshold_in_per_lane_comparison_out),
    .max_error_threshold_in_aggregate_comparison_out                        (max_error_threshold_in_aggregate_comparison_out),
    .idle_count_out                                                         (idle_count_out),
    .iterations_out                                                         (iterations_out),
    .current_lane_map_module_0_enable_out                                   (current_lane_map_module_0_enable_out),
    // Convenience taps
    .ucie_link_cap_r_out                                                    (ucie_link_cap_r_out),
    .ucie_link_ctrl_r_out                                                   (ucie_link_ctrl_r_out),
    .ucie_link_status_r_out                                                 (ucie_link_status_r_out),
    .link_event_notif_ctrl_r_out                                            (link_event_notif_ctrl_r_out),
    .error_notif_ctrl_r_out                                                 (error_notif_ctrl_r_out),
    .phy_cap_r_out                                                          (phy_cap_r_out),
    .phy_control_r_out                                                      (phy_control_r_out),
    .phy_status_r_out                                                       (phy_status_r_out),
    .phy_init_debug_r_out                                                   (phy_init_debug_r_out),
    .training_setup1_r_out                                                  (training_setup1_r_out),
    .training_setup2_r_out                                                  (training_setup2_r_out),
    .training_setup3_r_out                                                  (training_setup3_r_out),
    .training_setup4_r_out                                                  (training_setup4_r_out),
    .lane_map_mod0_r_out                                                    (lane_map_mod0_r_out),
    .error_log0_r_out                                                       (error_log0_r_out),
    .error_log1_r_out                                                       (error_log1_r_out),
    .rt_test_ctrl_r_out                                                     (rt_test_ctrl_r_out),
    .rt_test_status_r_out                                                   (rt_test_status_r_out)
);

// ===========================================================================
//  4. Completion_gen
// ===========================================================================
Completion_gen u_completion_gen (
    .clk             (clk),
    .rst_n           (rst_n),
    // From FSM
    .completion_start(completion_start_w),
    .status          (status_w),
    // From DePacketizer
    .Original_Header (orig_hdr_w),
    // From Reg_File
    .rf_rdata        (rf_rdata_w),
    .rdata_vld       (rdata_vld_w),
    // To TX arbiter
    .completion_msg  (completion_msg),
    .completion_vld  (completion_vld),
    .completion_rdy  (completion_rdy)
);

endmodule
