onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /testbench/lclk
add wave -noupdate -divider {Adapter interface}
add wave -noupdate -color Gold -itemcolor Gold /testbench/lp_awak_req
add wave -noupdate -color Gold -itemcolor Gold /testbench/pl_awak_ack
add wave -noupdate -divider {Ungaing block interface}
add wave -noupdate /testbench/ungating_done
add wave -noupdate /testbench/ungating_req
add wave -noupdate -divider state
add wave -noupdate -color Blue -itemcolor Blue /testbench/DUT/AWAK_cs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {19 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 201
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
WaveRestoreZoom {0 ns} {253 ns}
