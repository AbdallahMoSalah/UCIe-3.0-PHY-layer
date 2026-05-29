# Packages (relative to UCIe-3.0-PHY-layer/)
rtl/common/UCIe_pkg.sv
rtl/MainSM/LTSM/common/ltsm_state_n_pkg.sv

# DUT — D2C_PT sub-modules (local and partner for both TX and RX)
rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_partner.sv

# DUT — Wrappers (local and partner)
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_partner.sv

# DUT — Top-level wrapper (the new module under test)
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_top.sv

# Testbench
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_top_tb.sv
