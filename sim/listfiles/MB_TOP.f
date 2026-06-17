# =============================================================================
# Listfile: MB_TOP.f
# Purpose : Full Main-Band integration compile list.
#           Covers MB_TX_TOP + MB_RX_TOP connected inside MB_TOP.
#
# Run  (console) : make run   CONFIG=MB_TOP TOP=MB_TOP_tb
# Run  (GUI)     : make debug CONFIG=MB_TOP TOP=MB_TOP_tb
# =============================================================================

# ── Testbench ──────────────────────────────────────────────────────────────
rtl/MainBand/MB_TOP/MB_TOP_tb.sv

# ── Top-level wrappers ─────────────────────────────────────────────────────
rtl/MainBand/MB_TOP/mb_die.sv

# ── TX path ────────────────────────────────────────────────────────────────
rtl/MainBand/MB_TX_TOP/MB_TX_TOP.sv

# PLL & clock
rtl/MainBand/MB_PLL/mb_PLL.sv
rtl/common/ClkDiv.sv

# CLK pattern generator (phase_delay is bundled inside this file)
rtl/MainBand/CLK_pattern_gen_TX/CLK_PATTERN_GEN_TX.sv

# Mapper
rtl/MainBand/MAPPER/Mapper.sv

# LFSR TX
rtl/MainBand/LFSR_TX/LFSR_TX.sv

# Valid TX
rtl/MainBand/VALID_TX/Valid_tx.sv

# Serializer
rtl/MainBand/MB_Serializer/mb_serializer.sv

# ── RX path ────────────────────────────────────────────────────────────────
rtl/MainBand/MB_RX_TOP/MB_RX_TOP.sv

# Valid-lane deserializer
rtl/MainBand/MB_DES_VALID/mb_des_valid.sv

# Data-lane deserializers (x16)
rtl/MainBand/MB_DeSerializer/mb_deserializer.sv

# Valid detector
rtl/MainBand/VALID_RX/Valid_RX.sv

# LFSR RX
rtl/MainBand/LFSR_RX/LFSR_RX.sv

# Pattern comparator
rtl/MainBand/MB_Pattern_comparator/mb_pattern_comparator.sv

# Demapper
rtl/MainBand/DEMAPPER/Demapper.sv

# CLK pattern detector
rtl/MainBand/CLK_pattern_detector_RX/CLK_PATTERN_DETECTOR_RX.sv
