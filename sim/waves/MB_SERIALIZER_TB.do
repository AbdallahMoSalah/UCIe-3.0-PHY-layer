onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -color Magenta /MB_SERIALIZER_TB/DUT/SER_out
add wave -noupdate /MB_SERIALIZER_TB/DUT/Ser_en
add wave -noupdate -radix decimal /MB_SERIALIZER_TB/DUT/ser_counter
add wave -noupdate /MB_SERIALIZER_TB/DUT/PLL_clk
add wave -noupdate /MB_SERIALIZER_TB/DUT/mb_clk
add wave -noupdate /MB_SERIALIZER_TB/DUT/load_reg
add wave -noupdate /MB_SERIALIZER_TB/DUT/in_data
add wave -noupdate /MB_SERIALIZER_TB/DUT/i_rst_n
add wave -noupdate /MB_SERIALIZER_TB/DUT/DATA_WIDTH
add wave -noupdate /MB_SERIALIZER_TB/DUT/data_reg
add wave -noupdate /MB_SERIALIZER_TB/DUT/SER_out
add wave -noupdate /MB_SERIALIZER_TB/DUT/load_condition
add wave -noupdate /MB_SERIALIZER_TB/DUT/ser_en_pll_sync2
add wave -noupdate /MB_SERIALIZER_TB/DUT/ser_en_pll_sync1
add wave -noupdate /MB_SERIALIZER_TB/DUT/ser_en_pll_dl
add wave -noupdate /MB_SERIALIZER_TB/DUT/Ser_en
add wave -noupdate /MB_SERIALIZER_TB/DUT/ser_counter
add wave -noupdate /MB_SERIALIZER_TB/DUT/rising_ser_en_pll
add wave -noupdate /MB_SERIALIZER_TB/DUT/PLL_clk
add wave -noupdate /MB_SERIALIZER_TB/DUT/mb_clk
add wave -noupdate /MB_SERIALIZER_TB/DUT/load_reg
add wave -noupdate /MB_SERIALIZER_TB/DUT/in_data
add wave -noupdate /MB_SERIALIZER_TB/DUT/i_rst_n
add wave -noupdate /MB_SERIALIZER_TB/DUT/DATA_WIDTH
add wave -noupdate /MB_SERIALIZER_TB/DUT/data_reg
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {168181 ps} 0}
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
WaveRestoreZoom {92572 ps} {198812 ps}
