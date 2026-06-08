# Packages & Enums
rtl/common/UCIe_pkg.sv
rtl/MainSM/LTSM/common/ltsm_state_n_pkg.sv
rtl/MainSM/common/LTSM_state_pkg.sv

# Common training decoders
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/MBTRAIN/common/unit_negotiated_speed.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/MBTRAIN/common/unit_negotiated_lanes.sv

# D2C PT sub-modules (local and partner for both TX and RX)
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_local.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_partner.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_local.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_partner.sv

# D2C PT wrappers & sweeps
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_local.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_partner.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_top.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/unit_D2C_sweep.sv

# DUT
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/MBTRAIN/unit_REPAIR.sv

# Testbench Support & Interfaces
./../target_implementation_technique/new_version_implementation/tb/unit/MainSM/LTSM/common/ltsm_tb_if.sv
./../target_implementation_technique/new_version_implementation/tb/unit/MainSM/LTSM/common/ltsm_tb_attachments.sv

# Testbench
./../target_implementation_technique/new_version_implementation/tb/unit/MainSM/LTSM/MBTRAIN/unit_REPAIR_tb.sv
