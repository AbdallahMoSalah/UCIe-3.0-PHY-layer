onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} /unit_unit_pulse_gen_tx_tb/lclk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_unit_pulse_gen_tx_tb/rst_n
add wave -noupdate -expand -group {Pulse Control} -color Yellow -itemcolor Yellow /unit_unit_pulse_gen_tx_tb/pulse_in
add wave -noupdate -expand -group {Pulse Control} -color Magenta -itemcolor Magenta /unit_unit_pulse_gen_tx_tb/pulse_out
add wave -noupdate -expand -group {Pulse Control} -color Cyan -itemcolor Cyan /unit_unit_pulse_gen_tx_tb/dut/active
add wave -noupdate -expand -group {Internal} -color Cyan -itemcolor Cyan -radix unsigned /unit_unit_pulse_gen_tx_tb/dut/counter
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

