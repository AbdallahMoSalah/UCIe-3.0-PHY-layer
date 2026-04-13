onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /MB_DESERIALIZER_TB/DUT/PLL_clk
add wave -noupdate /MB_DESERIALIZER_TB/DUT/mb_clk
add wave -noupdate /MB_DESERIALIZER_TB/DUT/in_des_data
add wave -noupdate /MB_DESERIALIZER_TB/DUT/i_rst_n
add wave -noupdate /MB_DESERIALIZER_TB/DUT/i_clkp
add wave -noupdate /MB_DESERIALIZER_TB/DUT/i_clkn
add wave -noupdate /MB_DESERIALIZER_TB/DUT/deser_en
add wave -noupdate /MB_DESERIALIZER_TB/DUT/deser_done
add wave -noupdate /MB_DESERIALIZER_TB/DUT/deser_data_out_reg
add wave -noupdate /MB_DESERIALIZER_TB/DUT/deser_data_out
add wave -noupdate /MB_DESERIALIZER_TB/DUT/des_counter
add wave -noupdate /MB_DESERIALIZER_TB/DUT/data_valid_reg
add wave -noupdate /MB_DESERIALIZER_TB/DUT/data_save_reg
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {184563 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 135
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
WaveRestoreZoom {387759 ps} {437487 ps}
