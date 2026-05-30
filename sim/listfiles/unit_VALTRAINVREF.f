# Core packages and interfaces
rtl/common/UCIe_pkg.sv
rtl/MainSM/common/LTSM_state_pkg.sv
rtl/MainSM/LTSM/common/ltsm_state_n_pkg.sv
rtl/MainSM/LTSM/common/internal_ltsm_if.sv

# D2C sub-unit files (TX/RX local and partner)
rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_partner.sv

# D2C wrapper modules (local, partner, and top)
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_top.sv

# Design Under Test (DUT)
rtl/MainSM/LTSM/MBTRAIN/common/unit_val_sweep.sv
rtl/MainSM/LTSM/MBTRAIN/unit_VALTRAINVREF.sv

# Testbench attachments and verification logic
tb/unit/MainSM/LTSM/common/ltsm_tb_attachments.sv

# Main unit testbench
tb/unit/MainSM/LTSM/MBTRAIN/unit_VALTRAINVREF_tb.sv
