onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {System Signals}
add wave -noupdate /MBINIT_REPAIRMB_tb/clk
add wave -noupdate /MBINIT_REPAIRMB_tb/rst_n

add wave -noupdate -divider {Enables & Done}
add wave -noupdate /MBINIT_REPAIRMB_tb/m_enable
add wave -noupdate /MBINIT_REPAIRMB_tb/m_done
add wave -noupdate /MBINIT_REPAIRMB_tb/p_enable
add wave -noupdate /MBINIT_REPAIRMB_tb/p_done

add wave -noupdate -divider {Master State}
add wave -noupdate -radix unsigned /MBINIT_REPAIRMB_tb/master/current_state
add wave -noupdate -radix unsigned /MBINIT_REPAIRMB_tb/master/next_state
add wave -noupdate /MBINIT_REPAIRMB_tb/master/mb_repairmb_error
add wave -noupdate /MBINIT_REPAIRMB_tb/master/timeout_error

add wave -noupdate -divider {Partner State}
add wave -noupdate -radix unsigned /MBINIT_REPAIRMB_tb/partner/current_state
add wave -noupdate -radix unsigned /MBINIT_REPAIRMB_tb/partner/next_state
add wave -noupdate /MBINIT_REPAIRMB_tb/partner/mb_repairmb_error
add wave -noupdate /MBINIT_REPAIRMB_tb/partner/timeout_error

add wave -noupdate -divider {Master RX/TX}
add wave -noupdate /MBINIT_REPAIRMB_tb/m_rx_valid
add wave -noupdate /MBINIT_REPAIRMB_tb/m_rx_msg_id
add wave -noupdate /MBINIT_REPAIRMB_tb/m_tx_valid
add wave -noupdate /MBINIT_REPAIRMB_tb/m_tx_msg_id

add wave -noupdate -divider {Partner RX/TX}
add wave -noupdate /MBINIT_REPAIRMB_tb/p_rx_valid
add wave -noupdate /MBINIT_REPAIRMB_tb/p_rx_msg_id
add wave -noupdate /MBINIT_REPAIRMB_tb/p_tx_valid
add wave -noupdate /MBINIT_REPAIRMB_tb/p_tx_msg_id

add wave -noupdate -divider {D2C Interface}
add wave -noupdate /MBINIT_REPAIRMB_tb/d2c_if_master/tx_pt_en
add wave -noupdate /MBINIT_REPAIRMB_tb/d2c_if_master/test_d2c_done
add wave -noupdate -radix hexadecimal /MBINIT_REPAIRMB_tb/d2c_if_master/d2c_perlane_err

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
configure wave -namecolwidth 350
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
WaveRestoreZoom {0 ns} {1000 ns}
