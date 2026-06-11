onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_clk
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_rst_n
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_enable
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_mode
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_max_error_threshold
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_clear_error
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_valid_frame_data
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_valid_frame_vld
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/o_done
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/o_pass
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/err_accum
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/consecutive_ctr
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/iter_ctr
add wave -noupdate /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/err_inc
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1525280 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 249
configure wave -valuecolwidth 108
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
configure wave -timelineunits ps
update
WaveRestoreZoom {1324768 ps} {1732232 ps}
