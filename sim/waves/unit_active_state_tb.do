onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_active_state_tb/dut/lclk
add wave -noupdate /unit_active_state_tb/dut/rst_n
add wave -noupdate /unit_active_state_tb/dut/EN
add wave -noupdate -divider {massage interface}
add wave -noupdate /unit_active_state_tb/dut/massage_recieve
add wave -noupdate /unit_active_state_tb/dut/massage_send
add wave -noupdate -divider {stall handshake interface}
add wave -noupdate -color coral -itemcolor coral /unit_active_state_tb/dut/stall_req
add wave -noupdate -color coral -itemcolor coral /unit_active_state_tb/dut/stall_done
add wave -noupdate -divider {other controll siganls}
add wave -noupdate -color violet -itemcolor violet /unit_active_state_tb/dut/lp_state_req
add wave -noupdate -color violet -itemcolor violet /unit_active_state_tb/dut/lp_linkerror
add wave -noupdate -color violet -itemcolor violet /unit_active_state_tb/dut/timeout_1us
add wave -noupdate -color violet -itemcolor violet /unit_active_state_tb/dut/start_1us_timer
add wave -noupdate -divider {state corner}
add wave -noupdate -color blue -itemcolor blue /unit_active_state_tb/dut/next_state
add wave -noupdate -color blue -itemcolor blue /unit_active_state_tb/dut/cs
add wave -noupdate -color blue -itemcolor blue /unit_active_state_tb/dut/flow
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {99313 ps} 0} {{Cursor 2} {19160 ps} 0}
quietly wave cursor active 2
configure wave -namecolwidth 227
configure wave -valuecolwidth 221
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
WaveRestoreZoom {0 ps} {99313 ps}
