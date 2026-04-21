// Packages and Include Directories
+incdir+rtl/common
+incdir+rtl/MainSM/common
+incdir+rtl/MainSM/RDI_SM/common

rtl/common/UCIe_pkg.sv
rtl/MainSM/common/LTSM_state_pkg.sv
rtl/MainSM/RDI_SM/common/RDI_SM_pkg.sv

// RDI SM Sub-modules
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

// RDI SM Top-level Logic
rtl/MainSM/RDI_SM/unit_main_controller/unit_main_controller.sv
rtl/MainSM/RDI_SM/unit_message_send_MUX/unit_message_send_MUX.sv
rtl/MainSM/RDI_SM/wrapper_sm/wrapper_sm.sv

// Testbench
tb/wrapper/wrapper_sm/wrapper_sm_tb.sv