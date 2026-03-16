onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /DEMAPPER_tb/clk
add wave -noupdate /DEMAPPER_tb/rst_n
add wave -noupdate /DEMAPPER_tb/dut/is_128bit
add wave -noupdate -expand -group {from ser} /DEMAPPER_tb/msg_rcvd
add wave -noupdate -expand -group {from ser} /DEMAPPER_tb/msg_vld_rcvd
add wave -noupdate -expand -group output /DEMAPPER_tb/msg_word_rcvd
add wave -noupdate -expand -group output /DEMAPPER_tb/word_vld_rcvd
add wave -noupdate /DEMAPPER_tb/pass_cnt
add wave -noupdate /DEMAPPER_tb/fail_cnt
add wave -noupdate /DEMAPPER_tb/dut/opcode
add wave -noupdate /DEMAPPER_tb/dut/first_half_reg
add wave -noupdate /DEMAPPER_tb/dut/current_state
add wave -noupdate /DEMAPPER_tb/dut/vld
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {141 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 198
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
WaveRestoreZoom {113 ns} {197 ns}
