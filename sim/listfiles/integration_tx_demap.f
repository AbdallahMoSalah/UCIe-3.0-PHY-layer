# =============================================================================
# Listfile: integration_tx_demap.f
# Purpose : Full TX->RX loopback integration. unit_tx_demap_wrapper drives a flit
#           through unit_tx_top (mapper/lfsr_tx/serializer), the Solution-2 RX
#           deserializer chain, unit_lfsr_rx (descramble) and unit_demapper, and
#           the TB checks the recovered flit (after demapper) against the original
#           flit (before mapper) - which is its byte-reverse for these blocks.
#
#           Builds on integration_tx_deser.f: same TX set + async FIFO + s2 RX
#           leaves, PLUS unit_lfsr_rx and unit_demapper.
#
#           Wrapper + TB live under "rtl/MainBand/Integration steps/" (the dir
#           name has a space) - paths are double-quoted for Questa's -f parser.
# Run     : make run CONFIG=integration_tx_demap TOP=unit_tx_demap_wrapper_tb
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

# ---- RX deserializer chain (Solution 2) -------------------------------------
rtl/MainBand/rx/unit_valid_deserializer_s2.sv
rtl/MainBand/rx/unit_valid_frame_detector_s2.sv
rtl/MainBand/rx/unit_data_deserializer_s2.sv

# ---- RX descramble + demap --------------------------------------------------
rtl/MainBand/rx/unit_lfsr_rx.sv
rtl/MainBand/rx/unit_demapper.sv

# ---- Integration wrapper + testbench ----------------------------------------
"rtl/MainBand/Integration steps/unit_tx_demap_wrapper.sv"
tb/integration/MAIN_BAND/Integration_steps/unit_tx_demap_wrapper_tb.sv
