onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /wrapper_MBTRAIN_tb/lclk
add wave -noupdate /wrapper_MBTRAIN_tb/rst_n
add wave -noupdate /wrapper_MBTRAIN_tb/intf/current_mbtrain_substate
add wave -noupdate /wrapper_MBTRAIN_tb/intf/mbtrain_en
add wave -noupdate /wrapper_MBTRAIN_tb/intf/mbtrain_done
add wave -noupdate /wrapper_MBTRAIN_tb/intf/trainerror_req
add wave -noupdate /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_unit_MBTRAIN_ctrl/current_mbtrain_substate
add wave -noupdate -divider {D2C Handshake}
add wave -noupdate /wrapper_MBTRAIN_tb/intf/tx_pt_en
add wave -noupdate /wrapper_MBTRAIN_tb/intf/rx_pt_en
add wave -noupdate /wrapper_MBTRAIN_tb/intf/test_d2c_done
add wave -noupdate -divider {MB Model}
add wave -noupdate /wrapper_MBTRAIN_tb/active_mb_tx_pattern_en
add wave -noupdate /wrapper_MBTRAIN_tb/intf/mb_tx_pattern_count_done
add wave -noupdate /wrapper_MBTRAIN_tb/intf/mb_rx_compare_done
add wave -noupdate /wrapper_MBTRAIN_tb/intf/mb_rx_aggr_err
add wave -noupdate -divider {SB Model}
add wave -noupdate /wrapper_MBTRAIN_tb/active_tx_sb_msg_valid
add wave -noupdate -radix ascii /wrapper_MBTRAIN_tb/active_tx_sb_msg
add wave -noupdate /wrapper_MBTRAIN_tb/intf/rx_sb_msg_valid
add wave -noupdate -radix ascii /wrapper_MBTRAIN_tb/intf/rx_sb_msg
add wave -noupdate -divider {Substate FSMs}
add wave -noupdate /wrapper_MBTRAIN_tb/u_wrapper_d2c_pt/TX_D2C_PT/current_state
add wave -noupdate /wrapper_MBTRAIN_tb/u_wrapper_d2c_pt/RX_D2C_PT/current_state
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 350
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
WaveRestoreZoom {0 ps} {100000000 ps}
