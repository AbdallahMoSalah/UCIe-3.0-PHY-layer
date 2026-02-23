onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /RDI_Packetizer_tb/pass_count
add wave -noupdate /RDI_Packetizer_tb/fail_count
add wave -noupdate /RDI_Packetizer_tb/DUT/clk
add wave -noupdate /RDI_Packetizer_tb/DUT/rst_n
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_msg_no_send
add wave -noupdate /RDI_Packetizer_tb/DUT/stall_send
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_vld_send
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_ready
add wave -noupdate /RDI_Packetizer_tb/DUT/push_ready
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_msg
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_vld_out
add wave -noupdate /RDI_Packetizer_tb/DUT/header_reg
add wave -noupdate /RDI_Packetizer_tb/DUT/header_next
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
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
WaveRestoreZoom {3195 ns} {4112 ns}
