rtl/common/UCIe_pkg.sv
# Packages
rtl/SideBand/common/sb_pkg.sv
rtl/SideBand/common/msg_codec_pkg.sv

# Common Utilities
rtl/common/FIFO/fifo_mem.sv
rtl/common/FIFO/fifo_rptr_empty.sv
rtl/common/FIFO/fifo_sync_2ff.sv
rtl/common/FIFO/fifo_wptr_full.sv
rtl/common/FIFO/fifo.sv

# DUT
rtl/SideBand/common/sb_demux.sv
rtl/SideBand/common/sb_priority_arbiter.sv

# SerDes
rtl/SideBand/analog_modeling/sb_serializer/sb_serializer.sv
rtl/SideBand/analog_modeling/sb_deserializer/sb_deserializer.sv
rtl/SideBand/analog_modeling/sb_serializer/sb_serializer_sva.sv
rtl/SideBand/analog_modeling/sb_deserializer/sb_deserializer_sva.sv

# Link Controller
rtl/SideBand/Link_Controller/sb_mapper.sv
rtl/SideBand/Link_Controller/sb_demapper.sv
rtl/SideBand/Link_Controller/Link_Demux.sv
rtl/SideBand/Link_Controller/sb_pattern_detector.sv
rtl/SideBand/Link_Controller/sb_pattern_engine.sv
rtl/SideBand/Link_Controller/Link_Controller.sv

# Training Management
rtl/SideBand/Training_mgmt/roud_robin_arbiter.sv
rtl/SideBand/Training_mgmt/Packetizer.sv
rtl/SideBand/Training_mgmt/DePacketizer.sv
rtl/SideBand/Training_mgmt/Training_Mgmt_Demux.sv
rtl/SideBand/Training_mgmt/Training_Mgmt.sv

# RDI Controller
rtl/SideBand/rdi_controller/credit_counter.sv
rtl/SideBand/rdi_controller/rdi_aggregator.sv
rtl/SideBand/rdi_controller/rdi_de_aggregator.sv
rtl/SideBand/rdi_controller/rdi_router.sv
rtl/SideBand/rdi_controller/rdi_comp_req_decoder.sv
rtl/SideBand/rdi_controller/RDI_control.sv

# Reg Access
rtl/SideBand/Reg_Access/Completion_gen.sv
rtl/SideBand/Reg_Access/Reg_DePacketizer.sv
rtl/SideBand/Reg_Access/Reg_Access_FSM.sv
rtl/SideBand/Reg_Access/Reg_Access.sv

# Top
rtl/SideBand/top/SideBand_Top.sv

# TB
tb/integration/SideBand_Top/SideBand_Top_tb.sv

rtl/common/CLK_GATE.sv
