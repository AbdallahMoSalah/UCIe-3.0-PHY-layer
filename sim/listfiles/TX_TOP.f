# =============================================================================
# Listfile: TX_TOP.f
# Purpose : Compilation list for TX_TOP (rtl/MainBand/tx/unused/unit_tx_top.sv).
#           Pulls the UNUSED-folder TX sub-modules (MB_PLL, LFSR_TX, VALID_TX,
#           MB_SERIALIZER, CLK_PATTERN_GEN_TX) plus the active Mapper (no unsued
#           variant) and the MB-local clocking leaf modules unit_clkdiv
#           (pll_clk / 16 -> lclk) + unit_clk_gate (rtl/MainBand/tx).
#
#           MB_PLL: unit_tx_top instantiates the self-oscillating variant at
#           rtl/MainBand/tx/unit_mb_pll.sv (.en/.speed_sel/.clk/.local_period,
#           no i_ref_clk). Any i_ref_clk/.period variant has a different port set
#           and must NOT be used here.
#
#           NOTE: the unsued sub-modules share module names with the active RTL
#           and unit_clk_pattern_gen_tx bundles its own phase_delay, so do NOT add the
#           active LFSR_TX / Valid_tx / mb_serializer / unit_clk_pattern_gen_tx or
#           rtl/common/analog_modeling/phase_delay.sv here (duplicate modules).
# Run     : make run CONFIG=TX_TOP TOP=unit_tx_top_tb
# =============================================================================

# DUT (top first)
rtl/MainBand/tx/unused/unit_tx_top.sv

# Active sub-modules (no unsued variant)
rtl/MainBand/tx/unit_mapper.sv

# Clocking leaf modules (MB-local unit_* variants matching unit_tx_top's
# unit_clkdiv / unit_clk_gate instantiations)
rtl/MainBand/tx/unit_clkdiv.sv
rtl/MainBand/tx/unit_clk_gate.sv

# Unsued sub-modules
rtl/MainBand/tx/unit_mb_pll.sv
rtl/MainBand/tx/unit_lfsr_tx.sv
rtl/MainBand/tx/unit_valid_tx.sv
rtl/MainBand/tx/unit_mb_serializer.sv
rtl/MainBand/tx/unit_clk_pattern_gen_tx.sv

# Testbench
rtl/MainBand/tx/unused/unit_tx_top_tb.sv
