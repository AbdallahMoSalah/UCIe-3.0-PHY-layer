onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group clk_detector /MB_RX_TOP_TB/dut/track_pattern_pass
add wave -noupdate -group clk_detector /MB_RX_TOP_TB/dut/track
add wave -noupdate -group clk_detector /MB_RX_TOP_TB/dut/clk_p_pattern_pass
add wave -noupdate -group clk_detector /MB_RX_TOP_TB/dut/clk_p
add wave -noupdate -group clk_detector /MB_RX_TOP_TB/dut/clk_n_pattern_pass
add wave -noupdate -group clk_detector /MB_RX_TOP_TB/dut/clk_n
add wave -noupdate -group clk_detector /MB_RX_TOP_TB/dut/clk_detector_en
add wave -noupdate -group VALID_Deserializer /MB_RX_TOP_TB/dut/ser_valid_en
add wave -noupdate -group VALID_Deserializer /MB_RX_TOP_TB/dut/SER_out
add wave -noupdate -group VALID_Deserializer /MB_RX_TOP_TB/dut/enable_des_valid_frame_w
add wave -noupdate -group VALID_Deserializer /MB_RX_TOP_TB/dut/valid_par_data_w
add wave -noupdate -group VALID_Deserializer /MB_RX_TOP_TB/dut/de_ser_done
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/ser_data_in
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/ser_data_en
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/data_deser_enable
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/deser_data_w
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_0
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_15
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_14
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_13
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_12
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_11
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_10
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_9
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_8
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_7
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_6
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_5
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_4
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_3
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_2
add wave -noupdate -group Data_Deserializer /MB_RX_TOP_TB/dut/de_ser_done_data_1
add wave -noupdate /MB_RX_TOP_TB/dut/valid_par_data_w
add wave -noupdate -group Valid_Detector /MB_RX_TOP_TB/dut/i_enable_detector
add wave -noupdate -group Valid_Detector /MB_RX_TOP_TB/dut/i_enable_cons
add wave -noupdate -group Valid_Detector /MB_RX_TOP_TB/dut/i_enable_128
add wave -noupdate -group Valid_Detector /MB_RX_TOP_TB/dut/i_max_error_threshold_valid
add wave -noupdate -group Valid_Detector /MB_RX_TOP_TB/dut/o_valid_frame_detect
add wave -noupdate -group Valid_Detector /MB_RX_TOP_TB/dut/detection_result
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/i_state
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/i_active_state_entered
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/i_width_deg_lfsr
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/gated_enable_buffer
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/i_descramble_en
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/deser_data_w
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/lfsr_gen_w
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/pattern_comp_en_w
add wave -noupdate -group LFSR_RX /MB_RX_TOP_TB/dut/lfsr_data_w
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/i_active_state_entered
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/pattern_comp_en_w
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/i_type_of_com
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/i_max_error_threshold_per_lane_ID
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/i_max_error_threshold_aggergate
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/lfsr_gen_w
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/lfsr_data_w
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/o_per_lane_error
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/o_error_done
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/o_error_counter
add wave -noupdate -group Pattern_comparator /MB_RX_TOP_TB/dut/comp_data_w
add wave -noupdate -group Demapper /MB_RX_TOP_TB/dut/comp_data_w
add wave -noupdate -group Demapper /MB_RX_TOP_TB/dut/demapper_en
add wave -noupdate -group Demapper /MB_RX_TOP_TB/dut/i_width_deg_demap
add wave -noupdate -group Demapper /MB_RX_TOP_TB/dut/rx_data_valid
add wave -noupdate -group Demapper /MB_RX_TOP_TB/dut/o_out_data
add wave -noupdate -group Demapper /MB_RX_TOP_TB/dut/pl_valid
add wave -noupdate /MB_RX_TOP_TB/dut/pll_clk
add wave -noupdate -color Magenta /MB_RX_TOP_TB/dut/i_rst_n
add wave -noupdate /MB_RX_TOP_TB/dut/MB_clk
add wave -noupdate /MB_RX_TOP_TB/dut/N_BYTES
add wave -noupdate /MB_RX_TOP_TB/dut/i_enable_buffer
add wave -noupdate /MB_RX_TOP_TB/dut/DATA_WIDTH
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {197859880 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 262
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
WaveRestoreZoom {191807832 ps} {203222583 ps}
