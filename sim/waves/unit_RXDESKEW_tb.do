onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_RXDESKEW_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_RXDESKEW_tb/lclk
add wave -noupdate -expand -group {Control} -color Gold /unit_RXDESKEW_tb/intf/rxdeskew_en
add wave -noupdate -expand -group {Control} -color Gold /unit_RXDESKEW_tb/intf/rxdeskew_done
add wave -noupdate -expand -group {Control} -color {Indian Red} /unit_RXDESKEW_tb/intf/rxdeskew_fail_flag
add wave -noupdate -expand -group {Control} -color Orange /unit_RXDESKEW_tb/intf/datatraincenter1_req
add wave -noupdate -expand -group {Upstream Flags} -color Orange /unit_RXDESKEW_tb/intf/datatraincenter1_fail_flag
add wave -noupdate -expand -group {Upstream Flags} -color Orange /unit_RXDESKEW_tb/intf/valtraincenter_fail_flag
add wave -noupdate -expand -group {Speed} -radix unsigned /unit_RXDESKEW_tb/intf/param_negotiated_max_speed
add wave -noupdate -expand -group {FSM States} -color Magenta /unit_RXDESKEW_tb/current_state
add wave -noupdate -expand -group {Deskew Sweep} -color Gold -radix unsigned /unit_RXDESKEW_tb/unit_RXDESKEW_inst/deskew_code
add wave -noupdate -expand -group {Deskew Sweep} -color Cyan -radix unsigned /unit_RXDESKEW_tb/unit_RXDESKEW_inst/min_deskew
add wave -noupdate -expand -group {Deskew Sweep} -color Cyan -radix unsigned /unit_RXDESKEW_tb/unit_RXDESKEW_inst/max_deskew
add wave -noupdate -expand -group {EQ Preset} -color Violet -radix unsigned /unit_RXDESKEW_tb/unit_RXDESKEW_inst/current_eq_preset
add wave -noupdate -expand -group {EQ Preset} -color Violet -radix unsigned /unit_RXDESKEW_tb/unit_RXDESKEW_inst/dtc1_loop_cnt
add wave -noupdate -expand -group {EQ Preset} -color Gold /unit_RXDESKEW_tb/unit_RXDESKEW_inst/is_my_preset_new
add wave -noupdate -expand -group {EQ Preset} -color {Indian Red} /unit_RXDESKEW_tb/unit_RXDESKEW_inst/preset_fail_flag2
add wave -noupdate -expand -group {D2C Interface} -color Violet /unit_RXDESKEW_tb/intf/rx_pt_en
add wave -noupdate -expand -group {D2C Interface} -color Violet /unit_RXDESKEW_tb/intf/test_d2c_done
add wave -noupdate -expand -group {SB Messages} -color Cyan /unit_RXDESKEW_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan /unit_RXDESKEW_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_RXDESKEW_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_RXDESKEW_tb/intf/trainerror_req
TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 295
configure wave -valuecolwidth 197
configure wave -signalnamewidth 1
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {10000000 ps}
