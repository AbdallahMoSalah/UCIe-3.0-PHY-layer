onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /VALID_RX_TB/DUT/current_state
add wave -noupdate /VALID_RX_TB/i_clk
add wave -noupdate /VALID_RX_TB/i_rst_n
add wave -noupdate /VALID_RX_TB/RVLD_L
add wave -noupdate /VALID_RX_TB/i_Valid_en
add wave -noupdate /VALID_RX_TB/i_max_error_threshold
add wave -noupdate /VALID_RX_TB/O_result_logged_iteration
add wave -noupdate /VALID_RX_TB/O_result_logged_consecutive
add wave -noupdate /VALID_RX_TB/DUT/i_clk
add wave -noupdate /VALID_RX_TB/DUT/i_rst_n
add wave -noupdate /VALID_RX_TB/DUT/RVLD_L
add wave -noupdate /VALID_RX_TB/DUT/i_Valid_en
add wave -noupdate -color Pink -radix decimal /VALID_RX_TB/DUT/iteration_counter
add wave -noupdate -color Magenta -radix decimal /VALID_RX_TB/DUT/consec_count
add wave -noupdate /VALID_RX_TB/DUT/O_result_logged_iteration
add wave -noupdate /VALID_RX_TB/DUT/i_max_error_threshold
add wave -noupdate /VALID_RX_TB/DUT/O_result_logged_consecutive
add wave -noupdate /VALID_RX_TB/DUT/error_count
add wave -noupdate /VALID_RX_TB/DUT/mismatch_count
add wave -noupdate /VALID_RX_TB/DUT/valid_bytes
add wave -noupdate /VALID_RX_TB/DUT/i
add wave -noupdate /VALID_RX_TB/DUT/seg_0
add wave -noupdate /VALID_RX_TB/DUT/seg_1
add wave -noupdate /VALID_RX_TB/DUT/seg_2
add wave -noupdate /VALID_RX_TB/DUT/seg_3
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1394622 ps} 0}
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
WaveRestoreZoom {1374072 ps} {1480312 ps}
