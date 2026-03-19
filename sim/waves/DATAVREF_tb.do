onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /DATAVREF_tb/rst_n
add wave -noupdate /DATAVREF_tb/ltsm_tb_attachments_inst/sb_clk
add wave -noupdate /DATAVREF_tb/lclk
add wave -noupdate -radix unsigned /DATAVREF_tb/intf/datavref_en
add wave -noupdate -color Magenta -itemcolor Magenta /DATAVREF_tb/current_state
add wave -noupdate -expand -group {SB signals} /DATAVREF_tb/DATAVREF_inst/d2c_if/rx_pt_en
add wave -noupdate -expand -group {SB signals} /DATAVREF_tb/DATAVREF_inst/d2c_if/tx_pt_en
add wave -noupdate -expand -group {SB signals} /DATAVREF_tb/ltsm_tb_attachments_inst/tx_sb_msg_valid_pulse
add wave -noupdate -expand -group {SB signals} -color Magenta -itemcolor Magenta /DATAVREF_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB signals} -color Cyan -itemcolor Cyan /DATAVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/tx_sb_msg
add wave -noupdate -expand -group {SB signals} -color Cyan -itemcolor Cyan /DATAVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg
add wave -noupdate -expand -group {SB signals} -color Cyan -itemcolor Cyan /DATAVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg_valid
add wave -noupdate -expand -group {Global Vref Sweeping} -color Yellow -itemcolor Yellow -radix unsigned /DATAVREF_tb/DATAVREF_inst/current_vref_code
add wave -noupdate -expand -group {Global Vref Sweeping} -color {Medium Blue} -itemcolor {Medium Blue} -radix binary /DATAVREF_tb/intf/tb_perlane_err
add wave -noupdate -expand -group {Global Vref Sweeping} -color Gold -itemcolor Gold -radix unsigned /DATAVREF_tb/DATAVREF_inst/vref_range
add wave -noupdate -expand -group {Global Vref Sweeping} -color Cyan -itemcolor Cyan -radix unsigned /DATAVREF_tb/DATAVREF_inst/min_vref_code
add wave -noupdate -expand -group {Global Vref Sweeping} -color Gold -itemcolor Gold -radix unsigned /DATAVREF_tb/DATAVREF_inst/max_vref_code
add wave -noupdate -expand -group {Global Vref Sweeping} -color Green -itemcolor Green -radix unsigned /DATAVREF_tb/DATAVREF_inst/best_vref_code
add wave -noupdate -expand -group {Global Vref Sweeping} -color Orange -itemcolor Orange -radix unsigned /DATAVREF_tb/intf/phy_rx_datavref_ctrl
add wave -noupdate -expand -group {Global Vref Sweeping} -radix binary /DATAVREF_tb/DATAVREF_inst/vref_code_filled
add wave -noupdate -expand -group {Lane 0 Detailed Analysis} -color Yellow -itemcolor Gold -radix binary {/DATAVREF_tb/intf/tb_perlane_err[0]}
add wave -noupdate -expand -group {Lane 0 Detailed Analysis} -radix binary {/DATAVREF_tb/DATAVREF_inst/is_in_valid_region[0]}
add wave -noupdate -expand -group {Lane 0 Detailed Analysis} -color Cyan -itemcolor Cyan -radix unsigned {/DATAVREF_tb/DATAVREF_inst/min_vref_code[0]}
add wave -noupdate -expand -group {Lane 0 Detailed Analysis} -color Gold -itemcolor Gold -radix unsigned {/DATAVREF_tb/DATAVREF_inst/max_vref_code[0]}
add wave -noupdate -expand -group {Lane 0 Detailed Analysis} -color Green -itemcolor Green -radix unsigned {/DATAVREF_tb/DATAVREF_inst/best_vref_code[0]}
add wave -noupdate -expand -group {Lane 0 Detailed Analysis} -color Orange -itemcolor Orange -radix unsigned {/DATAVREF_tb/intf/phy_rx_datavref_ctrl[0]}
add wave -noupdate -expand -group {Final Result} /DATAVREF_tb/intf/datavref_done
add wave -noupdate -expand -group {Final Result} /DATAVREF_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Final Result} /DATAVREF_tb/intf/trainerror_req
add wave -noupdate -expand -group {Final Result} /DATAVREF_tb/intf/datavref_fail_flag
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {12994628374 ps} 0}
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
WaveRestoreZoom {12994166500 ps} {12996166500 ps}
