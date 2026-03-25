add wave -noupdate /ltsm_ctrl_tb/lclk
add wave -noupdate /ltsm_ctrl_tb/rst_n
add wave -noupdate /ltsm_ctrl_tb/state_req
add wave -noupdate /ltsm_ctrl_tb/state_status
add wave -noupdate /ltsm_ctrl_tb/timeout_timer_en
add wave -noupdate /ltsm_ctrl_tb/timeout_8ms_occured
add wave -noupdate /ltsm_ctrl_tb/mbtrain_en
add wave -noupdate /ltsm_ctrl_tb/mbtrain_done
add wave -noupdate /ltsm_ctrl_tb/mbtrain_fail
add wave -noupdate /ltsm_ctrl_tb/dut/current_state
run -all