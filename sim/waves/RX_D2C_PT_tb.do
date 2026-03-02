onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/lclk
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/rst_n
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/rx_pt_trigger
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/timeout_8ms
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/test_d2c_done
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_clk_sampling_en
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_clk_sampling
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_pattern_en
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_pattern_setup
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_data_pattern_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_val_pattern_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_lfsr_en
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_lfsr_rst
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_lfsr_en
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_lfsr_rst
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_pattern_mode
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_burst_count
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_idle_count
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_iter_count
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_pattern_count_done
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_compare_en
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_max_err_thresh_aggr
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_max_err_thresh_perlane
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_compare_setup
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_aggr_err
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_perlane_err
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_val_err
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_clk_err
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_compare_done
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_clk_lane_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_data_lane_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_val_lane_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_tx_trk_lane_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_clk_lane_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_data_lane_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_val_lane_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/mb_rx_trk_lane_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_clk_sampling
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_timeout_or_error
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_lfsr_en
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_pattern_setup
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_data_pattern_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_val_pattern_sel
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_pattern_mode
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_burst_count
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_idle_count
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_iter_count
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_compare_setup
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_aggr_err
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_perlane_err
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_val_err
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/d2c_clk_err
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/tx_sb_msg_valid
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/tx_sb_msg
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/tx_msginfo
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/tx_data_field
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/rx_sb_msg_valid
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/rx_sb_msg
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/cfg_train4_max_err_thresh_perlane
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/cfg_train4_max_err_thresh_aggr
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/lclk
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/sb_clk
add wave -noupdate -expand -group errors -color Coral -itemcolor Coral -radix unsigned /RX_D2C_PT_tb/timeout_8ms_counter
add wave -noupdate -expand -group errors -color Coral -itemcolor Coral -radix unsigned /RX_D2C_PT_tb/aggr_err
add wave -noupdate -expand -group errors -color Coral -itemcolor Coral -radix unsigned /RX_D2C_PT_tb/perlane_err
add wave -noupdate -expand -group errors -color Coral -itemcolor Coral -radix unsigned /RX_D2C_PT_tb/val_err
add wave -noupdate -expand -group errors -color Coral -itemcolor Coral -radix unsigned /RX_D2C_PT_tb/clk_err
add wave -noupdate -expand -group errors -color Coral -itemcolor Coral -radix unsigned /RX_D2C_PT_tb/wait_timeout
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/burst_counter
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/idle_counter
add wave -noupdate -radix unsigned /RX_D2C_PT_tb/iter_counter
add wave -noupdate -color Magenta -itemcolor Magenta -radix unsigned /RX_D2C_PT_tb/tx_sb_msg_enum
add wave -noupdate -color Magenta -itemcolor Magenta -radix unsigned /RX_D2C_PT_tb/rx_sb_msg_enum
add wave -noupdate -color {Slate Blue} -itemcolor {Blue Violet} -radix unsigned /RX_D2C_PT_tb/rx_sb_msg_valid_reg
add wave -noupdate -color {Slate Blue} -itemcolor {Blue Violet} -radix unsigned /RX_D2C_PT_tb/sb_msg_waiting_time
add wave -noupdate -color Cyan -itemcolor Blue -radix unsigned /RX_D2C_PT_tb/current_state
add wave -noupdate -color Cyan -itemcolor Blue -radix unsigned /RX_D2C_PT_tb/previous_state
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {19797017 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 204
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
configure wave -timelineunits ps
update
WaveRestoreZoom {19731684 ps} {19942705 ps}
