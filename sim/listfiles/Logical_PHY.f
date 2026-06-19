# =============================================================================
# Listfile: Logical_PHY.f
# Purpose : Back-to-back integration testbench for the Logical_PHY wrapper
#           (MainBand die + SideBand + LTSM + RDI_SM)
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
rtl/MainSM/LTSM/D2C/TX_D2C_PT/unit_TX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C/TX_D2C_PT/unit_TX_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C/RX_D2C_PT/unit_RX_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C/RX_D2C_PT/unit_RX_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C/wrapper_D2C_PT/wrapper_D2C_PT_local.sv
rtl/MainSM/LTSM/D2C/wrapper_D2C_PT/wrapper_D2C_PT_partner.sv
rtl/MainSM/LTSM/D2C/wrapper_D2C_PT/wrapper_D2C_PT.sv
rtl/MainSM/LTSM/D2C/unit_D2C_sweep.sv
rtl/MainSM/LTSM/D2C/wrapper_D2C_sweep.sv

# ---- MBTRAIN substates + top wrapper -----------------------------------------
rtl/MainSM/LTSM/MBTRAIN/unit_MBTRAIN_ctrl.sv
rtl/MainSM/LTSM/MBTRAIN/VALVREF/unit_VALVREF_local.sv
rtl/MainSM/LTSM/MBTRAIN/VALVREF/unit_VALVREF_partner.sv
rtl/MainSM/LTSM/MBTRAIN/VALVREF/wrapper_VALVREF.sv
rtl/MainSM/LTSM/MBTRAIN/DATAVREF/unit_DATAVREF_local.sv
rtl/MainSM/LTSM/MBTRAIN/DATAVREF/unit_DATAVREF_partner.sv
rtl/MainSM/LTSM/MBTRAIN/DATAVREF/wrapper_DATAVREF.sv
rtl/MainSM/LTSM/MBTRAIN/SPEEDIDLE/unit_SPEEDIDLE_local.sv
rtl/MainSM/LTSM/MBTRAIN/SPEEDIDLE/unit_SPEEDIDLE_partner.sv
rtl/MainSM/LTSM/MBTRAIN/SPEEDIDLE/wrapper_SPEEDIDLE.sv
rtl/MainSM/LTSM/MBTRAIN/TXSELFCAL/unit_TXSELFCAL_local.sv
rtl/MainSM/LTSM/MBTRAIN/TXSELFCAL/unit_TXSELFCAL_partner.sv
rtl/MainSM/LTSM/MBTRAIN/TXSELFCAL/wrapper_TXSELFCAL.sv
rtl/MainSM/LTSM/MBTRAIN/RXCLKCAL/unit_RXCLKCAL_local.sv
rtl/MainSM/LTSM/MBTRAIN/RXCLKCAL/unit_RXCLKCAL_partner.sv
rtl/MainSM/LTSM/MBTRAIN/RXCLKCAL/unit_RXCLKCAL_IQ_local.sv
rtl/MainSM/LTSM/MBTRAIN/RXCLKCAL/unit_RXCLKCAL_IQ_partner.sv
rtl/MainSM/LTSM/MBTRAIN/RXCLKCAL/wrapper_RXCLKCAL.sv
rtl/MainSM/LTSM/MBTRAIN/VALTRAINCENTER/unit_VALTRAINCENTER_local.sv
rtl/MainSM/LTSM/MBTRAIN/VALTRAINCENTER/unit_VALTRAINCENTER_partner.sv
rtl/MainSM/LTSM/MBTRAIN/VALTRAINCENTER/wrapper_VALTRAINCENTER.sv
rtl/MainSM/LTSM/MBTRAIN/VALTRAINVREF/unit_VALTRAINVREF_local.sv
rtl/MainSM/LTSM/MBTRAIN/VALTRAINVREF/unit_VALTRAINVREF_partner.sv
rtl/MainSM/LTSM/MBTRAIN/VALTRAINVREF/wrapper_VALTRAINVREF.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER1/unit_DATATRAINCENTER1_local.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER1/unit_DATATRAINCENTER1_partner.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER1/wrapper_DATATRAINCENTER1.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINVREF/unit_DATATRAINVREF_local.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINVREF/unit_DATATRAINVREF_partner.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINVREF/wrapper_DATATRAINVREF.sv
rtl/MainSM/LTSM/MBTRAIN/RXDESKEW/unit_RXDESKEW_local.sv
rtl/MainSM/LTSM/MBTRAIN/RXDESKEW/unit_RXDESKEW_partner.sv
rtl/MainSM/LTSM/MBTRAIN/RXDESKEW/wrapper_RXDESKEW.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER2/unit_DATATRAINCENTER2_local.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER2/unit_DATATRAINCENTER2_partner.sv
rtl/MainSM/LTSM/MBTRAIN/DATATRAINCENTER2/wrapper_DATATRAINCENTER2.sv
rtl/MainSM/LTSM/MBTRAIN/LINKSPEED/unit_LINKSPEED_local.sv
rtl/MainSM/LTSM/MBTRAIN/LINKSPEED/unit_LINKSPEED_partner.sv
rtl/MainSM/LTSM/MBTRAIN/LINKSPEED/wrapper_LINKSPEED.sv
rtl/MainSM/LTSM/MBTRAIN/REPAIR/unit_negotiated_lanes.sv
rtl/MainSM/LTSM/MBTRAIN/REPAIR/unit_REPAIR_local.sv
rtl/MainSM/LTSM/MBTRAIN/REPAIR/unit_REPAIR_partner.sv
rtl/MainSM/LTSM/MBTRAIN/REPAIR/wrapper_REPAIR.sv
rtl/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN.sv

# ---- LINKINIT + ACTIVE -------------------------------------------------------
rtl/MainSM/LTSM/LINKINIT/linkinit.sv
rtl/MainSM/LTSM/ACTIVE.sv

# ---- L1 / L2 / TRAINERROR ----------------------------------------------------
rtl/MainSM/LTSM/L1.sv
rtl/MainSM/LTSM/L2.sv
rtl/MainSM/LTSM/TRAINERROR.sv

# ---- LTSM controller + wrapper -----------------------------------------------
rtl/MainSM/LTSM/trainerror_handshake.sv
rtl/MainSM/LTSM/unit_ltsm_controller.sv
rtl/MainSM/LTSM/LTSM_wrapper.sv

# ---- LTSM_TOP interface + top ------------------------------------------------
rtl/MainBand_RD/mainband_ltsm_interface.sv
rtl/MainSM/LTSM/LTSM_TOP.sv

# ---- RDI_SM : wrapper_sm sub-modules -----------------------------------------
rtl/MainSM/RDI_SM/unit_Timer/unit_Timer.sv
rtl/MainSM/RDI_SM/unit_reset_state/unit_reset_state.sv
rtl/MainSM/RDI_SM/unit_active_state/unit_active_state.sv
rtl/MainSM/RDI_SM/unit_active_pmnak_state/unit_active_pmnak_state.sv
rtl/MainSM/RDI_SM/unit_retrain_state/unit_retrain_state.sv
rtl/MainSM/RDI_SM/unit_L1_state/unit_L1_state.sv
rtl/MainSM/RDI_SM/unit_L2_state/unit_L2_state.sv
rtl/MainSM/RDI_SM/unit_linkreset_state/unit_linkreset_state.sv
rtl/MainSM/RDI_SM/unit_linkerror_state/unit_linkerror_state.sv
rtl/MainSM/RDI_SM/unit_disabled_state/unit_disabled_state.sv
rtl/MainSM/RDI_SM/unit_main_controller/unit_main_controller.sv
rtl/MainSM/RDI_SM/unit_message_send_MUX/unit_message_send_MUX.sv
rtl/MainSM/RDI_SM/wrapper_sm/wrapper_sm.sv

# ---- RDI_SM : wrapper_handshake_logic sub-modules ----------------------------
rtl/MainSM/RDI_SM/unit_clk_handshake/unit_clk_handshake.sv
rtl/MainSM/RDI_SM/unit_awak_handshake/unit_awak_handshake.sv
rtl/MainSM/RDI_SM/unit_stall_handshake/unit_stall_handshake.sv
rtl/MainSM/RDI_SM/unit_active_handshake/unit_Active_handshake.sv
rtl/MainSM/RDI_SM/wrapper_handshake_logic/wrapper_handshake_logic.sv

# ---- RDI_SM : remaining sub-modules ------------------------------------------
rtl/MainSM/RDI_SM/unit_gating_logic/unit_gating_logic.sv
rtl/MainSM/RDI_SM/unit_signal_transition_detector/unit_signal_transition_detector.sv
rtl/MainSM/RDI_SM/unit_status_decoder/unit_status_decoder.sv
rtl/MainSM/RDI_SM/unit_msg_handler/unit_msg_handler.sv

# ---- RDI_SM Top-level --------------------------------------------------------
rtl/MainSM/RDI_SM/RDI_SM/RDI_SM.sv

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
rtl/TOP/Logical_PHY.sv

# ---- Testbench ---------------------------------------------------------------
tb/integration/Logical_PHY/Logical_PHY_tb.sv
