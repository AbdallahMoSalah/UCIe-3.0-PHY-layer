onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/i_clk
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/i_rst_n
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/clk_detector_en
add wave -noupdate -expand -group P /CLK_PATTERN_DETECTOR_RX_tb/clk_p
add wave -noupdate -expand -group P /CLK_PATTERN_DETECTOR_RX_tb/clk_p_pattern_error
add wave -noupdate -expand -group P -color {Dark Orchid} -radix unsigned /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_toggle_p
add wave -noupdate -expand -group P -color {Dark Orchid} -radix unsigned /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_zero_p
add wave -noupdate -expand -group P -color {Dark Orchid} -radix unsigned /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_16_consecetive_p
add wave -noupdate -expand -group P /CLK_PATTERN_DETECTOR_RX_tb/dut/clk_p_p_w
add wave -noupdate -expand -group P /CLK_PATTERN_DETECTOR_RX_tb/dut/clk_p_n_w
add wave -noupdate -expand -group P /CLK_PATTERN_DETECTOR_RX_tb/dut/flag_p_tog
add wave -noupdate -expand -group P /CLK_PATTERN_DETECTOR_RX_tb/dut/flag_p_zero
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/clk_n
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/track
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/clk_n_pattern_error
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/track_pattern_error
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_toggle_n
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_toggle_track
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_zero_n
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_zero_track
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_16_consecetive_n
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/counter_16_consecetive_track
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/clk_n_p_w
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/clk_n_n_w
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/track_p_w
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/track_n_w
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/flag_n_tog
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/flag_n_zero
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/flag_track_tog
add wave -noupdate /CLK_PATTERN_DETECTOR_RX_tb/dut/flag_track_zero
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
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
WaveRestoreZoom {3495 ns} {4495 ns}
