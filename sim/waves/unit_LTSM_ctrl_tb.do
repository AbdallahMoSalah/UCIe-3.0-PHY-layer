onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} /unit_unit_LTSM_ctrl_tb/lclk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_unit_LTSM_ctrl_tb/rst_n
add wave -noupdate -expand -group {RDI Interface} -color Cyan -itemcolor Cyan /unit_unit_LTSM_ctrl_tb/state_req
add wave -noupdate -expand -group {RDI Interface} -color Cyan -itemcolor Cyan /unit_unit_LTSM_ctrl_tb/state_status
add wave -noupdate -expand -group {Timers} -color Yellow -itemcolor Yellow /unit_unit_LTSM_ctrl_tb/timeout_timer_en
add wave -noupdate -expand -group {Timers} -color Yellow -itemcolor Yellow /unit_unit_LTSM_ctrl_tb/timeout_8ms_occured
add wave -noupdate -expand -group {MBTRAIN Sub-State} -color Gold -itemcolor Gold /unit_unit_LTSM_ctrl_tb/mbtrain_en
add wave -noupdate -expand -group {MBTRAIN Sub-State} -color Gold -itemcolor Gold /unit_unit_LTSM_ctrl_tb/mbtrain_done
add wave -noupdate -expand -group {MBTRAIN Sub-State} -color Orange -itemcolor Orange /unit_unit_LTSM_ctrl_tb/mbtrain_fail
add wave -noupdate -expand -group {Internal FSM} -color Magenta -itemcolor Magenta /unit_unit_LTSM_ctrl_tb/dut/current_state
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

