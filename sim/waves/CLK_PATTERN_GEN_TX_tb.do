onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/i_clk
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/i_rst_n
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/clk_pattern_en
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/clk_embedded_en
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/o_clk_p
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/o_clk_n
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/track
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/o_done
add wave -noupdate -color Violet -radix unsigned /CLK_PATTERN_GEN_TX_tb/dut/counter_toggle
add wave -noupdate -color Violet -radix unsigned /CLK_PATTERN_GEN_TX_tb/dut/counter_zero
add wave -noupdate -color Violet -radix unsigned /CLK_PATTERN_GEN_TX_tb/dut/counter_main
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/pd/in_signal
add wave -noupdate /CLK_PATTERN_GEN_TX_tb/dut/pd/delayed_signal
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {129255 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
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
WaveRestoreZoom {129411 ns} {129633 ns}
