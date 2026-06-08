# =============================================================================
# Listfile: integration_mb_train_seq.f
# Purpose : Full Main-Band link-training sequence over the TX -> RX loopback
#           (unit_mb_loopback_wrapper). Drives clock test -> valid -> data
#           (per-lane + lfsr) -> speed-up -> valid -> data -> ACTIVE, and proves
#           the link only reaches ACTIVE when every step passes (plus fault-
#           injected runs that must abort).
#
#           Wrapper + TB live under "rtl/MainBand/Integration steps/" (the dir
#           name has a space) - paths are double-quoted for Questa's -f parser.
# Run     : make run CONFIG=integration_mb_train_seq TOP=unit_mb_train_seq_tb
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

# ---- Integration wrapper + training-sequence testbench ----------------------
"rtl/MainBand/Integration steps/unit_mb_loopback_wrapper.sv"
"rtl/MainBand/Integration steps/unit_mb_train_seq_tb.sv"
