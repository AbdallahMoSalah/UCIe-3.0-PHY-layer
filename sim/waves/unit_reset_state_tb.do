onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_reset_state_tb/dut/lclk
add wave -noupdate /unit_reset_state_tb/dut/EN
add wave -noupdate -divider {active handshake if}
add wave -noupdate -color coral -itemcolor coral /unit_reset_state_tb/dut/Active_handshake_strt
add wave -noupdate -color coral -itemcolor coral /unit_reset_state_tb/dut/Active_handshake_done
add wave -noupdate -divider {basic controllers}
add wave -noupdate -color violet -itemcolor violet /unit_reset_state_tb/dut/lp_linkerror
add wave -noupdate -color violet -itemcolor violet /unit_reset_state_tb/dut/lp_state_req
add wave -noupdate -color violet -itemcolor violet /unit_reset_state_tb/dut/state_sts
add wave -noupdate -divider {sb if}
add wave -noupdate /unit_reset_state_tb/dut/message_receive
add wave -noupdate /unit_reset_state_tb/dut/message_send
add wave -noupdate -divider {state transition}
add wave -noupdate -color blue -itemcolor blue /unit_reset_state_tb/dut/next_state
add wave -noupdate -color blue -itemcolor blue /unit_reset_state_tb/dut/cs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {155530 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 336
configure wave -valuecolwidth 215
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
WaveRestoreZoom {0 ps} {290629 ps}
