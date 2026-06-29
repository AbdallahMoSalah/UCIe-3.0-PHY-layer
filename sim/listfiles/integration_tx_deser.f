# =============================================================================
# Listfile: integration_tx_deser.f
# Purpose : SER/DES integration of the frozen Main-Band TX top (unit_tx_top)
#           with the "Solution 2" RX deserializer chain. The wrapper
#           (unit_tx_deser_wrapper) loops TD_P/TVLD_P back into the
#           data/valid deserializers; the TB checks that every recovered word
#           (after deser) equals the serializer-input word (before ser).
#
#           TX file set mirrors TX_TOP.f (same unsued sub-modules + active
#           Mapper + MB-local clkdiv/clk_gate). Adds the common async FIFO
#           (needed by unit_data_deserializer_s2) and the s2 RX leaves, which
#           now live in rtl/MainBand/rx/ (moved out of rx/unused/).
#
#           NOTE: the wrapper + TB live under "rtl/MainBand/Integration steps/"
#           (the directory name contains a space) - paths are double-quoted so
#           Questa's -f parser treats each as a single filename.
# Run     : make run CONFIG=integration_tx_deser TOP=unit_tx_deser_wrapper_tb
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

# ---- Common async FIFO (unit_data_deserializer_s2 dependency) ----------------
rtl/common/FIFO/fifo_mem.sv
rtl/common/FIFO/fifo_rptr_empty.sv
rtl/common/FIFO/fifo_sync_2ff.sv
rtl/common/FIFO/fifo_wptr_full.sv
rtl/common/FIFO/fifo.sv

# ---- RX deserializer chain (Solution 3) -------------------------------------
rtl/MainBand/rx/unit_valid_deserializer.sv
rtl/MainBand/rx/unit_valid_frame_detector.sv
rtl/MainBand/rx/unit_data_deserializer.sv

# ---- Integration wrapper + testbench ----------------------------------------
"rtl/MainBand/Integration steps/unit_tx_deser_wrapper.sv"
tb/integration/MAIN_BAND/Integration_steps/unit_tx_deser_wrapper_tb.sv
