onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /sb_serializer_tb/clk
add wave -noupdate /sb_serializer_tb/rst_n
add wave -noupdate /sb_serializer_tb/tx_parallel_data
add wave -noupdate /sb_serializer_tb/tx_data_valid
add wave -noupdate /sb_serializer_tb/tx_ready
add wave -noupdate /sb_serializer_tb/tx_serial_out
add wave -noupdate /sb_serializer_tb/TXCKSB
add wave -noupdate /sb_serializer_tb/serial_capture
add wave -noupdate -radix decimal /sb_serializer_tb/bit_count
add wave -noupdate /sb_serializer_tb/send_packet/data
add wave -noupdate /sb_serializer_tb/dut/state
add wave -noupdate /sb_serializer_tb/dut/next_state
add wave -noupdate /sb_serializer_tb/dut/shift_reg
add wave -noupdate -radix decimal /sb_serializer_tb/dut/bit_cnt
add wave -noupdate /sb_serializer_tb/pass
add wave -noupdate /sb_serializer_tb/fail
add wave -noupdate /sb_serializer_tb/dut/SVA/assert__p_valid_hold
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {3042 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 130
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
WaveRestoreZoom {73670 ns} {73702 ns}
