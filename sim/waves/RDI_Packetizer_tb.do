onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /RDI_Packetizer_tb/DUT/clk
add wave -noupdate /RDI_Packetizer_tb/DUT/rst_n
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_msg_no_send
add wave -noupdate /RDI_Packetizer_tb/DUT/stall_send
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_vld_send
add wave -noupdate /RDI_Packetizer_tb/DUT/push_ready
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_ready
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_msg
add wave -noupdate /RDI_Packetizer_tb/DUT/RDI_vld_out
add wave -noupdate /RDI_Packetizer_tb/DUT/header_next
add wave -noupdate -expand -group result -expand /RDI_Packetizer_tb/DUT/header_reg
add wave -noupdate -expand -group result -expand /RDI_Packetizer_tb/dut_hdr
add wave -noupdate /RDI_Packetizer_tb/pass_count
add wave -noupdate /RDI_Packetizer_tb/fail_count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {50 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 423
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
WaveRestoreZoom {19998 ns} {20032 ns}
