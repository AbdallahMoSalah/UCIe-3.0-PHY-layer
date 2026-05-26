onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /MB_DESERIALIZER_TB/MB_clk
add wave -noupdate /MB_DESERIALIZER_TB/pll_clk
add wave -noupdate /MB_DESERIALIZER_TB/i_rst_n
add wave -noupdate /MB_DESERIALIZER_TB/ser_data_en
add wave -noupdate /MB_DESERIALIZER_TB/ser_data_in
add wave -noupdate /MB_DESERIALIZER_TB/enable_des_valid_frame
add wave -noupdate /MB_DESERIALIZER_TB/par_data_out
add wave -noupdate /MB_DESERIALIZER_TB/de_ser_done
add wave -noupdate /MB_DESERIALIZER_TB/test_num
add wave -noupdate /MB_DESERIALIZER_TB/pass_count
add wave -noupdate /MB_DESERIALIZER_TB/fail_count
add wave -noupdate /MB_DESERIALIZER_TB/send_serial_word/data
add wave -noupdate -radix decimal /MB_DESERIALIZER_TB/send_serial_word/i
add wave -noupdate /MB_DESERIALIZER_TB/check_output/expected
add wave -noupdate /MB_DESERIALIZER_TB/check_output/test_id
add wave -noupdate /MB_DESERIALIZER_TB/check_no_output/test_id
add wave -noupdate /MB_DESERIALIZER_TB/check_no_output/failed
add wave -noupdate /MB_DESERIALIZER_TB/DUT/MB_clk
add wave -noupdate /MB_DESERIALIZER_TB/DUT/pll_clk
add wave -noupdate /MB_DESERIALIZER_TB/DUT/i_rst_n
add wave -noupdate /MB_DESERIALIZER_TB/DUT/ser_data_en
add wave -noupdate /MB_DESERIALIZER_TB/DUT/ser_data_in
add wave -noupdate -color Magenta /MB_DESERIALIZER_TB/DUT/enable_des_valid_frame
add wave -noupdate /MB_DESERIALIZER_TB/DUT/par_data_out
add wave -noupdate /MB_DESERIALIZER_TB/DUT/de_ser_done
add wave -noupdate /MB_DESERIALIZER_TB/DUT/shift_reg
add wave -noupdate /MB_DESERIALIZER_TB/DUT/save_data
add wave -noupdate /MB_DESERIALIZER_TB/DUT/bit_cnt
add wave -noupdate /MB_DESERIALIZER_TB/DUT/save_data_toggle
add wave -noupdate /MB_DESERIALIZER_TB/DUT/sync1_toggle
add wave -noupdate /MB_DESERIALIZER_TB/DUT/sync2_toggle
add wave -noupdate /MB_DESERIALIZER_TB/DUT/sync3_toggle
add wave -noupdate /MB_DESERIALIZER_TB/DUT/valid_pulse
add wave -noupdate /MB_DESERIALIZER_TB/DUT/r_data_pos
add wave -noupdate /MB_DESERIALIZER_TB/DUT/r_data_neg
add wave -noupdate /MB_DESERIALIZER_TB/DUT/r_data_det
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1313220 ps} 0}
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
WaveRestoreZoom {746745 ps} {1531193 ps}
