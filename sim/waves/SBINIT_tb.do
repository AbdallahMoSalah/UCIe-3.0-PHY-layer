onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /SBINIT_tb/clk
add wave -noupdate /SBINIT_tb/rst_n
add wave -noupdate /SBINIT_tb/sb_enable
add wave -noupdate /SBINIT_tb/sb_rx_valid
add wave -noupdate /SBINIT_tb/sb_rx_msg_id
add wave -noupdate /SBINIT_tb/sb_tx_valid
add wave -noupdate /SBINIT_tb/sb_tx_msg_id
add wave -noupdate /SBINIT_tb/sb_done
add wave -noupdate /SBINIT_tb/sb_error
add wave -noupdate /SBINIT_tb/sb_det_pattern_req
add wave -noupdate /SBINIT_tb/sb_det_pattern_rcvd
add wave -noupdate /SBINIT_tb/sb_4_iterations_done
add wave -noupdate /SBINIT_tb/timeout_error
add wave -noupdate /SBINIT_tb/sbinit_inst/pattern_rcvd_cnt
add wave -noupdate /SBINIT_tb/sbinit_inst/pattern_req_cnt
add wave -noupdate /SBINIT_tb/sbinit_inst/out_of_reset_msg_sent
add wave -noupdate /SBINIT_tb/sbinit_inst/out_of_reset_msg_rcvd
add wave -noupdate /SBINIT_tb/sbinit_inst/done_rsp_rcvd
add wave -noupdate /SBINIT_tb/sbinit_inst/done_req_rcvd
add wave -noupdate /SBINIT_tb/sbinit_inst/current_state
add wave -noupdate /SBINIT_tb/sbinit_inst/next_state
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {3170887 ps} 0}
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
configure wave -timelineunits ms
update
WaveRestoreZoom {0 ps} {41015628 ps}
