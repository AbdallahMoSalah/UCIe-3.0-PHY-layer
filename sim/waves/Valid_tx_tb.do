onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /VALID_TX_tb/uut/i_clk
add wave -noupdate /VALID_TX_tb/uut/i_rst_n
add wave -noupdate /VALID_TX_tb/uut/valid_pattern_en
add wave -noupdate /VALID_TX_tb/uut/ser_en_lfsr_i
add wave -noupdate /VALID_TX_tb/uut/ser_en_o
add wave -noupdate /VALID_TX_tb/uut/O_done
add wave -noupdate /VALID_TX_tb/uut/o_TVLD_L
add wave -noupdate /VALID_TX_tb/uut/COUNTER
add wave -noupdate /VALID_TX_tb/uut/current_state
add wave -noupdate /VALID_TX_tb/uut/next_state
add wave -noupdate /VALID_TX_tb/uut/ser_en_internal
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {473423 ps} 0}
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
WaveRestoreZoom {78926 ps} {424731 ps}
