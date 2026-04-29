onerror {resume}
quietly WaveActivateNextPane {} 0

# ─────────────────────────────────────────────────────────────────────────────
# Group: Clock & Reset
# ─────────────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_RXCLKCAL_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_RXCLKCAL_tb/ltsm_tb_attachments_inst/sb_clk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_RXCLKCAL_tb/lclk

# ─────────────────────────────────────────────────────────────────────────────
# Group: RXCLKCAL Control
# ─────────────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_RXCLKCAL_tb/intf/rxclkcal_en
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_RXCLKCAL_tb/intf/rxclkcal_done
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_negotiated_speed

# ─────────────────────────────────────────────────────────────────────────────
# Group: FSM State
# ─────────────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_RXCLKCAL_tb/current_state

# ─────────────────────────────────────────────────────────────────────────────
# Group: SB Messages
# ─────────────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_RXCLKCAL_tb/ltsm_tb_attachments_inst/tx_sb_msg_valid_pulse
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_RXCLKCAL_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_RXCLKCAL_tb/intf/tx_msginfo
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_RXCLKCAL_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_RXCLKCAL_tb/intf/rx_msginfo
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_RXCLKCAL_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg_valid

# ─────────────────────────────────────────────────────────────────────────────
# Group: MB Lane Control
# ─────────────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_RXCLKCAL_tb/intf/mb_tx_clk_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_RXCLKCAL_tb/intf/mb_tx_trk_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_RXCLKCAL_tb/intf/mb_tx_data_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_RXCLKCAL_tb/intf/mb_tx_val_lane_sel
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_RXCLKCAL_tb/intf/mb_rx_clk_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_RXCLKCAL_tb/intf/mb_rx_trk_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_RXCLKCAL_tb/intf/mb_tx_pattern_en

# ─────────────────────────────────────────────────────────────────────────────
# Group: PHY IQ Calibration Signals
# ─────────────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_rx_clock_lock_en
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_rx_track_lock_en
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_rx_phase_detector_en
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_tx_tckn_shift_en
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_rx_tckn_shift
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_rx_decrement_shift
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_tx_tckn_shift
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_tx_decrement_shift
add wave -noupdate -expand -group {PHY Operations} -color Plum -itemcolor Plum /unit_RXCLKCAL_tb/intf/phy_tx_tckn_shift_out_of_range

# ─────────────────────────────────────────────────────────────────────────────
# Group: Timers
# ─────────────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_RXCLKCAL_tb/intf/timeout_timer_en
add wave -noupdate -expand -group {Timers & Counters} -color Yellow -itemcolor Yellow /unit_RXCLKCAL_tb/intf/analog_settle_timer_en
add wave -noupdate -expand -group {Control & Data} /unit_RXCLKCAL_tb/intf/analog_settle_time_done

# ─────────────────────────────────────────────────────────────────────────────
# Group: Errors & Alerts
# ─────────────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_RXCLKCAL_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_RXCLKCAL_tb/intf/trainerror_req

TreeUpdate [SetDefaultTree]
quietly wave cursor active 1
configure wave -namecolwidth 400
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
