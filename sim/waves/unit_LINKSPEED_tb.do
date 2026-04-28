onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_LINKSPEED_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_LINKSPEED_tb/lclk
add wave -noupdate -expand -group {Control} -color Gold      /unit_LINKSPEED_tb/intf/linkspeed_en
add wave -noupdate -expand -group {Control} -color Gold      /unit_LINKSPEED_tb/intf/linkspeed_done
add wave -noupdate -expand -group {Control} -color Orange    /unit_LINKSPEED_tb/intf/linkspeed_fail_flag
add wave -noupdate -expand -group {Control} -color {Spring Green} /unit_LINKSPEED_tb/intf/phy_negotiated_speed
add wave -noupdate -expand -group {FSM States} -color Magenta /unit_LINKSPEED_tb/current_state
add wave -noupdate -expand -group {Fail Flags} -color Orange  /unit_LINKSPEED_tb/intf/datatraincenter2_fail_flag
add wave -noupdate -expand -group {Fail Flags} -color Orange  /unit_LINKSPEED_tb/intf/datatrainvref_fail_flag
add wave -noupdate -expand -group {Fail Flags} -color Orange  /unit_LINKSPEED_tb/intf/valtrainvref_fail_flag
add wave -noupdate -expand -group {Fail Flags} -color Orange  /unit_LINKSPEED_tb/intf/valtraincenter_fail_flag
add wave -noupdate -expand -group {Data Path} -color Cyan    /unit_LINKSPEED_tb/unit_LINKSPEED_inst/speed_r
add wave -noupdate -expand -group {Data Path} -color Violet  /unit_LINKSPEED_tb/unit_LINKSPEED_inst/any_train_fail_r
add wave -noupdate -expand -group {Data Path} -color Violet  /unit_LINKSPEED_tb/unit_LINKSPEED_inst/eq_needed_r
add wave -noupdate -expand -group {Data Path} -color Violet  /unit_LINKSPEED_tb/unit_LINKSPEED_inst/fail_flag_r
add wave -noupdate -expand -group {SB Messages} -color Cyan  /unit_LINKSPEED_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan  /unit_LINKSPEED_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan  /unit_LINKSPEED_tb/intf/rx_sb_msg_valid
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_LINKSPEED_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_LINKSPEED_tb/intf/trainerror_req
TreeUpdate [SetDefaultTree]
quietly wave cursor active 2
configure wave -namecolwidth 380
configure wave -valuecolwidth 200
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
WaveRestoreZoom {0 ps} {5000000 ps}
