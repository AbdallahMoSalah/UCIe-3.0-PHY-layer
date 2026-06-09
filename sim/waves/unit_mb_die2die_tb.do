onerror {resume}
quietly WaveActivateNextPane {} 0

# --- Group: Clocks
add wave -noupdate -group "Clocks" -color "orange" /unit_mb_die2die_tb/o_pll_clk0
add wave -noupdate -group "Clocks" -color "orange" /unit_mb_die2die_tb/o_pll_clk1
add wave -noupdate -group "Clocks" -color "yellow" /unit_mb_die2die_tb/lclk0
add wave -noupdate -group "Clocks" -color "yellow" /unit_mb_die2die_tb/lclk1

# --- Group: Global & Control
add wave -noupdate -group "Global & Control" -color "cyan" /unit_mb_die2die_tb/i_rst_n
add wave -noupdate -group "Global & Control" -color "cyan" /unit_mb_die2die_tb/lclk_g
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_pll_speed_sel
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_lfsr_state
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_rx_mode
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_mapper_en
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_clk_pattern_en
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_clk_detector_en
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_clk_embedded_en
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_pcmp_enable
add wave -noupdate -group "Global & Control" /unit_mb_die2die_tb/i_vcmp_enable

# --- Group: Die 0 TX -> Die 1 RX (Serial Interface)
add wave -noupdate -group "Die 0 TX -> Die 1 RX" /unit_mb_die2die_tb/d0_TCKP_P
add wave -noupdate -group "Die 0 TX -> Die 1 RX" /unit_mb_die2die_tb/d0_TCKN_P
add wave -noupdate -group "Die 0 TX -> Die 1 RX" /unit_mb_die2die_tb/d0_TTRK_P
add wave -noupdate -group "Die 0 TX -> Die 1 RX" /unit_mb_die2die_tb/d0_TVLD_P
add wave -noupdate -group "Die 0 TX -> Die 1 RX" /unit_mb_die2die_tb/d0_TD_P

# --- Group: Die 1 TX -> Die 0 RX (Serial Interface)
add wave -noupdate -group "Die 1 TX -> Die 0 RX" /unit_mb_die2die_tb/d1_TCKP_P
add wave -noupdate -group "Die 1 TX -> Die 0 RX" /unit_mb_die2die_tb/d1_TCKN_P
add wave -noupdate -group "Die 1 TX -> Die 0 RX" /unit_mb_die2die_tb/d1_TTRK_P
add wave -noupdate -group "Die 1 TX -> Die 0 RX" /unit_mb_die2die_tb/d1_TVLD_P
add wave -noupdate -group "Die 1 TX -> Die 0 RX" /unit_mb_die2die_tb/d1_TD_P

# --- Group: Die 0 Protocol Interface (Data)
add wave -noupdate -group "Die 0 Protocol Interface" /unit_mb_die2die_tb/lp_irdy
add wave -noupdate -group "Die 0 Protocol Interface" /unit_mb_die2die_tb/lp_valid
add wave -noupdate -group "Die 0 Protocol Interface" -radix hexadecimal /unit_mb_die2die_tb/lp_data0
add wave -noupdate -group "Die 0 Protocol Interface" /unit_mb_die2die_tb/o_pl_valid0
add wave -noupdate -group "Die 0 Protocol Interface" -radix hexadecimal /unit_mb_die2die_tb/o_out_data0

# --- Group: Die 1 Protocol Interface (Data)
add wave -noupdate -group "Die 1 Protocol Interface" /unit_mb_die2die_tb/lp_irdy
add wave -noupdate -group "Die 1 Protocol Interface" /unit_mb_die2die_tb/lp_valid
add wave -noupdate -group "Die 1 Protocol Interface" -radix hexadecimal /unit_mb_die2die_tb/lp_data1
add wave -noupdate -group "Die 1 Protocol Interface" /unit_mb_die2die_tb/o_pl_valid1
add wave -noupdate -group "Die 1 Protocol Interface" -radix hexadecimal /unit_mb_die2die_tb/o_out_data1

# --- Group: Die 0 RX Internal
add wave -noupdate -group "Die 0 RX Internal" /unit_mb_die2die_tb/die0/u_rx_top/sample_clk
add wave -noupdate -group "Die 0 RX Internal" /unit_mb_die2die_tb/die0/u_rx_top/o_valid_frame_pulse
add wave -noupdate -group "Die 0 RX Internal" /unit_mb_die2die_tb/die0/u_rx_top/o_data_valid
add wave -noupdate -group "Die 0 RX Internal" /unit_mb_die2die_tb/die0/u_rx_top/u_lfsr_rx/current_state
add wave -noupdate -group "Die 0 RX Internal" /unit_mb_die2die_tb/die0/u_rx_top/u_lfsr_rx/rx_lfsr_lane
add wave -noupdate -group "Die 0 RX Internal" -radix hexadecimal /unit_mb_die2die_tb/die0/u_rx_top/o_rx_lane

# --- Group: Die 1 RX Internal
add wave -noupdate -group "Die 1 RX Internal" /unit_mb_die2die_tb/die1/u_rx_top/sample_clk
add wave -noupdate -group "Die 1 RX Internal" /unit_mb_die2die_tb/die1/u_rx_top/o_valid_frame_pulse
add wave -noupdate -group "Die 1 RX Internal" /unit_mb_die2die_tb/die1/u_rx_top/o_data_valid
add wave -noupdate -group "Die 1 RX Internal" /unit_mb_die2die_tb/die1/u_rx_top/u_lfsr_rx/current_state
add wave -noupdate -group "Die 1 RX Internal" /unit_mb_die2die_tb/die1/u_rx_top/u_lfsr_rx/rx_lfsr_lane
add wave -noupdate -group "Die 1 RX Internal" -radix hexadecimal /unit_mb_die2die_tb/die1/u_rx_top/o_rx_lane

# --- Group: Calibration & Test Status
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_clk_done0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_clk_done1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_clk_p_pass0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_clk_n_pass0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_track_pass0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_clk_p_pass1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_clk_n_pass1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_track_pass1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_valid_done0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_valid_done1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_lfsr_tx_done0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_lfsr_tx_done1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_vcmp_done0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_vcmp_pass0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_vcmp_done1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_vcmp_pass1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_pcmp_done0
add wave -noupdate -group "Calibration & Test Status" -radix hexadecimal /unit_mb_die2die_tb/o_pcmp_per_lane_pass0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_pcmp_agg_error0
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_pcmp_done1
add wave -noupdate -group "Calibration & Test Status" -radix hexadecimal /unit_mb_die2die_tb/o_pcmp_per_lane_pass1
add wave -noupdate -group "Calibration & Test Status" /unit_mb_die2die_tb/o_pcmp_agg_error1

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
configure wave -namecolwidth 250
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
WaveRestoreZoom {0 ns} {30 us}
