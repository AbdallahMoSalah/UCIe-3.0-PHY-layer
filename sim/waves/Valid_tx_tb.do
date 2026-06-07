onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_tx_top_tb/dut/i_rst_n
add wave -noupdate /unit_tx_top_tb/dut/lp_data
add wave -noupdate /unit_tx_top_tb/dut/lp_irdy
add wave -noupdate /unit_tx_top_tb/dut/lp_valid
add wave -noupdate /unit_tx_top_tb/dut/pl_trdy
add wave -noupdate /unit_tx_top_tb/dut/i_mapper_en
add wave -noupdate /unit_tx_top_tb/dut/i_width_deg
add wave -noupdate /unit_tx_top_tb/dut/i_lfsr_state
add wave -noupdate /unit_tx_top_tb/dut/i_reversal_en
add wave -noupdate /unit_tx_top_tb/dut/i_valid_pattern_en
add wave -noupdate /unit_tx_top_tb/dut/i_pll_en
add wave -noupdate /unit_tx_top_tb/dut/i_pll_speed_sel
add wave -noupdate /unit_tx_top_tb/dut/lclk_g
add wave -noupdate /unit_tx_top_tb/dut/i_clk_pattern_en
add wave -noupdate /unit_tx_top_tb/dut/i_clk_embedded_en
add wave -noupdate /unit_tx_top_tb/dut/lclk
add wave -noupdate /unit_tx_top_tb/dut/TD_P
add wave -noupdate /unit_tx_top_tb/dut/TVLD_P
add wave -noupdate /unit_tx_top_tb/dut/TCKP_P
add wave -noupdate /unit_tx_top_tb/dut/TCKN_P
add wave -noupdate /unit_tx_top_tb/dut/TTRK_P
add wave -noupdate /unit_tx_top_tb/dut/o_lfsr_tx_done
add wave -noupdate /unit_tx_top_tb/dut/o_valid_done
add wave -noupdate /unit_tx_top_tb/dut/o_clk_done
add wave -noupdate {/unit_tx_top_tb/dut/gen_data_ser[15]/u_data_ser/even_src}
add wave -noupdate {/unit_tx_top_tb/dut/gen_data_ser[15]/u_data_ser/odd_src}
add wave -noupdate {/unit_tx_top_tb/dut/gen_data_ser[15]/u_data_ser/even_q}
add wave -noupdate {/unit_tx_top_tb/dut/gen_data_ser[15]/u_data_ser/odd_q}
add wave -noupdate {/unit_tx_top_tb/dut/gen_data_ser[15]/u_data_ser/high_reg}
add wave -noupdate {/unit_tx_top_tb/dut/gen_data_ser[15]/u_data_ser/low_reg}
add wave -noupdate {/unit_tx_top_tb/dut/gen_data_ser[15]/u_data_ser/data_reg}
add wave -noupdate {/unit_tx_top_tb/dut/gen_data_ser[15]/u_data_ser/load_reg}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {2977964 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
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
WaveRestoreZoom {2972291 ps} {3008008 ps}
