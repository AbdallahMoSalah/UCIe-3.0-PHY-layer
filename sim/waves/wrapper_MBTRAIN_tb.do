onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {TB & Global Control}
add wave -noupdate /wrapper_MBTRAIN_tb/lclk
add wave -noupdate /wrapper_MBTRAIN_tb/rst_n
add wave -noupdate /wrapper_MBTRAIN_tb/intf/mbtrain_en
add wave -noupdate /wrapper_MBTRAIN_tb/intf/current_mbtrain_substate
add wave -noupdate /wrapper_MBTRAIN_tb/intf/mbtrain_done
add wave -noupdate /wrapper_MBTRAIN_tb/intf/trainerror_req
add wave -noupdate -color Violet /wrapper_MBTRAIN_tb/intf/timeout_8ms_occured
add wave -noupdate -color Violet /wrapper_MBTRAIN_tb/intf/analog_settle_time_done

add wave -noupdate -divider {D2C Interface & FSMs}
add wave -noupdate -group {D2C Handshake} /wrapper_MBTRAIN_tb/intf/tx_pt_en
add wave -noupdate -group {D2C Handshake} /wrapper_MBTRAIN_tb/intf/rx_pt_en
add wave -noupdate -group {D2C Handshake} /wrapper_MBTRAIN_tb/intf/test_d2c_done
add wave -noupdate -group {D2C Handshake} /wrapper_MBTRAIN_tb/intf/d2c_aggr_err
add wave -noupdate -group {D2C Handshake} /wrapper_MBTRAIN_tb/intf/d2c_perlane_err
add wave -noupdate -group {D2C Handshake} /wrapper_MBTRAIN_tb/intf/partner_valtraincenter_fail_flag
add wave -noupdate -group {D2C TX FSM} /wrapper_MBTRAIN_tb/u_wrapper_d2c_pt/TX_D2C_PT/current_state
add wave -noupdate -group {D2C TX FSM} /wrapper_MBTRAIN_tb/u_wrapper_d2c_pt/TX_D2C_PT/next_state
add wave -noupdate -group {D2C RX FSM} /wrapper_MBTRAIN_tb/u_wrapper_d2c_pt/RX_D2C_PT/current_state
add wave -noupdate -group {D2C RX FSM} /wrapper_MBTRAIN_tb/u_wrapper_d2c_pt/RX_D2C_PT/next_state

add wave -noupdate -divider {MB Model}
add wave -noupdate -group {MB TX} /wrapper_MBTRAIN_tb/active_mb_tx_pattern_en
add wave -noupdate -group {MB TX} -radix unsigned /wrapper_MBTRAIN_tb/iter_ctr
add wave -noupdate -group {MB TX} /wrapper_MBTRAIN_tb/intf/mb_tx_pattern_count_done
add wave -noupdate -group {MB RX} /wrapper_MBTRAIN_tb/intf/mb_rx_compare_done
add wave -noupdate -group {MB RX} /wrapper_MBTRAIN_tb/intf/mb_rx_aggr_err

add wave -noupdate -divider {SB Model}
add wave -noupdate -group {SB TX} /wrapper_MBTRAIN_tb/active_tx_sb_msg_valid
add wave -noupdate -group {SB TX} -radix ascii /wrapper_MBTRAIN_tb/active_tx_sb_msg
add wave -noupdate -group {SB RX} /wrapper_MBTRAIN_tb/intf/rx_sb_msg_valid
add wave -noupdate -group {SB RX} -radix ascii /wrapper_MBTRAIN_tb/intf/rx_sb_msg

add wave -noupdate -divider {MBTRAIN Substates}
add wave -noupdate -group {VALVREF} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_valvref/current_state
add wave -noupdate -group {VALVREF} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_valvref/next_state

add wave -noupdate -group {DATAVREF} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datavref/current_state
add wave -noupdate -group {DATAVREF} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datavref/next_state

add wave -noupdate -group {SPEEDIDLE} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_speedidle/current_state

add wave -noupdate -group {TXSELFCAL} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_txselfcal/current_state

add wave -noupdate -group {RXCLKCAL} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_rxclkcal/current_state

add wave -noupdate -group {VALTRAINCENTER} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_valtraincenter/current_state
add wave -noupdate -group {VALTRAINCENTER} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_valtraincenter/next_state
add wave -noupdate -group {VALTRAINCENTER} -radix unsigned /wrapper_MBTRAIN_tb/intf/phy_tx_val_pi_phase_ctrl

add wave -noupdate -group {VALTRAINVREF} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_valtrainvref/current_state
add wave -noupdate -group {VALTRAINVREF} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_valtrainvref/next_state

add wave -noupdate -group {DATATRAINCENTER1} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datatraincenter1/current_state
add wave -noupdate -group {DATATRAINCENTER1} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datatraincenter1/next_state

add wave -noupdate -group {DATATRAINVREF} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datatrainvref/current_state
add wave -noupdate -group {DATATRAINVREF} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datatrainvref/next_state

add wave -noupdate -group {RXDESKEW} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_rxdeskew/current_state
add wave -noupdate -group {RXDESKEW} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_rxdeskew/next_state

add wave -noupdate -group {DATATRAINCENTER2} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datatraincenter2/current_state
add wave -noupdate -group {DATATRAINCENTER2} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datatraincenter2/next_state
add wave -noupdate -group {DATATRAINCENTER2} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_datatraincenter2/active_lane_idx

add wave -noupdate -group {LINKSPEED} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_linkspeed/current_state

add wave -noupdate -group {REPAIR} /wrapper_MBTRAIN_tb/u_wrapper_mbtrain/u_repair/current_state

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 450
configure wave -valuecolwidth 200
configure wave -justifyvalue left
configure wave -signalnamewidth 0
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
WaveRestoreZoom {0 ps} {100000 ps}
