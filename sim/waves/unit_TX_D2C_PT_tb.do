onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/mb_rx_compare_done
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/lclk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/sb_clk
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/rx_sb_msg_valid
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/rx_sb_msg_enum
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/tx_sb_msg_valid
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/tx_sb_msg_enum
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_TX_D2C_PT_tb/current_state
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_TX_D2C_PT_tb/previous_state
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/tx_pt_trigger
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/wait_timeout
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/timeout_8ms
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/test_d2c_done
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan -radix decimal /unit_TX_D2C_PT_tb/sb_msg_waiting_time
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/receive_wrong_sb_msg
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/wrong_sb_msg_value
add wave -noupdate -expand -group timeout -color Pink -itemcolor Plum -radix unsigned -subitemconfig {{/unit_TX_D2C_PT_tb/lclk_counter[31]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[30]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[29]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[28]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[27]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[26]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[25]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[24]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[23]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[22]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[21]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[20]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[19]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[18]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[17]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[16]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[15]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[14]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[13]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[12]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[11]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[10]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[9]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[8]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[7]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[6]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[5]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[4]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[3]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[2]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[1]} {-color Pink -itemcolor Plum} {/unit_TX_D2C_PT_tb/lclk_counter[0]} {-color Pink -itemcolor Plum}} /unit_TX_D2C_PT_tb/lclk_counter
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} -radix unsigned /unit_TX_D2C_PT_tb/lclk_counter_run_flag
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/start_test/wrong_sb_msg
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/lclk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/rst_n
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/tx_pt_trigger
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/timeout_8ms
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/test_d2c_done
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_clk_sampling_en
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_clk_sampling
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_pattern_en
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_pattern_setup
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_data_pattern_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_val_pattern_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_lfsr_en
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_lfsr_rst
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_lfsr_en
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_lfsr_rst
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_pattern_mode
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_burst_count
add wave -noupdate -expand -group {Timers & Counters} -color Yellow -itemcolor Yellow /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_idle_count
add wave -noupdate -expand -group {Timers & Counters} -color Yellow -itemcolor Yellow /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_iter_count
add wave -noupdate -expand -group {Timers & Counters} -color Yellow -itemcolor Yellow /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_pattern_count_done
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_compare_en
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_max_err_thresh_aggr
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_max_err_thresh_perlane
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_compare_setup
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_aggr_err
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_perlane_err
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_val_err
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_clk_err
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_compare_done
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_clk_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_data_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_val_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_tx_trk_lane_sel
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_clk_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_data_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_val_lane_sel
add wave -noupdate -expand -group {MB Interface} -color Pink -itemcolor Pink /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/mb_rx_trk_lane_sel
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_clk_sampling
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_timeout_or_error
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_lfsr_en
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_pattern_setup
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_data_pattern_sel
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_pattern_mode
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_burst_count
add wave -noupdate -expand -group {Timers & Counters} -color Yellow -itemcolor Yellow /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_idle_count
add wave -noupdate -expand -group {Timers & Counters} -color Yellow -itemcolor Yellow /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_iter_count
add wave -noupdate -expand -group {D2C Interface} -color Violet -itemcolor Violet /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_compare_setup
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_aggr_err
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_perlane_err
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_val_err
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} -itemcolor {Spring Green} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/d2c_clk_err
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/tx_sb_msg_valid
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/tx_msginfo
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/tx_data_field
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/rx_sb_msg_valid
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/rx_msginfo
add wave -noupdate -expand -group {SB Messages} -color Cyan -itemcolor Cyan /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/rx_data_field
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/cfg_train4_max_err_thresh_perlane
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/cfg_train4_max_err_thresh_aggr
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/current_state
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/next_state
add wave -noupdate -expand -group {FSM States} -color Magenta -itemcolor Magenta /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/previous_state
add wave -noupdate -expand -group {Errors & Alerts} -color Orange -itemcolor Orange /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/data_incoherence
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {82157 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 234
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
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {1088583 ps}


