# Include directories
+incdir+rtl/common
+incdir+rtl/MainSM/RDI_SM/common
+incdir+rtl/MainSM/LTSM/Common

# Packages (dependencies first)
rtl/common/UCIe_pkg.sv
rtl/MainSM/RDI_SM/common/RDI_SM_pkg.sv
rtl/MainSM/LTSM/Common/ltsm_state_n_pkg.sv
rtl/MainSM/common/LTSM_state_pkg.sv
rtl/MainSM/LTSM/Common/internal_ltsm_if.sv

# Common Sub-components
rtl/MainSM/LTSM/Common/TimeOut_counter.sv

# RESET state submodule
rtl/MainSM/LTSM/RESET.sv

# SBINIT state submodule
rtl/MainSM/LTSM/SBINIT.sv

# MBINIT FSMs and controller
rtl/MainSM/LTSM/MBINIT/MBINIT_PARAM.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_CAL.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRCLK.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRVAL.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REVERSALMB.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRMB.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_controller.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_WRAPPER.sv
rtl/MainSM/LTSM/MBINIT/MBINIT.sv

# MBTRAIN FSMs and controller (unimplemented/commented out)
#rtl/MainSM/LTSM/MBTRAIN/unit_MBTRAIN_ctrl.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_VALVREF.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_DATAVREF.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_SPEEDIDLE.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_TXSELFCAL.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_RXCLKCAL.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_VALTRAINCENTER.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_VALTRAINVREF.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_DATATRAINCENTER1.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_DATATRAINVREF.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_RXDESKEW/unit_phase_interpolator_for_deskew.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_RXDESKEW/unit_RXDESKEW.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_DATATRAINCENTER2.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_LINKSPEED.sv
#rtl/MainSM/LTSM/MBTRAIN/unit_REPAIR.sv

# Shared D2C Test Modules
rtl/MainSM/LTSM/D2C_PT/unit_TX_D2C_PT.sv
rtl/MainSM/LTSM/D2C_PT/unit_RX_D2C_PT.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT.sv

# MBTRAIN wrapper (unimplemented/commented out)
#rtl/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN.sv

# LINKINIT state submodule
rtl/MainSM/LTSM/LINKINIT/linkinit.sv

# ACTIVE state submodule
rtl/MainSM/LTSM/ACTIVE.sv

# Controller and Wrapper Top DUTs
rtl/MainSM/LTSM/ltsm_controller.sv
rtl/MainSM/LTSM/ltsm_wrapper.sv
