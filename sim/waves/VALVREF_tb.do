onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /VALVREF_tb/rst_n
add wave -noupdate /VALVREF_tb/ltsm_tb_attachments_inst/sb_clk
add wave -noupdate /VALVREF_tb/lclk
add wave -noupdate -radix unsigned /VALVREF_tb/intf/valvref_en
add wave -noupdate -color Magenta -itemcolor Magenta /VALVREF_tb/current_state
add wave -noupdate -expand -group {SB signals} /VALVREF_tb/VALVREF_inst/d2c_if/rx_pt_en
add wave -noupdate -expand -group {SB signals} /VALVREF_tb/VALVREF_inst/d2c_if/tx_pt_en
add wave -noupdate -expand -group {SB signals} /VALVREF_tb/ltsm_tb_attachments_inst/tx_sb_msg_valid_pulse
add wave -noupdate -expand -group {SB signals} -color Magenta -itemcolor Magenta /VALVREF_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB signals} -color Cyan -itemcolor Cyan /VALVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/tx_sb_msg
add wave -noupdate -expand -group {SB signals} -color Cyan -itemcolor Cyan /VALVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg
add wave -noupdate -expand -group {SB signals} -color Cyan -itemcolor Cyan /VALVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/rx_sb_msg_valid
add wave -noupdate -expand -group {Vref Calculation} /VALVREF_tb/intf/tb_val_err
add wave -noupdate -expand -group {Vref Calculation} -color {Light Blue} -itemcolor Aquamarine -radix unsigned /VALVREF_tb/intf/phy_rx_valvref_ctrl
add wave -noupdate -expand -group {Vref Calculation} /VALVREF_tb/VALVREF_inst/vref_code_filled
add wave -noupdate -expand -group {Vref Calculation} -color Gold -itemcolor Gold -radix unsigned -childformat {{{/VALVREF_tb/VALVREF_inst/vref_range[6]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/vref_range[5]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/vref_range[4]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/vref_range[3]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/vref_range[2]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/vref_range[1]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/vref_range[0]} -radix unsigned}} -subitemconfig {{/VALVREF_tb/VALVREF_inst/vref_range[6]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/vref_range[5]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/vref_range[4]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/vref_range[3]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/vref_range[2]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/vref_range[1]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/vref_range[0]} {-color Gold -height 15 -itemcolor Gold -radix unsigned}} /VALVREF_tb/VALVREF_inst/vref_range
add wave -noupdate -expand -group {Vref Calculation} -color Cyan -itemcolor Cyan -radix unsigned -childformat {{{/VALVREF_tb/VALVREF_inst/min_vref_code[6]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/min_vref_code[5]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/min_vref_code[4]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/min_vref_code[3]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/min_vref_code[2]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/min_vref_code[1]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/min_vref_code[0]} -radix unsigned}} -subitemconfig {{/VALVREF_tb/VALVREF_inst/min_vref_code[6]} {-color Cyan -height 15 -itemcolor Cyan -radix unsigned} {/VALVREF_tb/VALVREF_inst/min_vref_code[5]} {-color Cyan -height 15 -itemcolor Cyan -radix unsigned} {/VALVREF_tb/VALVREF_inst/min_vref_code[4]} {-color Cyan -height 15 -itemcolor Cyan -radix unsigned} {/VALVREF_tb/VALVREF_inst/min_vref_code[3]} {-color Cyan -height 15 -itemcolor Cyan -radix unsigned} {/VALVREF_tb/VALVREF_inst/min_vref_code[2]} {-color Cyan -height 15 -itemcolor Cyan -radix unsigned} {/VALVREF_tb/VALVREF_inst/min_vref_code[1]} {-color Cyan -height 15 -itemcolor Cyan -radix unsigned} {/VALVREF_tb/VALVREF_inst/min_vref_code[0]} {-color Cyan -height 15 -itemcolor Cyan -radix unsigned}} /VALVREF_tb/VALVREF_inst/min_vref_code
add wave -noupdate -expand -group {Vref Calculation} -color Gold -itemcolor Gold -radix unsigned -childformat {{{/VALVREF_tb/VALVREF_inst/max_vref_code[6]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/max_vref_code[5]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/max_vref_code[4]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/max_vref_code[3]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/max_vref_code[2]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/max_vref_code[1]} -radix unsigned} {{/VALVREF_tb/VALVREF_inst/max_vref_code[0]} -radix unsigned}} -subitemconfig {{/VALVREF_tb/VALVREF_inst/max_vref_code[6]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/max_vref_code[5]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/max_vref_code[4]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/max_vref_code[3]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/max_vref_code[2]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/max_vref_code[1]} {-color Gold -height 15 -itemcolor Gold -radix unsigned} {/VALVREF_tb/VALVREF_inst/max_vref_code[0]} {-color Gold -height 15 -itemcolor Gold -radix unsigned}} /VALVREF_tb/VALVREF_inst/max_vref_code
add wave -noupdate -expand -group {Final Result} /VALVREF_tb/intf/valvref_done
add wave -noupdate -expand -group {Final Result} /VALVREF_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Final Result} /VALVREF_tb/intf/trainerror_req
add wave -noupdate -expand -group {Final Result} /VALVREF_tb/intf/valvref_fail_flag
add wave -noupdate -color Gold -itemcolor Gold -radix unsigned /VALVREF_tb/VALVREF_inst/max_vref_code
add wave -noupdate -color Gold -itemcolor Gold -radix unsigned /VALVREF_tb/VALVREF_inst/min_vref_code
add wave -noupdate -color Gold -itemcolor Gold -radix unsigned /VALVREF_tb/VALVREF_inst/vref_range
add wave -noupdate /VALVREF_tb/ltsm_tb_attachments_inst/d2c_mux_out_if/tx_sb_msg_valid
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {188396463063 ps} 0} {{Cursor 2} {279552 ps} 0}
quietly wave cursor active 2
configure wave -namecolwidth 295
configure wave -valuecolwidth 197
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
WaveRestoreZoom {0 ps} {1992494 ps}
