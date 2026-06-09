onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /MB_TOP_TB/i_rst_n
add wave -noupdate /MB_TOP_TB/o_pll_clk
add wave -noupdate /MB_TOP_TB/o_mb_clk

add wave -noupdate -expand -group TX_Side /MB_TOP_TB/i_tx_raw_data
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/i_tx_mapper_en
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/i_tx_lp_irdy
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/i_tx_lp_valid
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/i_tx_lfsr_state
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/i_tx_valid_pattern_en
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/i_tx_clk_pattern_en
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/o_tx_mapper_ready
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/o_tx_lfsr_done
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/o_tx_valid_done
add wave -noupdate -expand -group TX_Side /MB_TOP_TB/o_tx_clk_done

add wave -noupdate -expand -group Physical_Loopback /MB_TOP_TB/o_loopback_clk_p
add wave -noupdate -expand -group Physical_Loopback /MB_TOP_TB/o_loopback_clk_n
add wave -noupdate -expand -group Physical_Loopback /MB_TOP_TB/o_loopback_valid
add wave -noupdate -expand -group Physical_Loopback /MB_TOP_TB/o_loopback_data

add wave -noupdate -expand -group RX_Side /MB_TOP_TB/i_rx_clk_detector_en
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/i_rx_state
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/i_rx_enable_buffer
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/i_rx_enable_detector
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_de_ser_done
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_detection_result
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_valid_frame_detect
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_error_done
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_error_counter
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_per_lane_error
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_clk_p_pattern_pass
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_clk_n_pattern_pass
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_track_pattern_pass
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_pl_valid
add wave -noupdate -expand -group RX_Side /MB_TOP_TB/o_rx_out_data

TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 262
configure wave -valuecolwidth 255
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
