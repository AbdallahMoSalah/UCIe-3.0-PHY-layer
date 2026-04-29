onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TXSELFCAL_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TXSELFCAL_tb/ltsm_tb_attachments_inst/sb_clk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TXSELFCAL_tb/lclk

add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_TXSELFCAL_tb/intf/txselfcal_en
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_TXSELFCAL_tb/intf/txselfcal_done
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_TXSELFCAL_tb/current_state

add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TXSELFCAL_tb/ltsm_tb_attachments_inst/tx_sb_msg_valid_pulse
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TXSELFCAL_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TXSELFCAL_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TXSELFCAL_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg_valid

add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TXSELFCAL_tb/intf/mb_tx_clk_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TXSELFCAL_tb/intf/mb_tx_data_lane_sel

add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TXSELFCAL_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TXSELFCAL_tb/intf/trainerror_req

TreeUpdate [SetDefaultTree]
quietly wave cursor active 1
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
