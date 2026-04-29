onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /MB_DESERIALIZER_TB/DUT/valid_pulse
add wave -noupdate /MB_DESERIALIZER_TB/DUT/sync3_toggle
add wave -noupdate /MB_DESERIALIZER_TB/DUT/sync2_toggle
add wave -noupdate /MB_DESERIALIZER_TB/DUT/sync1_toggle
add wave -noupdate -color Magenta -radix binary /MB_DESERIALIZER_TB/DUT/shift_reg
add wave -noupdate /MB_DESERIALIZER_TB/DUT/ser_valid
add wave -noupdate /MB_DESERIALIZER_TB/DUT/ser_data_in
add wave -noupdate /MB_DESERIALIZER_TB/DUT/save_data_toggle
add wave -noupdate -radix binary /MB_DESERIALIZER_TB/DUT/save_data
add wave -noupdate /MB_DESERIALIZER_TB/DUT/pll_clk
add wave -noupdate /MB_DESERIALIZER_TB/DUT/par_data_out
add wave -noupdate /MB_DESERIALIZER_TB/DUT/MB_clk
add wave -noupdate -color Magenta /MB_DESERIALIZER_TB/DUT/i_rst_n
add wave -noupdate /MB_DESERIALIZER_TB/DUT/i_ckp
add wave -noupdate /MB_DESERIALIZER_TB/DUT/i_ckn
add wave -noupdate /MB_DESERIALIZER_TB/DUT/de_ser_done
add wave -noupdate /MB_DESERIALIZER_TB/DUT/DATA_WIDTH
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {725937 ps} 0}
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
WaveRestoreZoom {704316 ps} {824348 ps}
