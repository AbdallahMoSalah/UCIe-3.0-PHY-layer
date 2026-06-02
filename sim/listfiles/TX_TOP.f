# =============================================================================
# Listfile: TX_TOP.f
# Purpose : Compilation list for TX_TOP (rtl/MainBand/unsued/TX_TOP.sv).
#           Pulls the UNUSED-folder TX sub-modules (LFSR_TX, VALID_TX,
#           MB_SERIALIZER, CLK_PATTERN_GEN_TX) plus the active Mapper + MB_PLL
#           (no unsued variants exist for those two).
#
#           NOTE: the unsued sub-modules share module names with the active RTL
#           and CLK_PATTERN_GEN_TX bundles its own phase_delay, so do NOT add the
#           active LFSR_TX / Valid_tx / mb_serializer / CLK_PATTERN_GEN_TX or
#           rtl/common/analog_modeling/phase_delay.sv here (duplicate modules).
# Run     : make run CONFIG=TX_TOP TOP=TX_TOP_tb
# =============================================================================

# DUT (top first)
rtl/MainBand/unsued/TX_TOP.sv

# Active sub-modules (no unsued variant)
rtl/MainBand/MAPPER/Mapper.sv
rtl/MainBand/MB_PLL/mb_PLL.sv

# Unsued sub-modules
rtl/MainBand/unsued/LFSR_TX.sv
rtl/MainBand/unsued/Valid_tx.sv
rtl/MainBand/unsued/mb_serializer.sv
rtl/MainBand/unsued/CLK_PATTERN_GEN_TX.sv

# Testbench
rtl/MainBand/unsued/TX_TOP_tb.sv
