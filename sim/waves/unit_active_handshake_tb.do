onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_active_handshake_tb/uut/lclk
add wave -noupdate /unit_active_handshake_tb/uut/pm_exit
add wave -noupdate /unit_active_handshake_tb/uut/message_receive
add wave -noupdate /unit_active_handshake_tb/uut/Active_handshake_strt
add wave -noupdate /unit_active_handshake_tb/uut/inband_pres
add wave -noupdate /unit_active_handshake_tb/uut/Active_message_send
add wave -noupdate /unit_active_handshake_tb/uut/Active_handshake_done
add wave -noupdate /unit_active_handshake_tb/uut/state
add wave -noupdate /unit_active_handshake_tb/uut/flow
add wave -noupdate /unit_active_handshake_tb/uut/req_r
add wave -noupdate /unit_active_handshake_tb/uut/rsp_r
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {130581 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 247
configure wave -valuecolwidth 167
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
WaveRestoreZoom {0 ps} {689032 ps}
