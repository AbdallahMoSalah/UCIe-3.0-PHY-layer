onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /sb_pattern_serializer_tb/clk_parallel
add wave -noupdate /sb_pattern_serializer_tb/clk
add wave -noupdate /sb_pattern_serializer_tb/rst_n
add wave -noupdate /sb_pattern_serializer_tb/pattern_mode
add wave -noupdate /sb_pattern_serializer_tb/dut_pattern/start_pat_req
add wave -noupdate /sb_pattern_serializer_tb/mapper_data
add wave -noupdate /sb_pattern_serializer_tb/mapper_valid
add wave -noupdate /sb_pattern_serializer_tb/mapper_ready
add wave -noupdate /sb_pattern_serializer_tb/ser_data
add wave -noupdate /sb_pattern_serializer_tb/ser_valid
add wave -noupdate /sb_pattern_serializer_tb/ser_ready
add wave -noupdate /sb_pattern_serializer_tb/TXDATASB
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/pmo_en
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/tx_parallel_data
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/tx_data_valid
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/tx_ready
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/TXDATASB
add wave -noupdate -color Magenta /sb_pattern_serializer_tb/dut_serializer/TXCKSB
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/state
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/next_state
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/shift_reg
add wave -noupdate -radix unsigned /sb_pattern_serializer_tb/dut_serializer/bit_cnt
add wave -noupdate /sb_pattern_serializer_tb/dut_pattern/send_4_iter
add wave -noupdate /sb_pattern_serializer_tb/dut_pattern/four_iter_done
add wave -noupdate /sb_pattern_serializer_tb/dut_pattern/iter_cnt
add wave -noupdate /sb_pattern_serializer_tb/dut_serializer/SVA_ser/assert__p_valid_hold
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {66892 ps} 0}
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
WaveRestoreZoom {0 ps} {131336 ps}
