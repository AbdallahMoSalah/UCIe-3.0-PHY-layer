onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /sb_pattern_detector_tb/clk
add wave -noupdate /sb_pattern_detector_tb/rst_n
add wave -noupdate /sb_pattern_detector_tb/pattern_mode
add wave -noupdate /sb_pattern_detector_tb/packet_data
add wave -noupdate /sb_pattern_detector_tb/packet_done
add wave -noupdate -color Magenta /sb_pattern_detector_tb/pattern_detected
add wave -noupdate /sb_pattern_detector_tb/data_out
add wave -noupdate /sb_pattern_detector_tb/data_valid
add wave -noupdate /sb_pattern_detector_tb/send_packet/data
add wave -noupdate /sb_pattern_detector_tb/dut/is_pattern
add wave -noupdate /sb_pattern_detector_tb/dut/first_packet_last_bit
add wave -noupdate /sb_pattern_detector_tb/dut/pattern_cnt
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {77562 ps} 0}
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
WaveRestoreZoom {0 ps} {131250 ps}
