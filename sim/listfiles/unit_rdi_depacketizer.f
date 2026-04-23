# Include directories
+incdir+rtl/common
+incdir+rtl/SideBand/common
+incdir+rtl/SideBand/Training_mgmt

# Packages (لو فيه)
rtl/SideBand/common/sb_pkg.sv
rtl/SideBand/common/msg_codec_pkg.sv
tb/unit/sideband/rdi_depacketizer/RDI_DePacketizer_tb_pkg.sv

# DUT
rtl/SideBand/Training_mgmt/RDI_DePacketizer.sv

# Testbench
tb/unit/sideband/rdi_depacketizer/RDI_DePacketizer_tb.sv
