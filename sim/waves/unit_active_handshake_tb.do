onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_active_handshake_tb/uut/lclk
add wave -noupdate -divider {handshake interface}
add wave -noupdate -color coral -itemcolor coral /unit_active_handshake_tb/uut/Active_handshake_strt
add wave -noupdate -color coral -itemcolor coral /unit_active_handshake_tb/uut/Active_handshake_done
add wave -noupdate -divider {recieve port}
add wave -noupdate -color blue -itemcolor blue /unit_active_handshake_tb/uut/Active_resp_r
add wave -noupdate -color blue -itemcolor blue /unit_active_handshake_tb/uut/Active_req_r
add wave -noupdate -divider {send port}
add wave -noupdate /unit_active_handshake_tb/uut/Active_resp_s
add wave -noupdate /unit_active_handshake_tb/uut/Active_req_s
add wave -noupdate -divider state
add wave -noupdate /unit_active_handshake_tb/uut/state
add wave -noupdate -divider {flow control}
add wave -noupdate -color violet -itemcolor violet /unit_active_handshake_tb/uut/flow
add wave -noupdate -color violet -itemcolor violet /unit_active_handshake_tb/uut/req_r
TreeUpdate [SetDefaultTree]
quietly WaveActivateNextPane
WaveRestoreCursors {{Cursor 1} {239913 ps} 0} {{Cursor 2} {343532 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 244
configure wave -valuecolwidth 117
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
WaveRestoreZoom {239913 ps} {343532 ps}
