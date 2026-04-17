onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_msg_handler_tb/uut/lclk
add wave -noupdate -divider {received msg}
add wave -noupdate -color green -itemcolor green /unit_msg_handler_tb/uut/Link_Mgmt_Msg_Received
add wave -noupdate -color green -itemcolor green /unit_msg_handler_tb/uut/valid_r
add wave -noupdate -divider {sent msg}
add wave -noupdate -color tan -itemcolor tan /unit_msg_handler_tb/uut/Link_Mgmt_Msg_Send
add wave -noupdate -color tan -itemcolor tan /unit_msg_handler_tb/uut/valid_s
add wave -noupdate -divider {interface with main SM}
add wave -noupdate -color violet -itemcolor violet /unit_msg_handler_tb/uut/Message_send
add wave -noupdate -color violet -itemcolor violet /unit_msg_handler_tb/uut/Message_receive
add wave -noupdate -divider {interface with Active handshake}
add wave -noupdate -color coral -itemcolor coral /unit_msg_handler_tb/uut/Active_resp_r
add wave -noupdate -color coral -itemcolor coral /unit_msg_handler_tb/uut/Active_req_r
add wave -noupdate -color coral -itemcolor coral /unit_msg_handler_tb/uut/Active_resp_s
add wave -noupdate -color coral -itemcolor coral /unit_msg_handler_tb/uut/Active_req_s
add wave -noupdate -divider State
add wave -noupdate /unit_msg_handler_tb/uut/cs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {26764 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 282
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
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {387667 ps}
