onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {System Signals}
add wave -noupdate /MBINIT_PARAM_tb/clk
add wave -noupdate /MBINIT_PARAM_tb/rst_n
add wave -noupdate -color Gold /MBINIT_PARAM_tb/mb_param_enable
add wave -noupdate -color Green /MBINIT_PARAM_tb/mb_param_done
add wave -noupdate -color Red /MBINIT_PARAM_tb/mb_param_error
add wave -noupdate -color Red /MBINIT_PARAM_tb/timeout_error

add wave -noupdate -divider {State Machine (DUT)}
add wave -noupdate -color Blue /MBINIT_PARAM_tb/dut/current_state
add wave -noupdate -color Blue /MBINIT_PARAM_tb/dut/next_state
add wave -noupdate -color Orange /MBINIT_PARAM_tb/dut/partner_s1_valid
add wave -noupdate -color Orange /MBINIT_PARAM_tb/dut/partner_s2_valid
add wave -noupdate -color Orange /MBINIT_PARAM_tb/dut/param_req_rcvd
add wave -noupdate -color Orange /MBINIT_PARAM_tb/dut/param_rsp_rcvd
add wave -noupdate -color Orange /MBINIT_PARAM_tb/dut/sbfe_req_rcvd
add wave -noupdate -color Orange /MBINIT_PARAM_tb/dut/sbfe_rsp_rcvd

add wave -noupdate -divider {Interface Variables (Negotiated)}
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/cap_if/use_x8_mode
add wave -noupdate -radix unsigned -color Cyan /MBINIT_PARAM_tb/cap_if/negotiated_speed
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/cap_if/negotiated_sbfe
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/cap_if/negotiated_tarr
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/cap_if/negotiated_l2spd
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/cap_if/negotiated_pspt
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/cap_if/negotiated_so
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/cap_if/negotiated_pmo
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/cap_if/negotiated_mtp

add wave -noupdate -divider {RX Message Interface}
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/mb_param_rx_valid
add wave -noupdate -color Cyan /MBINIT_PARAM_tb/mb_param_rx_msg_id
add wave -noupdate -radix hexadecimal -color Cyan /MBINIT_PARAM_tb/mb_param_rx_MsgInfo
add wave -noupdate -radix hexadecimal -color Cyan /MBINIT_PARAM_tb/mb_param_rx_data_Field

add wave -noupdate -divider {TX Message Interface}
add wave -noupdate -color Magenta /MBINIT_PARAM_tb/mb_param_tx_valid
add wave -noupdate -color Magenta /MBINIT_PARAM_tb/mb_param_tx_msg_id
add wave -noupdate -radix hexadecimal -color Magenta /MBINIT_PARAM_tb/mb_param_tx_MsgInfo
add wave -noupdate -radix hexadecimal -color Magenta /MBINIT_PARAM_tb/mb_param_tx_data_Field

add wave -noupdate -divider {PHY Control}
add wave -noupdate -color Yellow /MBINIT_PARAM_tb/mb_tx_valid_status
add wave -noupdate -color Yellow /MBINIT_PARAM_tb/mb_tx_track_status
add wave -noupdate -color Yellow /MBINIT_PARAM_tb/mb_tx_clk_status
add wave -noupdate -color Yellow /MBINIT_PARAM_tb/mb_tx_data_status
add wave -noupdate -color Green /MBINIT_PARAM_tb/mb_rx_valid_status
add wave -noupdate -color Green /MBINIT_PARAM_tb/mb_rx_track_status
add wave -noupdate -color Green /MBINIT_PARAM_tb/mb_rx_clk_status
add wave -noupdate -color Green /MBINIT_PARAM_tb/mb_rx_data_status

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 350
configure wave -valuecolwidth 150
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
WaveRestoreZoom {0 ps} {400 ns}
