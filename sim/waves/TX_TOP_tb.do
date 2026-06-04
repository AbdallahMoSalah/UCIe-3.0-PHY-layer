onerror {resume}
quietly WaveActivateNextPane {} 0

# =============================================================================
# Wave layout for TX_TOP_tb  (DUT instance = /TX_TOP_tb/dut)
#   make run CONFIG=TX_TOP TOP=TX_TOP_tb MODE=debug
# Grouped to follow the TB phases:
#   Phase 1 CLK pattern / Phase 2 VALID / Phase 3 LFSR / Phase 4 DATA_TRANSFER
# =============================================================================

# ----- Clocks & reset --------------------------------------------------------
add wave -noupdate -group {Clocks & Reset} -color Yellow      /TX_TOP_tb/dut/pll_clk
add wave -noupdate -group {Clocks & Reset} -color {Cornflower Blue} /TX_TOP_tb/lclk
add wave -noupdate -group {Clocks & Reset} -color {Cornflower Blue} /TX_TOP_tb/dut/gated_lclk
add wave -noupdate -group {Clocks & Reset} -color Magenta     /TX_TOP_tb/i_rst_n
add wave -noupdate -group {Clocks & Reset}                    /TX_TOP_tb/lclk_g
add wave -noupdate -group {Clocks & Reset}                    /TX_TOP_tb/i_pll_speed_sel
add wave -noupdate -group {Clocks & Reset} -radix unsigned    /TX_TOP_tb/dut/pll_period

# ----- TB control / phase ----------------------------------------------------
add wave -noupdate -group {TB control} -radix unsigned        /TX_TOP_tb/test_num
add wave -noupdate -group {TB control}                        /TX_TOP_tb/i_pll_en
add wave -noupdate -group {TB control}                        /TX_TOP_tb/i_mapper_en
add wave -noupdate -group {TB control} -radix binary          /TX_TOP_tb/i_width_deg
add wave -noupdate -group {TB control}                        /TX_TOP_tb/i_clk_pattern_en
add wave -noupdate -group {TB control}                        /TX_TOP_tb/i_clk_embedded_en
add wave -noupdate -group {TB control}                        /TX_TOP_tb/i_valid_pattern_en
add wave -noupdate -group {TB control} -radix binary          /TX_TOP_tb/i_lfsr_state
add wave -noupdate -group {TB control}                        /TX_TOP_tb/i_reversal_en
add wave -noupdate -group {TB control}                        /TX_TOP_tb/i_active_state_entered

# ----- Done / status pulses --------------------------------------------------
add wave -noupdate -group {Status} -color Green                /TX_TOP_tb/o_clk_done
add wave -noupdate -group {Status} -color Green                /TX_TOP_tb/o_valid_done
add wave -noupdate -group {Status} -color Green                /TX_TOP_tb/o_lfsr_tx_done
add wave -noupdate -group {Status}                             /TX_TOP_tb/pl_trdy

# ----- Phase 1: CLK pattern generator (pll_clk domain) -----------------------
add wave -noupdate -group {CLK_PATTERN_GEN} /TX_TOP_tb/dut/u_clk_pattern_gen/i_clk
add wave -noupdate -group {CLK_PATTERN_GEN} /TX_TOP_tb/dut/u_clk_pattern_gen/clk_pattern_en
add wave -noupdate -group {CLK_PATTERN_GEN} /TX_TOP_tb/dut/u_clk_pattern_gen/clk_embedded_en
add wave -noupdate -group {CLK_PATTERN_GEN} -color Orange /TX_TOP_tb/TCKP_P
add wave -noupdate -group {CLK_PATTERN_GEN} -color Orange /TX_TOP_tb/TCKN_P
add wave -noupdate -group {CLK_PATTERN_GEN} /TX_TOP_tb/TTRK_P
add wave -noupdate -group {CLK_PATTERN_GEN} /TX_TOP_tb/o_clk_done

# ----- Mapper interface (lp_* / pl_trdy) -------------------------------------
add wave -noupdate -group {Mapper IF} -radix hexadecimal /TX_TOP_tb/lp_data
add wave -noupdate -group {Mapper IF} /TX_TOP_tb/lp_irdy
add wave -noupdate -group {Mapper IF} /TX_TOP_tb/lp_valid
add wave -noupdate -group {Mapper IF} /TX_TOP_tb/pl_trdy
add wave -noupdate -group {Mapper IF} /TX_TOP_tb/dut/mapper_scramble_en
add wave -noupdate -group {Mapper IF} -radix hexadecimal /TX_TOP_tb/dut/mapper_lane

# ----- Phase 3/4: LFSR_TX ----------------------------------------------------
add wave -noupdate -group {LFSR_TX} -radix binary       /TX_TOP_tb/dut/u_lfsr_tx/i_state
add wave -noupdate -group {LFSR_TX} /TX_TOP_tb/dut/u_lfsr_tx/i_scramble_en
add wave -noupdate -group {LFSR_TX} /TX_TOP_tb/dut/u_lfsr_tx/i_active_state_entered
add wave -noupdate -group {LFSR_TX} -radix hexadecimal  /TX_TOP_tb/dut/u_lfsr_tx/tx_lfsr
add wave -noupdate -group {LFSR_TX} -radix hexadecimal  /TX_TOP_tb/dut/lfsr_lane
add wave -noupdate -group {LFSR_TX} -color Green         /TX_TOP_tb/dut/lfsr_ser_en
add wave -noupdate -group {LFSR_TX} /TX_TOP_tb/dut/lfsr_valid_frame_en
add wave -noupdate -group {LFSR_TX} -color Green         /TX_TOP_tb/o_lfsr_tx_done

# ----- Phase 2: VALID_TX -----------------------------------------------------
add wave -noupdate -group {VALID_TX} /TX_TOP_tb/dut/u_valid_tx/valid_pattern_en
add wave -noupdate -group {VALID_TX} /TX_TOP_tb/dut/u_valid_tx/ser_en_lfsr_i
add wave -noupdate -group {VALID_TX} -radix hexadecimal /TX_TOP_tb/dut/valid_word
add wave -noupdate -group {VALID_TX} /TX_TOP_tb/dut/valid_ser_en
add wave -noupdate -group {VALID_TX} -color Green        /TX_TOP_tb/o_valid_done

# ----- Serializers / physical outputs (pll_clk domain) -----------------------
add wave -noupdate -group {Serial out} -color Orange -radix hexadecimal /TX_TOP_tb/TD_P
add wave -noupdate -group {Serial out} -color Orange /TX_TOP_tb/TVLD_P
add wave -noupdate -group {Serial out} /TX_TOP_tb/dut/gen_data_ser[0]/u_data_ser/Ser_en
add wave -noupdate -group {Serial out} -radix hexadecimal /TX_TOP_tb/dut/gen_data_ser[0]/u_data_ser/in_data
add wave -noupdate -group {Serial out} /TX_TOP_tb/dut/u_valid_ser/Ser_en
add wave -noupdate -group {Serial out} -radix hexadecimal /TX_TOP_tb/dut/u_valid_ser/in_data

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 280
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
WaveRestoreZoom {0 ps} {2000 ns}
