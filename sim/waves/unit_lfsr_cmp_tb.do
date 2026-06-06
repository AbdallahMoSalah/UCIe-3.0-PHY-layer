onerror {resume}
quietly WaveActivateNextPane {} 0

# =====================================================================
#  LFSR_TX  (DUT_P)  -- interface only
# =====================================================================
add wave -noupdate -group {LFSR_TX (DUT_P)} /unit_lfsr_cmp_tb/DUT_P/i_clk
add wave -noupdate -group {LFSR_TX (DUT_P)} /unit_lfsr_cmp_tb/DUT_P/i_rst_n
add wave -noupdate -group {LFSR_TX (DUT_P)} -radix unsigned /unit_lfsr_cmp_tb/DUT_P/i_state
add wave -noupdate -group {LFSR_TX (DUT_P)} /unit_lfsr_cmp_tb/DUT_P/i_scramble_en
add wave -noupdate -group {LFSR_TX (DUT_P)} -radix unsigned /unit_lfsr_cmp_tb/DUT_P/i_width_deg_lfsr
add wave -noupdate -group {LFSR_TX (DUT_P)} /unit_lfsr_cmp_tb/DUT_P/i_reversal_en
add wave -noupdate -group {LFSR_TX (DUT_P)} -radix hexadecimal /unit_lfsr_cmp_tb/DUT_P/i_lane
add wave -noupdate -group {LFSR_TX (DUT_P)} -radix hexadecimal /unit_lfsr_cmp_tb/DUT_P/o_lane
add wave -noupdate -group {LFSR_TX (DUT_P)} /unit_lfsr_cmp_tb/DUT_P/o_ser_en_lfsr
add wave -noupdate -group {LFSR_TX (DUT_P)} /unit_lfsr_cmp_tb/DUT_P/o_Lfsr_tx_done

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
configure wave -namecolwidth 260
configure wave -valuecolwidth 120
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {2000 ns}
