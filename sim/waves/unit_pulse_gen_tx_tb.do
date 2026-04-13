onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_pulse_gen_tx_tb/lclk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_pulse_gen_tx_tb/rst_n
add wave -noupdate -expand -group {Control & Data} /unit_pulse_gen_tx_tb/pulse_in
add wave -noupdate -expand -group {Control & Data} /unit_pulse_gen_tx_tb/pulse_out
add wave -noupdate -expand -group {Control & Data} /unit_pulse_gen_tx_tb/dut/active
add wave -noupdate -expand -group {Timers & Counters} -color Yellow -itemcolor Yellow -radix unsigned /unit_pulse_gen_tx_tb/dut/counter
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 300
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
WaveRestoreZoom {0 ps} {100 ns}

