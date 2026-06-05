onerror {resume}
quietly WaveActivateNextPane {} 0

# =====================================================================
#  Clocks / reset / global control
# =====================================================================
add wave -noupdate -group CLK/RST /mb_framed_path_tb/MB_clk
add wave -noupdate -group CLK/RST /mb_framed_path_tb/pll_tx
add wave -noupdate -group CLK/RST /mb_framed_path_tb/pll_rx
add wave -noupdate -group CLK/RST /mb_framed_path_tb/i_rst_n
add wave -noupdate -group CLK/RST /mb_framed_path_tb/des_en
add wave -noupdate -group CLK/RST /mb_framed_path_tb/ser_en_w
add wave -noupdate -group CLK/RST -radix unsigned /mb_framed_path_tb/wdeg

# =====================================================================
#  ALL DATA SERIALIZERS  -> serial outputs (16 lanes)
# =====================================================================
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[0]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[1]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[2]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[3]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[4]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[5]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[6]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[7]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[8]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[9]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[10]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[11]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[12]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[13]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[14]/u_ser/SER_out
add wave -noupdate -group {DATA SERIALIZERS (SER_out)} /mb_framed_path_tb/g_lane[15]/u_ser/SER_out

# =====================================================================
#  ALL DATA DESERIALIZERS -> parallel outputs (16 lanes)
# =====================================================================
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[0]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[1]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[2]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[3]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[4]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[5]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[6]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[7]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[8]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[9]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[10]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[11]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[12]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[13]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[14]/u_des/par_data_out
add wave -noupdate -group {DATA DESERIALIZERS (par_data_out)} -radix hexadecimal /mb_framed_path_tb/g_lane[15]/u_des/par_data_out

# =====================================================================
#  Mapper  (u_map)  -- interface
# =====================================================================
add wave -noupdate -group {Mapper (u_map)} /mb_framed_path_tb/u_map/i_clk
add wave -noupdate -group {Mapper (u_map)} /mb_framed_path_tb/u_map/i_rst_n
add wave -noupdate -group {Mapper (u_map)} -radix hexadecimal /mb_framed_path_tb/u_map/i_in_data
add wave -noupdate -group {Mapper (u_map)} /mb_framed_path_tb/u_map/mapper_en
add wave -noupdate -group {Mapper (u_map)} -radix unsigned /mb_framed_path_tb/u_map/i_width_deg_map
add wave -noupdate -group {Mapper (u_map)} /mb_framed_path_tb/u_map/lp_irdy
add wave -noupdate -group {Mapper (u_map)} /mb_framed_path_tb/u_map/lp_valid
add wave -noupdate -group {Mapper (u_map)} -radix hexadecimal /mb_framed_path_tb/u_map/o_lane_0
add wave -noupdate -group {Mapper (u_map)} -radix hexadecimal /mb_framed_path_tb/u_map/o_lane_1
add wave -noupdate -group {Mapper (u_map)} -radix hexadecimal /mb_framed_path_tb/u_map/o_lane_2
add wave -noupdate -group {Mapper (u_map)} -radix hexadecimal /mb_framed_path_tb/u_map/o_lane_3
add wave -noupdate -group {Mapper (u_map)} /mb_framed_path_tb/u_map/out_scramble_en
add wave -noupdate -group {Mapper (u_map)} /mb_framed_path_tb/u_map/mapper_ready

# =====================================================================
#  LFSR_TX  (u_lfsr_tx)  -- interface
# =====================================================================
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} /mb_framed_path_tb/u_lfsr_tx/i_clk
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} /mb_framed_path_tb/u_lfsr_tx/i_rst_n
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} -radix unsigned /mb_framed_path_tb/u_lfsr_tx/i_state
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} /mb_framed_path_tb/u_lfsr_tx/i_scramble_en
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} -radix unsigned /mb_framed_path_tb/u_lfsr_tx/i_width_deg_lfsr
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} /mb_framed_path_tb/u_lfsr_tx/i_reversal_en
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} /mb_framed_path_tb/u_lfsr_tx/i_active_state_entered
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} -radix hexadecimal /mb_framed_path_tb/u_lfsr_tx/i_lane
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} -radix hexadecimal /mb_framed_path_tb/u_lfsr_tx/o_lane
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} /mb_framed_path_tb/u_lfsr_tx/o_ser_en_lfsr
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} /mb_framed_path_tb/u_lfsr_tx/o_Lfsr_tx_done
add wave -noupdate -group {LFSR_TX (u_lfsr_tx)} /mb_framed_path_tb/u_lfsr_tx/o_valid_frame_en

# =====================================================================
#  VALID_TX  (u_valid_tx)  -- interface
# =====================================================================
add wave -noupdate -group {VALID_TX (u_valid_tx)} /mb_framed_path_tb/u_valid_tx/i_clk
add wave -noupdate -group {VALID_TX (u_valid_tx)} /mb_framed_path_tb/u_valid_tx/i_rst_n
add wave -noupdate -group {VALID_TX (u_valid_tx)} /mb_framed_path_tb/u_valid_tx/valid_pattern_en
add wave -noupdate -group {VALID_TX (u_valid_tx)} /mb_framed_path_tb/u_valid_tx/ser_en_lfsr_i
add wave -noupdate -group {VALID_TX (u_valid_tx)} /mb_framed_path_tb/u_valid_tx/ser_en_o
add wave -noupdate -group {VALID_TX (u_valid_tx)} /mb_framed_path_tb/u_valid_tx/O_done
add wave -noupdate -group {VALID_TX (u_valid_tx)} -radix hexadecimal /mb_framed_path_tb/u_valid_tx/o_TVLD_L

# =====================================================================
#  VALID serializer  (u_valid_ser, MB_SERIALIZER)  -- interface
# =====================================================================
add wave -noupdate -group {VALID SER (u_valid_ser)} /mb_framed_path_tb/u_valid_ser/mb_clk
add wave -noupdate -group {VALID SER (u_valid_ser)} /mb_framed_path_tb/u_valid_ser/PLL_clk
add wave -noupdate -group {VALID SER (u_valid_ser)} /mb_framed_path_tb/u_valid_ser/i_rst_n
add wave -noupdate -group {VALID SER (u_valid_ser)} /mb_framed_path_tb/u_valid_ser/Ser_en
add wave -noupdate -group {VALID SER (u_valid_ser)} -radix hexadecimal /mb_framed_path_tb/u_valid_ser/in_data
add wave -noupdate -group {VALID SER (u_valid_ser)} -color {Orange Red} /mb_framed_path_tb/u_valid_ser/SER_out

# =====================================================================
#  FRAMER  (u_framer, MB_DESERIALIZER_VALID)  -- interface
# =====================================================================
add wave -noupdate -group {FRAMER (u_framer)} /mb_framed_path_tb/u_framer/MB_clk
add wave -noupdate -group {FRAMER (u_framer)} /mb_framed_path_tb/u_framer/pll_clk
add wave -noupdate -group {FRAMER (u_framer)} /mb_framed_path_tb/u_framer/i_rst_n
add wave -noupdate -group {FRAMER (u_framer)} /mb_framed_path_tb/u_framer/ser_valid_en
add wave -noupdate -group {FRAMER (u_framer)} -color {Orange Red} /mb_framed_path_tb/u_framer/ser_data_in
add wave -noupdate -group {FRAMER (u_framer)} -color Magenta /mb_framed_path_tb/u_framer/o_frame_start
add wave -noupdate -group {FRAMER (u_framer)} -color Cyan /mb_framed_path_tb/u_framer/o_word_load
add wave -noupdate -group {FRAMER (u_framer)} /mb_framed_path_tb/u_framer/enable_des_valid_frame
add wave -noupdate -group {FRAMER (u_framer)} -radix hexadecimal /mb_framed_path_tb/u_framer/par_data_out
add wave -noupdate -group {FRAMER (u_framer)} /mb_framed_path_tb/u_framer/de_ser_done

# ---- FRAMER internals (framing logic) -------------------------------
add wave -noupdate -group {FRAMER internals} /mb_framed_path_tb/u_framer/r_data_pos
add wave -noupdate -group {FRAMER internals} /mb_framed_path_tb/u_framer/r_data_pos_d
add wave -noupdate -group {FRAMER internals} -color Yellow /mb_framed_path_tb/u_framer/val_pos_rise
add wave -noupdate -group {FRAMER internals} -color {Spring Green} /mb_framed_path_tb/u_framer/locked
add wave -noupdate -group {FRAMER internals} -radix unsigned /mb_framed_path_tb/u_framer/pair_cnt
add wave -noupdate -group {FRAMER internals} -radix hexadecimal /mb_framed_path_tb/u_framer/shift_reg
add wave -noupdate -group {FRAMER internals} -radix hexadecimal /mb_framed_path_tb/u_framer/save_data

# =====================================================================
#  LFSR_RX  (u_lfsr_rx)  -- interface
# =====================================================================
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} /mb_framed_path_tb/u_lfsr_rx/i_clk
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} /mb_framed_path_tb/u_lfsr_rx/i_rst_n
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} -radix unsigned /mb_framed_path_tb/u_lfsr_rx/i_state
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} -radix unsigned /mb_framed_path_tb/u_lfsr_rx/i_width_deg_lfsr
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} /mb_framed_path_tb/u_lfsr_rx/i_active_state_entered
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} /mb_framed_path_tb/u_lfsr_rx/i_descramble_en
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} /mb_framed_path_tb/u_lfsr_rx/i_enable_buffer
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} -radix hexadecimal /mb_framed_path_tb/u_lfsr_rx/i_data_in
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} -radix hexadecimal /mb_framed_path_tb/u_lfsr_rx/o_Data_by
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} -radix hexadecimal /mb_framed_path_tb/u_lfsr_rx/o_final_gene
add wave -noupdate -group {LFSR_RX (u_lfsr_rx)} /mb_framed_path_tb/u_lfsr_rx/pattern_comp_en

# =====================================================================
#  Demapper  (u_demap)  -- interface
# =====================================================================
add wave -noupdate -group {Demapper (u_demap)} /mb_framed_path_tb/u_demap/i_clk
add wave -noupdate -group {Demapper (u_demap)} /mb_framed_path_tb/u_demap/i_rst_n
add wave -noupdate -group {Demapper (u_demap)} -radix hexadecimal /mb_framed_path_tb/u_demap/i_lane_0
add wave -noupdate -group {Demapper (u_demap)} -radix hexadecimal /mb_framed_path_tb/u_demap/i_lane_1
add wave -noupdate -group {Demapper (u_demap)} -radix hexadecimal /mb_framed_path_tb/u_demap/i_lane_2
add wave -noupdate -group {Demapper (u_demap)} -radix hexadecimal /mb_framed_path_tb/u_demap/i_lane_3
add wave -noupdate -group {Demapper (u_demap)} /mb_framed_path_tb/u_demap/demapper_en
add wave -noupdate -group {Demapper (u_demap)} /mb_framed_path_tb/u_demap/rx_data_valid
add wave -noupdate -group {Demapper (u_demap)} -radix unsigned /mb_framed_path_tb/u_demap/i_width_deg_demap
add wave -noupdate -group {Demapper (u_demap)} /mb_framed_path_tb/u_demap/pl_valid
add wave -noupdate -group {Demapper (u_demap)} -radix hexadecimal /mb_framed_path_tb/u_demap/o_out_data

# =====================================================================
#  Self-check counters
# =====================================================================
add wave -noupdate -group CHECK -radix unsigned /mb_framed_path_tb/valid_ok_cnt
add wave -noupdate -group CHECK -radix unsigned /mb_framed_path_tb/valid_bad_cnt

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 260
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
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {2000 ns}
