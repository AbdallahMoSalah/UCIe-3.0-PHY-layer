onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {FSM State & Control}
add wave -noupdate /unit_RXDESKEW_tb/current_state
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/current_state
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/next_state
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/rxdeskew_if/rxdeskew_en
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/rxdeskew_if/rxdeskew_done
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/rxdeskew_if/timeout_timer_en
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/rxdeskew_if/timeout_8ms_occured
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/rxdeskew_if/trainerror_req
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/rxdeskew_if/datatraincenter1_req
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/is_high_speed
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/swept_code_r_out
add wave -noupdate -divider {PI Sub-module}
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/u_phase_interpolator_for_deskew/pi_state
add wave -noupdate -divider {SB Handshakes}
add wave -noupdate -radix ascii /unit_RXDESKEW_tb/unit_RXDESKEW_inst/rxdeskew_if/tx_sb_msg
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/rxdeskew_if/tx_sb_msg_valid
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/my_preset
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/partner_preset
add wave -noupdate -divider {D2C Interface}
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/d2c_if/rx_pt_en
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/d2c_if/test_d2c_done
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/d2c_if/d2c_perlane_err
add wave -noupdate -divider {Deskew Tracking & EQ evaluation}
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/preset_search_cnt
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/dtc1_arc_cnt
add wave -noupdate -radix unsigned {/unit_RXDESKEW_tb/unit_RXDESKEW_inst/u_phase_interpolator_for_deskew/current_preset_min_range[16]}
add wave -noupdate -radix unsigned /unit_RXDESKEW_tb/unit_RXDESKEW_inst/overall_best_min_range
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/best_preset_saved
add wave -noupdate /unit_RXDESKEW_tb/unit_RXDESKEW_inst/old_preset_saved
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1112229765 ps} 0}
quietly wave cursor active 1
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
WaveRestoreZoom {0 ps} {6598516971 ps}
