onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_DATATRAINCENTER1_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_DATATRAINCENTER1_tb/lclk
add wave -noupdate -expand -group {Control} -color Gold /unit_DATATRAINCENTER1_tb/intf/datatraincenter1_en
add wave -noupdate -expand -group {Control} -color Gold /unit_DATATRAINCENTER1_tb/intf/datatraincenter1_done
add wave -noupdate -expand -group {Control} -color {Indian Red} /unit_DATATRAINCENTER1_tb/intf/datatraincenter1_fail_flag
add wave -noupdate -expand -group {FSM States} -color Magenta /unit_DATATRAINCENTER1_tb/current_state
add wave -noupdate -expand -group {Phase Sweep} -color Gold -radix unsigned /unit_DATATRAINCENTER1_tb/unit_DATATRAINCENTER1_inst/swept_code_r
add wave -noupdate -expand -group {Phase Sweep} -color Cyan -radix unsigned {/unit_DATATRAINCENTER1_tb/unit_DATATRAINCENTER1_inst/best_lo[0]}
add wave -noupdate -expand -group {Phase Sweep} -color Cyan -radix unsigned {/unit_DATATRAINCENTER1_tb/unit_DATATRAINCENTER1_inst/best_hi[0]}
add wave -noupdate -expand -group {Phase Sweep} -color Violet {/unit_DATATRAINCENTER1_tb/unit_DATATRAINCENTER1_inst/found_pass[0]}
add wave -noupdate -expand -group {Phase Sweep} -color {Spring Green} -radix unsigned {/unit_DATATRAINCENTER1_tb/unit_DATATRAINCENTER1_inst/best_code_r[0]}
add wave -noupdate -expand -group {Phase Sweep} -color Gold -radix unsigned /unit_DATATRAINCENTER1_tb/intf/phy_tx_pi_phase_ctrl
add wave -noupdate -expand -group {D2C Interface} -color Violet {/unit_DATATRAINCENTER1_tb/unit_DATATRAINCENTER1_inst/d2c_if/tx_pt_en}
add wave -noupdate -expand -group {D2C Interface} -color Violet /unit_DATATRAINCENTER1_tb/intf/test_d2c_done
add wave -noupdate -expand -group {D2C Interface} -radix hex /unit_DATATRAINCENTER1_tb/intf/d2c_perlane_err
add wave -noupdate -expand -group {SB Messages} -color Cyan /unit_DATATRAINCENTER1_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan /unit_DATATRAINCENTER1_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan /unit_DATATRAINCENTER1_tb/intf/rx_sb_msg_valid
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_DATATRAINCENTER1_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_DATATRAINCENTER1_tb/intf/trainerror_req
TreeUpdate [SetDefaultTree]
quietly wave cursor active 2
configure wave -namecolwidth 350
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
