onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider clks
add wave -noupdate /testbench/lclk
add wave -noupdate /testbench/lclk_g
add wave -noupdate -divider inputs
add wave -noupdate -color coral -itemcolor coral /testbench/pl_phyinrecenter
add wave -noupdate -color coral -itemcolor coral /testbench/pl_clk_req
add wave -noupdate -color coral -itemcolor coral /testbench/ungating_req
add wave -noupdate -divider output
add wave -noupdate /testbench/ungating_done
add wave -noupdate -divider states
add wave -noupdate -color blue -itemcolor blue /testbench/pl_state_sts
add wave -noupdate -color blue -itemcolor blue /testbench/DUT/GATING_cs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
configure wave -namecolwidth 174
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
WaveRestoreZoom {0 ns} {979 ns}
