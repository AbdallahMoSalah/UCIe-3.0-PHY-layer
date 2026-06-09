onerror {resume}
quietly WaveActivateNextPane {} 0

# =============================================================================
# Wave layout for MB_TOP_tb   (DUT instance = /MB_TOP_tb/dut)
#   make debug CONFIG=MB_TOP TOP=MB_TOP_tb
#
# Groups:
#   Clocks & Reset
#   TB Control
#   TX Status
#   RX Status
#   CLK Pattern (Phase 1)
#   VALID TX/RX (Phase 2)
#   LFSR Training (Phase 3)
#   Serializer — valid lane
#   Deserializer — valid lane
#   DATA_TRANSFER (Phase 4)
# =============================================================================

# ── Clocks & Reset ────────────────────────────────────────────────────────
add wave -noupdate -group {Clocks & Reset} -color Yellow      /MB_TOP_tb/o_pll_clk
add wave -noupdate -group {Clocks & Reset} -color {Cornflower Blue} /MB_TOP_tb/o_mb_clk
add wave -noupdate -group {Clocks & Reset} -color Magenta     /MB_TOP_tb/i_rst_n

# ── TB Control ────────────────────────────────────────────────────────────
add wave -noupdate -group {TB Control} -radix unsigned        /MB_TOP_tb/test_num
add wave -noupdate -group {TB Control} -radix binary          /MB_TOP_tb/i_ltsm_state
add wave -noupdate -group {TB Control}                        /MB_TOP_tb/i_active_state_entered
add wave -noupdate -group {TB Control} -radix binary          /MB_TOP_tb/i_width_deg
add wave -noupdate -group {TB Control}                        /MB_TOP_tb/i_pll_en
add wave -noupdate -group {TB Control} -radix binary          /MB_TOP_tb/i_pll_speed_sel

# ── TX Status ─────────────────────────────────────────────────────────────
add wave -noupdate -group {TX Status} -color Green            /MB_TOP_tb/o_clk_done
add wave -noupdate -group {TX Status} -color Green            /MB_TOP_tb/o_valid_done
add wave -noupdate -group {TX Status} -color Green            /MB_TOP_tb/o_lfsr_tx_done
add wave -noupdate -group {TX Status} -color Green            /MB_TOP_tb/o_mapper_ready

# ── RX Status ─────────────────────────────────────────────────────────────
add wave -noupdate -group {RX Status} -color Cyan             /MB_TOP_tb/de_ser_done
add wave -noupdate -group {RX Status} -color Cyan             /MB_TOP_tb/detection_result
add wave -noupdate -group {RX Status}                         /MB_TOP_tb/o_valid_frame_detect
add wave -noupdate -group {RX Status} -color Cyan             /MB_TOP_tb/o_error_done
add wave -noupdate -group {RX Status} -radix binary           /MB_TOP_tb/o_per_lane_error
add wave -noupdate -group {RX Status} -radix unsigned         /MB_TOP_tb/o_error_counter
add wave -noupdate -group {RX Status} -color Cyan             /MB_TOP_tb/pl_valid

# ── Phase 1: CLK Pattern ──────────────────────────────────────────────────
add wave -noupdate -group {CLK Pattern} /MB_TOP_tb/i_clk_pattern_en
add wave -noupdate -group {CLK Pattern} /MB_TOP_tb/clk_detector_en
add wave -noupdate -group {CLK Pattern} -color Orange /MB_TOP_tb/dut/u_tx/o_clk_p
add wave -noupdate -group {CLK Pattern} -color Orange /MB_TOP_tb/dut/u_tx/o_clk_n
add wave -noupdate -group {CLK Pattern} /MB_TOP_tb/dut/u_tx/o_clk_track
add wave -noupdate -group {CLK Pattern} -color Green  /MB_TOP_tb/o_clk_done
add wave -noupdate -group {CLK Pattern} -color Cyan   /MB_TOP_tb/clk_p_pattern_pass
add wave -noupdate -group {CLK Pattern} -color Cyan   /MB_TOP_tb/clk_n_pattern_pass
add wave -noupdate -group {CLK Pattern} -color Cyan   /MB_TOP_tb/track_pattern_pass

# ── Phase 2: VALID TX → RX ───────────────────────────────────────────────
add wave -noupdate -group {VALID TX-RX} /MB_TOP_tb/i_valid_pattern_en
add wave -noupdate -group {VALID TX-RX} /MB_TOP_tb/dut/u_tx/valid_ser_en
add wave -noupdate -group {VALID TX-RX} -radix hexadecimal /MB_TOP_tb/dut/u_tx/valid_word
add wave -noupdate -group {VALID TX-RX} -color Orange /MB_TOP_tb/dut/u_tx/o_tx_valid
add wave -noupdate -group {VALID TX-RX} -color Green  /MB_TOP_tb/o_valid_done
add wave -noupdate -group {VALID TX-RX} /MB_TOP_tb/i_enable_cons
add wave -noupdate -group {VALID TX-RX} /MB_TOP_tb/i_enable_detector
add wave -noupdate -group {VALID TX-RX} -radix hexadecimal /MB_TOP_tb/dut/u_rx/valid_par_data_w
add wave -noupdate -group {VALID TX-RX} /MB_TOP_tb/dut/u_rx/enable_des_valid_frame_w
add wave -noupdate -group {VALID TX-RX} -color Cyan /MB_TOP_tb/detection_result

# ── Phase 3: LFSR Training ────────────────────────────────────────────────
add wave -noupdate -group {LFSR Training} /MB_TOP_tb/i_enable_buffer
add wave -noupdate -group {LFSR Training} -radix binary /MB_TOP_tb/dut/u_tx/u_lfsr_tx/i_state
add wave -noupdate -group {LFSR Training} /MB_TOP_tb/dut/u_tx/lfsr_ser_en
add wave -noupdate -group {LFSR Training} -color Green /MB_TOP_tb/o_lfsr_tx_done
add wave -noupdate -group {LFSR Training} /MB_TOP_tb/dut/u_rx/pattern_comp_en_w
add wave -noupdate -group {LFSR Training} -color Cyan  /MB_TOP_tb/o_error_done
add wave -noupdate -group {LFSR Training} -radix binary /MB_TOP_tb/o_per_lane_error
add wave -noupdate -group {LFSR Training} -radix unsigned /MB_TOP_tb/o_error_counter

# ── Valid-lane Serializer (TX) ────────────────────────────────────────────
add wave -noupdate -group {Valid Serializer} /MB_TOP_tb/dut/u_tx/u_valid_ser/Ser_en
add wave -noupdate -group {Valid Serializer} /MB_TOP_tb/dut/u_tx/u_valid_ser/load_toggle_mb
add wave -noupdate -group {Valid Serializer} /MB_TOP_tb/dut/u_tx/u_valid_ser/rising_ser_en_pll
add wave -noupdate -group {Valid Serializer} -radix hexadecimal /MB_TOP_tb/dut/u_tx/u_valid_ser/load_reg
add wave -noupdate -group {Valid Serializer} /MB_TOP_tb/dut/u_tx/u_valid_ser/SER_pos_reg
add wave -noupdate -group {Valid Serializer} /MB_TOP_tb/dut/u_tx/u_valid_ser/SER_neg_reg
add wave -noupdate -group {Valid Serializer} -color Orange /MB_TOP_tb/dut/u_tx/o_tx_valid

# ── Valid-lane Deserializer (RX) ──────────────────────────────────────────
add wave -noupdate -group {Valid Deserializer} /MB_TOP_tb/dut/u_rx/u_MB_DES_VALID/ser_data_in
add wave -noupdate -group {Valid Deserializer} /MB_TOP_tb/dut/u_rx/u_MB_DES_VALID/o_state
add wave -noupdate -group {Valid Deserializer} -radix unsigned /MB_TOP_tb/dut/u_rx/u_MB_DES_VALID/o_count
add wave -noupdate -group {Valid Deserializer} -radix hexadecimal /MB_TOP_tb/dut/u_rx/u_MB_DES_VALID/save_data
add wave -noupdate -group {Valid Deserializer} /MB_TOP_tb/dut/u_rx/enable_des_valid_frame_w
add wave -noupdate -group {Valid Deserializer} /MB_TOP_tb/de_ser_done

# ── Phase 4: DATA_TRANSFER ────────────────────────────────────────────────
add wave -noupdate -group {DATA_TRANSFER} /MB_TOP_tb/i_mapper_en
add wave -noupdate -group {DATA_TRANSFER} /MB_TOP_tb/i_lp_irdy
add wave -noupdate -group {DATA_TRANSFER} /MB_TOP_tb/i_lp_valid
add wave -noupdate -group {DATA_TRANSFER} -color Green /MB_TOP_tb/o_mapper_ready
add wave -noupdate -group {DATA_TRANSFER} -radix hexadecimal /MB_TOP_tb/i_raw_data
add wave -noupdate -group {DATA_TRANSFER} -color Orange -radix hexadecimal /MB_TOP_tb/dut/u_tx/o_tx_data
add wave -noupdate -group {DATA_TRANSFER} /MB_TOP_tb/demapper_en
add wave -noupdate -group {DATA_TRANSFER} /MB_TOP_tb/rx_data_valid
add wave -noupdate -group {DATA_TRANSFER} -color Cyan  /MB_TOP_tb/pl_valid
add wave -noupdate -group {DATA_TRANSFER} -radix hexadecimal /MB_TOP_tb/o_out_data

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 120
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
WaveRestoreZoom {0 ps} {5000 ns}
