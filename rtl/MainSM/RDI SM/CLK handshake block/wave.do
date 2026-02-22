onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /testbench/lclk
add wave -noupdate -divider {adapter interface}
add wave -noupdate -color Red -itemcolor Red /testbench/pl_clk_req
add wave -noupdate -color Red -itemcolor Red /testbench/lp_clk_ack
add wave -noupdate -divider {interface with main controller}
add wave -noupdate /testbench/clk_handshake_strt
add wave -noupdate /testbench/clk_handshake_done
add wave -noupdate -divider state
add wave -noupdate -color Blue -itemcolor Blue /testbench/DUT/CLK_cs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {125 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 282
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
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
WaveRestoreZoom {0 ns} {221 ns}
