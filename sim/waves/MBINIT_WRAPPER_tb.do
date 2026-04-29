onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /MBINIT_WRAPPER_tb/clk
add wave -noupdate /MBINIT_WRAPPER_tb/rst_n

add wave -noupdate -divider {GLOBAL STATUS}
add wave -noupdate /MBINIT_WRAPPER_tb/m_enable
add wave -noupdate /MBINIT_WRAPPER_tb/m_done
add wave -noupdate /MBINIT_WRAPPER_tb/m_error
add wave -noupdate /MBINIT_WRAPPER_tb/p_enable
add wave -noupdate /MBINIT_WRAPPER_tb/p_done
add wave -noupdate /MBINIT_WRAPPER_tb/p_error

add wave -noupdate -divider {MASTER STATE}
add wave -noupdate -radix unsigned /MBINIT_WRAPPER_tb/master/u_controller/current_state
add wave -noupdate /MBINIT_WRAPPER_tb/master/u_controller/param_enable
add wave -noupdate /MBINIT_WRAPPER_tb/master/u_controller/cal_enable
add wave -noupdate /MBINIT_WRAPPER_tb/master/u_controller/repairclk_enable
add wave -noupdate /MBINIT_WRAPPER_tb/master/u_controller/repairval_enable
add wave -noupdate /MBINIT_WRAPPER_tb/master/u_controller/reversalmb_enable
add wave -noupdate /MBINIT_WRAPPER_tb/master/u_controller/repairmb_enable

add wave -noupdate -divider {PARTNER STATE}
add wave -noupdate -radix unsigned /MBINIT_WRAPPER_tb/partner/u_controller/current_state
add wave -noupdate /MBINIT_WRAPPER_tb/partner/u_controller/param_enable
add wave -noupdate /MBINIT_WRAPPER_tb/partner/u_controller/cal_enable
add wave -noupdate /MBINIT_WRAPPER_tb/partner/u_controller/repairclk_enable
add wave -noupdate /MBINIT_WRAPPER_tb/partner/u_controller/repairval_enable
add wave -noupdate /MBINIT_WRAPPER_tb/partner/u_controller/reversalmb_enable
add wave -noupdate /MBINIT_WRAPPER_tb/partner/u_controller/repairmb_enable

add wave -noupdate -divider {M TO P BUS}
add wave -noupdate /MBINIT_WRAPPER_tb/m_tx_valid
add wave -noupdate /MBINIT_WRAPPER_tb/m_tx_msg_id
add wave -noupdate -radix hex /MBINIT_WRAPPER_tb/m_tx_MsgInfo
add wave -noupdate -radix hex /MBINIT_WRAPPER_tb/m_tx_data

add wave -noupdate -divider {P TO M BUS}
add wave -noupdate /MBINIT_WRAPPER_tb/p_tx_valid
add wave -noupdate /MBINIT_WRAPPER_tb/p_tx_msg_id
add wave -noupdate -radix hex /MBINIT_WRAPPER_tb/p_tx_MsgInfo
add wave -noupdate -radix hex /MBINIT_WRAPPER_tb/p_tx_data

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 250
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
WaveRestoreZoom {0 ps} {1000 ns}
