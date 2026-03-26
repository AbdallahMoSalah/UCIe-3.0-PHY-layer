onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /rdi_aggregator_tb/dut/clk
add wave -noupdate /rdi_aggregator_tb/dut/rst_n
add wave -noupdate /rdi_aggregator_tb/dut/lp_cfg
add wave -noupdate /rdi_aggregator_tb/dut/lp_cfg_vld
add wave -noupdate /rdi_aggregator_tb/dut/lp_msg
add wave -noupdate /rdi_aggregator_tb/dut/lp_msg_vld
add wave -noupdate /rdi_aggregator_tb/dut/state
add wave -noupdate /rdi_aggregator_tb/dut/next_state
add wave -noupdate /rdi_aggregator_tb/dut/packet_reg
add wave -noupdate /rdi_aggregator_tb/dut/chunk_cnt
add wave -noupdate /rdi_aggregator_tb/dut/expected_chunks
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {195 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 196
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
WaveRestoreZoom {145 ns} {251 ns}
