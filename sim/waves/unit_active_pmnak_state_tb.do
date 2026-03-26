onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_active_pmnak_state_tb/uut/lclk
add wave -noupdate /unit_active_pmnak_state_tb/uut/rst_n
add wave -noupdate /unit_active_pmnak_state_tb/uut/EN
add wave -noupdate /unit_active_pmnak_state_tb/uut/lp_linkerror
add wave -noupdate /unit_active_pmnak_state_tb/uut/lp_state_req
add wave -noupdate -divider {massage handler if}
add wave -noupdate -color coral -itemcolor coral /unit_active_pmnak_state_tb/uut/massage_recieve
add wave -noupdate -color coral -itemcolor coral /unit_active_pmnak_state_tb/uut/massage_send
add wave -noupdate -divider {stall handshake if}
add wave -noupdate -color violet -itemcolor violet /unit_active_pmnak_state_tb/uut/stall_done
add wave -noupdate -color violet -itemcolor violet /unit_active_pmnak_state_tb/uut/stall_req
add wave -noupdate -divider {state and flows}
add wave -noupdate -color blue -itemcolor blue /unit_active_pmnak_state_tb/uut/next_state
add wave -noupdate -color blue -itemcolor blue /unit_active_pmnak_state_tb/uut/cs
add wave -noupdate -color blue -itemcolor blue /unit_active_pmnak_state_tb/uut/flow
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {53656 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 191
configure wave -valuecolwidth 189
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
WaveRestoreZoom {0 ps} {422159 ps}
