# =============================================================================
# Listfile: TX_TOP.f
# Purpose : Compilation list for TX_TOP (rtl/MainBand/tx/unused/TX_TOP.sv).
#           Pulls the UNUSED-folder TX sub-modules (MB_PLL, LFSR_TX, VALID_TX,
#           MB_SERIALIZER, CLK_PATTERN_GEN_TX) plus the active Mapper (no unsued
#           variant) and the shared clocking leaf modules ClkDiv (pll_clk / 16 ->
#           lclk) + CLK_GATE (rtl/common).
#
#           MB_PLL: TX_TOP instantiates the self-oscillating unsued variant
#           (.en/.speed_sel/.clk/.local_period, no i_ref_clk). The active
#           rtl/MainBand/mb_PLL.sv has a different port set (i_ref_clk,
#           .period) and must NOT be used here.
#
#           NOTE: the unsued sub-modules share module names with the active RTL
#           and CLK_PATTERN_GEN_TX bundles its own phase_delay, so do NOT add the
#           active LFSR_TX / Valid_tx / mb_serializer / CLK_PATTERN_GEN_TX or
#           rtl/common/analog_modeling/phase_delay.sv here (duplicate modules).
# Run     : make run CONFIG=TX_TOP TOP=TX_TOP_tb
# =============================================================================

# DUT (top first)
rtl/MainBand/tx/unused/TX_TOP.sv

# Active sub-modules (no unsued variant)
rtl/MainBand/tx/Mapper.sv

# Shared clocking leaf modules (rtl/common copies; unsued dupes removed)
rtl/common/ClkDiv.sv
rtl/common/CLK_GATE.sv

# Unsued sub-modules
rtl/MainBand/mb_PLL.sv
rtl/MainBand/tx/LFSR_TX.sv
rtl/MainBand/tx/Valid_tx.sv
rtl/MainBand/tx/mb_serializer.sv
rtl/MainBand/tx/CLK_PATTERN_GEN_TX.sv

# Testbench
rtl/MainBand/tx/unused/TX_TOP_tb.sv
