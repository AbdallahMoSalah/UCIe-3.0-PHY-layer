onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_L2_state_tb/uut/lclk
add wave -noupdate /unit_L2_state_tb/uut/EN
add wave -noupdate /unit_L2_state_tb/uut/lp_linkerror
add wave -noupdate /unit_L2_state_tb/uut/lp_state_req
add wave -noupdate /unit_L2_state_tb/uut/massage_receive
add wave -noupdate /unit_L2_state_tb/uut/Active_handshake_done
add wave -noupdate /unit_L2_state_tb/uut/next_state
add wave -noupdate /unit_L2_state_tb/uut/state_req
add wave -noupdate /unit_L2_state_tb/uut/active_handshake_strt
add wave -noupdate /unit_L2_state_tb/uut/massage_send
add wave -noupdate /unit_L2_state_tb/uut/cs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {440117 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 253
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
WaveRestoreZoom {332257 ps} {547977 ps}
