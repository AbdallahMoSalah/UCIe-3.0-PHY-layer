# =============================================================================
# Listfile: mb_top_unit.f
# Purpose : Compilation list for MB_TOP full physical-loopback integration testbench.
# =============================================================================

# ---------- Clock / PLL / Common ----------
rtl/MainBand/MB_PLL/mb_PLL.sv
rtl/common/ClkDiv.sv
rtl/MainBand/CLK_pattern_gen_TX/CLK_PATTERN_GEN_TX.sv

# ---------- Transmit (TX) Side ----------
rtl/MainBand/MAPPER/Mapper.sv
rtl/MainBand/LFSR_TX/LFSR_TX.sv
rtl/MainBand/VALID_TX/Valid_tx.sv
rtl/MainBand/MB_Serializer/mb_serializer.sv
rtl/MainBand/MB_TX_TOP/MB_TX_TOP.sv

# ---------- Receive (RX) Side ----------
rtl/MainBand/MB_DeSerializer/mb_deserializer.sv
rtl/MainBand/VALID_RX/Valid_RX.sv
rtl/MainBand/MB_DES_VALID/mb_des_valid.sv
rtl/MainBand/CLK_pattern_detector_RX/CLK_PATTERN_DETECTOR_RX.sv
rtl/MainBand/LFSR_RX/LFSR_RX.sv
rtl/MainBand/DEMAPPER/Demapper.sv
rtl/MainBand/MB_Pattern_comparator/mb_pattern_comparator.sv
rtl/MainBand/MB_RX_TOP/MB_RX_TOP.sv

# ---------- Top Integration ----------
rtl/MainBand/Mian_Band_Integration/MB_TOP.sv

# ---------- Testbench ----------
tb/integration/MAIN_BAND/MB_TOP_TB.sv
