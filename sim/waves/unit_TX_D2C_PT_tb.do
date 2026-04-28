onerror {resume}
quietly WaveActivateNextPane {} 0

# ── Clock & Reset ──
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_TX_D2C_PT_tb/lclk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_TX_D2C_PT_tb/sb_clk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_TX_D2C_PT_tb/rst_n

# ── FSM States ──
add wave -noupdate -expand -group {FSM States} -color Magenta /unit_TX_D2C_PT_tb/state_monitor
add wave -noupdate -expand -group {FSM States} -color Magenta /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/current_state
add wave -noupdate -expand -group {FSM States} -color Magenta /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/next_state
add wave -noupdate -expand -group {FSM States} -color Magenta /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/previous_state
add wave -noupdate -expand -group {FSM States} -color {Pale Violet Red} /unit_TX_D2C_PT_tb/unit_TX_D2C_PT_inst/data_incoherence

# ── D2C Substate Control ──
add wave -noupdate -expand -group {D2C Control} -color Gold /unit_TX_D2C_PT_tb/intf/tx_pt_en
add wave -noupdate -expand -group {D2C Control} -color Gold /unit_TX_D2C_PT_tb/intf/test_d2c_done
add wave -noupdate -expand -group {D2C Control} -color Orange /unit_TX_D2C_PT_tb/intf/d2c_timeout_or_error

# ── D2C Configuration (from parent sub-state) ──
add wave -noupdate -expand -group {D2C Config} -color Violet -radix unsigned /unit_TX_D2C_PT_tb/intf/d2c_clk_sampling
add wave -noupdate -expand -group {D2C Config} -color Violet /unit_TX_D2C_PT_tb/intf/d2c_pattern_setup
add wave -noupdate -expand -group {D2C Config} -color Violet /unit_TX_D2C_PT_tb/intf/d2c_data_pattern_sel
add wave -noupdate -expand -group {D2C Config} -color Violet /unit_TX_D2C_PT_tb/intf/d2c_val_pattern_sel
add wave -noupdate -expand -group {D2C Config} -color Violet /unit_TX_D2C_PT_tb/intf/d2c_lfsr_en
add wave -noupdate -expand -group {D2C Config} -color Violet /unit_TX_D2C_PT_tb/intf/d2c_pattern_mode
add wave -noupdate -expand -group {D2C Config} -color Violet -radix unsigned /unit_TX_D2C_PT_tb/intf/d2c_burst_count
add wave -noupdate -expand -group {D2C Config} -color Violet -radix unsigned /unit_TX_D2C_PT_tb/intf/d2c_idle_count
add wave -noupdate -expand -group {D2C Config} -color Violet -radix unsigned /unit_TX_D2C_PT_tb/intf/d2c_iter_count
add wave -noupdate -expand -group {D2C Config} -color Violet /unit_TX_D2C_PT_tb/intf/d2c_compare_setup

# ── D2C Results (partner errors) ──
add wave -noupdate -expand -group {D2C Results} -color Orange /unit_TX_D2C_PT_tb/intf/d2c_partner_tx_fail_flag
add wave -noupdate -expand -group {D2C Results} -color Orange -radix hex /unit_TX_D2C_PT_tb/intf/d2c_perlane_err
add wave -noupdate -expand -group {D2C Results} -color Orange -radix hex /unit_TX_D2C_PT_tb/intf/d2c_aggr_err
add wave -noupdate -expand -group {D2C Results} -color Orange /unit_TX_D2C_PT_tb/intf/d2c_val_err

# ── SB Tx Messages ──
add wave -noupdate -expand -group {SB Tx} -color Cyan /unit_TX_D2C_PT_tb/intf/tx_sb_msg_valid
add wave -noupdate -expand -group {SB Tx} -color Cyan /unit_TX_D2C_PT_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Tx} -color Cyan -radix hex /unit_TX_D2C_PT_tb/intf/tx_msginfo
add wave -noupdate -expand -group {SB Tx} -color Cyan -radix hex /unit_TX_D2C_PT_tb/intf/tx_data_field

# ── SB Rx Messages ──
add wave -noupdate -expand -group {SB Rx} -color {Cornflower Blue} /unit_TX_D2C_PT_tb/intf/rx_sb_msg_valid
add wave -noupdate -expand -group {SB Rx} -color {Cornflower Blue} /unit_TX_D2C_PT_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {SB Rx} -color {Cornflower Blue} -radix hex /unit_TX_D2C_PT_tb/intf/rx_msginfo
add wave -noupdate -expand -group {SB Rx} -color {Cornflower Blue} -radix hex /unit_TX_D2C_PT_tb/intf/rx_data_field

# ── MB Pattern Control ──
add wave -noupdate -expand -group {MB Pattern} -color Pink /unit_TX_D2C_PT_tb/intf/mb_tx_pattern_en
add wave -noupdate -expand -group {MB Pattern} -color Pink /unit_TX_D2C_PT_tb/intf/mb_tx_pattern_setup
add wave -noupdate -expand -group {MB Pattern} -color Pink /unit_TX_D2C_PT_tb/intf/mb_tx_pattern_mode
add wave -noupdate -expand -group {MB Pattern} -color Pink /unit_TX_D2C_PT_tb/intf/mb_tx_pattern_count_done

# ── MB LFSR & Compare ──
add wave -noupdate -expand -group {MB LFSR} -color {Medium Orchid} /unit_TX_D2C_PT_tb/intf/mb_tx_lfsr_en
add wave -noupdate -expand -group {MB LFSR} -color {Medium Orchid} /unit_TX_D2C_PT_tb/intf/mb_tx_lfsr_rst
add wave -noupdate -expand -group {MB LFSR} -color {Medium Orchid} /unit_TX_D2C_PT_tb/intf/mb_rx_lfsr_en
add wave -noupdate -expand -group {MB LFSR} -color {Medium Orchid} /unit_TX_D2C_PT_tb/intf/mb_rx_lfsr_rst
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} /unit_TX_D2C_PT_tb/intf/mb_rx_compare_en
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} /unit_TX_D2C_PT_tb/intf/mb_rx_compare_setup
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} /unit_TX_D2C_PT_tb/intf/mb_tx_clk_sampling_en
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} -radix unsigned /unit_TX_D2C_PT_tb/intf/mb_tx_clk_sampling

# ── MB Tx Lane Selection ──
add wave -noupdate -expand -group {Lane Sel Tx} -color {Dark Green} /unit_TX_D2C_PT_tb/intf/mb_tx_clk_lane_sel
add wave -noupdate -expand -group {Lane Sel Tx} -color {Dark Green} /unit_TX_D2C_PT_tb/intf/mb_tx_data_lane_sel
add wave -noupdate -expand -group {Lane Sel Tx} -color {Dark Green} /unit_TX_D2C_PT_tb/intf/mb_tx_val_lane_sel
add wave -noupdate -expand -group {Lane Sel Tx} -color {Dark Green} /unit_TX_D2C_PT_tb/intf/mb_tx_trk_lane_sel

# ── MB Rx Lane Selection ──
add wave -noupdate -expand -group {Lane Sel Rx} -color {Dark Cyan} /unit_TX_D2C_PT_tb/intf/mb_rx_clk_lane_sel
add wave -noupdate -expand -group {Lane Sel Rx} -color {Dark Cyan} /unit_TX_D2C_PT_tb/intf/mb_rx_data_lane_sel
add wave -noupdate -expand -group {Lane Sel Rx} -color {Dark Cyan} /unit_TX_D2C_PT_tb/intf/mb_rx_val_lane_sel
add wave -noupdate -expand -group {Lane Sel Rx} -color {Dark Cyan} /unit_TX_D2C_PT_tb/intf/mb_rx_trk_lane_sel

# ── MB Rx Errors (local) ──
add wave -noupdate -expand -group {MB Rx Errors} -color {Orange Red} -radix hex /unit_TX_D2C_PT_tb/intf/mb_rx_perlane_err
add wave -noupdate -expand -group {MB Rx Errors} -color {Orange Red} -radix hex /unit_TX_D2C_PT_tb/intf/mb_rx_aggr_err
add wave -noupdate -expand -group {MB Rx Errors} -color {Orange Red} /unit_TX_D2C_PT_tb/intf/mb_rx_val_err

# ── TB Control ──
add wave -noupdate -expand -group {TB Control} -color Yellow /unit_TX_D2C_PT_tb/intf/tb_wait_timeout
add wave -noupdate -expand -group {TB Control} -color Yellow /unit_TX_D2C_PT_tb/intf/tb_wrong_sb_msg_en
add wave -noupdate -expand -group {TB Control} -color Yellow -radix hex /unit_TX_D2C_PT_tb/intf/tb_rx_msginfo
add wave -noupdate -expand -group {TB Control} -color Yellow -radix hex /unit_TX_D2C_PT_tb/intf/tb_rx_data_field
add wave -noupdate -expand -group {TB Control} -color Yellow -radix unsigned /unit_TX_D2C_PT_tb/timeout_cnt

# ── Counters ──
add wave -noupdate -expand -group {Counters} -color {Khaki} -radix unsigned /unit_TX_D2C_PT_tb/success_count
add wave -noupdate -expand -group {Counters} -color {Khaki} -radix unsigned /unit_TX_D2C_PT_tb/fail_count
add wave -noupdate -expand -group {Counters} -color {Khaki} -radix unsigned /unit_TX_D2C_PT_tb/test_scenario_no

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
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
WaveRestoreZoom {0 ps} {10000000 ps}
