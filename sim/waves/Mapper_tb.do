onerror {resume}
quietly WaveActivateNextPane {} 0
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
add wave -noupdate /Mapper_tb/DUT/out_scramble_en
add wave -noupdate /Mapper_tb/DUT/mapper_ready
add wave -noupdate /Mapper_tb/DUT/cycle_count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {50308 ps} 0}
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
WaveRestoreZoom {0 ps} {174564 ps}
