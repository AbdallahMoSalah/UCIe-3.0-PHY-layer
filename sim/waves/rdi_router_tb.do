onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /rdi_router_tb/clk
add wave -noupdate /rdi_router_tb/rst_n
add wave -noupdate /rdi_router_tb/reset
add wave -noupdate /rdi_router_tb/rdi_msg
add wave -noupdate /rdi_router_tb/rdi_vld
add wave -noupdate /rdi_router_tb/rdi_ready
add wave -noupdate /rdi_router_tb/reg_msg
add wave -noupdate /rdi_router_tb/reg_vld
add wave -noupdate /rdi_router_tb/reg_ready
add wave -noupdate /rdi_router_tb/Adapter_msg_send
add wave -noupdate /rdi_router_tb/Adapter_vld_send
add wave -noupdate /rdi_router_tb/Adapter_ready
add wave -noupdate /rdi_router_tb/dropped_count
add wave -noupdate /rdi_router_tb/reg_match_count
add wave -noupdate /rdi_router_tb/adp_match_count
add wave -noupdate /rdi_router_tb/errors
add wave -noupdate /rdi_router_tb/predict_and_push/current_reset
add wave -noupdate /rdi_router_tb/predict_and_push/msg
add wave -noupdate /rdi_router_tb/#ublk#86473634#119/#ublk#86473634#190/#ublk#86473634#200/exp_data
add wave -noupdate /rdi_router_tb/#ublk#86473634#119/#ublk#86473634#219/#ublk#86473634#229/exp_data
add wave -noupdate /rdi_router_tb/dut/opcode
add wave -noupdate /rdi_router_tb/dut/dstid
add wave -noupdate /rdi_router_tb/dut/is_req
add wave -noupdate /rdi_router_tb/dut/is_local_phy
add wave -noupdate /rdi_router_tb/dut/consumer_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {176070 ps} 0}
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
WaveRestoreZoom {0 ps} {227328 ps}
