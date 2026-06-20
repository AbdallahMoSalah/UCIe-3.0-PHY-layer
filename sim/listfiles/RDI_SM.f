// ============================================================
// RDI_SM Integration Testbench Filelist
// ============================================================

// Include Directories (for `include / package search paths)
+incdir+rtl/common
+incdir+rtl/MainSM/common
+incdir+rtl/MainSM/RDI_SM/common

// Packages
rtl/common/UCIe_pkg.sv
rtl/MainSM/common/LTSM_state_pkg.sv
rtl/MainSM/RDI_SM/common/RDI_SM_pkg.sv

// ---- wrapper_sm sub-modules ----
rtl/MainSM/RDI_SM/unit_Timer/unit_Timer.sv
rtl/MainSM/RDI_SM/unit_reset_state/unit_reset_state.sv
rtl/MainSM/RDI_SM/unit_active_state/unit_active_state.sv
rtl/MainSM/RDI_SM/unit_active_pmnak_state/unit_active_pmnak_state.sv
rtl/MainSM/RDI_SM/unit_retrain_state/unit_retrain_state.sv
rtl/MainSM/RDI_SM/unit_L1_state/unit_L1_state.sv
rtl/MainSM/RDI_SM/unit_L2_state/unit_L2_state.sv
rtl/MainSM/RDI_SM/unit_linkreset_state/unit_linkreset_state.sv
rtl/MainSM/RDI_SM/unit_linkerror_state/unit_linkerror_state.sv
rtl/MainSM/RDI_SM/unit_disabled_state/unit_disabled_state.sv
rtl/MainSM/RDI_SM/unit_main_controller/unit_main_controller.sv
rtl/MainSM/RDI_SM/unit_message_send_MUX/unit_message_send_MUX.sv
rtl/MainSM/RDI_SM/message_timeout_handler/message_timeout_handler.sv
rtl/MainSM/RDI_SM/wrapper_sm/wrapper_sm.sv

// ---- wrapper_handshake_logic sub-modules ----
rtl/MainSM/RDI_SM/unit_clk_handshake/unit_clk_handshake.sv
rtl/MainSM/RDI_SM/unit_awak_handshake/unit_awak_handshake.sv
rtl/MainSM/RDI_SM/unit_stall_handshake/unit_stall_handshake.sv
rtl/MainSM/RDI_SM/unit_active_handshake/unit_Active_handshake.sv
rtl/MainSM/RDI_SM/wrapper_handshake_logic/wrapper_handshake_logic.sv

// ---- Remaining RDI_SM sub-modules ----
rtl/MainSM/RDI_SM/unit_gating_logic/unit_gating_logic.sv
rtl/MainSM/RDI_SM/unit_signal_transition_detector/unit_signal_transition_detector.sv
rtl/MainSM/RDI_SM/unit_status_decoder/unit_status_decoder.sv
rtl/MainSM/RDI_SM/unit_msg_handler/unit_msg_handler.sv

// ---- RDI_SM Top-level ----
rtl/MainSM/RDI_SM/RDI_SM/RDI_SM.sv

// ---- Testbench ----
tb/integration/RDI_SM/RDI_SM_checker.sv
tb/integration/RDI_SM/RDI_SM_tb.sv
