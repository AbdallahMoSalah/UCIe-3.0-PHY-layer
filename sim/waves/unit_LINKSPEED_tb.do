onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_LINKSPEED_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_LINKSPEED_tb/lclk
add wave -noupdate -expand -group {Control} -color Gold -itemcolor Gold /unit_LINKSPEED_tb/intf/linkspeed_en
add wave -noupdate -expand -group {Control} -color Gold -itemcolor Gold /unit_LINKSPEED_tb/intf/linkspeed_done
add wave -noupdate -expand -group {Control} -color {Spring Green} -itemcolor {Spring Green} /unit_LINKSPEED_tb/intf/phy_negotiated_speed
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_LINKSPEED_tb/current_state
add wave -noupdate -expand -group {Data Path} -color Cyan -itemcolor Cyan /unit_LINKSPEED_tb/unit_LINKSPEED_inst/d2c_fail_r
add wave -noupdate -expand -group {Data Path} -color Violet -itemcolor Violet /unit_LINKSPEED_tb/unit_LINKSPEED_inst/req_speed_degrade_r
add wave -noupdate -expand -group {Data Path} -color Violet -itemcolor Violet /unit_LINKSPEED_tb/unit_LINKSPEED_inst/dont_wait_req
add wave -noupdate -expand -group {Width Degrade} -color Gold -itemcolor Gold -radix hexadecimal /unit_LINKSPEED_tb/unit_LINKSPEED_inst/negotiated_data_lanes
add wave -noupdate -expand -group {Width Degrade} -color Gold -itemcolor Gold -radix hexadecimal /unit_LINKSPEED_tb/unit_LINKSPEED_inst/active_lanes
add wave -noupdate -expand -group {Width Degrade} -color Cyan -itemcolor Cyan /unit_LINKSPEED_tb/intf/rf_cap_SPMW
add wave -noupdate -expand -group {Width Degrade} -color Cyan -itemcolor Cyan -radix unsigned /unit_LINKSPEED_tb/intf/rf_ctrl_target_link_width
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_LINKSPEED_tb/unit_LINKSPEED_inst/d2c_if/tx_pt_en
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_LINKSPEED_tb/unit_LINKSPEED_inst/d2c_if/test_d2c_done
add wave -noupdate -expand -group {D2C Interface} -color Orange -itemcolor Orange -radix hexadecimal /unit_LINKSPEED_tb/unit_LINKSPEED_inst/d2c_if/d2c_perlane_err
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_LINKSPEED_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_LINKSPEED_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_LINKSPEED_tb/intf/rx_sb_msg_valid
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_LINKSPEED_tb/intf/tx_sb_msg_valid
add wave -noupdate -expand -group {PHY Retrain} -color {Medium Spring Green} -itemcolor {Medium Spring Green} /unit_LINKSPEED_tb/intf/phyretrain_PHY_IN_RETRAIN
add wave -noupdate -expand -group {PHY Retrain} -color {Medium Spring Green} -itemcolor {Medium Spring Green} /unit_LINKSPEED_tb/intf/linkspeed_PHY_IN_RETRAIN
add wave -noupdate -expand -group {PHY Retrain} -color {Medium Spring Green} -itemcolor {Medium Spring Green} /unit_LINKSPEED_tb/intf/params_changed
add wave -noupdate -expand -group {Exit Requests} -color Orange -itemcolor Orange /unit_LINKSPEED_tb/intf/linkinit_req
add wave -noupdate -expand -group {Exit Requests} -color Orange -itemcolor Orange /unit_LINKSPEED_tb/intf/repair_req
add wave -noupdate -expand -group {Exit Requests} -color Orange -itemcolor Orange /unit_LINKSPEED_tb/intf/speedidle_req
add wave -noupdate -expand -group {Exit Requests} -color Orange -itemcolor Orange /unit_LINKSPEED_tb/intf/phyretrain_req
add wave -noupdate -expand -group {Exit Requests} -color Orange -itemcolor Orange /unit_LINKSPEED_tb/intf/trainerror_req
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_LINKSPEED_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {SB Timer} -color Yellow -itemcolor Yellow -radix unsigned /unit_LINKSPEED_tb/unit_LINKSPEED_inst/send_timer
add wave -noupdate -expand -group {Lane Control} -color {Medium Spring Green} -itemcolor {Medium Spring Green} /unit_LINKSPEED_tb/intf/mb_tx_clk_lane_sel
add wave -noupdate -expand -group {Lane Control} -color {Medium Spring Green} -itemcolor {Medium Spring Green} /unit_LINKSPEED_tb/intf/mb_tx_data_lane_sel
add wave -noupdate -expand -group {Lane Control} -color {Medium Spring Green} -itemcolor {Medium Spring Green} /unit_LINKSPEED_tb/intf/mb_tx_val_lane_sel
TreeUpdate [SetDefaultTree]
quietly wave cursor active 1
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
WaveRestoreZoom {0 ps} {10000000 ps}
