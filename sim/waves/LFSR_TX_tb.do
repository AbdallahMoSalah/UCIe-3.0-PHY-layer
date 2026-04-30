onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /LFSR_TX_tb/dut/i_clk
add wave -noupdate /LFSR_TX_tb/dut/i_rst_n
add wave -noupdate /LFSR_TX_tb/dut/i_state
add wave -noupdate /LFSR_TX_tb/dut/current_state
add wave -noupdate /LFSR_TX_tb/dut/i_state_reg
add wave -noupdate /LFSR_TX_tb/dut/i_state_changed
add wave -noupdate /LFSR_TX_tb/dut/i_active_state_entered
add wave -noupdate /LFSR_TX_tb/dut/i_scramble_en
add wave -noupdate /LFSR_TX_tb/dut/i_width_deg_lfsr
add wave -noupdate /LFSR_TX_tb/dut/i_reversal_en
add wave -noupdate /LFSR_TX_tb/dut/i_lane
add wave -noupdate /LFSR_TX_tb/dut/o_lane
add wave -noupdate /LFSR_TX_tb/dut/o_Lfsr_tx_done
add wave -noupdate /LFSR_TX_tb/dut/o_valid_frame_en
add wave -noupdate /LFSR_TX_tb/dut/SEED
add wave -noupdate -radix unsigned /LFSR_TX_tb/dut/counter_lfsr
add wave -noupdate -radix unsigned /LFSR_TX_tb/dut/counter_per_lane
add wave -noupdate /LFSR_TX_tb/dut/lane_reversal_enabled
add wave -noupdate /LFSR_TX_tb/dut/tx_lfsr
add wave -noupdate /LFSR_TX_tb/dut/o_lane_23
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
quietly wave cursor active 0
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
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {1 us}
