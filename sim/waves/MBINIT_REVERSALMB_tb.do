onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {System Signals}
add wave -noupdate /MBINIT_REVERSALMB_tb/clk
add wave -noupdate /MBINIT_REVERSALMB_tb/rst_n
add wave -noupdate -color Gold /MBINIT_REVERSALMB_tb/mb_reversal_enable
add wave -noupdate -color Green /MBINIT_REVERSALMB_tb/mb_reversal_done
add wave -noupdate -color Red /MBINIT_REVERSALMB_tb/mb_reversal_error
add wave -noupdate -color Red /MBINIT_REVERSALMB_tb/timeout_error

add wave -noupdate -divider {State Machine (DUT)}
add wave -noupdate -color Blue /MBINIT_REVERSALMB_tb/dut/current_state
add wave -noupdate -color Blue /MBINIT_REVERSALMB_tb/dut/next_state
add wave -noupdate -color Orange /MBINIT_REVERSALMB_tb/dut/retry_done
add wave -noupdate -color Green /MBINIT_REVERSALMB_tb/dut/majority_success

add wave -noupdate -divider {RX Message Interface}
add wave -noupdate -color Cyan /MBINIT_REVERSALMB_tb/mb_rx_valid
add wave -noupdate -color Cyan /MBINIT_REVERSALMB_tb/mb_rx_msg_id
add wave -noupdate -radix hexadecimal -color Cyan /MBINIT_REVERSALMB_tb/mb_rx_MsgInfo
add wave -noupdate -radix hexadecimal -color Cyan /MBINIT_REVERSALMB_tb/mb_rx_data_Field

add wave -noupdate -divider {TX Message Interface}
add wave -noupdate -color Magenta /MBINIT_REVERSALMB_tb/mb_tx_valid
add wave -noupdate -color Magenta /MBINIT_REVERSALMB_tb/mb_tx_msg_id
add wave -noupdate -radix hexadecimal -color Magenta /MBINIT_REVERSALMB_tb/mb_tx_MsgInfo
add wave -noupdate -radix hexadecimal -color Magenta /MBINIT_REVERSALMB_tb/mb_tx_data_Field

add wave -noupdate -divider {Pattern Comparison}
add wave -noupdate -color Yellow /MBINIT_REVERSALMB_tb/mb_tx_pattern_en
add wave -noupdate -color Yellow /MBINIT_REVERSALMB_tb/mb_rx_compare_en
add wave -noupdate -color Green /MBINIT_REVERSALMB_tb/mb_rx_compare_done
add wave -noupdate -radix hexadecimal -color Red /MBINIT_REVERSALMB_tb/mb_rx_perlane_err

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 350
configure wave -valuecolwidth 150
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
WaveRestoreZoom {0 ps} {2000 ns}
