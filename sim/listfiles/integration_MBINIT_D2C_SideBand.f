# UCIe package
rtl/common/UCIe_pkg.sv

# Sideband packages
rtl/SideBand/common/sb_pkg.sv
rtl/SideBand/common/msg_codec_pkg.sv

# Common utilities & FIFO
rtl/common/FIFO/fifo_mem.sv
rtl/common/FIFO/fifo_rptr_empty.sv
rtl/common/FIFO/fifo_sync_2ff.sv
rtl/common/FIFO/fifo_wptr_full.sv
rtl/common/FIFO/fifo.sv
rtl/common/CLK_GATE.sv

# Sideband modules
rtl/SideBand/common/sb_demux.sv
rtl/SideBand/common/sb_priority_arbiter.sv

# SerDes (analog models)
rtl/SideBand/analog_modeling/sb_serializer/sb_serializer.sv
rtl/SideBand/analog_modeling/sb_serializer/sb_serializer_sva.sv
rtl/SideBand/analog_modeling/sb_deserializer/sb_deserializer.sv
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

# Register Access
rtl/SideBand/Reg_Access/Completion_gen.sv
rtl/SideBand/Reg_Access/Reg_DePacketizer.sv
rtl/SideBand/Reg_Access/Reg_Access_FSM.sv
rtl/SideBand/Reg_Access/Reg_Access.sv

# Top Sideband Module
rtl/SideBand/top/SideBand_Top.sv

# MBINIT design files
rtl/MainSM/LTSM/Common/timeout_counter.sv
rtl/MainSM/LTSM/Common/ltsm_state_n_pkg.sv
rtl/MainSM/common/LTSM_state_pkg.sv
rtl/MainSM/LTSM/Common/internal_ltsm_if.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_PARAM.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_CAL.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRCLK.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRVAL.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REVERSALMB.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRMB.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_CONTROLLER.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_WRAPPER.sv
rtl/MainSM/LTSM/MBINIT/MBINIT.sv

# D2C Point Test top wrapper & sub-modules design files
rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_top.sv

# Target Loopback Testbench with wrapper_D2C_PT_top
tb/integration/MBINIT_SideBand/MBINIT_D2C_SideBand_tb.sv
