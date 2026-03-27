onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /MB_DESERIALIZER_TB/i_clk
add wave -noupdate /MB_DESERIALIZER_TB/i_rst_n
add wave -noupdate /MB_DESERIALIZER_TB/in_des_data
add wave -noupdate /MB_DESERIALIZER_TB/deser_data_out
add wave -noupdate /MB_DESERIALIZER_TB/i
add wave -noupdate -color {Orange Red} -radix binary /MB_DESERIALIZER_TB/test_data
add wave -noupdate /MB_DESERIALIZER_TB/DUT/i_clk
add wave -noupdate /MB_DESERIALIZER_TB/DUT/i_rst_n
add wave -noupdate /MB_DESERIALIZER_TB/DUT/in_des_data
add wave -noupdate -color Magenta -radix binary /MB_DESERIALIZER_TB/DUT/deser_data_out
add wave -noupdate -radix decimal /MB_DESERIALIZER_TB/DUT/des_counter
add wave -noupdate -radix binary /MB_DESERIALIZER_TB/DUT/deser_data_out_temp
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {273451 ps} 0}
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
WaveRestoreZoom {175935 ps} {282175 ps}
