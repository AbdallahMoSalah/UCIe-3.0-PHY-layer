onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/WIDTH
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/w_local_gen
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/w_data
add wave -noupdate -color Magenta -radix binary /MB_PATTERN_COMPARATOR_TB/DUT/o_per_lane_error
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/o_error_done
add wave -noupdate -color {Medium Orchid} -radix decimal /MB_PATTERN_COMPARATOR_TB/DUT/o_error_counter
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/mismatch_upper
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/mismatch_lower
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/lane_total_mismatch
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/lane_mismatch_part_2
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/lane_mismatch_part_1
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/lane_err_accum
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_clk
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/k
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/in_progress
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_type_of_com
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_enable_pattern_com
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_rst_n
add wave -noupdate -color {Sky Blue} -radix decimal /MB_PATTERN_COMPARATOR_TB/DUT/iteration_ctr
add wave -noupdate -radix decimal /MB_PATTERN_COMPARATOR_TB/DUT/i_max_error_threshold_per_lane_ID
add wave -noupdate -radix decimal /MB_PATTERN_COMPARATOR_TB/DUT/i_max_error_threshold_aggergate
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_15
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_14
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_13
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_12
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_11
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_10
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_9
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_8
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_7
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_6
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_5
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_4
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_3
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_2
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_1
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_local_gen_0
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_15
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_14
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_13
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_12
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_11
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_10
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_9
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_8
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_7
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_6
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_5
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_4
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_3
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_2
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_1
add wave -noupdate /MB_PATTERN_COMPARATOR_TB/DUT/i_data_0
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2706263 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 194
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
WaveRestoreZoom {2585095 ps} {2682805 ps}
