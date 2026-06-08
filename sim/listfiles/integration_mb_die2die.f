# =============================================================================
# Listfile: integration_mb_die2die.f
# Purpose : Two complete Main-Band dies (unit_mb_die = TX top + RX top) wired
#           back-to-back as die 0 and die 1. Runs the full link-training
#           sequence (clock/valid/data/active) on both link directions at once,
#           plus fault-injected runs that must abort.
#
#           Wrapper + TB live under "rtl/MainBand/Integration steps/" (the dir
#           name has a space) - paths are double-quoted for Questa's -f parser.
# Run     : make run CONFIG=integration_mb_die2die TOP=unit_mb_die2die_tb
# =============================================================================

# ---- TX datapath (mirrors TX_TOP.f) -----------------------------------------
rtl/MainBand/tx/unit_mapper.sv
rtl/MainBand/tx/unit_clkdiv.sv
rtl/MainBand/tx/unit_clk_gate.sv
rtl/MainBand/tx/unit_mb_pll.sv
rtl/MainBand/tx/unit_lfsr_tx.sv
rtl/MainBand/tx/unit_valid_tx.sv
rtl/MainBand/tx/unit_mb_serializer.sv
rtl/MainBand/tx/unit_clk_pattern_gen_tx.sv
rtl/MainBand/tx/unused/unit_tx_top.sv

# ---- Common async FIFO (unit_data_deserializer dependency) -------------------
rtl/common/FIFO/fifo_mem.sv
rtl/common/FIFO/fifo_rptr_empty.sv
rtl/common/FIFO/fifo_sync_2ff.sv
rtl/common/FIFO/fifo_wptr_full.sv
rtl/common/FIFO/fifo.sv

# ---- Common utilities --------------------------------------------------------
rtl/common/PULSE_GEN.v

# ---- RX deserializer chain (Solution 3) -------------------------------------
rtl/MainBand/rx/unit_valid_deserializer.sv
rtl/MainBand/rx/unit_valid_frame_detector.sv
rtl/MainBand/rx/unit_data_deserializer.sv

# ---- RX descramble + demap + comparators + clk detect -----------------------
rtl/MainBand/rx/unit_lfsr_rx.sv
rtl/MainBand/rx/unit_demapper.sv
rtl/MainBand/rx/unit_mb_pattern_comparator.sv
rtl/MainBand/rx/unit_valid_comparator.sv
rtl/MainBand/rx/unit_clk_pattern_detector_rx.sv

# ---- RX top -----------------------------------------------------------------
rtl/MainBand/rx/unit_mb_rx_top.sv

# ---- Full MB die (TX + RX) + two-die back-to-back testbench ------------------
"rtl/MainBand/Integration steps/unit_mb_die.sv"
"rtl/MainBand/Integration steps/unit_mb_die2die_tb.sv"
