onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_VALTRAINVREF_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_VALTRAINVREF_tb/ltsm_tb_attachments_inst/sb_clk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_VALTRAINVREF_tb/lclk
add wave -noupdate -expand -group {Control} -color Gold -itemcolor Gold /unit_VALTRAINVREF_tb/intf/valtrainvref_en
add wave -noupdate -expand -group {Control} -color Gold -itemcolor Gold /unit_VALTRAINVREF_tb/intf/valtrainvref_done
add wave -noupdate -expand -group {Control} -color {Indian Red} -itemcolor {Indian Red} /unit_VALTRAINVREF_tb/intf/valtraincenter_fail_flag
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_VALTRAINVREF_tb/current_state
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_VALTRAINVREF_tb/unit_VALTRAINVREF_inst/d2c_if/rx_pt_en
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_VALTRAINVREF_tb/unit_VALTRAINVREF_inst/d2c_if/tx_pt_en
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINVREF_tb/ltsm_tb_attachments_inst/tx_sb_msg_valid_pulse
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINVREF_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg_valid
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_VALTRAINVREF_tb/intf/tb_val_err
add wave -noupdate -expand -group {Vref Sweep} -color Gold -itemcolor Gold -radix unsigned /unit_VALTRAINVREF_tb/intf/phy_rx_valvref_ctrl
add wave -noupdate -expand -group {Vref Sweep} -color Gold -itemcolor Gold /unit_VALTRAINVREF_tb/unit_VALTRAINVREF_inst/vref_code_filled
add wave -noupdate -expand -group {Vref Sweep} -color Gold -itemcolor Gold /unit_VALTRAINVREF_tb/unit_VALTRAINVREF_inst/is_in_valid_region
add wave -noupdate -expand -group {Vref Calculation} -color Cyan -itemcolor Cyan -radix unsigned /unit_VALTRAINVREF_tb/unit_VALTRAINVREF_inst/min_vref_code
add wave -noupdate -expand -group {Vref Calculation} -color Gold -itemcolor Gold -radix unsigned /unit_VALTRAINVREF_tb/unit_VALTRAINVREF_inst/max_vref_code
add wave -noupdate -expand -group {Vref Calculation} -color Gold -itemcolor Gold -radix unsigned /unit_VALTRAINVREF_tb/unit_VALTRAINVREF_inst/vref_range
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_VALTRAINVREF_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_VALTRAINVREF_tb/intf/trainerror_req
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_VALTRAINVREF_tb/intf/valtrainvref_fail_flag
TreeUpdate [SetDefaultTree]
quietly wave cursor active 2
configure wave -namecolwidth 295
configure wave -valuecolwidth 197
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
WaveRestoreZoom {0 ps} {1992494 ps}
