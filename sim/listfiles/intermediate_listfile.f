# Packages (relative to UCIe-3.0-PHY-layer/)
rtl/common/UCIe_pkg.sv
rtl/MainSM/LTSM/common/ltsm_state_n_pkg.sv

# DUT — D2C_PT sub-modules (local and partner for both TX and RX)
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_local.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_partner.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_local.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_partner.sv

# DUT — Wrappers
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_local.sv
./../target_implementation_technique/new_version_implementation/rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_partner.sv

# Testbench
./../target_implementation_technique/new_version_implementation/tb/unit/MainSM/LTSM/D2C_PT/wrapper_D2C_PT_tb.sv
