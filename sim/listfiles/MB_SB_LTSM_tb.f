# =============================================================================
# Listfile: MB_SB_LTSM_tb.f
# Purpose : Back-to-back integration testbench for MB_SB_LTSM wrapper
# =============================================================================

# ---- Packages ----------------------------------------------------------------
rtl/common/UCIe_pkg.sv
rtl/SideBand/common/sb_pkg.sv
rtl/SideBand/common/msg_codec_pkg.sv
rtl/MainSM/RDI_SM/common/RDI_SM_pkg.sv
rtl/MainSM/LTSM/Common/ltsm_state_n_pkg.sv
rtl/MainSM/common/LTSM_state_pkg.sv
rtl/MainSM/LTSM/Common/internal_ltsm_if.sv

# ---- Common utilities --------------------------------------------------------
rtl/common/FIFO/fifo_mem.sv
rtl/common/FIFO/fifo_rptr_empty.sv
rtl/common/FIFO/fifo_sync_2ff.sv
rtl/common/FIFO/fifo_wptr_full.sv
rtl/common/FIFO/fifo.sv
rtl/common/CLK_GATE.sv
rtl/common/PULSE_GEN.v
rtl/common/ClkDiv.sv

# ---- SideBand RTL ------------------------------------------------------------
rtl/SideBand/sb_pll.sv
rtl/SideBand/common/sb_demux.sv
rtl/SideBand/common/sb_priority_arbiter.sv
rtl/SideBand/analog_modeling/sb_serializer/sb_serializer.sv
rtl/SideBand/analog_modeling/sb_serializer/sb_serializer_sva.sv
rtl/SideBand/analog_modeling/sb_deserializer/sb_deserializer.sv
rtl/SideBand/analog_modeling/sb_deserializer/sb_deserializer_sva.sv
rtl/SideBand/Link_Controller/sb_mapper.sv
rtl/SideBand/Link_Controller/sb_demapper.sv
rtl/SideBand/Link_Controller/Link_Demux.sv
rtl/SideBand/Link_Controller/sb_pattern_detector.sv
rtl/SideBand/Link_Controller/sb_pattern_engine.sv
rtl/SideBand/Link_Controller/Link_Controller.sv
rtl/SideBand/Training_mgmt/roud_robin_arbiter.sv
rtl/SideBand/Training_mgmt/Packetizer.sv
rtl/SideBand/Training_mgmt/DePacketizer.sv
rtl/SideBand/Training_mgmt/Training_Mgmt_Demux.sv
rtl/SideBand/Training_mgmt/Training_Mgmt.sv
rtl/SideBand/rdi_controller/credit_counter.sv
rtl/SideBand/rdi_controller/rdi_aggregator.sv
rtl/SideBand/rdi_controller/rdi_de_aggregator.sv
rtl/SideBand/rdi_controller/rdi_router.sv
rtl/SideBand/rdi_controller/rdi_comp_req_decoder.sv
rtl/SideBand/rdi_controller/RDI_control.sv
rtl/SideBand/Reg_Access/Completion_gen.sv
rtl/SideBand/Reg_Access/Reg_DePacketizer.sv
rtl/SideBand/Reg_Access/Reg_Access_FSM.sv
rtl/SideBand/Reg_Access/Reg_Access.sv
rtl/SideBand/top/SideBand_Top.sv

# ---- LTSM common -------------------------------------------------------------
rtl/MainSM/LTSM/Common/timeout_counter.sv

# ---- LTSM substates ----------------------------------------------------------
rtl/MainSM/LTSM/RESET.sv
rtl/MainSM/LTSM/SBINIT.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_PARAM.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_CAL.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRCLK.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRVAL.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REVERSALMB.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_REPAIRMB.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_CONTROLLER.sv
rtl/MainSM/LTSM/MBINIT/MBINIT_WRAPPER.sv
rtl/MainSM/LTSM/MBINIT/MBINIT.sv

# ---- D2C Point Test ----------------------------------------------------------
rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/TX_D2C_PT/unit_TX_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/RX_D2C_PT/unit_RX_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C_PT/wrapper_D2C_PT/wrapper_D2C_PT_top.sv

# ---- LINKINIT + ACTIVE -------------------------------------------------------
rtl/MainSM/LTSM/LINKINIT/linkinit.sv
rtl/MainSM/LTSM/ACTIVE.sv

# ---- LTSM controller + wrapper -----------------------------------------------
rtl/MainSM/LTSM/unit_ltsm_controller.sv
rtl/MainSM/LTSM/LTSM_wrapper.sv

# ---- LTSM_TOP interface + top ------------------------------------------------
rtl/MainBand_RD/mainband_ltsm_interface.sv
rtl/MainSM/LTSM/LTSM_TOP.sv

# ---- MainBand RD TX datapath -------------------------------------------------
rtl/MainBand_RD/tx/unit_mapper.sv
rtl/MainBand_RD/tx/unit_clkdiv.sv
rtl/MainBand_RD/tx/unit_clk_gate.sv
rtl/MainBand_RD/tx/unit_mb_pll.sv
rtl/MainBand_RD/tx/unit_lfsr_tx.sv
rtl/MainBand_RD/tx/unit_valid_tx.sv
rtl/MainBand_RD/tx/unit_mb_serializer.sv
rtl/MainBand_RD/tx/unit_clk_pattern_gen_tx.sv
rtl/MainBand_RD/tx/unused/unit_tx_top.sv
rtl/MainBand_RD/tx/unit_mb_tx_reversal.sv

# ---- MainBand RD RX datapath -------------------------------------------------
rtl/MainBand_RD/rx/unit_valid_deserializer.sv
rtl/MainBand_RD/rx/unit_valid_frame_detector.sv
rtl/MainBand_RD/rx/unit_data_deserializer.sv
rtl/MainBand_RD/rx/unit_lfsr_rx.sv
rtl/MainBand_RD/rx/unit_demapper.sv
rtl/MainBand_RD/rx/unit_mb_pattern_comparator.sv
rtl/MainBand_RD/rx/unit_valid_comparator.sv
rtl/MainBand_RD/rx/unit_clk_pattern_detector_rx.sv
rtl/MainBand_RD/rx/unit_mb_rx_top.sv

# ---- Full MB die (TX + RX) ---------------------------------------------------
"rtl/MainBand_RD/Integration steps/unit_mb_die.sv"

# ---- Wrapper under test ------------------------------------------------------
rtl/TOP/MB_SB_LTSM.sv

# ---- Testbench ---------------------------------------------------------------
tb/integration/MB_SB_LTSM/MB_SB_LTSM_tb.sv
