onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /rdi_de_aggregator_tb/rdi_de_aggregatorif/clk
add wave -noupdate /rdi_de_aggregator_tb/rdi_de_aggregatorif/rst_n
add wave -noupdate /rdi_de_aggregator_tb/rdi_de_aggregatorif/pl_msg
add wave -noupdate /rdi_de_aggregator_tb/rdi_de_aggregatorif/pl_msg_vld
add wave -noupdate /rdi_de_aggregator_tb/rdi_de_aggregatorif/pl_msg_ready
add wave -noupdate /rdi_de_aggregator_tb/dut/traffic_req
add wave -noupdate /rdi_de_aggregator_tb/dut/traffic_ready
add wave -noupdate /rdi_de_aggregator_tb/rdi_de_aggregatorif/pl_cfg
add wave -noupdate /rdi_de_aggregator_tb/rdi_de_aggregatorif/pl_cfg_vld
add wave -noupdate /rdi_de_aggregator_tb/dut/state
add wave -noupdate /rdi_de_aggregator_tb/dut/next_state
add wave -noupdate /rdi_de_aggregator_tb/dut/msg_reg
add wave -noupdate /rdi_de_aggregator_tb/dut/msg_flat
add wave -noupdate /rdi_de_aggregator_tb/dut/in_msg_flat
add wave -noupdate /rdi_de_aggregator_tb/dut/chunk_cnt
add wave -noupdate /rdi_de_aggregator_tb/dut/expected_chunks
add wave -noupdate /rdi_de_aggregator_tb/dut/in_opcode
add wave -noupdate /rdi_de_aggregator_tb/dut/next_expected_chunks
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {675 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 224
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
WaveRestoreZoom {654 ns} {704 ns}
