onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /RDI_DePacketizer_tb/clk
add wave -noupdate /RDI_DePacketizer_tb/rst_n
add wave -noupdate /RDI_DePacketizer_tb/LINK_msg_rcvd
add wave -noupdate /RDI_DePacketizer_tb/LINK_vld_rcvd
add wave -noupdate /RDI_DePacketizer_tb/RDI_msg_no_rcvd
add wave -noupdate /RDI_DePacketizer_tb/stall_rcvd
add wave -noupdate /RDI_DePacketizer_tb/RDI_vld_rcvd
add wave -noupdate /RDI_DePacketizer_tb/pass_count
add wave -noupdate /RDI_DePacketizer_tb/fail_count
add wave -noupdate -expand /RDI_DePacketizer_tb/DUT/header
add wave -noupdate /RDI_DePacketizer_tb/DUT/RDI_msg_no_rcvd_next
add wave -noupdate /RDI_DePacketizer_tb/DUT/stall_rcvd_next
add wave -noupdate /RDI_DePacketizer_tb/DUT/rdi_msg_valid
add wave -noupdate /RDI_DePacketizer_tb/DUT/cp_calc
add wave -noupdate /RDI_DePacketizer_tb/DUT/error
add wave -noupdate /RDI_DePacketizer_tb/obj
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {31170 ns} 0}
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
WaveRestoreZoom {31160 ns} {31180 ns}
