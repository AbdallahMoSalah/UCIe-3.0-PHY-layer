onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_VALTRAINCENTER_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_VALTRAINCENTER_tb/ltsm_tb_attachments_inst/sb_clk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_VALTRAINCENTER_tb/lclk
add wave -noupdate -expand -group {Phase Operations} -color Gold -itemcolor Gold -radix unsigned /unit_VALTRAINCENTER_tb/intf/valtraincenter_en
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_VALTRAINCENTER_tb/current_state
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_VALTRAINCENTER_tb/unit_VALTRAINCENTER_inst/d2c_if/rx_pt_en
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_VALTRAINCENTER_tb/unit_VALTRAINCENTER_inst/d2c_if/tx_pt_en
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINCENTER_tb/ltsm_tb_attachments_inst/tx_sb_msg_valid_pulse
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINCENTER_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINCENTER_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINCENTER_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_VALTRAINCENTER_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg_valid
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_VALTRAINCENTER_tb/intf/tb_val_err
add wave -noupdate -expand -group {Phase Operations} -color Gold -itemcolor Gold -radix unsigned /unit_VALTRAINCENTER_tb/intf/phy_tx_pi_phase_ctrl
add wave -noupdate -expand -group {Phase Operations} -color Gold -itemcolor Gold /unit_VALTRAINCENTER_tb/unit_VALTRAINCENTER_inst/phase_code_filled
add wave -noupdate -expand -group {Phase Operations} -color Gold -itemcolor Gold /unit_VALTRAINCENTER_tb/unit_VALTRAINCENTER_inst/is_in_valid_region
add wave -noupdate -expand -group {Phase Calculation} -color Cyan -itemcolor Cyan -radix unsigned /unit_VALTRAINCENTER_tb/unit_VALTRAINCENTER_inst/min_phase_code
add wave -noupdate -expand -group {Phase Calculation} -color Gold -itemcolor Gold -radix unsigned /unit_VALTRAINCENTER_tb/unit_VALTRAINCENTER_inst/max_phase_code
add wave -noupdate -expand -group {Phase Calculation} -color Gold -itemcolor Gold -radix unsigned /unit_VALTRAINCENTER_tb/unit_VALTRAINCENTER_inst/phase_range
add wave -noupdate -expand -group {Phase Operations} -color Gold -itemcolor Gold /unit_VALTRAINCENTER_tb/intf/valtraincenter_done
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_VALTRAINCENTER_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_VALTRAINCENTER_tb/intf/trainerror_req
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_VALTRAINCENTER_tb/intf/valtraincenter_fail_flag
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
