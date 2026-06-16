# =============================================================================
# Listfile: integration_mb_die2die_mainband.f
# Purpose : Two MainBand dies (mb_die = MB_TX_TOP + MB_RX_TOP with serial pads
#           exposed) wired back-to-back as die0 and die1 over a real inter-die
#           channel. Reproduces the full MainBand_RD/unit_mb_die2die_tb scenario
#           set: continuous happy training (incl. forked stall + 20-flit heavy
#           load), clean + 3 fault aborts, and the full 5x5x3 degrade/reversal
#           sweep with real channel lane-reversal + directional fault injection.
#
# Run : make run CONFIG=integration_mb_die2die_mainband TOP=mb_die2die_tb
# =============================================================================

# ── Two-die wrapper + testbench ──────────────────────────────────────────────
rtl/MainBand/MB_DIE/mb_die.sv
rtl/MainBand/MB_DIE/mb_die2die_tb.sv

# ── TX path ──────────────────────────────────────────────────────────────────
rtl/MainBand/MB_TX_TOP/MB_TX_TOP.sv
rtl/MainBand/MB_PLL/mb_PLL.sv
rtl/common/ClkDiv.sv
rtl/MainBand/CLK_pattern_gen_TX/CLK_PATTERN_GEN_TX.sv
rtl/MainBand/MAPPER/Mapper.sv
rtl/MainBand/LFSR_TX/LFSR_TX.sv
rtl/MainBand/VALID_TX/Valid_tx.sv
rtl/MainBand/MB_Serializer/mb_serializer.sv

# ── RX path ──────────────────────────────────────────────────────────────────
rtl/MainBand/MB_RX_TOP/MB_RX_TOP.sv
rtl/MainBand/MB_DES_VALID/mb_des_valid.sv
rtl/MainBand/MB_DeSerializer/mb_deserializer.sv
rtl/MainBand/VALID_RX/Valid_RX.sv
rtl/MainBand/LFSR_RX/LFSR_RX.sv
rtl/MainBand/MB_Pattern_comparator/mb_pattern_comparator.sv
rtl/MainBand/DEMAPPER/Demapper.sv
rtl/MainBand/CLK_pattern_detector_RX/CLK_PATTERN_DETECTOR_RX.sv
