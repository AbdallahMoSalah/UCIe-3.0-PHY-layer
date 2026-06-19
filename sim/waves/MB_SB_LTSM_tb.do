onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_clk
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_rst_n
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_pcmp_enable
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_enable
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/o_done
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_comparison_mode
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_lane_mask
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_max_error_threshold_per_lane
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_max_error_threshold_aggregate
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_iteration_count
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_pattern_mode
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_clear_error
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_local_pattern
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/i_rx_pattern
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/o_per_lane_pass
add wave -noupdate -radix unsigned /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/o_aggregate_error_counter
add wave -noupdate /MB_SB_LTSM_tb/u_die1/u_mb_die/u_rx_top/u_pat_cmp/o_aggregate_error
add wave -noupdate /MB_SB_LTSM_tb/u_die0/u_ltsm_top/current_ltsm_state_n
add wave -noupdate /MB_SB_LTSM_tb/u_die0/u_mb_die/o_TD_P
add wave -noupdate /MB_SB_LTSM_tb/u_die0/u_mb_die/o_TVLD_P
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {491992555 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 319
configure wave -valuecolwidth 384
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
WaveRestoreZoom {473504647 ps} {503119257 ps}
