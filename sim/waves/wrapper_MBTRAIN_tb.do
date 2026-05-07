# ==============================================================================
# Waveform configuration for wrapper_MBTRAIN_tb
# ==============================================================================

onerror {resume}
quietly WaveActivateNextPane {} 0

# --- Top Level State ---
add wave -noupdate -divider {Global State}
add wave -noupdate -label {Current LTSM State} /wrapper_MBTRAIN_tb/intf/current_ltsm_state
add wave -noupdate -label {Current MBTRAIN Substate} /wrapper_MBTRAIN_tb/current_substate

# --- MBTRAIN Wrapper Mux/Enables ---
add wave -noupdate -divider {MBTRAIN Wrapper Interface}
add wave -noupdate -label {MBTRAIN Enable} /wrapper_MBTRAIN_tb/intf/mbtrain_en
add wave -noupdate -label {MBTRAIN Done} /wrapper_MBTRAIN_tb/intf/mbtrain_done
add wave -noupdate -label {TX PT Enable (D2C)} /wrapper_MBTRAIN_tb/DUT/mbtrain_if/tx_pt_en
add wave -noupdate -label {RX PT Enable (D2C)} /wrapper_MBTRAIN_tb/DUT/mbtrain_if/rx_pt_en
add wave -noupdate -label {Timeout Timer Enable} /wrapper_MBTRAIN_tb/intf/timeout_timer_en
add wave -noupdate -label {Timeout 8ms Occured} /wrapper_MBTRAIN_tb/intf/timeout_8ms_occured
add wave -noupdate -label {Analog Settle Timer Enable} /wrapper_MBTRAIN_tb/intf/analog_settle_timer_en
add wave -noupdate -label {Analog Settle Time Done} /wrapper_MBTRAIN_tb/intf/analog_settle_time_done

# --- Sideband Messages ---
add wave -noupdate -divider {Sideband Handshake}
add wave -noupdate -label {TX SB Msg Valid} /wrapper_MBTRAIN_tb/intf/tx_sb_msg_valid
add wave -noupdate -label {TX SB Msg} /wrapper_MBTRAIN_tb/intf/tx_sb_msg
add wave -noupdate -label {RX SB Msg Valid} /wrapper_MBTRAIN_tb/intf/rx_sb_msg_valid
add wave -noupdate -label {RX SB Msg} /wrapper_MBTRAIN_tb/intf/rx_sb_msg
add wave -noupdate -label {TX Data Field} /wrapper_MBTRAIN_tb/intf/tx_data_field
add wave -noupdate -label {RX Data Field} /wrapper_MBTRAIN_tb/intf/rx_data_field

# --- D2C Testing ---
add wave -noupdate -divider {D2C Handshake}
add wave -noupdate -label {MB TX Pattern En} /wrapper_MBTRAIN_tb/intf/mb_tx_pattern_en
add wave -noupdate -label {MB TX Pattern Count Done} /wrapper_MBTRAIN_tb/intf/mb_tx_pattern_count_done
add wave -noupdate -label {MB RX Compare En} /wrapper_MBTRAIN_tb/intf/mb_rx_compare_en
add wave -noupdate -label {MB RX Compare Done} /wrapper_MBTRAIN_tb/intf/mb_rx_compare_done
add wave -noupdate -label {D2C Test Done} /wrapper_MBTRAIN_tb/DUT/u_wrapper_D2C_PT/mbinit_if/test_d2c_done

# --- Substate Specific Groups ---
add wave -noupdate -divider {Substates Internal Signals}

add wave -noupdate -group {VALVREF} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/VALVREF/current_state
add wave -noupdate -group {VALVREF} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valvref/timeout_timer_en
add wave -noupdate -group {VALVREF} -label {Analog Settle En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valvref/analog_settle_timer_en
add wave -noupdate -group {VALVREF} -label {PHY RX ValVref Ctrl} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valvref/phy_rx_valvref_ctrl
add wave -noupdate -group {VALVREF} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_valvref/tx_pt_en
add wave -noupdate -group {VALVREF} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_valvref/rx_pt_en

add wave -noupdate -group {DATAVREF} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/DATAVREF/current_state
add wave -noupdate -group {DATAVREF} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datavref/timeout_timer_en
add wave -noupdate -group {DATAVREF} -label {Analog Settle En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datavref/analog_settle_timer_en
add wave -noupdate -group {DATAVREF} -label {PHY RX DataVref Ctrl} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datavref/phy_rx_datavref_ctrl
add wave -noupdate -group {DATAVREF} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_datavref/tx_pt_en
add wave -noupdate -group {DATAVREF} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_datavref/rx_pt_en

add wave -noupdate -group {SPEEDIDLE} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/SPEEDIDLE/current_state
add wave -noupdate -group {SPEEDIDLE} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_speedidle/timeout_timer_en
add wave -noupdate -group {SPEEDIDLE} -label {PHY Negotiated Speed} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_speedidle/phy_negotiated_speed

add wave -noupdate -group {TXSELFCAL} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/TXSELFCAL/current_state
add wave -noupdate -group {TXSELFCAL} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_txselfcal/timeout_timer_en
add wave -noupdate -group {TXSELFCAL} -label {PHY TX Selfcal En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_txselfcal/phy_tx_selfcal_en

add wave -noupdate -group {RXCLKCAL} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/RXCLKCAL/current_state
add wave -noupdate -group {RXCLKCAL} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_rxclkcal/timeout_timer_en
add wave -noupdate -group {RXCLKCAL} -label {RX Clock Lock En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_rxclkcal/phy_rx_clock_lock_en
add wave -noupdate -group {RXCLKCAL} -label {TX Tckn Shift En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_rxclkcal/phy_tx_tckn_shift_en

add wave -noupdate -group {VALTRAINCENTER} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/VALTRAINCENTER/current_state
add wave -noupdate -group {VALTRAINCENTER} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valtraincenter/timeout_timer_en
add wave -noupdate -group {VALTRAINCENTER} -label {Analog Settle En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valtraincenter/analog_settle_timer_en
add wave -noupdate -group {VALTRAINCENTER} -label {PHY TX Val PI Phase} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valtraincenter/phy_tx_val_pi_phase_ctrl
add wave -noupdate -group {VALTRAINCENTER} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_valtraincenter/tx_pt_en
add wave -noupdate -group {VALTRAINCENTER} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_valtraincenter/rx_pt_en

add wave -noupdate -group {VALTRAINVREF} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/VALTRAINVREF/current_state
add wave -noupdate -group {VALTRAINVREF} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valtrainvref/timeout_timer_en
add wave -noupdate -group {VALTRAINVREF} -label {Analog Settle En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valtrainvref/analog_settle_timer_en
add wave -noupdate -group {VALTRAINVREF} -label {PHY RX ValVref Ctrl} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_valtrainvref/phy_rx_valvref_ctrl
add wave -noupdate -group {VALTRAINVREF} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_valtrainvref/tx_pt_en
add wave -noupdate -group {VALTRAINVREF} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_valtrainvref/rx_pt_en

add wave -noupdate -group {DATATRAINCENTER1} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/DTC1/current_state
add wave -noupdate -group {DATATRAINCENTER1} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatraincenter1/timeout_timer_en
add wave -noupdate -group {DATATRAINCENTER1} -label {Analog Settle En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatraincenter1/analog_settle_timer_en
add wave -noupdate -group {DATATRAINCENTER1} -label {PHY TX Data PI Phase} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatraincenter1/phy_tx_data_pi_phase_ctrl
add wave -noupdate -group {DATATRAINCENTER1} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_datatraincenter1/tx_pt_en
add wave -noupdate -group {DATATRAINCENTER1} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_datatraincenter1/rx_pt_en

add wave -noupdate -group {DATATRAINVREF} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/DTVREF/current_state
add wave -noupdate -group {DATATRAINVREF} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatrainvref/timeout_timer_en
add wave -noupdate -group {DATATRAINVREF} -label {Analog Settle En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatrainvref/analog_settle_timer_en
add wave -noupdate -group {DATATRAINVREF} -label {PHY RX DataVref Ctrl} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatrainvref/phy_rx_datavref_ctrl
add wave -noupdate -group {DATATRAINVREF} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_datatrainvref/tx_pt_en
add wave -noupdate -group {DATATRAINVREF} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_datatrainvref/rx_pt_en

add wave -noupdate -group {RXDESKEW} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/RXDESKEW/current_state
add wave -noupdate -group {RXDESKEW} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_rxdeskew/timeout_timer_en
add wave -noupdate -group {RXDESKEW} -label {Analog Settle En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_rxdeskew/analog_settle_timer_en
add wave -noupdate -group {RXDESKEW} -label {PHY TX EQ Preset} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_rxdeskew/phy_tx_eq_preset_ctrl
add wave -noupdate -group {RXDESKEW} -label {PHY RX Deskew} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_rxdeskew/phy_rx_deskew_ctrl
add wave -noupdate -group {RXDESKEW} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_rxdeskew/tx_pt_en
add wave -noupdate -group {RXDESKEW} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_rxdeskew/rx_pt_en

add wave -noupdate -group {DATATRAINCENTER2} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/DTC2/current_state
add wave -noupdate -group {DATATRAINCENTER2} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatraincenter2/timeout_timer_en
add wave -noupdate -group {DATATRAINCENTER2} -label {Analog Settle En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatraincenter2/analog_settle_timer_en
add wave -noupdate -group {DATATRAINCENTER2} -label {PHY TX Data PI Phase} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_datatraincenter2/phy_tx_data_pi_phase_ctrl
add wave -noupdate -group {DATATRAINCENTER2} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_datatraincenter2/tx_pt_en
add wave -noupdate -group {DATATRAINCENTER2} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_datatraincenter2/rx_pt_en

add wave -noupdate -group {LINKSPEED} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/LINKSPEED/current_state
add wave -noupdate -group {LINKSPEED} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_linkspeed/timeout_timer_en
add wave -noupdate -group {LINKSPEED} -label {TX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_linkspeed/tx_pt_en
add wave -noupdate -group {LINKSPEED} -label {RX PT En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/d2c_linkspeed/rx_pt_en

add wave -noupdate -group {REPAIR} -label {Current State} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/REPAIR/current_state
add wave -noupdate -group {REPAIR} -label {Timeout En} /wrapper_MBTRAIN_tb/DUT/u_wrapper_MBTRAIN/intf_repair/timeout_timer_en


# --- D2C Errors ---
add wave -noupdate -divider {D2C Error Status}
add wave -noupdate -label {Aggregate Error} /wrapper_MBTRAIN_tb/intf/mb_rx_aggr_err
add wave -noupdate -label {Per-lane Error} /wrapper_MBTRAIN_tb/intf/mb_rx_perlane_err
add wave -noupdate -label {Val Error} /wrapper_MBTRAIN_tb/intf/mb_rx_val_err
add wave -noupdate -label {Clk Error} /wrapper_MBTRAIN_tb/intf/mb_rx_clk_err

# --- Physical Layer Controls ---
add wave -noupdate -divider {Physical Controls}
add wave -noupdate -label {PHY TX Val PI Phase} /wrapper_MBTRAIN_tb/intf/phy_tx_val_pi_phase_ctrl
add wave -noupdate -label {PHY RX Val Vref} /wrapper_MBTRAIN_tb/intf/phy_rx_valvref_ctrl

# --- Testbench Control ---
add wave -noupdate -divider {Testbench Logging}
add wave -noupdate -label {Scenario Counter} /wrapper_MBTRAIN_tb/test_no
add wave -noupdate -label {Success Count} /wrapper_MBTRAIN_tb/success_count
add wave -noupdate -label {Fail Count} /wrapper_MBTRAIN_tb/fail_count

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
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
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {10 ns}
