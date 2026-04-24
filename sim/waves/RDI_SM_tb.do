onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider -height 50 RDI_SM_Interface
add wave -noupdate /RDI_SM_tb/dut/lclk
add wave -noupdate /RDI_SM_tb/dut/rst_n
add wave -noupdate /RDI_SM_tb/dut/lp_clk_ack
add wave -noupdate /RDI_SM_tb/dut/lp_awak_req
add wave -noupdate /RDI_SM_tb/dut/lp_stallack
add wave -noupdate /RDI_SM_tb/dut/lp_state_req
add wave -noupdate /RDI_SM_tb/dut/lp_linkerror
add wave -noupdate /RDI_SM_tb/dut/pl_clk_req
add wave -noupdate /RDI_SM_tb/dut/pl_stallreq
add wave -noupdate /RDI_SM_tb/dut/pl_awak_ack
add wave -noupdate /RDI_SM_tb/dut/pl_trainerror
add wave -noupdate /RDI_SM_tb/dut/pl_inband_pres
add wave -noupdate /RDI_SM_tb/dut/pl_phyinrecenter
add wave -noupdate /RDI_SM_tb/dut/pl_state_sts
add wave -noupdate /RDI_SM_tb/dut/pl_max_speedmode
add wave -noupdate /RDI_SM_tb/dut/pl_speedmode
add wave -noupdate /RDI_SM_tb/dut/pl_lnk_cfg
add wave -noupdate /RDI_SM_tb/dut/UCIe_Link_DVSEC_UCIe_Link_Capability_7to4
add wave -noupdate /RDI_SM_tb/dut/UCIe_Link_DVSEC_UCIe_Link_Status_17to11
add wave -noupdate /RDI_SM_tb/dut/UCIe_Link_DVSEC_UCIe_Link_Status_10to7
add wave -noupdate /RDI_SM_tb/dut/Link_Mgmt_Msg_Receive
add wave -noupdate /RDI_SM_tb/dut/valid_r
add wave -noupdate /RDI_SM_tb/dut/Link_Mgmt_Msg_Send
add wave -noupdate /RDI_SM_tb/dut/valid_s
add wave -noupdate /RDI_SM_tb/dut/traffic_req
add wave -noupdate /RDI_SM_tb/dut/clk_handshake_done
add wave -noupdate /RDI_SM_tb/dut/lclk_g
add wave -noupdate /RDI_SM_tb/dut/stall_done
add wave -noupdate /RDI_SM_tb/dut/pl_error
add wave -noupdate /RDI_SM_tb/dut/state_sts
add wave -noupdate -divider -height 50 SM_Interface
add wave -noupdate /RDI_SM_tb/dut/sm/lclk
add wave -noupdate /RDI_SM_tb/dut/sm/rst_n
add wave -noupdate /RDI_SM_tb/dut/sm/state_sts
add wave -noupdate /RDI_SM_tb/dut/sm/pl_error
add wave -noupdate /RDI_SM_tb/dut/sm/lp_linkerror
add wave -noupdate /RDI_SM_tb/dut/sm/lp_state_req
add wave -noupdate /RDI_SM_tb/dut/sm/message_receive
add wave -noupdate /RDI_SM_tb/dut/sm/Active_handshake_done
add wave -noupdate /RDI_SM_tb/dut/sm/stall_done
add wave -noupdate /RDI_SM_tb/dut/sm/stall_req
add wave -noupdate /RDI_SM_tb/dut/sm/Active_handshake_strt
add wave -noupdate /RDI_SM_tb/dut/sm/message_send
add wave -noupdate /RDI_SM_tb/dut/sm/trainerror
add wave -noupdate /RDI_SM_tb/dut/sm/phyinrecenter
add wave -noupdate /RDI_SM_tb/dut/sm/pm_exit
add wave -noupdate /RDI_SM_tb/dut/sm/inband_pres
add wave -noupdate /RDI_SM_tb/dut/sm/rdi_state_sts
add wave -noupdate -divider -height 50 Handshake_logic_Interface
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/lclk
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/rst_n
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/lp_awak_req
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/ungating_done
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/pl_awak_ack
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/ungating_req
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/lp_stallack
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/stall_req
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/pl_stallreq
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/stall_done
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/Active_handshake_strt
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/message_receive
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/pm_exit
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/inband_pres
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/Active_handshake_done
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/Active_message_send
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/clk_handshake_strt
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/lp_clk_ack
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/pl_clk_req
add wave -noupdate /RDI_SM_tb/dut/handshake_logic/clk_handshake_done
add wave -noupdate -divider -height 50 Gating_logic_Interface
add wave -noupdate /RDI_SM_tb/dut/gating_logic/lclk
add wave -noupdate /RDI_SM_tb/dut/gating_logic/rst_n
add wave -noupdate /RDI_SM_tb/dut/gating_logic/pl_phyinrecenter
add wave -noupdate /RDI_SM_tb/dut/gating_logic/pl_clk_req
add wave -noupdate /RDI_SM_tb/dut/gating_logic/ungating_req
add wave -noupdate /RDI_SM_tb/dut/gating_logic/pl_state_sts
add wave -noupdate /RDI_SM_tb/dut/gating_logic/lclk_g
add wave -noupdate /RDI_SM_tb/dut/gating_logic/ungating_done
add wave -noupdate /RDI_SM_tb/dut/gating_logic/GATING_cs
add wave -noupdate -divider -height 50 Signal_transition_detector_interface
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/lclk
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/rst_n
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/phyinrecenter
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/inband_pres
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/trainerror
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/clk_handshake_done
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/rdi_state_sts
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/pl_phyinrecenter
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/pl_inband_pres
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/pl_trainerror
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/signal_transition
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/pl_state_sts
add wave -noupdate /RDI_SM_tb/dut/signal_transition_detector/cs
add wave -noupdate -divider -height 50 Status_decoder_Interface
add wave -noupdate /RDI_SM_tb/dut/status_decoder/UCIe_Link_DVSEC_UCIe_Link_Capability_7_downto_4
add wave -noupdate /RDI_SM_tb/dut/status_decoder/UCIe_Link_DVSEC_UCIe_Link_Status_10_downto_7
add wave -noupdate /RDI_SM_tb/dut/status_decoder/UCIe_Link_DVSEC_UCIe_Link_Status_17_downto_11
add wave -noupdate /RDI_SM_tb/dut/status_decoder/pl_lnk_cfg
add wave -noupdate /RDI_SM_tb/dut/status_decoder/pl_speedmode
add wave -noupdate /RDI_SM_tb/dut/status_decoder/pl_max_speedmode
add wave -noupdate -divider -height 50 Msg_Handler_Interface
add wave -noupdate /RDI_SM_tb/dut/msg_handler/lclk
add wave -noupdate /RDI_SM_tb/dut/msg_handler/rst_n
add wave -noupdate /RDI_SM_tb/dut/msg_handler/Active_message_send
add wave -noupdate /RDI_SM_tb/dut/msg_handler/Message_send
add wave -noupdate /RDI_SM_tb/dut/msg_handler/valid_r
add wave -noupdate /RDI_SM_tb/dut/msg_handler/Link_Mgmt_Msg_Received
add wave -noupdate /RDI_SM_tb/dut/msg_handler/valid_s
add wave -noupdate /RDI_SM_tb/dut/msg_handler/Link_Mgmt_Msg_Send
add wave -noupdate /RDI_SM_tb/dut/msg_handler/Message_receive
add wave -noupdate /RDI_SM_tb/dut/msg_handler/cs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {10759 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 324
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
WaveRestoreZoom {0 ps} {40501 ps}
