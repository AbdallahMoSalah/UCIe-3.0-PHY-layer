onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {SM top module interface}
add wave -noupdate -divider {SM input}
add wave -noupdate /wrapper_sm_tb/dut/lclk
add wave -noupdate /wrapper_sm_tb/dut/rst_n
add wave -noupdate /wrapper_sm_tb/dut/state_sts
add wave -noupdate /wrapper_sm_tb/dut/pl_error
add wave -noupdate /wrapper_sm_tb/dut/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/message_receive
add wave -noupdate /wrapper_sm_tb/dut/Active_handshake_done
add wave -noupdate /wrapper_sm_tb/dut/stall_done
add wave -noupdate -divider {SM output}
add wave -noupdate -color coral -itemcolor coral /wrapper_sm_tb/dut/stall_req
add wave -noupdate -color coral -itemcolor coral /wrapper_sm_tb/dut/Active_handshake_strt
add wave -noupdate -color coral -itemcolor coral /wrapper_sm_tb/dut/message_send
add wave -noupdate -color coral -itemcolor coral /wrapper_sm_tb/dut/trainerror
add wave -noupdate -color coral -itemcolor coral /wrapper_sm_tb/dut/phyinrecenter
add wave -noupdate -color coral -itemcolor coral /wrapper_sm_tb/dut/pm_exit
add wave -noupdate -color coral -itemcolor coral /wrapper_sm_tb/dut/inband_pres
add wave -noupdate -color coral -itemcolor coral /wrapper_sm_tb/dut/rdi_state_sts
add wave -noupdate -divider {main controller interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Reset_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/LinkError_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Disable_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/LinkReset_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Active_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/L1_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/L2_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Retrain_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Active_PMNAK_next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/state_sts
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Active_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/L1_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/L2_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Retrain_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Active_PMNAK_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/LinkReset_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Disable_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/Reset_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/LinkError_EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/trainerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/phyinrecenter
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/inband_pres
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/pm_exit
add wave -noupdate /wrapper_sm_tb/dut/u_unit_main_controller/rdi_state_sts
add wave -noupdate -divider {Timer interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_Timer/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_Timer/start_time_16ms
add wave -noupdate /wrapper_sm_tb/dut/u_unit_Timer/start_time_1us
add wave -noupdate /wrapper_sm_tb/dut/u_unit_Timer/time_16ms
add wave -noupdate /wrapper_sm_tb/dut/u_unit_Timer/time_1us
add wave -noupdate /wrapper_sm_tb/dut/u_unit_Timer/counter_16ms
add wave -noupdate /wrapper_sm_tb/dut/u_unit_Timer/counter_1us
add wave -noupdate -divider {Reset state interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/Active_handshake_done
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/state_sts
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/message_receive
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/Active_handshake_strt
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/cs
add wave -noupdate /wrapper_sm_tb/dut/u_unit_reset_state/cs_reg
add wave -noupdate -divider {Active state interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/lclk
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/message_receive
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/stall_done
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/timeout_1us
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/pl_error
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/stall_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/start_1us_timer
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/cs
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_state/flow
add wave -noupdate -divider {Active.PMNAK state interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/lclk
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/message_receive
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/stall_done
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/stall_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/cs
add wave -noupdate /wrapper_sm_tb/dut/u_unit_active_pmnak_state/flow
add wave -noupdate -divider {Retrain state interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/lclk
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/message_receive
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/Active_handshake_done
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/state_sts
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/Active_handshake_strt
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_retrain_state/cs
add wave -noupdate -divider {L1 state interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/lclk
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/message_receive
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/Active_handshake_done
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/active_handshake_strt
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L1_state/cs
add wave -noupdate -divider {L2 state interafce}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/lclk
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/message_receive
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/Active_handshake_done
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/active_handshake_strt
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_L2_state/cs
add wave -noupdate -divider {LinkReset state interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/lclk
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/message_receive
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkreset_state/cs
add wave -noupdate -divider {LinkError state interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/lclk
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/time_16ms
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/start_timer_16ms
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_linkerror_state/cs
add wave -noupdate -divider Disabled
add wave -noupdate /wrapper_sm_tb/dut/u_unit_disabled_state/lclk
add wave -noupdate /wrapper_sm_tb/dut/u_unit_disabled_state/EN
add wave -noupdate /wrapper_sm_tb/dut/u_unit_disabled_state/lp_linkerror
add wave -noupdate /wrapper_sm_tb/dut/u_unit_disabled_state/lp_state_req
add wave -noupdate /wrapper_sm_tb/dut/u_unit_disabled_state/rst_n
add wave -noupdate /wrapper_sm_tb/dut/u_unit_disabled_state/next_state
add wave -noupdate /wrapper_sm_tb/dut/u_unit_disabled_state/cs
add wave -noupdate -divider {MUX interface}
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/Reset_message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/Retrain_message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/Active_message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/Active_PMNAK_message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/L1_message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/L2_message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/LinkReset_message_send
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/rdi_state_sts
add wave -noupdate /wrapper_sm_tb/dut/u_unit_message_send_MUX/message_send
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {92847825 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 243
configure wave -valuecolwidth 179
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
WaveRestoreZoom {0 ps} {1339228949 ps}
