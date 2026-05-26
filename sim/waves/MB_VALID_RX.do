onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /VALID_RX_TB/i_clk
add wave -noupdate /VALID_RX_TB/i_rst_n
add wave -noupdate /VALID_RX_TB/RVLD_L
add wave -noupdate /VALID_RX_TB/i_max_error_threshold
add wave -noupdate /VALID_RX_TB/i_enable_cons
add wave -noupdate -expand -group seg_group /VALID_RX_TB/DUT/seg_0
add wave -noupdate -expand -group seg_group /VALID_RX_TB/DUT/seg_1
add wave -noupdate -expand -group seg_group /VALID_RX_TB/DUT/seg_2
add wave -noupdate -expand -group seg_group /VALID_RX_TB/DUT/seg_3
add wave -noupdate -color Magenta -itemcolor {Medium Sea Green} -radix unsigned /VALID_RX_TB/DUT/consec_count
add wave -noupdate /VALID_RX_TB/i_enable_128
add wave -noupdate /VALID_RX_TB/i_enable_detector
add wave -noupdate -color Magenta -itemcolor {Medium Sea Green} -radix decimal /VALID_RX_TB/DUT/iteration_counter
add wave -noupdate /VALID_RX_TB/detection_result
add wave -noupdate /VALID_RX_TB/o_valid_frame_detect
add wave -noupdate /VALID_RX_TB/prev_detection_result
add wave -noupdate /VALID_RX_TB/prev_valid_frame_detect
add wave -noupdate /VALID_RX_TB/DUT/i_clk
add wave -noupdate /VALID_RX_TB/DUT/i_rst_n
add wave -noupdate /VALID_RX_TB/DUT/RVLD_L
add wave -noupdate /VALID_RX_TB/DUT/i_max_error_threshold
add wave -noupdate /VALID_RX_TB/DUT/i_enable_cons
add wave -noupdate /VALID_RX_TB/DUT/i_enable_128
add wave -noupdate /VALID_RX_TB/DUT/i_enable_detector
add wave -noupdate -color Magenta -itemcolor {Medium Sea Green} /VALID_RX_TB/DUT/detection_result
add wave -noupdate /VALID_RX_TB/DUT/o_valid_frame_detect
add wave -noupdate /VALID_RX_TB/DUT/error_count
add wave -noupdate /VALID_RX_TB/DUT/mismatch_count
add wave -noupdate /VALID_RX_TB/DUT/valid_bytes
add wave -noupdate /VALID_RX_TB/DUT/i
add wave -noupdate /VALID_RX_TB/DUT/mode_select
add wave -noupdate /VALID_RX_TB/DUT/valid_frame_detect
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2684771 ps} 0}
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
configure wave -timelineunits ps
update
WaveRestoreZoom {2645523 ps} {2677523 ps}
