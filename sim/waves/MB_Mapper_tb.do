onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /Mapper_tb/i_clk
add wave -noupdate /Mapper_tb/i_rst_n
add wave -noupdate /Mapper_tb/mapper_en
add wave -noupdate /Mapper_tb/i_width_deg_map
add wave -noupdate /Mapper_tb/i_in_data
add wave -noupdate /Mapper_tb/lp_irdy
add wave -noupdate /Mapper_tb/lp_valid
add wave -noupdate /Mapper_tb/o_lane_0
add wave -noupdate /Mapper_tb/o_lane_1
add wave -noupdate /Mapper_tb/o_lane_2
add wave -noupdate /Mapper_tb/o_lane_3
add wave -noupdate /Mapper_tb/o_lane_4
add wave -noupdate /Mapper_tb/o_lane_5
add wave -noupdate /Mapper_tb/o_lane_6
add wave -noupdate /Mapper_tb/o_lane_7
add wave -noupdate /Mapper_tb/o_lane_8
add wave -noupdate /Mapper_tb/o_lane_9
add wave -noupdate /Mapper_tb/o_lane_10
add wave -noupdate /Mapper_tb/o_lane_11
add wave -noupdate /Mapper_tb/o_lane_12
add wave -noupdate /Mapper_tb/o_lane_13
add wave -noupdate /Mapper_tb/o_lane_14
add wave -noupdate /Mapper_tb/o_lane_15
add wave -noupdate /Mapper_tb/out_scramble_en
add wave -noupdate /Mapper_tb/mapper_ready
add wave -noupdate /Mapper_tb/correct_count
add wave -noupdate /Mapper_tb/error_count
add wave -noupdate /Mapper_tb/i
add wave -noupdate /Mapper_tb/run_mode/mode
add wave -noupdate /Mapper_tb/run_mode/num_cycles
add wave -noupdate /Mapper_tb/run_mode/c
add wave -noupdate /Mapper_tb/check_output/mode
add wave -noupdate /Mapper_tb/check_output/cycle
add wave -noupdate /Mapper_tb/check_output/exp0
add wave -noupdate /Mapper_tb/check_output/exp1
add wave -noupdate /Mapper_tb/check_output/exp2
add wave -noupdate /Mapper_tb/check_output/exp3
add wave -noupdate /Mapper_tb/check_output/exp4
add wave -noupdate /Mapper_tb/check_output/exp5
add wave -noupdate /Mapper_tb/check_output/exp6
add wave -noupdate /Mapper_tb/check_output/exp7
add wave -noupdate /Mapper_tb/check_output/exp8
add wave -noupdate /Mapper_tb/check_output/exp9
add wave -noupdate /Mapper_tb/check_output/exp10
add wave -noupdate /Mapper_tb/check_output/exp11
add wave -noupdate /Mapper_tb/check_output/exp12
add wave -noupdate /Mapper_tb/check_output/exp13
add wave -noupdate /Mapper_tb/check_output/exp14
add wave -noupdate /Mapper_tb/check_output/exp15
add wave -noupdate /Mapper_tb/check_output/j
add wave -noupdate /Mapper_tb/check_output/cm
add wave -noupdate /Mapper_tb/DUT/i_clk
add wave -noupdate /Mapper_tb/DUT/i_rst_n
add wave -noupdate /Mapper_tb/DUT/i_in_data
add wave -noupdate /Mapper_tb/DUT/mapper_en
add wave -noupdate /Mapper_tb/DUT/i_width_deg_map
add wave -noupdate /Mapper_tb/DUT/lp_irdy
add wave -noupdate /Mapper_tb/DUT/lp_valid
add wave -noupdate /Mapper_tb/DUT/o_lane_0
add wave -noupdate /Mapper_tb/DUT/o_lane_1
add wave -noupdate /Mapper_tb/DUT/o_lane_2
add wave -noupdate /Mapper_tb/DUT/o_lane_3
add wave -noupdate /Mapper_tb/DUT/o_lane_4
add wave -noupdate /Mapper_tb/DUT/o_lane_5
add wave -noupdate /Mapper_tb/DUT/o_lane_6
add wave -noupdate /Mapper_tb/DUT/o_lane_7
add wave -noupdate /Mapper_tb/DUT/o_lane_8
add wave -noupdate /Mapper_tb/DUT/o_lane_9
add wave -noupdate /Mapper_tb/DUT/o_lane_10
add wave -noupdate /Mapper_tb/DUT/o_lane_11
add wave -noupdate /Mapper_tb/DUT/o_lane_12
add wave -noupdate /Mapper_tb/DUT/o_lane_13
add wave -noupdate /Mapper_tb/DUT/o_lane_14
add wave -noupdate /Mapper_tb/DUT/o_lane_15
add wave -noupdate -color Magenta /Mapper_tb/DUT/out_scramble_en
add wave -noupdate -color Magenta /Mapper_tb/DUT/mapper_ready
add wave -noupdate -color Coral /Mapper_tb/DUT/cycle_count
add wave -noupdate /Mapper_tb/DUT/data_active
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {274884 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
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
WaveRestoreZoom {96635 ps} {337019 ps}
