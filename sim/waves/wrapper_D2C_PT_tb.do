onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /wrapper_D2C_PT_tb/lclk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /wrapper_D2C_PT_tb/sb_clk
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /wrapper_D2C_PT_tb/rst_n
add wave -noupdate -expand -group {FSM States} -color Magenta /wrapper_D2C_PT_tb/tx_state_monitor
add wave -noupdate -expand -group {FSM States} -color Magenta /wrapper_D2C_PT_tb/rx_state_monitor
add wave -noupdate -expand -group {FSM States} -color Magenta /wrapper_D2C_PT_tb/intf_mux/current_ltsm_state
add wave -noupdate -expand -group {D2C MBINIT} -color Gold /wrapper_D2C_PT_tb/intf_mbinit/tx_pt_en
add wave -noupdate -expand -group {D2C MBINIT} -color Gold /wrapper_D2C_PT_tb/intf_mbinit/rx_pt_en
add wave -noupdate -expand -group {D2C MBINIT} -color Gold /wrapper_D2C_PT_tb/intf_mbinit/test_d2c_done
add wave -noupdate -expand -group {D2C MBTRAIN} -color Gold /wrapper_D2C_PT_tb/intf_mbtrain/tx_pt_en
add wave -noupdate -expand -group {D2C MBTRAIN} -color Gold /wrapper_D2C_PT_tb/intf_mbtrain/rx_pt_en
add wave -noupdate -expand -group {D2C MBTRAIN} -color Gold /wrapper_D2C_PT_tb/intf_mbtrain/test_d2c_done
add wave -noupdate -expand -group {D2C Results (MUX)} -color Orange -radix hexadecimal /wrapper_D2C_PT_tb/intf_mux/d2c_perlane_err
add wave -noupdate -expand -group {D2C Results (MUX)} -color Orange -radix hexadecimal /wrapper_D2C_PT_tb/intf_mux/d2c_aggr_err
add wave -noupdate -expand -group {D2C Results (MUX)} -color Orange /wrapper_D2C_PT_tb/intf_mux/d2c_val_err
add wave -noupdate -expand -group {SB Tx} -color Cyan /wrapper_D2C_PT_tb/intf_mux/tx_sb_msg_valid
add wave -noupdate -expand -group {SB Tx} -color Cyan /wrapper_D2C_PT_tb/intf_mux/tx_sb_msg
add wave -noupdate -expand -group {SB Tx} -color Cyan -radix hexadecimal /wrapper_D2C_PT_tb/intf_mux/tx_msginfo
add wave -noupdate -expand -group {SB Tx} -color Cyan -radix hexadecimal /wrapper_D2C_PT_tb/intf_mux/tx_data_field
add wave -noupdate -expand -group {SB Rx} -color {Cornflower Blue} /wrapper_D2C_PT_tb/intf_mux/rx_sb_msg_valid
add wave -noupdate -expand -group {SB Rx} -color {Cornflower Blue} /wrapper_D2C_PT_tb/intf_mux/rx_sb_msg
add wave -noupdate -expand -group {SB Rx} -color {Cornflower Blue} -radix hexadecimal /wrapper_D2C_PT_tb/intf_mux/rx_msginfo
add wave -noupdate -expand -group {SB Rx} -color {Cornflower Blue} -radix hexadecimal /wrapper_D2C_PT_tb/intf_mux/rx_data_field
add wave -noupdate -expand -group {MB Pattern} -color Pink /wrapper_D2C_PT_tb/intf_mux/mb_tx_pattern_en
add wave -noupdate -expand -group {MB Pattern} -color Pink /wrapper_D2C_PT_tb/intf_mux/mb_tx_pattern_setup
add wave -noupdate -expand -group {MB Pattern} -color Pink /wrapper_D2C_PT_tb/intf_mux/mb_tx_pattern_mode
add wave -noupdate -expand -group {MB Pattern} -color Pink /wrapper_D2C_PT_tb/intf_mux/mb_tx_pattern_count_done
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} /wrapper_D2C_PT_tb/intf_mux/mb_rx_compare_en
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} /wrapper_D2C_PT_tb/intf_mux/mb_rx_compare_setup
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} /wrapper_D2C_PT_tb/intf_mux/mb_rx_compare_done
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} /wrapper_D2C_PT_tb/intf_mux/mb_tx_clk_sampling_en
add wave -noupdate -expand -group {MB Compare} -color {Indian Red} -radix unsigned /wrapper_D2C_PT_tb/intf_mux/mb_tx_clk_sampling
add wave -noupdate -expand -group {MB Rx Errors} -color {Spring Green} -radix hexadecimal /wrapper_D2C_PT_tb/intf_mux/mb_rx_perlane_err
add wave -noupdate -expand -group {MB Rx Errors} -color {Spring Green} -radix hexadecimal /wrapper_D2C_PT_tb/intf_mux/mb_rx_aggr_err
add wave -noupdate -expand -group {MB Rx Errors} -color {Spring Green} /wrapper_D2C_PT_tb/intf_mux/mb_rx_val_err
add wave -noupdate -expand -group Counters -color Khaki -radix unsigned /wrapper_D2C_PT_tb/success_count
add wave -noupdate -expand -group Counters -color Khaki -radix unsigned /wrapper_D2C_PT_tb/fail_count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1106040 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 350
configure wave -valuecolwidth 200
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
WaveRestoreZoom {0 ps} {4 us}
