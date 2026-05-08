# ============================================================
# Link Initialization (linkinit) Unit Testbench Filelist
# ============================================================

# Include directories
+incdir+rtl/MainSM/RDI_SM/common

# Packages
rtl/MainSM/RDI_SM/common/RDI_SM_pkg.sv

# Dependencies
rtl/MainSM/LTSM/Common/TimeOut_counter.sv

# DUT
rtl/MainSM/LTSM/LINKINIT/linkinit.sv

# Testbench
tb/unit/MainSM/LTSM/LINKINIT/linkinit_tb.sv
