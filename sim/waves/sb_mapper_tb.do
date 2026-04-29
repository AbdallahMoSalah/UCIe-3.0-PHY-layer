onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -color yellow /sb_mapper_tb/dut/clk
add wave -noupdate -color yellow /sb_mapper_tb/dut/rst_n
add wave -noupdate /sb_mapper_tb/dut/msg_word_send
add wave -noupdate /sb_mapper_tb/dut/word_vld_send
add wave -noupdate -color green -radix hexadecimal /sb_mapper_tb/dut/msg_send
add wave -noupdate /sb_mapper_tb/dut/msg_vld_send
add wave -noupdate -color red /sb_mapper_tb/dut/mapper_ready
add wave -noupdate /sb_mapper_tb/dut/ser_ready
add wave -noupdate /sb_mapper_tb/dut/opcode
add wave -noupdate /sb_mapper_tb/dut/is_128bit
add wave -noupdate /sb_mapper_tb/dut/state
add wave -noupdate /sb_mapper_tb/mon
add wave -noupdate /sb_mapper_tb/drv
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {74 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 150
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
WaveRestoreZoom {45 ns} {97 ns}
