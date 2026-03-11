onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /Packetizer_tb/clk
add wave -noupdate -color Red -itemcolor Red /Packetizer_tb/rst_n
add wave -noupdate -color Yellow /Packetizer_tb/msg_info_send
add wave -noupdate -expand -group inputs -color {Medium Blue} /Packetizer_tb/msg_no_send
add wave -noupdate -expand -group inputs /Packetizer_tb/valid_send
add wave -noupdate -expand -group inputs /Packetizer_tb/stall_send
add wave -noupdate -expand -group inputs /Packetizer_tb/LINK_ready
add wave -noupdate -expand -group inputs -color {Orange Red} /Packetizer_tb/msg_data_send
add wave -noupdate -expand -group outputs -color {Orange Red} /Packetizer_tb/dut/header_comb
add wave -noupdate -expand -group outputs /Packetizer_tb/dut/header_reg
add wave -noupdate -expand -group outputs /Packetizer_tb/dut/payload
add wave -noupdate -expand -group outputs /Packetizer_tb/LINK_msg
add wave -noupdate -expand -group outputs /Packetizer_tb/LINK_vld
add wave -noupdate -expand -group outputs /Packetizer_tb/ready
add wave -noupdate /Packetizer_tb/dut/is_there_data
add wave -noupdate /Packetizer_tb/dut/is_req
add wave -noupdate -expand -group tb_counters /Packetizer_tb/pass_count
add wave -noupdate -expand -group tb_counters /Packetizer_tb/fail_count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {19183 ps} 0}
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
WaveRestoreZoom {0 ps} {102592 ps}
