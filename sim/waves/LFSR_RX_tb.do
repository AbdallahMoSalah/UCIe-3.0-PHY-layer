onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /LFSR_RX_tb/dut/i_clk
add wave -noupdate /LFSR_RX_tb/dut/i_rst_n
add wave -noupdate /LFSR_RX_tb/dut/i_state
add wave -noupdate /LFSR_RX_tb/dut/current_state
add wave -noupdate /LFSR_RX_tb/dut/i_state_reg
add wave -noupdate /LFSR_RX_tb/dut/i_state_changed
add wave -noupdate /LFSR_RX_tb/dut/i_width_deg_lfsr
add wave -noupdate /LFSR_RX_tb/dut/i_active_state_entered
add wave -noupdate /LFSR_RX_tb/dut/i_enable_buffer
add wave -noupdate /LFSR_RX_tb/dut/i_descramble_en
add wave -noupdate /LFSR_RX_tb/dut/i_data_in
add wave -noupdate /LFSR_RX_tb/dut/o_Data_by
add wave -noupdate /LFSR_RX_tb/dut/o_final_gene
add wave -noupdate /LFSR_RX_tb/dut/pattern_comp_en
add wave -noupdate /LFSR_RX_tb/dut/rx_lfsr_lane
add wave -noupdate /LFSR_RX_tb/dut/o_lane_23
add wave -noupdate /LFSR_RX_tb/dut/temp_Data_by
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
