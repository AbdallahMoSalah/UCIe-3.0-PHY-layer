onerror {resume}
quietly WaveActivateNextPane {} 0

# --- Group: Clocks
add wave -noupdate -group "Clocks" -color "orange" /unit_mb_train_seq_tb/o_pll_clk
add wave -noupdate -group "Clocks" -color "orange" /unit_mb_train_seq_tb/o_rx_pll_clk
add wave -noupdate -group "Clocks" -color "yellow" /unit_mb_train_seq_tb/lclk

# --- Group: Control
add wave -noupdate -group "Control" /unit_mb_train_seq_tb/i_rst_n
add wave -noupdate -group "Control" /unit_mb_train_seq_tb/i_pll_speed_sel
add wave -noupdate -group "Control" /unit_mb_train_seq_tb/i_lfsr_state
add wave -noupdate -group "Control" /unit_mb_train_seq_tb/i_rx_mode
add wave -noupdate -group "Control" /unit_mb_train_seq_tb/i_mapper_en
add wave -noupdate -group "Control" /unit_mb_train_seq_tb/i_clk_pattern_en
add wave -noupdate -group "Control" /unit_mb_train_seq_tb/i_clk_detector_en
add wave -noupdate -group "Control" /unit_mb_train_seq_tb/i_clk_embedded_en

# --- Group: TX top
add wave -noupdate -group "TX top" /unit_mb_train_seq_tb/dut/u_tx_top/lclk
add wave -noupdate -group "TX top" /unit_mb_train_seq_tb/dut/u_tx_top/TD_P
add wave -noupdate -group "TX top" /unit_mb_train_seq_tb/dut/u_tx_top/TVLD_P
add wave -noupdate -group "TX top" /unit_mb_train_seq_tb/dut/u_tx_top/TCKP_P

# --- Group: RX top
add wave -noupdate -group "RX top" /unit_mb_train_seq_tb/dut/u_rx_top/i_mb_clk
add wave -noupdate -group "RX top" /unit_mb_train_seq_tb/dut/u_rx_top/sample_clk
add wave -noupdate -group "RX top" /unit_mb_train_seq_tb/dut/u_rx_top/o_valid_frame_pulse
add wave -noupdate -group "RX top" /unit_mb_train_seq_tb/dut/u_rx_top/o_data_valid
add wave -noupdate -group "RX top" /unit_mb_train_seq_tb/dut/u_rx_top/u_lfsr_rx/current_state
add wave -noupdate -group "RX top" /unit_mb_train_seq_tb/dut/u_rx_top/u_lfsr_rx/rx_lfsr_lane
add wave -noupdate -group "RX top" -radix hexadecimal /unit_mb_train_seq_tb/dut/u_rx_top/o_rx_lane
add wave -noupdate -group "RX top" -radix hexadecimal /unit_mb_train_seq_tb/dut/u_rx_top/o_out_data
add wave -noupdate -group "RX top" /unit_mb_train_seq_tb/dut/u_rx_top/o_pl_valid

# --- Group: Valid Comparator
add wave -noupdate -group "Valid Comparator" /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_enable
add wave -noupdate -group "Valid Comparator" /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_mode
add wave -noupdate -group "Valid Comparator" -radix hexadecimal /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/i_valid_frame_data
add wave -noupdate -group "Valid Comparator" /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/o_done
add wave -noupdate -group "Valid Comparator" /unit_mb_train_seq_tb/dut/u_rx_top/u_valid_cmp/o_pass

# --- Group: Pattern Comparator
add wave -noupdate -group "Pattern Comparator" /unit_mb_train_seq_tb/dut/u_rx_top/u_pat_cmp/i_enable
add wave -noupdate -group "Pattern Comparator" /unit_mb_train_seq_tb/dut/u_rx_top/u_pat_cmp/o_done
add wave -noupdate -group "Pattern Comparator" -radix hexadecimal /unit_mb_train_seq_tb/dut/u_rx_top/u_pat_cmp/o_per_lane_pass

# --- Group: Clock Detector
add wave -noupdate -group "Clock Detector" /unit_mb_train_seq_tb/dut/u_rx_top/u_clk_det/clk_detector_en

# --- Group: Calibration & Test Status
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_clk_done
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_clk_p_pass
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_clk_n_pass
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_track_pass
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_valid_done
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_vcmp_done
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_vcmp_pass
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_lfsr_tx_done
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_pcmp_done
add wave -noupdate -group "Calibration & Test Status" -radix hexadecimal /unit_mb_train_seq_tb/o_pcmp_per_lane_pass
add wave -noupdate -group "Calibration & Test Status" /unit_mb_train_seq_tb/o_pcmp_agg_error

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
WaveRestoreZoom {0 ns} {25 us}
