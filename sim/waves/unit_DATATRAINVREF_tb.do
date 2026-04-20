onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_DATATRAINVREF_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_DATATRAINVREF_tb/lclk
add wave -noupdate -expand -group {Control} -color Gold /unit_DATATRAINVREF_tb/intf/datatrainvref_en
add wave -noupdate -expand -group {Control} -color Gold /unit_DATATRAINVREF_tb/intf/datatrainvref_done
add wave -noupdate -expand -group {Control} -color {Indian Red} /unit_DATATRAINVREF_tb/intf/datatrainvref_fail_flag
add wave -noupdate -expand -group {S2 Skip Inputs} -color Orange /unit_DATATRAINVREF_tb/intf/datatraincenter1_fail_flag
add wave -noupdate -expand -group {S2 Skip Inputs} -color Orange /unit_DATATRAINVREF_tb/intf/valtraincenter_fail_flag
add wave -noupdate -expand -group {FSM States} -color Magenta /unit_DATATRAINVREF_tb/current_state
add wave -noupdate -expand -group {Vref Sweep} -color Gold -radix unsigned /unit_DATATRAINVREF_tb/intf/phy_rx_datavref_ctrl
add wave -noupdate -expand -group {Vref Sweep} -color Cyan -radix unsigned /unit_DATATRAINVREF_tb/unit_DATATRAINVREF_inst/min_vref_code
add wave -noupdate -expand -group {Vref Sweep} -color Cyan -radix unsigned /unit_DATATRAINVREF_tb/unit_DATATRAINVREF_inst/max_vref_code
add wave -noupdate -expand -group {Vref Sweep} -color Violet /unit_DATATRAINVREF_tb/unit_DATATRAINVREF_inst/vref_code_filled
add wave -noupdate -expand -group {D2C Interface} -color Violet /unit_DATATRAINVREF_tb/intf/rx_pt_en
add wave -noupdate -expand -group {D2C Interface} -color Violet /unit_DATATRAINVREF_tb/intf/test_d2c_done
add wave -noupdate -expand -group {SB Messages} -color Cyan /unit_DATATRAINVREF_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan /unit_DATATRAINVREF_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_DATATRAINVREF_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_DATATRAINVREF_tb/intf/trainerror_req
TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 295
configure wave -valuecolwidth 197
configure wave -signalnamewidth 1
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {10000000 ps}
