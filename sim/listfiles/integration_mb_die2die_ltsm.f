# =============================================================================
# Listfile: integration_mb_die2die_ltsm.f
# Purpose : Two complete Main-Band dies (unit_mb_die = TX top + RX top) wired
#           back-to-back, integrated with the LTSM interface.
# =============================================================================

# ---- TX datapath (mirrors TX_TOP.f) -----------------------------------------
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

# ---- Common async FIFO (unit_data_deserializer dependency) -------------------
rtl/common/FIFO/fifo_mem.sv
rtl/common/FIFO/fifo_rptr_empty.sv
rtl/common/FIFO/fifo_sync_2ff.sv
rtl/common/FIFO/fifo_wptr_full.sv
rtl/common/FIFO/fifo.sv

# ---- Common utilities --------------------------------------------------------
rtl/common/PULSE_GEN.v

# ---- RX deserializer chain (Solution 3) -------------------------------------
rtl/MainBand_RD/rx/unit_valid_deserializer.sv
rtl/MainBand_RD/rx/unit_valid_frame_detector.sv
rtl/MainBand_RD/rx/unit_data_deserializer.sv

# ---- RX descramble + demap + comparators + clk detect -----------------------
rtl/MainBand_RD/rx/unit_lfsr_rx.sv
rtl/MainBand_RD/rx/unit_demapper.sv
rtl/MainBand_RD/rx/unit_mb_pattern_comparator.sv
rtl/MainBand_RD/rx/unit_valid_comparator.sv
rtl/MainBand_RD/rx/unit_clk_pattern_detector_rx.sv

# ---- RX top -----------------------------------------------------------------
rtl/MainBand_RD/rx/unit_mb_rx_top.sv

# ---- Full MB die (TX + RX) + LTSM Interface + two-die testbench --------------
rtl/MainBand_RD/mainband_ltsm_interface.sv
"rtl/MainBand_RD/Integration steps/unit_mb_die.sv"
"rtl/MainBand_RD/Integration steps/unit_mb_die2die_ltsm_tb.sv"
