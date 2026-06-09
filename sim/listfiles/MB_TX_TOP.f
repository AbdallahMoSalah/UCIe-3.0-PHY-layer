# =============================================================================
# Listfile: MB_TX_TOP.f
# Purpose : Compilation list for MB_TX_TOP integration testbench.
#           Covers the full Main-Band TX datapath:
#             MB_PLL → ClkDiv → CLK_PATTERN_GEN_TX (+ phase_delay)
#             Mapper → LFSR_TX → VALID_TX → MB_SERIALIZER (×17)
#
# Notes:
#   - CLK_PATTERN_GEN_TX.sv contains phase_delay inline; no separate file.
#   - Use the active RTL (rtl/MainBand/…), NOT the unsued/ folder variants.
#   - o_mb_clk is generated internally by ClkDiv (divide o_pll_clk by 16);
#     the TB drives no mb_clk — it observes o_mb_clk as a DUT output.
#
# Run  (console): make run   CONFIG=MB_TX_TOP TOP=MB_TX_TOP_tb
# Run  (GUI)    : make debug CONFIG=MB_TX_TOP TOP=MB_TX_TOP_tb
# =============================================================================

# ---------- Testbench ---------------------------------------------------------
rtl/MainBand/MB_TX_TOP/MB_TX_TOP_tb.sv

# ---------- DUT top -----------------------------------------------------------
rtl/MainBand/MB_TX_TOP/MB_TX_TOP.sv

# ---------- Clock / PLL -------------------------------------------------------
rtl/MainBand/MB_PLL/mb_PLL.sv
rtl/common/ClkDiv.sv

# ---------- Clock pattern generator (phase_delay bundled inside) --------------
rtl/MainBand/CLK_pattern_gen_TX/CLK_PATTERN_GEN_TX.sv

# ---------- Data-path sub-modules ---------------------------------------------
rtl/MainBand/MAPPER/Mapper.sv
rtl/MainBand/LFSR_TX/LFSR_TX.sv
rtl/MainBand/VALID_TX/Valid_tx.sv
rtl/MainBand/MB_Serializer/mb_serializer.sv
