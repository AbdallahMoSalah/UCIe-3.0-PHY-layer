onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {FSM State & Control}
add wave -noupdate /unit_RXDESKEW_tb/dut/current_state
add wave -noupdate /unit_RXDESKEW_tb/dut/next_state
add wave -noupdate /unit_RXDESKEW_tb/dut/rxdeskew_if/rxdeskew_en
add wave -noupdate /unit_RXDESKEW_tb/dut/rxdeskew_if/rxdeskew_done
add wave -noupdate /unit_RXDESKEW_tb/dut/rxdeskew_if/timeout_timer_en
add wave -noupdate /unit_RXDESKEW_tb/dut/rxdeskew_if/timeout_8ms_occured
add wave -noupdate /unit_RXDESKEW_tb/dut/rxdeskew_if/trainerror_req
add wave -noupdate /unit_RXDESKEW_tb/dut/rxdeskew_if/datatraincenter1_req
add wave -noupdate /unit_RXDESKEW_tb/dut/is_high_speed
add wave -noupdate /unit_RXDESKEW_tb/dut/swept_code_r

add wave -noupdate -divider {SB Handshakes}
add wave -noupdate -radix ascii /unit_RXDESKEW_tb/dut/rxdeskew_if/tx_sb_msg
add wave -noupdate /unit_RXDESKEW_tb/dut/rxdeskew_if/tx_sb_msg_valid
add wave -noupdate -radix ascii /unit_RXDESKEW_tb/dut/rxdeskew_if/rx_sb_msg
add wave -noupdate /unit_RXDESKEW_tb/dut/rxdeskew_if/rx_sb_msg_valid
add wave -noupdate /unit_RXDESKEW_tb/dut/my_preset
add wave -noupdate /unit_RXDESKEW_tb/dut/partner_preset

add wave -noupdate -divider {D2C Interface}
add wave -noupdate /unit_RXDESKEW_tb/dut/d2c_if/rx_pt_en
add wave -noupdate /unit_RXDESKEW_tb/dut/d2c_if/test_d2c_done
add wave -noupdate /unit_RXDESKEW_tb/dut/d2c_if/d2c_perlane_err

add wave -noupdate -divider {Deskew Tracking & EQ evaluation}
add wave -noupdate /unit_RXDESKEW_tb/dut/preset_search_cnt
add wave -noupdate /unit_RXDESKEW_tb/dut/dtc1_arc_cnt
add wave -noupdate -radix unsigned /unit_RXDESKEW_tb/dut/current_preset_min_range[16]
add wave -noupdate -radix unsigned /unit_RXDESKEW_tb/dut/overall_best_min_range
add wave -noupdate /unit_RXDESKEW_tb/dut/best_preset_saved
add wave -noupdate /unit_RXDESKEW_tb/dut/old_preset_saved

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
configure wave -namecolwidth 300
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
WaveRestoreZoom {0 ps} {1000 ns}
